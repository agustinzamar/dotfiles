alias ar="php artisan"
alias mfs="php artisan migrate:fresh --seed"

alias cu="herd composer update"
alias cr="herd composer require"
alias ci="herd composer install"
alias cda="herd composer dump-autoload -o"

function pint() {
  if [ -f vendor/bin/pint ]; then
    vendor/bin/pint "$@"
  else
    echo "Pint is not installed. Please run 'herd composer require laravel/pint' to install it."
  fi
}

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