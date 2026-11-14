# appearance

Light and dark palette switching for every program, driven by one desktop
setting.

When you change Appearance in GNOME Settings, terminals and editors repaint
without a restart. The programs that cannot repaint use the new palette on their
next run. Each program keeps the dark palette it already had. The light
palette is Solarized Light almost everywhere, except NeoVim, which stays
greyscale in both modes.

## The signal

GNOME writes the `color-scheme` key of `org.gnome.desktop.interface`. The XDG
desktop portal serves the same value as `org.freedesktop.appearance`. Both names
describe one setting, and this module keys off that setting alone.

The Light button in GNOME sets `color-scheme` to `default`, not to
`prefer-light`. Only `prefer-dark` means dark mode. Any other value, and any
desktop without the schema, resolves to light.

## Three kinds of program

Each program learns the current mode in one of three ways. Only the third kind
costs any configuration.

Some programs read the portal themselves. Zed, WezTerm, GTK applications, and
Doom Emacs at startup all do this. They need no hook.

Some programs ask the terminal for its background color instead of asking the
desktop. bat, delta, and lazygit do this. They follow for free, because the hook
for Alacritty already changed what the terminal answers.

The rest know nothing about either. They need a hook.

## The option

`dotless.appearance` is a shared slot that any module writes into, and one place
that reads what every module wrote. An option in the Nix module system is a
named setting that several files can assign to. The module system merges those
assignments into one value.

| Option | What it holds |
| --- | --- |
| `enable` | Turns the switching on. Linux only, because the trigger is a GNOME setting |
| `hooks` | Shell snippets keyed by the program they belong to, with `$mode` set to `light` or `dark` |
| `path` | Packages the snippets need on PATH |
| `stateFile` | The file that records the current mode, for programs that read it at startup |

The module itself names no program. It receives a merged set that holds ten
entries today, and it does not know where any of them came from.

## Adding a program

1. Add `imports = [ ./../../appearance ];` to the program's module. The module
   assigns to an option that it does not declare. It must bring the declaration
   with it, or it fails when someone imports it on its own.
2. Assign one entry to `hooks`, named after the program, next to the rest of
   that program's configuration.
3. Add any command the snippet calls to `path`.

The tmux module holds this:

```nix
dotless.appearance.hooks.tmux = ''
  install -m644 "${config.xdg.configHome}/tmux/theme-$mode.conf" …
'';
```

## What runs on a switch

A systemd user service runs `gsettings monitor` and calls `appearance-switch`
each time the key changes. Home Manager activation calls it too, so a new
generation lands in the correct mode.

The script does three things:

1. It reads `color-scheme` and resolves `$mode` to `light` or `dark`.
2. It writes that word to the state file.
3. It runs each hook and prints a warning that names any hook that failed.

Run `appearance-switch light` or `appearance-switch dark` to force a mode by
hand. Without an argument the script reads the GNOME setting.

## Why each hook is a separate script

Every hook is built as its own `writeShellApplication`, not as a block inside
the switch script. Bash turns `errexit` off inside a subshell that is used as an
`if` condition or as an operand of `||`. A hook written that way runs on past
its own failed command, and reports the status of whatever line ran last.

A separate process restores both halves. The hook stops at its first failure,
and the switch script reads a true exit status for it. One program that is
missing or wedged then costs only that program its repaint.

## Writable files

Home Manager links configuration from the Nix store, and store files are
read only. A switch needs a file it can write. Every program here follows one
rule: Home Manager owns the variants, and the hook owns the active copy.

| Shape | Programs |
| --- | --- |
| The program's own include directive | Alacritty (`general.import`), tmux (`source-file`) |
| An environment variable names the path | fzf, opencode, gh-dash |
| Home Manager ships `-dark` and `-light`, the hook writes the real name | diffnav |
| The file is already writable, so rewrite one key in place | herdr, claude-code |
| No file at all, send a message to the running program | NeoVim over its socket, Emacs over emacsclient |

Never write into a path that Home Manager manages. That rule is what keeps
activation and the hook from undoing each other.

## Repaint or next run

Alacritty watches the file it imports, tmux re-sources its theme, and NeoVim and
Emacs are told directly. Those four repaint while you work.

diffnav, opencode, gh-dash, herdr, and claude-code read their configuration once
at startup. They use the new palette the next time you start them. No work is
lost either way.
