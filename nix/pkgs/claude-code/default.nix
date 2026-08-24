{
  lib,
  stdenv,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
}:

let
  # Run `nix/pkgs/claude-code/update.sh` to get a new version + hashes
  version = "2.1.211";
  gcs = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases";

  srcs = {
    "x86_64-linux" = {
      urlPlatform = "linux-x64";
      hash = "sha256-gnLIpHSsnqG8NfGbn3x+fcTcTrbVrT5ISxkzWsckRrI=";
    };
    "aarch64-darwin" = {
      urlPlatform = "darwin-arm64";
      hash = "sha256-WnKKdhmLbsp/PHzb/0O6tEt3tIwhCPejEH2Il3M4Jik=";
    };
    "x86_64-darwin" = {
      urlPlatform = "darwin-x64";
      hash = "sha256-MwSesUz0cCuZK37aQewHf8bnZTn3/QRubTJTh1cjXaQ=";
    };
  };

  platformSrc =
    srcs.${stdenv.hostPlatform.system}
      or (throw "claude-code: unsupported system ${stdenv.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  pname = "claude-code";
  inherit version;

  src = fetchurl {
    url = "${gcs}/${version}/${platformSrc.urlPlatform}/claude";
    hash = platformSrc.hash;
  };

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ] ++ [
    makeWrapper
  ];

  # The Linux binary dynamically links against glibc and libstdc++
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ stdenv.cc.cc.lib ];

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
    platforms = builtins.attrNames srcs;
  };
}
