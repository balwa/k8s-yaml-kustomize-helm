# Lab 1: Anatomy of a Kubernetes object (45 min)

## Learning objectives

By the end of this lab you can:

1. Explain what `apiVersion`, `kind`, `metadata`, `spec` and `status` are for, and which
   of them **you** write and which ones the **cluster** writes.
2. Write a manifest for a resource you've never seen before, using only `kubectl explain`.
3. Trace how **labels and selectors** connect a Deployment, its Pods and a Service, and
   debug a Service that has no endpoints.
4. Check a change before applying it with `--dry-run=server` and `kubectl diff`.

## The big idea: a manifest is an API request

When you run `kubectl apply -f web.yaml`, kubectl turns your YAML into JSON and sends it to
the API server, for example as an HTTP `POST` to `/apis/apps/v1/namespaces/lab1/deployments`.
**The YAML file is the body of that request.** That's why the file has to follow a schema:
you're calling an API.

Every Kubernetes object has the same outline:

```yaml
apiVersion: apps/v1     # WHICH API: group "apps", version "v1"
kind: Deployment        # WHICH TYPE in that API
metadata:               # WHO it is: name, namespace, labels, annotations
  name: web
spec:                   # WHAT YOU WANT  <- you write this
  ...
status:                 # WHAT IS TRUE NOW <- the cluster writes this, you never do
  ...
```

> **Analogy: an online order.** `apiVersion` + `kind` is the store and the product type.
> `metadata` is the label on the box (order number, name). `spec` is what you ordered:
> "3 replicas of podinfo 6.15.0". `status` is the tracking page: "2 of 3 delivered".
> You fill in the order. Only the store updates the tracking page. The whole job of
> Kubernetes is to keep moving `status` toward `spec`.

## Setup

```bash
cd ~/workshop/lab-1-anatomy-of-a-k8s-object
kubectl create namespace lab1
kubectl config set-context --current --namespace=lab1   # makes lab1 the default for this lab
```

---

## Task 1: Discover the API (5 min)

Your cluster can tell you every kind of object it knows about:

```bash
kubectl api-resources
```

Find the rows for `pods`, `services`, `deployments` and `configmaps`:

```text
NAME          SHORTNAMES   APIVERSION   NAMESPACED   KIND
configmaps    cm           v1           true         ConfigMap
pods          po           v1           true         Pod
services      svc          v1           true         Service
deployments   deploy       apps/v1      true         Deployment
```

**Answer before moving on:**

* Why is a Pod `v1` but a Deployment `apps/v1`? (Hint: Pods are part of the original
  **core** API. Deployments came later in a named **group**, `apps`.)
* `NAMESPACED` is `false` for `nodes` and `namespaces`. Why does that make sense?
* What would `kubectl get deploy` do? (Try it. Shortnames save a lot of typing.)

---

## Task 2: Write a Pod using only `kubectl explain` (10 min)

`kubectl explain` is the built-in documentation for the schema, read from **your** cluster,
so it always matches your version. Learn to navigate it like a file system:

```bash
kubectl explain pod                          # top-level fields
kubectl explain pod.spec                     # what goes in spec?
kubectl explain pod.spec.containers          # note the type: <[]Container> means LIST of Container
kubectl explain pod.spec.containers.env      # <[]EnvVar> is another list
kubectl explain pod.spec.containers.ports.containerPort   # <integer> -required-
```

How to read the types:

| `explain` says | In YAML you write |
|----------------|-------------------|
| `<string>` | `name: web` (quote it if it looks like a number or a bool) |
| `<integer>` / `<boolean>` | `replicas: 3` / `stdin: true` (no quotes) |
| `<Object>` or `<SomeType>` | a nested map, indented one level |
| `<[]SomeType>` | a list: each item starts with `- ` |
| `<map[string]string>` | a nested map whose values are all strings (labels, ConfigMap data) |
| `-required-` | leave this out and the API server rejects the object |

**Your task:** without copying from anywhere, create `pod.yaml` for a Pod that:

* is named `hello` and has the label `app: hello`
* runs one container named `podinfo` with image `ghcr.io/stefanprodan/podinfo:6.15.0`
* exposes container port `9898`
* sets env var `PODINFO_UI_MESSAGE` to `Hello from a hand-written Pod`

Validate it **before** creating it. `--dry-run=server` sends the object to the API server,
which runs every check and then throws the object away:

```bash
kubectl apply --dry-run=server -f pod.yaml
# pod/hello created (server dry run)

kubectl apply -f pod.yaml
kubectl get pod hello
# NAME    READY   STATUS    RESTARTS   AGE
# hello   1/1     Running   0          10s
```

### Break it: misspell a field

Change `containerPort` to `containerport` (lower-case p) and dry-run again:

```text
Error from server (BadRequest): error when creating "pod.yaml": Pod in version "v1" cannot be
handled as a Pod: strict decoding error: unknown field "spec.containers[0].ports[0].containerport"
```

The API server rejects fields it doesn't know. Field names are **case-sensitive**. Fix it.

---

## Task 3: You write `spec`, the cluster writes everything else (5 min)

Now ask the cluster for the Pod you created:

```bash
kubectl get pod hello -o yaml
```

Compare that with your `pod.yaml`. Your file is about 15 lines. The server's copy is much longer.
Find these in the output:

| Field | Who added it, and why |
|-------|----------------------|
| `metadata.uid`, `metadata.creationTimestamp`, `metadata.resourceVersion` | API server: identity and versioning |
| `metadata.namespace: lab1` | API server: from your current context |
| `spec.restartPolicy: Always`, `spec.dnsPolicy`, `terminationGracePeriodSeconds` | API server **defaults**: you didn't set them, so you got the standard values |
| `spec.nodeName` | The **scheduler**: it chose a worker for the Pod |
| `status.phase`, `status.podIP`, `status.conditions` | The **kubelet** on that node, reporting what is actually happening |

**Lesson:** you declare the *minimum* you care about, and the system fills in the rest.
That's also why you should **never** copy the output of `kubectl get -o yaml` back into
Git as-is: it's full of fields that belong to the server.

### Break it: try to change a running Pod

Add `restartPolicy: Never` under `spec:` in your `pod.yaml` and apply:

```text
The Pod "hello" is invalid: spec: Forbidden: pod updates may not change fields other than
`spec.containers[*].image`, ...
```

Most of a Pod's spec is **immutable**. To change a Pod, you replace it. That's one reason
we almost never create bare Pods and use a **Deployment** instead: it replaces Pods for us.

```bash
kubectl delete pod hello
```

---

## Task 4: Generate YAML, don't type it all (8 min)

Typing every manifest from scratch is slow and easy to get wrong. kubectl can **generate**
a starting point without creating anything:

```bash
kubectl create deployment web \
  --image=ghcr.io/stefanprodan/podinfo:6.15.0 \
  --replicas=2 --port=9898 \
  --dry-run=client -o yaml > web.yaml

cat web.yaml
```

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: web
  name: web
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web
  strategy: {}
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - image: ghcr.io/stefanprodan/podinfo:6.15.0
        name: podinfo
        ports:
        - containerPort: 9898
        resources: {}
status: {}
```

Clean it up:

1. Delete the noise: `strategy: {}`, `resources: {}`, `status: {}`, and
   `creationTimestamp: null` if your kubectl version adds it.
2. Add the `PODINFO_UI_MESSAGE` env var with the value `Hello from a Deployment`.

> **Notice the list style.** kubectl writes `- image:` at the **same** indent as
> `containers:`. In Lab 0 we indented it two more spaces. **Both are valid YAML.** What
> matters is that every key in one list item lines up. Pick one style per file and stick to it.

Now generate the Service and **append** it to the same file, with `---` in between:

```bash
echo '---' >> web.yaml
kubectl create service nodeport web --tcp=80:9898 --dry-run=client -o yaml >> web.yaml
```

Clean up the Service part too: delete `status:` / `loadBalancer: {}`, and delete the
generated `name: 80-9898` port name if you like.

Apply both objects with one command, then reach the app:

```bash
kubectl apply --dry-run=server -f web.yaml
kubectl apply -f web.yaml
kubectl get deploy,pods,svc

NODE_PORT=$(kubectl get svc web -o jsonpath='{.spec.ports[0].nodePort}')
curl -s http://$NODE_IP:$NODE_PORT/ | grep -E 'hostname|message'
#   "hostname": "web-7c9d8b6f5-abcde",
#   "message": "Hello from a Deployment",
```

Run the `curl` a few times. The `hostname` changes: the Service is spreading requests
across both Pods.

---

## Task 5: Labels are the glue (10 min)

Nothing in Kubernetes refers to another object by a hard link. **Labels and selectors**
connect everything:

```
  Deployment "web"                          Service "web"
  selector: app=web ──────┐       ┌──────── selector: app=web
                          ▼       ▼
                 ┌─────────────────────────┐
                 │ Pod  labels: app=web    │   x2
                 └─────────────────────────┘
       "these Pods are mine"       "send traffic to these Pods"
```

See the glue directly:

```bash
kubectl get pods --show-labels
kubectl get pods -l app=web                        # filter by label, like the Service does
kubectl get endpointslices -l kubernetes.io/service-name=web
# NAME        ADDRESSTYPE   PORTS   ENDPOINTS                 AGE
# web-xxxxx   IPv4          9898    10.244.1.5,10.244.2.7     2m
```

### Break it: a typo in the Service selector

In `web.yaml`, change **only the Service's** selector to `app: webb`. Apply, then:

```bash
kubectl apply -f web.yaml
kubectl get endpointslices -l kubernetes.io/service-name=web
# ENDPOINTS: <unset>          <- no Pods match "app=webb"
curl -s --max-time 3 http://$NODE_IP:$NODE_PORT/ || echo "no response"
```

There's no error anywhere. `apply` worked, the Pods are `Running`, and the app still
doesn't answer. **This is the most common Kubernetes bug you'll ever debug.** Remember
the check: *does the Service have endpoints?* Fix the typo and confirm the endpoints come back.

### Break it: change the Deployment's selector

Now change the Deployment's `selector.matchLabels` **and** the template labels to `app: web2`
and apply:

```text
The Deployment "web" is invalid: spec.selector: Invalid value: ...: field is immutable
```

A Deployment's selector can't change after creation. If it could, the Deployment would
suddenly "forget" the Pods it owns. Remember this one: it comes back in Lab 3. Undo the change.

---

## Task 6: Preview changes with `kubectl diff` (5 min)

Change `replicas: 2` to `replicas: 3` and the message to `Hello v2`. **Don't apply yet.**

```bash
kubectl diff -f web.yaml
```

```diff
-  generation: 1
+  generation: 2
...
-  replicas: 2
+  replicas: 3
...
-              value: Hello from a Deployment
+              value: Hello v2
```

`kubectl diff` shows what *would* change on the live object, like `git diff` for your
cluster. Use it before every `apply` from now on. Apply when you're happy with the diff.

### Checkpoint

```bash
kubectl get deploy web
# NAME   READY   UP-TO-DATE   AVAILABLE   AGE
# web    3/3     3            3           8m
curl -s http://$NODE_IP:$NODE_PORT/ | grep message
#   "message": "Hello v2",
```

Reference answers: [`solutions/lab-1/`](../solutions/lab-1/).

## Clean up

```bash
kubectl delete namespace lab1
kubectl config set-context --current --namespace=default
```

## Reflection questions

1. In your own words: what is the difference between `spec` and `status`? Who writes each one?
2. You `apply` a Service and get no errors, but `curl` hangs. List the first three things
   you would check, in order.
3. Why does the Deployment's Pod template have `metadata.labels` but no `apiVersion` or `kind`?
4. `--dry-run=client` and `--dry-run=server`: which one would have caught the
   `containerport` typo? Why?
5. Look at your final `web.yaml`. Which values would probably be **different** if you ran
   this same app for a "dev" team and a "prod" team? (Keep this list. It's the start of Lab 2.)
