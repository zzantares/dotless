{
  config,
  profile,
  lib,
  pkgs,
  ...
}:

let
  browserConfig = import ../browser {
    inherit
      profile
      config
      lib
      pkgs
      ;
  };

in
{
  programs.firefox = lib.attrsets.recursiveUpdate browserConfig {
    package = config.lib.nixGL.wrap pkgs.firefox;
    configPath = "${config.xdg.configHome}/mozilla/firefox";

    policies = {
      ExtensionSettings = {
        "search@kagi.com" = {
          private_browsing_allowed = true;
        };
      };
    };

    profiles."${profile.login}" = {
      settings = {
        "browser.search.defaultenginename" = "kagi";
        "browser.startup.homepage" = "https://calendar.google.com/calendar/u/0/r";
        # "browser.startup.homepage" = "https://mail.google.com/mail/u/0/#inbox";

        # TODO Temporarily disable this to see if it helps with window relocation after unlocking the screen
        "browser.sessionstore.restore_windows_to_virtual_desktop" = false;
      };

      search = {
        default = "kagi";
        privateDefault = "kagi";

        order = [
          "kagi"
          "ddg" # DuckDuckGo
          "google"
        ];
      };
    };
  };
}
