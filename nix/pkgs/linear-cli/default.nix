{
  lib,
  stdenv,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
}:

let
  version = "1.11.1";
  base = "https://github.com/schpet/linear-cli/releases/download/v${version}";

  srcs = {
    "x86_64-linux" = {
      urlSuffix = "x86_64-unknown-linux-gnu";
      hash = "sha256-S7zwxOYXwYmK+zcyuhuvVW8JhXPI5hgaWiyEz7T0gII=";
    };
    "aarch64-darwin" = {
      urlSuffix = "aarch64-apple-darwin";
      hash = "sha256-v906DXJ3YgGLX9wnQ6yZN/1wiws99wxz2tas1idEdpQ=";
    };
  };

  platformSrc = srcs.${stdenvNoCC.hostPlatform.system} or (throw "linear-cli: unsupported system ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  pname = "linear-cli";
  inherit version;

  src = fetchurl {
    url = "${base}/linear-${platformSrc.urlSuffix}.tar.xz";
    hash = platformSrc.hash;
  };

  nativeBuildInputs = lib.optionals stdenvNoCC.hostPlatform.isLinux [ autoPatchelfHook ];

  buildInputs = lib.optionals stdenvNoCC.hostPlatform.isLinux [ stdenv.cc.cc.lib ];

  installPhase = ''
    install -Dm755 linear $out/bin/linear
  '';

  meta = with lib; {
    description = "linear without leaving the command line: list, start, and create PRs for linear issues";
    homepage = "https://github.com/schpet/linear-cli";
    license = licenses.mit;
    mainProgram = "linear";
    platforms = builtins.attrNames srcs;
  };
}
