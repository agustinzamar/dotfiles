catcopy() {
  bat -p --paging=never "$1" | pbcopy
}
