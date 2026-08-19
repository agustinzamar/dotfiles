alias ar="php artisan"
alias mfs="php artisan migrate:fresh --seed"
alias pest='./vendor/bin/pest'
alias pint='./vendor/bin/pint'

alias cu="herd composer update"
alias cr="herd composer require"
alias ci="herd composer install"
alias cda="herd composer dump-autoload -o"

function p() {
  if [ -f vendor/bin/pest ]; then
    vendor/bin/pest "$@"
  else
    vendor/bin/phpunit "$@"
  fi
}

function pestf() {
  if [ -f vendor/bin/pest ]; then
    vendor/bin/pest --filter "$@"
  else
    vendor/bin/phpunit --filter "$@"
  fi
}

function pestp() {
  php artisan test --parallel "$@"
}