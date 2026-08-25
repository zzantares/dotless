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
  version = "2.1.245";
  baseUrl = "https://downloads.claude.ai/claude-code-releases";

  srcs = {
    "x86_64-linux" = {
      urlPlatform = "linux-x64";
      hash = "sha256-Fq0rlN6veymr7ZZtmByZkaR68EIPW+jtSj+Dvqn2eLw=";
    };
    "aarch64-darwin" = {
      urlPlatform = "darwin-arm64";
      hash = "sha256-n3wiYCUXZaGNCzUZhmnazBkS9ugSmjsB9rWNkzZf8fE=";
    };
    "x86_64-darwin" = {
      urlPlatform = "darwin-x64";
      hash = "sha256-3gRLtUPoJjUvMVh6dDVuGy2ulNwbnJYKNi2fB9+Wwqc=";
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
    url = "${baseUrl}/${version}/${platformSrc.urlPlatform}/claude";
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
