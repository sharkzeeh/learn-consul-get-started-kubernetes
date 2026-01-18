# Hashicorp consul-k8s tutorials

Links:
- https://github.com/hashicorp/consul-k8s
- https://developer.hashicorp.com/consul/tutorials/get-started-kubernetes

## Install Hashicorp binaries

### Download consul-k8s cli
https://releases.hashicorp.com/consul-k8s/

```sh
VERSION=1.9.1
curl -LO https://releases.hashicorp.com/consul-k8s/${VERSION}/consul-k8s_${VERSION}_linux_amd64.zip
unzip consul-k8s_${VERSION}_linux_amd64.zip

sudo install consul-k8s /usr/local/bin/consul-k8s
```

### Windows
- Put Hashicorp exe files in `%USERPROFILE%/hashicorp/bin`
```sh
PS C:\Users\robez\hashicorp\bin> pwd

Path
----
C:\Users\robez\hashicorp\bin


PS C:\Users\robez\hashicorp\bin> ls


    Directory: C:\Users\robez\hashicorp\bin


Mode                 LastWriteTime         Length Name
----                 -------------         ------ ----
-a----        12/25/2025   2:42 AM      137480080 consul-k8s.exe
-a----         10/8/2024   2:23 PM      185134256 consul.exe
-a----         10/8/2024   2:25 PM       91100336 terraform.exe
```

- Edit system environment variables
    * User variables for \<USER\>
    * Path -> New
    ```sh
    C:\Users\robez\hashicorp\bin
    ```


## 1. Deploy Consul on Kubernetes

Links:
- https://developer.hashicorp.com/consul/tutorials/get-started-kubernetes/kubernetes-gs-deploy
- https://github.com/hashicorp-education/learn-consul-get-started-kubernetes

```sh
cd learn-consul-get-started-kubernetes/self-managed/local
```

- template chart
```sh
helm template consul hashicorp/consul -n consul `
    -f helm/values-v1.yaml `
    --version 1.9.2 > rendered.yaml
```

- install / uninstall
```sh
helm install --values helm/values-v1.yaml consul hashicorp/consul --create-namespace --namespace consul --version "1.9.2"

# helm uninstall consul -n consul --no-hooks
# kubectl delete namespace consul --wait=false
```

- set default namespace
```sh
kubectl config set-context --current --namespace=consul
```

- set env variables (+ acl token)
```sh
export CONSUL_HTTP_TOKEN=$(kubectl get --namespace consul secrets/consul-bootstrap-acl-token --template={{.data.token}} | base64 -d)
export CONSUL_HTTP_ADDR=https://127.0.0.1:8501
export CONSUL_HTTP_SSL_VERIFY=false
```

## 2. Securely connect your services with Consul service mesh

Links:
- https://developer.hashicorp.com/consul/tutorials/get-started-kubernetes/kubernetes-gs-service-mesh

- create namespace for *hashicups*
```sh
kubectl create namespace demo
```

<!-- - create a separate namespace and label it
```sh
kubectl create namespace demo
kubectl label namespace demo consul.hashicorp.com/connect-inject=enabled
``` -->

<!-- - remove label from namespace (trailing `-` is important)
```sh
kubectl label namespace demo consul.hashicorp.com/connect-inject-
namespace/demo unlabeled

kubectl get namespace demo --show-labels
``` -->

- apply k8s manifests
```sh
kubectl apply -n demo -f hashicups/v1/
```

- list existing *Services* (note *proxy* services) and *Intentions*

This configuration deployed Consul in secure mode with ACLs set to a default deny policy and is automatically managed by Consul and Kubernetes.

This means that the only allowed service-to-service communications are the ones explicitly specified by intentions.
```sh
kubectl port-forward svc/consul-ui --namespace consul 8501:443

$ consul catalog services
consul
frontend
frontend-sidecar-proxy
nginx
nginx-sidecar-proxy
payments
payments-sidecar-proxy
product-api
product-api-db
product-api-db-sidecar-proxy
product-api-sidecar-proxy
public-api
public-api-sidecar-proxy

$ consul intention list
There are no intentions.
```

- observe *error* in `product-api` pod: *API* cannot connect to *DB*
```sh
2025-12-25T08:23:06.336Z [ERROR] Unable to connect to database: error="unexpected EOF"
2025-12-25T08:23:07.345Z [ERROR] Unable to connect to database: error="unexpected EOF"
2025-12-25T08:23:08.353Z [ERROR] Unable to connect to database: error="unexpected EOF"
2025-12-25T08:23:09.361Z [ERROR] Unable to connect to database: error="unexpected EOF"
2025-12-25T08:23:09.361Z [ERROR] Timeout waiting for database connection
```

- observe *error* `RBAC: access denied`
```sh
kubectl port-forward svc/nginx --namespace demo 8081:80

curl localhost:8081
RBAC: access denied
```

- apply Consul *Intentions* to allow service-to-service communication
```sh
kubectl apply -n demo -f hashicups/intentions/allow.yaml
```

- observe working app at `localhost:8081`
![alt](./screenshots/hashicups_01.jpg){width=50%}

```sh
curl -s -o /dev/null -w "%{http_code}" localhost:8081
200
```

- list *Intentions*
```sh
$ consul intention list
ID  Source       Action  Destination     Precedence
    nginx        allow   frontend        9
    nginx        allow   public-api      9
    product-api  allow   product-api-db  9
    public-api   allow   payments        9
    public-api   allow   product-api     9
```

### Misc

- Delete intentions (RECOMMENDED WAY)
```sh
# delete all intentions
kubectl delete -n demo -f hashicups/intentions/allow.yaml
# or delete individual ones:
kubectl delete -n demo serviceintentions.consul.hashicorp.com/frontend
```

- Delete intentions (directly in Consul - NOT RECOMMENDED); you will not be able to recreate the intentions with kubectl apply -f allow.yaml
```sh
# export CONSUL_HTTP_TOKEN=$(kubectl get --namespace consul secrets/consul-bootstrap-acl-token --template={{.data.token}} | base64 -d)
# export CONSUL_HTTP_ADDR=https://127.0.0.1:8501
# export CONSUL_HTTP_SSL_VERIFY=false

consul config list -kind service-intentions
frontend
payments
product-api
product-api-db
public-api

for name in $(consul config list -kind service-intentions);
do
    echo "Deleting intention: $name"
    consul config delete -kind service-intentions -name "$name"
done

consul config list -kind service-intentions
# should be empty
```

- Restore intentions (if you deleted them directly from consul)
```sh
for r in frontend public-api product-api product-api-db payments; do
  kubectl annotate -n demo serviceintentions.consul.hashicorp.com/$r \
    consul.hashicorp.com/reconcile-at="$(date +%s)" --overwrite
done

consul config list -kind service-intentions
```

## 3. Enable external traffic ingress into Consul service mesh

Links:
- https://developer.hashicorp.com/consul/tutorials/get-started-kubernetes/kubernetes-gs-ingress
