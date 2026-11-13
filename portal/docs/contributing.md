# Contributing

Documentation is reviewed like code. That is the whole policy — the rest is
mechanics.

## Local preview

```bash
docker compose --env-file .env -f docker/docker-compose.yml up -d --build
# portal: http://127.0.0.1:8080
```

Rebuild after editing content:

```bash
docker compose --env-file .env -f docker/docker-compose.yml up -d --build portal
```

Building without Docker requires MkDocs 1.6 and the pins in
`portal/requirements.txt`; the image is the supported path because it is the
same renderer that serves production.

## Writing rules

- **One page, one job.** If a page needs a table of contents longer than the
  page, split it.
- **No credentials, ever** — not in an example, not in a screenshot, not as a
  "temporary" placeholder that looks real. Use `example.invalid` and obvious
  placeholders.
- **Link internally** with relative paths (`../api/index.md`), never absolute
  URLs: the build fails on a broken relative link, which is how dead
  documentation gets caught.
- **State the failure mode.** "Run this command" without "and here is how you
  know it worked" is an unfinished sentence.

## Review checklist

| Check | Why |
| --- | --- |
| Page is in `portal/mkdocs.yml` nav | Unlisted pages are effectively unpublished |
| Internal links resolve | `--strict` enforces this at build time |
| Owners and channels are real | A catalog row nobody answers is worse than none |
| No secrets, no customer data | The portal is internal, not private from staff |

## Where things live

```
portal/docs/        Markdown sources (what you edit)
portal/mkdocs.yml   Navigation, theme, extensions
docker/             Compose, Nginx server block
configs/nginx/      Security headers mounted into the container
terraform/          OCI provisioning (Stage 2, not yet applied)
```
