#!/usr/bin/env bash
set -euo pipefail

mode=${1:-}
case "$mode" in
  baseline | migrated) ;;
  *) printf 'Usage: %s baseline|migrated\n' "$0" >&2; exit 2 ;;
esac

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
candidate=$(cd "$here/../.." && pwd)
trial=$(mktemp -d "${TMPDIR:-/tmp}/claude-hs-parity.XXXXXX")
printf 'Trial workspace %s\n' "$trial" >&2

checkout() {
  local name=$1 uri=$2 revision=$3 source
  source=$(mori path "$uri" | tail -n 1)
  git clone --quiet --shared --no-checkout "$source" "$trial/$name"
  git -C "$trial/$name" checkout --quiet --detach "$revision"
}

checkout baikai mori://shinzui/baikai/repos/baikai 87481ea7ff867a37bf602b0dc1ac8caa9e2e2710
checkout shikumi mori://shinzui/shikumi/repos/shikumi 4fec9169d97a85f5e0e38246347f6c70ef555d7e
checkout shikigami mori://shinzui/shikigami/repos/shikigami d9d18d23b456f25a6b507a60514bcd90e796392b
git -C "$trial/shikumi" apply "$here/shikumi.patch"
git -C "$trial/shikigami" apply "$here/shikigami.patch"
git -C "$trial/shikigami" apply "$here/shikigami-parity-pins.patch"

case "$mode" in
  baseline)
    git -C "$trial/baikai" apply "$here/baikai.patch" "$here/baikai-parity-projections.patch"
    ;;
  migrated)
    git -C "$trial/baikai" apply "$here/baikai-migration.patch"
    git -C "$trial/shikigami" apply "$here/shikigami-remove-mercury.patch"
    ;;
esac

printf 'packages: "%s"\n' "$candidate" > "$trial/baikai/cabal.project.local"
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
