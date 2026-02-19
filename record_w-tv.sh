## Requirements: sudo apt install -y curl jq ffmpeg
#!/usr/bin/env bash
set -u

# Change user1 and user2 to yours
# Can comment user2 just to record one user
CHANNEL_NICKNAMES=(
  "user1"
  "user2"
)

# Change interval check, in seconds
CHECK_INTERVAL=8   
SCRIPT_DIR="$(pwd)"

declare -A CHANNEL_NICKNAME
declare -A CHANNEL_RECORDING
declare -A CHANNEL_PID
declare -A CHANNEL_LOG
declare -A CHANNEL_STREAMID

log() {
  local logfile="$1"
  local text="$2"
  echo "$(date '+%Y-%m-%d %H-%M-%S') | $text" >> "$logfile"
}

# Get userId by nickname
get_userid() {
  local nickname="$1"
  curl -s --max-time 6 \
    "https://profiles-service.w.tv/api/v1/profiles/by-nickname/${nickname}" |
    jq -r '.profile.userId'
}

# Start ffmpeg
start_ffmpeg() {
  local userid="$1"
  local nickname="$2"
  local playback="$3"

  local timestamp
  timestamp="$(date '+%Y-%m-%d_%H-%M-%S')"

  local outfile="${SCRIPT_DIR}/${nickname}-w-tv-${timestamp}.ts"
  local logfile="${SCRIPT_DIR}/${nickname}-w-tv-${timestamp}.log"

  CHANNEL_LOG["$userid"]="$logfile"
  CHANNEL_RECORDING["$userid"]=1

  log "$logfile" "START | ${nickname}"
  log "$logfile" "URL   | ${playback}"
  log "$logfile" "FILE  | ${outfile}"

  ffmpeg \
    -hide_banner \
    -loglevel error \
    -stats \
    -i "$playback" \
    -c copy \
    "$outfile" \
    2>>"$logfile" &

  local pid=$!
  CHANNEL_PID["$userid"]=$pid

  log "$logfile" "FFMPEG | started pid=${pid}"
}

echo "Resolving channels..."

for nick in "${CHANNEL_NICKNAMES[@]}"; do
  userid="$(get_userid "$nick")"

  if [[ -n "$userid" ]]; then
    CHANNEL_NICKNAME["$userid"]="$nick"
    CHANNEL_RECORDING["$userid"]=0
    CHANNEL_PID["$userid"]=""
    CHANNEL_LOG["$userid"]=""
    CHANNEL_STREAMID["$userid"]=""

    echo "Channel ${nick} | userId=${userid}"
  else
    echo "Skipped channel ${nick}"
  fi
done

echo "Monitoring channels started..."

while true; do
  for userid in "${!CHANNEL_NICKNAME[@]}"; do
    nickname="${CHANNEL_NICKNAME[$userid]}"
    api_url="https://streams-search-service.w.tv/api/v1/channels/${userid}"

    response="$(curl -s --max-time 10 "$api_url")"
    live="$(echo "$response" | jq -r '.channel.live')"

    # STREAM START
    if [[ "$live" == "true" && "${CHANNEL_RECORDING[$userid]}" -eq 0 ]]; then
      playback="$(echo "$response" | jq -r '.channel.liveStream.playbackUrl')"
      streamid="$(echo "$response" | jq -r '.channel.liveStream.streamId')"

      CHANNEL_STREAMID["$userid"]="$streamid"
      start_ffmpeg "$userid" "$nickname" "$playback"
    fi

    # AUTO-RECONNECT
    if [[ "$live" == "true" && "${CHANNEL_RECORDING[$userid]}" -eq 1 ]]; then
      pid="${CHANNEL_PID[$userid]}"

      if ! kill -0 "$pid" 2>/dev/null; then
        logfile="${CHANNEL_LOG[$userid]}"
        log "$logfile" "RESTART | ffmpeg crashed, restarting"

        playback="$(echo "$response" | jq -r '.channel.liveStream.playbackUrl')"
        start_ffmpeg "$userid" "$nickname" "$playback"
      fi
    fi

    # STREAM END
    if [[ "$live" == "false" && "${CHANNEL_RECORDING[$userid]}" -eq 1 ]]; then
      logfile="${CHANNEL_LOG[$userid]}"
      pid="${CHANNEL_PID[$userid]}"

      log "$logfile" "STOP | Stream ended"

      if kill -0 "$pid" 2>/dev/null; then
        kill "$pid"
      fi

      CHANNEL_RECORDING["$userid"]=0
      CHANNEL_PID["$userid"]=""
      CHANNEL_STREAMID["$userid"]=""
      CHANNEL_LOG["$userid"]=""
    fi
  done

  sleep "$CHECK_INTERVAL"
done
