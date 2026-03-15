$ kubectl -n consul port-forward deploy/api-gateway 19001:19000

That forwards your local 19001 → the pod's Envoy admin port 19000. It's for /config_dump, /stats, etc., and is intentionally not exposed via the api-gateway Service.

---

2026-02-27T10:12:29.395Z [ERROR] agent: Error starting agent: error="refusing to rejoin cluster because server has been offline for more than the configured server_rejoin_age_max (168h0m0s) - consider wiping your data dir"

kubectl consul exec statefulset/consul-server -- mv /consul/data/server_metadata.json /consul/data/_server_metadata.json

---
