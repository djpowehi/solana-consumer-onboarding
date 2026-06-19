---
name: solana-consumer-onboarding
description: Build Solana apps for people who don't know they're using Solana. Email/social login (embedded wallets), gasless transactions via a sponsor relay, safe sponsorship (per-instruction allowlists + drain prevention), one-tap account creation, transaction bundling, and production operations. Extracted from a live Solana mainnet consumer app. For protocol/program development, delegates to solana-dev-skill.
user-invocable: true
license: MIT
metadata:
  author: djpowehi
  version: "1.0.0"
tags:
  - consumer-onboarding
  - gasless
  - sponsor-relay
  - fee-payer
  - embedded-wallets
  - privy
  - account-abstraction
  - transaction-bundling
  - relay-security
  - solana-kit
  - web3js
---

# Solana Consumer Onboarding

> **The thesis:** Existing gasless solutions teach developers how to sponsor transactions. This skill teaches AI agents how to sponsor them **safely** — without accidentally shipping a treasury-draining machine.
>
> **Protocol gasless ≠ application gasless.** Most gasless tooling teaches you to use a *protocol's* sponsored transactions (Jupiter `/order`, DFlow). Almost none teaches you to build your *own* application-level sponsorship — and **a naive sponsor relay is a treasury drainer**. That gap is the entire point of this skill.
>
> **Extends**: solana-dev-skill (core programs/frontend/testing). For Phantom/external-wallet connection, defer to the ecosystem `phantom-connect` skill — this skill owns the *embedded-wallet + gasless + sponsorship* path.

## What this skill is for

Use it when the user is building an app for **mainstream users who don't have a wallet and don't have SOL** — and you need to make the chain invisible. Concretely, when the user says any of:

- "users sign up with email / Google, no seed phrase"
- "users have no SOL — I need gasless / sponsored transactions"
- "one-tap signup, create the account on first action"
- "how do I sponsor transactions **without getting drained**"
- "how do I onboard non-crypto users to my Solana app"

If the user is building for existing crypto users with Phantom/Solflare, that's the wallet-adapter / `phantom-connect` path — say so and route there. This skill is for the *no-wallet, no-SOL* audience.

## Quick route (by what the user says)

| User says… | Load |
|---|---|
| "sign up with email / Google", "no seed phrase" | `embedded-wallets.md` |
| "users don't have SOL", "gasless", "I'll pay their fees" | `sponsor-relays.md` → then **`relay-security.md`** |
| "my relay got drained", "is sponsoring safe?", "how do I not get drained" | `relay-security.md` |
| "one-tap signup", "create the account on first action" | `transaction-bundling.md` |
| "I'm launching to production", "rate limits", "key handling" | `production-checklist.md` |
| "how do I onboard non-crypto users" (start here) | `onboarding-architecture.md` |

## Decision tree (the branching logic behind the table)

This is decision support, not a file index. Walk the branches:

```
User is onboarding users to a Solana app
│
├─ Do the users already have a Solana wallet (Phantom/Solflare)?
│   ├─ YES → not this skill's core. Use wallet-adapter / phantom-connect.
│   │        (You can still sponsor their gas — see sponsor-relays.md.)
│   └─ NO  → embedded-wallets.md   (email/social login, invisible signing)
│
├─ Will users have 0 SOL when they take their first action?  (almost always YES for normies)
│   ├─ YES → sponsor-relays.md     (fee-payer relay: app pays gas + rent)
│   │        └─ THEN ALWAYS → relay-security.md   (non-negotiable: see below)
│   └─ NO  → standard client signing (sendTransaction). No relay needed.
│
├─ Does the first action also need to CREATE accounts (PDAs/ATAs)?
│   ├─ YES → transaction-bundling.md   (one-tap: create + act in a single sponsored tx,
│   │                                    idempotent ATA pre-flight, lazy creation)
│   └─ NO  → single sponsored ix (sponsor-relays.md is enough)
│
└─ Going to production?
    └─ production-checklist.md   (rate limits, treasury caps, key handling, monitoring)
```

### The one hard rule

**If you build a sponsor relay, you MUST read and apply `relay-security.md` in the same breath.** A relay that signs transactions on a user's behalf, without per-instruction validation, is a wallet-drainer template. Never sponsor an arbitrary transaction. The security model is not an add-on — it is the feature.

## Opinionated defaults (2026 stack)

1. **Embedded wallets:** Privy (`@privy-io/react-auth/solana`) for email/Google login. Configure `showWalletUIs: false` so the chain stays invisible — no "wallet popup" jargon for non-crypto users. Power users can still attach Phantom/Solflare alongside.
2. **Transactions:** Solana Kit (`@solana/kit`, web3.js v2/3.0) for new code — it's the current stack and what the rest of the AI Kit targets. Classic `@solana/web3.js` 1.x patterns are provided as a migration appendix; the reference implementation in this skill was shipped on 1.x and battle-tested on mainnet, then translated forward.
3. **Relay:** a thin server endpoint (Next.js route handler / Express / any runtime) that holds the sponsor keypair, **validates every instruction against an allowlist**, co-signs as fee payer only, and broadcasts. Broadcast-only — let the client confirm (serverless functions time out before finalization).
4. **Account creation:** idempotent ATA instructions (`createAssociatedTokenAccountIdempotentInstruction`); lazy account creation bundled into the user's first real action, so you never pay rent for users who never convert.

## Files in this skill

| File | Load when |
|------|-----------|
| [onboarding-architecture.md](onboarding-architecture.md) | Deciding the overall flow: embedded vs external, when to sponsor, one-tap setup |
| [embedded-wallets.md](embedded-wallets.md) | Email/social login, invisible signing, Privy integration |
| [sponsor-relays.md](sponsor-relays.md) | Building the fee-payer relay (client builds + partial-signs, server co-signs + broadcasts) |
| [relay-security.md](relay-security.md) | **Always, when sponsoring.** Threat models + dangerous/safe pattern pairs |
| [transaction-bundling.md](transaction-bundling.md) | One-tap create+act, idempotent ATAs, lazy account creation |
| [production-checklist.md](production-checklist.md) | Rate limits, treasury caps, sponsor key handling, monitoring |

## Why this is hard (and why agents get it wrong)

The naive sponsor relay an agent will generate by default looks like:

```ts
const tx = Transaction.from(base64);
tx.partialSign(sponsorKeypair);   // ← DANGER: signs ANYTHING
return await connection.sendRawTransaction(tx.serialize());
```

That endpoint will co-sign *any* transaction a client sends — including one that lists the sponsor as the authority on a token transfer, draining the treasury. The whole point of this skill is to replace that reflex with a validated relay. See `relay-security.md`.
