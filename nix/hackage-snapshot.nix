# One pin for the all-cabal-hashes Hackage snapshot, shared by the Haskell
# package set in nix/overlays and by nix/pkgs/hackage-mirror. Bump it
# deliberately, never via `just flake-update`: the mirror's shard hashes
# derive from this rev, so a bump needs `just hackage-latest` re-run.
{
  rev = "62ad74598227903a0ab83d540cd19ec5029ab5f5";
  hash = "sha256-A2orekxJBNlBGYkD6SaN4WWLphOHdSs+1tMc7fBTH4I=";
}
