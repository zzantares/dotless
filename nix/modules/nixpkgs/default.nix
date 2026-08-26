# Single source of truth for injecting the dotless overlay into nixpkgs.
#
# Both `modules/nix` and the NixOS/darwin base presets import THIS module
# instead of each setting `nixpkgs.overlays` themselves. The module system
# deduplicates modules by key, so however many import paths reach the overlay
# — a desktop NixOS config reaches it through both `modules/nix` and a base
# preset — it is contributed exactly once and the overlay is applied a single
# time.
#
# This matters because the overlay is not idempotent under repeated
# application: overrideAttrs that append to `postPatch` (diffnav, opencode)
# would re-run their substitutions and abort. Funnelling every entry point
# through one deduplicated module removes the double application at the source.
{ inputs, ... }:

{
  nixpkgs.overlays = [
    # inputs.dotless refers to the dotless flake input — the README establishes
    # "dotless" as the conventional name: `inputs.dotless.url = "..."`.
    inputs.dotless.overlays.default
  ];
}
