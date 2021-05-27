# Benchmark guide

Sample benchmark [scenario](https://github.com/cortexproject/cortex/issues/3753):
- 9 tenants, each doing around 42M active series
- overall 381M active series with 6M datapoint/s => 360M datapoint/min (so ~60s between updates)
- 12 compactors (but Jan 2021 comment in ticket mentions that any given tenant will be assigned a single compactor)

## Install prerequisites

> curl -L https://opstrace-ci-main-artifacts.s3-us-west-2.amazonaws.com/cli/main/latest/opstrace-cli-linux-amd64-latest.tar.bz2 | tar xjf -
> sudo pacman -S eksctl

## Deploy clusters

### Opstrace cluster

1. Create cluster in `us-west-2`

> ./opstrace create aws opstrace-scale-test-$USER --log-level debug -c ./opstrace-cluster.yaml --write-kubeconfig-file ~/.kube/config-opstrace

2. Add people to opstrace cluster via UI

### Driver cluster

1. Create driver cluster (initially "just" 10 nodes) in `us-west-1` (intentionally spanning regions for a bit more accuracy)

> eksctl create cluster -f ./driver-eksctl.yaml

2. Scale up driver cluster

> COUNT=10
> eksctl scale nodegroup -r us-west-1 --cluster nick-scaletest-driver -n t3amedium --nodes $COUNT --nodes-min $COUNT --nodes-max $COUNT

## Start testing

In the test we have N avalanche instances being polled by M prometheus instances.

1. Deploy [avalanche](https://github.com/open-fresh/avalanche) instances into driver cluster. Could someday try cortex-tools' [benchtool](https://github.com/grafana/cortex-tools/blob/main/docs/benchtool.md) since it has richer metric type support, but it only has [basic auth](https://github.com/grafana/cortex-tools/blob/main/pkg/bench/query_runner.go#L185)

> kubectl apply -f ./driver-kube-avalanche.yaml

2. Deploy per-tenant prometheus instances into driver cluster (will send data to `$TENANT` in opstrace cluster):

> CLUSTER_NAME=nick-nine-nodes
> TENANT=default
> sed "s/__AUTH_TOKEN__/$(cat tenant-api-token-$TENANT)/g" ./driver-kube-prom.yaml.template | sed "s/__CLUSTER_NAME__/$CLUSTER_NAME/g" | sed "s/__TENANT__/$TENANT/g" | kubectl apply -f -

3. Check prometheus dashboard

> kubectl port-forward deployments/tenant-prometheus-$TENANT ui

4. Scale things up once they look good (saves time on redeploying if tweaks are needed):

> kubectl scale deployments/avalanche --replicas=300
> kubectl scale deployments/tenant-prometheus-$TENANT --replicas=5

EACH prometheus instance will be scraping ALL avalanche instances: Nprometheus * Navalanche

## Check status

Go to `https://system.yourcluster.opstrace.io/grafana` and check the `Opstrace Overview Dashboard`.
- Infra section: Want to stay under limits of around 60% CPU and RAM
- Cluster section: Pay attention to Active Series

TODO: measure per-tenant active series?
TODO: anything for datapoints/sec?

## See also

- [previous scale test deployments](./old/) copied from old repo [doc](https://github.com/opstrace/opstrace-prelaunch/blob/963d874b781299cab094629967e8156acd5fb0f0/docs/tests/how_to_launch_scale_test.md) and [manifests](https://github.com/opstrace/opstrace-prelaunch/tree/963d874b781299cab094629967e8156acd5fb0f0/test/manifests)
- [playbook: changing opstrace cluster size](https://docs.google.com/document/d/1wqTE2Evr2sAcfsSxkd7VD4cy8QqjaCnyCYiVoJ4i9gk/edit#heading=h.vf1rp13ok2tl)
