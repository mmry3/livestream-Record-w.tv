# Livestream Recorder W.tv
Parallel monitor and record Livestream on w.tv.

## Linux:
Bash. Using ffmpeg, curl, jq.
Record in current directory there is script.

#### Requirements:
```
sudo apt install -y curl jq ffmpeg
```

Can change interval check, in seconds.
```
CHECK_INTERVAL=8
```

### Usage:
```
chmod +x record_w-tv.sh
./record_w-tv.sh nickname1,nickname2,nickname3
```

## Powershell:
Record in current directory there is script.

Can change interval check, in seconds.
```
$CHECK_INTERVAL = 3
```

### Usage:
```
.\record_w-tv.ps1 -Channels "nickname1,nickname2,nickname3"
```
