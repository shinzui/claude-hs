# Bundle Update Log

## 2026-11-20

* **Update**: FRIC-1 resolved: Upgraded claude-hs to 0.40.1 and removed the local exclusion. Treefmt changed zero files and the Seihou update preview was a no-op.


* **Update**: FRIC-2 accepted: The complete Shikigami suite passes with serial fixture scheduling.


* **Addition**: FRIC-2 records detour environment friction with mori://shinzui/shikigami/packages/shikigami-core: Concurrent Shikigami fixture deadlines expire during the consumer trial


* **Update**: FRIC-1 accepted: Verified the exclusion and repeated the Seihou preview.


* **Addition**: FRIC-1 records detour tooling friction with mori://shinzui/seihou-modules/templates/nix-haskell-flake: The generated Haskell flake conflicts after its own formatter runs

* **Adoption**: Adopt the `friction-log` profile (`coordination.frictionLog`) from https://raw.githubusercontent.com/shinzui/okf-profiles/v0.23.0/package.dhall.
