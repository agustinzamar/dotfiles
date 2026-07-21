mkd() {
  mkdir -p "$@" && cd "$_"
}

digga() {
  dig +nocmd "$1" any +multiline +noall +answer
}

killport() {
  local port="$1"
  if [[ -z "$port" ]]; then
    echo "Usage: killport <port>"
    return 1
  fi

  local pids
  pids=$(lsof -ti tcp:"$port" 2>/dev/null)
  if [[ -z "$pids" ]]; then
    echo "No process found on port $port."
    return 1
  fi

  echo "$pids" | xargs kill -9
  echo "Killed process(es) on port $port."
}

disablesleep-timed() {
  local hours=${1:-2}
  local secs=$((hours * 3600))

  sudo pmset -a disablesleep 1
  echo "disablesleep ON for ${hours}h (until $(date -v +${hours}H '+%H:%M'))"

  ( sleep $secs; sudo pmset -a disablesleep 0 ) >/tmp/.disablesleep_revert.log 2>&1 &
  disown
  echo $! > /tmp/.disablesleep_pid
  echo "Run 'disablesleep-off' to cancel/revert early."
}

disablesleep-off() {
  sudo pmset -a disablesleep 0
  if [[ -f /tmp/.disablesleep_pid ]]; then
    kill "$(cat /tmp/.disablesleep_pid)" 2>/dev/null
    rm /tmp/.disablesleep_pid
  fi
  echo "disablesleep OFF."
}

disablesleep-status() {
  local state
  state=$(pmset -g | grep disablesleep | awk '{print $2}')
  if [[ "$state" == "1" ]]; then
    echo "disablesleep is ON"
  else
    echo "disablesleep is OFF"
  fi
  if [[ -f /tmp/.disablesleep_pid ]] && kill -0 "$(cat /tmp/.disablesleep_pid)" 2>/dev/null; then
    echo "Auto-revert timer active (PID $(cat /tmp/.disablesleep_pid))"
  fi
}
