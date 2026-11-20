---
okf_version: "0.2"
---

# Files

- [profile.dhall](profile.dhall)

# Friction Entry

- [The generated Haskell flake conflicts after its own formatter runs](1-the-generated-haskell-flake-conflicts-after-its-own-formatter-runs.md) - The generated pre-commit formatter rewrites the Seihou-owned nix/haskell.nix, which makes a repeat application report a conflict.
- [Concurrent Shikigami fixture deadlines expire during the consumer trial](2-concurrent-shikigami-fixture-deadlines-expire-during-the-consumer-trial.md) - The comprehensive runtime suite hit local HTTP fixture deadlines under concurrent execution, despite passing when Tasty scheduled one test at a time.
