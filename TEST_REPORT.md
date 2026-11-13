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
