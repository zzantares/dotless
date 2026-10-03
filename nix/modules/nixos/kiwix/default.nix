{
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
  stackoverflow = "/var/lib/kiwix/stackoverflow.com_en_all.zim";

  # Keyed by the name each book is served and searched under. kiwix.el derives
  # its library list from these filenames, so the keys are user-visible.
  zims = {
    rust = devdocs "devdocs_en_rust_2026-10" "sha256-kDUPDPVbJhkLf9w7UvBvsmPYNdRFj3yHC+FaCmqFYCM=";
    python = devdocs "devdocs_en_python_2026-08" "sha256-KJ5dPg6MPTRwvxg+XJE7474LYacwzlKiR8I4EnmbqlE=";
    postgresql = devdocs "devdocs_en_postgresql_2026-08" "sha256-5Oc+OvXPvORQy53BY9wh4g07G1m4SBOXYSNldPN8UOo=";
    haskell = devdocs "devdocs_en_haskell_2026-04" "sha256-gS33vVlAWJY9oCZxo0Zt/v9gQuFldb444Eij7D/jEaI=";
    typescript = devdocs "devdocs_en_typescript_2026-07" "sha256-sDjPXLDUTJ9kdxQH1hvz0JSi0Eovn35Pa84vbyXA0FI=";
    inherit stackoverflow;
  };
in

{
  # Offline documentation served from pinned ZIM archives. DevDocs covers the
  # languages with nothing local of their own - python, typescript, postgres.
  # Haskell and Rust already ship haddock and rustdoc in their toolchains but
  # are kept here for full-text search across the whole set.
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
  systemd.tmpfiles.rules = [
    "d /var/lib/kiwix 0755 root root -"
    "d /var/lib/kiwix/zims 0755 root root -"
  ]
  ++ lib.mapAttrsToList (name: path: "L+ /var/lib/kiwix/zims/${name}.zim - - - - ${path}") zims;
}
