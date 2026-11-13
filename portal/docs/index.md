# CloudGuard Internal Developer Portal

The single place where engineering finds **what exists, who owns it, and how to
operate it**. Three things live here:

<div class="grid cards" markdown>

-   :material-format-list-bulleted:{ .lg .middle } **Service catalog**

    ---

    Every internal service with its owner, tier, SLO and on-call rotation.

    [:octicons-arrow-right-24: Browse services](services/index.md)

-   :material-api:{ .lg .middle } **API specifications**

    ---

    Contract-first specs, authentication model and versioning policy.

    [:octicons-arrow-right-24: Read the specs](api/index.md)

-   :material-book-open-variant:{ .lg .middle } **Runbooks**

    ---

    Step-by-step recovery procedures, written to be followed at 03:00.

    [:octicons-arrow-right-24: Open runbooks](runbooks/index.md)

</div>

## What this portal is not

It is not a wiki and not a place for meeting notes. If a page cannot be acted
on — a service to page, an endpoint to call, a procedure to run — it belongs
somewhere else. That rule is the reason the catalog stays trustworthy.

## How it is built

| Layer | Choice | Why |
| --- | --- | --- |
| Content | Markdown in `portal/docs/` | Reviewable in a pull request, diffable, no database |
| Renderer | MkDocs Material, static HTML | No runtime, no server-side attack surface |
| Server | Nginx unprivileged, uid 101, port 8080 | Drops every capability, read-only root filesystem |
| Hosting | One small container (OCI Always Free A1.Flex) | Fits in 64 MiB; no managed service needed |

The site is rendered at image build time with `--strict`, so a broken internal
link or a page missing from the nav fails the build instead of reaching a reader.

## Where to start

- New to the team? Read [Contributing](contributing.md), then the service you
  will be on call for.
- Looking for an endpoint? Start at [API specifications](api/index.md).
- Something is broken? Go straight to [Runbooks](runbooks/index.md).

!!! warning "Internal only"
    This portal is served on the internal network behind the platform proxy. It
    is not reachable from the public internet, and nothing here should be
    indexed by a search engine.
