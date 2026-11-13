# Runbooks

Written to be followed at 03:00 by someone who did not build the system. Every
runbook states how to tell it worked, and how to stop if it does not.

## Rotate signing keys

**Service:** `identity-gateway` · **Owner:** Platform Identity · **Risk:** high

1. Confirm the new key is published at `/.well-known/jwks.json` **before**
   rotating anything (`curl` and check `kid`).
2. Start the rotation: `POST /v1/identity/keys/rotate` with the new `kid`.
3. Watch login error rate for 10 minutes. Expected: zero change.
4. Retire the old key only after every verifier has refreshed its JWKS cache —
   normally 15 minutes, an hour in the worst case.

!!! danger "If login errors rise above 1 %"
    Re-publish the previous key as active. Old tokens remain valid until their
    `exp`, so rolling back is safe and does not log anyone out.

## Replay failed invoices

**Service:** `billing-api` · **Owner:** Payments · **Risk:** medium

1. Identify the window: `GET /v1/billing/invoices?status=failed&since=<ts>`.
2. Replay one invoice first and confirm the downstream consumer acknowledged it.
3. Replay the rest in batches of 50, pausing between batches.
4. Verify the count of `failed` invoices returned to its pre-incident baseline.

## Rebuild an index

**Service:** `search-indexer` · **Owner:** Discovery · **Risk:** medium

1. Note the current index name; the rebuild writes to a **new** index.
2. Trigger `search-indexer rebuild --from=<snapshot> --to=<new-index>`.
3. Compare document counts between old and new. They should match within the
   snapshot lag, not exactly.
4. Flip the read alias to the new index, keep the old one for 24 hours.

## Drain a stuck queue

**Service:** `notification-fanout` · **Owner:** Platform Messaging · **Risk:** low

1. Check depth and age of the oldest message. Age matters more than depth.
2. Look for a poison message: one message redelivered repeatedly with the same
   error is the usual cause.
3. Move poison messages to the dead-letter queue, then let the consumer drain.
4. Replay the dead-letter queue only after the fix is deployed, never before.

## Verify log continuity

**Service:** `audit-log-sink` · **Owner:** Security Engineering · **Risk:** low

1. Query the sink for the hourly marker records of the last 24 hours.
2. Gaps in the markers mean missing hours, even if individual events look
   plausible.
3. Record the gap window in the incident ticket — audit continuity is a
   compliance statement, not an operational nicety.
4. Restore from the bucket archive and re-ingest the missing window.
