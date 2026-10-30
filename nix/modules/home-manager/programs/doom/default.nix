{
  profile,
  config,
  lib,
  ...
}:

let
  cfg = config.dotless.editors.doom;

  bundled = ./../../../../../config/doom;
  partsDir = "modules/config/dotless/parts";

  # Per-item live-override convention (mirrors claude-code). profile.liveOverrides.doom
  # is either `true` - symlink the consumer's whole doom dir, dotless writes nothing -
  # or a list of paths relative to doom-user-dir, each symlinked live (out-of-store →
  # editable, `doom reload` picks it up, no rebuild) with dotless's own version turned
  # off so there is one owner per path. Listing a directory covers everything under it.
  #
  # DECLARED, not detected: probing the live tree with builtins.pathExists is impure and
  # aborts eval in CI. TODO(dotless#48): pure, shared live-override mechanism.
  live = profile.liveOverrides.doom or [ ];
  wholeDir = live == true;
  liveList = if lib.isList live then live else [ ];
  isLive = rel: builtins.any (p: p == rel || lib.hasPrefix "${p}/" rel) liveList;

  userDoomDir = "${config.home.homeDirectory}/${profile.flakeRoot}/config/doom";
  customFile = "${config.xdg.configHome}/doom/${profile.login}-custom.el";

  # The doom-user-dir layer, authored as elisp under config/doom/user. Nix reads
  # these, it does not write elisp: init.el is a template, the other two take
  # the consumer's extra* appended.
  userLayer = bundled + "/user";
  customSeed = userLayer + "/custom-seed.el";

  # doom! takes one flat list: keywords open a category, the rest are modules.
  renderModules = lib.concatMapStrings (
    m: if lib.hasPrefix ":" m then "\n       ${m}\n" else "       ${m}\n"
  );

  initText = lib.replaceStrings [ "@MODULES@" ] [ (renderModules cfg.modules) ] (
    builtins.readFile (userLayer + "/init.el")
  );

  configText =
    builtins.readFile (userLayer + "/config.el")
    + lib.optionalString (cfg.extraConfig != "") "\n${cfg.extraConfig}";

  packagesText =
    builtins.readFile (userLayer + "/packages.el")
    + lib.optionalString (cfg.extraPackages != "") "\n${cfg.extraPackages}";

  # The module's own config.el is a load list, so dropping a part from the Nix
  # option drops the file from the sequence - no elisp conditionals.
  moduleConfigText = ''
    ;;; config/dotless/config.el -*- lexical-binding: t; -*-
    ;; Generated from dotless.editors.doom.parts.

  ''
  + lib.concatMapStrings (p: "(load! \"parts/${p}\")\n") cfg.parts;

  # Every path dotless owns under doom-user-dir, as published path → file attrs.
  # Consumer-overridden paths drop out, leaving the live symlink as sole owner.
  managed = {
    "init.el".text = initText;
    "config.el".text = configText;
    "packages.el".text = packagesText;
    "modules/config/dotless/config.el".text = moduleConfigText;
    "modules/config/dotless/packages.el".source = bundled + "/modules/config/dotless/packages.el";
    "modules/config/dotless/lisp/ztd.el".source = bundled + "/modules/config/dotless/lisp/ztd.el";
    "modules/config/dotless/lisp/zutil.el".source = bundled + "/modules/config/dotless/lisp/zutil.el";
    "${partsDir}/identity.el".text = ''
      ;;; parts/identity.el -*- lexical-binding: t; -*-

      (setopt user-full-name "${profile.name}"
              user-mail-address "${profile.email}")
    '';
  }
  // lib.listToAttrs (
    map (p: {
      name = "${partsDir}/${p}.el";
      value.source = bundled + "/${partsDir}/${p}.el";
    }) (lib.filter (p: p != "identity") cfg.parts)
  )
  // lib.listToAttrs (
    map (t: {
      name = "themes/${t}";
      value.source = bundled + "/themes/${t}";
    }) cfg.themes
  )
  // lib.listToAttrs (
    map (s: {
      name = "snippets/${s}";
      value.source = bundled + "/snippets/${s}";
    }) cfg.snippets
  )
  // cfg.extraFiles;
in

{
  options.dotless.editors.doom = {
    enable = lib.mkEnableOption "the dotless Doom Emacs configuration" // {
      default = config.programs.emacs.enable;
      defaultText = lib.literalExpression "config.programs.emacs.enable";
    };

    modules = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = ''
        Entries of init.el's `doom!' form, in order. An entry starting with ":"
        opens a category; the rest are modules, written as Doom writes them
        (`vertico', `(corfu +orderless)'). Run `doom sync' after a change.
      '';
      default = [
        ":completion"
        "(corfu +orderless)"
        "vertico"

        ":ui"
        "doom"
        "dashboard"
        "hl-todo"
        "indent-guides"
        "(modeline +light)"
        "ophints"
        "(popup +defaults)"
        "(treemacs +lsp)"
        "(vc-gutter +pretty)"
        "vi-tilde-fringe"
        "workspaces"
        "zen"

        ":editor"
        "(evil +everywhere)"
        "file-templates"
        "fold"
        "(format +lsp +onsave)"
        "lispy"
        "multiple-cursors"
        "snippets"

        ":emacs"
        "(dired +icons)"
        "electric"
        "undo"
        "vc"

        ":term"
        "vterm"

        ":checkers"
        "syntax"
        "(spell +aspell)"

        ":tools"
        "ansible"
        "direnv"
        "docker"
        "(eval +overlay)"
        "llm"
        "lookup"
        "lsp"
        "(magit +forge)"
        "pdf"
        "terraform"

        ":os"
        "(:if IS-MAC macos)"

        ":lang"
        "(cc +lsp)"
        "(clojure +lsp)"
        "common-lisp"
        "dhall"
        "emacs-lisp"
        "(graphql +lsp)"
        "(haskell +lsp)"
        "json"
        "(javascript +lsp)"
        "(lua +lsp)"
        "markdown"
        "(nix +lsp)"
        "(org +crypt +noter)"
        "(python +lsp +pyright)"
        "(rust +lsp)"
        "(sh +lsp)"
        "(web +lsp +html +css)"
        "yaml"

        ":email"
        "(notmuch +org)"

        ":config"
        # `dotless' last: `default's +bindings load first, so dotless wins the
        # keys both touch, and doom-user-dir's own config.el still loads after.
        "(default +bindings +smartparens)"
        "dotless"
      ];
    };

    parts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = ''
        Chunks of dotless's Doom config to load, in order. Each name is a file
        under modules/config/dotless/parts. Drop a name to drop that chunk.
      '';
      default = [
        "identity"
        "locale"
        "lisp"
        "fonts"
        "theme"
        "line-numbers"
        "org-paths"
        "auth"
        "spell"
        "editing"
        "world-clock"
        "incremental"
        "notmuch"
        "org-mime"
        "evil"
        "vertico"
        "dired"
        "flycheck"
        "treemacs"
        "projectile"
        "workspaces"
        "forge"
        "magit"
        "smerge"
        "code-review"
        "so-long"
        "magit-hooks"
        "gptel-magit"
        "ui-misc"
        "eww-org"
        "org"
        "org-keys"
        "markdown"
        "cc"
        "apheleia"
        "spell-fu"
        "sql"
        "haskell"
        "keys-global"
        "drag-stuff"
        "pdf"
        "lsp"
        "auto-mode"
        "sly"
        "lispy"
        "clojure"
        "emmet"
        "vterm"
        "gptel"
        "claude-code-ide"
        "linear"
        "frames"
        "nitpick"
        "forge-worktree"
        "kiwix"
      ];
    };

    themes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "Theme files to place in doom-user-dir/themes.";
      default = [
        "default-black-theme.el"
        "kanagawa-theme.el"
        "prez-theme.el"
      ];
    };

    snippets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "Snippet files to place in doom-user-dir/snippets, path included.";
      default = [
        "haskell-mode/liftPutStrLn"
        "haskell-mode/putStrLn"
      ];
    };

    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = ''
        Elisp appended to doom-user-dir/config.el, which loads after every part.
      '';
    };

    extraPackages = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = ''
        `package!' declarations appended to doom-user-dir/packages.el.
      '';
    };

    extraFiles = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = ''
        Extra files under doom-user-dir, as xdg.configFile attrs keyed by path
        relative to it - a consumer's own private Doom module, say.
      '';
      example = lib.literalExpression ''
        { "modules/config/mine/config.el".source = ./doom/mine-config.el; }
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = lib.all (p: builtins.pathExists (bundled + "/${partsDir}/${p}.el")) (
              lib.filter (p: p != "identity") cfg.parts
            );
            message = "dotless.editors.doom.parts names a chunk dotless does not ship.";
          }
        ];

        # `doom sync' writes nothing here, but Emacs writes custom-file, and
        # `doom reload' reads whatever is on disk - so link files, never the
        # directory: ~/.config/doom stays a real, writable directory.
        xdg.configFile = lib.mkIf (!wholeDir) (
          lib.mapAttrs' (rel: v: lib.nameValuePair "doom/${rel}" v) (
            lib.filterAttrs (rel: _: !isLive rel) managed
          )
          // lib.listToAttrs (
            map (rel: {
              name = "doom/${rel}";
              value.source = config.lib.file.mkOutOfStoreSymlink "${userDoomDir}/${rel}";
            }) liveList
          )
        );

        # Last-resort full replace: the consumer owns the whole directory.
        home.file.doom = lib.mkIf wholeDir {
          source = config.lib.file.mkOutOfStoreSymlink userDoomDir;
          target = "${config.xdg.configHome}/doom";
        };
      }

      # custom-file has to exist and be writable before Emacs loads it. Seed it
      # from the consumer's own doom dir when that copy is there, so an existing
      # customize layer survives the move off the directory symlink.
      (lib.mkIf (!wholeDir && !isLive "${profile.login}-custom.el") {
        home.activation.doomCustomFile = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          if [[ ! -e "${customFile}" ]]; then
            if [[ -f "${userDoomDir}/${profile.login}-custom.el" ]]; then
              run install -Dm0644 "${userDoomDir}/${profile.login}-custom.el" "${customFile}"
            else
              run install -Dm0644 ${customSeed} "${customFile}"
            fi
          fi
        '';
      })
    ]
  );
}
