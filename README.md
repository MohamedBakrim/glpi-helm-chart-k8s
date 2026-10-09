# glpi-helm-chart-k8s

A Helm 3 chart (chart name: **`myhelm`**) that deploys [GLPI 11](https://glpi-project.github.io/GLPI/) — the open-source ITSM / asset-management helpdesk — on Kubernetes, with the full production shape a stateful PHP app needs: **php-fpm** running GLPI, an **nginx** frontend, **MariaDB** for the database, **Valkey** for cache/sessions, scheduled-task and backup CronJobs, Ingress (or Gateway API) exposure, and a chain of post-install hook Jobs that automate GLPI's otherwise-manual installer. Application code ships *inside* the php-fpm image (nothing is downloaded at install time); only real state (`/etc/glpi`, `/var/lib/glpi`, `marketplace`, `/backup`) is persisted on PVCs.

## Features

- Two-Deployment design: nginx serves static assets directly and forwards PHP to php-fpm over FastCGI.
- Automated install/upgrade: four ordered post-install/post-upgrade hook Jobs (dir ownership → DB schema install/upgrade → `config_db.php` + crypto keys → Valkey cache wiring).
- MariaDB and Valkey as conditional, vendored subcharts (offline-friendly install from `charts/*.tgz` / `dist/`).
- Ingress (cert-manager TLS) by default; optional Gateway API HTTPRoute.
- Nightly backups (`mariadb-dump` + tar of files/marketplace) with retention pruning, plus a guarded GLPI cron every 2 minutes.
- Hardened by default: read-only root filesystems, non-root (uid 82), dropped capabilities, `automountServiceAccountToken: false`, digest-pinned images, PodDisruptionBudget, NetworkPolicy limiting DB access.
- Optional HPA, ExternalSecrets integration, and PVC `storageClass`/`accessModes` escape hatches.

## Prerequisites

- Kubernetes 1.24+ (defaults assume a k3s/Rancher-style cluster with a `local-path` default StorageClass)
- Helm 3
- [ingress-nginx](https://kubernetes.github.io/ingress-nginx/) controller
- [cert-manager](https://cert-manager.io/) with a `ClusterIssuer` named `selfsigned` (or change `ingress.annotations`)
- DNS/hosts entry for `myhelm.local` (default Ingress host)
- Optional: Gateway API controller (only if you enable `httpRoute`), External Secrets operator (only if you enable `externalSecrets`)

## Install

The credentials Secret must exist **before** installing — see [Secret contract](#secret-contract-my-test-app-auth) below.

```bash
kubectl create namespace glpi

kubectl -n glpi create secret generic my-test-app-auth \
  --from-literal=mariadb-user-password='<password>' \
  --from-literal=mariadb-root-password='<root-password>' \
  --from-literal=mariadb-replication-password='<repl-password>' \
  --from-literal=valkey-password='<valkey-password>'

# from the repo root (dependencies are vendored; otherwise: helm dependency build)
helm install glpi . -n glpi --create-namespace

# or from the packaged artifact:
helm install glpi dist/myhelm-0.2.10.tgz -n glpi --create-namespace
```

Install **without `--wait`**: the backup PVC stays `Pending` until the first backup job runs (`WaitForFirstConsumer`) — that is normal.

## Upgrade / test / uninstall

```bash
helm upgrade glpi . -n glpi -f your-values.yaml   # hook Jobs re-run; DB scripts are idempotent
helm test glpi -n glpi                            # runs the nginx connectivity test pod
helm uninstall glpi -n glpi
```

PVCs carry `helm.sh/resource-policy: keep` and survive uninstall. To wipe data:

```bash
kubectl delete pvc --all -n glpi
```

> **Note:** `storageClass` and `accessModes` are immutable on a bound PVC. Migration is: back up → `kubectl delete pvc <name>` → `helm upgrade` → restore.

## Configuration highlights

Full, heavily commented reference lives in [`values.yaml`](values.yaml). The most important keys:

| Key | Default | Effect |
|---|---|---|
| `replicaCount` | `1` | php-fpm/nginx replicas; >1 needs RWX storage first |
| `image.tag` | `11.0.11@sha256:…` | php-fpm app image (digest-pinned, contains GLPI code) |
| `nginx.image.tag` | `11.0.11@sha256:…` | nginx frontend image (aligned with `appVersion`) |
| `nginx.service.type` / `.port` | `ClusterIP` / `80` | the public HTTP Service (Ingress/test/HTTPRoute target) |
| `service.port` | `9000` | php-fpm FastCGI Service — internal only, never expose it |
| `ingress.enabled` / `.hosts` / `.tls` | `true` / `myhelm.local` / secret `myhelm-tls` | HTTPS front door (cert-manager `selfsigned` issuer) |
| `httpRoute.enabled` | `false` | Gateway API alternative to Ingress |
| `nodeSelector` / `mariadb.nodeSelector` / `valkey.nodeSelector` | `{}` | **empty by default** — pin to *your* node if using local-path/RWO storage |
| `jobs.dbInit.enabled` | `true` | master switch for all four install/upgrade hook Jobs |
| `mariadb.auth.existingSecret` / `.database` / `.username` | `my-test-app-auth` / `mydb` / `myuser` | DB credentials come from the pre-created Secret |
| `valkey.auth.existingSecret` | `my-test-app-auth` (key `valkey-password`) | cache password from the same Secret |
| `*Persistence` (`etc`/`files`/`marketplace`) | `true` / 50Mi / 10Gi / 2Gi | GLPI config, uploads/sessions, plugins |
| `backup.enabled` / `.schedule` / `.retentionDays` | `true` / `0 2 * * *` / `7` | nightly dump+tar with pruning |
| `cronjob.enabled` / `.schedule` | `true` / `*/2 * * * *` | GLPI's own task scheduler (schema-integrity guarded) |
| `pdb.enabled` / `networkPolicy.enabled` | `true` / `true` | disruption budget; DB-only ingress policy |
| `autoscaling.enabled` | `false` | HPA for php-fpm (needs RWX + replicas > 1 to be useful) |
| `externalSecrets.enabled` | `false` | sync credentials from a ClusterSecretStore instead of hand-making the Secret |

**Ports:** nginx `80` (HTTP) · php-fpm `9000` (FastCGI, internal) · MariaDB `3306` · Valkey `6379`.

## Architecture summary

- **`<fullname>-phpfpm` Deployment** — GLPI code at `/var/www/html`, FastCGI on 9000, wired to `<release>-mariadb:3306` and `<release>-valkey-client:6379`; `tcpSocket` probes (an `httpGet` against FastCGI would crash-loop the pod). Mounts the `etc`, `files` and `marketplace` PVCs plus an `emptyDir` at `/tmp`.
- **`<fullname>-nginx` Deployment** — serves static files, proxies `index.php` to php-fpm:9000; Service port 80 is the only HTTP entry point (Ingress and the helm test target it).
- **Hook chain** (post-install/post-upgrade, ordered): `verify-dir` (w5, chowns fresh volumes as root) → `glpi-install` (w10, DB schema install/upgrade) → `glpi-configure` (w20, writes `config_db.php`) → `glpi-cache` (w30, points GLPI cache at Valkey).
- **CronJobs:** `<fullname>-cron` (GLPI task runner, guarded by a schema-integrity wait) and `<fullname>-backup` (daily dump + tar, retention-pruned).
- **Storage:** four kept PVCs (`-etc` 50Mi, `-files` 10Gi, `-marketplace` 2Gi, `-backup` 2Gi) + 8Gi each for MariaDB and Valkey. App code is never persisted — it comes from the image.
- **Exposure:** Ingress (default) or HTTPRoute (optional) → nginx Service :80 → nginx → php-fpm :9000.

## Secret contract: `my-test-app-auth`

> ⚠️ **Do not rename this Secret (or the chart) without updating every consumer.**

The chart **requires** a Secret named `my-test-app-auth` (default of `mariadb.auth.existingSecret` / `valkey.auth.existingSecret`) to exist in the release namespace *before* install, with exactly these four keys:

| Key | Used by |
|---|---|
| `mariadb-user-password` | MariaDB app user + php-fpm/hook Jobs (`MARIADB_PASSWORD`) |
| `mariadb-root-password` | MariaDB subchart admin |
| `mariadb-replication-password` | MariaDB subchart replication user |
| `valkey-password` | Valkey subchart + GLPI cache config |

Secrets are never stored in `values.yaml`. If you use the External Secrets operator, set `externalSecrets.enabled: true` to sync these keys from a secret store instead.

Similarly, the **chart name `myhelm` is part of the deployed contract** — resource names render as `glpi-myhelm-*` for a release named `glpi`. Renaming the chart would orphan existing resources on upgrade; use `fullnameOverride` if you need different names.

## License

MIT — see [LICENSE](LICENSE).
