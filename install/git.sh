#!/usr/bin/env bash
# Git identity and the generated gitconfig. Sourced by bin/dot.
#
# Private values live in ~/.dotfiles-custom/vars.json (mode 0600) and are
# prompted for once. The rendered output stays ignored by Git.

VARS_FILE="$HOME/.dotfiles-custom/vars.json"

read_var() { [[ -f "$VARS_FILE" ]] && jq -r --arg key "$1" '.[$key] // empty' "$VARS_FILE"; }

ask_var() {
  local key=$1 value
  value=$(read_var "$key")
  if [[ -z "$value" ]] && ! "$DRY_RUN"; then
    read -r -p "$key: " value
    mkdir -p "$(dirname "$VARS_FILE")"
    [[ -f "$VARS_FILE" ]] || printf '{}' >"$VARS_FILE"
    jq --arg key "$key" --arg value "$value" '.[$key]=$value' "$VARS_FILE" >"$VARS_FILE.tmp"
    mv "$VARS_FILE.tmp" "$VARS_FILE"
    chmod 600 "$VARS_FILE"
  fi
  printf '%s' "$value"
}

render_git_config() {
  local name=$1 email=$2 gpg_key=$3
  {
    printf '[user]\n\tname = %s\n\temail = %s\n' "$name" "$email"
    if [[ -n "$gpg_key" ]]; then printf '\tsigningkey = %s\n' "$gpg_key"; fi
    printf '[core]\n\tautocrlf = input\n\tpager = hunk pager\n[credential "https://github.com"]\n\thelper =\n\thelper = !/opt/homebrew/bin/gh auth git-credential\n[credential "https://gist.github.com"]\n\thelper =\n\thelper = !/opt/homebrew/bin/gh auth git-credential\n[push]\n\tautoSetupRemote = true\n[help]\n\tautocorrect = immediate\n'
    if [[ -n "$gpg_key" ]]; then printf '[commit]\n\tgpgsign = true\n'; fi
  } >"$DOTFILES_DIR/config/git/.gitconfig.rendered"
  chmod 600 "$DOTFILES_DIR/config/git/.gitconfig.rendered"
}

setup_git() {
  local name email gpg_key
  name=$(ask_var GitName)
  email=$(ask_var GitEmail)
  gpg_key=$(ask_var GitGPGKey)

  # if/fi rather than `&&`: inside a function under `set -e`, an unset value
  # would abort the run instead of just skipping that setting.
  if [[ -n "$name" ]]; then run git config --global user.name "$name"; fi
  if [[ -n "$email" ]]; then run git config --global user.email "$email"; fi
  run git config --global core.pager "hunk pager"
  run git config --global core.autocrlf input
  run git config --global push.autoSetupRemote true
  run git config --global help.autocorrect immediate
  if [[ -n "$gpg_key" ]]; then
    run git config --global user.signingkey "$gpg_key"
    run git config --global commit.gpgsign true
  fi
  if command -v gh >/dev/null 2>&1; then run gh auth setup-git; fi

  if "$DRY_RUN"; then
    echo '+ render config/git/.gitconfig.rendered'
  else
    render_git_config "$name" "$email" "$gpg_key"
  fi

  link_file config/git/.gitconfig.rendered "$HOME/.gitconfig"
}
