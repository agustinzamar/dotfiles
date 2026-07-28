dsh() {
  local cid=$(docker ps --format '{{.Names}}' | fzf)
  [[ -n "$cid" ]] && docker exec -it "$cid" sh
}
