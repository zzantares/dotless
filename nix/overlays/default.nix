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

  boom = final.callPackage ./../pkgs/boom { };

  # diffnav ships hardcoded vim keybindings (pkg/ui/keys.go) with no config
  # hook, so the only way to get the Colemak nav scheme used elsewhere in this
  # config (h=up, k=down, j=left, l=right; cf. gh-dash, aerospace) is to rewrite
  # the key strings at build time.
  diffnav = prev.diffnav.overrideAttrs (old: {
    # `--replace-fail` makes the build fail loudly if upstream reworks these lines
    # on a `nix flake update` — the signal to re-sync this patch — rather than
    # silently reverting to vim defaults.
    #
    # The append is guarded on a sentinel so it is idempotent: this overlay can
    # be composed onto the same pkgs set more than once (e.g. a NixOS config
    # that imports both the `nix` module and a base preset, each of which adds
    # dotless.overlays.default), which runs this overrideAttrs twice. Without
    # the guard the second pass re-appends the block and --replace-fail aborts,
    # because the first pass already rewrote 'k' -> 'h' etc.
    postPatch =
      (old.postPatch or "")
      +
        final.lib.optionalString
          (!(final.lib.hasInfix "colemak keybindings for diffnav" (old.postPatch or "")))
          ''
            # colemak keybindings for diffnav
            substituteInPlace pkg/ui/keys.go \
              --replace-fail 'key.WithKeys("up", "k"),' 'key.WithKeys("up", "h"),' \
              --replace-fail 'key.WithKeys("down", "j"),' 'key.WithKeys("down", "k"),' \
              --replace-fail 'key.WithKeys("h"),' 'key.WithKeys("j"),' \
              --replace-fail 'key.WithHelp("↑/k", "prev file"),' 'key.WithHelp("↑/h", "prev file"),' \
              --replace-fail 'key.WithHelp("↓/j", "next file"),' 'key.WithHelp("↓/k", "next file"),' \
              --replace-fail 'key.WithHelp("h", "collapse"),' 'key.WithHelp("j", "collapse"),'
            substituteInPlace pkg/ui/panes/filetree/keys.go \
              --replace-fail 'key.WithKeys("h"),' 'key.WithKeys("j"),' \
              --replace-fail 'key.WithHelp("h", "collapse"),' 'key.WithHelp("j", "collapse"),'
          '';
  });

  tea-dash = final.callPackage ./../pkgs/tea-dash { };

  # v0.1.7 has a dbus screensaver-inhibit ref-counting bug (logs "BUG THIS:
  # inhibit locks < 0: -1", triggered by apps like Firefox rapidly toggling
  # inhibit during video playback). Once it fires, listener state gets
  # corrupted and some timeout listeners — e.g. a "dpms off" rule shortly
  # after a lock rule — silently stop firing for the rest of the session, so
  # the screen locks but the display never turns off. Fixed upstream in
  # hyprwm/hypridle#175 ("core: fix dbus inhibit lock counting"), merged
  # 2025-11-01, not yet in a tagged release. Track main until v0.1.8 ships.
  hypridle = prev.hypridle.overrideAttrs (_: {
    version = "0.1.7-unstable-2026-07-25";
    src = final.fetchFromGitHub {
      owner = "hyprwm";
      repo = "hypridle";
      rev = "6c119c280e19522b61d28e74626ef2134acd39d5";
      hash = "sha256-MbOcUbVyZ8bfhe5rKKzax2VVBgLXZOJJHlQnOXJKwhM=";
    };
  });

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
    if prev.stdenv.hostPlatform.isLinux then
      (inputs.opencode.packages.${system}.default).overrideAttrs (old: {
        # Both appends below are sentinel-guarded so they stay idempotent when
        # this overlay is composed onto the same pkgs set twice (see the diffnav
        # note above): a second pass would otherwise re-run --replace-fail on an
        # already-patched build.ts and re-`mv` an already-moved binary.
        postPatch =
          (old.postPatch or "")
          +
            final.lib.optionalString
              (!(final.lib.hasInfix "opencode cross-platform build patch" (old.postPatch or "")))
              ''
                # opencode cross-platform build patch
                substituteInPlace packages/opencode/script/build.ts \
                  --replace-fail \
                    'if (item.os === process.platform && item.arch === process.arch && !item.abi) {' \
                    'if (false) {'
              '';

        postInstall = "";
        doInstallCheck = false;

        postFixup =
          (old.postFixup or "")
          + final.lib.optionalString (!(final.lib.hasInfix ".opencode-bun" (old.postFixup or ""))) ''
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

  # Attach to the tmux server's most-recently-used session if one exists,
  # otherwise start a fresh one named after the current user and host.
  tux = final.writeShellScriptBin "tux" ''
    #!/usr/bin/env bash
    if ${final.tmux}/bin/tmux -q has-session 2>/dev/null; then
      exec ${final.tmux}/bin/tmux attach-session -d
    else
      exec ${final.tmux}/bin/tmux new-session -s "$USER@$HOSTNAME"
    fi
  '';

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

  wallpapers = final.callPackage ./../pkgs/wallpapers { };

  # Zed's flake pins cargo-about to 0.8.2 (via overrideAttrs) but inherits
  # buildFeatures from the surrounding nixpkgs' cargo-about recipe. Since
  # nixpkgs bumped cargo-about to 0.9.0 — which moved the CLI behind a `cli`
  # feature — the inherited `buildFeatures = [ "cli" ]` breaks the 0.8.2 build
  # ("does not contain this feature: cli"). We follow nixpkgs (needed for the
  # crates.io User-Agent fix in fetch-cargo-vendor-util), so strip that feature
  # from the cargo-about Zed receives before it pins the version down.
  zed-editor = inputs.zed-editor.packages.${system}.default.override {
    cargo-about = final.cargo-about.overrideAttrs (_: {
      buildFeatures = [ ];
      cargoBuildFeatures = [ ];
      checkFeatures = [ ];
      cargoCheckFeatures = [ ];
    });
  };

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
      paths = prev.lib.optionals prev.stdenv.hostPlatform.isLinux (
        with final;
        [
          (symlinkJoin {
            name = "android-studio-wrapped";
            paths = [ android-studio ];
            buildInputs = [ makeWrapper ];
            postBuild = ''
              wrapProgram $out/bin/android-studio \
                --prefix PATH : ${glib}/bin
            '';
          })
        ]
      );
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

    ocaml = final.buildEnv {
      name = "ocaml-toolchain";
      paths = with final; [
        ocaml
        dune
        opam
        ocamlPackages.ocaml-lsp
        ocamlPackages.merlin
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
        ]
        ++ prev.lib.optionals prev.stdenv.hostPlatform.isLinux [
          # CGO_ENABLED=1 builds — require Linux/Darwin SDK; primarily server-side daemons
          nomad
          consul
          vault
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
        ++ prev.lib.optionals prev.stdenv.hostPlatform.isLinux [
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
        mdbook
        mdbook-mermaid
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
// prev.lib.optionalAttrs prev.stdenv.hostPlatform.isLinux {
  gnomeExtensions = prev.gnomeExtensions // {
    # auto-move-windows only *assigns* a window to its workspace: it moves the
    # window but leaves you on the current one (i3 `assign`). Patch it to also
    # activate the target workspace after the move, so focus follows the app to
    # its slot (like Hyprland launching onto its bound workspace). Upstream exposes
    # no gsetting for this — the move lives in WindowMover._moveWindow's
    # change_workspace_by_index call.
    auto-move-windows-follow = prev.gnomeExtensions.auto-move-windows.overrideAttrs (old: {
      postPatch = (old.postPatch or "") + ''
        substituteInPlace extension.js --replace-fail \
          'window.change_workspace_by_index(workspaceNum, false);' \
          'window.change_workspace_by_index(workspaceNum, false);
                global.workspace_manager.get_workspace_by_index(workspaceNum).activate(global.get_current_time());'
      '';
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
// prev.lib.optionalAttrs prev.stdenv.hostPlatform.isDarwin {
  # Emacs 30 + emacs-plus's macOS patches, and the applet that hands files and
  # org-protocol URLs to the daemon. Both are darwin-only, so Linux consumers
  # keep stock `pkgs.emacs`; the emacs home module wires them up per platform.
  emacs-plus = final.callPackage ./../pkgs/emacs-plus { };

  # `emacs` defaults to the unwrapped build here; the module overrides it with
  # `programs.emacs.finalPackage` so the applet talks to the emacsclient that
  # actually ships the user's packages.
  emacs-client = final.callPackage ./../pkgs/emacs-client { emacs = final.emacs-plus; };
}
