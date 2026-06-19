# Embedded Wallets — identity without a seed phrase

> Load this for the email/social-login path: give a non-crypto user a Solana wallet they never have to think about. For existing-wallet users (Phantom/Solflare), use the wallet-adapter / `phantom-connect` path instead.
>
> Stack note: Privy examples below target `@privy-io/react-auth`. Kit/v2 signer wiring: verified-docs pass pending.

## Goal

The user logs in with email or Google and gets a Solana keypair created and custodied for them — no seed phrase, no extension, no popup. Signing is invisible: the app calls `signTransaction` and the user sees nothing crypto-flavored.

## Privy setup (invisible chain)

```tsx
<PrivyProvider
  appId={PRIVY_APP_ID}
  config={{
    loginMethods: ["email", "google"],
    embeddedWallets: { solana: { createOnLogin: "users-without-wallets" } },
    // Keep the chain invisible: no wallet popups/jargon for non-crypto users.
    // The transaction-confirm modal stays out of the way; signing is programmatic.
    appearance: { showWalletUIs: false },
    solana: { rpcs: { "solana:mainnet": { rpc: MAINNET_RPC } } },
  }}
>
  {children}
</PrivyProvider>
```

## The wallet shape your code should depend on

Don't couple your transaction code to a specific provider. Depend on a minimal interface so embedded and external wallets are interchangeable:

```ts
// Sign-only (sponsored/relay path): the server broadcasts, the wallet never needs to.
type SigningWallet = {
  publicKey: PublicKey | null;
  signTransaction: <T>(tx: T) => Promise<T>;
};

// Send-capable (self-funded path): wallet signs AND broadcasts.
type SendingWallet = {
  publicKey: PublicKey | null;
  sendTransaction: (tx, connection) => Promise<string>;
};
```

For the sponsored path you only need `SigningWallet` — Privy fills the user's signature slot, the relay adds the sponsor's. A thin `useWallet()` compatibility shim lets the same call sites work whether the active wallet is Privy-embedded or an attached Phantom.

## Supporting both audiences

Offer embedded as the default; let power users attach Phantom/Solflare alongside. Route signing to whichever wallet is active. This keeps the normie path frictionless without locking out crypto-native users.

## Pairs with

- **No SOL?** Embedded-wallet users have 0 SOL by definition → `sponsor-relays.md` + `relay-security.md`.
- **First action needs accounts?** → `transaction-bundling.md`.
