# appearance

Light and dark palettes for every program, from one desktop setting. Dark
palettes are unchanged. Light is Solarized Light, except NeoVim, which is
greyscale in both modes.

## The signal

The XDG desktop portal serves `color-scheme` in the
`org.freedesktop.appearance` namespace. GNOME, KDE, Hyprland and sway each
ship a backend for it, and `darkman` is a backend for a session with no
desktop of its own, so one source covers them all. It is also the source Zed,
WezTerm and GTK already read.

The portal answers with a number: 1 is dark, 2 is light, and 0 means the
desktop has no preference.

`gsettings get org.gnome.desktop.interface color-scheme` is the last resort,
because dconf answers where no portal runs at all. There, only `prefer-dark`
is dark. The Light button sets `default`, not `prefer-light`, so every other
value is light. No answer from either is dark.

## Providers

A provider is one pair of actions: read the mode, and watch for a change.
Everything desktop-specific lives in one, and nothing else in the module names
a desktop.

| Field | What it holds |
| --- | --- |
| `detect` | Shell that prints `light` or `dark`, and nothing else |
| `watch` | Long-running shell that calls `appearance-switch auto` per change |
| `path` | Packages the two need on PATH |

`provider = "auto"` picks the one for the platform. The set is open, so a
desktop dotless does not ship can add its own pair from a consumer's
configuration and name it:

```nix
dotless.appearance.provider = "sway-idle";
dotless.appearance.providers.sway-idle = {
  detect = "…";
  path = [ pkgs.foo ];
};
```

A provider with no `watch` leaves the mode to an explicit
`appearance-switch light` or `appearance-switch dark`, from a key binding.
The module keeps the supervision, so a provider never knows about systemd.

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
| `enable` | Turns switching on. Linux only today |
| `provider` | Which `providers` entry supplies the mode, or `auto` |
| `providers` | The sources themselves, keyed by the environment they read |
| `hooks` | Shell snippets keyed by program, with `$mode` set to `light` or `dark` |
| `path` | Packages the snippets need on PATH |
| `fallbacks` | Dark palettes to install where switching is off |
| `watchTarget` | The systemd user target the watcher binds to |
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

A systemd user service runs the provider's watcher, which calls
`appearance-switch` on every change, as does Home Manager activation. The
script resolves `$mode`, writes it to the state file, then runs each hook and
names any that failed.

On the portal the watcher uses a D-Bus match rule, so the bus filters and no
other setting wakes it. Where no portal answers it falls back to `gsettings
monitor`. It decides which once at start, because a session either serves the
portal or it does not.

`appearance-switch light` or `appearance-switch dark` forces a mode. Without an
argument it asks the provider.

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

## Where switching is off

With `enable = false` nothing repaints, so a program whose palette only a hook
writes would fall back to its own built-in theme. `fallbacks` installs the dark
palette into that same path on every activation instead. Every activation, not
once, because a new generation may have changed the palette and nothing else
would ever update it.

This is why tmux showed its stock green status bar on macOS: `source-file -q`
reports no error for a file that is not there.

## Repaint or next run

Alacritty, tmux, NeoVim and Emacs repaint while you work. diffnav, opencode,
gh-dash, herdr and claude-code read their configuration once at startup, so
they change on their next run. No work is lost either way.
