{ inputs, ... }:

final: prev:

let
  system = prev.stdenv.hostPlatform.system;
in

{
  nix = final.nixVersions.latest;

  myHaskellPackages = final.haskell.packages.ghc910;

  aspell-with-dicts = final.aspellWithDicts (
    ds: with ds; [
      en
      en-computers
      en-science
      es
    ]
  );

  claude-code = final.callPackage ./../pkgs/claude-code { };

  # Bun standalone executables embed their JS bundle as a blob appended after
  # the ELF sections. This binary is non-PIE (type EXEC) with fixed virtual
  # addresses and uses Nix's ld-linux-x86-64.so.2 (glibc 2.42) as its
  # interpreter. That linker crashes applying COPY relocations to the binary's
  # BSS section — the system linker works correctly.
  #
  # patchelf can't fix this: it resizes ELF segments when adding RPATH, which
  # shifts the embedded blob and corrupts the binary. Instead we shim
  # .opencode-wrapped to invoke the binary via the system linker.
  #
  # Build-time checks (smoke test, shell completions, version check) also run
  # the binary and segfault in the Nix sandbox for the same reason — skip them.
  opencode =
    if prev.stdenv.isLinux then
      (inputs.opencode.packages.${system}.default).overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          substituteInPlace packages/opencode/script/build.ts \
            --replace-fail \
              'if (item.os === process.platform && item.arch === process.arch && !item.abi) {' \
              'if (false) {'
        '';

        postInstall = "";
        doInstallCheck = false;

        postFixup = (old.postFixup or "") + ''
          # The Bun binary uses Nix's ld-linux-x86-64.so.2 (glibc 2.42) as its
          # interpreter, but that linker crashes while applying COPY relocations to
          # the BSS section of this non-PIE Bun binary. The system linker works.
          # We replace .opencode-wrapped with a shim that invokes it via the system
          # linker, leaving the binary itself untouched.
          mv $out/bin/.opencode-wrapped $out/bin/.opencode-bun
          printf '#!/bin/sh\nexec /lib64/ld-linux-x86-64.so.2 "%s" "$@"\n' \
            "$out/bin/.opencode-bun" > $out/bin/.opencode-wrapped
          chmod +x $out/bin/.opencode-wrapped
        '';
      })
    else
      inputs.opencode.packages.${system}.default;

  # Creates a menu for tmux-fzf that exposes Claude Code sessions
  tmux-claude-picker = final.writeShellScriptBin "tmux-claude-picker" ''
    #!/usr/bin/env bash
    selected=$(tmux list-sessions -F '#{session_name}' | while read s; do
        val=$(tmux show-option -t "$s" -qv @claude_attention 2>/dev/null)
        [ "$val" = '1' ] && echo "● $s" || echo "  $s"
    done | sort -r | fzf --ansi --reverse --no-sort)

    [ -n "$selected" ] && tmux switch-client -t "$(echo "$selected" | sed 's/^[● ]*//')"
  '';

  fonts = final.callPackage ./../pkgs/fonts { };

  zed-editor = inputs.zed-editor.packages.${system}.default;

  toolchains = {
    c = final.buildEnv {
      name = "c-toolchain";
      paths = with final; [
        gcc
        gnumake
        cmake
        clang-tools
      ];
    };

    nix = final.buildEnv {
      name = "nix-toolchain";
      paths = with final; [
        cachix
        nil
        nixd
        nixfmt
      ];
    };

    android = final.buildEnv {
      name = "android-toolchain";
      paths = prev.lib.optionals prev.stdenv.isLinux (with final; [
        (symlinkJoin {
          name = "android-studio-wrapped";
          paths = [ android-studio ];
          buildInputs = [ makeWrapper ];
          postBuild = ''
            wrapProgram $out/bin/android-studio \
              --prefix PATH : ${glib}/bin
          '';
        })
      ]);
    };

    shell = final.buildEnv {
      name = "shell-toolchain";
      paths = with final; [
        bash-language-server
        shellcheck
        shfmt
      ];
    };

    rust = final.buildEnv {
      name = "rust-toolchain";
      paths = with final; [
        pkgs.rust-bin.stable.latest.default
        rust-analyzer
      ];
    };

    python =
      let
        python-with-batteries = final.python3.withPackages (
          ps: with ps; [
            pyflakes
            pytest
          ]
        );
      in
      final.buildEnv {
        name = "python-toolchain";
        paths = with final; [
          python-with-batteries
          isort
          pipenv
          pyright
          black
        ];
      };

    lisp = final.buildEnv {
      name = "lisp-toolchain";
      paths = with final; [
        guile
        sbcl
        scheme-manpages
      ];
    };

    lua = final.buildEnv {
      name = "lua-toolchain";
      paths = with final; [
        lua
        stylua
        lua-language-server
        selene
      ];
    };

    ops = final.buildEnv {
      name = "ops-toolchain";
      paths =
        with final;
        [
          opentofu
          tofu-ls
          terragrunt
          ansible-lint
          hadolint
          hclfmt
          atlas
          nomad
          consul
          vault
        ]
        ++ prev.lib.optionals prev.stdenv.isLinux [
          qemu_kvm
          virt-manager
        ];
    };

    network = final.buildEnv {
      name = "network-toolchain";
      paths =
        with final;
        [
          wireshark
          tcpdump
          iperf
          nmap
        ]
        ++ prev.lib.optionals prev.stdenv.isLinux [
          iproute2
          wirelesstools
          aircrack-ng
          traceroute
          tcptraceroute
          netcat
        ];
    };

    haskell = final.buildEnv {
      name = "haskell-toolchain";
      paths =
        with final.myHaskellPackages;
        [
          cabal-fmt
          cabal-install
          cabal-plan
          ghcid
        ]
        ++ [ final.ghc-with-batteries ];
    };

    typescript = final.buildEnv {
      name = "typescript-toolchain";
      paths = with final; [
        typescript
        typescript-language-server
        graphql-language-service-cli
        vscode-langservers-extracted
        biome
        bun
      ];
    };

    clojure = final.buildEnv {
      name = "clojure-toolchain";
      paths = with final; [
        babashka
        clj-kondo
        cljfmt
        clojure
        clojure-lsp
        jdk
        jet
        leiningen
        neil
      ];
    };

    web = final.buildEnv {
      name = "html-toolchain";
      paths = with final; [
        html-tidy
        stylelint
      ];
    };

    markdown = final.buildEnv {
      name = "markdown-toolchain";
      paths = with final; [
        discount
        markdownlint-cli
      ];
    };

    postgresql = final.buildEnv {
      name = "postgresql-toolchain";
      paths = with final; [
        pgformatter
        sqls
      ];
    };
  };

  bat-extras = prev.bat-extras // {
    batman =
      let
        theme = "Solarized (dark)";
      in
      prev.bat-extras.batman.overrideAttrs (old: {
        postFixup = ''
          wrapProgram $out/bin/batman --set BAT_THEME "${theme}"
        '';
      });
  };

  linear-cli = final.callPackage ./../pkgs/linear-cli { };

  latex-with-packages = final.texliveMedium.withPackages (
    ps: with ps; [
      capt-of
      environ
      fontspec
      fvextra
      iftex
      listings
      listingsutf8
      minted
      pdfcol
      tcolorbox
      ucs
      unicode-math
      upquote
      wrapfig
    ]
  );

  ghc-with-batteries = final.myHaskellPackages.ghcWithHoogle (
    hpkgs: with hpkgs; [
      HUnit
      QuickCheck
      aeson
      async
      attoparsec
      base
      base16-bytestring
      base64-bytestring
      bifunctors
      bytes
      bytestring
      Cabal
      cassava
      containers
      directory
      dns
      doctest
      happstack-server
      happy
      haskell-language-server
      haskell-src-exts
      hedgehog
      hspec
      hspec-expectations
      hspec-wai
      http-client
      http-client-tls
      io-streams
      monad-par
      mtl
      network
      parallel
      process
      quickcheck-instances
      random
      scientific
      servant
      servant-auth
      servant-client
      servant-server
      tar
      text
      text-show
      time
      tls
      transformers
      unordered-containers
      vector
      void
      wai
      warp
      yaml
      zlib
    ]
  );
}
// prev.lib.optionalAttrs prev.stdenv.isLinux {
  gnomeExtensions = prev.gnomeExtensions // {
    tiling-shell = prev.gnomeExtensions.tiling-shell.overrideAttrs (old: {
      version = "42";
      src = final.fetchzip {
        url = "https://extensions.gnome.org/extension-data/tilingshellferrarodomenico.com.v42.shell-extension.zip";
        sha256 = "sha256-CH55Q4gNi1uklDUyeW3lr1leDw+9l/sTUi41OCnHZzY=";
        stripRoot = false;
      };
    });

    unite = prev.gnomeExtensions.unite.overrideAttrs (old: rec {
      version = "72";
      src = final.fetchFromGitHub {
        owner = "hardpixel";
        repo = "unite-shell";
        rev = "v${version}";
        hash = "sha256-7MHd9iBOtW/ukciQ5ADfKwcu8afv/3GBjHi5FTMp1QA=";
      };
    });
  };

  firefox = prev.firefox.override {
    nativeMessagingHosts = with final; [
      gnome-browser-connector
      tridactyl-native
    ];
  };

  librewolf = prev.librewolf.override {
    nativeMessagingHosts = with final; [
      gnome-browser-connector
      tridactyl-native
    ];
  };
}
