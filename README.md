# From YAML to Kustomize to Helm: a 4-hour hands-on workshop

You already know how to run a Pod, put a Service in front of it, and reach it on a
NodePort. This workshop answers the next questions:

1. **What is all this YAML, really?** (It's data. It's an API request.)
2. **Why does everybody complain about YAML?** (Copy-paste across environments.)
3. **How do Kustomize and Helm make that pain go away, and how are they different?**

Every lab builds on the one before it. You will deploy the **same small web app**
the whole way through, so you can focus on the YAML and not on a new app each time.

## The app: podinfo

[`podinfo`](https://github.com/stefanprodan/podinfo) is a tiny Go web server built
for Kubernetes demos. It listens on port **9898** and returns JSON when you `curl` it.
Two environment variables change what it says back to you:

| Env var              | Effect                                 |
|----------------------|----------------------------------------|
| `PODINFO_UI_MESSAGE` | Shows up as `"message"` in the JSON    |
| `PODINFO_UI_COLOR`   | Shows up as `"color"` in the JSON      |

That's useful here: when you change config, you can **see** the change with one `curl`.

```bash
$ curl -s http://<node-ip>:<node-port>/
{
  "hostname": "web-6d4b75cb6d-x2x7k",
  "version": "6.15.0",
  "color": "#34577c",
  "message": "Hello from the base",
  ...
}
```

## Prerequisites

* The 3-node kubeadm cluster from your homework (1 control plane, 2 workers) on EC2.
* You work **on the control-plane node**, where `kubectl get nodes` already works.
* The EC2 security group allows **TCP 30000–32767** between the nodes.
* Nodes can pull images from `ghcr.io`.

## Setup (do this before Lab 0)

On the control-plane node:

```bash
git clone https://github.com/balwa/k8s-yaml-kustomize-helm.git ~/workshop
cd ~/workshop

# Installs Helm if it is missing. kubectl already has Kustomize built in.
./setup/install-helm.sh

# Checks that everything you need is in place.
./setup/check-env.sh
```

`check-env.sh` should end with `All checks passed.` If it doesn't, fix what it reports
before you start. Ask for help if you need it.

### Finding a node IP to curl

You'll `curl` NodePorts a lot. Save a worker's internal IP in a variable once per
shell session:

```bash
export NODE_IP=$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' \
  -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
echo $NODE_IP
```

## Repository layout

```
setup/                          install + preflight scripts
lab-0-yaml-is-just-data/        YAML syntax and types, broken files to fix
lab-1-anatomy-of-a-k8s-object/  the Kubernetes object model, kubectl explain, labels
lab-2-the-copy-paste-problem/   the starting app, envsubst "templating"
lab-3-kustomize/                base + overlays
lab-4-helm/                     build a chart from scratch, then use someone else's
lab-5-wrap-up/                  comparison, quiz, homework
solutions/                      reference answers for every lab (try first!)
scripts/verify-solutions.sh     instructor check that all solutions render and validate
```

## Ground rules

* **Type the YAML yourself** when a lab asks you to. Copy-paste hides the lessons.
* **Break things on purpose.** Every lab has a "break it" step. Read the error
  message slowly. Learning to read Kubernetes error messages is half the skill.
* **Use `--dry-run=server` and `kubectl diff`** before `apply`. That's what professionals do.
* Stuck for more than 5 minutes? Look in `solutions/`, then work out *why* the answer works.
