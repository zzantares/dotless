{
  profile,
  config,
  lib,
  pkgs,
  ...
}:

# TODO this is not a HM module shouldn't be placed here but as a lib or override or shared scope

let
  defaultEngines = import ./search-engines.nix {
    inherit pkgs;
    inherit profile;
  };

in

{
  enable = true;
  package = config.lib.nixGL.wrap pkgs.librewolf;

  # See: https://releases.mozilla.org/pub/firefox/releases/<version>/linux-x86_64/xpi/
  languagePacks = [
    "en-US"
    "es-MX"
  ];

  # See "about:policies#documentation" for more options
  policies = {
    ShowHomeButton = true;
    PasswordManagerEnabled = false;
    ExtensionSettings = {
      "tridactyl.vim@cmcaine.co.uk" = {
        private_browsing_allowed = true;
      };
    };
  };

  profiles."${profile.login}" = {
    id = 0;
    name = "${profile.login}";
    isDefault = true;

    bookmarks = { };

    # Available options can be found in "about:config" page; see: https://kb.mozillazine.org/About:config_entries
    settings = {
      "browser.startup.page" = 3; # Resume previous browser session
      "extensions.autoDisableScopes" = 0;
      "extensions.enabledScopes" = 15;
      "extensions.pocket.enabled" = false;

      # Bigger font
      # "layout.css.devPixelsPerPx" = 1.1;
      "browser.zoom.full" = false;
      "font.size.variable.x-western" = if profile.login == "antares" then 20 else 18;
      "sidebar.revamp" = false;
      "sidebar.visibility" = "hide-sidebar";
      "sidebar.verticalTabs" = true;
      "browser.translations.automaticallyPopup" = false;

      "browser.uiCustomization.state" = builtins.toJSON {
        placements = {
          widget-overflow-fixed-list = [ ];
          unified-extensions-area = [
            "search_kagi_com-browser-action"
            "_f209234a-76f0-4735-9920-eb62507a54cd_-browser-action"
            "vpn_proton_ch-browser-action"
            "idcac-pub_guus_ninja-browser-action"
            "languagetool-webextension_languagetool_org-browser-action"
          ];
          nav-bar = [
            "firefox-view-button"
            "alltabs-button"
            "jid1-mnnxcxisbpnsxq_jetpack-browser-action"
            "ublock0_raymondhill_net-browser-action"
            "unified-extensions-button"
            "urlbar-container"
            "vertical-spacer"
            "forward-button"
            "back-button"
            "home-button"
            "_446900e4-71c2-419f-a6a7-df9c091e268b_-browser-action"
            "addon_darkreader_org-browser-action"
            "offline-qr-code_rugk_github_io-browser-action"
            "78272b6fa58f4a1abaac99321d503a20_proton_me-browser-action"
          ];
          toolbar-menubar = [ "menubar-items" ];
          TabsToolbar = [ ];
          vertical-tabs = [ "tabbrowser-tabs" ];
          PersonalToolbar = [ "personal-bookmarks" ];
        };
        seen = [
          "search_kagi_com-browser-action"
          "_f209234a-76f0-4735-9920-eb62507a54cd_-browser-action"
          "78272b6fa58f4a1abaac99321d503a20_proton_me-browser-action"
          "vpn_proton_ch-browser-action"
          "idcac-pub_guus_ninja-browser-action"
          "addon_darkreader_org-browser-action"
          "jid1-mnnxcxisbpnsxq_jetpack-browser-action"
          "languagetool-webextension_languagetool_org-browser-action"
          "offline-qr-code_rugk_github_io-browser-action"
          "ublock0_raymondhill_net-browser-action"
          "_446900e4-71c2-419f-a6a7-df9c091e268b_-browser-action"
          "developer-button"
          "screenshot-button"
        ];
        dirtyAreaCache = [
          "unified-extensions-area"
          "nav-bar"
          "TabsToolbar"
          "vertical-tabs"
        ];
        currentVersion = 23;
        newElementCount = 0;
      };

      # Graphics
      # "media.ffmpeg.vaapi.enabled" = profile.login == "antares";

      # DRM
      "browser.eme.ui.enabled" = false; # Do not show UI elements to toggle DRM
      "media.eme.enabled" = true;
      # "media.eme.require-app-approval" = false;
      # "media.gmp-provider.enabled" = true;
      # TODO if DRM content still doesn't work we might need these `gmp-widevinecdm` settings and install widevine-cdm
      #   firefox would need to see it by setting:
      #   `environment.sessionVariables.MOZ_GMP_PATH = [ "${pkgs.widevine-cdm-lacros}/gmp-widevinecdm/system-installed" ];`
      # "media.gmp-widevinecdm.enabled" = true;
      # "media.gmp-widevinecdm.visible" = true;

      # Disable notifications
      "dom.webnotifications.enabled" = false;
      "dom.webnotifications.serviceworker.enabled" = false;
      "dom.pushconnection.enabled" = false;
      "dom.push.enabled" = false;
      "services.sync.prefs.sync.dom.webnotifications.enabled" = true;
      "services.sync.prefs.sync.dom.webnotifications.serviceworker.enabled" = true;
      "services.sync.prefs.sync.dom.pushconnection.enabled" = true;
      "services.sync.prefs.sync.dom.push.enabled" = true;

      # Network settings (like DNS-over-HTTPS) see: https://wiki.mozilla.org/Trusted_Recursive_Resolver
      # TODO DoH causes slow browsing need to setup a self-hosted server for faster web browsing + caching
      # "network.ttr.mode" = 2; # Fallback to native resolver if DoH fails # TODO switch to 3 after using self-hosted server
      "network.ttr.mode" = 0; # Off (default). use standard native resolving only (don't use TRR at all) # TODO remove when using DoH
      # "network.ttr.uri" = "https://mozilla.cloudflare-dns.com/dns-query";
      # "network.ttr.custom_uri" = "https://mozilla.cloudflare-dns.com/dns-query";
      # "network.trr.bootstrapAddress" = "1.1.1.1";
      # "network.trr.excluded-domains" = "localhost,local,omnia,ip6-localhost"; # when using TTR `/etc/hosts` settings are be ignored except for these domains
      # "network.security.esni.enabled" = true;

      # Disable irritating first-run stuff
      "browser.disableResetPrompt" = true;
      "browser.download.panel.shown" = true;
      "browser.feeds.showFirstRunUI" = false;
      "browser.messaging-system.whatsNewPanel.enabled" = false;
      "browser.rights.3.shown" = true;
      "browser.shell.checkDefaultBrowser" = false;
      "browser.shell.defaultBrowserCheckCount" = 1;
      "browser.startup.homepage_override.mstone" = "ignore";
      "browser.uitour.enabled" = false;
      "startup.homepage_override_url" = "";
      "trailhead.firstrun.didSeeAboutWelcome" = true;
      "browser.aboutConfig.showWarning" = false;
      "browser.bookmarks.restore_default_bookmarks" = false;
      "browser.bookmarks.addedImportButton" = true;

      # Disable crappy home activity stream page
      "browser.newtabpage.activity-stream.feeds.section.topstories" = false;
      "browser.newtabpage.activity-stream.feeds.snippets" = false;
      "browser.newtabpage.activity-stream.feeds.topsites" = false;
      "browser.newtabpage.activity-stream.section.highlights.includePocket" = false;
      "browser.newtabpage.activity-stream.section.highlights.includeBookmarks" = false;
      "browser.newtabpage.activity-stream.section.highlights.includeDownloads" = false;
      "browser.newtabpage.activity-stream.section.highlights.includeVisited" = false;
      "browser.newtabpage.activity-stream.showSponsored" = false;
      "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
      "browser.newtabpage.activity-stream.system.showSponsored" = false;
      "browser.newtabpage.activity-stream.improvesearch.topSiteSearchShortcuts" = false;
      "browser.newtabpage.blocked" = lib.genAttrs [
        # Youtube
        "26UbzFJ7qT9/4DhodHKA1Q=="
        # Facebook
        "4gPpjkxgZzXPVtuEoAL9Ig=="
        # Wikipedia
        "eV8/WsSLxHadrTL1gAxhug=="
        # Reddit
        "gLv0ja2RYVgxKdp0I5qwvA=="
        # Amazon
        "K00ILysCaEq8+bEqV/3nuw=="
        # Twitter
        "T9nJot5PurhJSy8n038xGA=="
      ] (_: 1);

      # Disable "save password" prompt
      "signon.rememberSignons" = false;

      # Disable annoying flaoting button when reading PDFs
      "pdfjs.enableAltTextForEnglish" = false;

      # Default search engine and start page
      "browser.search.defaultenginename" = "ddg";
      "browser.startup.homepage" = "https://mail.proton.me/u/0/inbox";

      # Harden
      "privacy.trackingprotection.enabled" = true;
      "dom.security.https_first" = true;
      "dom.security.https_only_mode" = true;
      "browser.fixup.fallback-to-https" = true;
    };

    # See https://gitlab.com/rycee/nur-expressions/-/blob/9da3f74ac2cba8d812aef5fe16686afa25033b21/pkgs/firefox-addons/addons.json
    extensions.packages = with pkgs.nur.repos.rycee.firefox-addons; [
      bitwarden
      darkreader
      istilldontcareaboutcookies
      kagi-search
      languagetool
      link-cleaner # TODO switch to maintained fork link-cleaner-plus
      offline-qr-code-generator
      old-reddit-redirect
      privacy-badger
      proton-pass
      proton-vpn
      reddit-enhancement-suite
      tridactyl
      ublock-origin
      unpaywall
    ];

    search = {
      force = true;
      engines = defaultEngines;

      default = "ddg";
      privateDefault = "ddg";

      order = [
        "ddg" # DuckDuckGo
        "kagi"
        "google"
      ];
    };
  };
}
