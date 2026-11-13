# Service catalog

One row per service. A service without an owner is not a service, it is an
incident waiting for a name.

| Service | Tier | Owner | SLO | On-call | Runbook |
| --- | --- | --- | --- | --- | --- |
| `identity-gateway` | 1 | Platform Identity | 99.95 % monthly | `#oncall-identity` | [Rotate signing keys](../runbooks/index.md#rotate-signing-keys) |
| `billing-api` | 1 | Payments | 99.9 % monthly | `#oncall-payments` | [Replay failed invoices](../runbooks/index.md#replay-failed-invoices) |
| `search-indexer` | 2 | Discovery | 99.5 % monthly | `#oncall-discovery` | [Rebuild an index](../runbooks/index.md#rebuild-an-index) |
| `notification-fanout` | 2 | Platform Messaging | 99.5 % monthly | `#oncall-messaging` | [Drain a stuck queue](../runbooks/index.md#drain-a-stuck-queue) |
| `audit-log-sink` | 3 | Security Engineering | 99.0 % monthly | `#oncall-security` | [Verify log continuity](../runbooks/index.md#verify-log-continuity) |

## Tier definitions

| Tier | Meaning | Page a human? |
| --- | --- | --- |
| 1 | Customer-facing and revenue-affecting | Yes, 24/7 |
| 2 | Degrades a customer workflow but has a fallback | Business hours, escalates if > 30 min |
| 3 | Internal only, delayable | Next business day |

## Adding a service

1. Create the entry in this table — tier, owner, SLO, on-call channel.
2. Add a runbook **before** the service takes production traffic.
3. Publish its contract under [API specifications](../api/index.md).

!!! note "Fields are not optional"
    `Owner` and `On-call` must resolve to a real team and channel. A catalog row
    nobody answers is worse than no row at all, because it looks covered.
