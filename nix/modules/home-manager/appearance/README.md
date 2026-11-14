# appearance

Light and dark palettes for every program, from one desktop setting. Dark
palettes are unchanged. Light is Solarized Light, except NeoVim, which is
greyscale in both modes.

## The signal

GNOME writes `color-scheme` in `org.gnome.desktop.interface`, which the XDG
desktop portal serves as `org.freedesktop.appearance`.

Only `prefer-dark` is dark. The Light button sets `default`, not
`prefer-light`, so every other value is light. A missing schema is dark.

## Three kinds of program

Only the third needs configuration.

- Reads the portal: Zed, WezTerm, GTK applications, Doom Emacs at startup.
- Asks the terminal for its background color: bat, delta, lazygit. They follow
  for free, because the Alacritty hook changed that answer.
- Needs a hook: everything else.

## The option

`dotless.appearance` is a shared slot. Several modules assign to it and the
module system merges those assignments into one value, so the module itself
names no program. It reads ten entries today.

| Option | What it holds |
| --- | --- |
| `enable` | Turns switching on. Linux only: the trigger is a GNOME setting |
| `hooks` | Shell snippets keyed by program, with `$mode` set to `light` or `dark` |
| `path` | Packages the snippets need on PATH |
| `stateFile` | Records the current mode, for programs that read it at startup |

## Adding a program

1. Add `imports = [ ./../../appearance ];` to the program's module. It assigns
   to an option it does not declare, so it must carry the declaration.
2. Assign one `hooks` entry named after the program.
3. Add any command the snippet calls to `path`.

```nix
dotless.appearance.hooks.tmux = ''
  install -m644 "${config.xdg.configHome}/tmux/theme-$mode.conf" …
'';
```

## What runs on a switch

A systemd user service runs `gsettings monitor` and calls `appearance-switch`
on every change, as does Home Manager activation. The script resolves `$mode`,
writes it to the state file, then runs each hook and names any that failed.

`appearance-switch light` or `appearance-switch dark` forces a mode. Without an
argument it reads the GNOME setting.

## Why each hook is a separate script

Each hook is built as its own `writeShellApplication`. Bash turns `errexit` off
inside a subshell used as an `if` condition or an `||` operand, so an inline
hook would run past its own failed command and report the wrong status. A
separate process stops at the first failure, so one broken program costs only
its own repaint.

## Writable files

Store files are read only, so Home Manager owns the variants and the hook owns
the active copy. Never write into a path Home Manager manages, or activation
and the hook undo each other.

| Shape | Programs |
| --- | --- |
| The program's own include | Alacritty (`general.import`), tmux (`source-file`) |
| An environment variable names it | fzf, opencode, gh-dash |
| `-dark` and `-light` ship, the hook writes the real name | diffnav |
| Already writable, rewrite one key | herdr, claude-code |
| No file, message the running program | NeoVim over its socket, Emacs over emacsclient |

## Repaint or next run

Alacritty, tmux, NeoVim and Emacs repaint while you work. diffnav, opencode,
gh-dash, herdr and claude-code read their configuration once at startup, so
they change on their next run. No work is lost either way.
