# Suffix aliases: open files with the right pager by extension
# (zsh only — `alias -s` is a zsh feature)

# JSON / YAML → jless (interactive JSON/YAML pager)
alias -s json=jless
alias -s jsonc=jless
alias -s yaml=jless
alias -s yml=jless

# Markdown / prose → bat (syntax-highlighted pager)
alias -s md=bat
alias -s mdx=bat
alias -s txt=bat
alias -s log=bat

# Common config files → bat
alias -s ini=bat
alias -s toml=bat
alias -s conf=bat
alias -s config=bat
alias -s env=bat
