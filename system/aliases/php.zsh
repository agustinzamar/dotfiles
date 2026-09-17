alias ar="php artisan"
alias mfs="php artisan migrate:fresh --seed"

alias cu="composer update"
alias cr="composer require"
alias ci="composer install"
alias cda="composer dump-autoload -o"

function pint() {
  if [ -f vendor/bin/pint ]; then
    vendor/bin/pint "$@"
  else
    echo "Pint is not installed. Please run 'composer require laravel/pint' to install it."
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