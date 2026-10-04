{
  rustPlatform,
  runCommand,
}:

let
  vendor = rustPlatform.importCargoLock { lockFile = ./Cargo.lock; };
in

# The Cargo config that points at the vendored crates, with the vendor
# directory kept in its closure. Source replacement is the only way to
# redirect crates.io and it is all-or-nothing - a crate outside the vendor
# directory stops resolving even with a working connection - so this must
# never land in ~/.cargo. It is a separate CARGO_HOME, selected per
# invocation, which leaves the normal one pointed at crates.io.
runCommand "cargo-offline-config.toml"
  {
    passthru = { inherit vendor; };
    meta.description = "Cargo config selecting a pinned set of crates vendored for offline use";
  }
  ''
    cat > $out <<EOF
    [source.crates-io]
    replace-with = "vendored-sources"

    [source.vendored-sources]
    directory = "${vendor}"

    [net]
    offline = true
    EOF
  ''
