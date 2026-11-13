# AGENT_GUIDE — Internal Developer Portal

Operating instructions for AI coding agents (Cursor, Claude Code, Windsurf,
Codebuff) working in this repository.

## Ground rules

- **Final production verification happens on Oracle Cloud Infrastructure (OCI).**
  OCI is the certified target: it is where the host is provisioned, where the
  portal is served, and where the response headers and 404 behaviour are signed
  off. Any other platform is a documented port, not a certified one — never
  describe this project as "AWS-verified" or "Vercel-verified".
- **Current status:** Stage 1 (scaffold) is complete and the stack builds and
  serves locally. Stage 2 is written and statically verified — `tofu validate`
  passes and `tofu plan` reports `6 to add` — but **nothing has been applied**:
  no VCN, no instance, no reachable portal. Verify before claiming anything —
  see the phase map.
- **Git boundary:** `.env`, `terraform.tfvars`, `*.tfstate`, `*.pem`, build
  output (`site/`) and local overrides never enter Git. The `.gitignore` blocks
  them; a blocked file that was copied into the tree is still a leak.

| Project stage | Playbook phases | State |
| --- | --- | --- |
| Stage 1 — scaffold, Docker, Nginx, Git boundary | 0, 1 | ✅ complete |
| Stage 2 — OpenTofu provisioning | 2 | ✅ written, plan 6 to add (not applied) |
| Stage 3 — this guide + prerequisites | — | 🟡 guide drafted |
| Stage 4 — local drills (headers, 404, low-spec) | 3, 4 | ⬜ |
| Stage 5 — live OCI deploy + verification | 5 | ⬜ |
| Stage 6 — teardown, zero resources | 6 | ⬜ |
| Stage 7 — security audit, cost table, README | 7 | ⬜ |
| Stage 8 — release + vault certification | 8 | ⬜ |

---

## Hard limits for an agent

- **Never open 8080 to the internet.** The portal is internal. Compose binds
  loopback by default; the Stage 2 security list must keep 8080 closed and let
  the platform proxy reach it over the private network.
- **Never add a runtime dependency to the portal.** It is static HTML behind
  Nginx: no PHP, no Node server, no database. If a request needs dynamic
  behaviour, it belongs to another project.
- **Never serve the Markdown sources.** `location ~* \.md$` is denied on
  purpose; do not "fix" a 404 by allowing source files through.
- **Never add `add_header` inside a `location`.** Nginx drops every inherited
  header when a location declares its own, which silently removes the CSP from
  that path. Put headers in `configs/nginx/security-headers.conf` at server
  level.
- **Never disable `--strict`** to make a build pass. A broken link that ships is
  worse than a red build: the strict build is the only dead-link detector the
  project has.
- **Never commit `site/`, `.env`, or a real hostname.** `site/` is build output;
  the rest is credentials or internal topology.

---

## Phase 0 — Preflight

```bash
docker version --format '{{.Server.Version}}'    # engine must answer
docker compose version
git status --porcelain                           # must be empty before you start
```

Stop if the Docker daemon is unreachable: every verification below needs it.

## Phase 1 — Build and serve

```bash
cp .env.example .env
docker compose --env-file .env -f docker/docker-compose.yml up -d --build
docker compose --env-file .env -f docker/docker-compose.yml ps
```

Success criteria: `cg-portal` reports `healthy`, and `curl -sI` on `/` returns
`200` with `X-Content-Type-Options: nosniff` and a `Content-Security-Policy`.

## Phase 2 — Provision (OCI)

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # gitignored; fill in the tenancy
tofu init && tofu fmt -recursive -check && tofu validate
tofu plan                                      # expect: Plan: 6 to add
tofu apply                                     # Stage 5 only
```

Success criteria: `output.ingress_ports == [22, 80, 443]` (8080 must never
appear) and `output.instance_public_ip` is populated. A1 capacity is the usual
failure: pin `availability_domain` to AD-2 rather than switching to a paid
shape.

## Phase 3 — Content integrity

```bash
docker run --rm -v "$PWD/portal:/portal" -w /portal python:3.12-alpine \
  sh -c 'pip install -q -r requirements.txt && mkdocs build --strict'
```

A non-zero exit means a broken internal link, an orphan page or a missing nav
entry. Fix the content; do not relax the flag.

## Phase 4 — Local drills

Verify, from the running container:

1. `GET /` → 200, HTML, CSP present.
2. `GET /healthz` → `ok`, no security headers needed (it is a monitor probe).
3. `GET /does-not-exist` → 404 page, not a directory listing.
4. `GET /.env` and `GET /mkdocs.yml` → 403, never file contents.
5. `docker stats --no-stream` → steady-state RSS well under the 64 MiB limit.
6. `docker inspect` → `ReadonlyRootfs: true`, `CapDrop: [ALL]`.

## Phase 5 — Live OCI verification

Deploy on the provisioned host, then re-run the Phase 4 checks **against the
instance** over the private network, and capture:

- response headers as served by the real host (CSP, nosniff, frame denial);
- cold-start and warm response times for `/` and a nested page;
- container RSS and CPU after 10 minutes of idle;
- one forced failure: stop the container, confirm the proxy returns 502 rather
  than a stale page, then restore.

Record the numbers in `README.md`. An unmeasured claim is not evidence.

## Phase 6 — Teardown

```bash
cd terraform && tofu destroy -auto-approve
tofu state list        # must be empty
```

Then verify provider-side (the instance shows `TERMINATED`) before removing the
state file. The portal is stateless, so teardown needs no bucket emptying — one
of the few advantages of having no storage.

## Phase 7 — Audit

Re-run the zero-leak scan (`git status --porcelain`, `git check-ignore -v` on
every secret path), confirm no `.md` source is reachable over HTTP, and refresh
the cost table. Note that the free-tier envelope makes the running cost zero.

## Phase 8 — Release and certification

MIT license, clean commit history, push to
`https://github.com/kaveh8866/Internal-Developer-Portal-Static-Docs.git`, then
run the CloudGuard portability audit so the vault row reflects reality. Never
write `PORTABLE_CERTIFIED` by hand — the audit writes it, and only when all five
checks pass.
