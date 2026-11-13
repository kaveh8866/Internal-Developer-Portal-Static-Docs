# Internal Developer Portal — Static Docs

![lifecycle](https://img.shields.io/badge/lifecycle-stages%201--7%20of%208-3f51b5)
![container](https://img.shields.io/badge/container-nginx%20unprivileged%20%C2%B7%20uid%20101-2496ED?logo=nginx&logoColor=white)
![site](https://img.shields.io/badge/site-MkDocs%20Material%209.5-526CFE)
![iac](https://img.shields.io/badge/IaC-OpenTofu%20%E2%89%A5%201.6-FFDA18)
![verified](https://img.shields.io/badge/verified-OCI%20eu--frankfurt--1-FF5C39)

A containerized internal developer portal: Markdown sources rendered by MkDocs
Material into static HTML at image build time, served by a hardened unprivileged
Nginx on port 8080. One place for technical documentation, API specifications and
the service catalog — with no database, no CMS and no runtime to patch.

**Status: Stage 7 complete (security audit + documentation).** The portal was
provisioned on OCI, verified from the public internet and then destroyed the same
day, leaving **zero billable resources**. Delivery is Stage 8. Evidence:
[`TEST_REPORT.md`](TEST_REPORT.md) §11 (live run) and
[`TEARDOWN_REPORT.md`](TEARDOWN_REPORT.md) (zero-resource audit).

---

## Why this exists

Internal documentation fails in predictable ways: it lives in a wiki nobody
curates, it drifts from the code, and the service catalog lists owners who left.
A static portal solves the parts that are solvable by construction:

- **Broken links cannot ship.** The build runs `mkdocs build --strict`; a dead
  internal link or a page missing from the nav fails the image build. This was
  tested, not assumed — see `TEST_REPORT.md` §2.
- **There is no runtime to exploit.** No PHP, no Node server, no database. The
  attack surface is a file server that can only read.
- **It fits anywhere.** 2.4–12.6 MiB resident, a 79 MB image, and a 1 OCPU /
  1 GB instance that is free on OCI.

## Features

| | |
| --- | --- |
| Static rendering | MkDocs Material, built with `--strict` in a throwaway stage; no Python in the shipped image |
| Hardened server | Nginx unprivileged (uid 101), read-only rootfs, `cap_drop: ALL`, `no-new-privileges`, 64 MiB / 0.25 CPU |
| Security headers | CSP, `nosniff`, `DENY` framing, referrer and permissions policy — on 200 **and** 404/403 responses |
| Source protection | `*.md`, `*.yml`, dotfiles and editor backups return 403; no directory listing, no version banner |
| Search | Client-side index (`search_index.json`), no search service |
| Portable | Multi-arch image (x86_64 and aarch64 verified), provider-neutral OpenTofu modules |
| Observable | `/healthz` liveness probe, structured access logs with rotation, `docker inspect`-verifiable limits |

---

## Architecture

```text
   [ Internal engineers ]
             │
             │  HTTPS / 80, 443   (security list: 22, 80, 443 — never 8080)
             ▼
   ┌──────────────────────────────────────────────────────────────┐
   │  OCI Compute instance — VM.Standard.A1.Flex, 1 OCPU / 1 GB   │
   │  Ubuntu 24.04 (aarch64), Docker 29.9                        │
   │                                                              │
   │   ┌──────────────────────────────────────────────────────┐   │
   │   │  Hardened Nginx proxy  (nginx-unprivileged, uid 101)  │   │
   │   │  · port 8080 inside, published on host :80            │   │
   │   │  · read-only rootfs, cap_drop ALL, 64 MiB cap         │   │
   │   │  · CSP + nosniff + frame denial on every response     │   │
   │   └───────────────────────┬──────────────────────────────┘   │
   │                           │ try_files, gzip, cache headers    │
   │                           ▼                                   │
   │   ┌──────────────────────────────────────────────────────┐   │
   │   │  Static portal assets  (/usr/share/nginx/html)        │   │
   │   │  MkDocs output: HTML, CSS, logo, search_index.json    │   │
   │   │  55 files · 2.62 MB · rendered at image build         │   │
   │   └──────────────────────────────────────────────────────┘   │
   │                                                              │
   │   build stage (discarded): python:3.12-alpine + mkdocs       │
   └──────────────────────────────────────────────────────────────┘

   Source of truth: portal/docs/*.md  →  mkdocs build --strict  →  image
```

The portal container never talks to a database, an API or another service. It
reads files from its own image and writes nothing: `read_only: true` is not a
restriction it works around, it is a description of what it does.

---

## Verified live deployment (destroyed in Stage 6)

Provisioned and verified on 2026-11-13, then torn down. **This environment no
longer exists** — the numbers are the record of a measured run, not a host you
can reach.

| | |
| --- | --- |
| Host | `152.70.169.194` — A1.Flex, 1 OCPU / 1 GB, Ubuntu 24.04, aarch64, AD-2 |
| Provisioning | `tofu apply`: **6 resources** in 34 s (VCN, IGW, route table, security list, subnet, instance) |
| Deploy | tracked tree transferred by `git archive \| ssh tar`, arm64 image built in 40 s |
| Response | `GET /` → **200 in 48 ms** from the internet; assets 32 ms; gzip 17,488 → 4,663 B |
| Routing | `/services` → 301 · `/.env` → 403 · unknown → 404 · `/healthz` → `ok` |
| Runtime | container **2.4 MiB / 64 MiB**, 0.00 % CPU, 2 pids |
| Exposure | 8080 confirmed **unreachable from outside**; only 22 and 80 listening |
| Teardown | 6 destroyed, provider confirms instance `TERMINATED`, no VCN remains |

---

## Quick start

```bash
cp .env.example .env          # placeholders are fine locally
docker compose --env-file .env -f docker/docker-compose.yml up -d --build
curl -sI http://127.0.0.1:8080/ | head -6
open http://127.0.0.1:8080/   # or browse it
```

Stop it:

```bash
docker compose --env-file .env -f docker/docker-compose.yml down
```

Content changes are rebuild-time, not request-time:

```bash
docker compose --env-file .env -f docker/docker-compose.yml up -d --build portal
```

### Deploying to OCI

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars     # gitignored; fill in the tenancy
tofu init && tofu fmt -recursive -check && tofu validate
tofu plan                                        # expect: Plan: 6 to add
tofu apply                                       # ~34 s

ssh ubuntu@$(tofu output -raw instance_public_ip)
# on the host:
git clone https://github.com/kaveh8866/Internal-Developer-Portal-Static-Docs.git
cd Internal-Developer-Portal-Static-Docs && cp .env.example .env
#   PORTAL_BIND_ADDRESS=0.0.0.0   PORTAL_PORT=80   PORTAL_ENV=production
docker compose --env-file .env -f docker/docker-compose.yml up -d --build
```

Teardown: `cd terraform && tofu destroy -auto-approve`.

---

## Structuring documentation pages

```text
portal/
├── mkdocs.yml            # nav, theme, extensions
├── requirements.txt      # pinned: mkdocs 1.6.1, material 9.5.44, pymdown 10.12
└── docs/
    ├── index.md          # landing page
    ├── contributing.md   # how to write for this portal
    ├── services/index.md # service catalog (owner, tier, SLO, on-call)
    ├── api/index.md      # API specifications and conventions
    ├── runbooks/index.md # recovery procedures with anchors
    └── assets/           # portal.css, logo.svg, images
```

Rules the build enforces for you:

1. **Every page is listed in `nav:`** in `portal/mkdocs.yml`. An unlisted page
   is reachable but effectively unpublished.
2. **Internal links are relative** (`../api/index.md`), never absolute URLs. A
   link to a missing file fails the build.
3. **Cross-page anchors must exist** (`#rotate-signing-keys` needs a matching
   heading).

Adding a page: create `portal/docs/<area>/<page>.md`, add it to `nav:`, link it
from a page someone actually reads, rebuild. Metadata, admonitions, tabs, tables
and Mermaid-free diagrams are available through the extensions already enabled.

## Configuring Nginx

| File | Purpose | Changes require |
| --- | --- | --- |
| `docker/nginx/default.conf` | server block: listen 8080, `try_files`, gzip, cache, deny rules | image rebuild |
| `configs/nginx/security-headers.conf` | CSP, `nosniff`, framing, referrer, permissions (mounted read-only) | container restart |
| `docker/docker-compose.yml` | port publishing, limits, tmpfs, healthcheck, log rotation | `up -d` |

Two rules that matter more than they look:

- **Add headers only at server level.** An `add_header` inside a `location`
  replaces every inherited header, silently stripping the CSP from that path.
- **Keep 8080 unpublished.** Compose maps container 8080 to host 80; the
  security list never opens 8080, so there is exactly one way in.

To put TLS in front, terminate at the platform proxy and forward to
`127.0.0.1:8080`; enable HSTS **there**, not in the container that serves plain
HTTP.

## Health endpoints and how to test them

| Endpoint | Expected | Purpose |
| --- | --- | --- |
| `/healthz` | `200`, body `ok`, no security headers | liveness probe used by compose and any monitor |
| `/` | `200`, CSP + `nosniff` | the portal itself |
| `/services` | `301` → `/services/` | directory-URL normalisation (expect, don't "fix") |
| `/.env`, `/mkdocs.yml`, `/*.md` | `403` | sources and metadata are denied |
| unknown path | `404` | rendered `404.html`, no listing |
| `8080` from outside | unreachable | proves the port contract |

```bash
B=http://127.0.0.1:8080
curl -s $B/healthz
curl -sI $B/ | grep -iE 'content-security-policy|x-content-type-options'
for p in / /services/ /services /.env /nope-xyz; do
  printf '%-12s %s\n' "$p" "$(curl -s -o /dev/null -w '%{http_code}' "$B$p")"
done
docker inspect cg-portal --format '{{.HostConfig.ReadonlyRootfs}} {{.HostConfig.CapDrop}} {{.Config.User}}'
```

---

## Security posture (Stage 7 audit)

Full sign-off: [`SECURITY_AUDIT.md`](SECURITY_AUDIT.md).

| Control | Verified behaviour |
| --- | --- |
| Zero-leak boundary | 37 tracked files, 0 credentials; `.env` and `terraform.tfvars` exist locally and are gitignored |
| Runtime identity | uid 101, read-only rootfs, `cap_drop: ALL`, `no-new-privileges`, 64 pids |
| HTTP methods | `GET`/`HEAD` only — `POST`, `PUT`, `DELETE`, `OPTIONS`, `TRACE`, `PATCH` all **405** |
| Source disclosure | `.md`, `.yml`, dotfiles → **403**; path traversal attempts → 403/404 |
| Directory listing | disabled (`/assets/` → 403) |
| Banner | `Server: nginx` with no version |
| Headers on errors | CSP and `nosniff` present on 404 and 403, not only on 200 |
| Logging | json-file, 10 MiB × 2; only error-level entries are the probe attempts |

**Known gap:** no TLS terminator. The container speaks HTTP; 443 is reserved for
the proxy. HSTS is deliberately absent so a browser is never pinned to a scheme
this container cannot serve.

## Cross-cloud portability note

The OpenTofu configuration and the container are **cloud-agnostic by design**.
The modules name the equivalent resource on every provider (see
`terraform/README.md`), the image is multi-arch, and the only cloud-specific code
is the provider block plus two module bodies.

**Final production verification and testing certification were performed strictly
on Oracle Cloud Infrastructure (OCI), using OCI trial credits / the Always Free
envelope.** AWS and GCP are supported *ports*, not certified targets: this
repository carries no test evidence for them. Do not describe the project as
"AWS-verified" or "GCP-verified".

### Migrating to AWS

1. Replace `modules/network` with `aws_vpc`, `aws_internet_gateway`,
   `aws_route_table`, `aws_security_group`, `aws_subnet`.
2. Replace `modules/compute` with `aws_instance` (`t4g.small`/`t4g.micro`, ARM,
   free-tier eligible) and `associate_public_ip_address = true`.
3. Map `metadata.user_data` → `user_data` (same cloud-init payload works).
4. Keep the ingress contract: 22 from the operator CIDR, 80/443 from the web
   CIDR, never 8080. Verify with `aws ec2 describe-security-groups`.

### Migrating to GCP

1. Replace `modules/network` with `google_compute_network`,
   `google_compute_subnetwork` and `google_compute_firewall`; the internet
   gateway and default route are implicit.
2. Replace `modules/compute` with `google_compute_instance` (`e2-micro`,
   free-tier eligible in `us-central1`/`us-west1`/`us-east1`), and add
   `network_interface { access_config {} }` for a public IP.
3. Map `metadata.user_data` → `metadata_startup_script` (drop the base64).
4. Keep the same three firewall rules; verify with `gcloud compute
   firewall-rules list`.

Because the portal is stateless, there is nothing to migrate: no bucket, no
database, no volume. A port is an IaC exercise, not a data migration.

---

## 💰 Cross-Cloud Cost & Benchmark Estimation

Based on the **measured footprint**: 1 vCPU, 1 GB RAM, 50 GB disk, one container
at 64 MiB cap (2.4 MiB idle on ARM), ~2.6 MB of site assets, and roughly
2 GB/month egress for a 20-person team (≈ 5,000 page views × ~350 KB).

List prices, monthly, 730 h, EU regions, late 2026. **Estimates for planning, not
billing-verified figures** — free-tier rules change, so confirm in each
provider's calculator before committing.

| | OCI (Always Free / trial) | AWS — `t4g.micro` (eu-central-1) | GCP — `e2-micro` (europe-west3) |
| --- | --- | --- | --- |
| Compute | **$0** — A1.Flex 1 OCPU / 1 GB inside the free allowance | $6.13 on-demand; **$0** for 750 h/mo in the first 12 months | $6.11 on-demand; **$0** in `us-central1` free tier |
| Disk (50 GB) | **$0** — 200 GB free across block volumes | 30 GB free, remaining 20 GB ≈ $1.60 (gp3 $0.08/GB) | 30 GB free tier; 50 GB pd-standard ≈ $2.00 |
| Egress (~2 GB/mo) | **$0** — 10 TB/mo free | **$0** — first 100 GB/mo free, then $0.09/GB | **$0** — first 200 GB/mo free, then ~$0.12/GB |
| Static IPv4 | **$0** while attached | $0 while attached to a running instance | $0 while attached |
| **Effective monthly** | **$0** | **≈ $7.73** after free tier | **≈ $8.11** outside a free-tier region |
| **First-year monthly** | **$0** | **≈ $1.60** (disk above 30 GB) | **$0** in a free-tier region |

### Measured benchmarks (this project)

| Metric | Value | Where measured |
| --- | --- | --- |
| First-byte latency, `GET /` | **48 ms** (internet → Frankfurt) | Stage 5, live OCI |
| Static asset latency | 32 ms | Stage 5 |
| Transfer per page | 17,488 B → 4,663 B gzipped | Stage 4 + 5 |
| Container RSS | **2.4 MiB** (ARM idle) / 12.6 MiB (x86, under load) | Stage 5 / Stage 4 |
| Sustained load at 0.1 CPU | **200/200 → 200**, 12.7 MiB | Stage 4 |
| Image size | 79 MB (arm64) / 77 MB (x86_64) | Stage 5 / Stage 4 |
| Cold provision + deploy | 34 s `apply` + 40 s build | Stage 5 |

**Reading the table:** the portal is free on OCI and nearly free everywhere else
because it is a file server. If your bill for a site like this is material, the
cause is egress, not compute — which is why the free-tier egress allowances are
the column that actually decides the platform.

---

## Repository layout

```
.
├── Dockerfile                      # multi-stage: mkdocs --strict -> nginx
├── docker/
│   ├── docker-compose.yml          # hardened service, multi-arch
│   └── nginx/default.conf          # server block on 8080
├── configs/nginx/                  # security headers (mounted, no rebuild)
├── portal/                         # mkdocs.yml, requirements, docs/, assets
├── terraform/                      # VCN + A1 instance; modules/network, modules/compute
├── docs/                           # verification transcripts
└── .env.example                    # 21 placeholder keys, no values
```

## Roadmap

| Stage | Scope | State |
| --- | --- | --- |
| **1** | Scaffold, Docker, Nginx, strict Git boundary | ✅ complete |
| **2** | OpenTofu: VCN, A1.Flex compute, security list | ✅ applied and verified |
| **3** | `AGENT_GUIDE.md` + `MANUAL_PREREQS.md` | ✅ complete |
| **4** | Local drills: routing, headers, low-spec, failure surfacing | ✅ verified |
| **5** | Live OCI deployment and verification | ✅ verified 2026-11-13 |
| **6** | Teardown to zero burn rate | ✅ verified — 0 resources remain |
| **7** | Security audit, cost table, final README | ✅ this document |
| **8** | MIT license, publish to GitHub, vault certification | ⬜ remaining |

## Documentation

| Document | Audience |
| --- | --- |
| [`MANUAL_PREREQS.md`](MANUAL_PREREQS.md) | Operator: accounts, credentials, parameters, pre-flight and verification checklists |
| [`AGENT_GUIDE.md`](AGENT_GUIDE.md) | Coding agents: phases 0–10, verified commands, hard limits, troubleshooting |
| [`TEST_REPORT.md`](TEST_REPORT.md) | Measured results: local drills and the live OCI run (§11) |
| [`TEARDOWN_REPORT.md`](TEARDOWN_REPORT.md) | Stage 6 audit: destroy transcript and provider-side zero proof |
| [`SECURITY_AUDIT.md`](SECURITY_AUDIT.md) | Stage 7 zero-leak scan and security sign-off |
| [`terraform/README.md`](terraform/README.md) | IaC layout, ingress contract, AWS/GCP mapping |
| [`portal/docs/contributing.md`](portal/docs/contributing.md) | Engineers writing content for the portal |

## License

MIT — added at Stage 8. Copyright (c) 2026 Mostafa Kaveh.
