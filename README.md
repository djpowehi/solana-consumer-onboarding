# solana-consumer-onboarding

**An AI skill for building Solana apps for people who don't know they're using Solana.**

> Existing gasless solutions teach developers how to *sponsor transactions*.
> This skill teaches AI agents how to sponsor them **safely** — without accidentally shipping a treasury-draining machine.

## The problem it solves

Every consumer app chasing mainstream users hits the same wall on day one:

- users **don't have a wallet** (and won't write down a seed phrase)
- users **don't have SOL** (so they can't pay gas or rent — they can't do *anything*)
- users **churn during onboarding** the moment they see crypto jargon
- and the obvious fix — sponsoring their transactions — is **dangerous**: a naive relay that signs whatever a client sends is a wallet-drainer with a public endpoint.

The ecosystem has plenty of *protocol-level* gasless (Jupiter `/order`, DFlow sponsorship). It has almost nothing on the **application-level** problem: *"I'm building a regular Solana app — how do I onboard normies and sponsor their transactions without getting drained?"* Those are different problems. This skill owns the second one.

## Why this skill is credible

It was **extracted from a live Solana mainnet consumer app** — a real product onboarding non-crypto users via email login, with a hot-wallet sponsor relay paying gas and rent, secured by a per-instruction allowlist that rejects any transaction trying to use the sponsor as a value-moving authority. The security model in [`skill/relay-security.md`](skill/relay-security.md) is not theoretical; it's the validator that guards a real treasury.

## What's inside

A progressively-loaded skill following the Solana AI Kit shape: a routing [`SKILL.md`](skill/SKILL.md) entry point with an opinionated decision tree, plus focused modules loaded only when needed.

| Module | What it covers |
|--------|----------------|
| `onboarding-architecture.md` | The mental model + decision flow: embedded vs external wallets, when to sponsor, one-tap setup |
| `embedded-wallets.md` | Email/Google login, invisible signing (Privy), keeping the chain invisible |
| `sponsor-relays.md` | The fee-payer relay: client builds + partial-signs, server validates + co-signs + broadcasts |
| **`relay-security.md`** | **The moat.** Threat models (auditor-style) + dangerous→safe pattern pairs + a reference validator |
| `transaction-bundling.md` | One-tap create+act, idempotent ATAs, lazy account creation |
| `production-checklist.md` | Rate limits, treasury caps, sponsor-key handling, monitoring |

## Decision support, not docs

The skill routes by *what the user is trying to do*, not by keyword — see the decision tree in `SKILL.md`. It teaches the agent to **make the right call** (embedded vs external, sponsor vs not, bundle vs single) and, when sponsoring, forces it through the security model. The default reflex it replaces:

```ts
tx.partialSign(sponsor);                       // ❌ signs anything
await connection.sendRawTransaction(tx.serialize());
```

with a validated relay that denies by default.

## Stack

- **Embedded wallets:** Privy (email/Google), `showWalletUIs: false` for an invisible-chain UX.
- **Transactions:** Solana Kit (`@solana/kit`, web3.js v2/3.0) primary; classic `@solana/web3.js` 1.x as a migration appendix (the reference implementation shipped on 1.x and was battle-tested on mainnet).
- **Runtime-agnostic relay:** the relay endpoint is a thin handler — Next.js route, Express, or any server.

## Install

```bash
# As a submodule of the Solana AI Kit (matches the kit's ext/ layout):
git submodule add https://github.com/djpowehi/solana-consumer-onboarding .claude/skills/ext/consumer-onboarding

# Or standalone into a project's skills dir:
./install.sh
```

## License

MIT — see [LICENSE](LICENSE). Built for the Solana AI Kit by Vicenzo Tulio.
