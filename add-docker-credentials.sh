#!/bin/bash

USER=$1
PASSWORD=$2

if [ -z "$USER" -o -z "$PASSWORD" ]; then
    echo "Syntax: $0 <username> <password>"
    exit 1
fi

# strict mode, AFTER accessing $0/$1/etc above
IFS=$'\n\t'

# namespace:password is b64-encoded within docker auth json
AUTH_ORIG="$USER:$PASSWORD"       # ...
if [[ "$OSTYPE" == "darwin"* ]]; then
  # Mac OSX uses -b instead of -w and defaults to same as -w
  AUTH_B64=$(echo -n $AUTH_ORIG | base64)
else
  AUTH_B64=$(echo -n $AUTH_ORIG | base64 -w 0)
fi
# json is then b64-encoded (again) for the k8s secret
AUTHS_ORIG="{\"auths\":{\"https://index.docker.io/v2/\":{\"auth\":\"$AUTH_B64\"}}}"
if [[ "$OSTYPE" == "darwin"* ]]; then
  # Mac OSX uses -b instead of -w and defaults to same as -w
  AUTHS_B64=$(echo -n $AUTHS_ORIG | base64)
else
  AUTHS_B64=$(echo -n $AUTHS_ORIG | base64 -w 0)
fi

# omits namespace:
read -d '' SECRET_YAML <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: regcred
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: $AUTHS_B64
EOF

for ns in $(kubectl get namespaces -o name | sed 's,namespace/,,g'); do
    echo "Creating 'regcred' secret in namespace $ns"
    echo "$SECRET_YAML" | kubectl apply -n $ns -f -
done
