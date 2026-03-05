# Debug Consul DNS in consul-k8s

## Create pods

### `consul-inject = false`

- pod
```sh
kubectl -n debug run -it client --rm --restart=Never \
  --image=nicolaka/netshoot \
  --overrides='{
    "apiVersion":"v1",
    "metadata":{
      "annotations":{
        "consul.hashicorp.com/connect-inject":"false"
      }
    },
    "spec":{
      "restartPolicy":"Never",
      "automountServiceAccountToken":false,
      "containers":[{"name":"client","image":"nicolaka/netshoot","stdin":true,"tty":true,"command":["sh"]}],
      "dnsPolicy":"ClusterFirst"
    }
  }' -- sh
```
or
```sh
kubectl -n debug apply -f debug/netshoot-pod.yaml
```

- deploy
```sh
kubectl -n debug apply -f debug/netshoot-deploy.yaml
```

these requests will fail because of missing service intentios (see section `consul-inject = true`)
```sh

client:~# curl public-api.demo:8080
curl: (52) Empty reply from server

client:~# curl frontend.demo.svc.cluster.local:3000
curl: (52) Empty reply from server
```

### `consul-inject = true`
- create K8S objects:
   * namespace
   * Service
   * ServiceDefaults
   * ServiceIntentions (debug -> frontend, debug -> public-api)
```sh
kubectl apply -f debug/debug-consul-inject-objects.yaml
kubectl apply -f debug/debug-intentions.yaml
kubectl apply -f debug/netshoot-deploy-connect-inject.yaml

# kubectl apply -f debug/netshoot-pod.yaml
## kubectl -n debug run -it --rm curl --image=curlimages/curl --serviceaccount=deubg -- sh
```

- exec into netshoot container
```sh
# deployed as a pod
kubectl -n debug -c netshoot exec -it debug -- bash

# deployed as a deployment
kubectl -n debug -c netshoot exec -it deploy/debug -- bash
```

- run curl get requests (UNRELIABLE RESULTS)
```sh
$ nslookup public-api.service.consul
Server:         127.0.0.1
Address:        127.0.0.1:53


Name:   public-api.service.consul
Address: 10.1.0.83

# NOK
$ curl public-api.service.consul:8080
$ curl -sS http://frontend.service.consul:3000/
curl: (52) Empty reply from server
```

- run test requests
```sh
kubectl -n demo exec -it debug -c curl -- sh
kubectl -n demo exec -it deploy/debug -c curl -- sh

# OK
curl public-api.demo
curl public-api.demo:8080

curl frontend.demo.svc.cluster.local
curl frontend.demo.svc.cluster.local:3000
# html content will be returned if you DO NOT use "upstream" annotation in your app
# otherwise curl: (52) Empty reply from server (see test requests from nginx pod next)

nslookup public-api.service.consul. consul-dns.consul
Server:         consul-dns.consul
Address:        10.111.33.219#53

Name:   public-api.service.consul
Address: 10.1.0.172
```

### Test requests from NGINX pod (demo/nginx)

- upstream annotation enabled
```yaml
# deploy/nginx.yaml
annotations:
  consul.hashicorp.com/connect-inject: "true"
  consul.hashicorp.com/connect-service-upstreams: frontend:3000, public-api:8080
```

```sh
kubectl -n demo exec -it deploy/nginx -c nginx -- sh

# OK (check upstream settings for deploy/nginx)
curl -sS http://127.0.0.1:8080/     # public-api
curl -sS http://127.0.0.1:3000/     # frontend

# NOK: kube-dns no longer works if upstream annotation is enabled
curl frontend.demo.svc.cluster.local:3000
curl public-api.demo.svc.cluster.local:3000
curl: (52) Empty reply from server
```

- upstream annotation disabled
```yaml
# deploy/nginx.yaml
annotations:
  consul.hashicorp.com/connect-inject: "true"
  # consul.hashicorp.com/connect-service-upstreams: frontend:3000, public-api:8080
```

```sh
curl -i -s frontend:3000 | head -n 1
HTTP/1.1 200 OK

curl localhost:3000
curl: (7) Failed to connect to localhost port 3000 after 0 ms: Could not connect to server
```

---

## Consul DNS. Transparent proxy

Links:
- [Static DNS queries](https://developer.hashicorp.com/consul/docs/discover/service/static)

Transparent proxy 53 -> 8600

```sh
debug-d8f8956b7-9qw9f:~# dig @127.0.0.1 -p 8600 public-api.service.consul

;; ANSWER SECTION:
public-api.service.consul. 0    IN      A       10.1.0.141

;; Query time: 0 msec
;; SERVER: 127.0.0.1#8600(127.0.0.1) (UDP)
;; WHEN: Mon Jan 19 16:28:43 UTC 2026
;; MSG SIZE  rcvd: 70

debug-d8f8956b7-9qw9f:~# dig @127.0.0.1 -p 53 public-api.service.consul

;; ANSWER SECTION:
public-api.service.consul. 0    IN      A       10.1.0.141

;; Query time: 0 msec
;; SERVER: 127.0.0.1#53(127.0.0.1) (UDP)
;; WHEN: Mon Jan 19 16:28:52 UTC 2026
;; MSG SIZE  rcvd: 70
```

### nslookup

`.` dot at the end is important - it becomes an absolute FQDN

```sh
debug-d8f8956b7-9qw9f:~# nslookup public-api.service.consul. 127.0.0.1
Server:         127.0.0.1
Address:        127.0.0.1#53

Name:   public-api.service.consul
Address: 10.1.0.141
```

- the request fails if you omit last dot `.`
```sh
debug-fbd67b496-svgzz:~# nslookup public-api.service.consul 127.0.0.1
Server:         127.0.0.1
Address:        127.0.0.1#53

** server can't find public-api.service.consul.debug.svc.cluster.local: REFUSED
```

- Default nslookup fails because it falls back to CoreDNS
```sh
debug-d8f8956b7-9qw9f:~# nslookup public-api.service.consul.
;; Got recursion not available from 127.0.0.1, trying next server
Server:         10.96.0.10
Address:        10.96.0.10#53

** server can't find public-api.service.consul: NXDOMAIN
```

- Consul DNS service in K8S (ip 10.111.33.219 / service name `consul-dns.consul`) and local transparent DNS path works (127.0.0.1) work
```sh 
kubectl -n consul get svc consul-dns -o jsonpath='{.spec.clusterIP}'
10.111.33.219

debug-d8f8956b7-9qw9f:~# nslookup public-api.service.consul. 10.111.33.219
debug-d8f8956b7-9qw9f:~# nslookup public-api.service.consul. consul-dns.consul
Server:         consul-dns.consul
Address:        10.111.33.219#53

Name:   public-api.service.consul
Address: 10.1.0.141

debug-d8f8956b7-9qw9f:~# nslookup public-api.service.consul. 127.0.0.1
Server:         127.0.0.1
Address:        127.0.0.1#53

Name:   public-api.service.consul
Address: 10.1.0.141
```

---

### dig

- dig with coredns (kube-system.kube-dns service ) fails - OK
```sh
$ kubectl get svc -n kube-system -o wide | grep kube-dns
kube-dns   ClusterIP   10.96.0.10   <none>        53/UDP,53/TCP,9153/TCP   35d   k8s-app=kube-dns
```

```sh
debug-d8f8956b7-9qw9f:~# dig @10.96.0.10           public-api.service.consul
debug-d8f8956b7-9qw9f:~# dig @kube-dns.kube-system public-api.service.consul

; <<>> DiG 9.20.17 <<>> @kube-dns.kube-system public-api.service.consul
; (1 server found)
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NXDOMAIN, id: 55797
;; flags: qr rd ra; QUERY: 1, ANSWER: 0, AUTHORITY: 0, ADDITIONAL: 1

;; OPT PSEUDOSECTION:
; EDNS: version: 0, flags:; udp: 1232
; COOKIE: 75d302006266fff3 (echoed)
;; QUESTION SECTION:
;public-api.service.consul.     IN      A

;; Query time: 12 msec
;; SERVER: 10.96.0.10#53(kube-dns.kube-system) (UDP)
;; WHEN: Fri Jan 23 11:53:22 UTC 2026
;; MSG SIZE  rcvd: 66
```

^
|

Confirmed by your own evidence

You observed with `netstat` / `ss`
```sh
debug-d8f8956b7-9qw9f:~# netstat -lntup
Active Internet connections (only servers)
Proto Recv-Q Send-Q Local Address           Foreign Address         State       PID/Program name
tcp        0      0 127.0.0.1:15001         0.0.0.0:*               LISTEN      -
tcp        0      0 127.0.0.1:15001         0.0.0.0:*               LISTEN      -
tcp        0      0 10.1.0.144:20000        0.0.0.0:*               LISTEN      -
tcp        0      0 10.1.0.144:20000        0.0.0.0:*               LISTEN      -
tcp        0      0 127.0.0.1:37735         0.0.0.0:*               LISTEN      -
tcp        0      0 127.0.0.1:20600         0.0.0.0:*               LISTEN      -
tcp        0      0 127.0.0.1:19000         0.0.0.0:*               LISTEN      -
tcp        0      0 127.0.0.1:8600          0.0.0.0:*               LISTEN      -
udp        0      0 127.0.0.1:8600          0.0.0.0:*                           -
debug-d8f8956b7-9qw9f:~# ss -lntup
Netid               State                Recv-Q               Send-Q                             Local Address:Port                              Peer Address:Port               Process
udp                 UNCONN               0                    0                                      127.0.0.1:8600                                   0.0.0.0:*
tcp                 LISTEN               0                    4096                                   127.0.0.1:15001                                  0.0.0.0:*
tcp                 LISTEN               0                    4096                                   127.0.0.1:15001                                  0.0.0.0:*
tcp                 LISTEN               0                    4096                                  10.1.0.144:20000                                  0.0.0.0:*
tcp                 LISTEN               0                    4096                                  10.1.0.144:20000                                  0.0.0.0:*
tcp                 LISTEN               0                    4096                                   127.0.0.1:37735                                  0.0.0.0:*
tcp                 LISTEN               0                    4096                                   127.0.0.1:20600                                  0.0.0.0:*
tcp                 LISTEN               0                    4096                                   127.0.0.1:19000                                  0.0.0.0:*
tcp                 LISTEN               0                    4096                                   127.0.0.1:8600                                   0.0.0.0:*
```

These points prove transparent DNS redirection (see iptables section next):
* No listener on `:53`
* Listener on `:8600`
* `dig @127.0.0.1 -p 53` works
* `dig @127.0.0.1 -p 8600` works

That is only possible if:
```
53 → 8600
```

Final mental model (keep this)
```
Application
   ↓ DNS query
127.0.0.1:53
   ↓ (iptables / transparent proxy)
127.0.0.1:8600   ← Consul DNS
   ↓
Consul catalog
```

One-liner summary
> Transparent proxy rewrites DNS traffic from port 53 to Consul's DNS port 8600 — never the reverse.Transparent proxy rewrites DNS traffic from port 53 to Consul's DNS port 8600 — never the reverse.

- dig with consul-dns works - OK
```sh
debug-fbd67b496-8qs6b:~# dig @consul-dns.consul public-api.service.consul

; <<>> DiG 9.20.17 <<>> @consul-dns.consul public-api.service.consul
; (1 server found)
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 9388
;; flags: qr aa rd; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1
;; WARNING: recursion requested but not available

;; OPT PSEUDOSECTION:
; EDNS: version: 0, flags:; udp: 1232
;; QUESTION SECTION:
;public-api.service.consul.     IN      A

;; ANSWER SECTION:
public-api.service.consul. 0    IN      A       10.1.3.4

;; Query time: 0 msec
;; SERVER: 10.98.2.135#53(consul-dns.consul) (UDP)
;; WHEN: Fri Feb 27 12:23:18 UTC 2026
;; MSG SIZE  rcvd: 70
```

---
### iptables 

Prerequisites:
- enable privileged container (check `self/managed/debug/netshoot-deploy-connect-inject.md`)
```sh
$ kubectl -n debug -c netshoot exec -it deploy/debug -- bash

iptables -t nat -L -n -v
Chain PREROUTING (policy ACCEPT 0 packets, 0 bytes)
 pkts bytes target     prot opt in     out     source               destination
  120  7216 CONSUL_PROXY_INBOUND  tcp  --  *      *       0.0.0.0/0            0.0.0.0/0

Chain INPUT (policy ACCEPT 0 packets, 0 bytes)
 pkts bytes target     prot opt in     out     source               destination

Chain OUTPUT (policy ACCEPT 8 packets, 718 bytes)
 pkts bytes target     prot opt in     out     source               destination
    6   598 CONSUL_DNS_REDIRECT  udp  --  *      *       0.0.0.0/0            127.0.0.1            udp dpt:53
    0     0 CONSUL_DNS_REDIRECT  tcp  --  *      *       0.0.0.0/0            127.0.0.1            tcp dpt:53
    2   120 CONSUL_PROXY_OUTPUT  tcp  --  *      *       0.0.0.0/0            0.0.0.0/0

Chain POSTROUTING (policy ACCEPT 0 packets, 0 bytes)
 pkts bytes target     prot opt in     out     source               destination

Chain CONSUL_DNS_REDIRECT (2 references)
 pkts bytes target     prot opt in     out     source               destination
    6   598 DNAT       udp  --  *      *       0.0.0.0/0            127.0.0.1            udp dpt:53 to:127.0.0.1:8600
    0     0 DNAT       tcp  --  *      *       0.0.0.0/0            127.0.0.1            tcp dpt:53 to:127.0.0.1:8600

Chain CONSUL_PROXY_INBOUND (1 references)
 pkts bytes target     prot opt in     out     source               destination
  120  7216 CONSUL_PROXY_IN_REDIRECT  tcp  --  *      *       0.0.0.0/0            0.0.0.0/0

Chain CONSUL_PROXY_IN_REDIRECT (1 references)
 pkts bytes target     prot opt in     out     source               destination
  120  7216 REDIRECT   tcp  --  *      *       0.0.0.0/0            0.0.0.0/0            redir ports 20000

Chain CONSUL_PROXY_OUTPUT (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 RETURN     all  --  *      *       0.0.0.0/0            0.0.0.0/0            owner UID match 5996
    2   120 RETURN     all  --  *      *       0.0.0.0/0            0.0.0.0/0            owner UID match 5995
    0     0 RETURN     all  --  *      *       0.0.0.0/0            127.0.0.1
    0     0 CONSUL_PROXY_REDIRECT  all  --  *      *       0.0.0.0/0            0.0.0.0/0

Chain CONSUL_PROXY_REDIRECT (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 REDIRECT   tcp  --  *      *       0.0.0.0/0            0.0.0.0/0            redir ports 15001
```

1. DNS redirection: `127.0.0.1:53` → `127.0.0.1:8600`

`CONSUL_DNS_REDIRECT`

- check Consul DNS Redirect rule
```sh
Chain CONSUL_DNS_REDIRECT
DNAT udp ... udp dpt:53 to:127.0.0.1:8600
DNAT tcp ... tcp dpt:53 to:127.0.0.1:8600
|
v
Chain OUTPUT
CONSUL_DNS_REDIRECT udp ... destination 127.0.0.1 udp dpt:53
CONSUL_DNS_REDIRECT tcp ... destination 127.0.0.1 tcp dpt:53
```
Meaning:
- Your app thinks it is querying DNS at `127.0.0.1:53`
- iptables rewrites that to `127.0.0.1:8600`
- That's why `dig @127.0.0.1` (port 53 default) works even though nothing is "listening" on 53 in ss

The counters confirm it's being used:
- 6 packets / 598 bytes on UDP rule (DNS is usually UDP)
- 0 packets TCP (normal unless responses are large/DNSSEC/etc.)

2. Inbound traffic interception: redirect all inbound TCP to port 20000
```sh
PREROUTING → CONSUL_PROXY_INBOUND
CONSUL_PROXY_INBOUND → CONSUL_PROXY_IN_REDIRECT
CONSUL_PROXY_IN_REDIRECT → REDIRECT ... redir ports 20000

# PREROUTING
#    → CONSUL_PROXY_INBOUND
# CONSUL_PROXY_INBOUND
#    → CONSUL_PROXY_IN_REDIRECT
# CONSUL_PROXY_IN_REDIRECT
#    → REDIRECT tcp → port 20000
```
Specifically:
```sh
Chain CONSUL_PROXY_IN_REDIRECT
REDIRECT tcp ... redir ports 20000
```
Meaning:
- Any TCP connection coming into the pod (to any destination port) is transparently redirected to local port 20000
- Port 20000 is the inbound listener for the Consul dataplane/Envoy in your setup
- Envoy then decides where it should go based on service mesh config (intentions, upstreams, mTLS, etc.)

Counters show it's actively used:
- 120 packets / 7216 bytes

3. Outbound traffic interception: redirect outbound TCP to Envoy on 15001 (with exceptions)
This is the classic "transparent proxy" for outgoing connections:
```sh
Chain CONSUL_PROXY_REDIRECT
REDIRECT tcp ... redir ports 15001
```

And it's applied from `OUTPUT` via `CONSUL_PROXY_OUTPUT`:
```sh
Chain OUTPUT
CONSUL_PROXY_OUTPUT tcp ...
```

Inside CONSUL_PROXY_OUTPUT you see exclusions first:
```sh
RETURN ... owner UID match 5996
RETURN ... owner UID match 5995
RETURN ... destination 127.0.0.1
```

Then
```sh
CONSUL_PROXY_REDIRECT ... (catch-all)
```

**Meaning:**
- Most outbound TCP is redirected to 15001 (Envoy outbound listener)
- But traffic is not redirected if:
   * it's created by Envoy/Consul processes themselves (UID 5995/5996) → avoids loops
   * it's to 127.0.0.1 → avoid breaking localhost calls

Your counters show outbound redirect hasn't triggered much yet (0 packets on the final redirect), while the earlier OUTPUT has only a couple of packets. That's normal in a "sleep" debug pod unless you actually make outbound TCP calls (curl to a service, etc.).

### Putting it all together: what transparent proxy means in your pod

#### DNS path
- App sends DNS to 127.0.0.1:53
- iptables DNAT → 127.0.0.1:8600 (Consul DNS)
- Consul answers .consul names

#### Inbound network path

- Any inbound TCP to the pod → redirected to 20000 (Envoy inbound)

#### Outbound network path

- Any outbound TCP from the app → redirected to 15001 (Envoy outbound)
- Except for Envoy/Consul itself and localhost

That is literally "transparent proxy"

#### Quick experiments you can do to "see it working"

- Prove outbound interception increments counters
```sh
# curl public-api service
kubectl -n demo get svc public-api -o jsonpath='{.spec.clusterIP}'
10.98.3.231

# curl -sS http://10.98.3.231
debug-fbd67b496-svgzz:~# curl -sS -o /dev/null -s -w "%{http_code}\n" http://10.98.3.231
200
debug-fbd67b496-svgzz:~# curl -sS -o /dev/null -s -w "%{http_code}\n" public-api.demo
200

# You should see packet counters increase
debug-fbd67b496-svgzz:~# iptables -t nat -L CONSUL_PROXY_REDIRECT -n -v
Chain CONSUL_PROXY_REDIRECT (1 references)
 pkts bytes target     prot opt in     out     source               destination
    2   120 REDIRECT   tcp  --  *      *       0.0.0.0/0            0.0.0.0/0            redir ports 15001
debug-fbd67b496-svgzz:~# iptables -t nat -L CONSUL_PROXY_OUTPUT -n -v
Chain CONSUL_PROXY_OUTPUT (1 references)
 pkts bytes target     prot opt in     out     source               destination
    0     0 RETURN     all  --  *      *       0.0.0.0/0            0.0.0.0/0            owner UID match 5996
    4   240 RETURN     all  --  *      *       0.0.0.0/0            0.0.0.0/0            owner UID match 5995
    0     0 RETURN     all  --  *      *       0.0.0.0/0            127.0.0.1
    2   120 CONSUL_PROXY_REDIRECT  all  --  *      *       0.0.0.0/0            0.0.0.0/0 # <---
```

- Test Inbound traffic interception (???)
```sh
# inside debug consul-injected pod (packets counter should increase in realtime)
watch -n 1 'iptables -t nat -L CONSUL_PROXY_IN_REDIRECT -n -v'
```

from the client pod (consul-injected=false)
```sh
# debug privileged pod IP (consul-inject=true) - OK
client-bbd6cc9fd-t8l59:~# nc -vz 10.1.0.160 12345
Connection to 10.1.0.160 12345 port [tcp/*] succeeded!

# debug service - NOK
client-bbd6cc9fd-t8l59:~# nc -vz debug.debug.svc.cluster.local 12345
```

**NOTE**: if you connect to `demo/public-api` pod from the *client* pod,
your requests will be ok, but the packets counter in the debug pod (consul-inject=true) WILL NOT increase

```sh
# demo/public-api pod IP (consul-inject=true) - OK
client-bbd6cc9fd-t8l59:~# nc -vz 10.1.0.149 12345
Connection to 10.1.0.149 12345 port [tcp/*] succeeded!
```

- Prove DNS is going through the DNAT rule (check `pkts`)
```sh
debug-fbd67b496-svgzz:~# iptables -t nat -L CONSUL_DNS_REDIRECT -n -v
Chain CONSUL_DNS_REDIRECT (2 references)
 pkts bytes target     prot opt in     out     source               destination
    9   880 DNAT       udp  --  *      *       0.0.0.0/0            127.0.0.1            udp dpt:53 to:127.0.0.1:8600 # <---
    0     0 DNAT       tcp  --  *      *       0.0.0.0/0            127.0.0.1            tcp dpt:53 to:127.0.0.1:8600

debug-fbd67b496-svgzz:~# dig public-api.service.consul.
...
public-api.service.consul. 0    IN      A       10.1.0.149
...

debug-fbd67b496-svgzz:~# iptables -t nat -L CONSUL_DNS_REDIRECT -n -v
Chain CONSUL_DNS_REDIRECT (2 references)
 pkts bytes target     prot opt in     out     source               destination
   10   974 DNAT       udp  --  *      *       0.0.0.0/0            127.0.0.1            udp dpt:53 to:127.0.0.1:8600 # <---
    0     0 DNAT       tcp  --  *      *       0.0.0.0/0            127.0.0.1            tcp dpt:53 to:127.0.0.1:8600
```

---

## kube-system/coredns tweaks
To make this kind of requests work `nslookup public-api.service.consul`, Add this block to CoreDNS configmap
```
consul:53 {
    errors
    cache 30
    forward . 10.111.33.219:53
}
```

- edit coredns configmap
```sh
kubectl -n consul get svc consul-dns -o jsonpath='{.spec.clusterIP}'
10.111.33.219

kubectl -n kube-system edit configmap coredns
```

```
# configmap: kube-system/coredns
.:53 {
    errors
    health {
       lameduck 5s
    }
    ready
    kubernetes cluster.local in-addr.arpa ip6.arpa {
       pods insecure
       fallthrough in-addr.arpa ip6.arpa
       ttl 30
    }
    prometheus :9153
    forward . /etc/resolv.conf {
       max_concurrent 1000
    }
    cache 30 {
       disable success cluster.local
       disable denial cluster.local
    }
    loop
    reload
    loadbalance
}

consul:53 {
    errors
    cache 30
    forward . 10.111.33.219:53
}
```
- restart coredns
```sh
kubectl -n kube-system rollout restart deploy/coredns
```

- test nslookup
```sh
debug-fbd67b496-svgzz:~# nslookup public-api.service.consul
...
;; Got recursion not available from 127.0.0.1, trying next server
;; Got recursion not available from 10.96.0.10
Server:         10.96.0.10
Address:        10.96.0.10#53

Name:   public-api.service.consul
Address: 10.1.0.172
;; Got recursion not available from 127.0.0.1, trying next server
;; Got recursion not available from 10.96.0.10
```

- curl get requests keeps failing
```sh
debug-fbd67b496-svgzz:~# curl public-api.service.consul
curl: (52) Empty reply from server

debug-fbd67b496-svgzz:~# curl -v http://public-api.service.consul:8080
* Host public-api.service.consul:8080 was resolved.
* IPv6: (none)
* IPv4: 10.1.0.172
*   Trying 10.1.0.172:8080...
* Established connection to public-api.service.consul (10.1.0.172 port 8080) from 10.1.0.182 port 34834
* using HTTP/1.x
> GET / HTTP/1.1
> Host: public-api.service.consul:8080
> User-Agent: curl/8.18.0
> Accept: */*
>
* Request completely sent off
* Empty reply from server
* shutting down connection #0
curl: (52) Empty reply from server
```


## MISC

It looks like Consul DNS is running (you have svc/consul-dns), but CoreDNS doesn't have a .consul stub domain configured yet. I'll show how to add it and test.
- Get the Consul DNS ClusterIP:
$CONSUL_DNS_IP = kubectl -n consul get svc consul-dns -o jsonpath='{.spec.clusterIP}
$CONSUL_DNS_IP
- Edit CoreDNS Corefile and add a consul:53 block that forwards to that IP on port 53:
kubectl -n kube-system edit configmap coredns
- Add this block alongside the existing .:53 block (replace the IP if you didn't capture it above):
consul:53 {
    errors
    cache 30
    forward . 10.111.33.219:53
}

- Restart CoreDNS:
kubectl -n kube-system rollout restart deploy/corednskubectl -n kube-system rollout status deploy/coredns

- Test resolution from a pod:
kubectl run -it --rm dns-test --image=busybox:1.36 --restart=Never -- sh -c "  nslookup kubernetes.service.consul || true; nslookup <your-service>.service.consul || true"

If those lookups succeed, .consul DNS is enabled cluster-wide.
I reviewed your output; consul-dns exists but the CoreDNS Corefile lacks a consul:53 stub. I provided the exact edit, restart, and a quick test to confirm resolution.



access NodePort service

root@DESKTOP-FOI15CP:/mnt/c/Users/robez# kubectl describe svc consul-ui -n consul
Name:                     consul-ui
Namespace:                consul
Labels:                   app=consul
                          app.kubernetes.io/managed-by=Helm
                          chart=consul-helm
                          component=ui
                          heritage=Helm
                          release=consul
Annotations:              meta.helm.sh/release-name: consul
                          meta.helm.sh/release-namespace: consul
Selector:                 app=consul,component=server,release=consul
Type:                     NodePort
IP Family Policy:         SingleStack
IP Families:              IPv4
IP:                       10.106.138.31
IPs:                      10.106.138.31
Port:                     https  443/TCP
TargetPort:               8501/TCP
NodePort:                 https  30349/TCP
Endpoints:                10.1.0.135:8501
Session Affinity:         None
External Traffic Policy:  Cluster
Internal Traffic Policy:  Cluster
Events:                   <none>

curl -k -L https://localhost:30349

or openbrowser at https://localhost:30349

---
