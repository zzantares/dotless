{
  profile,
  pkgs,
  lib,
  ...
}:

let
  devdocs =
    name: hash:
    pkgs.fetchurl {
      url = "https://download.kiwix.org/zim/devdocs/${name}.zim";
      inherit hash;
    };

  # Stack Overflow is NOT fetched into the store: at 115 GB a fetchurl has no
  # resume, so one dropped connection restarts the whole download. Fetch it out
  # of band with something resumable; --skipInvalid covers its absence.
  #
  # It cannot live under $HOME either: the unit runs ProtectHome=true, so the
  # whole of /home reads as empty from inside it.
  stackoverflow = "/var/lib/kiwix/stackoverflow.com_en_all.zim";

  # Keyed by the name each book is served and searched under. kiwix.el derives
  # its library list from these filenames, so the keys are user-visible.
  zims = {
    # Packed from this closure, so the versions cannot drift from the tools.
    # Upstream's Haskell docset tracks the newest GHC 9.x - 9.14 against the
    # 9.10 installed here - its Rust and TypeScript docsets carry no version at
    # all, and its Postgres book followed 18 while this fleet serves 17.
    haskell = pkgs.zim-haskell;
    rust = pkgs.zim-rust;
    postgresql = pkgs.zim-postgresql;

    # DevDocs for the languages with no local HTML to pack. Python matches to
    # the minor; TypeScript upstream is still on 6.x, so that one trails the
    # installed compiler until they ship 7.
    python = devdocs "devdocs_en_python_2026-08" "sha256-KJ5dPg6MPTRwvxg+XJE7474LYacwzlKiR8I4EnmbqlE=";
    typescript = devdocs "devdocs_en_typescript_2026-07" "sha256-sDjPXLDUTJ9kdxQH1hvz0JSi0Eovn35Pa84vbyXA0FI=";

    inherit stackoverflow;
  };
in

{
  # Offline documentation served from ZIM archives, which add full-text search
  # over the toolchains' own HTML and cover the languages that ship no local
  # docs at all.
  #
  # Dated filenames are deliberate: refreshing a docset is a URL + hash bump,
  # the price of the ZIMs being part of the closure.
  services.kiwix-serve = {
    enable = lib.mkDefault true;
    port = lib.mkDefault 8124;
    library = lib.mkDefault zims;

    # Without this the unit refuses to start until every ZIM exists, making the
    # five pinned docsets hostage to a 115 GB download that may not have run.
    extraArgs = [ "--skipInvalid" ];
  };

  # kiwix.el lists `*.zim` in one directory to build its library menu, and the
  # module's own link farm is an internal store path it does not expose. Mirror
  # the same set at a stable path so Emacs and the server agree on both the
  # books and the names. kiwix-serve runs under DynamicUser, hence 0755.
  #
  # The parent is owned by the login user so the out-of-store ZIM can be
  # downloaded without root - it is a multi-hour transfer, and needing sudo for
  # it only sends people to put the file somewhere ProtectHome then hides.
  # zims/ stays root-owned: tmpfiles manages every symlink in it.
  systemd.tmpfiles.rules = [
    "d /var/lib/kiwix 0755 ${profile.login} users -"
    "d /var/lib/kiwix/zims 0755 root root -"
  ]
  ++ lib.mapAttrsToList (name: path: "L+ /var/lib/kiwix/zims/${name}.zim - - - - ${path}") zims;
}
