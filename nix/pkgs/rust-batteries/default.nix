{
  rustPlatform,
  runCommand,
  writeShellApplication,
  cacert,
  toolchains,
}:

let
  vendor = rustPlatform.importCargoLock { lockFile = ./Cargo.lock; };

  manifest = runCommand "rust-batteries-manifest" { } ''
    mkdir -p $out/src
    cp ${./Cargo.toml} $out/Cargo.toml
    cp ${./Cargo.lock} $out/Cargo.lock
    echo 'fn main() {}' > $out/src/main.rs
  '';

  # Warms the normal ~/.cargo with the same crate set, so plain `cargo` resolves
  # them offline too. Cargo only offers transparent source redirection via
  # source replacement, which is exclusive; pre-fetching into the real registry
  # is additive instead, at the cost of being cache rather than closure. Both
  # read this one manifest, so the two paths cannot drift.
  warm = writeShellApplication {
    name = "cargo-warm";
    runtimeInputs = [ toolchains.rust ];
    text = ''
      # Cargo wants a writable tree and the store copy is not one.
      work=$(mktemp -d)
      trap 'rm -rf "$work"' EXIT
      cp -r ${manifest}/. "$work"/
      chmod -R u+w "$work"

      export SSL_CERT_FILE="''${SSL_CERT_FILE:-${cacert}/etc/ssl/certs/ca-bundle.crt}"
      echo "Fetching $(grep -c '^\[\[package\]\]' "$work/Cargo.lock") packages into ''${CARGO_HOME:-$HOME/.cargo} ..."
      cd "$work" && cargo fetch --locked
      echo "Done. Plain 'cargo build --offline' can now use them."
    '';
  };
in

# The Cargo config that points at the vendored crates, with the vendor
# directory kept in its closure. Source replacement is the only way to
# redirect crates.io and it is all-or-nothing - a crate outside the vendor
# directory stops resolving even with a working connection - so this must
# never land in ~/.cargo. It is a separate CARGO_HOME, selected per
# invocation, which leaves the normal one pointed at crates.io.
runCommand "cargo-offline-config.toml"
  {
    passthru = { inherit vendor manifest warm; };
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
