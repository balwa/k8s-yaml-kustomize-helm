# Lab 5: Wrap-up (15 min)

## What you did today

```
Lab 0  YAML is data             maps, lists, scalars; types matter
   │
Lab 1  YAML is an API request   apiVersion/kind/metadata/spec/status; labels are the glue
   │
Lab 2  ...and it gets copied    2 envs = 2 copies = drift; envsubst breaks on types
   │
   ├──► Lab 3  Kustomize         keep plain YAML, describe the DIFFERENCES as patches
   │
   └──► Lab 4  Helm              real templates + values + packaging + release history
```

## Kustomize vs Helm, side by side

| | **Kustomize** | **Helm** |
|---|---|---|
| Core idea | Overlay **patches** on plain YAML | **Templates** filled with values |
| Install | Built into `kubectl` (`-k`) | Separate CLI |
| Source files | Valid Kubernetes YAML | Not valid YAML until rendered (`{{ }}`) |
| Logic (`if`, loops) | None, on purpose | Yes |
| Per-environment config | One overlay folder per env | One values file per env |
| Config change → rollout | Built in (`configMapGenerator` hash) | Manual (`checksum/config` annotation) |
| Remembers what it deployed | No (Git is the record) | Yes: releases, `history`, `rollback` |
| Sharing with strangers | Awkward: they have to patch your YAML | Great: they set documented values |
| Main use | **Your own** apps across **your own** environments | **Packaging** software for others, and installing third-party software |
| Common pain | Patching deeply nested lists | Indentation (`nindent`), template debugging |

**They're not rivals.** Many teams install third-party software (databases, monitoring,
ingress controllers) with **Helm** and deploy their own services with **Kustomize**.
GitOps tools like Argo CD and Flux support both.

## A quick decision guide

```
Is it software someone else wrote (Postgres, Prometheus, ingress-nginx)?
 └─ yes → use their Helm chart. Read `helm show values` first.
 └─ no, it's our app →
       Do strangers need to configure it in ways we can't predict?
        └─ yes → write a Helm chart
        └─ no  → Kustomize base + overlays is usually enough (and simpler to read)
```

## Quiz (scenario-based, answer individually, then discuss)

1. You run `kubectl apply -f svc.yaml`. There are no errors, the Pods are `Running`, and `curl` to the
   NodePort hangs. What **one** command do you run first, and what are you looking for?

2. What's wrong with this, and will the YAML parser, the API server, or neither catch it?
   ```yaml
   env:
     - name: FEATURE_FLAG
       value: on
   ```

3. A teammate adds `includeSelectors: true` to an overlay's `labels:` and runs `kubectl apply -k`
   on an existing environment. What happens to the Deployment? What happens to the Service?

4. In Kustomize, you change a value in a `configMapGenerator` and apply. Why do the Pods
   restart, when editing a regular ConfigMap with `kubectl edit` would not restart them?

5. A Helm template contains `value: {{ .Values.port }}` and someone runs `--set port=8080`.
   The field is an env var `value`. What happens, and what's the fix?

6. Your prod release is broken after `helm upgrade`. Write the **two** commands to find the
   last good revision and go back to it.

7. You need to deploy your team's service to dev, staging and prod. The only differences are
   replica count, image tag and two config values. Kustomize or Helm? Justify in one sentence.

8. **Analyze:** a student writes this Helm template. `helm template` prints **no error**, but the
   rendered Deployment is wrong. What does the output look like, and what finally catches it?
   ```yaml
          resources:
          {{ toYaml .Values.resources }}
   ```

## Homework

Pick **one** (your instructor may assign one):

**A. Kustomize: add a component.**
Extend your Lab 3 kustomization with a `staging` overlay, plus a Kustomize **component**
(`kind: Component`) called `debug` that adds the env var `PODINFO_LEVEL=debug`. Only dev
and staging should include it. Submit the tree and the output of
`kubectl kustomize overlays/staging`.

**B. Helm: make your chart production-ready.**
Extend your Lab 4 chart with:
* a `templates/_helpers.tpl` that defines the name and labels once (use `include`)
* an optional ConfigMap for the message and color, plus a `checksum/config` annotation so a
  config change still rolls the Pods
* a values-file-driven `livenessProbe` that's turned off by default

Submit the chart and the output of `helm template` with two different values files.

**C. Compare: same app, both tools.**
Deploy the **same** dev/prod configuration with both your Lab 3 overlays and your Lab 4
chart. Run `diff` on the two rendered outputs. Explain every difference (there will be some).
One page, max.

## Final reflection (2 minutes, on paper)

* One thing about Kubernetes YAML that confused you this morning and doesn't anymore:
* One thing that still confuses you:
* Which tool would you reach for first, and why:
