# Livestream Recorder W.tv
Monitor and records Livestreams on w.tv.

## Linux:
Record in current directory where is script.

#### Requirements:
```
sudo apt install -y curl jq ffmpeg
```

Interval check, in seconds.
```
CHECK_INTERVAL=8
```

### Usage:
```
chmod +x record_w-tv.sh
./record_w-tv.sh nickname1,nickname2,nickname3
```

## Powershell:
Record in current directory where is script.

Interval check, in seconds.
```
$CHECK_INTERVAL = 6
```

### Usage:
```
.\record_w-tv.ps1 -Channels "nickname1,nickname2,nickname3"
```
