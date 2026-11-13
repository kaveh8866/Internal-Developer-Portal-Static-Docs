# Internal Developer Portal — Static Docs

A containerized internal developer portal: Markdown sources rendered by MkDocs
Material into static HTML, served by a hardened unprivileged Nginx. Built for
engineering teams that need one trustworthy place for technical docs, API specs
and the service catalog — without running a wiki, a database, or a CMS.

**Status: Stage 2 written.** The portal builds and serves locally (Stage 1),
and the OCI infrastructure is written and `tofu plan`-verified (`6 to add`) but
**not applied** — nothing exists in the cloud yet. See the roadmap below for
what is verified and what is not.

| | |
| --- | --- |
| Site generator | MkDocs 1.6 + Material 9.5, rendered with `--strict` at image build |
| Web server | `nginxinc/nginx-unprivileged:1.27-alpine`, uid 101, port 8080 |
| Container | read-only rootfs, `cap_drop: ALL`, `no-new-privileges`, 64 MiB / 0.25 CPU |
| Hosting target | OCI Always Free `VM.Standard.A1.Flex` (1 OCPU / 1 GB), arm64 or x86 |
| Provisioning | OpenTofu modules: VCN + A1.Flex instance + security list (22/80/443) |

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
| **3** | `AGENT_GUIDE.md` phases + operator prerequisites | 🟡 `AGENT_GUIDE.md` drafted |
| **4** | Local drills: build, headers, 404/toxic paths, low-spec behaviour | ⬜ |
| **5** | Live OCI deployment and verification | ⬜ |
| **6** | Teardown to zero burn rate | ⬜ |
| **7** | Security audit, cost table, final README | ⬜ |
| **8** | MIT license, release, vault certification | ⬜ |

## Documentation

| Document | Audience |
| --- | --- |
| [`AGENT_GUIDE.md`](AGENT_GUIDE.md) | Coding agents: phases, stop conditions, hard limits |
| [`terraform/README.md`](terraform/README.md) | The reserved IaC layer and its planned inputs |
| [`portal/docs/contributing.md`](portal/docs/contributing.md) | Engineers writing content for the portal |

## License

MIT — added at Stage 8. Copyright (c) 2026 Mostafa Kaveh.
