# API specifications

Contract-first: the spec is the source of truth, the implementation follows it.

## Common conventions

| Concern | Rule |
| --- | --- |
| Base path | `/v1/<service>` — a breaking change is a new version, never a patch |
| Auth | `Authorization: Bearer <token>`; service-to-service uses mTLS at the proxy |
| Content type | `application/json; charset=utf-8` |
| Errors | RFC 9457 problem details (`type`, `title`, `status`, `detail`) |
| Pagination | `?limit=` (max 100) and `?cursor=`; never offset for large sets |
| Idempotency | Mutating `POST` accepts `Idempotency-Key`, honoured for 24 h |
| Tracing | `traceparent` propagated (W3C Trace Context) |

## `identity-gateway` v1

=== "Endpoints"

    | Method | Path | Purpose |
    | --- | --- | --- |
    | `GET` | `/v1/identity/users/{id}` | Fetch a user profile |
    | `POST` | `/v1/identity/tokens/introspect` | Validate a token and return its claims |
    | `POST` | `/v1/identity/keys/rotate` | Start a signing-key rotation |

=== "Introspect example"

    ```json
    {
      "active": true,
      "sub": "user_8f21c",
      "scope": ["profile:read", "billing:read"],
      "exp": 1798761600,
      "iat": 1798758000,
      "iss": "https://identity.internal.example.com"
    }
    ```

=== "Error shape"

    ```json
    {
      "type": "https://errors.internal.example.com/token-expired",
      "title": "Token expired",
      "status": 401,
      "detail": "The presented token expired 42 seconds ago."
    }
    ```

## `billing-api` v1

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/v1/billing/invoices/{id}` | Fetch an invoice |
| `POST` | `/v1/billing/invoices/{id}/replay` | Re-emit a webhook for one invoice |
| `GET` | `/v1/billing/plans` | List available plans |

## Versioning and deprecation

1. Additive changes ship inside the current version.
2. A breaking change is a new path version and a new page here.
3. Old versions get a `Deprecation` and `Sunset` response header for at least
   one quarter before removal — a date, not "soon".

!!! tip "OpenAPI files"
    Machine-readable specs live next to each service repository as
    `openapi.yaml`. This page is the human-readable summary; if they disagree,
    the `openapi.yaml` wins and this page gets fixed in the same pull request.
