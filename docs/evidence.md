<!--
=============================================================================
File        : docs/evidence.md
Assignment  : DSO202 Assignment 4
Purpose     : Command output for every task, recorded as it was run
              (brief section 9, evidence convention). Passwords, the admin
              password and the sealing key are never recorded; where a command
              prints one, the output is replaced by a note.
=============================================================================
-->

# Evidence — DSO202 Assignment 4

Cluster `dso202-gitops` (kind, 1 control-plane + 2 workers, Kubernetes v1.36.1), repository
<https://github.com/pomegranateis/dso202-gitops>. Times are local (UTC+6). Screenshots are in
[`docs/screenshots/`](screenshots/) and are referenced from the task that requires them.

## Task 1 — Repository, Chart Contract and Cluster

### Tool check (section 3.2)
```text
$ docker version --format '{{.Server.Version}}'
28.0.1

$ kind version
kind v0.32.0 go1.26.3 linux/amd64

$ kubectl version --client
Client Version: v1.36.0
Kustomize Version: v5.8.1

$ helm version --short
v4.3.0+gbec5b06

$ git --version
git version 2.34.1

$ argocd version --client
argocd: v3.5.6
  BuildDate: 2026-10-20T18:33:20Z
  GitCommit: c2b1e3017e2cec86b122172e861dcd026453ae44
  GitTreeState: clean
  GitTag: v3.5.6
  GoVersion: go1.26.10
  Compiler: gc
  Platform: linux/amd64

$ kubeseal --version
kubeseal version: 0.40.0

$ helm repo add sealed-secrets https://bitnami.github.io/sealed-secrets
"sealed-secrets" already exists with the same configuration, skipping

$ helm repo update
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "kong" chart repository
...Successfully got an update from the "hashicorp" chart repository
...Successfully got an update from the "sealed-secrets" chart repository
...Successfully got an update from the "podinfo" chart repository
Update Complete. ⎈Happy Helming!⎈

$ helm search repo sealed-secrets/sealed-secrets --versions | head -5
NAME                         	CHART VERSION	APP VERSION	DESCRIPTION                                  
sealed-secrets/sealed-secrets	2.22.0       	0.41.2     	Helm chart for the sealed-secrets controller.
sealed-secrets/sealed-secrets	2.21.0       	0.41.2     	Helm chart for the sealed-secrets controller.
sealed-secrets/sealed-secrets	2.20.0       	0.40.0     	Helm chart for the sealed-secrets controller.
sealed-secrets/sealed-secrets	2.19.3       	0.39.1     	Helm chart for the sealed-secrets controller.
```

Chart `2.20.0` (controller `0.40.0`) is listed, as required.

### Chart contract

| # | Requirement | Where it is satisfied |
| --- | --- | --- |
| C1 | Image repository and tag are values per tier | `charts/tasktracker/values.yaml`: `database.image`, `backend.image`, `frontend.image` (`repository`, `tag`); template helper `tasktracker.image` in `templates/_helpers.tpl` reads only these |
| C2 | Per-tier configuration from values | `values.yaml`: `database.env`, `backend.env`, `frontend.env`; rendered by `tasktracker.envConfigMap` into `database-config`, `backend-config`, `frontend-config` (`templates/configmap.yaml`) |
| C3 | No `Secret`; credentials from `existingSecret` | `values.yaml`: `existingSecret: tasktracker-credentials`; `secretRef` in `templates/database.yaml` and `templates/backend.yaml`; `templates/secret.yaml` removed (commit `22180f7`) |
| C4 | Readiness probes on all tiers | `templates/database.yaml` (`pg_isready`), `templates/backend.yaml` (`GET /api/status`), `templates/frontend.yaml` (`GET /`) |
| C5 | Sync waves 0 / 1 / 2 | `argocd.argoproj.io/sync-wave` on `db-statefulset` (`"0"`), `backend-deployment` (`"1"`), `frontend-deployment` (`"2"`) |
| C6 | `progressDeadlineSeconds: 120` | `templates/backend.yaml`, `templates/frontend.yaml` |
| C7 | Requests and limits on every container | `values.yaml`: `<tier>.resources` (schema requires both); smoke-test Job in `templates/smoke-test-job.yaml` |
| C8 | No Namespace, ResourceQuota, LimitRange, Role, RoleBinding | `templates/quota.yaml` and `templates/rbac.yaml` removed (commit `22180f7`); those objects are in `platform/<env>/` |
| C9 | Ingress disabled by default | `values.yaml`: `ingress.enabled: false`; `templates/ingress.yaml` renders nothing unless enabled |
| C10 | Frontend `NodePort`, port as a value | `values.yaml`: `frontend.service.type: NodePort`; `environments/dev/values.yaml` `30080`, `environments/staging/values.yaml` `30081` |
| C11 | `helm lint` clean, `helm template` succeeds for both | output below |

The database tier is a StatefulSet (from Assignment 2) rather than the Deployment + PVC of Assignment 3, so that
the kinds rendered by the chart match the project whitelist (Task 3) without adding `PersistentVolumeClaim`.

### `helm lint` and the rendered kinds (step 6)

The kind list was rendered from commit `c5a965d`, i.e. before the smoke-test `Job` was added in Task 5.
```text
$ helm lint charts/tasktracker -f environments/dev/values.yaml
==> Linting charts/tasktracker
[INFO] Chart.yaml: icon is recommended

1 chart(s) linted, 0 chart(s) failed

$ helm lint charts/tasktracker -f environments/staging/values.yaml
==> Linting charts/tasktracker
[INFO] Chart.yaml: icon is recommended

1 chart(s) linted, 0 chart(s) failed

$ helm template tasktracker charts/tasktracker -f environments/dev/values.yaml | grep '^kind:' | sort | uniq -c
      3 kind: ConfigMap
      2 kind: Deployment
      3 kind: Service
      1 kind: StatefulSet
```

### Cluster (step 7)
```text
$ date
Mon Nov 23 03:50:30 PM +06 2026

$ kind get clusters
dso202

$ kind delete cluster --name dso202
Deleting cluster "dso202" ...
Deleted nodes: ["dso202-control-plane" "dso202-worker2" "dso202-worker"]

$ kind create cluster --name dso202-gitops --config cluster/kind-cluster.yaml
Creating cluster "dso202-gitops" ...
Set kubectl context to "kind-dso202-gitops"
You can now use your cluster with:

kubectl cluster-info --context kind-dso202-gitops

Have a nice day! 👋

$ kubectl config current-context
kind-dso202-gitops

$ kubectl wait --for=condition=Ready nodes --all --timeout=180s
node/control-plane condition met
node/worker-node-1 condition met
node/worker-node-2 condition met

$ kubectl get nodes
NAME            STATUS   ROLES           AGE   VERSION
control-plane   Ready    control-plane   23s   v1.36.1
worker-node-1   Ready    <none>          12s   v1.36.1
worker-node-2   Ready    <none>          12s   v1.36.1

$ docker ps --filter name=dso202-gitops --format '{{.Names}}   {{.Ports}}'
dso202-gitops-worker2   
dso202-gitops-worker   
dso202-gitops-control-plane   127.0.0.1:30080->30080/tcp, 127.0.0.1:33771->6443/tcp
```

Host port `30080` is mapped on `dso202-gitops-control-plane`, bound to `127.0.0.1`.

## Task 2 — Install Argo CD Declaratively

### Render checks (step 2)
```text
$ kubectl kustomize bootstrap/argocd | grep -E '^kind: (Deployment|StatefulSet)$' | sort | uniq -c
      6 kind: Deployment
      1 kind: StatefulSet

$ kubectl kustomize bootstrap/argocd | grep 'image:' | sort -u
        image: ghcr.io/dexidp/dex:v2.45.1
        image: public.ecr.aws/docker/library/redis:8.2.3-alpine
        image: quay.io/argoproj/argocd:v3.5.6
```

All 50 namespaced objects render in `argocd`; the ClusterRoleBinding subjects also name `argocd`.
No image comes from Docker Hub.

### Server-side apply and readiness (steps 3, 4, 6)

The `serverside-applied` lines (60 objects) are omitted.
```text
$ kubectl apply -k bootstrap/argocd --server-side --force-conflicts

$ kubectl wait --for=condition=Available deployment --all -n argocd --timeout=300s
deployment.apps/argocd-applicationset-controller condition met
deployment.apps/argocd-dex-server condition met
deployment.apps/argocd-notifications-controller condition met
deployment.apps/argocd-redis condition met
deployment.apps/argocd-repo-server condition met
deployment.apps/argocd-server condition met

$ kubectl rollout status statefulset/argocd-application-controller -n argocd --timeout=300s
partitioned roll out complete: 1 new pods have been updated...

$ kubectl get pods -n argocd
NAME                                                READY   STATUS    RESTARTS   AGE
argocd-application-controller-0                     1/1     Running   0          42s
argocd-applicationset-controller-58bb5c7479-k5q7n   1/1     Running   0          42s
argocd-dex-server-dd6b85d9c-bkmpb                   1/1     Running   0          42s
argocd-notifications-controller-6b85c65458-pbvdr    1/1     Running   0          42s
argocd-redis-869b85489d-f9fhz                       1/1     Running   0          42s
argocd-repo-server-5bf66565cd-jbbcg                 1/1     Running   0          42s
argocd-server-7474bb8f76-9jgvv                      1/1     Running   0          42s

$ kubectl get crd | grep argoproj.io
applications.argoproj.io      2026-11-24T20:13:55Z
applicationsets.argoproj.io   2026-11-24T20:13:55Z
appprojects.argoproj.io       2026-11-24T20:13:55Z

$ kubectl get configmap argocd-cm -n argocd -o yaml | grep -E 'timeout.reconciliation|accounts.reviewer'
  accounts.reviewer: login
  timeout.reconciliation: 60s
  timeout.reconciliation.jitter: 10s
```

### Sign-in and versions (steps 5, 6)
```text
$ argocd admin initial-password -n argocd
(output not recorded: it is the admin password)

$ argocd login localhost:8080 --username admin --insecure
'admin:login' logged in successfully
Context 'localhost:8080' updated

$ argocd version
argocd: v3.5.6
  BuildDate: 2026-10-20T18:33:20Z
  GitCommit: c2b1e3017e2cec86b122172e861dcd026453ae44
  GitTreeState: clean
  GitTag: v3.5.6
  GoVersion: go1.26.10
  Compiler: gc
  Platform: linux/amd64
argocd-server: v3.5.6
  BuildDate: 2026-10-20T18:33:20Z
  GitCommit: c2b1e3017e2cec86b122172e861dcd026453ae44
  GitTreeState: clean
  GitTag: v3.5.6
  GoVersion: go1.26.10
  Compiler: gc
  Platform: linux/amd64
  Kustomize Version: v5.8.1 2026-02-09T16:15:27Z
  Helm Version: v4.2.1+gd591a19
  Kubectl Version: v0.36.1
  Jsonnet Version: v0.22.0
```

The `argocd` CLI binary was copied from the official `quay.io/argoproj/argocd:v3.5.6` image
(`sha256:8e5cc5bb008df8a09dba439462e58c94c55b7735888d3ebde0c25fc05e4e5335`) because the
release download from GitHub kept stalling; `argocd version` above shows the same build
(`GitTag v3.5.6`, `GitCommit c2b1e30`, `GitTreeState clean`) for client and server.

![Argo CD v3.5.6 after admin sign-in: all six Applications Healthy and Synced](screenshots/a4-1-argocd-signed-in.jpg)

## Task 3 — AppProjects and the Root Application

### Whitelist check (step 1)

The chart renders `ConfigMap`, `Deployment`, `Service`, `StatefulSet` and, from Task 5, the hook `Job`.
At this point `argocd/projects/dso202.yaml` listed exactly these five kinds. Compared with Listing 8,
`ServiceAccount` was removed (the chart renders none; the Assignment 2 ServiceAccount is in
`platform/<env>/rbac.yaml`), and `PersistentVolumeClaim` was not added (the database PVC comes from
`volumeClaimTemplates`). Each change is commented in the file. In Task 6, `ReplicaSet` and `Pod` were added
so that Argo CD shows the Pods and their logs (see Task 6).

### Apply and observe (steps 4, 5)
```text
$ kubectl apply -f bootstrap/root
appproject.argoproj.io/platform created
Warning: metadata.finalizers: "resources-finalizer.argocd.argoproj.io": prefer a domain-qualified finalizer name including a path (/) to avoid accidental conflicts with other finalizer writers
application.argoproj.io/root created
```
```text
$ kubectl get appproject,application -n argocd
NAME                              AGE
appproject.argoproj.io/default    110s
appproject.argoproj.io/dso202     2s
appproject.argoproj.io/platform   5s

NAME                           SYNC STATUS   HEALTH STATUS
application.argoproj.io/root   Synced        Healthy

$ argocd app get root
Name:               argocd/root
Project:            platform
Server:             https://kubernetes.default.svc
Namespace:          argocd
URL:                https://localhost:8080/applications/root
Source:
- Repo:             https://github.com/pomegranateis/dso202-gitops.git
  Target:           main
  Path:             argocd
SyncWindow:         Sync Allowed
Sync Policy:        Automated (Prune)
Sync Status:        Synced to main (c3741ce)
Health Status:      Healthy

GROUP        KIND        NAMESPACE  NAME    STATUS  HEALTH  HOOK  MESSAGE
argoproj.io  AppProject  argocd     dso202  Synced                appproject.argoproj.io/dso202 unchanged

$ argocd proj get dso202
Name:                        dso202
Description:                 Task Tracker workloads for the dev and staging environments
Destinations:                https://kubernetes.default.svc,dso202-dev
                             https://kubernetes.default.svc,dso202-staging
Repositories:                https://github.com/pomegranateis/dso202-gitops.git
Source Namespaces:           <none>
Scoped Repositories:         <none>
Allowed Cluster Resources:   <none>
Scoped Clusters:             <none>
Denied Namespaced Resources: <none>
Signature keys:              <none>
Orphaned Resources:          disabled
```

`dso202` was created by the root Application: it appears in the resource list of `argocd app get root`,
and it is three seconds younger than `platform`, which was applied by hand.

![Root Application resource tree: five child Applications and the dso202 AppProject](screenshots/a4-2-root-tree.jpg)

## Task 4 — Platform Layer and Sealed Secrets

### Controller installed through Git (step 1)

Commit `497bfcc` added `argocd/applications/sealed-secrets.yaml`.
```text
$ kubectl get applications -n argocd
NAME             SYNC STATUS   HEALTH STATUS
root             Synced        Healthy
sealed-secrets   Synced        Healthy

$ kubectl get pods -n sealed-secrets
NAME                                        READY   STATUS    RESTARTS   AGE
sealed-secrets-controller-8b5ffdf69-2bfvk   1/1     Running   0          15s

$ kubectl get crd sealedsecrets.bitnami.com
NAME                        CREATED AT
sealedsecrets.bitnami.com   2026-11-24T20:16:22Z
```

### Sealing-key backup (step 2)

The backup's contents are never shown.
```text
$ mkdir -p ../dso202-keys
$ kubectl get secret -n sealed-secrets -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > ../dso202-keys/sealing-key.backup.yaml
$ chmod 600 ../dso202-keys/sealing-key.backup.yaml
$ ls -l ../dso202-keys/
-rw------- 1 pomegranateu pomegranateu 7087 Nov 25 02:17 sealing-key.backup.yaml
$ kubectl get secret -n sealed-secrets -l sealedsecrets.bitnami.com/sealed-secrets-key
NAME                      TYPE                DATA   AGE
sealed-secrets-key49h67   kubernetes.io/tls   2      41s
```

### Sealing (steps 3, 4)

`secrets-plain/dev.env` and `secrets-plain/staging.env` (git-ignored, mode `600`) held different passwords
for dev and staging, with `DB_*` and `POSTGRES_*` carrying the same values. Each was sealed for its own
namespace with the pipeline of step 4; the output files are
`platform/dev/tasktracker-credentials.sealed.yaml` and `platform/staging/tasktracker-credentials.sealed.yaml`.
After sealing, the plaintext inputs were deleted and the values kept outside the repository.

The first history search (step 7) found the database **user name** `taskuser`: it entered the repository with
the unchanged Assignment 3 chart import (`84fcd3e`, `values.yaml` `credentials.username`) and had already been
removed from the chart in `d30935c`. Because history is permanent, both environments were re-sealed with user
names that had never appeared in Git (commit `3c670f8`, "Re-seal credentials with database usernames that never
appeared in Git history"). The passwords had never been committed and were kept.

### Delivered platform layer (step 6)
```text
$ kubectl get applications -n argocd
NAME               SYNC STATUS   HEALTH STATUS
platform-dev       Synced        Healthy
platform-staging   Synced        Healthy
root               Synced        Healthy
sealed-secrets     Synced        Healthy

$ kubectl get namespaces | grep dso202
dso202-dev           Active   12s
dso202-staging       Active   12s

$ kubectl get sealedsecret -n dso202-dev
NAME                      STATUS   SYNCED   AGE
tasktracker-credentials            True     11s

$ kubectl get sealedsecret -n dso202-staging
NAME                      STATUS   SYNCED   AGE
tasktracker-credentials            True     11s

$ kubectl describe secret tasktracker-credentials -n dso202-dev
Name:         tasktracker-credentials
Namespace:    dso202-dev
Labels:       <none>
Annotations:  <none>

Type:  Opaque

Data
====
DB_PASSWORD:        24 bytes
DB_USER:            9 bytes
POSTGRES_PASSWORD:  24 bytes
POSTGRES_USER:      9 bytes

$ kubectl describe secret tasktracker-credentials -n dso202-staging
Name:         tasktracker-credentials
Namespace:    dso202-staging
Labels:       <none>
Annotations:  <none>

Type:  Opaque

Data
====
DB_PASSWORD:        24 bytes
DB_USER:            13 bytes
POSTGRES_PASSWORD:  24 bytes
POSTGRES_USER:      13 bytes

$ kubectl get resourcequota,limitrange -n dso202-dev
NAME                             REQUEST                                                        LIMIT                                   AGE
resourcequota/assignment-quota   pods: 0/10, requests.cpu: 0/1500m, requests.memory: 0/1536Mi   limits.cpu: 0/3, limits.memory: 0/3Gi   11s

NAME                               CREATED AT
limitrange/assignment-limitrange   2026-11-24T20:19:24Z

$ kubectl get resourcequota,limitrange -n dso202-staging
NAME                             REQUEST                                                        LIMIT                                   AGE
resourcequota/assignment-quota   pods: 0/10, requests.cpu: 0/1500m, requests.memory: 0/1536Mi   limits.cpu: 0/3, limits.memory: 0/3Gi   12s

NAME                               CREATED AT
limitrange/assignment-limitrange   2026-11-24T20:19:24Z

$ kubectl get role,rolebinding,serviceaccount readonly-viewer -n dso202-dev 2>/dev/null
NAME              AGE
readonly-viewer   11s
NAME                                           CREATED AT
role.rbac.authorization.k8s.io/readonly-role   2026-11-24T20:19:24Z

NAME                                                     ROLE                 AGE
rolebinding.rbac.authorization.k8s.io/readonly-binding   Role/readonly-role   11s

$ kubectl get secret tasktracker-credentials -n dso202-dev -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}'
SealedSecret/tasktracker-credentials
```

### No plaintext in Git (step 7)

Tested keys: `DB_USER` and `DB_PASSWORD` for dev and for staging, and the base64 encoding of each password.
`POSTGRES_USER` and `POSTGRES_PASSWORD` carry the same values, so they are covered.
```text
# For each distinct credential value, the whole history (all refs) is searched. Values are read from secrets-plain/ inside the command and never printed.
$ git log -p --all -S'<dev DB_USER value>' | head
(no output)

$ git log -p --all -S'<dev DB_PASSWORD value>' | head
(no output)

$ git log -p --all -S'<base64 of dev DB_PASSWORD>' | head
(no output)

$ git log -p --all -S'<staging DB_USER value>' | head
(no output)

$ git log -p --all -S'<staging DB_PASSWORD value>' | head
(no output)

$ git log -p --all -S'<base64 of staging DB_PASSWORD>' | head
(no output)

# POSTGRES_USER and POSTGRES_PASSWORD carry the same values as DB_USER and DB_PASSWORD, so the searches above cover all four keys.

$ git status --short --ignored
!! secrets-plain/
```

## Task 5 — Deliver the Workloads to dev and staging

Commit `740cfb5` added the smoke-test Job (Listing 13) and is tagged `v1.0.0`; commit `bafe41d` added the two
Applications. The smoke test's resources were raised from Listing 13's `10m/16Mi` to `50m/64Mi`: the
Assignment 2 LimitRange sets that minimum, and a server-side dry run of the listing's values was rejected with
`minimum cpu usage per Container is 50m, but request is 10m, minimum memory usage per Container is 64Mi, but request is 16Mi`.

### Wave order in dev (step 4)

`kubectl get pods -n dso202-dev -w --output-watch-events`, first line per Pod, readiness and status, with the local time:
```text
02:21:16 ADDED db-statefulset-0 0/1 Pending
02:21:20 MODIFIED db-statefulset-0 0/1 ContainerCreating
02:21:20 MODIFIED db-statefulset-0 0/1 Running
02:21:41 MODIFIED db-statefulset-0 1/1 Running
02:21:41 ADDED backend-deployment-6cbf846f89-c4h5c 0/1 Pending
02:21:41 MODIFIED backend-deployment-6cbf846f89-c4h5c 0/1 ContainerCreating
02:21:42 MODIFIED backend-deployment-6cbf846f89-c4h5c 0/1 Running
02:21:53 MODIFIED backend-deployment-6cbf846f89-c4h5c 1/1 Running
02:21:53 ADDED frontend-deployment-84f799988-hwv8n 0/1 Pending
02:21:53 MODIFIED frontend-deployment-84f799988-hwv8n 0/1 ContainerCreating
02:21:54 MODIFIED frontend-deployment-84f799988-hwv8n 0/1 Running
02:22:00 MODIFIED frontend-deployment-84f799988-hwv8n 1/1 Running
02:22:00 ADDED tasktracker-smoke-test-plh4v 0/1 Pending
02:22:00 MODIFIED tasktracker-smoke-test-plh4v 0/1 ContainerCreating
02:22:03 MODIFIED tasktracker-smoke-test-plh4v 1/1 Running
02:22:04 MODIFIED tasktracker-smoke-test-plh4v 0/1 Completed
02:27:51 ADDED backend-deployment-6cbf846f89-qmcgd 0/1 Pending
02:27:51 ADDED backend-deployment-6cbf846f89-m64x9 0/1 Pending
02:27:51 MODIFIED backend-deployment-6cbf846f89-qmcgd 0/1 ContainerCreating
02:27:51 MODIFIED backend-deployment-6cbf846f89-m64x9 0/1 ContainerCreating
02:27:51 MODIFIED backend-deployment-6cbf846f89-m64x9 0/1 Running
02:27:51 MODIFIED backend-deployment-6cbf846f89-qmcgd 0/1 Running
02:27:56 MODIFIED backend-deployment-6cbf846f89-qmcgd 0/1 Terminating
02:27:56 MODIFIED backend-deployment-6cbf846f89-m64x9 0/1 Terminating
02:27:56 MODIFIED backend-deployment-6cbf846f89-m64x9 0/1 Error
02:27:56 MODIFIED backend-deployment-6cbf846f89-qmcgd 0/1 Error
02:28:00 ADDED tasktracker-smoke-test-kbm8t 0/1 Pending
02:28:00 MODIFIED tasktracker-smoke-test-kbm8t 0/1 ContainerCreating
02:28:04 MODIFIED tasktracker-smoke-test-kbm8t 1/1 Running
02:28:04 MODIFIED tasktracker-smoke-test-kbm8t 0/1 Completed
02:41:23 ADDED tasktracker-smoke-test-926bq 0/1 Pending
02:41:23 MODIFIED tasktracker-smoke-test-926bq 0/1 ContainerCreating
02:41:26 MODIFIED tasktracker-smoke-test-926bq 1/1 Running
02:41:27 MODIFIED tasktracker-smoke-test-926bq 0/1 Completed
```

Each tier was created in the same second the previous one became ready: the database became ready (`1/1`) at
02:21:41 and the backend Pod was created at 02:21:41; the backend became ready at 02:21:53 and the frontend was
created at 02:21:53; the frontend became ready at 02:22:00 and the PostSync smoke test was created at 02:22:00 and
completed at 02:22:04. Argo CD waited for each wave to be Healthy before applying the next.
```text
$ kubectl get job -n dso202-dev
NAME                     STATUS     COMPLETIONS   DURATION   AGE
tasktracker-smoke-test   Complete   1/1           6s         19s

$ kubectl logs job/tasktracker-smoke-test -n dso202-dev
[{"id":1,"title":"Set up kind cluster","description":"Bring up the local cluster from Practical 1","status":"done","created_at":"2026-11-24T20:21:38.190Z"},{"id":2,"title":"Write namespace manifest","description":"One namespace for all assignment resources","status":"in_progress","created_at":"2026-11-24T20:21:38.190Z"},{"id":3,"title":"Wire ConfigMap and Secret","description":"DB_* and POSTGRES_* must carry matching values","status":"pending","created_at":"2026-11-24T20:21:38.190Z"}]

$ argocd app get tasktracker-dev
Name:               argocd/tasktracker-dev
Project:            dso202
Server:             https://kubernetes.default.svc
Namespace:          dso202-dev
URL:                https://localhost:8080/applications/tasktracker-dev
Source:
- Repo:             https://github.com/pomegranateis/dso202-gitops.git
  Target:           main
  Path:             charts/tasktracker
  Helm Values:      ../../environments/dev/values.yaml
SyncWindow:         Sync Allowed
Sync Policy:        Automated (Prune)
Sync Status:        Synced to main (bafe41d)
Health Status:      Healthy

GROUP  KIND         NAMESPACE   NAME                    STATUS     HEALTH   HOOK      MESSAGE
       ConfigMap    dso202-dev  frontend-config         Synced                        configmap/frontend-config created
       ConfigMap    dso202-dev  backend-config          Synced                        configmap/backend-config created
       ConfigMap    dso202-dev  database-config         Synced                        configmap/database-config created
       Service      dso202-dev  db-svc                  Synced     Healthy            service/db-svc created
       Service      dso202-dev  frontend-svc            Synced     Healthy            service/frontend-svc created
       Service      dso202-dev  backend-svc             Synced     Healthy            service/backend-svc created
apps   StatefulSet  dso202-dev  db-statefulset          Synced     Healthy            statefulset rolling update complete 1 pods at revision db-statefulset-6d7bbcddb4...
apps   Deployment   dso202-dev  backend-deployment      Synced     Healthy            deployment.apps/backend-deployment created
apps   Deployment   dso202-dev  frontend-deployment     Synced     Healthy            deployment.apps/frontend-deployment created
batch  Job          dso202-dev  tasktracker-smoke-test  Succeeded  Synced   PostSync  Reached expected number of succeeded pods

$ argocd app get tasktracker-staging
Name:               argocd/tasktracker-staging
Project:            dso202
Server:             https://kubernetes.default.svc
Namespace:          dso202-staging
URL:                https://localhost:8080/applications/tasktracker-staging
Source:
- Repo:             https://github.com/pomegranateis/dso202-gitops.git
  Target:           v1.0.0
  Path:             charts/tasktracker
  Helm Values:      ../../environments/staging/values.yaml
SyncWindow:         Sync Allowed
Sync Policy:        Manual
Sync Status:        OutOfSync from v1.0.0 (740cfb5)
Health Status:      Missing

GROUP  KIND         NAMESPACE       NAME                 STATUS     HEALTH   HOOK  MESSAGE
       ConfigMap    dso202-staging  backend-config       OutOfSync  Missing        
       ConfigMap    dso202-staging  database-config      OutOfSync  Missing        
       ConfigMap    dso202-staging  frontend-config      OutOfSync  Missing        
       Service      dso202-staging  backend-svc          OutOfSync  Missing        
       Service      dso202-staging  db-svc               OutOfSync  Missing        
       Service      dso202-staging  frontend-svc         OutOfSync  Missing        
apps   Deployment   dso202-staging  backend-deployment   OutOfSync  Missing        
apps   Deployment   dso202-staging  frontend-deployment  OutOfSync  Missing        
apps   StatefulSet  dso202-staging  db-statefulset       OutOfSync  Missing        

# root BEFORE the first staging sync
$ argocd app get root --refresh
Name:               argocd/root
Project:            platform
Server:             https://kubernetes.default.svc
Namespace:          argocd
URL:                https://localhost:8080/applications/root
Source:
- Repo:             https://github.com/pomegranateis/dso202-gitops.git
  Target:           main
  Path:             argocd
SyncWindow:         Sync Allowed
Sync Policy:        Automated (Prune)
Sync Status:        Synced to main (bafe41d)
Health Status:      Healthy

GROUP        KIND         NAMESPACE  NAME                 STATUS  HEALTH   HOOK  MESSAGE
argoproj.io  Application  argocd     tasktracker-staging  Synced  Missing        application.argoproj.io/tasktracker-staging unchanged
argoproj.io  Application  argocd     tasktracker-dev      Synced  Healthy        application.argoproj.io/tasktracker-dev unchanged
argoproj.io  AppProject   argocd     dso202               Synced                 
argoproj.io  Application  argocd     platform-dev         Synced  Healthy        
argoproj.io  Application  argocd     platform-staging     Synced  Healthy        
argoproj.io  Application  argocd     sealed-secrets       Synced  Healthy
```

![tasktracker-dev resource tree: ConfigMaps, Services, Deployments with their ReplicaSets and Pods, the StatefulSet and its Pod, and the PostSync Job](screenshots/a4-3-tasktracker-dev-tree.jpg)

The screenshot was taken after the Task 6 whitelist change; before it, the tree showed the same objects without the ReplicaSet and Pod nodes.

### CRUD cycle in dev (step 4)

The dev frontend is at `http://localhost:30080`. The browser calls the API at `BACKEND_URL`
(`http://localhost:8090`, set in `environments/dev/values.yaml`), reached with
`kubectl -n dso202-dev port-forward svc/backend-svc 8090:8080`.
```text
$ curl -s -o /dev/null -w 'frontend: HTTP %{http_code}\n' http://localhost:30080/
frontend: HTTP 200


$ curl -s http://localhost:30080/config.js | grep BACKEND_URL
  BACKEND_URL: "http://localhost:8090"


$ curl -s http://localhost:8090/api/status
{"status":"ok","db":"connected"}

# CREATE
$ curl -s -X POST -H 'Content-Type: application/json' -d '{"title":"GitOps CRUD check","description":"created through the dev backend"}' http://localhost:8090/api/tasks
{"id":4,"title":"GitOps CRUD check","description":"created through the dev backend","status":"pending","created_at":"2026-11-24T20:22:42.022Z"}

# READ
$ curl -s http://localhost:8090/api/tasks/4
{"id":4,"title":"GitOps CRUD check","description":"created through the dev backend","status":"pending","created_at":"2026-11-24T20:22:42.022Z"}

# UPDATE
$ curl -s -X PUT -H 'Content-Type: application/json' -d '{"title":"GitOps CRUD check","description":"created through the dev backend","status":"done"}' http://localhost:8090/api/tasks/4
{"id":4,"title":"GitOps CRUD check","description":"created through the dev backend","status":"done","created_at":"2026-11-24T20:22:42.022Z"}

# DELETE
$ curl -s -o /dev/null -w 'HTTP %{http_code}\n' -X DELETE http://localhost:8090/api/tasks/4
HTTP 204


$ curl -s -o /dev/null -w 'HTTP %{http_code}\n' http://localhost:8090/api/tasks/4
HTTP 404
```

![Dev UI at http://localhost:30080: BACKEND + DB ONLINE](screenshots/a4-5-dev-ui.jpg)

### Staging, synchronised by hand (step 5)

Before the sync, `tasktracker-staging` was `OutOfSync` / `Missing` (see `argocd app get tasktracker-staging` above).
Root state **before** the first staging sync: `Synced` / `Healthy` (output above). The brief expects the root not
to be `Healthy` at this point; in Argo CD v3.5.6 the parent's health does not take a child's `Missing` status into
account (the child is reported through its sync status instead), so the root stayed `Healthy`.
```text
$ argocd app sync tasktracker-staging
2026-11-25T02:22:48+06:00   apps  StatefulSet  dso202-staging        db-statefulset  OutOfSync  Missing
2026-11-25T02:22:48+06:00          ConfigMap   dso202-staging        backend-config  OutOfSync  Missing
2026-11-25T02:22:48+06:00          ConfigMap   dso202-staging       database-config  OutOfSync  Missing
2026-11-25T02:22:48+06:00          ConfigMap   dso202-staging       frontend-config  OutOfSync  Missing
2026-11-25T02:22:48+06:00            Service   dso202-staging           backend-svc  OutOfSync  Missing
2026-11-25T02:22:48+06:00            Service   dso202-staging                db-svc  OutOfSync  Missing
2026-11-25T02:22:48+06:00            Service   dso202-staging          frontend-svc  OutOfSync  Missing
2026-11-25T02:22:48+06:00   apps  Deployment   dso202-staging    backend-deployment  OutOfSync  Missing
2026-11-25T02:22:48+06:00   apps  Deployment   dso202-staging   frontend-deployment  OutOfSync  Missing
2026-11-25T02:22:48+06:00          ConfigMap  dso202-staging       database-config    Synced  Missing
2026-11-25T02:22:48+06:00          ConfigMap  dso202-staging        backend-config    Synced  Missing
2026-11-25T02:22:48+06:00          ConfigMap  dso202-staging       frontend-config    Synced  Missing
2026-11-25T02:22:48+06:00            Service   dso202-staging           backend-svc    Synced  Healthy
2026-11-25T02:22:48+06:00            Service   dso202-staging                db-svc    Synced  Healthy
2026-11-25T02:22:48+06:00            Service   dso202-staging          frontend-svc    Synced  Healthy
2026-11-25T02:22:48+06:00   apps  StatefulSet  dso202-staging        db-statefulset    Synced  Progressing
2026-11-25T02:22:50+06:00          ConfigMap   dso202-staging        backend-config    Synced  Missing                  configmap/backend-config created
2026-11-25T02:22:50+06:00            Service   dso202-staging                db-svc    Synced  Healthy                  service/db-svc created
2026-11-25T02:22:50+06:00            Service   dso202-staging           backend-svc    Synced  Healthy                  service/backend-svc created
2026-11-25T02:22:50+06:00          ConfigMap   dso202-staging       frontend-config    Synced  Missing                  configmap/frontend-config created
2026-11-25T02:22:50+06:00          ConfigMap   dso202-staging       database-config    Synced  Missing                  configmap/database-config created
2026-11-25T02:22:50+06:00            Service   dso202-staging          frontend-svc    Synced  Healthy                  service/frontend-svc created
2026-11-25T02:22:50+06:00   apps  StatefulSet  dso202-staging        db-statefulset    Synced  Progressing              statefulset.apps/db-statefulset created
2026-11-25T02:23:14+06:00   apps  StatefulSet  dso202-staging        db-statefulset    Synced  Healthy              statefulset.apps/db-statefulset created
2026-11-25T02:23:14+06:00   apps  Deployment  dso202-staging    backend-deployment    Synced  Progressing
2026-11-25T02:23:16+06:00   apps  Deployment   dso202-staging    backend-deployment    Synced  Progressing              deployment.apps/backend-deployment created
2026-11-25T02:23:16+06:00   apps  StatefulSet  dso202-staging        db-statefulset    Synced  Healthy                  statefulset rolling update complete 1 pods at revision db-statefulset-7cd7bb74f5...
2026-11-25T02:23:26+06:00   apps  Deployment  dso202-staging    backend-deployment    Synced  Healthy              deployment.apps/backend-deployment created
2026-11-25T02:23:26+06:00   apps  Deployment  dso202-staging   frontend-deployment    Synced  Progressing
2026-11-25T02:23:28+06:00   apps  Deployment  dso202-staging   frontend-deployment    Synced  Progressing              deployment.apps/frontend-deployment created
2026-11-25T02:23:32+06:00   apps  Deployment  dso202-staging   frontend-deployment    Synced  Healthy              deployment.apps/frontend-deployment created
2026-11-25T02:23:32+06:00  batch         Job  dso202-staging  tasktracker-smoke-test   Running   Synced    PostSync  job.batch/tasktracker-smoke-test created
2026-11-25T02:23:38+06:00  batch         Job  dso202-staging  tasktracker-smoke-test  Succeeded   Synced    PostSync  Reached expected number of succeeded pods
Name:               argocd/tasktracker-staging
Project:            dso202
Sync Status:        Synced to v1.0.0 (740cfb5)
Health Status:      Healthy
Operation:          Sync
Sync Revision:      740cfb5e356505b96d0b972860ffa021daa8a89d
Phase:              Succeeded
Start:              2026-11-25 02:22:48 +0600 +06
Finished:           2026-11-25 02:23:38 +0600 +06
Duration:           50s
Message:            successfully synced (no more tasks)
```

Root and staging **after** the first staging sync:
```text
# root AFTER the first staging sync
$ argocd app get root --refresh
Sync Status:        Synced to main (bafe41d)
Health Status:      Healthy

GROUP        KIND         NAMESPACE  NAME                 STATUS  HEALTH   HOOK  MESSAGE
argoproj.io  Application  argocd     tasktracker-staging  Synced  Healthy        application.argoproj.io/tasktracker-staging unchanged
argoproj.io  Application  argocd     tasktracker-dev      Synced  Healthy        application.argoproj.io/tasktracker-dev unchanged
argoproj.io  AppProject   argocd     dso202               Synced                 
argoproj.io  Application  argocd     platform-dev         Synced  Healthy        
argoproj.io  Application  argocd     platform-staging     Synced  Healthy        
argoproj.io  Application  argocd     sealed-secrets       Synced  Healthy        

$ kubectl get applications -n argocd
NAME                  SYNC STATUS   HEALTH STATUS
platform-dev          Synced        Healthy
platform-staging      Synced        Healthy
root                  Synced        Healthy
sealed-secrets        Synced        Healthy
tasktracker-dev       Synced        Healthy
tasktracker-staging   Synced        Healthy

$ kubectl get svc -n dso202-staging
NAME           TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)          AGE
backend-svc    ClusterIP   10.96.220.229   <none>        8080/TCP         65s
db-svc         ClusterIP   None            <none>        5432/TCP         65s
frontend-svc   NodePort    10.96.223.40    <none>        8080:30081/TCP   65s

$ kubectl port-forward -n dso202-staging svc/frontend-svc 8081:8080   (and svc/backend-svc 8091:8080)

$ curl -s -o /dev/null -w 'staging frontend: HTTP %{http_code}\n' http://localhost:8081/
staging frontend: HTTP 200
$ curl -s http://localhost:8081/config.js | grep BACKEND_URL
  BACKEND_URL: "http://localhost:8091"
$ curl -s http://localhost:8091/api/status
{"status":"ok","db":"connected"}

$ kubectl logs job/tasktracker-smoke-test -n dso202-staging
[{"id":1,"title":"Set up kind cluster","description":"Bring up the local cluster from Practical 1","status":"done","crea
```

![Staging UI at http://localhost:8081 (port-forward): BACKEND + DB ONLINE](screenshots/a4-6-staging-ui.jpg)

## Task 6 — Access Control for Argo CD Users

### Account, password, and the three permission states (steps 1-3)

Both passwords are read from files outside the repository and are not recorded.
```text
$ argocd account list
NAME      ENABLED  CAPABILITIES
admin     true     login
reviewer  true     login

$ argocd account update-password --account reviewer
(prompts answered from files outside the repository; neither password is recorded)
Password updated

$ argocd login localhost:8080 --username reviewer --insecure --name reviewer
'reviewer:login' logged in successfully
Context 'reviewer' updated

$ argocd --argocd-context reviewer app list
NAME                        CLUSTER                         NAMESPACE       PROJECT  STATUS  HEALTH   SYNCPOLICY  CONDITIONS  REPO                                                PATH                TARGET
argocd/tasktracker-dev      https://kubernetes.default.svc  dso202-dev      dso202   Synced  Healthy  Auto-Prune  <none>      https://github.com/pomegranateis/dso202-gitops.git  charts/tasktracker  main
argocd/tasktracker-staging  https://kubernetes.default.svc  dso202-staging  dso202   Synced  Healthy  Manual      <none>      https://github.com/pomegranateis/dso202-gitops.git  charts/tasktracker  v1.0.0

$ argocd --argocd-context reviewer account can-i get applications 'dso202/tasktracker-dev'
yes

$ argocd --argocd-context reviewer account can-i sync applications 'dso202/tasktracker-dev'
no

$ argocd --argocd-context reviewer account can-i get logs 'dso202/tasktracker-dev'
no

$ argocd --argocd-context reviewer proj get platform
{"level":"fatal","msg":"rpc error: code = PermissionDenied desc = permission denied: projects, get, platform, sub: reviewer, iat: 2026-11-24T20:24:11Z","time":"2026-11-25T02:24:11+06:00"}
```

### Log access granted by commit (step 4)

Commit `9df8c1c` enabled `p, reviewer, logs, get, dso202/*, allow` in `bootstrap/argocd/argocd-rbac-cm-patch.yaml`.
The bootstrap layer is not managed by the root Application, so the change was applied by re-running the
bootstrap command.
```text
$ kubectl apply -k bootstrap/argocd --server-side --force-conflicts
(all other objects: serverside-applied, unchanged in content)

$ argocd --argocd-context reviewer account can-i get logs 'dso202/tasktracker-dev'
yes

$ argocd --argocd-context reviewer account can-i get logs 'platform/platform-dev'
no

$ argocd --argocd-context reviewer account can-i sync applications 'dso202/tasktracker-dev'
no

$ kubectl get configmap argocd-rbac-cm -n argocd -o jsonpath={.data.policy\.csv} | grep "^ *p,"
p, reviewer, applications, get, dso202/*, allow
p, reviewer, projects, get, dso202, allow
p, reviewer, logs, get, dso202/*, allow

$ argocd context localhost:8080   (step 5: back to the admin session)
Already at context 'localhost:8080'
CURRENT  NAME            SERVER
*        localhost:8080  localhost:8080
         reviewer        localhost:8080
```

### Pods were not visible, so no logs could be served

With the log rule in place, the reviewer's UI and `argocd app logs` still returned no log lines, and the same
command as `admin` also returned nothing. `argocd app get tasktracker-dev -o tree` showed the Deployments,
StatefulSet and Job but none of their ReplicaSets or Pods, while `sealed-secrets` (in the unrestricted
`platform` project) showed `Deployment -> ReplicaSet -> Pod`. Argo CD leaves kinds that the project does not
permit out of an Application's resource tree, and it serves logs only for Pods in that tree. Commit `d270fd2`
added `ReplicaSet` and `Pod` to the `dso202` whitelist, with a comment. This does not let a commit do anything
new in practice: a `Deployment` is already permitted and can run any Pod.
```text
```text
# Before the change (whitelist without ReplicaSet and Pod):
$ argocd app get tasktracker-dev -o tree   -> Deployment/StatefulSet/Job only; no ReplicaSet or Pod nodes
$ argocd --argocd-context reviewer app logs tasktracker-dev --kind Deployment --name backend-deployment --tail 3
(no output; the same command as admin also printed nothing)
$ argocd app get sealed-secrets -o tree   (platform project, all kinds permitted) | grep -E "Deployment|ReplicaSet|Pod"
Deployment/sealed-secrets-controller                   Synced  Healthy  deployment.apps/sealed-secrets-controller created
└─ReplicaSet/sealed-secrets-controller-8b5ffdf69               Healthy  
  └─Pod/sealed-secrets-controller-8b5ffdf69-2bfvk              Healthy  

# After commit d270fd2 (ReplicaSet and Pod added to the dso202 whitelist):
$ argocd app get tasktracker-dev -o tree | grep -E "Deployment|StatefulSet|ReplicaSet|Pod|Job"
Deployment/backend-deployment                Synced     Healthy  deployment.apps/backend-deployment unchanged
└─ReplicaSet/backend-deployment-6cbf846f89              Healthy  
  └─Pod/backend-deployment-6cbf846f89-c4h5c             Healthy  
Deployment/frontend-deployment               Synced     Healthy  deployment.apps/frontend-deployment unchanged
└─ReplicaSet/frontend-deployment-84f799988              Healthy  
  └─Pod/frontend-deployment-84f799988-hwv8n             Healthy  
StatefulSet/db-statefulset                   Synced     Healthy  statefulset rolling update complete 1 pods at revision db-statefulset-6d7bbcddb4...
└─Pod/db-statefulset-0                                  Healthy  
Job/tasktracker-smoke-test                   Succeeded  Synced   Reached expected number of succeeded pods
└─Pod/tasktracker-smoke-test-926bq                      Healthy  

$ argocd --argocd-context reviewer app logs tasktracker-dev --kind Deployment --name backend-deployment --tail 3
[db] connected
[server] listening on :8080
$ argocd --argocd-context reviewer account can-i get logs 'platform/platform-dev'
no
```
```

### Reviewer session in the UI

The browser was signed out of the `admin` session and signed in as `reviewer` (a separate session, in place of a
private window). The reviewer sees only the two `dso202` Applications and can read Pod logs. The log viewer's
*follow* mode streams through the `kubectl port-forward`, which kept dropping the stream; with *follow* turned
off the viewer fetched the log once.

![reviewer reading the backend Pod's logs in tasktracker-dev](screenshots/a4-4-reviewer-logs.jpg)

![User Info: signed in as reviewer](screenshots/a4-4b-reviewer-user-info.jpg)

![reviewer's Applications page: only tasktracker-dev and tasktracker-staging](screenshots/a4-4c-reviewer-applications.jpg)

## Task 7 — A Release, a Faulty Release, and Recovery

**Adaptation.** The release images `frontend:1.1` and `backend:1.1` of section 8 were never issued (the tutor's
Docker Hub repositories contain only `1.0`), and section 10 forbids any other image. Task 7 was therefore carried
out with the issued `1.0` images, and each release is a values change (chart contract C2):

- **Frontend release 1.1.0:** two frontend replicas and a `RELEASE=1.1.0` marker in the Pods' environment (the
  page header of the 1.0 image cannot display a release number).
- **Backend release 1.2.0:** CORS restricted to each environment's own UI origin, and the database connection
  settings moved into the environment values. The first version of this release **deliberately** set
  `DB_PORT: "5433"` (PostgreSQL listens on 5432). This injected fault stands in for the unannounced start-up
  requirement of the missing backend 1.1 image, and it was declared as deliberate in pull request #3.

Every change went through a branch and a pull request, merged with squash. Task 8 had been done before Task 7,
while the release images were still expected; it does not depend on Task 7's state.

### Starting state
```text
$ date
Wed Nov 25 03:03:15 AM +06 2026

$ kubectl get applications -n argocd
NAME                  SYNC STATUS   HEALTH STATUS
platform-dev          Synced        Healthy
platform-staging      Synced        Healthy
root                  Synced        Healthy
sealed-secrets        Synced        Healthy
tasktracker-dev       Synced        Healthy
tasktracker-staging   Synced        Healthy

$ kubectl get deploy -n dso202-dev; kubectl get deploy -n dso202-staging
NAME                  READY   UP-TO-DATE   AVAILABLE   AGE
backend-deployment    1/1     1            1           41m
frontend-deployment   1/1     1            1           41m
NAME                  READY   UP-TO-DATE   AVAILABLE   AGE
backend-deployment    1/1     1            1           40m
frontend-deployment   1/1     1            1           39m

$ argocd app history tasktracker-dev | tail -3
0       2026-11-25 02:22:06 +0600 +06  main (bafe41d)
1       2026-11-25 02:28:06 +0600 +06  main (9df8c1c)
2       2026-11-25 02:41:29 +0600 +06  main (6d61d0b)
$ argocd app history tasktracker-staging
SOURCE  https://github.com/pomegranateis/dso202-gitops.git
ID      DATE                           REVISION
0       2026-11-25 02:23:38 +0600 +06  v1.0.0 (740cfb5)
1       2026-11-25 02:29:32 +0600 +06  v1.0.0 (740cfb5)
```

### Pull requests and history

PR merge times from GitHub are in UTC (local time is UTC+6).
```text
$ gh pr list --state all
#1  MERGED  21:03:47  release/frontend-1.1.0  Frontend release 1.1.0
#2  MERGED  21:04:49  promote/staging-v1.1.0  Promote staging to v1.1.0
#3  MERGED  21:06:15  release/backend-1.2.0  Backend release 1.2.0: per-environment CORS and database settings
#4  MERGED  21:10:57  revert/backend-1.2.0  Revert backend release 1.2.0 (dev Degraded)
#5  MERGED  21:17:39  release/backend-1.2.0-fixed  Backend release 1.2.0, fixed forward
#6  MERGED  21:18:51  promote/staging-v1.2.0  Promote staging to v1.2.0

$ git log --oneline --graph --decorate -n 15
* 0879cf4 (HEAD -> main, origin/main) Promote staging to v1.2.0 (#6)
* 7883dc7 (tag: v1.2.0) Backend release 1.2.0 (fixed forward): per-environment CORS origin, database port 5432 (#5)
* 40cc33b Revert "Backend release 1.2.0: per-environment CORS origin and database settings (#3)" (#4)
* 982fb28 Backend release 1.2.0: per-environment CORS origin and database settings (#3)
* 4ac77f5 Promote staging to v1.1.0 (#2)
* 486335d (tag: v1.1.0) Frontend release 1.1.0: two replicas and a release marker (dev and staging values) (#1)
* e2cc6c0 Docs: screenshots (Tasks 2, 3, 5, 6 and both UIs), whitelist change and reviewer log access in evidence and README
* d270fd2 dso202 project: permit ReplicaSet and Pod so Argo CD shows them and serves their logs
* 6d61d0b Docs: evidence for Task 8 (four drills with predictions and observations)
* ffe596f Revert "Task 8 drill 4: add a ResourceQuota to the workload chart (expect the project to reject it)"
* 099d6af Task 8 drill 4: add a ResourceQuota to the workload chart (expect the project to reject it)
* 4446e1d Task 8 drill 3: remove the throwaway ConfigMap from Git (expect pruning)
* 84ca178 Task 8 drill 3: add a throwaway ConfigMap to the dev platform layer
* e6ba1c2 Docs: README (purpose, versions, build sequence, credentials, Q1-Q4) and evidence for Tasks 1-6
* 9df8c1c Argo CD RBAC: grant the reviewer read access to Pod logs in the dso202 project
```

### Part A — frontend release 1.1.0, promoted (steps 1-3)

Pull request #1 changed `environments/dev/values.yaml` and `environments/staging/values.yaml`. Dev deployed it
28 seconds after the merge; staging, still on `v1.0.0`, did not change.
```text
$ gh pr merge 1 --squash --delete-branch   (main -> 486335d at 03:03:53)

$ argocd app get tasktracker-dev
Sync Status:        Synced to main (486335d)
Health Status:      Healthy
apps   Deployment   dso202-dev  frontend-deployment     Synced     Healthy            deployment.apps/frontend-deployment configured
batch  Job          dso202-dev  tasktracker-smoke-test  Succeeded  Synced   PostSync  Reached expected number of succeeded pods

$ kubectl get pods -n dso202-dev -l tier=frontend
NAME                                   READY   STATUS    RESTARTS   AGE
frontend-deployment-75897697bb-pkznm   1/1     Running   0          20s
frontend-deployment-75897697bb-t4kc6   1/1     Running   0          14s

$ kubectl exec -n dso202-dev deploy/frontend-deployment -- printenv RELEASE
1.1.0

$ argocd app history tasktracker-dev
SOURCE  https://github.com/pomegranateis/dso202-gitops.git
ID      DATE                           REVISION
0       2026-11-25 02:22:06 +0600 +06  main (bafe41d)
1       2026-11-25 02:28:06 +0600 +06  main (9df8c1c)
2       2026-11-25 02:41:29 +0600 +06  main (6d61d0b)
3       2026-11-25 03:04:20 +0600 +06  main (486335d)
```

`v1.1.0` was tagged on `486335d` and pull request #2 moved staging's `targetRevision` to it. Before the manual sync,
staging was `OutOfSync` but still ran the old frontend (one Pod, no `RELEASE` variable); after the sync it ran the
release.
```text
$ gh pr merge 2 --squash --delete-branch   (main -> 4ac77f5 at 03:04:54)

03:05:06 $ argocd app get tasktracker-staging
Sync Status:        OutOfSync from v1.1.0 (486335d)
Health Status:      Healthy
apps   Deployment   dso202-staging  frontend-deployment     OutOfSync  Healthy            deployment.apps/frontend-deployment unchanged

03:05:06 $ kubectl get pods -n dso202-staging -l tier=frontend
NAME                                   READY   STATUS    RESTARTS   AGE
frontend-deployment-5dcdd65cd9-jzldp   1/1     Running   0          41m

03:05:06 $ kubectl exec -n dso202-staging deploy/frontend-deployment -- printenv RELEASE
command terminated with exit code 1
(exit 1 - no RELEASE variable: staging still runs v1.0.0)

03:05:06 $ curl -s -o /dev/null -w '%{http_code}' http://localhost:8081/
200

03:05:06 $ argocd app sync tasktracker-staging
2026-11-25T03:05:13+06:00   apps  Deployment  dso202-staging   frontend-deployment    Synced  Progressing              deployment.apps/frontend-deployment configured
2026-11-25T03:05:24+06:00   apps  Deployment  dso202-staging   frontend-deployment    Synced  Healthy              deployment.apps/frontend-deployment configured
2026-11-25T03:05:30+06:00  batch         Job  dso202-staging  tasktracker-smoke-test  Succeeded   Synced    PostSync  Reached expected number of succeeded pods
Sync Status:        Synced to v1.1.0 (486335d)
Health Status:      Healthy
Phase:              Succeeded
Message:            successfully synced (no more tasks)
apps   Deployment   dso202-staging  frontend-deployment     Synced     Healthy            deployment.apps/frontend-deployment configured
batch  Job          dso202-staging  tasktracker-smoke-test  Succeeded  Synced   PostSync  Reached expected number of succeeded pods

03:05:31 $ kubectl get pods -n dso202-staging -l tier=frontend
NAME                                   READY   STATUS    RESTARTS   AGE
frontend-deployment-5dbc7f4f5d-czpzc   1/1     Running   0          21s
frontend-deployment-5dbc7f4f5d-l9hmj   1/1     Running   0          14s
03:05:32 $ kubectl exec -n dso202-staging deploy/frontend-deployment -- printenv RELEASE
1.1.0

$ argocd app history tasktracker-staging
SOURCE  https://github.com/pomegranateis/dso202-gitops.git
ID      DATE                           REVISION
0       2026-11-25 02:23:38 +0600 +06  v1.0.0 (740cfb5)
1       2026-11-25 02:29:32 +0600 +06  v1.0.0 (740cfb5)
2       2026-11-25 03:05:30 +0600 +06  v1.1.0 (486335d)
```

### Part B — the faulty backend release (steps 4-6)

Pull request #3 was merged as **`982fb28`, the bad commit**. Observations, without intervening, every 30 seconds:
```text
===== 03:06:30
backend-deployment-6cbf846f89-c4h5c   1/1   Running   0     44m
tasktracker-dev: OutOfSync / Healthy / revision 982fb28ef9e0e5e14338b03a315f97b84bcea5d9 / operation Running
frontend http://localhost:30080 -> 200   API (old backend via port-forward 8090) -> {"status":"ok","db":"connected"}
deployment condition: True NewReplicaSetAvailable: ReplicaSet "backend-deployment-6cbf846f89" has successfully progressed.
===== 03:06:58
backend-deployment-644c5b497f-wmr8b   0/1   Running   0     26s
backend-deployment-6cbf846f89-c4h5c   1/1   Running   0     45m
tasktracker-dev: Synced / Progressing / revision 982fb28ef9e0e5e14338b03a315f97b84bcea5d9 / operation Running
frontend http://localhost:30080 -> 200   API (old backend via port-forward 8090) -> {"status":"ok","db":"connected"}
deployment condition: True ReplicaSetUpdated: ReplicaSet "backend-deployment-644c5b497f" is progressing.
===== 03:07:26
backend-deployment-644c5b497f-wmr8b   0/1   Running   0     54s
backend-deployment-6cbf846f89-c4h5c   1/1   Running   0     45m
tasktracker-dev: Synced / Progressing / revision 982fb28ef9e0e5e14338b03a315f97b84bcea5d9 / operation Running
frontend http://localhost:30080 -> 200   API (old backend via port-forward 8090) -> {"status":"ok","db":"connected"}
deployment condition: True ReplicaSetUpdated: ReplicaSet "backend-deployment-644c5b497f" is progressing.
===== 03:07:54
backend-deployment-644c5b497f-wmr8b   0/1   Running   0     82s
backend-deployment-6cbf846f89-c4h5c   1/1   Running   0     46m
tasktracker-dev: Synced / Progressing / revision 982fb28ef9e0e5e14338b03a315f97b84bcea5d9 / operation Running
frontend http://localhost:30080 -> 200   API (old backend via port-forward 8090) -> {"status":"ok","db":"connected"}
deployment condition: True ReplicaSetUpdated: ReplicaSet "backend-deployment-644c5b497f" is progressing.
===== 03:08:22
backend-deployment-644c5b497f-wmr8b   0/1   Running   0     110s
backend-deployment-6cbf846f89-c4h5c   1/1   Running   0     46m
tasktracker-dev: Synced / Progressing / revision 982fb28ef9e0e5e14338b03a315f97b84bcea5d9 / operation Running
frontend http://localhost:30080 -> 200   API (old backend via port-forward 8090) -> {"status":"ok","db":"connected"}
deployment condition: True ReplicaSetUpdated: ReplicaSet "backend-deployment-644c5b497f" is progressing.
===== 03:08:51
backend-deployment-644c5b497f-wmr8b   0/1   Running   0     2m19s
backend-deployment-6cbf846f89-c4h5c   1/1   Running   0     47m
tasktracker-dev: Synced / Degraded / revision 982fb28ef9e0e5e14338b03a315f97b84bcea5d9 / operation Running
frontend http://localhost:30080 -> 200   API (old backend via port-forward 8090) -> {"status":"ok","db":"connected"}
deployment condition: False ProgressDeadlineExceeded: ReplicaSet "backend-deployment-644c5b497f" has timed out progressing.
===== 03:09:19
backend-deployment-644c5b497f-wmr8b   0/1   Running   0     2m47s
backend-deployment-6cbf846f89-c4h5c   1/1   Running   0     47m
tasktracker-dev: Synced / Degraded / revision 982fb28ef9e0e5e14338b03a315f97b84bcea5d9 / operation Running
frontend http://localhost:30080 -> 200   API (old backend via port-forward 8090) -> {"status":"ok","db":"connected"}
deployment condition: False ProgressDeadlineExceeded: ReplicaSet "backend-deployment-644c5b497f" has timed out progressing.
===== 03:09:47
backend-deployment-644c5b497f-wmr8b   0/1   Running   0     3m15s
backend-deployment-6cbf846f89-c4h5c   1/1   Running   0     48m
tasktracker-dev: Synced / Degraded / revision 982fb28ef9e0e5e14338b03a315f97b84bcea5d9 / operation Running
frontend http://localhost:30080 -> 200   API (old backend via port-forward 8090) -> {"status":"ok","db":"connected"}
deployment condition: False ProgressDeadlineExceeded: ReplicaSet "backend-deployment-644c5b497f" has timed out progressing.
```

- **New backend Pod** (`644c5b497f-wmr8b`): `Running` but never `Ready` (`0/1`).
- **Old backend Pod** (`6cbf846f89-c4h5c`): kept running (`1/1`), and the Service kept routing to it; the frontend
  answered `200` and the API answered `connected` throughout.
- **Application:** `Synced` / `Progressing`, then **`Synced` / `Degraded`** at 03:08:51, when the Deployment
  reported `ProgressDeadlineExceeded` (`progressDeadlineSeconds: 120`, chart contract C6). The root Application
  also became `Degraded`, because the restored health check (Listing 4) reports a child's health upward.
- **Smoke test:** did not run for `982fb28`. The sync operation stayed `Running`, waiting for the resources to
  become healthy before the PostSync phase; the only Job is the one from the previous sync.
```text
$ kubectl get applications -n argocd
NAME                  SYNC STATUS   HEALTH STATUS
platform-dev          Synced        Healthy
platform-staging      Synced        Healthy
root                  Synced        Degraded
sealed-secrets        Synced        Healthy
tasktracker-dev       Synced        Degraded
tasktracker-staging   Synced        Healthy

$ argocd app get tasktracker-dev
Sync Status:        Synced to main (982fb28)
Health Status:      Degraded
apps   Deployment   dso202-dev  backend-deployment      Synced  Degraded        Deployment "backend-deployment" exceeded its progress deadline
batch  Job          dso202-dev  tasktracker-smoke-test          Healthy         

$ kubectl get job -n dso202-dev   (smoke test from the previous sync; no new run for 982fb28)
NAME                     COMPLETIONS   CREATED
tasktracker-smoke-test   1             2026-11-24T21:04:14Z

$ kubectl get pods -n dso202-dev
NAME                                   READY   STATUS      RESTARTS   AGE
backend-deployment-644c5b497f-wmr8b    0/1     Running     0          3m56s
backend-deployment-6cbf846f89-c4h5c    1/1     Running     0          48m
db-statefulset-0                       1/1     Running     0          49m
frontend-deployment-75897697bb-pkznm   1/1     Running     0          6m27s
frontend-deployment-75897697bb-t4kc6   1/1     Running     0          6m21s
tasktracker-smoke-test-j5ws9           0/1     Completed   0          6m14s
```

**Diagnosis (step 6).** The exact log line: **`[db] not reachable yet (ECONNREFUSED), retrying in 2000ms`**,
repeated every two seconds. The backend waits for the database before it starts listening, so the readiness
probe gets `connection refused` on port 8080. The Pod's environment shows the cause: `DB_PORT=5433`.
```text
$ kubectl describe pod backend-deployment-644c5b497f-wmr8b -n dso202-dev   (excerpt: Conditions, readiness probe and Events)
    Readiness:  http-get http://:8080/api/status delay=5s timeout=3s period=5s #success=1 #failure=6
Conditions:
  Type                        Status
  PodReadyToStartContainers   True 
  Initialized                 True 
  Ready                       False 
  ContainersReady             False 
  PodScheduled                True 
Events:
  Type     Reason     Age                    From               Message
  ----     ------     ----                   ----               -------
  Normal   Scheduled  3m55s                  default-scheduler  Successfully assigned dso202-dev/backend-deployment-644c5b497f-wmr8b to worker-node-2
  Normal   Pulled     3m55s                  kubelet            spec.containers{backend}: Container image "pomegranatei/dso202-backend:1.0" already present on machine and can be accessed by the pod
  Normal   Created    3m55s                  kubelet            spec.containers{backend}: Container created
  Normal   Started    3m55s                  kubelet            spec.containers{backend}: Container started
  Warning  Unhealthy  115s (x25 over 3m50s)  kubelet            spec.containers{backend}: Readiness probe failed: Get "http://10.244.1.20:8080/api/status": dial tcp 10.244.1.20:8080: connect: connection refused

$ kubectl logs backend-deployment-644c5b497f-wmr8b -n dso202-dev | tail -5
[db] not reachable yet (ECONNREFUSED), retrying in 2000ms
[db] not reachable yet (ECONNREFUSED), retrying in 2000ms
[db] not reachable yet (ECONNREFUSED), retrying in 2000ms
[db] not reachable yet (ECONNREFUSED), retrying in 2000ms
[db] not reachable yet (ECONNREFUSED), retrying in 2000ms

$ kubectl exec -n dso202-dev backend-deployment-644c5b497f-wmr8b -- printenv DB_HOST DB_PORT
db-svc
5433
```

### `argocd app rollback` (step 7)
```text
$ argocd app rollback tasktracker-dev
{"level":"fatal","msg":"rpc error: code = FailedPrecondition desc = rollback cannot be initiated when auto-sync is enabled","time":"2026-11-25T03:10:35+06:00"}
(exit code 20)

$ argocd app history tasktracker-dev
SOURCE  https://github.com/pomegranateis/dso202-gitops.git
ID      DATE                           REVISION
0       2026-11-25 02:22:06 +0600 +06  main (bafe41d)
1       2026-11-25 02:28:06 +0600 +06  main (9df8c1c)
2       2026-11-25 02:41:29 +0600 +06  main (6d61d0b)
3       2026-11-25 03:04:20 +0600 +06  main (486335d)
```

Refused with `FailedPrecondition`: *rollback cannot be initiated when auto-sync is enabled*. The history has no
entry for `982fb28`, because its sync operation never completed.

### Recovery by `git revert` (step 8)

Pull request #4 reverted `982fb28` (squash-merged, so no `-m 1` was needed); main became `40cc33b`. Dev did **not**
recover at once: the sync operation for the bad revision was still running under the Application's retry policy
(`limit: 5`), which keeps retrying the same revision, and automated sync does not start a new operation while one
is running. After the fifth attempt failed, Argo CD synchronised the revert by itself.
```text
$ git checkout -b revert/backend-1.2.0; git revert 982fb28; git push -u origin revert/backend-1.2.0
$ gh pr create ... ; gh pr merge 4 --squash   (main -> 40cc33b)

03:15:08 $ argocd app get tasktracker-dev
Sync Status:        OutOfSync from main (40cc33b)
Health Status:      Degraded
apps   Deployment   dso202-dev  backend-deployment      OutOfSync  Degraded        Deployment "backend-deployment" exceeded its progress deadline
batch  Job          dso202-dev  tasktracker-smoke-test             Healthy         

03:15:08 $ kubectl get pods -n dso202-dev -l tier=backend
NAME                                  READY   STATUS    RESTARTS   AGE
backend-deployment-644c5b497f-wmr8b   0/1     Running   0          8m36s
backend-deployment-6cbf846f89-c4h5c   1/1     Running   0          53m
$ kubectl exec -n dso202-dev deploy/backend-deployment -- printenv DB_PORT CORS_ORIGIN
5432
*

$ kubectl get applications -n argocd
NAME                  SYNC STATUS   HEALTH STATUS
platform-dev          Synced        Healthy
platform-staging      Synced        Healthy
root                  Synced        Degraded
sealed-secrets        Synced        Healthy
tasktracker-dev       OutOfSync     Degraded
tasktracker-staging   Synced        Healthy

$ argocd app history tasktracker-dev
SOURCE  https://github.com/pomegranateis/dso202-gitops.git
ID      DATE                           REVISION
0       2026-11-25 02:22:06 +0600 +06  main (bafe41d)
1       2026-11-25 02:28:06 +0600 +06  main (9df8c1c)
2       2026-11-25 02:41:29 +0600 +06  main (6d61d0b)
3       2026-11-25 03:04:20 +0600 +06  main (486335d)
```
```text
03:15:30 operation on tasktracker-dev: Running for 982fb28ef9e0e5e14338b03a315f97b84bcea5d9 - one or more synchronization tasks completed unsuccessfully. Retrying attempt #5 at 9:16PM.
03:15:30 operation=Running rev=982fb28 sync=OutOfSync health=Degraded
03:16:55 operation=Running rev=40cc33b sync=OutOfSync health=Degraded
03:16:59 operation=Running rev=40cc33b sync=Synced health=Healthy
03:17:07 operation=Succeeded rev=40cc33b sync=Synced health=Healthy

03:17:07 $ kubectl get pods -n dso202-dev -l tier=backend
NAME                                  READY   STATUS    RESTARTS   AGE
backend-deployment-6cbf846f89-c4h5c   1/1     Running   0          55m
03:17:22 $ argocd app get tasktracker-dev
Sync Status:        Synced to main (40cc33b)
Health Status:      Healthy
apps   Deployment   dso202-dev  backend-deployment      Synced     Healthy            deployment.apps/backend-deployment configured
batch  Job          dso202-dev  tasktracker-smoke-test  Succeeded  Synced   PostSync  Reached expected number of succeeded pods

$ kubectl get applications -n argocd
NAME                  SYNC STATUS   HEALTH STATUS
platform-dev          Synced        Healthy
platform-staging      Synced        Healthy
root                  Synced        Healthy
sealed-secrets        Synced        Healthy
tasktracker-dev       Synced        Healthy
tasktracker-staging   Synced        Healthy

$ argocd app history tasktracker-dev
SOURCE  https://github.com/pomegranateis/dso202-gitops.git
ID      DATE                           REVISION
0       2026-11-25 02:22:06 +0600 +06  main (bafe41d)
1       2026-11-25 02:28:06 +0600 +06  main (9df8c1c)
2       2026-11-25 02:41:29 +0600 +06  main (6d61d0b)
3       2026-11-25 03:04:20 +0600 +06  main (486335d)
4       2026-11-25 03:17:06 +0600 +06  main (40cc33b)
```

### Fix forward (step 9)

Pull request #5 re-applied the release with `DB_PORT: "5432"`. Dev became `Healthy` 32 seconds after the merge,
with a passing smoke test.
```text
$ gh pr merge 5 --squash   (main -> 7883dc7 at 03:17:44)

03:18:15 $ argocd app get tasktracker-dev
Sync Status:        Synced to main (7883dc7)
Health Status:      Healthy
apps   Deployment   dso202-dev  backend-deployment      Synced     Healthy            deployment.apps/backend-deployment configured
batch  Job          dso202-dev  tasktracker-smoke-test  Succeeded  Synced   PostSync  Reached expected number of succeeded pods

$ kubectl get pods -n dso202-dev -l tier=backend
NAME                                  READY   STATUS    RESTARTS   AGE
backend-deployment-64d65dd597-k4ltr   1/1     Running   0          26s
$ kubectl logs backend-deployment-64d65dd597-k4ltr -n dso202-dev
[db] connected
[server] listening on :8080
$ kubectl exec -n dso202-dev backend-deployment-64d65dd597-k4ltr -- printenv DB_PORT CORS_ORIGIN
5432
http://localhost:30080

$ kubectl logs job/tasktracker-smoke-test -n dso202-dev | cut -c1-80
[{"id":1,"title":"Set up kind cluster","description":"Bring up the local cluster

$ curl -s -D - -o /dev/null -H 'Origin: http://localhost:30080' http://localhost:8090/api/status | grep -i -E 'HTTP/|access-control'
(the port-forward to the replaced Pod had dropped; re-established and run again:)
HTTP/1.1 200 OK
Access-Control-Allow-Origin: http://localhost:30080

$ argocd app history tasktracker-dev
SOURCE  https://github.com/pomegranateis/dso202-gitops.git
ID      DATE                           REVISION
0       2026-11-25 02:22:06 +0600 +06  main (bafe41d)
1       2026-11-25 02:28:06 +0600 +06  main (9df8c1c)
2       2026-11-25 02:41:29 +0600 +06  main (6d61d0b)
3       2026-11-25 03:04:20 +0600 +06  main (486335d)
4       2026-11-25 03:17:06 +0600 +06  main (40cc33b)
5       2026-11-25 03:18:13 +0600 +06  main (7883dc7)
```

### Promotion of the fixed release (step 10)

`v1.2.0` was tagged on `7883dc7` and pull request #6 moved staging to it. Staging never ran the faulty backend:
its history contains only `v1.0.0`, `v1.1.0` and `v1.2.0`, none of which has `DB_PORT: "5433"`, and no tag points
at `982fb28`.
```text
$ git tag -a v1.2.0; git push origin v1.2.0   (v1.2.0 -> 7883dc7)
$ gh pr merge 6 --squash   (main -> 0879cf4)

03:19:08 $ argocd app get tasktracker-staging   (before the manual sync)
Sync Status:        OutOfSync from v1.2.0 (7883dc7)
Health Status:      Healthy
apps   Deployment   dso202-staging  backend-deployment      OutOfSync  Healthy            deployment.apps/backend-deployment unchanged
03:19:08 $ kubectl exec -n dso202-staging deploy/backend-deployment -- printenv CORS_ORIGIN
*

03:19:08 $ argocd app sync tasktracker-staging
2026-11-25T03:19:13+06:00   apps  Deployment   dso202-staging    backend-deployment    Synced  Progressing              deployment.apps/backend-deployment configured
2026-11-25T03:19:22+06:00   apps  Deployment  dso202-staging    backend-deployment    Synced  Healthy              deployment.apps/backend-deployment configured
2026-11-25T03:19:30+06:00  batch         Job  dso202-staging  tasktracker-smoke-test  Succeeded   Synced    PostSync  Reached expected number of succeeded pods
apps   Deployment   dso202-staging  backend-deployment      Synced     Healthy            deployment.apps/backend-deployment configured
batch  Job          dso202-staging  tasktracker-smoke-test  Succeeded  Synced   PostSync  Reached expected number of succeeded pods
Health Status:      Healthy
Message:            successfully synced (no more tasks)
Phase:              Succeeded
Sync Status:        Synced to v1.2.0 (7883dc7)

03:19:32 $ kubectl get pods -n dso202-staging -l tier=backend
NAME                                 READY   STATUS    RESTARTS   AGE
backend-deployment-767c5c85d-pt6pf   1/1     Running   0          21s
$ kubectl logs backend-deployment-767c5c85d-pt6pf -n dso202-staging
[db] connected
[server] listening on :8080
$ kubectl exec -n dso202-staging backend-deployment-767c5c85d-pt6pf -- printenv DB_PORT CORS_ORIGIN
5432
http://localhost:8081

$ argocd app history tasktracker-staging
SOURCE  https://github.com/pomegranateis/dso202-gitops.git
ID      DATE                           REVISION
0       2026-11-25 02:23:38 +0600 +06  v1.0.0 (740cfb5)
1       2026-11-25 02:29:32 +0600 +06  v1.0.0 (740cfb5)
2       2026-11-25 03:05:30 +0600 +06  v1.1.0 (486335d)
3       2026-11-25 03:19:30 +0600 +06  v1.2.0 (7883dc7)

# Staging never ran the faulty backend: DB_PORT in the staging values at each revision staging has read
$ git show v1.0.0:environments/staging/values.yaml | grep DB_PORT
(none: chart default 5432)
$ git show v1.1.0:environments/staging/values.yaml | grep DB_PORT
(none: chart default 5432)
$ git show v1.2.0:environments/staging/values.yaml | grep DB_PORT
  # settings. 982fb28 set DB_PORT to 5433 and was reverted (40cc33b);
    DB_PORT: "5432"
$ git tag --contains 982fb28 --points-at 982fb28
(no tag points at the faulty commit)
```


## Task 8 — Drift, Pruning and Project Guardrails

Each prediction was written before the action. Times are local. Task 8 was done before Task 7 (see the note in Task 7).

### Drill 1 - drift in dev is reverted

**Prediction** (written 02:27:48, before running anything): Scaling the dev backend to 3 by hand makes the live state differ from Git (replicas: 1). Because tasktracker-dev has selfHeal: true, Argo CD will detect the drift within seconds and scale it back to 1; the extra Pods will be created and then terminated.

```text
$ kubectl get deployment -n dso202-dev
NAME                  READY   UP-TO-DATE   AVAILABLE   AGE
backend-deployment    1/1     1            1           6m7s
frontend-deployment   1/1     1            1           5m55s

$ kubectl get deployment/backend-deployment -n dso202-dev -w    (started before the change; timestamps added)
02:27:51 $ kubectl scale deployment/backend-deployment -n dso202-dev --replicas=3
deployment.apps/backend-deployment scaled
02:27:48 NAME                 READY   UP-TO-DATE   AVAILABLE   AGE
02:27:48 backend-deployment   1/1     1            1           6m7s
02:27:51 backend-deployment   1/3     1            1           6m10s
02:27:51 backend-deployment   1/3     1            1           6m10s
02:27:51 backend-deployment   1/3     1            1           6m10s
02:27:51 backend-deployment   1/3     3            1           6m10s
02:27:56 backend-deployment   1/1     3            1           6m15s
02:27:56 backend-deployment   1/1     3            1           6m15s
02:27:56 backend-deployment   1/1     3            1           6m15s
02:27:56 backend-deployment   1/1     1            1           6m15s
02:27:56 backend-deployment   1/1     1            1           6m15s
02:27:56 backend-deployment   1/1     1            1           6m15s

$ kubectl get events -n argocd --field-selector involvedObject.name=tasktracker-dev --sort-by=.lastTimestamp | tail -6
33s         Normal   OperationStarted     application/tasktracker-dev   Initiated automated sync to '9df8c1c9d783327d25c17e749ba4a3deb005a520'
33s         Normal   ResourceUpdated      application/tasktracker-dev   Updated sync status: Synced -> OutOfSync
33s         Normal   ResourceUpdated      application/tasktracker-dev   Updated health status: Healthy -> Progressing
31s         Normal   ResourceUpdated      application/tasktracker-dev   Updated sync status: OutOfSync -> Synced
31s         Normal   ResourceUpdated      application/tasktracker-dev   Updated health status: Progressing -> Healthy
21s         Normal   OperationCompleted   application/tasktracker-dev   Sync operation to 9df8c1c9d783327d25c17e749ba4a3deb005a520 succeeded

$ kubectl get deployment/backend-deployment -n dso202-dev
NAME                 READY   UP-TO-DATE   AVAILABLE   AGE
backend-deployment   1/1     1            1           6m46s
```

**Observation:** the manual scale to 3 at 02:27:51 was reverted to 1 replica at 02:27:56, five seconds later, before the two extra Pods became ready. **Prediction held.** `selfHeal: true` in `argocd/applications/tasktracker-dev.yaml` makes Argo CD re-apply the desired state as soon as it detects drift (principle 4, continuously reconciled). Restore: none needed; Argo CD restored it.

### Drill 2 - drift in staging is reported, not reverted

**Prediction** (written 02:28:37, before running anything): Staging has no automated sync, so the manual scale to 3 will remain. Argo CD will only report it: tasktracker-staging becomes OutOfSync and argocd app diff shows replicas 3 (live) against 1 (Git). Only a manual argocd app sync will restore 1 replica.

```text
02:28:37 $ kubectl scale deployment/backend-deployment -n dso202-staging --replicas=3
deployment.apps/backend-deployment scaled

02:29:17 $ kubectl get deployment/backend-deployment -n dso202-staging   (40 s later)
NAME                 READY   UP-TO-DATE   AVAILABLE   AGE
backend-deployment   3/3     3            3           6m3s

02:29:17 $ argocd app get tasktracker-staging --refresh
Sync Status:        OutOfSync from v1.0.0 (740cfb5)
Health Status:      Healthy
apps   Deployment   dso202-staging  backend-deployment      OutOfSync  Healthy            deployment.apps/backend-deployment created

02:29:19 $ argocd app diff tasktracker-staging

===== apps/Deployment dso202-staging/backend-deployment ======
154c154
<   replicas: 3
---
>   replicas: 1

02:29:19 $ kubectl get deployment/backend-deployment -n dso202-staging   (still not reverted)
NAME                 READY   UP-TO-DATE   AVAILABLE   AGE
backend-deployment   3/3     3            3           6m5s

02:29:19 $ argocd app sync tasktracker-staging
2026-11-25T02:29:20+06:00   apps  Deployment   dso202-staging    backend-deployment    OutOfSync  Healthy              
2026-11-25T02:29:20+06:00  batch         Job   dso202-staging  tasktracker-smoke-test             Healthy              
2026-11-25T02:29:22+06:00   apps  Deployment  dso202-staging    backend-deployment    Synced  Healthy              
2026-11-25T02:29:24+06:00   apps  Deployment   dso202-staging    backend-deployment    Synced  Healthy              deployment.apps/backend-deployment configured
2026-11-25T02:29:27+06:00  batch         Job  dso202-staging  tasktracker-smoke-test   Running   Synced    PostSync  job.batch/tasktracker-smoke-test created
2026-11-25T02:29:32+06:00  batch         Job  dso202-staging  tasktracker-smoke-test  Succeeded   Synced    PostSync  Reached expected number of succeeded pods
Sync Status:        Synced to v1.0.0 (740cfb5)
Health Status:      Healthy
Phase:              Succeeded
Message:            successfully synced (no more tasks)
apps   Deployment   dso202-staging  backend-deployment      Synced     Healthy            deployment.apps/backend-deployment configured
batch  Job          dso202-staging  tasktracker-smoke-test  Succeeded  Synced   PostSync  Reached expected number of succeeded pods

02:29:34 $ kubectl get deployment/backend-deployment -n dso202-staging
NAME                 READY   UP-TO-DATE   AVAILABLE   AGE
backend-deployment   1/1     1            1           6m20s
```

**Observation:** the Deployment stayed at 3/3 replicas; after a refresh `tasktracker-staging` was `OutOfSync` (and still `Healthy`, because three ready replicas are healthy), and `argocd app diff` showed exactly `replicas: 3` live against `1` in Git. Nothing reverted it until the manual `argocd app sync` at 02:29:19, after which it was 1/1 and the smoke test passed again. **Prediction held.** `tasktracker-staging` has no `automated` block, so Argo CD still compares continuously (principle 4: drift is detected and reported) but applies nothing until a person synchronises: the approval gate. Restore: the manual sync above.

### Drill 3 - removing a file prunes the object

**Prediction** (written 02:29:46, before running anything): Adding platform/dev/prune-drill.yaml makes platform-dev create the ConfigMap prune-drill in dso202-dev within about a minute of the push. Deleting the file with git rm makes Argo CD delete the ConfigMap, because platform-dev has prune: true.

```text
02:29:56 $ git commit (add platform/dev/prune-drill.yaml) -> 84ca178; git push
02:29:56 $ kubectl get configmap prune-drill -n dso202-dev
NAME          DATA   AGE
prune-drill   1      2s

02:30:07 $ git rm platform/dev/prune-drill.yaml; git commit -> 4446e1d
02:30:07 $ git push   -> failed: 'failed to push some refs' (network); nothing reached GitHub
02:31:40 $ kubectl get configmap prune-drill -n dso202-dev   -> still present (AGE 106s), as expected without the push
02:31:58 $ git push   -> 84ca178..4446e1d  main -> main
02:32:04 $ kubectl get configmap prune-drill -n dso202-dev
Error from server (NotFound): configmaps "prune-drill" not found

$ kubectl get events -n argocd --field-selector involvedObject.name=platform-dev --sort-by=.lastTimestamp | tail -4
3s          Normal   OperationStarted     application/platform-dev   Initiated automated sync to '4446e1d67c925f9a5996eca0704a8eee8c2d6ed6'
3s          Normal   ResourceUpdated      application/platform-dev   Updated sync status: Synced -> OutOfSync
3s          Normal   ResourceUpdated      application/platform-dev   Updated sync status: OutOfSync -> Synced
3s          Normal   OperationCompleted   application/platform-dev   Sync operation to 4446e1d67c925f9a5996eca0704a8eee8c2d6ed6 succeeded

$ argocd app get platform-dev
Sync Status:        Synced to main (4446e1d)
Health Status:      Healthy
```

**Observation:** the ConfigMap appeared from Git at 02:29:56 and was deleted at 02:32:04, six seconds after the removal commit reached GitHub; while the push had failed it stayed, because Argo CD only follows what is on GitHub. `platform-dev` is `Synced` to the removal commit `4446e1d`. **Prediction held.** `prune: true` in `argocd/applications/platform-dev.yaml` lets Argo CD delete live objects whose file is gone from Git, so the cluster never keeps objects that Git no longer describes (principles 1 and 4). The namespace manifest in the same directory (`platform/dev/namespace.yaml`, Listing 11) carries `argocd.argoproj.io/sync-options: Prune=false`: deleting that file would not delete the namespace (and everything inside it); Argo CD would leave it and report it as no longer in Git, so removing a namespace stays a deliberate manual step. That protection is explained, not tested. Restore: the removal commit is itself the restored state.

### Drill 4 - the project rejects a resource it does not permit

**Prediction** (written 02:32:16, before running anything): Adding a ResourceQuota template to the chart and pushing it makes tasktracker-dev try to apply it. ResourceQuota is not in the dso202 namespaceResourceWhitelist, so the sync will be refused with a "not permitted in project dso202" error and no quota will be created; the existing workloads keep running. Staging is unaffected: it reads tag v1.0.0, which does not contain the file, and it never syncs automatically.

```text
02:32:3x $ git commit (add charts/tasktracker/templates/drill-quota.yaml) -> 099d6af; git push

02:32:49 $ argocd app get tasktracker-dev
Name:               argocd/tasktracker-dev
Project:            dso202
Server:             https://kubernetes.default.svc
Namespace:          dso202-dev
URL:                https://localhost:8080/applications/tasktracker-dev
Source:
- Repo:             https://github.com/pomegranateis/dso202-gitops.git
  Target:           main
  Path:             charts/tasktracker
  Helm Values:      ../../environments/dev/values.yaml
SyncWindow:         Sync Allowed
Sync Policy:        Automated (Prune)
Sync Status:        OutOfSync from main (099d6af)
Health Status:      Healthy
GROUP  KIND           NAMESPACE   NAME                    STATUS   HEALTH   HOOK  MESSAGE
       ResourceQuota  dso202-dev  drill-quota             Unknown  Missing        resource :ResourceQuota is not permitted in project dso202
       ConfigMap      dso202-dev  backend-config          Synced                  
       ConfigMap      dso202-dev  database-config         Synced                  
       ConfigMap      dso202-dev  frontend-config         Synced                  
       Service        dso202-dev  backend-svc             Synced   Healthy        
       Service        dso202-dev  db-svc                  Synced   Healthy        
       Service        dso202-dev  frontend-svc            Synced   Healthy        
apps   Deployment     dso202-dev  backend-deployment      Synced   Healthy        
apps   Deployment     dso202-dev  frontend-deployment     Synced   Healthy        
apps   StatefulSet    dso202-dev  db-statefulset          Synced   Healthy        
batch  Job            dso202-dev  tasktracker-smoke-test           Healthy        

02:32:49 $ kubectl get applications -n argocd
NAME                  SYNC STATUS   HEALTH STATUS
platform-dev          Synced        Healthy
platform-staging      Synced        Healthy
root                  Synced        Healthy
sealed-secrets        Synced        Healthy
tasktracker-dev       OutOfSync     Healthy
tasktracker-staging   Synced        Healthy

02:32:49 $ kubectl get resourcequota -n dso202-dev
NAME               REQUEST                                                               LIMIT                                         AGE
assignment-quota   pods: 3/10, requests.cpu: 350m/1500m, requests.memory: 512Mi/1536Mi   limits.cpu: 1150m/3, limits.memory: 1Gi/3Gi   13m

02:32:49 $ argocd app get tasktracker-staging
Sync Status:        Synced to v1.0.0 (740cfb5)
Health Status:      Healthy

02:35:02 $ kubectl get application tasktracker-dev -n argocd -o jsonpath='{.status.conditions[*]}'   (before the revert)
Running: one or more synchronization tasks are not valid: resource :ResourceQuota is not permitted in project dso202. Retrying attempt #2 at 8:33PM.

02:35:14 $ git revert --no-edit 099d6af -> ffe596f; git push
02:35:17 $ argocd app get tasktracker-dev
Sync Status:        Synced to main (ffe596f)
Health Status:      Healthy
       ResourceQuota  dso202-dev  drill-quota                     SyncFailed        resource :ResourceQuota is not permitted in project dso202
02:35:17 $ kubectl get applications -n argocd
NAME                  SYNC STATUS   HEALTH STATUS
platform-dev          Synced        Healthy
platform-staging      Synced        Healthy
root                  Synced        Healthy
sealed-secrets        Synced        Healthy
tasktracker-dev       Synced        Healthy
tasktracker-staging   Synced        Healthy
```

**Observation:** after the push, `tasktracker-dev` became `OutOfSync` and stayed `Healthy`: the sync was refused with `resource :ResourceQuota is not permitted in project dso202` (retried with backoff, refused each time), no `drill-quota` object was created, and the running workloads were untouched. Staging stayed `Synced` to `v1.0.0`. After `git revert` of `099d6af` (commit `ffe596f`) dev returned to `Synced`/`Healthy`; the `drill-quota ... SyncFailed` line shown by `argocd app get` is the result of the earlier, refused sync operation. **Prediction held.** The `dso202` AppProject's `namespaceResourceWhitelist` does not list `ResourceQuota`, and the check is made by Argo CD at sync time whoever committed the file, so a commit to the chart cannot loosen the namespace limits (least privilege, section 6.4). Staging was unaffected for two independent reasons: it reads the immutable tag `v1.0.0`, which does not contain the file, and it has no automated sync.

## Task 9 — Rebuild from Git

**What was lost:** the contents of both databases (not in Git, not backed up). Each environment started again from
the image's three seed tasks.

### Before the rebuild (step 1)
```text
$ kubectl get secret -n sealed-secrets -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > ../dso202-keys/sealing-key.backup.yaml
$ ls -l ../dso202-keys/
-rw------- 1 pomegranateu pomegranateu   21 Nov 25 02:24 reviewer-password.txt
-rw------- 1 pomegranateu pomegranateu 7087 Nov 25 03:20 sealing-key.backup.yaml
-rw------- 1 pomegranateu pomegranateu  340 Nov 25 02:18 tasktracker-credentials.txt

$ kubectl get secret -n sealed-secrets -l sealedsecrets.bitnami.com/sealed-secrets-key
NAME                      TYPE                DATA   AGE
sealed-secrets-key49h67   kubernetes.io/tls   2      64m

$ git rev-parse HEAD
b1e90a28b24debf7dbfda917a76aa6a68564a42f

$ kubectl get applications -n argocd
NAME                  SYNC STATUS   HEALTH STATUS
platform-dev          Synced        Healthy
platform-staging      Synced        Healthy
root                  Synced        Healthy
sealed-secrets        Synced        Healthy
tasktracker-dev       Synced        Healthy
tasktracker-staging   Synced        Healthy

$ argocd app get tasktracker-staging | grep -E "^(Target|Sync Status)"
Sync Status:        Synced to v1.2.0 (7883dc7)
```

### Delete, recreate, restore the key (steps 2, 3)

The Task Tracker images are `linux/arm64` only, so the new `amd64` nodes cannot pull them from Docker Hub; they and
the other images were loaded from the host (section 13). No Kubernetes object is created by that step. The key was
restored before the controller existed and applied without the `resourceVersion`/`uid` error.
```text
$ date
Wed Nov 25 03:21:01 AM +06 2026
$ kind delete cluster --name dso202-gitops
Deleting cluster "dso202-gitops" ...
Deleted nodes: ["dso202-gitops-worker2" "dso202-gitops-worker" "dso202-gitops-control-plane"]

$ kind create cluster --name dso202-gitops --config cluster/kind-cluster.yaml
Creating cluster "dso202-gitops" ...
Set kubectl context to "kind-dso202-gitops"
You can now use your cluster with:

kubectl cluster-info --context kind-dso202-gitops

Not sure what to do next? 😅  Check out https://kind.sigs.k8s.io/docs/user/quick-start/

# cluster created at 03:21:25

# Section 13: the arm64-only Task Tracker images cannot be pulled by the amd64 nodes, and registry pulls stall on this network,
# so the images are loaded from the host (no Kubernetes object is applied by this step).
$ kind load docker-image pomegranatei/dso202-frontend:1.0 --name dso202-gitops   ok
$ kind load docker-image pomegranatei/dso202-backend:1.0 --name dso202-gitops   ok
$ kind load docker-image pomegranatei/dso202-db:1.0 --name dso202-gitops   ok
$ kind load docker-image busybox:1.37 --name dso202-gitops   ok
$ kind load docker-image docker.io/bitnami/sealed-secrets-controller:0.40.0 --name dso202-gitops   ok
$ kind load docker-image quay.io/argoproj/argocd:v3.5.6 --name dso202-gitops   ok
$ kind load docker-image ghcr.io/dexidp/dex:v2.45.1 --name dso202-gitops   ok
$ kind load docker-image public.ecr.aws/docker/library/redis:8.2.3-alpine --name dso202-gitops   ok

$ kubectl create namespace sealed-secrets
namespace/sealed-secrets created

$ kubectl apply -f ../dso202-keys/sealing-key.backup.yaml
secret/sealed-secrets-key49h67 created

```

### Bootstrap (step 4)
```text
$ kubectl apply -k bootstrap/argocd --server-side --force-conflicts
60 objects serverside-applied

$ kubectl wait --for=condition=Available deployment --all -n argocd --timeout=300s
deployment.apps/argocd-applicationset-controller condition met
deployment.apps/argocd-dex-server condition met
deployment.apps/argocd-notifications-controller condition met
deployment.apps/argocd-redis condition met
deployment.apps/argocd-repo-server condition met
deployment.apps/argocd-server condition met

$ kubectl rollout status statefulset/argocd-application-controller -n argocd --timeout=300s
partitioned roll out complete: 1 new pods have been updated...
# Argo CD ready at 03:23:05
```
```text
03:23:13 $ kubectl apply -f bootstrap/root
appproject.argoproj.io/platform created
application.argoproj.io/root created
```

### Applications in wave order (step 5)

`kubectl get applications -n argocd -w`, started before `kubectl apply -f bootstrap/root`. First time each
Application was `Synced` and `Healthy`:
```text
Application            first seen first Synced+Healthy
platform-dev           03:23:22   03:23:25            
platform-staging       03:23:22   03:23:25            
sealed-secrets         03:23:20   03:23:32            
root                   03:23:16   03:23:51            
tasktracker-dev        03:23:24   03:24:09            
tasktracker-staging    03:23:24   03:25:19            
```

The Applications were **created** in wave order: `root` 03:23:13, `sealed-secrets` (wave −2) 03:23:18,
`platform-dev`/`platform-staging` (wave −1) 03:23:21, `tasktracker-dev`/`tasktracker-staging` (wave 0) 03:23:24.
Each child Application reported `Healthy` for a moment right after it was created, before its first sync had
applied anything (for example `sealed-secrets  OutOfSync  Healthy` at 03:23:21, then `Synced  Progressing`). The
restored health check passes that state to the root, so the root released each next wave about three seconds
after the previous one instead of waiting for it to be really ready. The platform Applications still became
`Healthy` (03:23:25), because `SkipDryRunOnMissingResource` and the retry in Listing 10 cover a SealedSecret
applied before the controller is ready, and Kubernetes keeps retrying Pods whose Secret does not exist yet.
Everything had converged at 03:24:09.

The platform Applications can only be `Healthy` if the SealedSecrets were decrypted, so this also proves the key
restore. There is still only the restored key, `sealed-secrets-key49h67`: the controller found it at start-up and
did not generate another.
```text
$ kubectl get sealedsecret -A
NAMESPACE        NAME                      STATUS   SYNCED   AGE
dso202-dev       tasktracker-credentials            True     55s
dso202-staging   tasktracker-credentials            True     55s

$ kubectl get secret tasktracker-credentials -n dso202-dev -n dso202-dev -o jsonpath={.metadata.ownerReferences[0].kind}
SealedSecret
$ kubectl get secret -n sealed-secrets -l sealedsecrets.bitnami.com/sealed-secrets-key
NAME                      TYPE                DATA   AGE
sealed-secrets-key49h67   kubernetes.io/tls   2      2m1s

03:24:19 $ curl -s -o /dev/null -w '%{http_code}' http://localhost:30080/
200
$ curl -s http://localhost:8090/api/status   (dev API through the port-forward)
{"status":"ok","db":"connected"}

# kind delete/create started at 03:21:01; dev frontend answered 200 at 03:24:19: 3 min 18 s in total
```

**Elapsed time:** `kind delete cluster` started at 03:21:01 (`kind create cluster` finished at 03:21:25); the dev
frontend answered `200` at 03:24:19, **3 min 18 s** in total (2 min 54 s from the new cluster).

### Sign in again and synchronise staging (step 6)
```text
$ argocd admin initial-password -n argocd
(output not recorded: it is the new admin password)
$ argocd login localhost:8080 --username admin --insecure
'admin:login' logged in successfully
Context 'localhost:8080' updated

03:24:28 $ argocd app sync tasktracker-staging
2026-11-25T03:24:31+06:00   apps  StatefulSet  dso202-staging        db-statefulset    Synced  Progressing              statefulset.apps/db-statefulset created
2026-11-25T03:24:56+06:00   apps  StatefulSet  dso202-staging        db-statefulset    Synced  Healthy              statefulset.apps/db-statefulset created
2026-11-25T03:24:58+06:00   apps  StatefulSet  dso202-staging        db-statefulset    Synced  Healthy                  statefulset rolling update complete 1 pods at revision db-statefulset-7cd7bb74f5...
2026-11-25T03:25:13+06:00   apps  Deployment  dso202-staging    backend-deployment    Synced  Healthy              deployment.apps/backend-deployment created
2026-11-25T03:25:19+06:00   apps  Deployment  dso202-staging   frontend-deployment    Synced  Healthy              deployment.apps/frontend-deployment created
2026-11-25T03:25:25+06:00  batch         Job  dso202-staging  tasktracker-smoke-test  Succeeded   Synced    PostSync  Reached expected number of succeeded pods
apps   Deployment   dso202-staging  backend-deployment      Synced     Healthy            deployment.apps/backend-deployment created
apps   Deployment   dso202-staging  frontend-deployment     Synced     Healthy            deployment.apps/frontend-deployment created
apps   StatefulSet  dso202-staging  db-statefulset          Synced     Healthy            statefulset rolling update complete 1 pods at revision db-statefulset-7cd7bb74f5...
batch  Job          dso202-staging  tasktracker-smoke-test  Succeeded  Synced   PostSync  Reached expected number of succeeded pods
Health Status:      Healthy
Message:            successfully synced (no more tasks)
Phase:              Succeeded
Sync Status:        Synced to v1.2.0 (7883dc7)

03:25:27 $ kubectl get applications -n argocd
NAME                  SYNC STATUS   HEALTH STATUS
platform-dev          Synced        Healthy
platform-staging      Synced        Healthy
root                  Synced        Healthy
sealed-secrets        Synced        Healthy
tasktracker-dev       Synced        Healthy
tasktracker-staging   Synced        Healthy
```

### Both environments work (step 7)
```text
# dev
$ curl -s -o /dev/null -w '%{http_code}' http://localhost:30080/
200
$ curl -s http://localhost:30080/config.js | grep BACKEND_URL
  BACKEND_URL: "http://localhost:8090"
$ curl -s -X POST -H 'Content-Type: application/json' -d '{"title":"Rebuilt from Git (dev)"}' http://localhost:8090/api/tasks
{"id":4,"title":"Rebuilt from Git (dev)","description":null,"status":"pending","created_at":"2026-11-24T21:26:18.007Z"}
$ kubectl logs job/tasktracker-smoke-test -n dso202-dev | cut -c1-60
[{"id":1,"title":"Set up kind cluster","description":"Bring 

# staging
$ curl -s -o /dev/null -w '%{http_code}' http://localhost:8081/
000
$ curl -s -X POST -H 'Content-Type: application/json' -d '{"title":"Rebuilt from Git (staging)"}' http://localhost:8091/api/tasks
{"id":4,"title":"Rebuilt from Git (staging)","description":null,"status":"pending","created_at":"2026-11-24T21:26:18.242Z"}
$ kubectl logs job/tasktracker-smoke-test -n dso202-staging | cut -c1-60
[{"id":1,"title":"Set up kind cluster","description":"Bring 

# 03:27, after restarting the staging frontend port-forward:
(the first curl to http://localhost:8081/ returned 000: the staging frontend port-forward had ended with the old cluster and was not restarted; it was restarted and the check repeated)
$ curl -s -o /dev/null -w '%{http_code}' http://localhost:8081/   (port-forward re-established)
200
$ curl -s http://localhost:8081/config.js | grep BACKEND_URL
  BACKEND_URL: "http://localhost:8091"
$ curl -s http://localhost:8091/api/tasks | grep -o '"title":"Rebuilt[^"]*"'
"title":"Rebuilt from Git (staging)"

$ argocd app get tasktracker-staging | grep "Sync Status"
Sync Status:        Synced to v1.2.0 (7883dc7)
```

Staging is at the same tag as before the rebuild, `v1.2.0` (`7883dc7`).

### Fresh key backup (step 8)

The new backup is larger than the first one (14 199 bytes against 7 087) but holds the same single key: restoring it
with `kubectl apply` added a `last-applied-configuration` annotation that repeats the Secret. The file stays
outside the repository with mode `600`.
```text
$ kubectl get secret -n sealed-secrets -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > ../dso202-keys/sealing-key.backup.yaml
$ ls -l ../dso202-keys/sealing-key.backup.yaml
-rw------- 1 pomegranateu pomegranateu 14199 Nov 25 03:26 /home/pomegranateu/dso202-keys/sealing-key.backup.yaml
$ kubectl get secret -n sealed-secrets -l sealedsecrets.bitnami.com/sealed-secrets-key
NAME                      TYPE                DATA   AGE
sealed-secrets-key49h67   kubernetes.io/tls   2      3m59s

$ date
Wed Nov 25 03:26:18 AM +06 2026
```

## Task 10 — Bonus: Chart and Values from Separate Sources

Commit `8e39ebf` replaced `source` with `sources` in `argocd/applications/tasktracker-dev.yaml`: the chart from
`charts/tasktracker`, and a second source with `ref: values` and no path, referenced as
`$values/environments/dev/values.yaml` (relative to the repository root). The rendered manifests did not change, so
the Deployments were not rolled.

```text
$ argocd app get tasktracker-dev
Name:               argocd/tasktracker-dev
Project:            dso202
Server:             https://kubernetes.default.svc
Namespace:          dso202-dev
URL:                https://localhost:8080/applications/tasktracker-dev
Sources:
- Repo:             https://github.com/pomegranateis/dso202-gitops.git
  Target:           main
  Path:             charts/tasktracker
  Helm Values:      $values/environments/dev/values.yaml
- Repo:             https://github.com/pomegranateis/dso202-gitops.git
  Target:           main
  Ref:              values
SyncWindow:         Sync Allowed
Sync Policy:        Automated (Prune)
Sync Status:        Synced to main
Health Status:      Healthy


$ kubectl get application tasktracker-dev -n argocd -o jsonpath={.status.sync.revisions}
["8e39ebf288438725a014eae39f8d7f7fd7a8a0e5","8e39ebf288438725a014eae39f8d7f7fd7a8a0e5"]

$ kubectl get applications -n argocd
NAME                  SYNC STATUS   HEALTH STATUS
platform-dev          Synced        Healthy
platform-staging      Synced        Healthy
root                  Synced        Healthy
sealed-secrets        Synced        Healthy
tasktracker-dev       Synced        Healthy
tasktracker-staging   Synced        Healthy

$ kubectl get deploy -n dso202-dev
NAME                  READY   UP-TO-DATE   AVAILABLE   AGE
backend-deployment    1/1     1            1           5m25s
frontend-deployment   2/2     2            2           5m13s
```
