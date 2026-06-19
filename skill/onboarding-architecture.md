# Onboarding Architecture — the decision flow

> Load this when deciding the *shape* of an onboarding flow before writing code. It turns "I want normie onboarding" into a concrete set of choices.

## The mental model: make the chain invisible

A non-crypto user should never see a seed phrase, a wallet popup, the word "gas," or an empty-balance error. Everything below exists to hide those four things. The user signs in like any web app, taps one button, and something happens on Solana — they never know.

Three layers, each answering one question:

1. **Identity** — who is this user, without a wallet? → *embedded wallets* (email/Google login auto-creates a keypair).
2. **Funding** — they have 0 SOL; who pays? → *sponsor relay* (your app's hot wallet pays gas + rent).
3. **Orchestration** — their first action also needs accounts created; how, in one tap? → *transaction bundling* + *lazy creation*.

## Decision flow

### 1. Embedded vs external wallet

- **Building for mainstream users (no wallet):** embedded wallets (Privy). Email/Google login, invisible signing. → `embedded-wallets.md`
- **Building for existing crypto users (have Phantom/Solflare):** that's the wallet-adapter / `phantom-connect` path — not this skill's core. You may *still* sponsor their gas if you want a zero-friction experience.
- **Both audiences:** offer embedded as the default and let power users attach Phantom alongside. Route signing to whichever wallet is active.

### 2. Sponsor or not?

- Will the user have **0 SOL** at their first action? For normies onboarded via email, **yes, always.** They cannot pay the fee *or* the rent to create their accounts. → you must sponsor. `sponsor-relays.md` + (mandatory) `relay-security.md`.
- Building a flow where users arrive already funded (e.g. they bought SOL/USDC first)? Then standard client-side `sendTransaction` is fine; skip the relay.

### 3. One-tap setup or multi-step?

- If the first action **also needs to create accounts** (a PDA, an ATA), bundle the create + the action into a **single sponsored transaction** so the user taps once. → `transaction-bundling.md`
- Use **lazy creation**: don't create (and pay rent for) on-chain accounts at signup. Wait until the user's first real, value-bearing action, then create-and-act in one tx. A user who signs up and never converts costs the sponsor nothing. (This also blunts sponsored-creation spam — see Threat 5 in `relay-security.md`.)

### 4. The end-to-end flow (normie path)

```
1. User logs in with email/Google         → Privy creates an embedded wallet (no seed phrase)
2. User taps "do the thing"                → client builds the tx, fee_payer = sponsor wallet
3. Client signs as the user                → Privy invisible signing, no popup
4. Client POSTs the partial-signed tx      → to your relay endpoint
5. Relay VALIDATES every instruction       → allowlist + per-instruction sponsor checks (relay-security.md)
6. Relay co-signs as fee payer, broadcasts → returns the signature
7. Client confirms                         → (relay broadcasts only; serverless times out before finalization)
```

The two-step funding model (top-up → wallet → action) vs one-shot is a deliberate choice: routing funds to the user's own wallet first gives **recoverability** (a mistaken top-up can be withdrawn without ever touching downstream accounts) and matches the mental model of every consumer fintech (balance on top, actions below). See `transaction-bundling.md` for where lazy creation fits.

## What to hand to the other modules

Once you've made the calls above:
- identity → `embedded-wallets.md`
- funding → `sponsor-relays.md`, then **always** `relay-security.md`
- orchestration → `transaction-bundling.md`
- shipping → `production-checklist.md`
