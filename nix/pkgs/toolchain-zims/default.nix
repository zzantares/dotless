{
  lib,
  runCommand,
  zim-tools,
  python3,
  rustc-with-src,
  hoogle-batteries,
  ghc,
  postgresql-pinned,
}:

let
  # zimwriterfs wants a 48x48 PNG inside the HTML directory, and neither
  # toolchain ships one. A flat colour is enough to identify the book in
  # kiwix's library view.
  icon = rgb: ''
    ${python3}/bin/python3 - "$work/zim-illustration.png" <<'PY'
    import sys, zlib, struct
    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff))
    w = h = 48
    raw = b"".join(b"\x00" + bytes([${rgb}]) * w for _ in range(h))
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw))
           + chunk(b"IEND", b""))
    open(sys.argv[1], "wb").write(png)
    PY
  '';

  # zimwriterfs reads a directory, so the store tree has to be copied: it needs
  # the illustration (and for Haskell a root index) written alongside the HTML,
  # and the sources are read-only symlink farms.
  mkZim =
    {
      pname,
      title,
      description,
      src,
      rgb,
      welcome ? "index.html",
      prepare ? "",
    }:
    runCommand "${pname}.zim"
      {
        nativeBuildInputs = [ zim-tools ];
        meta = {
          inherit description;
          longDescription = ''
            Built from the installed toolchain's own HTML, so the content matches
            the compiler in this closure rather than whatever version an upstream
            docset happened to track. Carries a full-text index, unlike the raw
            HTML trees.
          '';
          platforms = lib.platforms.linux;
        };
      }
      ''
        work=$(mktemp -d)

        # `cp -rL` aborts on a dangling symlink, and the haddock tree has one
        # per package that produced no doc output (happy, for instance - it is
        # an executable). Copying from a resolved file list skips those at any
        # depth instead of failing the build.
        (cd ${src} && find -L . -type f -print0 \
          | tar --null --files-from=- --dereference -cf -) | tar -xf - -C "$work"
        chmod -R u+w "$work"

        ${icon rgb}
        ${prepare}

        zimwriterfs \
          --welcome=${welcome} \
          --illustration=zim-illustration.png \
          --language=eng \
          --name=${pname} \
          --title="${title}" \
          --description="${description}" \
          --creator="toolchain" \
          --publisher="dotless" \
          --threads=$NIX_BUILD_CORES \
          "$work" "$out"

        rm -rf "$work"
      '';
in

{
  rust = mkZim {
    pname = "rustdoc-local";
    title = "Rust ${rustc-with-src.version}";
    description = "std, book, reference, nomicon and cargo book from this Rust toolchain";
    src = "${rustc-with-src}/share/doc/rust/html";
    rgb = "222,165,132";

    # zimwriterfs resolves every meta-refresh target as a path inside the tree
    # and aborts when one does not resolve. rustdoc emits ~22k such stubs, of
    # which a few point at rust-lang.github.io and a few carry a #fragment.
    # Fix both in one pass rather than per-symptom.
    prepare = ''
      ${python3}/bin/python3 - "$work" <<'PY'
      import os, re, sys
      root = sys.argv[1]
      tag = re.compile(
          r'<meta\s+http-equiv="refresh"[^>]*?content="[^"]*?URL=([^"]*)"[^>]*>',
          re.I,
      )
      dropped = trimmed = 0
      for dirpath, _, names in os.walk(root):
          for name in names:
              if not name.endswith((".html", ".htm")):
                  continue
              path = os.path.join(dirpath, name)
              with open(path, encoding="utf-8", errors="surrogateescape") as f:
                  body = f.read()
              match = tag.search(body)
              if not match:
                  continue
              url = match.group(1)
              keep = None
              if not re.match(r"[a-z]+:", url, re.I):
                  bare = url.split("#", 1)[0].split("?", 1)[0]
                  if bare and os.path.exists(os.path.join(dirpath, bare)):
                      keep = bare
              if keep is None:
                  body = body[: match.start()] + body[match.end() :]
                  dropped += 1
              elif keep != url:
                  body = body[: match.start()] + match.group(0).replace(
                      "URL=" + url, "URL=" + keep
                  ) + body[match.end() :]
                  trimmed += 1
              else:
                  continue
              with open(path, "w", encoding="utf-8", errors="surrogateescape") as f:
                  f.write(body)
      print(f"redirects: dropped {dropped}, de-fragmented {trimmed}", file=sys.stderr)
      PY
    '';
  };

  postgresql = mkZim {
    pname = "postgresql-local";
    title = "PostgreSQL ${postgresql-pinned.version}";
    description = "The PostgreSQL manual for the major this fleet serves";
    src = "${postgresql-pinned.doc}/share/doc/postgresql/html";
    rgb = "51,103,145";
  };

  haskell = mkZim {
    pname = "haddock-local";
    title = "Haskell (GHC ${ghc.version})";
    description = "Haddock for every package in ghc-with-batteries, from this GHC";
    src = "${hoogle-batteries}/share/doc/hoogle";
    rgb = "94,80,134";

    # Haddock ships an index per package and no root, so the ZIM would have no
    # welcome page. Build one listing whatever the closure turned out to hold.
    prepare = ''
      ${python3}/bin/python3 - "$work" <<'PY'
      import os, sys, html
      root = sys.argv[1]
      pkgs = sorted(
          (d for d in os.listdir(root)
           if os.path.isfile(os.path.join(root, d, "index.html"))),
          key=str.lower,
      )
      rows = "\n".join(
          f'<li><a href="{html.escape(p)}/index.html">{html.escape(p)}</a></li>'
          for p in pkgs
      )
      with open(os.path.join(root, "index.html"), "w") as f:
          f.write(
              "<!doctype html><html><head><meta charset=utf-8>"
              "<title>Haskell packages</title></head><body>"
              f"<h1>Haskell packages ({len(pkgs)})</h1><ul>{rows}</ul>"
              "</body></html>"
          )
      print(f"indexed {len(pkgs)} packages", file=sys.stderr)
      PY
    '';
  };
}
