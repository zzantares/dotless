{
  runCommand,
  fetchFromGitHub,
}:

# jaidetree/doom-icon's `cute-doom` variant (`abject-doom` is the alternate):
# a hicolor drop so `Icon=doom` resolves on Linux, plus the icns the macOS
# bundle swaps in. Pinned to a master rev, not a tag - upstream tags rarely.
# https://github.com/jaidetree/doom-icon
let
  src = fetchFromGitHub {
    owner = "jaidetree";
    repo = "doom-icon";
    rev = "e90e93ff6c05615137a0a3694f4674ba83ff00ae";
    hash = "sha256-TLUzL37X41PBRK9oVtKjZDQ2Laf82OMA9KWzTjGKmyY=";
  };

  iconset = "${src}/cute-doom/src/doom.iconset";
in

runCommand "doom-icon" { } ''
  install -Dm444 ${src}/cute-doom/doom.icns $out/share/doom.icns
  install -Dm444 ${src}/cute-doom/doom.svg $out/share/icons/hicolor/scalable/apps/doom.svg

  # `@2x` names are the double-size renders: icon_32x32@2x.png is 64x64.
  install -Dm444 ${iconset}/icon_16x16.png $out/share/icons/hicolor/16x16/apps/doom.png
  install -Dm444 ${iconset}/icon_32x32.png $out/share/icons/hicolor/32x32/apps/doom.png
  install -Dm444 ${iconset}/icon_32x32@2x.png $out/share/icons/hicolor/64x64/apps/doom.png
  install -Dm444 ${iconset}/icon_128x128.png $out/share/icons/hicolor/128x128/apps/doom.png
  install -Dm444 ${iconset}/icon_256x256.png $out/share/icons/hicolor/256x256/apps/doom.png
  install -Dm444 ${iconset}/icon_512x512.png $out/share/icons/hicolor/512x512/apps/doom.png
''
