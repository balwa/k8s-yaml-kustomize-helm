# Lab 0: YAML is just data (15 min)

## Learning objectives

By the end of this lab you can:

1. Name the three YAML building blocks (**maps**, **lists**, **scalars**) and spot each in a file.
2. Predict the JSON a YAML file turns into, including the *type* of every value.
3. Read a YAML parse error and a Kubernetes type error, and fix both.

## Why start here?

Every Kubernetes manifest goes through two steps:

```
your .yaml file ──(1) YAML parser──► a data structure (JSON) ──(2) API server──► checks it against the schema
                     "is it valid YAML?"                        "is it a valid Pod?"
```

Most "Kubernetes YAML errors" are really one of these:

* **Step 1 failed:** bad indentation, a tab, a stray `-`. The file isn't valid YAML.
* **Step 2 failed:** the YAML is fine, but the *shape* or *type* doesn't match what
  Kubernetes expects. For example, a map where a list should be, or a number where a string should be.

Once you can tell which step failed, you can fix the error.

> **Analogy:** YAML is like a Python dict/list literal written without braces, brackets or
> commas. Indentation does the job of `{ }`, and `- ` does the job of `[ ]`. If you can read
> a Python dict, you can read YAML.

## Part A: Predict, then check (5 min)

Look at [`examples/student.yaml`](examples/student.yaml). **Before running anything**, write
down on paper what you think the JSON looks like. Then check:

```bash
cd ~/workshop/lab-0-yaml-is-just-data
./yaml2json.py examples/student.yaml
```

Do the same for these two, which show the patterns you'll see most in Kubernetes:

```bash
./yaml2json.py examples/list-of-maps.yaml   # a LIST of MAPS: how containers, ports and env are written
./yaml2json.py examples/two-docs.yaml       # "---" means several documents in one file
```

### Checkpoint

In `list-of-maps.yaml`, how many containers are there? Which keys belong to which one?
The JSON output should make it clear:

```json
{
  "containers": [
    { "name": "web",     "image": "nginx" },
    { "name": "sidecar", "image": "busybox" }
  ]
}
```

**Rule of thumb:** each `- ` starts a **new list item**. Lines indented under it, lined up
with the text after the dash, belong to **that same item**.

## Part B: Fix the broken files (10 min)

The [`broken/`](broken/) folder has six manifests. Each has **exactly one** problem.
For each file:

1. Run it through the YAML parser: `./yaml2json.py broken/0X-....yaml`
2. Ask the API server whether it is a valid object, without creating anything:
   `kubectl apply --dry-run=server -f broken/0X-....yaml`
3. Decide: **did step 1 (YAML) or step 2 (Kubernetes schema) fail?** Write it down.
4. Fix the file and re-run until the dry run prints `created (server dry run)`.

| File | Hint |
|------|------|
| `01-indentation.yaml` | Count the spaces. |
| `02-tabs.yaml` | Run `cat -A broken/02-tabs.yaml`. What is `^I`? |
| `03-map-instead-of-list.yaml` | `kubectl explain pod.spec.containers`: is it `<Object>` or `<[]Object>`? |
| `04-wrong-types.yaml` | Two type mistakes. The server only reports the first one it hits. |
| `05-the-norway-problem.yaml` | Look at the JSON. Is `NO` still the string `"NO"`? Is `1.10` still `1.10`? |
| `06-misplaced-dash.yaml` | This one parses **and** gets past the type check. Read the validation error. |

### Expected errors (so you know what you're looking at)

```text
# YAML step failed (01, 02):
error: error parsing broken/01-indentation.yaml: error converting YAML to JSON: yaml: line 8: did not find expected '-' indicator
error: error parsing broken/02-tabs.yaml: error converting YAML to JSON: yaml: line 4: found character that cannot start any token

# Kubernetes schema/type step failed (03, 04, 05):
... cannot unmarshal object into Go struct field PodSpec.spec.containers of type []v1.Container
... cannot unmarshal number into Go struct field EnvVar.spec.containers.env.value of type string
... cannot unmarshal number into Go struct field ConfigMap.data of type string

# Kubernetes validation failed (06):
The Pod "broken-06" is invalid:
* spec.containers[0].image: Required value
* spec.containers[1].name: Required value
```

> **How to read `cannot unmarshal X into Go struct field ... of type Y`:**
> Kubernetes is written in Go. Every object is a Go struct with typed fields. The message
> means "you gave me an **X** (object/number/bool/string), but this field needs a **Y**."
> The path after `field` tells you exactly where in your YAML the problem is.

### Checkpoint

```bash
kubectl apply --dry-run=server -f broken/
# pod/broken-01 created (server dry run)
# pod/broken-02 created (server dry run)
# pod/broken-03 created (server dry run)
# pod/broken-04 created (server dry run)
# configmap/broken-05 created (server dry run)
# pod/broken-06 created (server dry run)
```

Reference answers, with a comment on every fix: [`solutions/lab-0/`](../solutions/lab-0/).

## The three rules to keep

1. **Spaces, never tabs.** Use two spaces per level and be consistent.
2. **`- ` means a new list item.** One dash per container, port or env var.
3. **When in doubt, quote it.** `"yes"`, `"NO"`, `"1.10"`, `"8080"`, `"true"`. A string
   field never breaks because you quoted it. Number fields like `containerPort` and `replicas` must **not** be quoted.

## Reflection questions

1. In file 06, the YAML was valid and the API server still rejected it. What does that tell
   you about what a YAML linter in your editor can and can't catch?
2. `APP_VERSION: 1.10` silently became `1.1`. Why is a *silent* change worse than an error?
3. Why does the server report only the first type error in file 04, but list *both*
   problems in file 06? (Hint: decoding vs validation.)
