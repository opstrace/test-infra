# How to launch the scale test

Here are some simple instructions for creating scale test clusters manually.

TOOD: eventually, this entire process—including the assessment of its performance—should be fully automated and optimized.

## I. Launch Opstrace cluster

Nothing surprising here. Just be sure to set your environment variables:

```console
export STACK_NAME=scale0 OPSTRACE_INITIAL_NODE_COUNT=7 OPSTRACE_INSTALL_OPTS="--machine-type n1-highmem-32" OPSTRACE_AUTHORIZED_SOURCE_IP_RANGES="0.0.0.0/0"
```

## II. Launch workload clusters

Launch a cluster like this:

```console
gcloud beta container --project "vast-pad-240918" clusters create "workload-1" --zone "us-central1-c" --no-enable-basic-auth --release-channel "regular" --machine-type "n1-standard-2" --image-type "COS" --disk-type "pd-standard" --disk-size "500" --metadata disable-legacy-endpoints=true --scopes "https://www.googleapis.com/auth/devstorage.read_only","https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring","https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly","https://www.googleapis.com/auth/trace.append" --num-nodes "50" --enable-stackdriver-kubernetes --enable-ip-alias --network "projects/vast-pad-240918/global/networks/default" --subnetwork "projects/vast-pad-240918/regions/us-central1/subnetworks/default" --default-max-pods-per-node "110" --no-enable-master-authorized-networks --addons HorizontalPodAutoscaling,HttpLoadBalancing --enable-autoupgrade --enable-autorepair && gcloud beta container --project "vast-pad-240918" \
node-pools create "prom-pool" --cluster "workload-1" --zone "us-central1-c" --machine-type "n1-standard-32" --image-type "COS" --disk-type "pd-standard" --disk-size "800" --metadata disable-legacy-endpoints=true --scopes "https://www.googleapis.com/auth/devstorage.read_only","https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring","https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly","https://www.googleapis.com/auth/trace.append" --num-nodes "1" --enable-autoupgrade --enable-autorepair
```

The default region here is `us-central1` to add a little color to the test. The `prom-pool` is necessary since we are using a singe Prometheus instance to collect all metrics and Prometheus uses a substantial amount of resources.

## III. Deploy workloads

Assuming `$STACK_NAME` references your target Opstrace cluster, launch collectors like this...

```console
gcloud container clusters get-credentials workload-1 --zone us-central1-c --project vast-pad-240918
sed "s/%NAME%/$STACK_NAME/" test/manifests/collectors-scale-test.yaml | kubectl apply -f -
```

```console
sed "s/%NAME%/$STACK_NAME/" test/manifests/logs-daemonset-scale-test.yaml | kubectl apply -f -
sed "s/%NAME%/$STACK_NAME/" test/manifests/metrics-daemonset-scale-test.yaml | kubectl apply -f -
```

### Use deployments instead

To scale up and down, you can also use a Deployment like this:

```console
sed "s/%NAME%/$STACK_NAME/" test/manifests/logs-deployment-scale-test.yaml | kubectl apply -f -
sed "s/%NAME%/$STACK_NAME/" test/manifests/metrics-deployment-scale-test.yaml | kubectl apply -f -
```

The default replica count is 1. To scale up, do this:

```console
kubectl scale deploy/looker --replicas=10
kubectl scale deploy/avalanche --replicas=10
```

Or go slowly to a specific target, like this:

```console
for ((i=20; i<=100; i+=10)) ; do kubectl scale deploy/avalanche --replicas=$i ; kubectl scale deploy/looker --replicas=$i ; sleep 120 ; done
```

## IV. Inspect workloads

There are many ways to inspect these workloads running on Kubernetes. Here are some of the ways I have used.

You can observe the utilization of a pool using a selector for its name:

```console
$ kubectl top nodes --selector=cloud.google.com/gke-nodepool=default-pool --sort-by=cpu
NAME                                     CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
gke-workload-1-logs-pool-e2f995a0-4l46   2174m        55%    3659Mi          29%
gke-workload-1-logs-pool-e2f995a0-s48j   2098m        53%    3665Mi          29%
gke-workload-1-logs-pool-e2f995a0-4d8g   1718m        43%    3665Mi          29%
gke-workload-1-logs-pool-e2f995a0-9f7j   1381m        35%    2236Mi          18%
gke-workload-1-logs-pool-e2f995a0-trvs   1176m        30%    2352Mi          18%
```

You can then investigate a particular node to see, for example, CPU allocations like this:

```console
$ kubectl describe nodes gke-workload-1-logs-pool-e2f995a0-4l46 | grep -A 50 "CPU Requests"
  Namespace                   Name                                                 CPU Requests  CPU Limits  Memory Requests  Memory Limits  AGE
  ---------                   ----                                                 ------------  ----------  ---------------  -------------  ---
  default                     looker-894z9                                         500m (12%)    6 (153%)    2Gi (16%)        6Gi (49%)      2d11h
  kube-system                 fluentd-gcp-v3.1.1-slfz8                             100m (2%)     1 (25%)     200Mi (1%)       500Mi (4%)     9d
  kube-system                 kube-proxy-gke-workload-1-logs-pool-e2f995a0-4l46    100m (2%)     0 (0%)      0 (0%)           0 (0%)         9d
  kube-system                 prometheus-to-sd-cz7bh                               1m (0%)       3m (0%)     20Mi (0%)        20Mi (0%)      9d
Allocated resources:
  (Total limits may be over 100 percent, i.e., overcommitted.)
  Resource                   Requests      Limits
  --------                   --------      ------
  cpu                        701m (17%)    7003m (178%)
  memory                     2268Mi (18%)  6664Mi (53%)
  ephemeral-storage          0 (0%)        0 (0%)
  hugepages-2Mi              0 (0%)        0 (0%)
  attachable-volumes-gce-pd  0             0
Events:                      <none>
```

You can also ssh into the hosts for additional manual inspection:

```console
$ gcloud beta compute --project "vast-pad-240918" ssh --zone "us-central1-c" "gke-workload-1-logs-pool-e2f995a0-4l46"

Warning: Permanently added 'compute.2450573663955713051' (ED25519) to the list of known hosts.

Welcome to Kubernetes v1.15.9-gke.24!

You can find documentation for Kubernetes at:
  http://docs.kubernetes.io/

The source for this release can be found at:
  /home/kubernetes/kubernetes-src.tar.gz
Or you can download it at:
  https://storage.googleapis.com/kubernetes-release-gke/release/v1.15.9-gke.24/kubernetes-src.tar.gz

It is based on the Kubernetes source at:
  https://github.com/kubernetes/kubernetes/tree/v1.15.9-gke.24

For Kubernetes copyright and licensing information, see:
  /home/kubernetes/LICENSES

clambert@gke-workload-1-logs-pool-e2f995a0-4l46 ~ $
```
