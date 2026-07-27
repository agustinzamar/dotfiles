#!/usr/bin/env bash
set -Eeuo pipefail

DOTFILES_DIR=${1:?missing dotfiles directory}
DRY_RUN=${2:-false}
VARS_FILE="$HOME/.dotfiles-custom/vars.json"

read_var() { [[ -f "$VARS_FILE" ]] && jq -r --arg key "$1" '.[$key] // empty' "$VARS_FILE"; }
ask_var() {
  local key=$1 value
  value=$(read_var "$key")
  if [[ -z "$value" && "$DRY_RUN" == false ]]; then
    read -r -p "$key: " value
    mkdir -p "$(dirname "$VARS_FILE")"
    [[ -f "$VARS_FILE" ]] || printf '{}' > "$VARS_FILE"
    jq --arg key "$key" --arg value "$value" '.[$key]=$value' "$VARS_FILE" > "$VARS_FILE.tmp"
    mv "$VARS_FILE.tmp" "$VARS_FILE"
    chmod 600 "$VARS_FILE"
  fi
  printf '%s' "$value"
}

run() {
  if [[ "$DRY_RUN" == true ]]; then
    printf '+ '; printf '%q ' "$@"; printf '\n'
  else
    "$@"
  fi
}

link_generated() {
  local source=$1 target=$2
  if [[ "$DRY_RUN" == true ]]; then
    printf '+ ln -s %q %q\n' "$source" "$target"
    return
  fi
  mkdir -p "$(dirname "$target")"
  if [[ -e "$target" || -L "$target" ]]; then
    mv "$target" "$target.backup"
  fi
  ln -s "$source" "$target"
}

name=$(ask_var GitName)
email=$(ask_var GitEmail)
gpg_key=$(ask_var GitGPGKey)
pat=$(ask_var GitHubPAT)

[[ -n "$name" ]] && run git config --global user.name "$name"
[[ -n "$email" ]] && run git config --global user.email "$email"
run git config --global core.pager "hunk pager"
run git config --global core.autocrlf input
run git config --global push.autoSetupRemote true
run git config --global help.autocorrect immediate
if [[ -n "$gpg_key" ]]; then
  run git config --global user.signingkey "$gpg_key"
  run git config --global commit.gpgsign true
fi
command -v gh >/dev/null 2>&1 && run gh auth setup-git

if [[ "$DRY_RUN" == false ]]; then
  mkdir -p "$DOTFILES_DIR/config/opencode"
  jq --arg pat "$pat" 'walk(if type == "string" then gsub("\\{\\{ \\.GitHubPAT \\}\\}"; $pat) else . end)' "$DOTFILES_DIR/config/opencode/opencode.json" > "$DOTFILES_DIR/config/opencode/opencode.rendered.json"
  chmod 600 "$DOTFILES_DIR/config/opencode/opencode.rendered.json"
  {
    printf '[user]\n\tname = %s\n\temail = %s\n' "$name" "$email"
    [[ -n "$gpg_key" ]] && printf '\tsigningkey = %s\n' "$gpg_key"
    printf '[core]\n\tautocrlf = input\n\tpager = hunk pager\n[credential "https://github.com"]\n\thelper =\n\thelper = !/opt/homebrew/bin/gh auth git-credential\n[credential "https://gist.github.com"]\n\thelper =\n\thelper = !/opt/homebrew/bin/gh auth git-credential\n[push]\n\tautoSetupRemote = true\n[help]\n\tautocorrect = immediate\n'
    [[ -n "$gpg_key" ]] && printf '[commit]\n\tgpgsign = true\n'
  } > "$DOTFILES_DIR/config/git/.gitconfig.rendered"
  chmod 600 "$DOTFILES_DIR/config/git/.gitconfig.rendered"
else
  echo '+ render config/git/.gitconfig.rendered'
fi

link_generated "$DOTFILES_DIR/config/git/.gitconfig.rendered" "$HOME/.gitconfig"
link_generated "$DOTFILES_DIR/config/opencode/opencode.rendered.json" "$HOME/.config/opencode/opencode.json"
