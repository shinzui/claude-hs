{ ... }:
{
  perSystem = { ... }: {
    # Preserve this Seihou template byte for byte so upgrades can merge it.
    treefmt.settings.global.excludes = [ "nix/haskell.nix" ];
  };
}
