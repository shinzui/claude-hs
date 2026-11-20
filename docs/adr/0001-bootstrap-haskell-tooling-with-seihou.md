# Bootstrap Haskell tooling with Seihou

Accepted on 2026-11-20.

Use the Seihou module to generate the Nix flake, lockfile, development shell, formatter and hook configuration for the client. EP-1 owns its initial application. Local and CI builds run Cabal with the compiler from the locked flake. Start with GHC 9.12.4 to meet the project's GHC2024 baseline. The client tests use a loopback server, so the bootstrap disables process-compose and PostgreSQL. [Seihou template](mori://shinzui/seihou-modules/templates/nix-haskell-flake)

Track the generated files and Seihou application metadata together. Apply future template upgrades through Seihou. Put project-specific Nix extensions in the optional root `flake.module.nix`. The Cabal package, module layout and tests remain project-owned.
