# reeve: CLI php shim (reeve php cli <ver>).
#
# Linked to ~/.config/zsh/exports/ only while `reeve` is installed: the
# requirement column in install/links.sh owns that gate, and .zshrc sources the
# directory when it exists. Never hardcode a home directory here.
export PATH="$HOME/.reeve/bin:$PATH"
