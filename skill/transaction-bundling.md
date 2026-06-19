# Transaction Bundling — one tap, account creation included

> Load this when the user's first action also needs accounts created (PDAs/ATAs) and you want it to happen in a single tap, with the sponsor paying rent — without paying for users who never convert.

## Three patterns

### 1. Idempotent ATA pre-flight

Never assume a token account exists; never fail if it does. Prepend an **idempotent** ATA-create — it's a no-op if the account already exists, and the sponsor pays the rent if it doesn't.

```ts
const ataIx = createAssociatedTokenAccountIdempotentInstruction(
  sponsor,          // payer (rent) — the relay covers it
  ata,              // derived address
  owner,            // the USER owns the ATA, never the sponsor
  mint,
);
```

The `owner` is always the user. If you ever put the sponsor as the owner, you've created an account the user can't use and the app can't recover — and on a value-moving leg, a drain (see `relay-security.md`, Threats 3–4).

### 2. Bundle create + act in one sponsored transaction

If the first action needs a fresh account, put the create instruction and the action instruction in the **same** transaction so the user taps once:

```ts
const tx = new Transaction().add(createIx, actionIx);   // e.g. [create_account, deposit]
tx.feePayer = sponsor;
// → sign as user → POST to relay → relay validates BOTH ixs → co-signs → broadcasts
```

The relay's allowlist must explicitly recognize this **bundle shape** (e.g. "exactly two of my program's instructions, in order [create, act]") and apply the per-instruction sponsor checks to each: sponsor allowed only at fee-payer; sponsor must not appear in the value-moving instruction at all. See the lazy-bundle handling in `relay-security.md`.

### 3. Lazy creation — don't pay until value flows

Do **not** create on-chain accounts at signup. Keep the "draft" entirely client-side (localStorage) until the user's first real, value-bearing action. Then create-and-act in one bundled, sponsored tx.

Why:
- A user who signs up and never converts costs the sponsor **$0** instead of the rent for accounts they'll never use.
- It collapses account-creation logic into one place (the action flow) instead of scattering it across signup + action.
- It blunts sponsored-creation spam (Threat 5): there's nothing to spam-create because creation only happens alongside a funded action.

## Two-layer funding (recoverability)

Route incoming funds to the **user's own wallet first**, then let the user explicitly move them into downstream accounts — rather than one-shotting external funds straight into a destination account. This gives recoverability (a mistaken top-up can be withdrawn without touching downstream state) and matches the "balance on top, actions below" model of every consumer fintech.

## Idempotency for server-initiated transfers

If a webhook (e.g. a fiat on-ramp) triggers a server-signed transfer, make it idempotent **on-chain**: embed a unique id in an SPL Memo (`cid:<id>`), and before processing, scan recent sponsor-wallet signatures for that memo. If present, it's a duplicate — skip. This survives webhook retries without a database.
