# syntax=docker/dockerfile:1.7
# =============================================================================
# Internal Developer Portal — MkDocs Material build + hardened Nginx runtime
# =============================================================================
# Two stages, no build tools in the shipped image:
#   builder  python:3.12-alpine, renders portal/docs -> /site with --strict
#   runtime  nginx-unprivileged (uid 101, listens on 8080, no root anywhere)
#
# The build context is the repository root so the runtime config under docker/
# and the portal sources under portal/ are both reachable.

# --- Stage 1: render the static site ----------------------------------------
FROM python:3.12-alpine AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /portal

# Dependencies first: this layer only rebuilds when the pins change.
COPY portal/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

COPY portal/mkdocs.yml ./mkdocs.yml
COPY portal/docs ./docs

# --strict turns a broken internal link, a missing nav page or a bad anchor into
# a build failure, so a green image means the portal is internally consistent.
RUN mkdocs build --strict --clean --site-dir /site

# --- Stage 2: serve it -------------------------------------------------------
FROM nginxinc/nginx-unprivileged:1.27-alpine AS runtime

LABEL org.opencontainers.image.title="CloudGuard Internal Developer Portal" \
      org.opencontainers.image.description="Static internal docs, API specs and service catalog" \
      org.opencontainers.image.licenses="MIT"

USER root

# The stock server block would answer on 80 as a different site; replace it.
RUN rm -f /etc/nginx/conf.d/default.conf

COPY docker/nginx/default.conf /etc/nginx/conf.d/default.conf
COPY --from=builder --chown=101:101 /site /usr/share/nginx/html

# nginx-unprivileged already runs as 101; be explicit so the USER is auditable.
USER 101

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/healthz >/dev/null || exit 1

# SIGQUIT is a graceful shutdown for nginx; SIGTERM would still work.
STOPSIGNAL SIGQUIT

CMD ["nginx", "-g", "daemon off;"]
