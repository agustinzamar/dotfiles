# Herd: PHP binaries, NVM, the shell integration, and the per-version ini dirs.

# Ahead of /opt/homebrew/bin, so `php` is Herd's switchable one (php, php82..85)
# rather than whatever Homebrew pulled in as a dependency.
export PATH="$HOME/Library/Application Support/Herd/bin:$PATH"

export NVM_DIR="$HOME/Library/Application Support/Herd/config/nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

[[ -f "/Applications/Herd.app/Contents/Resources/config/shell/zshrc.zsh" ]] &&
  builtin source "/Applications/Herd.app/Contents/Resources/config/shell/zshrc.zsh"

# Hard-coded to $HOME rather than a literal path so this works on any machine.
export HERD_PHP_85_INI_SCAN_DIR="$HOME/Library/Application Support/Herd/config/php/85/"
export HERD_PHP_84_INI_SCAN_DIR="$HOME/Library/Application Support/Herd/config/php/84/"
export HERD_PHP_83_INI_SCAN_DIR="$HOME/Library/Application Support/Herd/config/php/83/"
