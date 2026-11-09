# Unit tests: `terraform test` (no cluster needed; helm/kubernetes are mocked).
#
# The interesting output of this module is the Helm *values* it generates, so
# most tests decode them with yamldecode() and check the settings that matter
# for each cloud.

mock_provider "helm" {}
mock_provider "kubernetes" {}
mock_provider "random" {}

variables {
  cloud_provider = "eks"
  cluster_name   = "prod-eks"
}

# ---------------------------------------------------------------- per cloud

run "eks_defaults" {
  command = plan

  assert {
    condition     = yamldecode(helm_release.this.values[0]).prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName == "gp3"
    error_message = "EKS should use the gp3 StorageClass."
  }

  assert {
    condition     = length(kubernetes_storage_class_v1.gp3) == 1 && kubernetes_storage_class_v1.gp3[0].parameters.encrypted == "true"
    error_message = "EKS should get an encrypted gp3 StorageClass."
  }

  assert {
    condition = (
      yamldecode(helm_release.this.values[0]).kubeScheduler.enabled == false &&
      yamldecode(helm_release.this.values[0]).kubeControllerManager.enabled == false &&
      yamldecode(helm_release.this.values[0]).kubeEtcd.enabled == false &&
      yamldecode(helm_release.this.values[0]).defaultRules.rules.etcd == false
    )
    error_message = "Managed control-plane components must not be scraped (they would alert as Down forever)."
  }

  assert {
    condition     = yamldecode(helm_release.this.values[0]).prometheus.prometheusSpec.externalLabels.cluster == "prod-eks"
    error_message = "cluster_name must be added as an external label."
  }

  assert {
    condition     = yamldecode(helm_release.this.values[0]).prometheus.prometheusSpec.retentionSize == "45GB"
    error_message = "retentionSize should be 90% of the 50Gi volume."
  }

  assert {
    condition     = yamldecode(helm_release.this.values[0]).nodeExporter.enabled == true
    error_message = "node-exporter must run on EKS."
  }

  assert {
    condition     = kubernetes_namespace_v1.this[0].metadata[0].labels["pod-security.kubernetes.io/enforce"] == "privileged"
    error_message = "node-exporter needs the privileged Pod Security level."
  }

  assert {
    condition     = helm_release.this.chart == "kube-prometheus-stack" && helm_release.this.version == "79.7.1" && helm_release.this.atomic
    error_message = "Chart must be pinned and installed atomically."
  }
}

run "aks_defaults" {
  command = plan

  variables {
    cloud_provider = "aks"
  }

  assert {
    condition     = yamldecode(helm_release.this.values[0]).grafana.persistence.storageClassName == "managed-csi"
    error_message = "AKS should use managed-csi."
  }

  assert {
    condition     = length(kubernetes_storage_class_v1.gp3) == 0
    error_message = "No gp3 StorageClass outside EKS."
  }

  assert {
    condition     = yamldecode(helm_release.this.values[0]).coreDns.enabled == true && yamldecode(helm_release.this.values[0]).kubeDns.enabled == false
    error_message = "AKS runs CoreDNS."
  }
}

run "gke_autopilot" {
  command = plan

  variables {
    cloud_provider = "gke"
    gke_autopilot  = true
  }

  assert {
    condition     = yamldecode(helm_release.this.values[0]).nodeExporter.enabled == false && yamldecode(helm_release.this.values[0]).defaultRules.rules.node == false
    error_message = "Autopilot forbids node-exporter; its rules must be off too."
  }

  assert {
    condition     = kubernetes_namespace_v1.this[0].metadata[0].labels["pod-security.kubernetes.io/enforce"] == "baseline"
    error_message = "Without node-exporter the namespace can use the baseline Pod Security level."
  }

  assert {
    condition     = yamldecode(helm_release.this.values[0]).kubeDns.enabled == true && yamldecode(helm_release.this.values[0]).coreDns.enabled == false
    error_message = "GKE uses kube-dns."
  }

  assert {
    condition     = yamldecode(helm_release.this.values[0]).alertmanager.alertmanagerSpec.storage.volumeClaimTemplate.spec.storageClassName == "standard-rwo"
    error_message = "GKE should use standard-rwo."
  }
}

run "generic_cluster_keeps_control_plane_monitoring" {
  command = plan

  variables {
    cloud_provider = "generic"
    cluster_name   = ""
  }

  assert {
    condition     = yamldecode(helm_release.this.values[0]).kubeScheduler.enabled == true && yamldecode(helm_release.this.values[0]).kubeEtcd.enabled == true
    error_message = "Self-managed clusters expose their control plane."
  }

  assert {
    condition     = yamldecode(helm_release.this.values[0]).prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName == null
    error_message = "Generic clusters should use the cluster's default StorageClass."
  }

  assert {
    condition     = length(yamldecode(helm_release.this.values[0]).prometheus.prometheusSpec.externalLabels) == 0
    error_message = "No cluster label when cluster_name is empty."
  }
}

run "explicit_storage_class_wins_and_skips_gp3_creation" {
  command = plan

  variables {
    storage_class_name = "io2-fast"
  }

  assert {
    condition     = yamldecode(helm_release.this.values[0]).grafana.persistence.storageClassName == "io2-fast" && length(kubernetes_storage_class_v1.gp3) == 0
    error_message = "An explicit storage class must be used as-is."
  }
}

# ---------------------------------------------------------------- alerting

run "rules_are_loaded_through_the_chart" {
  command = plan

  assert {
    condition     = [for g in yamldecode(helm_release.this.values[0]).additionalPrometheusRulesMap["node-pod-health"].groups : g.name] == ["node-health", "pod-health"]
    error_message = "The node & pod health rule groups must be loaded."
  }

  assert {
    condition = contains(
      flatten([for g in yamldecode(helm_release.this.values[0]).additionalPrometheusRulesMap["node-pod-health"].groups : [for r in g.rules : r.alert]]),
      "NodeNotReady"
    )
    error_message = "NodeNotReady alert missing."
  }

  assert {
    condition     = output.alert_rule_groups == tolist(["node-health", "pod-health"])
    error_message = "alert_rule_groups output is wrong."
  }

  assert {
    condition     = yamldecode(helm_release.this.values[0]).prometheus.prometheusSpec.ruleSelectorNilUsesHelmValues == false
    error_message = "Prometheus must pick up rules from every namespace."
  }
}

run "alertmanager_without_receivers_is_valid_but_silent" {
  command = plan

  assert {
    condition     = length(yamldecode(helm_release.this.values[0]).alertmanager.config.receivers[1].slack_configs) == 0
    error_message = "No Slack config expected without a webhook."
  }

  assert {
    condition     = [for r in yamldecode(helm_release.this.values[0]).alertmanager.config.route.routes : r.receiver] == ["null", "null", "critical"]
    error_message = "Watchdog/InfoInhibitor must be silenced and critical alerts routed separately."
  }
}

run "alertmanager_slack_and_pagerduty" {
  command = plan

  variables {
    slack_webhook_url     = "https://hooks.slack.com/services/T000/B000/XXXX"
    slack_channel         = "#prod-alerts"
    pagerduty_routing_key = "0123456789abcdef0123456789abcdef"
  }

  # Values containing secrets are sensitive; nonsensitive() lets the test read them.
  assert {
    condition     = nonsensitive(yamldecode(helm_release.this.values[0]).alertmanager.config.receivers[1].slack_configs[0].channel) == "#prod-alerts"
    error_message = "Default receiver should post to Slack."
  }

  assert {
    condition = (
      length(nonsensitive(yamldecode(helm_release.this.values[0]).alertmanager.config.receivers[2].pagerduty_configs)) == 1 &&
      length(nonsensitive(yamldecode(helm_release.this.values[0]).alertmanager.config.receivers[1].pagerduty_configs)) == 0
    )
    error_message = "Only the critical receiver may page PagerDuty."
  }
}

# ---------------------------------------------------------------- grafana

run "grafana_dashboard_and_admin_secret" {
  command = plan

  assert {
    condition     = kubernetes_config_map_v1.dashboard["cluster-health"].metadata[0].labels.grafana_dashboard == "1"
    error_message = "Dashboard ConfigMap needs the sidecar label."
  }

  assert {
    condition     = jsondecode(kubernetes_config_map_v1.dashboard["cluster-health"].data["cluster-health.json"]).uid == "cluster-health"
    error_message = "Dashboard JSON must be valid and keep a stable uid."
  }

  assert {
    condition     = yamldecode(helm_release.this.values[0]).grafana.admin.existingSecret == "monitoring-stack-grafana-admin"
    error_message = "Grafana must take its admin credentials from the generated Secret."
  }

  assert {
    condition     = random_password.grafana_admin.length == 32 && random_password.grafana_admin.special == false
    error_message = "Grafana admin password must be 32 random characters."
  }

  assert {
    condition     = yamldecode(helm_release.this.values[0]).grafana.ingress.enabled == false
    error_message = "Grafana must not be exposed by default."
  }
}

run "grafana_ingress_with_tls" {
  command = plan

  variables {
    grafana_ingress = {
      enabled         = true
      host            = "grafana.example.com"
      class_name      = "nginx"
      tls_secret_name = "grafana-tls"
      annotations     = { "cert-manager.io/cluster-issuer" = "letsencrypt" }
    }
  }

  assert {
    condition     = yamldecode(helm_release.this.values[0]).grafana.ingress.tls[0].secretName == "grafana-tls"
    error_message = "TLS must be configured on the ingress."
  }

  assert {
    condition     = output.grafana_url == "https://grafana.example.com"
    error_message = "grafana_url should use https when TLS is configured."
  }
}

run "extra_values_are_applied_last" {
  command = plan

  variables {
    extra_values = "prometheus:\n  prometheusSpec:\n    scrapeInterval: 15s\n"
  }

  assert {
    condition     = length(helm_release.this.values) == 2 && yamldecode(helm_release.this.values[1]).prometheus.prometheusSpec.scrapeInterval == "15s"
    error_message = "extra_values must be passed as the last values document."
  }
}

# ---------------------------------------------------------------- input validation

run "rejects_unknown_cloud" {
  command = plan
  variables {
    cloud_provider = "openshift"
  }
  expect_failures = [var.cloud_provider]
}

run "rejects_bad_retention" {
  command = plan
  variables {
    prometheus_retention = "two weeks"
  }
  expect_failures = [var.prometheus_retention]
}

run "rejects_ingress_without_host" {
  command = plan
  variables {
    grafana_ingress = { enabled = true }
  }
  expect_failures = [var.grafana_ingress]
}

run "rejects_non_slack_webhook" {
  command = plan
  variables {
    slack_webhook_url = "http://evil.example.com/hook"
  }
  expect_failures = [var.slack_webhook_url]
}
