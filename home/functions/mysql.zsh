dbdump() { mysqldump -u root "$1" > "$1_$(date +%Y%m%d_%H%M%S).sql" }

laradump() {
  local db=$(grep ^DB_DATABASE .env 2>/dev/null | cut -d= -f2)
  [[ -n "$db" ]] && mysqldump -u root "$db" > "${db}_$(date +%Y%m%d_%H%M%S).sql" || echo "No .env or DB_DATABASE found"
}
