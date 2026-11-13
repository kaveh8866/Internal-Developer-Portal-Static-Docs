# TEST_REPORT — local verification (Stage 4)

Recorded 2026-11-13 on the development machine. Every number below was measured
in this session; the commands are in §10 and the raw transcript is in
[`docs/stage-4-local-verification.txt`](docs/stage-4-local-verification.txt).

> **Scope.** Local only: one x86_64 machine, Docker Desktop, the published image
> served by Nginx. No cloud host exists yet — Stage 5 is the first deployment,
> and nothing here says the portal works on an OCI instance, on ARM, over TLS, or
> from outside a CIDR allow-list. Those are named as untested in §9.

| | |
| --- | --- |
| Host | Windows 11, `MINGW64_NT-10.0-26300`, x86_64, 16 CPUs |
| Docker Engine | 29.8.1 (Docker Desktop) |
| Docker Compose | 5.5.1 |
| Image | `cloudguard/idp-portal:local`, **77 MB** |
| Rendered site | **55 files** under `/usr/share/nginx/html` |
| Published port | `127.0.0.1:8081 -> 8080/tcp` (8080 was occupied on this machine) |
| Commit under test | `9c12f6b` + the port override in the local `.env` only |

---

## 1. Stack execution

```bash
docker compose --env-file .env -f docker/docker-compose.yml up -d
```

| Check | Result |
| --- | --- |
| Container state | `cg-portal | Up (healthy)` — healthcheck passed on the first interval |
| Port mapping | `127.0.0.1:8081->8080/tcp` (loopback only, as designed) |
| Rebuild with warm layer cache | **2 s** |
| Compose validation | `docker compose config -q` exits 0 |

The bind is loopback, which is the compose default (`PORTAL_BIND_ADDRESS`). On an
instance the value becomes `0.0.0.0` with `PORTAL_PORT=80` so the security-list
rule matches — see `MANUAL_PREREQS.md` §3.

## 2. Build and static assets

### The strict build actually refuses broken documentation

The claim that `--strict` catches dead links was **tested, not assumed**. A link
to a non-existent page was appended to `contributing.md`:

```text
WARNING -  Doc file 'contributing.md' contains a link '../does-not-exist.md',
           but the target is not found among documentation files.
Aborted with 1 warnings in strict mode!
ERROR: process "/bin/sh -c mkdocs build --strict ..." did not complete successfully: exit code: 1
```

Build exit code **1**. The file was reverted and the image rebuilt clean. A green
build therefore means something.

### Rendered output

| Check | Result |
| --- | --- |
| Index title | `<title>CloudGuard Internal Developer Portal</title>` |
| Navigation pages | `/`, `/services/`, `/api/`, `/runbooks/`, `/contributing/` all **200** |
| Runbook anchors resolve | `id="rotate-signing-keys"` present in the rendered HTML |
| Search index | `/search/search_index.json` — **23 documents**, parses as valid JSON |
| Tables rendered | 10 `<tr>` across the catalog tables |
| Stylesheet | `/assets/portal.css` → **200**, `Content-Type: text/css` |
| Logo/favicon | `/assets/logo.svg` → **200** |

## 3. Routing, health and error handling

| Request | Code | Note |
| --- | --- | --- |
| `/` | **200** | 17,488 bytes |
| `/services/` (trailing slash) | **200** | |
| `/services` (no slash) | **301** | `Location: /services/` — correct, not a failure |
| `/healthz` | **200** | body `ok`, no security headers (monitor probe by design) |
| `/nope-xyz` | **404** | rendered `404.html`, body contains `404`; no directory listing |
| `/.env` | **403** | denied |
| `/mkdocs.yml` | **403** | source metadata denied |
| `/contributing.md` | **403** | Markdown sources denied |

### Headers on `/`

```text
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
Content-Length: 17488
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
Referrer-Policy: strict-origin-when-cross-origin
Permissions-Policy: geolocation=(), microphone=(), camera=(), payment=()
Content-Security-Policy: default-src 'self'; base-uri 'self'; form-action 'self';
  frame-ancestors 'none'; img-src 'self' data:; font-src 'self' data:;
  style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; connect-src 'self'
```

Compression: **17,488 → 4,663 bytes** with `Accept-Encoding: gzip` (73 % reduction,
`Content-Encoding: gzip` confirmed on the response).

Header inheritance holds on cached paths too: `/assets/portal.css` returns
`Cache-Control: max-age=604800` **and** `X-Content-Type-Options: nosniff`, which is
the check that catches the classic "location-level `add_header` stripped the CSP"
regression.

## 4. Container hardening (from `docker inspect`)

| Control | Measured value |
| --- | --- |
| Read-only root filesystem | `true` |
| Capabilities | `cap_drop: [ALL]` |
| User | `101:101` (unprivileged Nginx) |
| `no-new-privileges` | present in `SecurityOpt` |
| PIDs limit | `64` |
| Memory limit | `67,108,864` bytes (64 MiB) |
| CPU limit | `250,000,000` nanocpus (0.25 CPU) |

## 5. Restart resilience

`docker restart cg-portal` → after 6 s: `/` **200**, `/healthz` **ok**. No manual
intervention, no stale page.

## 6. Low-spec behaviour (the smallest instance matters)

The deployment target is a 1 OCPU / 1 GB A1 instance, so the container was
tightened well below that and loaded:

```bash
docker update --cpus 0.1 --memory 48m cg-portal
# 200 sequential GET /
```

| Metric | Result |
| --- | --- |
| Limits applied | `100,000,000` nanocpus (0.1 CPU), `50,331,648` bytes (48 MiB) |
| Responses | **200/200 returned 200** — zero 5xx, zero timeouts |
| Wall time | **9,765 ms** for 200 serial requests (~49 ms each, single-threaded client) |
| Memory during load | **12.71 MiB / 48 MiB** |
| Processes | 17 pids of 64 |

Headroom is roughly 3.7× on memory at 0.1 CPU. The 49 ms per request is dominated
by curl process startup on Windows, not by Nginx — it is a floor, not a
measurement of server latency.

## 7. Failure surfacing

| Action | Result |
| --- | --- |
| `docker stop cg-portal`, then `curl` | connection refused (`curl` exit **7**, HTTP `000`) |
| `docker start cg-portal` | `/` **200**, `/healthz` **ok** |

A stopped portal fails loudly. It does not serve a stale page, which is the
failure mode that makes an internal portal lie to its readers.

## 8. Log hygiene

475 log lines across the session; exactly **1** at error level:

```text
[error] access forbidden by rule, request: "GET /.env HTTP/1.1"
```

That line is the deliberate §3 probe. There were no unexpected errors, no
upstream failures (there is no upstream), and no warnings from Nginx startup.

## 9. Not tested here — do not assume these

- **ARM (aarch64).** This host is x86_64. The image is multi-arch and the Stage 5
  target is Ampere, but the ARM build has not been exercised.
- **TLS / port 443.** No terminator exists; the container speaks plain HTTP.
- **`web_allowed_cidr` enforcement.** Only testable once the security list is
  applied in OCI (Stage 5).
- **Cold build time.** Only the warm-cache rebuild (2 s) was timed; the pip layer
  dominates a cold build and was not measured.
- **Visual rendering.** No browser screenshot or cross-viewport check was taken;
  assertions are on status codes, headers and DOM markers, not on appearance.
- **Concurrency.** The load test was serial; no parallel or keep-alive benchmark
  was run.

## 10. Reproduce

```bash
cd docker
docker compose --env-file ../.env -f docker-compose.yml up -d --build
B=http://127.0.0.1:8081

curl -s  $B/healthz                       # ok
curl -sI $B/ | head -12                   # 200 + CSP
curl -s -o /dev/null -w '%{http_code}\n' $B/services   # 301
curl -s -o /dev/null -w '%{http_code}\n' $B/.env       # 403
curl -s -o /dev/null -w '%{http_code}\n' $B/nope-xyz   # 404
docker inspect cg-portal --format '{{.HostConfig.ReadonlyRootfs}} {{.HostConfig.CapDrop}}'
docker stats --no-stream cg-portal
```

---

## 11. Live OCI deployment (Stage 5)

Run against a real tenancy in `eu-frankfurt-1` on 2026-11-13. Infrastructure came
from `terraform/` unmodified; only `terraform.tfvars` (gitignored) supplied the
credentials, SSH key and CIDRs.

### Provisioning

| Step | Result |
| --- | --- |
| `tofu apply` | `Apply complete! Resources: 6 added` — VCN, IGW, route table, security list, subnet, instance |
| Instance | created in **34 s** in AD-2 (AD-1 avoided from the Project 04 capacity lesson) |
| Public IP | **152.70.169.194** |
| Shape | `VM.Standard.A1.Flex`, 1 OCPU / 1 GB, Ubuntu 24.04, **aarch64** |
| `cloud-init status` | `done`; Docker 29.9.3 |
| Ingress | `tofu output ingress_ports` → `[22, 80, 443]` |

### Deployment

The repository was not published at deploy time (Stage 8 has since released it as
`v1.0.0`), so the tracked tree was transferred
rather than cloned: `git archive HEAD | ssh … tar -x` — 36 files, no `.git`, no
`.env`, no `terraform.tfvars`.

| Step | Result |
| --- | --- |
| Build on aarch64 | **40 s** for build + start (deps are pure-Python wheels) |
| Image | `arm64`, **79 MB** |
| Container | `Up (healthy)`, `0.0.0.0:80->8080/tcp` |
| `docker inspect` | `readonly=true`, `capdrop=[ALL]`, `user=101:101`, `mem=64 MiB` |
| Host sockets | `22`, `80` only — **nothing on 8080**, nothing on 443 |

### Live behaviour, measured from the public internet

| Request | Code | Time |
| --- | --- | --- |
| `/` | 200 | 48.7 ms |
| `/services/` | 200 | 47.9 ms |
| `/api/` | 200 | 47.8 ms |
| `/runbooks/` | 200 | 49.2 ms |
| `/contributing/` | 200 | 49.5 ms |
| `/services` | **301** → `/services/` | 31.7 ms |
| `/assets/portal.css` | 200 | 32.3 ms |
| `/assets/logo.svg` | 200 | 32.8 ms |
| `/search/search_index.json` | 200 | 35.0 ms |
| `/healthz` | 200 | 32.6 ms |
| `/nope-xyz` | **404** | 34.6 ms |
| `/.env` | **403** | 32.2 ms |
| `/mkdocs.yml` | **403** | 32.0 ms |
| `http://152.70.169.194:8080/` | **unreachable** (`000`) | — |

Headers on `/` are identical to the local run: CSP, `nosniff`, `X-Frame-Options:
DENY`, referrer and permissions policy. gzip unchanged at 17,488 → 4,663 B.
Rendered markers verified on the live host: index title, 10 catalogue table rows,
the `rotate-signing-keys` runbook anchor, and 23 documents in the search index.

### Host footprint

| Metric | Value |
| --- | --- |
| Container memory | **2.4 MiB / 64 MiB** (lower than the 12.6 MiB local run — arm64 idle Nginx with 2 pids) |
| CPU | 0.00 % idle |
| Rendered site | 55 files, 2.62 MB |
| Host | 425 / 945 MB RAM, 44 G free disk |
| Log lines | 50 total, 4 at error level — **all four are the deliberate `/.env` and `/mkdocs.yml` probes** |

### What Stage 5 changed about earlier claims

- **ARM is now verified.** §9 listed aarch64 as untested; the image builds and
  runs correctly on Ampere, in 40 s.
- **The security list is enforced, not just written.** 8080 is unreachable from
  outside while 80 answers — the compose/port contract holds in the cloud.
- **First-byte latency from the internet is ~48 ms**, which is dominated by
  round-trip time to Frankfurt, not by Nginx (assets are 32 ms for the same
  reason).

### Still open after Stage 5

- **TLS.** 443 is open but nothing listens; the page is served over plain HTTP.
- **`web_allowed_cidr` is `0.0.0.0/0`.** The portal was left reachable so the run
  could be verified end-to-end. For an internal portal this must be narrowed, or
  the proxy added and 80 closed. This is the single most important follow-up.
- **Visual rendering** was still not reviewed in a browser; assertions are on
  status codes, headers and DOM markers.
- **No load test against the live host** — the low-spec numbers in §6 are local.
- **The environment was destroyed in Stage 6.** `tofu destroy` removed all six
  resources; the provider confirms the instance `TERMINATED` and no VCN remains.
  See [`TEARDOWN_REPORT.md`](TEARDOWN_REPORT.md). Nothing above is invalidated —
  it is simply a record, not a running service.
