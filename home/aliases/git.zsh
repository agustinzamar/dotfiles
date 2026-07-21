alias nah="git reset --hard;git clean -df"
alias push="git push"
alias pull="git pull"
alias gpo="git push origin"
alias uncommit="git reset --soft HEAD~1"
alias branches="git branch --sort=committerdate | head -10"
alias gecor='git checkout $(git branch -a | fzf)'
