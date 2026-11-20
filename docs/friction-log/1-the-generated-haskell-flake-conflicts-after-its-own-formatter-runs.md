---
type: Friction Entry
title: "The generated Haskell flake conflicts after its own formatter runs"
description: "The generated pre-commit formatter rewrites the Seihou-owned nix/haskell.nix, which makes a repeat application report a conflict."
generated:
  by: "codex-cli/gpt-6.2-sol"
  at: "2026-11-20T20:55:43Z"
frictionId: FRIC-1
status: "accepted"
impact: detour
kind: tooling
origin: "mori://shinzui/claude-hs"
affects: "mori://shinzui/seihou-modules/templates/nix-haskell-flake"
affectedVersion: "0.40.0"
plan: "docs/plans/1-send-messages-and-count-input-tokens.md"
workaround: "Keep the generated file byte-identical to the baseline and exclude that path from the Nix formatter in flake.module.nix."
resolution: "Keep the generated template at its Seihou baseline with a single formatter exclusion in the project-owned flake module."
amended:
  - by: "codex-cli/gpt-6.2-sol"
    at: "2026-11-20T20:56:45Z"
    change: "Verified the exclusion and repeated the Seihou preview."
---
# The generated Haskell flake conflicts after its own formatter runs

## Attempted

Apply the nix-haskell-flake module, commit the generated files, and repeat the same seihou run with --dry-run.

## Encountered

The treefmt hook reformatted nix/haskell.nix. Seihou then reported a conflict on that generated file.

## Workaround

Keep the generated file byte-identical to the baseline and exclude that path from the Nix formatter in flake.module.nix.
