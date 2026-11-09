###############################################################################
# terraform-k8s-monitoring-stack
#
# Installs kube-prometheus-stack (the community standard Helm chart) on any
# Kubernetes cluster, with:
#   * per-cloud defaults for EKS / AKS / GKE (storage, managed control plane)
#   * node & pod health alert rules (rules/*.yaml, unit-tested with promtool)
#   * a "Cluster health" Grafana dashboard (dashboards/*.json)
#   * Alertmanager routing to Slack and/or PagerDuty
#   * a random Grafana admin password kept in a Kubernetes Secret
#
# What each component does:
#   Prometheus          scrapes (pulls) metrics every 30s and evaluates alert rules
#   Alertmanager        groups, deduplicates and routes alerts to Slack / PagerDuty
#   Grafana             dashboards on top of Prometheus
#   node-exporter       one pod per node exposing CPU, memory, disk metrics
#   kube-state-metrics  turns Kubernetes object state (pods, nodes...) into metrics
#   Prometheus Operator watches ServiceMonitor / PrometheusRule objects and
#                       configures Prometheus automatically
###############################################################################

locals {
  # --- Per-cloud defaults ---------------------------------------------------
  # Managed control planes (EKS/AKS/GKE) hide the scheduler, controller-manager
  # and etcd from us. Leaving those scrape targets on would fire "...Down"
  # alerts forever, so they are switched off there.
  cloud_defaults = {
    eks     = { storage_class = "gp3", managed_control_plane = true, kube_dns = false }
    aks     = { storage_class = "managed-csi", managed_control_plane = true, kube_dns = false }
    gke     = { storage_class = "standard-rwo", managed_control_plane = true, kube_dns = true }
    generic = { storage_class = null, managed_control_plane = false, kube_dns = false }
  }
  cloud = local.cloud_defaults[var.cloud_provider]

  storage_class         = var.storage_class_name != null ? var.storage_class_name : local.cloud.storage_class
  managed_control_plane = local.cloud.managed_control_plane

  # GKE Autopilot does not allow hostNetwork/hostPID/hostPath, which node-exporter needs.
  node_exporter_enabled = !(var.cloud_provider == "gke" && var.gke_autopilot)

  create_gp3_class = var.cloud_provider == "eks" && var.create_eks_gp3_storage_class && var.storage_class_name == null

  grafana_admin_secret = "${var.release_name}-grafana-admin"

  # --- Alert rules ------------------------------------------------------------
  # Loaded through the chart (additionalPrometheusRulesMap) instead of a
  # Terraform kubernetes_manifest, so a fresh cluster works in ONE apply
  # (kubernetes_manifest needs the PrometheusRule CRD to exist at plan time).
  rule_files = merge(
    { "node-pod-health" = "${path.module}/rules/node-pod-health.rules.yaml" },
    { for f in var.additional_rule_files : trimsuffix(trimsuffix(basename(f), ".yaml"), ".rules") => f },
  )
  prometheus_rules = { for name, f in local.rule_files : name => yamldecode(file(f)) }

  # --- Dashboards --------------------------------------------------------------
  dashboard_files = merge(
    { "cluster-health" = "${path.module}/dashboards/cluster-health.json" },
    { for f in var.additional_dashboard_files : trimsuffix(basename(f), ".json") => f },
  )

  # --- Alertmanager --------------------------------------------------------------
  # `[for x in [..] : x if cond]` builds "a list with this item, or empty":
  # the plain `cond ? [obj] : []` fails in Terraform with "inconsistent types".
  slack_configs = [for c in [{
    api_url       = var.slack_webhook_url
    channel       = var.slack_channel
    send_resolved = true
    title         = "[{{ .Status | toUpper }}{{ if eq .Status \"firing\" }}:{{ .Alerts.Firing | len }}{{ end }}] {{ .CommonLabels.alertname }}"
    text          = "{{ range .Alerts }}*{{ .Annotations.summary }}*\n{{ .Annotations.description }}\nRunbook: {{ .Annotations.runbook_url }}\n\n{{ end }}"
  }] : c if var.slack_webhook_url != null]

  pagerduty_configs = [for c in [{
    routing_key   = var.pagerduty_routing_key
    send_resolved = true
    description   = "{{ .CommonAnnotations.summary }}"
  }] : c if var.pagerduty_routing_key != null]

  alertmanager_config = {
    global = { resolve_timeout = "5m" }

    route = {
      receiver        = "default"
      group_by        = ["alertname", "namespace", "severity"]
      group_wait      = "30s" # wait a little to batch alerts that fire together
      group_interval  = "5m"
      repeat_interval = "4h" # re-notify if still firing
      routes = [
        # Watchdog always fires on purpose (proves the pipeline works); InfoInhibitor is internal.
        { receiver = "null", matchers = ["alertname = \"Watchdog\""] },
        { receiver = "null", matchers = ["alertname = \"InfoInhibitor\""] },
        { receiver = "critical", matchers = ["severity = \"critical\""] },
      ]
    }

    # A critical alert silences the matching warning (e.g. "almost full" vs "full").
    inhibit_rules = [
      {
        source_matchers = ["severity = \"critical\""]
        target_matchers = ["severity = \"warning\""]
        equal           = ["alertname", "namespace", "instance"]
      },
      {
        source_matchers = ["alertname = \"InfoInhibitor\""]
        target_matchers = ["severity = \"info\""]
        equal           = ["namespace"]
      },
    ]

    receivers = [
      { name = "null" },
      { name = "default", slack_configs = local.slack_configs },
      { name = "critical", slack_configs = local.slack_configs, pagerduty_configs = local.pagerduty_configs },
    ]
  }

  # --- Helm values -----------------------------------------------------------------
  pvc_spec = {
    storageClassName = local.storage_class
    accessModes      = ["ReadWriteOnce"]
  }

  helm_values = {
    # Deterministic names: <release>-prometheus, <release>-alertmanager, ...
    fullnameOverride = var.release_name

    defaultRules = {
      create = var.enable_default_rules
      rules = {
        etcd                   = !local.managed_control_plane
        kubeControllerManager  = !local.managed_control_plane
        kubeSchedulerAlerting  = !local.managed_control_plane
        kubeSchedulerRecording = !local.managed_control_plane
        kubeProxy              = !local.managed_control_plane
        node                   = local.node_exporter_enabled
      }
    }

    additionalPrometheusRulesMap = local.prometheus_rules

    # Control-plane scrape targets that do not exist on managed clusters.
    kubeControllerManager = { enabled = !local.managed_control_plane }
    kubeScheduler         = { enabled = !local.managed_control_plane }
    kubeEtcd              = { enabled = !local.managed_control_plane }
    kubeProxy             = { enabled = !local.managed_control_plane }
    coreDns               = { enabled = !local.cloud.kube_dns }
    kubeDns               = { enabled = local.cloud.kube_dns }

    nodeExporter = { enabled = local.node_exporter_enabled }

    prometheus = {
      prometheusSpec = {
        replicas       = var.prometheus_replicas
        retention      = var.prometheus_retention
        retentionSize  = "${floor(tonumber(trimsuffix(var.prometheus_storage_size, "Gi")) * 0.9)}GB"
        resources      = var.prometheus_resources
        externalLabels = var.cluster_name == "" ? {} : { cluster = var.cluster_name }

        # Pick up ServiceMonitors, PodMonitors and rules from ANY namespace and
        # release, so application teams can add their own monitoring.
        ruleSelectorNilUsesHelmValues           = false
        serviceMonitorSelectorNilUsesHelmValues = false
        podMonitorSelectorNilUsesHelmValues     = false
        probeSelectorNilUsesHelmValues          = false

        storageSpec = {
          volumeClaimTemplate = {
            spec = merge(local.pvc_spec, { resources = { requests = { storage = var.prometheus_storage_size } } })
          }
        }
      }
    }

    alertmanager = {
      config = local.alertmanager_config
      alertmanagerSpec = {
        resources = {
          requests = { cpu = "50m", memory = "128Mi" }
          limits   = { memory = "256Mi" }
        }
        storage = {
          volumeClaimTemplate = {
            spec = merge(local.pvc_spec, { resources = { requests = { storage = var.alertmanager_storage_size } } })
          }
        }
      }
    }

    grafana = {
      # Credentials come from a Secret this module creates: no default admin/prom-operator password.
      admin = {
        existingSecret = local.grafana_admin_secret
        userKey        = "admin-user"
        passwordKey    = "admin-password"
      }
      persistence = {
        enabled          = true
        storageClassName = local.storage_class
        size             = var.grafana_storage_size
      }
      # A ReadWriteOnce volume can only be mounted by one pod: replace the old
      # pod first instead of rolling (which would deadlock on the volume).
      deploymentStrategy = { type = "Recreate" }
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { memory = "512Mi" }
      }
      defaultDashboardsTimezone = "utc"
      sidecar = {
        dashboards = {
          enabled         = true
          label           = "grafana_dashboard"
          labelValue      = "1"
          searchNamespace = "ALL" # teams can ship dashboards as ConfigMaps in their own namespace
        }
      }
      "grafana.ini" = {
        analytics        = { check_for_updates = false, reporting_enabled = false }
        users            = { allow_sign_up = false }
        "auth.anonymous" = { enabled = false }
      }
      ingress = var.grafana_ingress.enabled ? {
        enabled          = true
        ingressClassName = var.grafana_ingress.class_name == "" ? null : var.grafana_ingress.class_name
        annotations      = var.grafana_ingress.annotations
        hosts            = [var.grafana_ingress.host]
        tls = var.grafana_ingress.tls_secret_name == "" ? [] : [
          { secretName = var.grafana_ingress.tls_secret_name, hosts = [var.grafana_ingress.host] }
        ]
      } : { enabled = false }
    }
  }
}

###############################################################################
# Namespace
###############################################################################

resource "kubernetes_namespace_v1" "this" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      # node-exporter needs host access (hostNetwork/hostPID/hostPath) to read
      # node metrics, which only the "privileged" Pod Security level allows.
      # Everything else in the stack runs as non-root without host access.
      "pod-security.kubernetes.io/enforce" = local.node_exporter_enabled ? "privileged" : "baseline"
      "pod-security.kubernetes.io/warn"    = "baseline"
    }
  }
}

locals {
  namespace = var.create_namespace ? kubernetes_namespace_v1.this[0].metadata[0].name : var.namespace
}

###############################################################################
# Grafana admin credentials (random password, stored in a Secret)
###############################################################################

resource "random_password" "grafana_admin" {
  length  = 32
  special = false
}

resource "kubernetes_secret_v1" "grafana_admin" {
  metadata {
    name      = local.grafana_admin_secret
    namespace = local.namespace
  }
  data = {
    "admin-user"     = "admin"
    "admin-password" = random_password.grafana_admin.result
  }
}

###############################################################################
# EKS: encrypted gp3 StorageClass (EKS only ships gp2)
###############################################################################

resource "kubernetes_storage_class_v1" "gp3" {
  count = local.create_gp3_class ? 1 : 0

  metadata {
    name   = "gp3"
    labels = { "app.kubernetes.io/managed-by" = "terraform" }
  }
  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer" # create the disk in the same AZ as the pod
  allow_volume_expansion = true
  parameters = {
    type      = "gp3"
    encrypted = "true"
  }
}

###############################################################################
# Dashboards: ConfigMaps labelled grafana_dashboard=1 are loaded by Grafana's sidecar
###############################################################################

resource "kubernetes_config_map_v1" "dashboard" {
  for_each = local.dashboard_files

  metadata {
    name      = "${var.release_name}-dashboard-${each.key}"
    namespace = local.namespace
    labels = {
      grafana_dashboard              = "1"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
  data = {
    "${each.key}.json" = file(each.value)
  }
}

###############################################################################
# The Helm release
###############################################################################

resource "helm_release" "this" {
  name       = var.release_name
  namespace  = local.namespace
  repository = var.chart_repository
  chart      = "kube-prometheus-stack"
  version    = var.chart_version

  # Wait until every pod is ready; on failure roll back to the previous version
  # instead of leaving a half-installed stack.
  wait            = true
  atomic          = true
  cleanup_on_fail = true
  timeout         = var.helm_timeout_seconds
  max_history     = 10

  values = compact([
    yamlencode(local.helm_values),
    var.extra_values,
  ])

  depends_on = [
    kubernetes_secret_v1.grafana_admin,
    kubernetes_storage_class_v1.gp3,
  ]
}
