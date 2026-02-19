# Livestream Recorder W.tv

Parallel monitor and record Livestream on w.tv
Bash. Using ffmpeg, curl, jq
Record in current directory.

### Requirements:
```
sudo apt install -y curl jq ffmpeg
```

Change variables user1 and user2 to yours
```
CHANNEL_NICKNAMES=(
  "user1"
  "user2"
)
```

Can change interval check, in seconds
```
CHECK_INTERVAL=8
```   

## Start:
```
chmod +x record_w-tv.sh
./w-tv.sh
```
