# SpaceLens Direct edition

The App Store and website editions share the storage-analysis engine but have separate commercial builds.

- `Release` keeps StoreKit subscriptions and the sandboxed App Store entitlement configuration.
- `Direct` defines `DIRECT_DISTRIBUTION`, uses bundle ID `com.lukemclaughlin.spacelens.direct`, compiles out StoreKit and subscription purchase UI, and permanently unlocks every feature.
- `scripts/build-direct.sh` produces a universal Developer ID-signed DMG, notarizes it with Apple, staples the ticket, checks Gatekeeper, and records its SHA-256 checksum.

Never publish a website installer unless every gate in the script passes.
