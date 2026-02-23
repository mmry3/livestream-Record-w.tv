param(
    [Parameter(Mandatory)]
    [string]$Channels
)

$CHECK_INTERVAL = 3
$SCRIPT_DIR = $PWD.Path

$channelNickname  = @{}
$channelRecording = @{}
$channelPid       = @{}
$channelLog       = @{}
$channelStreamId  = @{}

function Write-Log {
    param([string]$LogFile, [string]$Text)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH-mm-ss'
    $line = "$timestamp | $Text"
    $sw = [System.IO.StreamWriter]::new($LogFile, $true, [System.Text.Encoding]::UTF8)
    try { $sw.WriteLine($line) } finally { $sw.Close() }
}

function Get-UserId {
    param([string]$Nickname)
    try {
        $response = Invoke-RestMethod `
            -Uri "https://profiles-service.w.tv/api/v1/profiles/by-nickname/$Nickname" `
            -TimeoutSec 6 -ErrorAction Stop
        return $response.profile.userId
    } catch {
        return $null
    }
}

function Start-Ffmpeg {
    param([string]$UserId, [string]$Nickname, [string]$PlaybackUrl)

    $timestamp  = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $outFile    = Join-Path $SCRIPT_DIR "${Nickname}-w-tv-${timestamp}.ts"

    $logFile    = Join-Path $SCRIPT_DIR "${Nickname}-w-tv-${timestamp}_events.log"
    $ffmpegLog  = Join-Path $SCRIPT_DIR "${Nickname}-w-tv-${timestamp}_ffmpeg.log"

    $channelLog[$UserId]       = $logFile
    $channelRecording[$UserId] = $true

    Write-Log $logFile "START | $Nickname"
    Write-Log $logFile "URL   | $PlaybackUrl"
    Write-Log $logFile "FILE  | $outFile"

    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "$ts | START | $Nickname | recording to $outFile"

    $ffmpegArgs = @(
        '-hide_banner'
        '-loglevel', 'warning'
        '-fflags', '+genpts+discardcorrupt'
        '-err_detect', 'ignore_err'
        '-stats'
        '-stats_period', '1400'
        '-i', $PlaybackUrl
        '-c', 'copy'
        $outFile
    )

    # ffmpeg stderr goes to its own file — no lock conflict with Write-Log
    $proc = Start-Process -FilePath 'ffmpeg' `
                          -ArgumentList $ffmpegArgs `
                          -RedirectStandardError $ffmpegLog `
                          -NoNewWindow `
                          -PassThru

    $channelPid[$UserId] = $proc
    Write-Log $logFile "FFMPEG | started pid=$($proc.Id) ffmpeg_log=$ffmpegLog"
}

function Test-ProcessRunning {
    param([System.Diagnostics.Process]$Proc)
    if ($null -eq $Proc) { return $false }
    try { return -not $Proc.HasExited } catch { return $false }
}

# Resolve channels
$channelNicknames = $Channels -split ','

Write-Host "Resolving channels..."
foreach ($nick in $channelNicknames) {
    $userId = Get-UserId -Nickname $nick
    if ($userId) {
        $channelNickname[$userId]  = $nick
        $channelRecording[$userId] = $false
        $channelPid[$userId]       = $null
        $channelLog[$userId]       = $null
        $channelStreamId[$userId]  = $null
        Write-Host "Channel $nick | userId=$userId"
    } else {
        Write-Host "Skipped channel $nick"
    }
}

Write-Host "Monitoring channels started..."

while ($true) {
    foreach ($userId in @($channelNickname.Keys)) {
        $nickname = $channelNickname[$userId]
        $apiUrl   = "https://streams-search-service.w.tv/api/v1/channels/$userId"

        try {
            $response = Invoke-RestMethod -Uri $apiUrl -TimeoutSec 10 -ErrorAction Stop
        } catch {
            Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | WARN  | $nickname | API error: $_"
            continue
        }

        $live = $response.channel.live

        # STREAM START
        if ($live -eq $true -and $channelRecording[$userId] -eq $false) {
            Start-Sleep -Seconds 2
            $playbackUrl              = $response.channel.liveStream.playbackUrl
            $channelStreamId[$userId] = $response.channel.liveStream.streamId
            Start-Ffmpeg -UserId $userId -Nickname $nickname -PlaybackUrl $playbackUrl
        }

        # AUTO-RECONNECT (ffmpeg crashed while stream still live)
        elseif ($live -eq $true -and $channelRecording[$userId] -eq $true) {
            if (-not (Test-ProcessRunning $channelPid[$userId])) {
                $logFile = $channelLog[$userId]
                Write-Log $logFile "RESTART | ffmpeg crashed, restarting"
                $playbackUrl = $response.channel.liveStream.playbackUrl
                Start-Ffmpeg -UserId $userId -Nickname $nickname -PlaybackUrl $playbackUrl
            }
        }

        # STREAM END
        elseif ($live -eq $false -and $channelRecording[$userId] -eq $true) {
            $logFile = $channelLog[$userId]
            $proc    = $channelPid[$userId]

            Write-Log $logFile "STOP | Stream ended"
            $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            Write-Host "$ts | STOP  | $nickname | recording ended"

            if (Test-ProcessRunning $proc) { $proc.Kill() }

            $channelRecording[$userId] = $false
            $channelPid[$userId]       = $null
            $channelStreamId[$userId]  = $null
            $channelLog[$userId]       = $null
        }
    }

    Start-Sleep -Seconds $CHECK_INTERVAL
}
