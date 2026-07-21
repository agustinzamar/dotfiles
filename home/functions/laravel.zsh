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
