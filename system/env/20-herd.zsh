# Herd: PHP binaries, NVM, the shell integration, and the per-version ini dirs.
#
# NVM (loaded below) prepends its Node dir to PATH, so Herd's Node takes
# precedence over /opt/homebrew/bin/node from `brew install node`.

# Ahead of /opt/homebrew/bin, so `php` is Herd's switchable one (php, php82..85)
# rather than whatever Homebrew pulled in as a dependency.
export PATH="$HOME/Library/Application Support/Herd/bin:$PATH"

export NVM_DIR="$HOME/Library/Application Support/Herd/config/nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

[[ -f "/Applications/Herd.app/Contents/Resources/config/shell/zshrc.zsh" ]] &&
  builtin source "/Applications/Herd.app/Contents/Resources/config/shell/zshrc.zsh"

# Herd's chpwd hook calls nvm use, which prepends the active Node version's bin
# directory to PATH. That would shadow the dotfiles wrappers for npm, yarn, npx
# and bun, so keep ~/.dotfiles/bin at the front after every directory change.
_dotfiles-bin-to-front() {
  local d="$HOME/.dotfiles/bin"
  path=("$d" ${path:#$d})
}
autoload -U add-zsh-hook
add-zsh-hook chpwd _dotfiles-bin-to-front
_dotfiles-bin-to-front

# Hard-coded to $HOME rather than a literal path so this works on any machine.
export HERD_PHP_85_INI_SCAN_DIR="$HOME/Library/Application Support/Herd/config/php/85/"
export HERD_PHP_84_INI_SCAN_DIR="$HOME/Library/Application Support/Herd/config/php/84/"
export HERD_PHP_83_INI_SCAN_DIR="$HOME/Library/Application Support/Herd/config/php/83/"
