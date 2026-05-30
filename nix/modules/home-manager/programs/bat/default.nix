{ lib, pkgs, ... }:

let
  catppuccinFlavor = name: {
    file = "themes/${name}.tmTheme";
    src = pkgs.fetchFromGitHub {
      owner = "catppuccin";
      repo = "bat";
      rev = "699f60fc8ec434574ca7451b444b880430319941";
      sha256 = "sha256-6fWoCH90IGumAMc4buLRWL0N61op+AuMNN9CAR9/OdI=";
    };
  };

  tokyonightFlavor = name: {
    file = "extras/sublime/${name}.tmTheme";
    src = pkgs.fetchFromGitHub {
      owner = "folke";
      repo = "tokyonight.nvim";
      rev = "5598215fa06572048bc857c9c71378a5433ec070";
      sha256 = "sha256-0/PgFKjxFdgS7M8bW2N0d6Gzyl4tyVD3+ocsjcKVsiM=";
    };
  };

in
{
  home.sessionVariables = {
    PAGER = lib.mkDefault "bat";
    MANPAGER = lib.mkDefault "batman";
  };

  home.shellAliases = {
    cat = "bat -n --paging=never";
    less = "batpipe";
    man = "batman";
  };

  # Bat replaces cat
  programs.bat = {
    enable = lib.mkDefault true;
    extraPackages = with pkgs.bat-extras; [
      batman
      batgrep
      batwatch
      batpipe
    ];
    config = {
      theme = "1337";
      pager = "less"; # add "less -XFRS" for explicit behavior
      style = "auto";
      decorations = "auto";
    };

    themes = {
      catppuccin-frape = catppuccinFlavor "Catppuccin Frappe";
      catppuccin-late = catppuccinFlavor "Catppuccin Latte";
      catppuccin-macchiato = catppuccinFlavor "Catppuccin Macchiato";
      catppuccin-mocha = catppuccinFlavor "Catppuccin Mocha";
      tokyonight-day = tokyonightFlavor "tokyonight_day";
      tokyonight-moon = tokyonightFlavor "tokyonight_moon";
      tokyonight-night = tokyonightFlavor "tokyonight_night";
      tokyonight-storm = tokyonightFlavor "tokyonight_storm";
    };
  };
}
