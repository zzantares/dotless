{ profile, pkgs, ... }:

{
  bing.metadata.hidden = true;
  ebay.metadata.hidden = true;
  google.metaData.alias = "@go";
  wikipedia.metadata.alias = "@w";

  kagi = {
    urls = [
      {
        template = "https://kagi.com/search";
        params = [
          {
            name = "token";
            value = "${profile.sensitive.kagiAuthToken}";
          }
          {
            name = "q";
            value = "{searchTerms}";
          }
        ];
      }
    ];
    icon = "https://kagi.com/favicon.ico";
  };

  github = {
    definedAliases = [ "@gh" ];
    urls = [
      {
        template = "https://github.com/search";
        params = [
          {
            name = "q";
            value = "{searchTerms}";
          }
        ];
      }
    ];
    icon = "${pkgs.fetchurl {
      url = "https://github.githubassets.com/favicons/favicon.svg";
      sha256 = "sha256-apV3zU9/prdb3hAlr4W5ROndE4g3O1XMum6fgKwurmA=";
    }}";
  };

  nix-packages = {
    definedAliases = [ "@ni" ];
    urls = [
      {
        template = "https://search.nixos.org/packages";
        params = [
          {
            name = "channel";
            value = "unstable";
          }
          {
            name = "query";
            value = "{searchTerms}";
          }
        ];
      }
    ];
    icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
  };

  nixos-wiki = {
    definedAliases = [ "@nw" ];
    urls = [
      {
        template = "https://nixos.wiki/index.php";
        params = [
          {
            name = "search";
            value = "{searchTerms}";
          }
        ];
      }
    ];
    icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
  };

  home-manager-options = {
    definedAliases = [ "@hm" ];
    urls = [
      {
        template = "https://home-manager-options.extranix.com";
        params = [
          {
            name = "query";
            value = "{searchTerms}";
          }
        ];
      }
    ];
    icon = "${pkgs.fetchurl {
      url = "https://home-manager-options.extranix.com/images/favicon.png";
      sha256 = "1gjvkggi5b1qkyaywknzj2sfg1bsaj2avmdg003dspfbhix7wnm0";
    }}";
  };

  noogle = {
    definedAliases = [ "@no" ];
    urls = [
      {
        template = "https://noogle.dev/q";
        params = [
          {
            name = "term";
            value = "{searchTerms}";
          }
        ];
      }
    ];
    icon = "${pkgs.fetchurl {
      url = "https://noogle.dev/favicon.png";
      sha256 = "0lrm4xnncfyx05c9gb74lf653czgbqv5gbq81nwwvmcgqzwc2n75";
    }}";
  };

  hoogle = {
    definedAliases = [ "@ho" ];
    urls = [
      {
        template = "https://hoogle.haskell.org/";
        params = [
          {
            name = "scope";
            value = "set:stackage";
          }
          {
            name = "hoogle";
            value = "{searchTerms}";
          }
        ];
      }
    ];
    icon = "${pkgs.fetchurl {
      url = "https://hoogle.haskell.org/favicon.png";
      sha256 = "0bvslxrbnknw4w832z7cx2ifvmd3ga8a2js7x0k4qif3h12s7aga";
    }}";
  };

  hoogle-local = {
    definedAliases = [
      "@hol"
      "@lho"
    ];
    urls = [
      {
        template = "http://localhost:8080/";
        params = [
          {
            name = "scope";
            value = "set:stackage";
          }
          {
            name = "hoogle";
            value = "{searchTerms}";
          }
        ];
      }
    ];
    icon = "${pkgs.fetchurl {
      # Get the favicon from the internet such that when bootstraping
      # the config it does not depend on our local hoogle running yet
      url = "https://hoogle.haskell.org/favicon.png";
      sha256 = "0bvslxrbnknw4w832z7cx2ifvmd3ga8a2js7x0k4qif3h12s7aga";
    }}";
  };

  hoogle-mangoiv = {
    definedAliases = [ "@hl" ];
    urls = [
      {
        template = "https://hoogle.mangoiv.com/";
        params = [
          {
            name = "q";
            value = "{searchTerms}";
          }
        ];
      }
    ];
    icon = "${pkgs.fetchurl {
      url = "https://hoogle.mangoiv.com/assets/images/favicon.ico";
      sha256 = "0cz3njzchkz3p32pqnkva67rz6digiap31ddw2rs0lx695x2v2pp";
    }}";
  };

  hackage = {
    definedAliases = [ "@ha" ];
    urls = [
      {
        template = "https://hackage.haskell.org/packages/search";
        params = [
          {
            name = "terms";
            value = "{searchTerms}";
          }
        ];
      }
    ];
    icon = "${pkgs.fetchurl {
      url = "https://hackage.haskell.org/static/favicon.png";
      sha256 = "05ibl7wvj9k7zmm3sa6v1d2fx3wmcjn1hpp8v75hss7jvnzq19gv";
    }}";
  };

  hackage-package = {
    definedAliases = [ "@hp" ];
    urls = [
      {
        template = "https://hackage.haskell.org/package/{searchTerms}";
      }
    ];
    icon = "${pkgs.fetchurl {
      url = "https://hackage.haskell.org/static/favicon.png";
      sha256 = "05ibl7wvj9k7zmm3sa6v1d2fx3wmcjn1hpp8v75hss7jvnzq19gv";
    }}";
  };

  the-saurus = {
    definedAliases = [ "@sa" ];
    urls = [
      {
        template = "https://www.thesaurus.com/browse/{searchTerms}";
      }
    ];
    icon = "${pkgs.fetchurl {
      url = "https://www.google.com/s2/favicons?domain_url=thesaurus.com";
      sha256 = "sha256-u9HLdKJoIcMho8hu42P9hR1k30ygzn4hfEUVzHdsQsc=";
    }}";
  };

  reddit = {
    definedAliases = [ "@re" ];
    urls = [
      {
        template = "https://www.reddit.com/search";
        params = [
          {
            name = "q";
            value = "{searchTerms}";
          }
        ];
      }
    ];
    icon = "${pkgs.fetchurl {
      url = "https://www.redditstatic.com/accountmanager/favicon/favicon-512x512.png";
      sha256 = "sha256-4zWTcHuL1SEKk8KyVFsOKYPbM4rc7WNa9KrGhK4dJyg=";
    }}";
  };

  youtube = {
    definedAliases = [ "@yt" ];
    urls = [
      {
        template = "https://www.youtube.com/results";
        params = [
          {
            name = "search_query";
            value = "{searchTerms}";
          }
        ];
      }
    ];
    icon = "${pkgs.fetchurl {
      url = "www.youtube.com/s/desktop/8498231a/img/favicon_144x144.png";
      sha256 = "sha256-lQ5gbLyoWCH7cgoYcy+WlFDjHGbxwB8Xz0G7AZnr9vI=";
    }}";
  };
}
