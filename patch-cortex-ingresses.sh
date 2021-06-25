#!/bin/bash

# This utility script adds annotations to tenant cortex ingresses to allow larger payloads from scrapers,
# and removes the opstrace annotation so that the controller does not remove the changes.
# Specifically, this fixes errors like this logged by prometheus scraper pods:
#   ts=2021-06-23T08:06:10.048Z caller=dedupe.go:112 component=remote level=error remote_name=259b09 url=https://cortex.metrics-c.ship.opstrace.io/api/v1/push
#   msg="non-recoverable error" count=1669 err="server returned HTTP status 413 Request Entity Too Large: <html>"
# NOTE: This should be safe to run multiple times on the same cluster.
#       If a deployment/statefulset has already been patched, repatching it should be a no-op.

ANNOTATIONS="nginx.ingress.kubernetes.io/client-body-buffer-size=100m \
nginx.ingress.kubernetes.io/proxy-body-size=100m \
opstrace-"

echo "Applying annotations: $ANNOTATIONS"
echo ""

for ns in $(kubectl get namespaces -o name | sed 's,namespace/,,g'); do
    # explicitly avoid touching anything these namespaces since they shouldn't need patching in practice
    if [[ "$ns" != *-tenant ]]; then
        echo "Skipping namespace: $ns"
        echo ""
        continue
    fi
    echo "Patching cortex ingress in namespace: $ns"
    kubectl annotate --overwrite -n $ns ingress cortex $ANNOTATIONS
    echo ""
done
echo "Done! Hopefully any 413 errors will go away"
