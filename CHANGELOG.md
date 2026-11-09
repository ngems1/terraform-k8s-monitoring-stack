# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-11-09

### Added
- Terraform module installing kube-prometheus-stack 79.7.1 (Prometheus, Alertmanager, Grafana, node-exporter, kube-state-metrics, Prometheus Operator).
- Per-cloud defaults for EKS (encrypted gp3 StorageClass), AKS, GKE (incl. Autopilot) and generic clusters; managed control-plane targets disabled.
- 11 node & pod health alerts with runbooks, loaded through the chart in a single apply, plus 6 promtool unit tests.
- "Cluster health (nodes & pods)" Grafana dashboard provisioned via the sidecar; extra rule and dashboard files supported.
- Alertmanager routing to Slack (all) and PagerDuty (critical), with inhibition and Watchdog silencing.
- Random Grafana admin password in a Secret, optional TLS Ingress, persistent volumes, size-based retention, atomic Helm releases.
- Examples for EKS, AKS, GKE and kind; 15 terraform test runs; CI with TFLint, promtool and an end-to-end kind install.
- Beginner guide (`docs/LEARN.md`) and runbooks (`docs/RUNBOOKS.md`).
