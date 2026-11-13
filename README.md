# Internal Developer Portal — Static Docs

A containerized internal developer portal: Markdown sources rendered by MkDocs
Material into static HTML, served by a hardened unprivileged Nginx. Built for
engineering teams that need one trustworthy place for technical docs, API specs
and the service catalog — without running a wiki, a database, or a CMS.

**Status: Stage 6 complete — deployed, verified, destroyed.** The portal was
provisioned on an Ampere A1 instance in `eu-frankfurt-1`, verified from the public
internet (200 in 48 ms, CSP intact, 8080 unreachable), and then torn down the same
day: **6 resources destroyed, zero remaining**, burn rate $0. Nothing is running
now — the evidence lives in [`TEST_REPORT.md`](TEST_REPORT.md) §11 and
[`TEARDOWN_REPORT.md`](TEARDOWN_REPORT.md).

| | |
| --- | --- |
| Site generator | MkDocs 1.6 + Material 9.5, rendered with `--strict` at image build |
| Web server | `nginxinc/nginx-unprivileged:1.27-alpine`, uid 101, port 8080 |
| Container | read-only rootfs, `cap_drop: ALL`, `no-new-privileges`, 64 MiB / 0.25 CPU |
| Hosting target | OCI Always Free `VM.Standard.A1.Flex` (1 OCPU / 1 GB), arm64 or x86 |
| Provisioning | OpenTofu modules: VCN + A1.Flex instance + security list (22/80/443) |

### Verified live deployment (destroyed in Stage 6)

Provisioned and verified on 2026-11-13 (Stage 5). **The environment described
here no longer exists** — this is the record of a run that was measured, not a
host you can reach. Re-deploy with `tofu apply` (about 40 s) plus the compose
command below.

| | |
| --- | --- |
| Host | `152.70.169.194` — `VM.Standard.A1.Flex`, 1 OCPU / 1 GB, Ubuntu 24.04, **aarch64**, AD-2 |
| Provisioning | `tofu apply`: **6 resources** (VCN, IGW, route table, security list, subnet, instance) — instance created in 34 s |
| Ingress (security list) | 22 from the operator CIDR, 80 and 443 from `web_allowed_cidr`; **8080 closed and confirmed unreachable from outside** |
| Runtime | Docker 29.9.3, arm64 image (79 MB), container **2.4 MiB / 64 MiB**, 2 pids |
| Response (from the internet) | `GET /` → **200 in 48 ms**, assets 32 ms, gzip 17,488 → 4,663 B |
| Routing on the real host | `/services` → **301** `/services/`, `/.env` → **403**, unknown path → **404**, `/healthz` → `ok` |

```bash
# redeploy from scratch
cd terraform && tofu apply
# then, on the host: git clone … ; cp .env.example .env
#   PORTAL_BIND_ADDRESS=0.0.0.0  PORTAL_PORT=80  PORTAL_ENV=production
#   docker compose --env-file .env -f docker/docker-compose.yml up -d --build

# stop the spend (Stage 6)
cd terraform && tofu destroy -auto-approve
```

!!! warning "Internal portal, currently publicly reachable"
    `web_allowed_cidr` was left at `0.0.0.0/0` so the deployment could be
    verified end-to-end. That makes an *internal* portal answer on the public
    internet over plain HTTP. Narrow it to the office/VPN range, or put the
    proxy in front and close 80, before anyone treats this as production.

---

## Quick start

```bash
cp .env.example .env          # placeholders are fine for a local run
docker compose --env-file .env -f docker/docker-compose.yml up -d --build
curl -sI http://127.0.0.1:8080/ | head -5
```

Open <http://127.0.0.1:8080>. The port is bound to loopback by default
(`PORTAL_BIND_ADDRESS=127.0.0.1`), so nothing is exposed to your network.

Stop it with:

```bash
docker compose --env-file .env -f docker/docker-compose.yml down
```

Editing content? Rebuild the image — the site is rendered at build time, not per
request:

```bash
docker compose --env-file .env -f docker/docker-compose.yml up -d --build portal
```

---

## Repository layout

```
.
├── Dockerfile                      # multi-stage: mkdocs build -> nginx runtime
├── docker/
│   ├── docker-compose.yml          # the only service; hardened, ARM/x86 clean
│   └── nginx/default.conf          # server block: 8080, static only, no listing
├── configs/
│   └── nginx/security-headers.conf # CSP + friends, mounted read-only
├── portal/
│   ├── mkdocs.yml                  # nav, theme, extensions
│   ├── requirements.txt            # pinned build dependencies
│   └── docs/                       # Markdown sources + assets (this is content)
├── terraform/                      # Stage 2: OCI provisioning (reserved)
└── .env.example                    # every knob, placeholders only
```

Why the `Dockerfile` sits at the root rather than in `docker/`: the build needs
the repository root as its context (it copies both `portal/` and
`docker/nginx/`), and both sibling projects in this portfolio use the same
layout. Compose lives in `docker/` next to the server block it references.

---

## What is deliberately minimal

- **No search service, no database, no CMS.** MkDocs writes a static search
  index; Nginx serves files. There is nothing to patch at runtime and nothing
  that can 500 under load.
- **No external font or asset CDN.** `font: false` in `portal/mkdocs.yml`; the
  portal must render on an isolated internal network.
- **No published port to the internet.** Compose binds loopback; Stage 2 keeps
  8080 closed in the security list and puts the platform proxy in front.

## Security posture (Stage 1)

| Control | Implementation |
| --- | --- |
| Non-root runtime | `USER 101` in the image, `user: "101:101"` in compose |
| Immutable filesystem | `read_only: true` + sized `tmpfs` for `/tmp` and nginx cache |
| Capability reduction | `cap_drop: [ALL]` (Nginx unprivileged needs none to bind 8080) |
| Privilege escalation | `no-new-privileges:true`, no setuid binaries in the image |
| Resource bound | 64 MiB memory, 0.25 CPU, 64 pids |
| Headers | CSP, `nosniff`, `DENY` framing, referrer and permissions policy |
| Dotfile/metadata leak | `location ~ /\.` denied, `*.md`/`*.yml` denied |
| Log retention | json-file, 10 MiB × 2 per container |

---

## Roadmap

| Stage | Scope | State |
| --- | --- | --- |
| **1** | Scaffold, Docker, Nginx, strict Git boundary, vault metadata | ✅ complete |
| **2** | OpenTofu: VCN, A1.Flex compute, security list (8080 closed) | ✅ written, `validate` + `plan` clean, not applied |
| **3** | `AGENT_GUIDE.md` phases + operator prerequisites | ✅ complete |
| **4** | Local drills: build, headers, 404/toxic paths, low-spec behaviour | ✅ verified — 200/200 under 0.1 CPU, strict build proven to fail on a dead link |
| **5** | Live OCI deployment and verification | ✅ verified 2026-11-13 at `152.70.169.194` (48 ms first byte) |
| **6** | Teardown to zero burn rate | ✅ verified — 6 destroyed, provider confirms 0 remaining |
| **7** | Security audit, cost table, final README | ⬜ |
| **8** | MIT license, release, vault certification | ⬜ |

## Documentation

| Document | Audience |
| --- | --- |
| [`TEST_REPORT.md`](TEST_REPORT.md) | Measured results: local drills, live OCI run (§11), and the gaps | 
| [`TEARDOWN_REPORT.md`](TEARDOWN_REPORT.md) | Stage 6 audit: state at teardown, destroy transcript, provider-side zero proof |
| [`MANUAL_PREREQS.md`](MANUAL_PREREQS.md) | Human operator: accounts, credentials, parameters, pre-flight and verification checklists |
| [`AGENT_GUIDE.md`](AGENT_GUIDE.md) | Coding agents: phases 0–10, verified commands, hard limits, troubleshooting |
| [`terraform/README.md`](terraform/README.md) | IaC layout, ingress contract, AWS/GCP mapping, capacity constraints |
| [`portal/docs/contributing.md`](portal/docs/contributing.md) | Engineers writing content for the portal |

## License

MIT — added at Stage 8. Copyright (c) 2026 Mostafa Kaveh.
