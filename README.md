# Benchmark guide

How this works:
- `opstrace` cluster with 9 big nodes (see `opstrace-*.yaml` for configs)
- eks `driver` cluster with 5 himem nodes for 5 `prometheus` instances, and 25 medium nodes for `avalanche` instances (see `driver-*.yaml` for configs)
- the `prometheus` instances EACH scrape ALL of the `avalanche` instances, but each prometheus appends its pod name to the labels to ensure that each is treated as a distinct set of data. so the resulting metrics are Nprometheus * Navalanche
- the `prometheus` instances in the `driver` cluster are configured to `remote_write` to the `opstrace` cluster

Sample benchmark [scenario](https://github.com/cortexproject/cortex/issues/3753):
- 9 tenants, each doing around 42M active series
- overall 381M active series with 6M datapoint/s => 360M datapoint/min (so ~60s between updates)
- 12 compactors (but Jan 2021 comment in ticket mentions that any given tenant will be assigned a single compactor)

## Install prerequisites

```
curl -L https://opstrace-ci-main-artifacts.s3-us-west-2.amazonaws.com/cli/main/latest/opstrace-cli-linux-amd64-latest.tar.bz2 | tar xjf -
sudo pacman -S eksctl
```

## Deploy clusters

### Opstrace cluster

1. Create cluster in `us-west-2`

```
./opstrace create aws $USER-$NUMNODES \
  --log-level debug \
  -c ./opstrace-cluster-PICKONE.yaml \
  --write-kubeconfig-file ~/.kube/config-opstrace
```

2. Apply cortex config overrides (increase series limits)

```
kubectl apply -f opstrace-kube-overrides.yaml
# restart controller pod if it's already running, some overrides are only checked once at startup
kubectl delete pod -n kube-system opstrace-controller-HASH
```

3. Add people to opstrace cluster via UI

### Driver cluster

1. Create driver cluster in same region as opstrace cluster

```
eksctl create cluster -f ./driver-eksctl-PICKONE.yaml
```

If there are problems, take a look at the CloudFormation dashboard first - eksctl is a thin veneer over some CF templates

## Start testing

In the test we have N avalanche instances being polled by M prometheus instances.

The `avalanche` pods are deployed as a `StatefulSet` only to have stable pod names, so that metric labels do not change if the avalanche pods are restarted, reconfigured, or evicted. For example a mass eviction can lead to an unexpected increase in distinct series labels, because the avalanche pod name is included in the series.

The `prometheus` pods are also deployed as a StatefulSet, both in order to have stable pod names, and because they need local storage.

1. Deploy [avalanche](https://github.com/open-fresh/avalanche) instances into driver cluster. Could someday try cortex-tools' [benchtool](https://github.com/grafana/cortex-tools/blob/main/docs/benchtool.md) since it has richer metric type support, but it only has [basic auth](https://github.com/grafana/cortex-tools/blob/main/pkg/bench/query_runner.go#L185).

```
kubectl apply -f ./driver-kube-avalanche.yaml
```

2. Deploy per-tenant prometheus instances into driver cluster (will send data to `$TENANT` in opstrace cluster):

```
CLUSTER_NAME=nick-nine-nodes
TENANT=default
sed "s/__AUTH_TOKEN__/$(cat tenant-api-token-$TENANT)/g" ./driver-kube-prom.template.yaml | \
  sed "s/__CLUSTER_NAME__/$CLUSTER_NAME/g" | \
  sed "s/__TENANT__/$TENANT/g" | \
  kubectl apply -f -
```

3. (optional) Check prometheus dashboard

```
kubectl port-forward deployments/tenant-prometheus-$TENANT ui
```

EACH prometheus instance will be scraping ALL avalanche instances: Nprometheus * Navalanche

## Check status

Go to `https://system.yourcluster.opstrace.io/grafana` and check the `Opstrace Overview Dashboard`.
- Infra section: Want to stay under limits of around 60% CPU and RAM
- Cluster section: Pay attention to Active Series


## Misc cluster operations

Get kubectl config:
```
aws eks update-kubeconfig --region CLUSTER-REGION --name CLUSTER-NAME --kubeconfig ~/.kube/outpath
```

After adding a nodegroup to the file, deploy it to an existing cluster:
```
eksctl create nodegroup -f driver-eksctl.yaml
```

Change nodegroup size:
```
COUNT=10
eksctl scale nodegroup -r us-west-1 --cluster nick-scaletest-driver -n t3medium --nodes $COUNT --nodes-min $COUNT --nodes-max $COUNT
```

To delete an eksctl nodegroup: Delete the corresponding CloudFormation stack in the AWS dashboard. The nodes will automatically be decommissioned and any resident pods will be moved off of them

To delete an eksctl cluster: Delete all the CloudFormation stacks for the nodegroups, THEN delete the stack for the cluster. Attempts to delete the cluster before the stacks SHOULD fail.

## See also

- [previous scale test deployments](./old/) copied from old repo [doc](https://github.com/opstrace/opstrace-prelaunch/blob/963d874b781299cab094629967e8156acd5fb0f0/docs/tests/how_to_launch_scale_test.md) and [manifests](https://github.com/opstrace/opstrace-prelaunch/tree/963d874b781299cab094629967e8156acd5fb0f0/test/manifests)
- [playbook: changing opstrace cluster size](https://docs.google.com/document/d/1wqTE2Evr2sAcfsSxkd7VD4cy8QqjaCnyCYiVoJ4i9gk/edit#heading=h.vf1rp13ok2tl)
