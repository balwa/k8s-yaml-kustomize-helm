# Lab 4: Helm (60 min)

## Learning objectives

By the end of this lab you can:

1. Build a Helm chart from scratch, starting from plain YAML, and explain what `Chart.yaml`,
   `values.yaml` and `templates/` each do.
2. Use template basics (`.Values`, `.Release`, `quote`, `default`, `required`, `if`, `range`,
   `toYaml`), and say which Lab 2 `envsubst` bug each one fixes.
3. Manage a **release**: install, upgrade, inspect history and roll back.
4. Install and configure a chart **someone else wrote**, by reading its `values.yaml`.

## The idea: a real template language, plus a package manager

Kustomize patched plain YAML. Helm goes back to **templates**, the approach that failed in
Lab 2, but with a real template language (Go templates) that knows about types, defaults
and missing values. On top of that, Helm is a **package manager**:

| Python world | Helm world |
|---|---|
| A package on PyPI | A **chart** (a folder or `.tgz` of templates + default values) |
| `pip install requests` | `helm install my-release some-repo/some-chart` |
| Keyword arguments | **values** (`-f values.yaml`, `--set key=value`) |
| `pip list` | `helm list` |
| *(pip has no undo)* | `helm rollback` |

Each installation of a chart is a **release**. A release has a name and a numbered history
of revisions.

> **For the Python folks:** `{{ .Values.message }}` is like an f-string or a Jinja2 template:
> `f"value: {values['message']}"`. The difference from `envsubst` is that the template
> language has **functions**, like `quote`, `default`, `required` and `toYaml`. You call them
> with a pipe (`|`), like a Unix pipeline.

## Setup

```bash
cd ~/workshop/lab-4-helm
helm version          # v3.x or v4.x; both work for this lab
```

---

## Task 1: A chart with no templating at all (8 min)

A chart can be nothing but plain YAML. Start there:

```bash
mkdir -p web-chart/templates
cp ../lab-2-the-copy-paste-problem/app/deployment.yaml web-chart/templates/
cp ../lab-3-kustomize/base/service.yaml web-chart/templates/     # the version without nodePort
```

(Didn't finish Lab 3? Copy `../solutions/lab-3/kustomize/base/service.yaml` instead.)

Create `web-chart/Chart.yaml`:

```yaml
apiVersion: v2              # chart format for Helm 3+
name: web-chart
description: podinfo, packaged by our class
type: application
version: 0.1.0              # version of the CHART
appVersion: "6.15.0"        # version of the APP inside it
```

Render it locally. Like `kubectl kustomize`, this prints YAML and talks to no cluster:

```bash
helm template web-dev ./web-chart
```

Now **install** it as a release:

```bash
helm install web-dev ./web-chart -n helm-dev --create-namespace
helm list -n helm-dev
kubectl get deploy,svc -n helm-dev
```

Where does Helm keep track of the release? In the cluster, as a Secret:

```bash
kubectl get secrets -n helm-dev
# NAME                            TYPE                 DATA   AGE
# sh.helm.release.v1.web-dev.v1   helm.sh/release.v1   1      20s
```

One Secret per **revision**. This is how `helm rollback` works later.

---

## Task 2: Values: your first template (8 min)

Create `web-chart/values.yaml`:

```yaml
replicaCount: 2

image:
  repository: ghcr.io/stefanprodan/podinfo
  tag: ""                   # empty means "use the chart's appVersion"

message: "Hello from Helm"
color: "#34577c"
```

Edit `web-chart/templates/deployment.yaml` and replace the hard-coded values:

```yaml
  replicas: {{ .Values.replicaCount }}
  ...
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
  ...
            - name: PODINFO_UI_MESSAGE
              value: {{ .Values.message | quote }}
            - name: PODINFO_UI_COLOR
              value: {{ .Values.color | quote }}
```

Render with the defaults, then override from the command line:

```bash
helm template web-dev ./web-chart | grep -E 'replicas|image:|value:'
helm template web-dev ./web-chart --set replicaCount=5 --set message="Hi there" \
  | grep -E 'replicas|image:|value:'
```

Apply the change to the running release:

```bash
helm upgrade web-dev ./web-chart -n helm-dev --set message="Hello from DEV (helm)"
NODE_PORT=$(kubectl get svc web -n helm-dev -o jsonpath='{.spec.ports[0].nodePort}')
curl -s http://$NODE_IP:$NODE_PORT/ | grep message
```

---

## Task 3: Install it twice (8 min)

A second team wants their own copy **in the same namespace**:

```bash
helm install web-dev2 ./web-chart -n helm-dev
```

```text
Error: INSTALLATION FAILED: Unable to continue with install: Service "web" in namespace
"helm-dev" exists and cannot be imported into the current release: invalid ownership metadata; ...
```

(The exact wording differs a little between Helm 3 and Helm 4.) Both releases would create objects called `web`. Fix it by making names **depend on the
release**. In **both** template files, replace every `web` used as a name or label value
with `{{ .Release.Name }}-web`:

```yaml
metadata:
  name: {{ .Release.Name }}-web
  labels:
    app: {{ .Release.Name }}-web
```

Do the same for the Deployment's `selector.matchLabels`, the pod template labels and the
Service `selector`. Remember Lab 1: they all have to match.

```bash
helm template web-dev2 ./web-chart | grep -E 'name:|app:'
helm upgrade web-dev  ./web-chart -n helm-dev       # renames web -> web-dev-web
helm install web-dev2 ./web-chart -n helm-dev       # now works
kubectl get deploy,svc -n helm-dev
```

> Kustomize would need a separate overlay with `namePrefix:` for this. In Helm, "install it
> again with another name" is built in, because charts are meant to be installed many times.

Remove the second copy: `helm uninstall web-dev2 -n helm-dev`

---

## Task 4: Fix every Lab 2 bug (10 min)

Remember the four ways `envsubst` broke? Let's see how the template functions handle each one.

**First, see the bug.** Temporarily remove `| quote` from the message line, then:

```bash
helm template web-dev ./web-chart --set message=2026 | grep -A1 MESSAGE
#               value: 2026            <- a number again
helm upgrade web-dev ./web-chart -n helm-dev --set message=2026
# Error: UPGRADE FAILED: ... cannot unmarshal number into Go struct field EnvVar...value of type string

helm template web-dev ./web-chart --set "message=Status: ready"
# Error: YAML parse error on web-chart/templates/deployment.yaml: ... mapping values are not allowed in this context
```

**Now fix it.** Put `| quote` back. `quote` adds quotes **and escapes** characters
inside the value:

```bash
helm template web-dev ./web-chart --set 'message=She said "hi": ok' | grep -A1 MESSAGE
#               value: "She said \"hi\": ok"
```

**Then make a missing value fail loudly.** Change the replicas line to:

```yaml
  replicas: {{ required "replicaCount is required" .Values.replicaCount }}
```

```bash
helm template web-dev ./web-chart --set replicaCount=null
# Error: execution error at (web-chart/templates/deployment.yaml:8:15): replicaCount is required
```

| Lab 2 `envsubst` bug | Helm's answer |
|---|---|
| #1 missing `REPLICAS`, silently 1 replica | `required "msg" .Values.x` fails at render time, or `default 2 .Values.x` |
| #2 `Status: ready` breaks the YAML | `quote` |
| #3 `2026` / `yes` becomes a number/bool | `quote` |
| #4 missing tag, `image: repo:` | `default .Chart.AppVersion` |

> **Lesson:** Helm templates are still **text** templates. Helm doesn't understand YAML
> while it renders. Without `quote`, you get exactly the Lab 2 bugs. The functions only help
> if you use them.

---

## Task 5: Conditionals, loops, whitespace (8 min)

### `if`: add a field only when a value is set

Add to `values.yaml`:

```yaml
service:
  nodePort: null        # set a number to pin it; null lets Kubernetes pick one
```

In `templates/service.yaml`, under `targetPort`:

```yaml
    - port: 80
      targetPort: 9898
      {{- if .Values.service.nodePort }}
      nodePort: {{ .Values.service.nodePort }}
      {{- end }}
```

```bash
helm template x ./web-chart | grep -A3 'port: 80'
helm template x ./web-chart --set service.nodePort=30090 | grep -A3 'port: 80'
```

> **What does `{{-` mean?** The dash **trims whitespace and the newline before** the tag.
> Without it, every `{{ if }}` and `{{ end }}` would leave a blank line behind. Remove both
> dashes, render again, and look at the output.

### `range`: one env var per entry in a map

Add `extraEnv: {}` to `values.yaml`, and after the `PODINFO_UI_COLOR` entry in the
Deployment template:

```yaml
            {{- range $name, $value := .Values.extraEnv }}
            - name: {{ $name }}
              value: {{ $value | quote }}
            {{- end }}
```

```bash
helm template x ./web-chart --set extraEnv.FOO=bar --set extraEnv.TEAM=dev | grep -A1 -E 'FOO|TEAM'
```

### `toYaml`: copy a whole block from values

Add the change request's resources to `values.yaml`:

```yaml
resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    memory: 128Mi
```

And add this to the container in the template, along with the readiness probe:

```yaml
          readinessProbe:
            httpGet:
              path: /readyz
              port: 9898
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
```

`nindent 12` means "start a new line and indent every line by 12 spaces". If you get the
number wrong, the YAML is wrong. Try `nindent 8` and render. **Counting spaces is the part of
Helm everyone complains about.**

---

## Task 6: One values file per environment (6 min)

Create `values-dev.yaml`:

```yaml
replicaCount: 1
message: "Hello from DEV (helm)"
color: "#ff8800"
```

and `values-prod.yaml`:

```yaml
replicaCount: 3
image:
  tag: "6.14.0"
message: "Hello from PROD (helm)"
color: "#2e7d32"
resources:
  limits:
    memory: 256Mi       # merged into the defaults: requests are kept
service:
  nodePort: 30092
```

`upgrade --install` installs the release if it doesn't exist and upgrades it if it does.
It's the command you'd put in a CI pipeline:

```bash
helm upgrade --install web-dev  ./web-chart -n helm-dev  -f values-dev.yaml
helm upgrade --install web-prod ./web-chart -n helm-prod -f values-prod.yaml --create-namespace

curl -s http://$NODE_IP:30092/ | grep -E 'version|message|color'
```

**Precedence** (last one wins): `values.yaml` in the chart, then each `-f file` in order, then each `--set`.

### Checkpoint

```bash
helm list -A
# NAME      NAMESPACE  REVISION  STATUS    CHART            APP VERSION
# web-dev   helm-dev   ...       deployed  web-chart-0.1.0  6.15.0
# web-prod  helm-prod  1         deployed  web-chart-0.1.0  6.15.0
kubectl get deploy -n helm-prod -o wide     # 3 replicas, image tag 6.14.0
```

---

## Task 7: Release history and rollback (6 min)

Make a "bad" release, then undo it:

```bash
helm upgrade web-prod ./web-chart -n helm-prod -f values-prod.yaml --set message="OOPS"
curl -s http://$NODE_IP:30092/ | grep message        # OOPS

helm history web-prod -n helm-prod
# REVISION  STATUS      DESCRIPTION
# 1         superseded  Install complete
# 2         deployed    Upgrade complete

helm rollback web-prod 1 -n helm-prod
curl -s http://$NODE_IP:30092/ | grep message        # back to PROD
helm history web-prod -n helm-prod                   # rollback = a NEW revision 3
```

Ask Helm what it knows about a release:

```bash
helm get values   web-prod -n helm-prod      # the values YOU supplied
helm get manifest web-prod -n helm-prod      # the exact YAML it applied
```

> Kustomize has nothing like this. It renders and applies, and then forgets. With Kustomize,
> "roll back" means `git revert` and apply again. Which one is better depends on whether you
> treat **Git** or **the cluster** as the record of what's deployed (look up "GitOps").

---

## Task 8: Use someone else's chart (8 min)

This is where Helm is strongest: **installing software you didn't write**. The author of
podinfo publishes an official chart:

```bash
helm repo add podinfo https://stefanprodan.github.io/podinfo
helm repo update
helm search repo podinfo
```

Before installing **any** chart, read its values. That file is the chart's public interface:

```bash
helm show values podinfo/podinfo | less
```

**Your task:** write `values-podinfo.yaml` so the release:

* runs **2** replicas
* shows the message `Installed from someone else's chart` in the color `#6a1b9a`
* is exposed as a **NodePort** on port **31198**

*Hint:* search the `helm show values` output for `ui:` and `service:`.

Render it first and count what it would create:

```bash
helm template hello podinfo/podinfo -f values-podinfo.yaml | grep '^kind:'
```

Then install and test:

```bash
helm install hello podinfo/podinfo -n helm-pub --create-namespace -f values-podinfo.yaml
curl -s http://$NODE_IP:31198/ | grep -E 'message|color'
```

> **Discuss:** `helm template` lists some `kind: Pod` objects that don't show up after you
> install. Look at their annotations. What is `helm.sh/hook: test`? Try `helm test hello -n helm-pub`.

Reference answers: [`solutions/lab-4/`](../solutions/lab-4/).

---

## Stretch goals

1. Run `helm create scratch` and read every file it generates. You should now recognise
   almost everything. What is `_helpers.tpl` for? What does `include` do?
2. `helm lint ./web-chart` and `helm package ./web-chart`. What is in the `.tgz`?
3. In Kustomize, a config change rolled the Pods automatically (the hash suffix). In our chart,
   changing `message` also rolls the Pods. Why? Would that still be true if the message lived
   in a ConfigMap? Look up the `checksum/config` annotation pattern.
4. Use **both tools together**: render a chart with `helm template`, then patch the result with a
   Kustomize overlay. When would a team do that?

## Clean up

```bash
helm uninstall web-dev  -n helm-dev
helm uninstall web-prod -n helm-prod
helm uninstall hello    -n helm-pub
kubectl delete namespace helm-dev helm-prod helm-pub
```

## Reflection questions

1. Open your finished `templates/deployment.yaml`. Is it still valid YAML on its own? Why
   does that matter for editors, linters and code review?
2. Helm stores release state in Secrets in the cluster. List one advantage and one risk of that.
3. Your team will run **your own** service in 3 environments. Would you choose Kustomize or Helm? Why?
4. You need to install PostgreSQL, Prometheus and an ingress controller. Kustomize or Helm? Why?
