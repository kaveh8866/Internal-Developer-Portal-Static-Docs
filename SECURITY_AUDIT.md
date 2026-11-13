# SECURITY_AUDIT — Stage 7 sign-off

Audit date: 2026-11-13. Scope: the repository, the container image, and the
running behaviour of the server. Findings below are from executed commands, not
from reading configuration and assuming it works.

**Verdict: no credential leak, no exposed source material, no server-version
disclosure, and no writable surface in the runtime.** Two accepted risks are
recorded in §6 — one is a deliberate design choice, the other is a deployment
parameter that must be narrowed before any real use.

---

## 1. Zero-leak scan

### Files on disk vs. files in Git

| Artefact | Exists locally | Tracked | Ignored |
| --- | --- | --- | --- |
| `.env` | yes (local run config) | **no** | yes |
| `terraform/terraform.tfvars` | yes (OPERATOR CONFIG) | **no** | yes |
| `*.pem`, `*.key`, `*.p12`, `*.pfx` | none | — | rule present |
| `id_rsa*`, `id_ed25519*` | none | — | rule present |
| `rclone.conf`, `credentials.json` | none | — | rule present |
| `*.tfstate` | removed after teardown | **no** | yes |

Commands used, in order:

```bash
find . -path ./.git -prune -o \( -name "*.pem" -o -name "*.key" -o -name ".env" \
     -o -name "*.tfvars" -o -name "id_ed25519*" \) -print
git ls-files --error-unmatch <path>      # tracked?
git check-ignore -q <path>               # ignored?
```

Result: **two** sensitive files exist on disk, both gitignored, neither tracked.
A file that is ignored but untracked is the correct steady state; a file that is
tracked is a leak regardless of `.gitignore`.

### Secret signatures in tracked content

```bash
git grep -nIE "(BEGIN [A-Z ]*PRIVATE KEY|ssh-ed25519 AAAA[^ ]{24,}|\
ocid1\.(tenancy|user)\.oc1\.[a-z0-9]{30,}|AKIA[0-9A-Z]{16}|\
hooks\.slack\.com/services/[A-Za-z0-9/]{10,}|api[_-]?key\s*=\s*['\"][A-Za-z0-9]{16,})"
```

**Zero matches** in the 37 tracked files. The only near-misses are documented
placeholders:

- `terraform.tfvars.example` — `config_file_profile = "DEFAULT"` and commented
  `fingerprint = "aa:bb:…"`, both obviously synthetic.
- `MANUAL_PREREQS.md` — an example `~/.oci/config` block with `ocid1.user.oc1..xxxx`.
- `.env.example` — 21 keys, every value non-empty and a placeholder.

### `.gitignore` and `.env.example` are active, not decorative

| Check | Result |
| --- | --- |
| Rules for `.env`, `*.tfstate`, `*.pem`, `*.key`, `site/` | **5 of 5 present** |
| `.env.example` tracked | yes (1) |
| `.env` tracked | **0** |
| Empty values in `.env.example` | **0 of 21** |
| Live-looking values in `.env.example` | **0** |

`.env.example` carries the OCI block with placeholder OCIDs, an example
`ssh-ed25519` key marked as a placeholder, and a `PORTAL_BASIC_AUTH_PASSWORD`
that reads `replace-me-before-exposing`. None of it is usable.

## 2. Container hardening (read back from `docker inspect`)

| Control | Value |
| --- | --- |
| User | `101:101` — unprivileged Nginx, no root process in the container |
| Read-only root filesystem | `true` |
| Capabilities | `CapDrop: [ALL]` |
| Privilege escalation | `no-new-privileges:true` |
| PIDs limit | 64 |
| Memory / CPU | 64 MiB / 0.25 CPU |
| Writable paths | `/tmp` (16 m) and `/var/cache/nginx` (8 m) only, as tmpfs |

There is no shell in the runtime image, no package manager, and no build
toolchain: the Python stage is discarded.

## 3. HTTP behaviour

| Test | Result | Assessment |
| --- | --- | --- |
| `GET /` | 200 | — |
| `HEAD /` | 200 | — |
| `POST`, `PUT`, `DELETE`, `PATCH` | **405** | static server refuses mutation verbs |
| `OPTIONS`, `TRACE` | **405** | no method enumeration; TRACE disabled |
| `GET /.env` | **403** | credential file not served |
| `GET /mkdocs.yml` | **403** | config not served |
| `GET /contributing.md` | **403** | sources not served |
| `GET /assets/` | **403** | directory listing disabled |
| `GET /%2e%2e/mkdocs.yml` | **403** | encoded traversal blocked |
| `GET /../etc/passwd` | 404 | normalised away by the client/server |
| `Server` header | `nginx` | `server_tokens off` — no version |

Headers on **error** responses, which is where header configuration usually
breaks:

| Response | CSP | `nosniff` |
| --- | --- | --- |
| 404 `/nope-xyz` | present | present |
| 403 `/.env` | present | present |

This matters because `error_page` internal redirects can drop server-level
headers if a location declares its own `add_header`. It does not here.

## 4. Content security policy review

```text
default-src 'self'; base-uri 'self'; form-action 'self'; frame-ancestors 'none';
img-src 'self' data:; font-src 'self' data:; style-src 'self' 'unsafe-inline';
script-src 'self' 'unsafe-inline'; connect-src 'self'
```

`'unsafe-inline'` for `script-src` and `style-src` is required by MkDocs
Material's palette toggle and inline styles. That is the one weakening in the
policy, and it is recorded rather than hidden. There is no `unsafe-eval`, no
remote origin, and `frame-ancestors 'none'` plus `X-Frame-Options: DENY` prevent
framing.

A stricter alternative exists — a hash-based policy for Material's single inline
script — but it breaks on every theme upgrade. For an internal, static,
first-party-content site the trade is acceptable; for a portal accepting
user-generated HTML it would not be.

## 5. Supply chain and build

| Item | State |
| --- | --- |
| Base images | `python:3.12-alpine`, `nginxinc/nginx-unprivileged:1.27-alpine` |
| Python dependencies | **pinned exactly** (`mkdocs==1.6.1`, `mkdocs-material==9.8.1`, `pymdown-extensions==13.1`) — raised from 9.5.44 / 10.12 on 2026-11-13, see §5a |
| Build-tool exposure | none — the Python stage is not shipped |
| Nginx config review | one server block, no `proxy_pass`, no CGI, no `include` of user paths |
| Image provenance | built locally; `.terraform.lock.hcl` pins the OCI provider |

Dependency pins are deliberate: an unpinned docs toolchain means a build that can
change behaviour without a commit.

### 5a. Dependency advisories (Dependabot, resolved in v1.0.1)

GitHub reported **5 open alerts** on the default branch after the v1.0.0 push:
1 high, 3 moderate, 1 low. All five were in **build-stage Python packages**, not
in the shipped runtime image — but they still count: the build is the supply
chain, and a compromised or slow build is a real defect.

| # | Severity | Package | Advisory | Issue | Fixed in |
| --- | --- | --- | --- | --- | --- |
| 1 | LOW | pymdown-extensions | GHSA-r6h4-mm7h-8pmq / CVE-2025-68142 | ReDoS in the figure-capture extension | 10.16.1 |
| 2 | MEDIUM | pymdown-extensions | GHSA-62q4-447f-wv8h / CVE-2026-46338 | `snippets` sibling-prefix path traversal bypass of `restrict_base_path` | 10.21.3 |
| 3 | MEDIUM | pymdown-extensions | GHSA-9xwg-3r6f-jcx2 / CVE-2026-61632 | Path traversal in the `b64` extension lets `<img src>` read files outside `base_path` | 11.0.0 |
| 4 | **HIGH** | pymdown-extensions | GHSA-gm37-52c6-37mw / CVE-2026-67422 | Exponential-backtracking ReDoS in caret, tilde, betterem and magiclink inline processors | 11.0.1 |
| 5 | MEDIUM | mkdocs-material | GHSA-xvg9-69gf-fjrf / CVE-2026-73295 | DOM XSS in search suggestions via a query parameter | 9.7.7 |

**Resolution:** the single floor that satisfies all five is
`pymdown-extensions>=11.0.1` and `mkdocs-material>=9.7.7`. Pins moved to the
current releases — `mkdocs-material==9.8.1` and `pymdown-extensions==13.1` — with
`mkdocs==1.6.1` unchanged (no advisory, and `9.8.1` requires `mkdocs>=1.6,<2`).

The security floor is now also written into `portal/requirements.txt` as a
comment block, so lowering a pin requires deliberately deleting the reason.

**Why the site was not exposed by #5:** the DOM XSS lives in the search
suggestions widget, which renders client-side from `search_index.json`. Content
in this portal is first-party and authored in Git, so there is no untrusted input
path — but the fix is free, and "we trust our own content" is not a security
control. The CSP would also have blocked a naive exfiltration attempt.

**Rebuild evidence (this is the part that matters):**

```text
docker build --no-cache --progress=plain   # builder stage, no cached layers
  Successfully installed ... mkdocs-1.6.1 mkdocs-material-9.8.1
                            pymdown-extensions-13.1 markdown-3.11.3 ...
  [builder 7/7] RUN mkdocs build --strict --clean --site-dir /site   → exit 0
```

`--strict` treats warnings as errors, so a dead link, a missing nav entry or a
broken extension would have failed the image build. It passed with no warnings.

Runtime re-verified after the bump: `/`, `/services/`, `/api/`, `/runbooks/`,
`/contributing/` → 200; `search_index.json` → 200 with **23 entries** and a
`config` block (the widget's data contract survived the theme upgrade); real
hashed asset `assets/stylesheets/main.57a0d79d.min.css` → 200 (23,392 B gzip);
`/.env` and `/mkdocs.yml` still 403; CSP, `nosniff`, `X-Frame-Options: DENY`
still present; `Server: nginx` still version-free; container 13.2 MiB / 64 MiB.

## 6. Accepted risks

| Risk | Severity | Status |
| --- | --- | --- |
| **`web_allowed_cidr` was `0.0.0.0/0` during the Stage 5 run** | **High for an internal tool** | Accepted **only** for verification, and remediated by teardown. An internal portal must be restricted to the office/VPN range, or fronted by the proxy with 80 closed. Documented in README and `MANUAL_PREREQS.md` §5. |
| **No TLS terminator** | Medium | The container serves plain HTTP on 8080; 443 is reserved for the proxy. HSTS is intentionally **not** set, so browsers are never pinned to a scheme this container cannot serve. |
| `'unsafe-inline'` in CSP | Low | Required by the theme; no remote origins permitted. See §4. |
| No authentication in the container | Low (by placement) | Access control belongs at the proxy or allow-list. The container is not the security boundary for identity. |

## 7. What this audit does **not** cover

- **Penetration testing.** No fuzzing, no automated scanner, no exploit attempt.
- **Dependency CVE scanning is now advisory-driven, not exhaustive.** The five
  Dependabot alerts were pulled through the GitHub API and fixed (§5a), and the
  theme's transitive dependencies (Markdown 3.11.3, Jinja2 3.1.6, requests 2.34.2)
  resolved clean on rebuild. No `pip-audit` or Trivy run has been performed, and
  the container base images are not scanned — a CI job should own both.
- **TLS configuration.** There is no TLS listener to assess.
- **Multi-tenant isolation.** The portal is single-tenant by design — no user
  accounts, no writes, no per-user data.
- **Live environment.** All runtime checks were performed on the local container;
  Stage 5 reproduced a subset on the OCI instance and Stage 6 destroyed it.

## 8. Sign-off

| Requirement | Status |
| --- | --- |
| Dependency advisories resolved | ✅ 5/5 fixed in v1.0.1, strict rebuild verified |
| No private keys in the tree | ✅ none present |
| No tracked secrets | ✅ 0 of 37 files |
| `.gitignore` boundary active | ✅ verified per path |
| `.env.example` placeholder-only | ✅ 21 keys, no live values |
| Runtime cannot escalate or write | ✅ uid 101, `cap_drop: ALL`, read-only |
| Sources and metadata not served | ✅ 403 on `.md`, `.yml`, dotfiles |
| Header coverage including errors | ✅ CSP + `nosniff` on 200/403/404 |

Signed off for packaging (Stage 8), and published as `v1.0.0` on the basis of the
evidence above.
