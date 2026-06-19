# Production Checklist — operating a sponsor relay safely

> Load this before shipping. The relay holds real funds and faces the public internet; these are the operational controls that keep it from being drained or exhausted.

## Sponsor key handling

- [ ] Sponsor secret key lives in a **server-only** env secret — never in a client bundle, never in `NEXT_PUBLIC_*`.
- [ ] Enforce server-only at build time (`import "server-only"` in Next.js, or equivalent module boundary).
- [ ] Never log the secret, and never derive a string from it that could leak in an error message.
- [ ] Cache the decoded keypair across requests (decode once per deployment), but never persist it to disk.
- [ ] Plan rotation: the relay should read the key from config so you can rotate without a code change.

## Treasury limits (anti-exhaustion)

- [ ] **Balance cap with alerting:** keep only a bounded amount in the sponsor wallet so a worst-case drain/exhaustion is capped. Monitor the balance; alert (and optionally pause the relay) below a threshold.
- [ ] **Refill discipline:** top up from a separate funding wallet, not by parking the whole treasury in the hot wallet.
- [ ] Know your blast radius: at current rent + fee per onboard, how many sponsored actions does the balance cover? Put that number in your runbook.

## Rate limiting & abuse

- [ ] Per-identity / per-IP rate limits on the relay endpoint.
- [ ] Per-user quotas (e.g. N sponsored actions per day) — sponsorship is a cost center, treat it like one.
- [ ] **Lazy creation** so signups that never convert cost nothing (see `transaction-bundling.md`).
- [ ] Bot/abuse monitoring on the relay route; sudden spikes in valid-but-throwaway requests are Threat 5.

## Correctness in production

- [ ] **Broadcast-only; client confirms.** Do not `confirmTransaction` server-side — finalization can exceed the serverless timeout and return an empty body. Return the signature, let the client poll.
- [ ] Set the serverless function timeout (`maxDuration`) above preflight-simulation time.
- [ ] Wrap the handler in try/catch that always returns JSON (never an empty 500 body).
- [ ] Client reads the response as text before `JSON.parse`, so timeouts/HTML errors surface a real message.
- [ ] Idempotency for webhook-triggered transfers: on-chain memo (`cid:<id>`) + signature scan (see `transaction-bundling.md`).

## Security sign-off (from relay-security.md)

- [ ] Deny-by-default allowlist: every program + every instruction explicitly allowed.
- [ ] Sponsor rejected in every slot except fee-payer (and ATA-create payer slot 0).
- [ ] Value-moving instructions excluded from the allowlist (or sponsor asserted absent).
- [ ] `feePayer === sponsor` checked, and not the only check.
- [ ] User signature verified present before the relay signs.

## RPC

- [ ] Use a paid/keyed RPC for the relay's broadcast path; free tiers rate-limit under load.
- [ ] The RPC key used server-side is a server secret; the client-side RPC key (if any) is separate and origin-locked.
