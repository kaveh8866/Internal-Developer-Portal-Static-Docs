# MANUAL_PREREQS — operator checklist

Everything a human must have in place **before** running the deployment commands
in this repository. Work top to bottom; each section ends with something you can
verify, not something you assume.

> **This is a pre-flight document, not a status report.** At the time of writing,
> Stage 1 (local build) and Stage 2 (IaC written, `tofu plan` → `6 to add`) are
> done and **nothing has been applied in OCI**. No VCN, no instance, no URL
> exists yet. Stage 5 is the first `apply`.

---

## 0. Certification scope

- **Certified target: Oracle Cloud Infrastructure (OCI)**, using trial credits /
  the Always Free envelope. Final production verification and testing
  certification are performed strictly there.
- The OpenTofu configuration and the Nginx/container setup are **cloud-agnostic**
  and map onto AWS EC2/VPC and GCP GCE/VPC (see `terraform/README.md`). Those
  ports are documented, not certified, and carry no test evidence.
- The portal is **internal**. It is not a public website, and it must not become
  one by accident.

---

## 1. Accounts and access

- [ ] OCI tenancy with trial credits or Always Free, region chosen (this project
      is validated in `eu-frankfurt-1`).
- [ ] An IAM **user** you can create an API signing key for (not a federated-only
      login — API keys need a local user).
- [ ] A **compartment** to own the resources. Using the tenancy root also works;
      a dedicated compartment makes teardown unambiguous and costs nothing.
- [ ] Permission to create: VCN, internet gateway, route table, security list,
      subnet, compute instance, and boot volume.
- [ ] Always Free capacity awareness: **4 OCPU / 24 GB total** across all
      A1.Flex instances in the tenancy. The portal asks for 1 OCPU / 1 GB.
- [ ] An SSH key pair you control. The **public** half goes into
      `terraform.tfvars`; the private half never leaves your machine.

Verify: you can log into the OCI console and see the compartment you intend to
use.

## 2. OCI API credentials (local only)

Create an API key in the console: *Identity → Users → your user → API keys →
Add API key → generate key pair*. Save the private key outside any repository.

Then configure the local CLI profile:

```bash
mkdir -p ~/.oci
# paste the generated config into ~/.oci/config, or use:
#   oci setup config
chmod 600 ~/.oci/config ~/.oci/oci_api_key.pem
```

The profile looks like this (values are yours; never commit it):

```ini
[DEFAULT]
user=ocid1.user.oc1..xxxx
fingerprint=xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx
tenancy=ocid1.tenancy.oc1..xxxx
region=eu-frankfurt-1
key_file=/home/you/.oci/oci_api_key.pem
```

- [ ] `~/.oci/config` exists and is readable by you only.
- [ ] The key file path inside the config is absolute and correct.
- [ ] `terraform.tfvars` sets `config_file_profile = "DEFAULT"` (or your profile
      name) instead of inlining key material.

Verify without creating anything:

```bash
cd terraform
tofu init
tofu plan        # expect: Plan: 6 to add  (no prompt for credentials)
```

If `plan` asks for credentials, the profile is not being picked up — fix that
before going further.

## 3. Portal parameters

Copy the template and edit **your** copy (both are gitignored):

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
cp .env.example .env
```

### `terraform/terraform.tfvars`

| Variable | What to put |
| --- | --- |
| `tenancy_ocid`, `compartment_ocid` | from the console (tenancy OCID is under *Tenancy details*) |
| `region` | e.g. `eu-frankfurt-1` |
| `config_file_profile` | `DEFAULT` unless you named your profile |
| `ssh_public_key` | contents of `~/.ssh/id_ed25519.pub` — **public** key, one line |
| `ssh_allowed_cidr` | your egress IP + `/32` (`curl -s https://ifconfig.me`) |
| `web_allowed_cidr` | **narrow this**: office/VPN range. `0.0.0.0/0` is the default only so a fresh deploy is reachable |
| `availability_domain` | leave unset first; pin AD-2 if apply reports `Out of host capacity` |
| `instance_ocpus` / `instance_memory_gbs` | 1 / 1 — the portal needs 64 MB |

### `.env` (portal runtime)

| Variable | Local run | On the OCI host |
| --- | --- | --- |
| `PORTAL_BIND_ADDRESS` | `127.0.0.1` (local-only) | `0.0.0.0` |
| `PORTAL_PORT` | `8080`, or `80` to match production | **`80`** — matches the security list rule |
| `PORTAL_SITE_URL` | `http://localhost:8080/` | your real internal URL, with trailing slash |
| `PORTAL_ENV` | `development` | `production` |
| `TZ` | `UTC` | `UTC` |

The container **always listens on 8080 internally**; `PORTAL_PORT` is only the
host side. Port 8080 is never opened in the security list — do not add it.

## 4. Content structure

The portal is only as good as its content tree, and the build enforces the tree.

```
portal/
├── mkdocs.yml            # nav, theme, extensions — pages not listed here are
│                         # reachable but effectively unpublished
├── requirements.txt      # pinned build deps (mkdocs, material, pymdown)
└── docs/
    ├── index.md          # landing page
    ├── services/index.md # service catalog
    ├── api/index.md      # API specifications
    ├── runbooks/index.md # recovery procedures
    ├── contributing.md   # how to write for this portal
    └── assets/           # portal.css, logo.svg, (your images)
```

Rules that the `--strict` build enforces for you:

- [ ] Every page is listed in `nav:` in `portal/mkdocs.yml`.
- [ ] Every internal link is **relative** (`../api/index.md`, `#anchor`), not an
      absolute URL.
- [ ] Anchors referenced across pages exist as headings (`#rotate-signing-keys`
      needs a `## Rotate signing keys` heading).
- [ ] Asset references point at files under `portal/docs/assets/`.

Adding a page: create the `.md`, add it to `nav:`, link it from somewhere real,
then rebuild. A page nobody links to is a page nobody finds.

**Never** put credentials, real customer data, internal hostnames or screenshots
of dashboards in `portal/docs/`. The portal is internal, which is not the same as
private-from-staff, and every page is one export away from being public.

## 5. Domain, ports and TLS

- [ ] Decide the URL: `<portal>.<internal-domain>` recorded in your internal DNS,
      pointing at the instance's public IP (or at the proxy in front of it).
- [ ] Decide the port story. The container speaks **plain HTTP**; the security
      list opens **22, 80, 443**.
  - *Simplest internal deploy*: publish on host port 80, browse
    `http://<host>/`, accept plaintext inside the network.
  - *TLS*: terminate at the platform proxy or an Nginx/Caddy sidecar in front and
    forward to `127.0.0.1:8080`. Port 443 is already open for it. Until a
    terminator exists, `https://` on this host will not connect — that is
    expected, not a bug.
- [ ] If you terminate TLS, enable HSTS **there**, not in
      `configs/nginx/security-headers.conf` — pinning a scheme this container
      cannot serve breaks access.

## 6. Before you deploy

- [ ] `tofu validate` passes and `tofu plan` shows `6 to add`.
- [ ] `tofu output` is empty (nothing applied yet).
- [ ] `docker compose --env-file .env -f docker/docker-compose.yml config -q`
      passes.
- [ ] The portal renders locally with `200` on `/`, a CSP header, `403` on
      `/.env` and `404` on a missing page.
- [ ] `git status --porcelain` is clean — no `.env`, no `terraform.tfvars`
      staged.
- [ ] You know your teardown command (`cd terraform && tofu destroy
      -auto-approve`).

## 7. Deployment sequence (Stage 5)

```bash
cd terraform
tofu apply                     # expect: 6 added
tofu output ingress_ports      # expect: [22, 80, 443]
tofu output instance_public_ip

ssh ubuntu@$(tofu output -raw instance_public_ip)
#   cloud-init status --wait
#   git clone https://github.com/kaveh8866/Internal-Developer-Portal-Static-Docs.git
#   cd Internal-Developer-Portal-Static-Docs && cp .env.example .env
#   set PORTAL_BIND_ADDRESS=0.0.0.0 and PORTAL_PORT=80 in .env
#   docker compose --env-file .env -f docker/docker-compose.yml up -d --build
```

## 8. Verification checklist (run against the instance, not localhost)

- [ ] `curl -sI http://<ip>/` → `200` **and** `Content-Security-Policy`
- [ ] `curl -s http://<ip>/healthz` → `ok`
- [ ] `curl -sI http://<ip>/services` → `301` with `Location: /services/`
- [ ] `curl -s -o /dev/null -w '%{http_code}' http://<ip>/.env` → `403`
- [ ] Missing page → `404`
- [ ] `docker stats --no-stream` → RSS well under 64 MiB
- [ ] From **outside** the allowed CIDR, 80/443 are unreachable (proves the
      allow-list works, not just that the port is open)

## 9. Teardown (Stage 6)

```bash
cd terraform && tofu destroy -auto-approve
tofu state list     # must be empty
```

Then confirm in the console that the instance shows `TERMINATED` and the VCN is
gone, and only then remove the local state file. The portal is stateless: no
bucket to empty, no database to snapshot. Zero burn rate means $0 and no
lingering boot volume.

## 10. Common questions

**Can this run on AWS or GCP?** The configuration is written to port, and the
mapping tables name every equivalent resource. It is not certified there, and
this repository carries no evidence for those platforms.

**Why is 8080 not open if the container listens on 8080?** Because the host
publishes it as port 80. Keeping 8080 closed means there is exactly one way in,
and the security list documents it.

**Can I add a database-backed search or comments?** No. This project is static by
design; adding a runtime turns it into a different project with a different
threat model.

**Why did `apply` fail with `Out of host capacity`?** A1 capacity in AD-1. Pin
`availability_domain` to AD-2 and re-apply. Do not switch to a paid shape to make
the error go away.
