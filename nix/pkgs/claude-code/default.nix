{
  lib,
  stdenv,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
}:

let
  # Run `nix/pkgs/claude-code/update.sh` to get a new version + hash
  version = "2.1.77";
  gcs = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases";
in
stdenvNoCC.mkDerivation {
  pname = "claude-code";
  inherit version;

  src = fetchurl {
    url = "${gcs}/${version}/linux-x64/claude";
    hash = "sha256-NFWcnMnurclC1nMTZ67TkVtrc1HZjGHr/rvY+llQjs0=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];

  # The binary dynamically links against glibc and libstdc++
  buildInputs = [ stdenv.cc.cc.lib ];

  dontUnpack = true;
  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    install -Dm755 $src $out/bin/claude
  '';

  # Disable the built-in auto-updater — Nix manages versions
  postInstall = ''
    wrapProgram $out/bin/claude \
      --set DISABLE_AUTOUPDATER 1
  '';

  meta = with lib; {
    description = "Agentic coding tool from Anthropic";
    homepage = "https://github.com/anthropics/claude-code";
    license = licenses.unfree;
    mainProgram = "claude";
    platforms = [ "x86_64-linux" ];
  };
}
