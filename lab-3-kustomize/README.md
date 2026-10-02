# Lab 3: Kustomize (55 min)

## Learning objectives

By the end of this lab you can:

1. Organise an app as a **base** plus per-environment **overlays**, and render and apply it with
   `kubectl kustomize` / `kubectl apply -k`.
2. Use the built-in transformers (`namespace`, `replicas`, `images`, `labels`) and both kinds
   of patch (strategic merge and JSON 6902).
3. Explain why `configMapGenerator` adds a hash to the ConfigMap name, and show that a config
   change triggers a rolling update.

## The idea: patch the YAML, don't template it

Lab 2 showed that text placeholders (`${MESSAGE}`) break in many ways. Kustomize takes the
opposite approach:

* The **base** is plain, valid Kubernetes YAML. It has no placeholders, and you could
  `kubectl apply -f` it as-is.
* An **overlay** says "take that base and change *these* things". Kustomize understands the
  YAML structure, so it knows that `containers` is a list keyed by `name`, that `image`
  has a tag, and that a ConfigMap is referenced from a Deployment.

```
                ┌────────────────────────┐
                │ base/                  │  plain YAML: what's the SAME everywhere
                │   deployment.yaml      │
                │   service.yaml         │
                │   kustomization.yaml   │
                └───────────┬────────────┘
              ┌─────────────┴─────────────┐
   ┌──────────▼───────────┐    ┌──────────▼───────────┐
   │ overlays/dev/        │    │ overlays/prod/       │  only the DIFFERENCES
   │   kustomization.yaml │    │   kustomization.yaml │
   └──────────┬───────────┘    │   patch-memory.yaml  │
              │                └──────────┬───────────┘
              ▼                           ▼
     kubectl apply -k overlays/dev   kubectl apply -k overlays/prod
```

> **Analogy:** the base is the master copy of a course syllabus. Each section's instructor
> doesn't rewrite the syllabus. They hand out a one-page **addendum**: "our section meets
> in room B-12, and the project is due a week later." Kustomize applies the addendum for you.

Kustomize is **built into kubectl**, so there's nothing to install:

```bash
kubectl version --client     # look for "Kustomize Version: v5.x"
```

## Setup

```bash
cd ~/workshop/lab-3-kustomize
mkdir -p base overlays/dev overlays/prod
cp ../lab-2-the-copy-paste-problem/app/*.yaml base/
kubectl create namespace kz-dev
kubectl create namespace kz-prod
```

---

## Task 1: The base (5 min)

1. Open `base/service.yaml` and **delete the `nodePort: 30080` line**. Lab 2 showed that a
   fixed NodePort can't be shared between environments, so the base shouldn't pin one.
2. Create `base/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - deployment.yaml
  - service.yaml
```

Render it. This **prints** the final YAML and creates nothing:

```bash
kubectl kustomize base
```

The output is your two files joined with `---`, with the keys sorted. Nothing else has
changed yet.

> `kustomization.yaml` looks like a Kubernetes object (it has `apiVersion` and `kind`), but it
> **never goes to the cluster**. It's a set of instructions that kubectl reads on your machine.

---

## Task 2: Two overlays (10 min)

Create `overlays/dev/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: kz-dev            # set metadata.namespace on every object

resources:
  - ../../base               # start from the base (a directory path)

replicas:                    # change spec.replicas of the Deployment named "web"
  - name: web
    count: 1

images:                      # change the tag of every container using this image
  - name: ghcr.io/stefanprodan/podinfo
    newTag: "6.15.0"
```

Now write `overlays/prod/kustomization.yaml` **yourself**: namespace `kz-prod`, 3 replicas,
tag `6.14.0`.

Render both and compare:

```bash
kubectl kustomize overlays/dev
kubectl kustomize overlays/prod
diff <(kubectl kustomize overlays/dev) <(kubectl kustomize overlays/prod)
```

### Checkpoint

The diff shows **only** the namespace, the replica count and the image tag. Compare that with
the `diff` you ran in Lab 2.

> **Why `newTag: "6.15.0"` in quotes?** Lab 0: without quotes, YAML can read a value that
> looks like a number as a float. A tag like `1.10` would become `1.1`. Tags are strings, so quote them.

---

## Task 3: Diff and apply (5 min)

`kubectl diff` and `kubectl apply` take `-k <dir>` instead of `-f <file>`:

```bash
kubectl diff  -k overlays/dev        # everything shows as new
kubectl apply -k overlays/dev
kubectl apply -k overlays/prod

kubectl get deploy,svc -n kz-dev
kubectl get deploy,svc -n kz-prod
```

Find the auto-assigned NodePorts and curl them:

```bash
DEV_PORT=$(kubectl get svc web -n kz-dev  -o jsonpath='{.spec.ports[0].nodePort}')
PROD_PORT=$(kubectl get svc web -n kz-prod -o jsonpath='{.spec.ports[0].nodePort}')
curl -s http://$NODE_IP:$DEV_PORT/  | grep version     # "6.15.0"
curl -s http://$NODE_IP:$PROD_PORT/ | grep version     # "6.14.0"
```

---

## Task 4: The change request, again (5 min)

The platform team's request from Lab 2 is back: **readiness probe on `/readyz:9898`, requests
`cpu: 50m`/`memory: 64Mi`, memory limit `128Mi`**.

This time, edit **one file**: `base/deployment.yaml`. Then:

```bash
kubectl diff -k overlays/dev
kubectl diff -k overlays/prod       # both environments get it automatically
kubectl apply -k overlays/dev
kubectl apply -k overlays/prod
```

That's the payoff. In Lab 2 this took two edits and some hoping. With 12 services × 3
environments it would still be **one edit per service**, not three.

---

## Task 5: Patches, for anything there is no shortcut for (10 min)

`replicas` and `images` are shortcuts for common changes. For everything else you use a
**patch**. There are two kinds.

### 5a: Strategic merge patch: "a partial object that gets merged in"

Prod needs a bigger memory limit (`256Mi`). Create `overlays/prod/patch-memory.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web                    # which object to patch
spec:
  template:
    spec:
      containers:
        - name: podinfo        # which container (lists are matched by name)
          resources:
            limits:
              memory: 256Mi    # the only value that changes
```

Reference it from `overlays/prod/kustomization.yaml`:

```yaml
patches:
  - path: patch-memory.yaml
```

```bash
kubectl kustomize overlays/prod | grep -A6 resources:
```

Notice what you **didn't** have to repeat: the image, the ports, the probe, and the
`requests`. Kustomize merged your snippet into the base by matching on structure.

### 5b: JSON patch: "precise operations on a path"

We want prod on a **fixed** NodePort (30082) so the team can bookmark it. The port is the
first item of a list, so a JSON patch, which addresses fields by path, is a good fit. Add a
second entry under `patches:`:

```yaml
  - target:
      kind: Service
      name: web
    patch: |-
      - op: add
        path: /spec/ports/0/nodePort
        value: 30082
```

```bash
kubectl diff  -k overlays/prod
kubectl apply -k overlays/prod
curl -s http://$NODE_IP:30082/ | grep version
```

| | Strategic merge patch | JSON 6902 patch |
|---|---|---|
| Looks like | A small piece of the object | A list of `op` / `path` / `value` |
| Good for | Changing or adding nested fields | Removing fields, list items by index, precise edits |
| Downside | Not all fields merge the way you expect | `/0/` indexes break if the list order changes |

---

## Task 6: Config with `configMapGenerator` (12 min)

Each environment needs its own message and color. Kustomize can **generate** a ConfigMap.

**1.** In `base/deployment.yaml`, **replace** the whole `env:` block with:

```yaml
          envFrom:
            - configMapRef:
                name: web-config
```

**2.** In `base/kustomization.yaml`, add:

```yaml
configMapGenerator:
  - name: web-config
    literals:
      - PODINFO_UI_MESSAGE=Hello from the base
      - PODINFO_UI_COLOR=#34577c
```

**3.** In **each** overlay, override the values (`behavior: merge` means "change these keys
in the base's ConfigMap"):

```yaml
configMapGenerator:
  - name: web-config
    behavior: merge
    literals:
      - PODINFO_UI_MESSAGE=Hello from DEV      # PROD for prod
      - PODINFO_UI_COLOR=#ff8800               # #2e7d32 for prod
```

Render dev and look closely at **two** places:

```bash
kubectl kustomize overlays/dev | grep web-config
#   name: web-config-t4k94t944b              <- the ConfigMap's name has a hash suffix
#       name: web-config-t4k94t944b          <- and the Deployment's reference was rewritten to match
```

(Your hash will be different.) Apply both overlays and check the messages:

```bash
kubectl apply -k overlays/dev && kubectl apply -k overlays/prod
curl -s http://$NODE_IP:$DEV_PORT/ | grep -E 'message|color'
curl -s http://$NODE_IP:30082/     | grep -E 'message|color'
```

### Why the hash? Do this experiment

Change the dev message to `Hello DEV v2`, then:

```bash
kubectl diff -k overlays/dev         # the ConfigMap name changes, so the Deployment's pod template changes
kubectl apply -k overlays/dev
kubectl rollout status deploy/web -n kz-dev
kubectl get rs -n kz-dev             # a NEW ReplicaSet: the Pods were replaced
curl -s http://$NODE_IP:$DEV_PORT/ | grep message
```

<details>
<summary>Explain it before you open this</summary>

A container reads its environment variables **once, at startup**. If you edited a ConfigMap
in place, the running Pods would keep the old values until something restarted them.

Because the generated name includes a hash of the content, new content means a new name.
The new name changes the Deployment's pod template, and a template change makes the
Deployment do a rolling update. So **config changes roll out the same way image changes
do**, and you can roll them back the same way.

The old `web-config-<oldhash>` ConfigMap is left behind. Run `kubectl get cm -n kz-dev` to see it.
</details>

---

## Task 7: Labels, and a trap (5 min)

Add an `env` label to everything in each overlay:

```yaml
labels:
  - pairs:
      env: dev        # env: prod in the prod overlay
```

```bash
kubectl kustomize overlays/dev | grep -B2 -A3 'labels:'
kubectl apply -k overlays/dev
```

### Break it

The `labels` transformer has an option, `includeSelectors: true`, that also adds the label to
**selectors**. Add it under `pairs:` in the dev overlay (same indent as `pairs`) and apply:

```text
service/web configured
The Deployment "web" is invalid: spec.selector: ... field is immutable
```

Lab 1 again: a Deployment's selector can't change after it's created. **Worse**, look at
the first line: the *Service's* selector did change. It now requires `env=dev`, which the running Pods
don't have. Check your endpoints!

Remove `includeSelectors: true` and re-apply to fix it. (The older `commonLabels:` field
*always* changes selectors, which is one reason it's deprecated.)

---

## Checkpoint: your final tree

```
lab-3-kustomize/
├── base/
│   ├── deployment.yaml
│   ├── kustomization.yaml
│   └── service.yaml
└── overlays/
    ├── dev/
    │   └── kustomization.yaml
    └── prod/
        ├── kustomization.yaml
        └── patch-memory.yaml
```

Reference answer: [`solutions/lab-3/kustomize/`](../solutions/lab-3/kustomize/).

## Stretch goals

1. **Add a `staging` overlay** in under 3 minutes: 2 replicas, tag `6.15.0`, a purple color.
   How many files did you need?
2. Run `kubectl apply -k overlays/dev --prune -l env=dev` and see what happens to the old
   `web-config-<hash>` ConfigMaps. Why is pruning risky?
3. Read about Kustomize **components** (`kind: Component`). How would you add an optional
   "debug mode" that only some overlays turn on?
4. Install the standalone `kustomize` binary and try `kustomize edit set image ...` inside an
   overlay. Why is that useful in a CI pipeline?

## Clean up

```bash
kubectl delete -k overlays/dev
kubectl delete -k overlays/prod
kubectl delete namespace kz-dev kz-prod
```

## Reflection questions

1. Kustomize has **no variables and no `if` statements**. Is that a weakness or a strength?
   Think about who has to *read* these files at 2 a.m.
2. Why could the base be applied with `kubectl apply -f base/` as-is, and why does that matter?
3. You need a feature only in prod: an extra sidecar container. Which Kustomize feature
   would you use?
4. What would be hard to do with Kustomize? (Hint: think about sharing your app with another
   company that has different needs you can't predict.)
