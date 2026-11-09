# Runbooks

Every alert from [`rules/node-pod-health.rules.yaml`](../rules/node-pod-health.rules.yaml) links here. Each runbook answers: **what does it mean, how do I check, how do I fix it.**

> **Severity guide.** `critical` means someone is paged and should act now; users are or soon will be affected. `warning` means look at it during working hours; it's a trend or a single failing workload.

Useful commands throughout:

```bash
kubectl get nodes -o wide
kubectl describe node <node>
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
kubectl -n <ns> describe pod <pod>
kubectl -n <ns> logs <pod> -c <container> --previous     # logs of the crashed attempt
kubectl top nodes && kubectl top pods -A --sort-by=memory
```

---

## NodeNotReady

**Meaning:** the kubelet on a node has stopped reporting Ready for 5+ minutes. After a timeout, Kubernetes evicts its pods and reschedules them elsewhere.

**Check:**
1. `kubectl describe node <node>`: look at *Conditions* and *Events*.
2. Is the VM running? (EC2 / Azure VM / GCE console, or the node group's activity history.)
3. Is this a planned change (node upgrade, autoscaler scale-down)? Then it should resolve by itself.

**Fix:** if the VM is unhealthy, cordon and drain it, then replace it (`kubectl drain <node> --ignore-daemonsets --delete-emptydir-data`, then delete the instance; the node group recreates it). If many nodes are affected at once, suspect networking or the control plane, and check the cloud provider's status page.

## NodeUnderPressure

**Meaning:** the kubelet reports `MemoryPressure`, `DiskPressure` or `PIDPressure` and will **evict pods** to protect the node.

**Check:** `kubectl describe node <node>` (*Conditions*, *Allocated resources*); `kubectl top pods -A --sort-by=memory`.

**Fix:**
- Memory: find pods without memory limits, or with limits far above their requests, and set realistic values.
- Disk: clean up unused images (the kubelet does this automatically as disk fills), check for pods writing large logs or `emptyDir` data.
- PIDs: look for fork bombs or runaway processes.

Longer term: bigger nodes, or the cluster autoscaler.

## NodeHighCPU

**Meaning:** the node's CPU has been above 90% for 15 minutes. Workloads get slower; it isn't an outage by itself.

**Check:** `kubectl top pods -A --sort-by=cpu` and look for which pods on that node use the most.

**Fix:** set CPU requests so the scheduler spreads load, scale out the deployment (HPA), or add nodes. Investigate busy loops in the top consumer.

## NodeHighMemory

**Meaning:** less than 10% of the node's memory has been available for 15 minutes. The next step is `MemoryPressure` and evictions, or OOM kills.

**Check / fix:** same as NodeUnderPressure (memory). Make sure every container has a memory **limit** and a realistic **request**.

## NodeFilesystemAlmostFull

**Meaning:** a node disk has less than 10% free space. When it fills, the kubelet evicts pods and images can't be pulled. **Critical.**

**Check:** which mount (`/`, `/var/lib/containerd`, …)? Run `kubectl debug node/<node> -it --image=busybox -- df -h /host`.

**Fix (now):** free space by removing unused images (`crictl rmi --prune` on the node) and evicting log-heavy pods. **(Later):** larger node root volumes in the node group or launch template, and log rotation and limits.

## NodeFilesystemFillingUp

**Meaning:** at the current rate, a node disk will be full **within 24 hours** (based on the last 6 hours of growth). It's an early warning for NodeFilesystemAlmostFull.

**Fix:** as above, before it becomes critical. Find what's writing: a new deployment with verbose logging, or a stuck job.

## PodCrashLooping

**Meaning:** a container keeps crashing, and Kubernetes waits longer and longer between restarts (`CrashLoopBackOff`).

**Check:**
1. `kubectl -n <ns> logs <pod> -c <container> --previous`: the error from the last crash.
2. `kubectl -n <ns> describe pod <pod>`: *Last State* (exit code, `OOMKilled`?), failing probes, missing ConfigMaps or Secrets.

**Fix:** depends on the cause. Common ones: a bad config or a missing secret; a dependency (database) that's unreachable; a liveness probe that's too strict; a bad deploy (roll back with `kubectl -n <ns> rollout undo deploy/<name>`).

## PodNotRunning

**Meaning:** a pod has been `Pending`, `Unknown` or `Failed` for 15+ minutes.

**Check:** `kubectl -n <ns> describe pod <pod>`, then *Events*:
- `Insufficient cpu/memory`: no node has room. Lower the requests or add nodes.
- `didn't match node selector / taints`: scheduling constraints that can't be met.
- `pod has unbound immediate PersistentVolumeClaims`: a storage class or volume problem.
- `ImagePullBackOff`: wrong image name or tag, or missing registry credentials.

## ContainerOOMKilled

**Meaning:** a container used more memory than its limit and the kernel killed it.

**Fix:** raise the memory limit (and request) if the usage is legitimate; otherwise find the leak. Check the trend in Grafana (Kubernetes / Compute Resources / Pod).

## DeploymentReplicasMismatch

**Meaning:** a Deployment has had fewer *available* replicas than desired for 15+ minutes. Capacity is reduced and a rollout may be stuck.

**Check:** `kubectl -n <ns> rollout status deploy/<name>`, `kubectl -n <ns> get rs`, then look at the new pods. They usually show one of the problems above (crash loop, pending, image pull).

**Fix:** fix the underlying pod problem, or `kubectl -n <ns> rollout undo deploy/<name>`.

## PersistentVolumeAlmostFull

**Meaning:** a PVC has less than 10% free space. Databases and queues fail badly when their disk fills.

**Fix:** expand the volume. This works when the StorageClass has `allowVolumeExpansion: true`, which is true for the gp3 class this module creates: `kubectl -n <ns> patch pvc <pvc> -p '{"spec":{"resources":{"requests":{"storage":"<bigger>Gi"}}}}'`. Then clean up old data or add retention.
