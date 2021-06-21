#!/bin/bash

# This utility script adds 'imagePullSecrets: - name: regcred' to each Deployment and StatefulSet in the cluster.
# We could also patch DaemonSets but they don't seem to need the patching, so we skip them for now.
# NOTE: This should be safe to run multiple times on the same cluster.
#       If a deployment/statefulset has already been patched, repatching it should be a no-op.

# Compatible with both Deployments and StatefulSets
DEPLOYMENT_PATCH="spec:
  template:
    spec:
      imagePullSecrets:
      - name: regcred"

echo "Applying patch:"
echo "$DEPLOYMENT_PATCH"
echo ""

for ns in $(kubectl get namespaces -o name | sed 's,namespace/,,g'); do
    # explicitly avoid touching anything these namespaces since they shouldn't need patching in practice
    if [ "$ns" = "default" -o "$ns" = "kube-node-lease" -o "$ns" = "kube-public" ]; then
        echo "Skipping namespace: $ns"
        echo ""
        continue
    fi
    echo "Patching namespace: $ns"

    # in kube-system, only patch opstrace-controller, leave everything else alone
    if [ "$ns" = "kube-system" ]; then
        kubectl patch deployment -n kube-system opstrace-controller --patch "$DEPLOYMENT_PATCH"
        continue
    fi

    for deployment in $(kubectl get deployments -n $ns -o name | sed 's,deployment.apps/,,g'); do
        kubectl patch deployment -n $ns $deployment --patch "$DEPLOYMENT_PATCH"
    done
    for statefulset in $(kubectl get statefulsets -n $ns -o name | sed 's,statefulset.apps/,,g'); do
        kubectl patch statefulset -n $ns $statefulset --patch "$DEPLOYMENT_PATCH"
    done
    echo ""
done
echo "Done! You may need to manually delete some StatefulSet pods for them to pick up the imagePullSecret"
