alias gpo="git push origin"
alias ghopen='gh repo view --web'
alias uncommit="git reset --soft HEAD~1"
alias gecor='git checkout $(git branch -a | fzf)'
alias lg='lazygit'

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