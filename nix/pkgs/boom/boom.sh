# shellcheck shell=bash
#
# boom - bootstrap Doom: install, upgrade and activate Doom Emacs.
#
# Usage:
#   boom install    clone Doom into $DOOM_DIR, run doom install + sync
#   boom upgrade    re-clone and reinstall, rolling back on failure
#   boom activate   clear a stray ~/.emacs.d and restart the daemon
#
# install and upgrade both activate when they finish. Nix owns the Emacs binary
# and the daemon; Doom itself is a git checkout, which is why this is a script
# and not a derivation.
#
# Environment: DOOM_DIR (default $XDG_CONFIG_HOME/emacs), DOOM_REPO, DOOM_REF.

# The Emacs module of dotless's shared shell library; wt_emacs_restart branches
# launchd vs systemd. DOTLESS_SH_LIB is the library directory in the store,
# exported by the wrapper - not the copy the zsh module installs under
# ~/.local/lib/sh, so this script works without that module.
# shellcheck source=/dev/null
source "$DOTLESS_SH_LIB/emacs.sh"

# macOS GUI processes do not inherit the shell environment, so Doom needs its
# own envvars file there; on Linux the daemon gets its environment from systemd.
# --aot native-compiles ahead of time rather than on first use of each file.
case "$OSTYPE" in
	darwin*) doom_install_flags=(--aot --env) ;;
	*) doom_install_flags=(--no-env) ;;
esac

doom_repo="${DOOM_REPO:-https://github.com/doomemacs/doomemacs}"
doom_ref="${DOOM_REF:-master}"
doom_dir="${DOOM_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/emacs}"
tmp="${TMPDIR:-/tmp}"

die() {
	echo "boom: $*" >&2
	exit 1
}

usage() {
	cat >&2 <<'EOF'
usage:
  boom install    clone Doom, then run `doom install` and `doom sync`
  boom upgrade    re-clone and reinstall, restoring the old checkout if either
                  step fails
  boom activate   move a stray ~/.emacs.d aside and restart the Emacs daemon so
                  it picks Doom up
EOF
}

# Clone + set up. Kept as one unit so `upgrade` can roll back on either half.
install_doom() {
	git clone --depth 1 --branch "$doom_ref" "$doom_repo" "$doom_dir" &&
		"$doom_dir/bin/doom" install "${doom_install_flags[@]}" &&
		"$doom_dir/bin/doom" sync
}

# Emacs prefers ~/.emacs.d over the XDG dir whenever it exists, and the daemon
# starts at login - before Doom is ever installed - so it creates ~/.emacs.d and
# then shadows Doom permanently. Move it aside, then restart so emacsclient
# frames come up as Doom rather than the stock Emacs the daemon started as.
cmd_activate() {
	if [[ -e "$HOME/.emacs.d" ]]; then
		local stray
		stray="$tmp/dot-emacs.d-$(date +%Y%m%d-%H%M%S)"
		mv "$HOME/.emacs.d" "$stray"
		echo "moved stray ~/.emacs.d aside to $stray (it was shadowing $doom_dir)"
	fi

	if wt_emacs_restart; then
		echo "restarted the Emacs daemon so it picks up Doom"
	else
		# No unit or agent yet (e.g. mid-onboarding, before the first
		# activation) is fine - there is simply no daemon to restart.
		echo "no Emacs daemon to restart"
	fi
}

cmd_install() {
	[[ -e "$doom_dir" ]] && die "$doom_dir already exists - use 'boom upgrade'"

	install_doom || die "install failed; $doom_dir is left in place for inspection"

	cmd_activate
	echo "Doom installed at $doom_dir"
}

cmd_upgrade() {
	[[ -d "$doom_dir" ]] || die "no Doom at $doom_dir - run 'boom install' first"

	local backup
	backup="$tmp/emacs-$(date +%Y%m%d-%H%M%S)"
	mv "$doom_dir" "$backup"
	echo "previous configuration backed up at $backup"

	if ! install_doom; then
		rm -rf "${doom_dir:?}"
		mv "$backup" "$doom_dir"
		cmd_activate
		die "upgrade failed, rolled back to the previous configuration"
	fi

	cmd_activate
	echo "Doom upgraded at $doom_dir (previous checkout: $backup)"
}

case "${1:-}" in
	install) cmd_install ;;
	upgrade) cmd_upgrade ;;
	activate) cmd_activate ;;
	-h | --help | help)
		usage
		exit 0
		;;
	*)
		usage
		exit 1
		;;
esac
