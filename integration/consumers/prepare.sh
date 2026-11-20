#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
candidate=$(cd "$here/../.." && pwd)
trial=$(mktemp -d "${TMPDIR:-/tmp}/claude-hs-consumers.XXXXXX")
printf 'Trial workspace %s\n' "$trial" >&2

checkout() {
  local name=$1 uri=$2 revision=$3 source
  source=$(mori path "$uri" | tail -n 1)
  git clone --quiet --shared --no-checkout "$source" "$trial/$name"
  git -C "$trial/$name" checkout --quiet --detach "$revision"
  git -C "$trial/$name" apply "$here/$name.patch"
}

checkout baikai mori://shinzui/baikai/repos/baikai cdb79e5805613ab60074bb2c9279d779af610c05
checkout shikumi mori://shinzui/shikumi/repos/shikumi 4fec9169d97a85f5e0e38246347f6c70ef555d7e
checkout shikigami mori://shinzui/shikigami/repos/shikigami d9d18d23b456f25a6b507a60514bcd90e796392b

cat > "$trial/shikigami/cabal.project.local" <<PROJECT
packages:
  "../baikai/baikai"
  "../baikai/baikai-claude"
  "../baikai/baikai-openai"
  "../shikumi/shikumi"
  "$candidate"

package shikigami-core
  ghc-options: -j8
PROJECT

printf '%s\n' "$trial/shikigami"
