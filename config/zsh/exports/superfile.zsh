# Superfile's cd-on-quit integration for zsh.
#
# With `cd_on_quit = true` (config/superfile/config.toml), superfile writes a
# shell snippet (`cd '<dir>'`) to its lastdir file on exit. Sourcing and then
# removing that file moves the shell to superfile's last file panel. This
# mirrors the wrapper upstream ships for v1.6.0
# (superfile `cd_on_quit/cd_on_quit.sh`); `status` is read-only in zsh, so the
# official snippet's exit-code variable is not used here.
#
# Linked into ~/.config/zsh/exports/ only while `spf` is installed: the
# requirement column in install/links.sh owns that gate.
spf() {
  local spf_last_dir
  if [[ "$(uname -s)" == "Darwin" ]]; then
    spf_last_dir="${XDG_STATE_HOME:-$HOME/Library/Application Support}/superfile/lastdir"
  else
    spf_last_dir="${XDG_STATE_HOME:-$HOME/.local/state}/superfile/lastdir"
  fi

  command spf "$@"

  [[ -f "$spf_last_dir" ]] || return 0
  # The file holds a `cd '...'` snippet written by superfile itself.
  # shellcheck disable=SC1090
  . "$spf_last_dir"
  rm -f -- "$spf_last_dir"
}
