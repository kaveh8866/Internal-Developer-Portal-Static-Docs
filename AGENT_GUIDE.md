# AGENT_GUIDE — Internal Developer Portal

Execution playbook for AI coding agents (Cursor, Claude Code, Windsurf, Codebuff)
building, running and verifying this portal. Every command below has been run in
this repository; the outputs quoted are real, not illustrative.

## Scope and certification

- **Final production verification and testing certification are performed
  strictly on Oracle Cloud Infrastructure (OCI)**, using OCI trial credits and the
  Always Free envelope. OCI is the only certified target.
- **The configuration is cloud-agnostic.** The OpenTofu layer maps 1:1 onto AWS
  EC2/VPC and GCP GCE/VPC (tables in `terraform/modules/*/main.tf`), and the
  container is multi-arch. Those ports are **documented, not certified** — they
  carry no test evidence in this repository. Never describe this project as
  "AWS-verified" or "GCP-verified".
- **Current state:** Stage 1 (scaffold, local build + serve) and Stage 2 (IaC
  written, `tofu plan` → `6 to add`) are complete. **Nothing has been applied in
  the cloud**: no VCN, no instance, no public URL. Stage 5 is the first `apply`,
  and until it runs, no line in this repository may call the portal
  live-verified.

| Stage | Playbook phase | State |
| --- | --- | --- |
| 1 — scaffold, Docker, Nginx, Git boundary | 0–1 | ✅ complete |
| 2 — OpenTofu modules | 7 | ✅ written, plan 6 to add |
| 3 — this guide + `MANUAL_PREREQS.md` | — | ✅ complete |
| 4 — local drills (routing, headers, assets) | 0–6 | 🟡 commands verified, not yet a signed report |
| 5 — live OCI deploy + verification | 8 | ⬜ not started |
| 6 — teardown, zero resources | 9 | ⬜ |
| 7 — security audit, cost table, final README | — | ⬜ |
| 8 — release + vault certification | 10 | ⬜ |

---

## Hard limits

- **Never open 8080.** The container listens on 8080; compose publishes it on
  host port 80 (`PORTAL_PORT=80`). The security list allows 22/80/443 only. If
  you "temporarily" open 8080, an internal portal becomes a public one.
- **Never add `add_header` inside a `location`.** Nginx replaces every inherited
  header when a location declares its own, silently stripping the CSP from that
  path. Headers live in `configs/nginx/security-headers.conf` at server level.
- **Never serve source files.** `*.md`, `*.yml`, dotfiles and editor backups are
  denied on purpose. A 403 there is correct behaviour, not a bug to fix.
- **Never disable `--strict`.** The strict build is the only dead-link detector
  the project has; a shipped broken link is worse than a failed build.
- **Never add a runtime dependency.** This is static HTML behind Nginx: no PHP,
  no Node server, no database. Dynamic behaviour belongs to another project.
- **Never commit** `.env`, `terraform.tfvars`, `*.tfstate`, `*.pem`, `site/`, or
  a real internal hostname.

---

## Phase 0 — Preflight

```bash
docker version --format '{{.Server.Version}}'   # engine must answer
docker compose version
git status --porcelain                          # must be empty before you start
```

Stop if the Docker daemon is unreachable — every phase below needs it.

## Phase 1 — Build the documentation site

The site is rendered **at image build time**, not per request. Two stages:

```bash
docker build -t cloudguard/idp-portal:local .
```

What happens:

1. `python:3.12-alpine` installs the pins from `portal/requirements.txt`.
2. `mkdocs build --strict --clean --site-dir /site` renders `portal/docs/`.
3. The artifacts are copied into `nginxinc/nginx-unprivileged:1.27-alpine`.

Measured image size: **77 MB** (Nginx base is most of it; the site itself is
small). A broken internal link, a nav entry pointing at a missing page, or an
invalid `mkdocs.yml` key fails this step — that is the point.

### Content-only iteration

Rebuild just the image; the container keeps its name and port:

```bash
docker compose --env-file .env -f docker/docker-compose.yml up -d --build portal
```

## Phase 2 — Start the stack

```bash
cp .env.example .env          # placeholders are fine for a local run
docker compose --env-file .env -f docker/docker-compose.yml up -d --build
docker compose --env-file .env -f docker/docker-compose.yml ps
```

Success looks like `cg-portal | Up (healthy) | 127.0.0.1:8080->8080/tcp` (or
`:80` when `PORTAL_PORT=80` is set).

**Port choice.** `PORTAL_PORT` is the *host* port; the container always listens
on 8080. Locally the default is 8080. On the OCI host set:

```bash
PORTAL_BIND_ADDRESS=0.0.0.0
PORTAL_PORT=80
```

so the security list rule for 80/tcp matches the published port. A host port
already in use fails with `bind: Only one usage of each socket address`; change
`PORTAL_PORT` rather than stopping whatever owns it.

## Phase 3 — Verify health and headers

```bash
B=http://127.0.0.1:8080        # or :80 on the server

curl -fsS "$B/healthz"                                 # expect: ok
curl -s -o /dev/null -w '%{http_code}\n' "$B/"         # expect: 200
curl -sI "$B/" | grep -iE 'content-security-policy|x-content-type|x-frame|referrer-policy'
```

Measured on this repository:

| Check | Result |
| --- | --- |
| `GET /healthz` | `200`, body `ok` (no security headers by design) |
| `GET /` | `200`, `text/html; charset=utf-8`, 17,488 bytes |
| `Content-Security-Policy` | `default-src 'self'; … frame-ancestors 'none'; …` |
| `X-Content-Type-Options` | `nosniff` |
| `X-Frame-Options` | `DENY` |
| `Referrer-Policy` | `strict-origin-when-cross-origin` |
| `Permissions-Policy` | `geolocation=(), microphone=(), camera=(), payment=()` |
| gzip | `Content-Encoding: gzip`, 17,488 → **4,663 bytes** |
| `docker stats` idle | **12.62 MiB / 64 MiB**, 0.00 % CPU |

If `curl /` returns 200 but **no** CSP, you are almost certainly talking to a
different service on that port — check `docker compose ps` for the port mapping.

## Phase 4 — Routing, assets and custom rules

MkDocs uses directory URLs, so routing has three behaviours worth knowing:

```bash
B=http://127.0.0.1:8080
for p in / /services/ /api/ /runbooks/ /contributing/ \
         /assets/portal.css /assets/logo.svg /search/search_index.json \
         /does-not-exist /.env /mkdocs.yml /contributing.md; do
  printf '%-28s %s\n' "$p" "$(curl -s -o /dev/null -w '%{http_code}' "$B$p")"
done
```

Expected, measured:

| Path | Code | Meaning |
| --- | --- | --- |
| `/`, `/services/`, `/api/`, `/runbooks/`, `/contributing/` | 200 | rendered pages |
| `/services` (no trailing slash) | **301** → `/services/` | Nginx normalises the directory URL |
| `/assets/portal.css` | 200 | `text/css`, `Cache-Control: max-age=604800` |
| `/assets/logo.svg` | 200 | theme logo/favicon |
| `/search/search_index.json` | 200 | the client-side search index |
| `/does-not-exist` | 404 | rendered `404.html`, no directory listing |
| `/.env`, `/mkdocs.yml`, `/contributing.md` | **403** | source and metadata are denied |

`/services` returning 301 is correct and browsers follow it; an agent asserting
`200` on the slash-less URL will report a false failure. Use `curl -L`, or assert
on the trailing-slash form.

### Nginx proxy rules

There is deliberately **no `proxy_pass`** anywhere: the portal is static. Two
consequences for an agent:

1. If a request seems to need a proxy (an API behind the same host name), that
   is a separate service — add a dedicated `location /api/` **in front of** this
   container, not inside it.
2. If you ever add one, keep the header file's `add_header` lines at server level
   and use `proxy_set_header` for the upstream. Adding `add_header` in the new
   location drops the CSP for that path only — the classic silent regression.

Cache rules live in `docker/nginx/default.conf`: hashed-ish static extensions get
`expires 7d`, `search_index.json`/`sitemap.xml` get 1h, everything else is
`max-age=0`. Because the location blocks add no headers, the security headers
survive there — verify with:

```bash
curl -sI "$B/assets/portal.css" | grep -iE 'cache-control|x-content-type-options'
```

## Phase 5 — Custom assets and theme changes

| You want to change | Edit | Then |
| --- | --- | --- |
| Page content | `portal/docs/**/*.md` | rebuild image |
| Navigation / page order | `nav:` in `portal/mkdocs.yml` | rebuild image |
| Colours, layout | `portal/docs/assets/portal.css` (loaded via `extra_css`) | rebuild image |
| Logo / favicon | `portal/docs/assets/logo.svg` referenced by `theme.logo`/`favicon` | rebuild image |
| Extra JS | add the file, list it under `extra_javascript:` | rebuild image — CSP allows `'self'` scripts only |
| Headers | `configs/nginx/security-headers.conf` (mounted, no rebuild) | restart container |
| Routing / cache / deny rules | `docker/nginx/default.conf` (baked in) | rebuild image |

There is no hot reload: the site is static and rendered at build time. Do not add
a dev server to "fix" that — a watch mode inside the image would be a runtime
dependency in a project whose whole selling point is having none.

## Phase 6 — Local drills before any deployment

Run these and record the results; Stage 4 is not complete without them.

1. `docker inspect cg-portal` → `ReadonlyRootfs: true`, `CapDrop: [ALL]`, `User: 101:101`, `no-new-privileges`.
2. `docker stats --no-stream` → steady state well under the 64 MiB limit.
3. Restart resilience: `docker restart cg-portal`, then `/healthz` again.
4. Low-spec sanity: `docker update --cpus 0.1 --memory 48m cg-portal`, then load
   `GET /` 200 times and confirm no OOM or 5xx.
5. Failure surfacing: stop the container and confirm the port refuses
   connections rather than serving a stale page.

## Phase 7 — Provision the infrastructure

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # gitignored
tofu init && tofu fmt -recursive -check && tofu validate
tofu plan                                      # expect: Plan: 6 to add
tofu apply                                     # Stage 5 only
```

Success criteria: `tofu output ingress_ports` → `[22, 80, 443]` (8080 must never
appear) and `instance_public_ip` populated.

## Phase 8 — Deploy and verify on the host

```bash
ssh ubuntu@$(tofu output -raw instance_public_ip)
cloud-init status --wait                       # expect: status: done

git clone https://github.com/kaveh8866/Internal-Developer-Portal-Static-Docs.git
cd Internal-Developer-Portal-Static-Docs
cp .env.example .env
sed -i 's/^PORTAL_BIND_ADDRESS=.*/PORTAL_BIND_ADDRESS=0.0.0.0/; s/^PORTAL_PORT=.*/PORTAL_PORT=80/' .env
docker compose --env-file .env -f docker/docker-compose.yml up -d --build
docker compose --env-file .env -f docker/docker-compose.yml ps
```

Then **re-run Phase 3 and Phase 4 against the instance** (not localhost) and
record: headers as served, cold and warm `GET /` timings, container RSS after 10
minutes idle, and the 403/404 matrix. Capture one forced failure: `docker stop
cg-portal` must make the port refuse, then start it again.

An unmeasured claim is not evidence. Put the numbers in `README.md`.

## Phase 9 — Teardown

```bash
cd terraform && tofu destroy -auto-approve
tofu state list      # must be empty
```

Then verify provider-side (instance `TERMINATED`) before removing the state file.
The portal is stateless, so unlike Project 03 there is no bucket to empty first.

## Phase 10 — Release and certification

MIT license, clean commit history, push to
`https://github.com/kaveh8866/Internal-Developer-Portal-Static-Docs.git`, then run
the CloudGuard portability audit. Never hand-write `PORTABLE_CERTIFIED`; the
audit sets it, and only when all five checks pass.

---

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `bind: Only one usage of each socket address` | host port taken | change `PORTAL_PORT` in `.env` |
| 200 with no CSP | you reached another service on that port | `docker compose ps`, then curl the mapped port |
| `mkdocs build --strict` fails | broken relative link or nav entry | fix the content; do not drop `--strict` |
| CSP blocks an asset | third-party or inline source | self-host the asset and list it under `extra_*` |
| `403` on `/` | `try_files` found no `index.html` | the build copied nothing; rebuild, check builder logs |
| Healthcheck unhealthy, page fine | `wget` missing or 8080 mis-bound | check `docker logs cg-portal`; the server block must listen on 8080 |
| `Out of host capacity` on apply | A1 capacity in AD-1 | pin `availability_domain` to AD-2; never switch to a paid shape |
| `did not find a proper configuration for tenancy` | child module inferred `hashicorp/oci` | the `providers = { oci = oci }` line is missing |
