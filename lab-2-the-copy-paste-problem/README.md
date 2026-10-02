# Lab 2: The copy-paste problem (30 min)

## Learning objectives

By the end of this lab you can:

1. Deploy the same app to two environments by copying YAML, and explain why that doesn't scale.
2. Show that a NodePort is a **cluster-wide** resource, not a per-namespace one.
3. Explain, with examples you produced yourself, why **plain text substitution** (`envsubst`, `sed`)
   is a dangerous way to template YAML.

## The story

Your podinfo app from Lab 1 is a hit. Two teams now want their own copy:

| Setting           | **dev** team        | **prod** team                          |
|-------------------|---------------------|----------------------------------------|
| Namespace         | `copy-dev`          | `copy-prod`                            |
| Replicas          | 1                   | 3                                      |
| Image tag         | `6.15.0` (latest)   | `6.14.0` (prod runs last month's release) |
| Message           | `Hello from DEV`    | `Hello from PROD`                      |
| Color             | `#ff8800`           | `#2e7d32`                              |
| NodePort          | 30081               | 30082                                  |

The starting manifests are in [`app/`](app/). Read them first. They're the same as
Lab 1, plus a color env var and a **fixed** `nodePort: 30080`.

```bash
cd ~/workshop/lab-2-the-copy-paste-problem
cat app/deployment.yaml app/service.yaml
```

---

## Part A: Two environments by copy-paste (12 min)

### A1: Just deploy it twice?

Before editing anything, try deploying the **same files** to both namespaces:

```bash
kubectl create namespace copy-dev
kubectl create namespace copy-prod
kubectl apply -n copy-dev  -f app/
kubectl apply -n copy-prod -f app/
```

```text
deployment.apps/web created
service/web created
deployment.apps/web created
The Service "web" is invalid: spec.ports[0].nodePort: Invalid value: 30080: provided port is already allocated
```

**Stop and think:** the Deployment worked in both namespaces. The Service didn't. Why?

<details>
<summary>Answer</summary>

Names (`web`) only have to be unique **inside a namespace**, so two Deployments called
`web` are fine. A NodePort opens a port on **every node in the cluster**, and a node only
has one port 30080. NodePorts are a **cluster-wide** resource that namespaces don't isolate.
</details>

### A2: Copy and edit

```bash
cp -r app dev
cp -r app prod
```

Now edit `dev/*.yaml` and `prod/*.yaml` by hand so they match the table above. That's
replicas, image tag, message, color and nodePort, in two files per environment. Then apply:

```bash
kubectl apply -n copy-dev  -f dev/
kubectl apply -n copy-prod -f prod/

curl -s http://$NODE_IP:30081/ | grep -E 'version|message|color'
curl -s http://$NODE_IP:30082/ | grep -E 'version|message|color'
```

### Checkpoint

```text
# :30081 (dev)
  "version": "6.15.0",
  "color": "#ff8800",
  "message": "Hello from DEV",
# :30082 (prod)
  "version": "6.14.0",
  "color": "#2e7d32",
  "message": "Hello from PROD",
```

---

## Part B: The change request (8 min)

A message arrives from the platform team:

> **Starting today, every container must have:**
> * a readiness probe: HTTP GET `/readyz` on port `9898`
> * resource requests `cpu: 50m`, `memory: 64Mi`, and a memory limit of `128Mi`

Use `kubectl explain deployment.spec.template.spec.containers.readinessProbe` and
`...containers.resources` to work out the YAML. Add it to **both** `dev/deployment.yaml`
and `prod/deployment.yaml`, then use `kubectl diff` and apply both.

Now measure the duplication:

```bash
diff -u dev/deployment.yaml prod/deployment.yaml
wc -l dev/*.yaml
```

About 5 lines out of about 55 are different between dev and prod. **Over 90% of what you
maintain is duplicated.**

### Thought experiment (discuss with your neighbour)

A real company has **12 microservices × 3 environments (dev, staging, prod)**.

1. How many YAML files is that, at 2 files per service?
2. The platform team sends a change request like the one above. How many files do you edit?
3. Someone forgets **one** of them. How would you notice? When?
4. What do you call it when two copies that should match slowly stop matching?
   *(This is called **configuration drift**.)*

---

## Part C: "I'll just write a template!" (10 min)

The obvious fix: keep **one** file with placeholders, and fill them in per environment.
Linux already has a tool for this: `envsubst` replaces `${VAR}` with the value of an
environment variable. Look at [`envsubst/deployment.tmpl.yaml`](envsubst/deployment.tmpl.yaml).

```bash
kubectl create namespace copy-tmpl

REPLICAS=2 IMAGE_TAG=6.15.0 MESSAGE=Templated COLOR='#0000ff' \
  envsubst < envsubst/deployment.tmpl.yaml
```

Read the output. It looks right. Dry-run it:

```bash
REPLICAS=2 IMAGE_TAG=6.15.0 MESSAGE=Templated COLOR='#0000ff' \
  envsubst < envsubst/deployment.tmpl.yaml | kubectl apply -n copy-tmpl --dry-run=server -f -
# deployment.apps/web created (server dry run)
```

Problem solved? **Break it four ways.** For each one, predict what will happen *before*
you run it, then dry-run it:

| # | Try this | What actually happens |
|---|----------|-----------------------|
| 1 | Forget a variable: run **without** `REPLICAS=2` | |
| 2 | `MESSAGE='Status: ready'` | |
| 3 | `MESSAGE=2026` (or `MESSAGE=yes`) | |
| 4 | Forget `IMAGE_TAG` | |

To see the replica count the server *would* create for #1:

```bash
IMAGE_TAG=6.15.0 MESSAGE=hi COLOR=red envsubst < envsubst/deployment.tmpl.yaml \
  | kubectl apply -n copy-tmpl --dry-run=server -o jsonpath='{.spec.replicas}{"\n"}' -f -
```

<details>
<summary>What you should have seen</summary>

| # | Result | Why |
|---|--------|-----|
| 1 | **No error.** 1 replica. | `replicas:` with nothing after it is `null`, and the API server **defaults** null to 1. Prod quietly runs on one Pod. This is the worst of the four because nothing tells you. |
| 2 | `yaml: line 25: mapping values are not allowed in this context` | The output line became `value: Status: ready`. The second `: ` looks like the start of a new map to the YAML parser. |
| 3 | `cannot unmarshal number into Go struct field EnvVar...value of type string` (or `bool` for `yes`) | Lab 0 again. `value: 2026` is a number, not a string. |
| 4 | `yaml: line 20: mapping values are not allowed in this context` | `image: ghcr.io/stefanprodan/podinfo:` ends in a colon, so YAML reads it as a key. |

"Just put quotes around `${MESSAGE}`!" fixes #2 and #3. Then try `MESSAGE='She said "hi"'`.
</details>

### The lesson

`envsubst` and `sed` work on **text**. They don't know what YAML is, so they can't:

* quote a value correctly for its type
* fail loudly when a value is missing, or fill in a sensible default
* add a block (like a `nodePort:` line) **only** for some environments
* loop: "one env var per entry in this list"

There are two well-known ways out, and they take opposite approaches:

| Approach | Idea | Tool | Lab |
|----------|------|------|-----|
| **Patch structured data** | Keep plain, valid YAML. Describe each environment as a set of *changes* to that YAML. No placeholders at all. | **Kustomize** (built into `kubectl`) | Lab 3 |
| **Use a real template language** | Placeholders, but with types, functions (`quote`, `default`, `required`), `if` and `range`. Also adds packaging and release history. | **Helm** | Lab 4 |

Reference answers for Part A/B: [`solutions/lab-2/`](../solutions/lab-2/).

## Clean up

```bash
kubectl delete namespace copy-dev copy-prod copy-tmpl
```

## Reflection questions

1. In Part B, which was harder: making the change, or being *sure* you made it everywhere?
2. Envsubst failure #1 produced no error at all. Why is that more dangerous than #2–#4?
3. Look at the table at the top of this lab. Which settings are **per-environment** and
   which are **the same everywhere**? How could you store them so the shared part exists only once?
4. Write down one more way homemade templating could go wrong that we didn't try.
