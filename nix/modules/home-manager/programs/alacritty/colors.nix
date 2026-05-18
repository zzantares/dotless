{
  yorumi-abyss = (builtins.fromTOML (builtins.readFile ./themes/yorumi-abyss.toml)).colors;
  yorumi-mist = (builtins.fromTOML (builtins.readFile ./themes/yorumi-abyss.toml)).colors;

  iterm = {
    # Default colors
    primary = {
      background = "0x101421";
      foreground = "0xfffbf6";
    };

    # Normal colors
    normal = {
      black = "0x2e2e2e";
      red = "0xeb4129";
      green = "0xabe047";
      yellow = "0xf6c744";
      blue = "0x47a0f3";
      magenta = "0x7b5cb0";
      cyan = "0x64dbed";
      white = "0xe5e9f0";
    };

    # Bright colors
    bright = {
      black = "0x565656";
      red = "0xec5357";
      green = "0xc0e17d";
      yellow = "0xf9da6a";
      blue = "0x49a4f8";
      magenta = "0xa47de9";
      cyan = "0x99faf2";
      white = "0xffffff";
    };
  };

  kanagawa = {
    draw_bold_text_with_bright_colors = true;

    primary = {
      background = "0x1f1f28";
      foreground = "0xdcd7ba";
    };

    normal = {
      black = "0x090618";
      red = "0xc34043";
      green = "0x76946a";
      yellow = "0xc0a36e";
      blue = "0x7e9cd8";
      magenta = "0x957fb8";
      cyan = "0x6a9589";
      white = "0xc8c093";
    };

    bright = {
      black = "0x727169";
      red = "0xe82424";
      green = "0x98bb6c";
      yellow = "0xe6c384";
      blue = "0x7fb4ca";
      magenta = "0x938aa9";
      cyan = "0x7aa89f";
      white = "0xdcd7ba";
    };

    selection = {
      background = "0x2d4f67";
      foreground = "0xc8c093";
    };

    indexed_colors = [
      {
        index = 16;
        color = "0xffa066";
      }
      {
        index = 17;
        color = "0xff5d62";
      }
    ];
  };

  modus = {
    operandi = {
      normal = {
        black = "#d7d7d7";
        blue = "#2544bb";
        cyan = "#30517f";
        green = "#315b00";
        magenta = "#8f0075";
        red = "#972500";
        white = "#000000";
        yellow = "#70480f";
      };

      cursor = {
        cursor = "#282828";
        text = "#d7d7d7";
      };

      bright = {
        black = "#505050";
        blue = "#0031a9";
        cyan = "#00538b";
        green = "#005e00";
        magenta = "#721045";
        red = "#a60000";
        white = "#595959";
        yellow = "#813e00";
      };

      primary = {
        background = "#ffffff";
        foreground = "#000000";
      };

      selection = {
        background = "#bcbcbc";
        text = "#000000";
      };
    };

    operandi-tinted = {
      normal = {
        black = "#efe9dd";
        red = "#a60000";
        green = "#006800";
        yellow = "#6f5500";
        blue = "#0031a9";
        magenta = "#721045";
        cyan = "#005e8b";
        white = "#000000";
      };

      bright = {
        black = "#c9b9b0";
        red = "#a0132f";
        green = "#00663f";
        yellow = "#7a4f2f";
        blue = "#0000b0";
        magenta = "#531ab6";
        cyan = "#005f5f";
        white = "#595959";
      };

      cursor = {
        cursor = "#dfa0f0";
        text = "#fbf7f0";
      };

      primary = {
        background = "#fbf7f0";
        foreground = "#000000";
      };

      selection = {
        background = "#c2bcb5";
        text = "#000000";
      };
    };

    operandi-deuteranopia = {
      normal = {
        black = "#f2f2f2";
        red = "#a60000";
        green = "#006800";
        yellow = "#695500";
        blue = "#0031a9";
        magenta = "#721045";
        cyan = "#005e8b";
        white = "#000000";
      };

      bright = {
        black = "#c4c4c4";
        red = "#a0132f";
        green = "#00663f";
        yellow = "#77492f";
        blue = "#0000b0";
        magenta = "#531ab6";
        cyan = "#005f5f";
        white = "#595959";
      };

      cursor = {
        cursor = "#dfa0f0";
        text = "#ffffff";
      };

      primary = {
        background = "#ffffff";
        foreground = "#000000";
      };

      selection = {
        background = "#bdbdbd";
        text = "#000000";
      };
    };
  };
}
