git-prune-local() {
  git fetch -p && git branch -vv | grep ': gone]' | awk '{print $1}' | xargs git branch -D
}

ghopen() {
  local url=$(git config --get remote.origin.url | sed -E 's/git@github.com:(.*)\.git/https:\/\/github.com\/\1/')
  open "$url"
}

clone() {
  if [ $# -eq 0 ]; then
    local repo=$(gh api "user/repos?per_page=200&type=all" --jq '.[].full_name' 2>/dev/null | fzf --prompt="Clone repo: ")
    [ -n "$repo" ] && gh repo clone "$repo"
  else
    gh repo clone "$1" "${@:2}"
  fi
}

pr() {
  if git branch --show-current >/dev/null 2>&1; then
    gh pr view --web 2>/dev/null || gh pr create --web
  else
    echo "Not in a git repository or no current branch."
    return 1
  fi
}
