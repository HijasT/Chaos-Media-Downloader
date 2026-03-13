# ============================================================
#  Chaos Media Downloader - Fully Portable
#
#  Downloads audio and video from YouTube, Spotify, TikTok,
#  Instagram, Twitter/X, Reddit, Twitch and 1000+ more sites.
#
#  All tools (yt-dlp, python, ffmpeg, spotdl) are installed
#  and managed locally in a tools\ folder next to this script.
#  Nothing is installed system-wide.
#
#  File layout next to this script:
#    tools\          - portable binaries (auto-managed)
#    Downloads\      - default output folders
#    Logs\           - log file
#    config.json     - folder paths + tool settings
#    favourites.json - saved Spotify playlists
#    downloaded-songs.txt - history of downloaded tracks
#    yt-dlp-archive.txt   - yt-dlp duplicate prevention archive
# ============================================================

$ErrorActionPreference = "Continue"

# ============================================================
#  SECTION 1: PATHS
#  All paths are derived from the script's own location so
#  the entire folder can be moved or copied to any machine.
# ============================================================

$scriptDir       = Split-Path -Parent $MyInvocation.MyCommand.Path
$toolsDir        = "$scriptDir\tools"
$configFile      = "$scriptDir\config.json"
$favsFile        = "$scriptDir\favourites.json"
$logDir          = "$scriptDir\Logs"
$logFile         = "$logDir\log.txt"
$downloadedSongs = "$scriptDir\downloaded-songs.txt"
$ytArchive       = "$scriptDir\yt-dlp-archive.txt"

# Individual tool directories inside tools\
$ytdlpDir  = "$toolsDir\yt-dlp"
$pythonDir = "$toolsDir\python"
$ffmpegDir = "$toolsDir\ffmpeg"

# Executables
$ytdlpExe  = "$ytdlpDir\yt-dlp.exe"
$pythonExe = "$pythonDir\python.exe"
$ffmpegExe = "$ffmpegDir\ffmpeg.exe"

# Create required directories if they do not already exist
foreach ($d in @($logDir, $toolsDir, $ytdlpDir, $pythonDir, $ffmpegDir)) {
    if (!(Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
}

# Prepend portable tool paths to PATH for this session only.
# This ensures the portable binaries are found before any system-wide installs.
$env:PATH = "$ytdlpDir;$pythonDir;$pythonDir\Scripts;$ffmpegDir;$env:PATH"

# ============================================================
#  SECTION 2: GENERAL HELPERS
#  Small utility functions used throughout the script.
# ============================================================

# Write a timestamped entry to the log file
function Write-Log {
    param([string]$msg, [string]$type = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts [$type] $msg" | Out-File -Append -FilePath $logFile -Encoding utf8
}

# Pause and wait for Enter before returning to the calling menu
function Pause-Return {
    Write-Host ""
    Write-Host "  Press Enter to return to menu..." -ForegroundColor DarkGray
    $null = Read-Host
}

# Clear the screen and draw a consistent page header
function Show-Header {
    param([string]$title)
    Clear-Host
    Write-Host ""
    Write-Host "  ============================================" -ForegroundColor Cyan
    Write-Host "   $title" -ForegroundColor Cyan
    Write-Host "  ============================================" -ForegroundColor Cyan
    Write-Host ""
}

# Prompt the user for a URL and keep asking until a valid one is entered.
# Typing B or BACK returns $null so the caller can return to the menu.
function Get-ValidURL {
    param([string]$prompt)
    Write-Host "  (Type B to go back)" -ForegroundColor DarkGray
    while ($true) {
        Write-Host "  $prompt" -ForegroundColor Yellow
        $url = (Read-Host "  URL").Trim()
        if ($url.ToUpper() -eq 'B' -or $url.ToUpper() -eq 'BACK') {
            return $null
        } elseif ([string]::IsNullOrWhiteSpace($url)) {
            Write-Host "  URL cannot be empty. Type B to go back." -ForegroundColor Red
        } elseif ($url -notmatch "^https?://") {
            Write-Host "  Not a valid URL - must start with http:// or https://" -ForegroundColor Red
        } else {
            return $url
        }
    }
}

# Download a single file from the internet to a local path.
# Returns $true on success, $false on failure.
function Get-RemoteFile {
    param([string]$url, [string]$dest, [string]$label)
    Write-Host "    Downloading $label..." -ForegroundColor Cyan
    try {
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -ErrorAction Stop
        return $true
    } catch {
        Write-Host "    FAILED to download ${label}: $_" -ForegroundColor Red
        Write-Log "Download failed: $label - $_" "ERROR"
        return $false
    }
}

# Check whether the current PowerShell session has Administrator rights
function Test-IsAdmin {
    return ([Security.Principal.WindowsPrincipal]`
        [Security.Principal.WindowsIdentity]::GetCurrent()`
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Ask the user whether to relaunch as Administrator for a specific task.
# If the user agrees, the script relaunches elevated and the current process exits.
# If the user declines, execution continues without elevation (tool is skipped).
function Request-Elevation {
    param([string]$reason)
    Write-Host ""
    Write-Host "  !! ADMINISTRATOR ACCESS NEEDED" -ForegroundColor Yellow
    Write-Host "  Reason : $reason" -ForegroundColor White
    Write-Host ""
    Write-Host "  Windows requires Administrator rights for this action." -ForegroundColor DarkGray
    Write-Host "  Choosing [N] skips this step and continues without it." -ForegroundColor DarkGray
    Write-Host ""
    $ans = (Read-Host "  Request Administrator access? [Y/N]").Trim().ToUpper()
    if ($ans -eq 'Y') {
        Write-Host ""
        Write-Host "  Relaunching as Administrator..." -ForegroundColor Cyan
        Start-Process powershell.exe `
            -ArgumentList "-NoExit -ExecutionPolicy Bypass -File `"$PSCommandPath`"" `
            -Verb RunAs
        exit
    }
    Write-Host "  Skipping - continuing without this tool." -ForegroundColor DarkYellow
    return $false
}

# ============================================================
#  SECTION 3: DOWNLOAD HISTORY
#  Tracks which songs/tracks have already been downloaded so
#  duplicate detection works across sessions.
# ============================================================

# Add a track entry to the downloaded-songs list if not already present
function Add-ToHistory {
    param([string]$entry)
    if (!(Test-Path $downloadedSongs)) { New-Item -ItemType File -Path $downloadedSongs | Out-Null }
    $existing = Get-Content $downloadedSongs -ErrorAction SilentlyContinue
    if ($existing -notcontains $entry) {
        Add-Content -Path $downloadedSongs -Value $entry -Encoding utf8
    }
}

# Return $true if a track entry already exists in the history file
function Test-InHistory {
    param([string]$entry)
    if (!(Test-Path $downloadedSongs)) { return $false }
    $list = Get-Content $downloadedSongs -ErrorAction SilentlyContinue
    return ($null -ne $list -and $list -contains $entry)
}

# ============================================================
#  SECTION 4: FAVOURITES
#  Saved playlists stored as {name, url, type} in favourites.json.
#  Type is either "spotify" or "youtube".
#  Shown in the Audio Download menu and downloadable directly
#  from the Manage Favourites screen.
# ============================================================

# Load favourites from disk using a line-by-line approach to completely
# avoid PowerShell 5's ConvertFrom-Json single-object / Count=0 bug.
# Each favourite is stored as one JSON object per line in the file.
function Get-Favourites {
    if (!(Test-Path $favsFile)) { return @() }
    try {
        $lines = Get-Content $favsFile -Encoding utf8 | Where-Object { $_.Trim() -ne "" }
        if ($null -eq $lines -or $lines.Count -eq 0) { return @() }
        $result = @()
        foreach ($line in $lines) {
            try { $result += ($line | ConvertFrom-Json) } catch {}
        }
        return $result
    } catch { return @() }
}

# Save favourites: one JSON object per line (avoids PS5 array-collapse bug entirely)
function Save-Favourites {
    param([array]$favs)
    if ($favs.Count -eq 0) {
        "" | Set-Content $favsFile -Encoding utf8
    } else {
        $lines = $favs | ForEach-Object { $_ | ConvertTo-Json -Depth 3 -Compress }
        $lines | Set-Content $favsFile -Encoding utf8
    }
}

# Add a new favourite. Asks whether it is Spotify or YouTube.
# Prevents duplicates by checking the URL.
function Add-Favourite {
    param([string]$name, [string]$url, [string]$type)
    $favs = Get-Favourites
    if ($favs | Where-Object { $_.url -eq $url }) {
        Write-Host "  Already in favourites." -ForegroundColor DarkYellow
        return
    }
    $favs += [PSCustomObject]@{ name = $name; url = $url; type = $type }
    Save-Favourites -favs $favs
    Write-Host "  Saved: $name ($type)" -ForegroundColor Green
    Write-Log "Favourite added: $name | $type | $url"
}

# Remove a favourite by its list index (0-based)
function Remove-Favourite {
    param([int]$index)
    $favs = Get-Favourites
    if ($index -lt 0 -or $index -ge $favs.Count) {
        Write-Host "  Invalid selection." -ForegroundColor Red
        return
    }
    $removed = $favs[$index].name
    $newFavs = @($favs | Where-Object { $_ -ne $favs[$index] })
    Save-Favourites -favs $newFavs
    Write-Host "  Removed: $removed" -ForegroundColor DarkYellow
    Write-Log "Favourite removed: $removed"
}

# Show the type label with colour for display
function Get-TypeLabel {
    param([string]$type)
    if ($type -eq "youtube") { return "[YT]     " }
    return "[Spotify]"
}

# Manage Favourites screen.
# Options: Add, Remove, Download (select by number), Back.
function Show-FavouritesManager {
    param($cfg)
    while ($true) {
        Show-Header "MANAGE FAVOURITES"
        $favs = Get-Favourites

        if ($favs.Count -eq 0) {
            Write-Host "  No favourites saved yet." -ForegroundColor DarkGray
        } else {
            $i = 1
            foreach ($f in $favs) {
                $typeLabel = Get-TypeLabel -type $f.type
                $typeColor = if ($f.type -eq "youtube") { "Red" } else { "Green" }
                Write-Host "  [$i] " -NoNewline
                Write-Host $typeLabel -ForegroundColor $typeColor -NoNewline
                Write-Host " $($f.name)" -ForegroundColor Cyan
                Write-Host "       $($f.url)" -ForegroundColor DarkGray
                $i++
            }
        }

        Write-Host ""
        Write-Host "  [A]  Add a favourite"
        Write-Host "  [D]  Download a favourite"
        Write-Host "  [R]  Remove a favourite"
        Write-Host "  [B]  Back"
        Write-Host ""

        $choice = (Read-Host "  Choice [A/D/R/B]").Trim().ToUpper()
        switch ($choice) {
            'A' {
                # Ask for name
                $favName = (Read-Host "  Name / label for this playlist").Trim()
                if ([string]::IsNullOrWhiteSpace($favName)) {
                    Write-Host "  Name cannot be empty." -ForegroundColor Red
                    Start-Sleep -Seconds 1; break
                }
                # Ask for type
                Write-Host "  Is this a Spotify or YouTube playlist?" -ForegroundColor Yellow
                Write-Host "  [1] Spotify   [2] YouTube"
                $typeChoice = (Read-Host "  Type [1/2]").Trim()
                $favType = if ($typeChoice -eq "2") { "youtube" } else { "spotify" }
                # Ask for URL
                $favUrl = Get-ValidURL "Paste the $favType URL:"
                if ($null -eq $favUrl) { break }
                Add-Favourite -name $favName -url $favUrl -type $favType
                Start-Sleep -Seconds 1
            }
            'D' {
                if ($null -eq $cfg) {
                    Write-Host "  Cannot download from here - use the Audio Download menu." -ForegroundColor Red
                    Start-Sleep -Seconds 1; break
                }
                if ($favs.Count -eq 0) {
                    Write-Host "  No favourites to download." -ForegroundColor DarkGray
                    Start-Sleep -Seconds 1; break
                }
                $num = (Read-Host "  Enter number to download").Trim()
                if ($num -match "^\d+$") {
                    $idx = [int]$num - 1
                    if ($idx -ge 0 -and $idx -lt $favs.Count) {
                        $fav = $favs[$idx]
                        Show-Header "DOWNLOADING: $($fav.name)"
                        if ($fav.type -eq "youtube") {
                            Write-Host "  Downloading YouTube audio..." -ForegroundColor Green
                            $outTemplate = "$($cfg.audioDir)\%(artist,album_artist,uploader)s - %(title)s.%(ext)s"
                            $ytArgs = Build-AudioArgs -cfg $cfg -outputTemplate $outTemplate
                            & $ytdlpExe @ytArgs $fav.url
                        } else {
                            Invoke-SpotifyPlaylist -url $fav.url -cfg $cfg
                        }
                        Write-Log "Favourite downloaded: $($fav.name)"
                        Pause-Return
                    } else {
                        Write-Host "  Invalid number." -ForegroundColor Red
                        Start-Sleep -Seconds 1
                    }
                } else {
                    Write-Host "  Invalid input." -ForegroundColor Red
                    Start-Sleep -Seconds 1
                }
            }
            'R' {
                if ($favs.Count -eq 0) {
                    Write-Host "  Nothing to remove." -ForegroundColor DarkGray
                    Start-Sleep -Seconds 1; break
                }
                $num = (Read-Host "  Enter number to remove").Trim()
                if ($num -match "^\d+$") { Remove-Favourite -index ([int]$num - 1) }
                else { Write-Host "  Invalid number." -ForegroundColor Red }
                Start-Sleep -Seconds 1
            }
            'B' { return }
            default { Write-Host "  Invalid." -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    }
}

# ============================================================
#  SECTION 5: CONFIG & SETTINGS DEFINITIONS
#
#  config.json holds:
#    videoDir  - where video downloads are saved
#    audioDir  - where audio downloads are saved
#    ytdlp     - yt-dlp option overrides
#    spotdl    - spotdl option overrides
#
#  Both videoDir and audioDir can be changed at any time from
#  Main Menu -> [3] Settings -> [3] Change download folders.
# ============================================================

# yt-dlp settings: each entry defines a user-facing toggle or value setting.
# These are rendered on the Settings page and converted to CLI args at download time.
$ytdlpSettingsDefs = @(
    # key              default   description                                             type    preset options
    [PSCustomObject]@{ key="audioFormat";    default="mp3";   desc="Output audio format";                           type="value"; options=@("mp3","m4a","flac","opus","wav") }
    [PSCustomObject]@{ key="audioQuality";   default="320K";  desc="Audio quality / bitrate (0 = best VBR)";        type="value"; options=@("320K","256K","192K","128K","0") }
    [PSCustomObject]@{ key="embedThumbnail"; default=$true;   desc="Embed album art into the audio file";           type="bool";  options=$null }
    [PSCustomObject]@{ key="embedMetadata";  default=$true;   desc="Embed title, artist, album metadata tags";      type="bool";  options=$null }
    [PSCustomObject]@{ key="writeAutoSubs";  default=$true;   desc="Download auto-generated subtitles if available"; type="bool"; options=$null }
    [PSCustomObject]@{ key="embedSubs";      default=$true;   desc="Embed downloaded subtitles into the file";      type="bool";  options=$null }
    [PSCustomObject]@{ key="ignoreErrors";   default=$true;   desc="Skip failed items instead of stopping entirely"; type="bool"; options=$null }
    [PSCustomObject]@{ key="sponsorBlock";   default=$false;  desc="Remove sponsor/ad segments via SponsorBlock";   type="bool";  options=$null }
    [PSCustomObject]@{ key="noPlaylist";     default=$false;  desc="Download single video only, ignore playlists";  type="bool";  options=$null }
)

# spotdl settings: same structure, applied to Spotify downloads
$spotdlSettingsDefs = @(
    [PSCustomObject]@{ key="format";       default="mp3";     desc="Output audio format";                           type="value"; options=@("mp3","m4a","flac","opus","ogg","wav") }
    [PSCustomObject]@{ key="bitrate";      default="320k";    desc="Audio bitrate for the output file";             type="value"; options=@("320k","256k","192k","128k","auto") }
    [PSCustomObject]@{ key="lyrics";       default="genius";  desc="Lyrics provider (disabled = no lyrics)";        type="value"; options=@("genius","azlyrics","musixmatch","synced","disabled") }
    [PSCustomObject]@{ key="overwrite";    default="skip";    desc="What to do when a file already exists";         type="value"; options=@("skip","force","metadata") }
    [PSCustomObject]@{ key="generateLRC";  default=$false;    desc="Save lyrics as a separate .lrc sidecar file";   type="bool";  options=$null }
    [PSCustomObject]@{ key="printErrors";  default=$false;    desc="Print a summary of failed tracks after download"; type="bool"; options=$null }
    [PSCustomObject]@{ key="saveFile";     default=$false;    desc="Save a .spotdl project file alongside downloads"; type="bool"; options=$null }
    [PSCustomObject]@{ key="threadCount";  default="4";       desc="Number of parallel download threads (1-32)";    type="value"; options=@("1","2","4","8","16") }
)

# Build a PSCustomObject with all default values for both tool groups
function Get-DefaultSettings {
    $ytdlp  = [PSCustomObject]@{}
    $spotdl = [PSCustomObject]@{}
    foreach ($d in $ytdlpSettingsDefs)  { $ytdlp  | Add-Member -NotePropertyName $d.key -NotePropertyValue $d.default }
    foreach ($d in $spotdlSettingsDefs) { $spotdl | Add-Member -NotePropertyName $d.key -NotePropertyValue $d.default }
    return $ytdlp, $spotdl
}

# Load config.json from disk. On first run (or if file is missing/corrupted),
# prompts the user to set their download folders and writes a new config.
# Also merges any newly added setting keys with their defaults so old configs
# remain compatible when new settings are added in future versions.
function Get-Config {
    $defaults = Get-DefaultSettings
    $defYt    = $defaults[0]
    $defSpot  = $defaults[1]

    if (Test-Path $configFile) {
        try {
            $cfg = Get-Content $configFile -Raw | ConvertFrom-Json
            if ($cfg.videoDir -and $cfg.audioDir) {
                # Add missing top-level sections if this is an older config
                if (-not $cfg.ytdlp)  { $cfg | Add-Member -NotePropertyName "ytdlp"  -NotePropertyValue $defYt  }
                if (-not $cfg.spotdl) { $cfg | Add-Member -NotePropertyName "spotdl" -NotePropertyValue $defSpot }
                # Merge any new keys that didn't exist when this config was saved
                foreach ($d in $ytdlpSettingsDefs) {
                    if ($null -eq $cfg.ytdlp.($d.key)) {
                        $cfg.ytdlp | Add-Member -NotePropertyName $d.key -NotePropertyValue $d.default -ErrorAction SilentlyContinue
                    }
                }
                foreach ($d in $spotdlSettingsDefs) {
                    if ($null -eq $cfg.spotdl.($d.key)) {
                        $cfg.spotdl | Add-Member -NotePropertyName $d.key -NotePropertyValue $d.default -ErrorAction SilentlyContinue
                    }
                }
                return $cfg
            }
        } catch {
            Write-Host "  Config corrupted - recreating..." -ForegroundColor Yellow
        }
    }

    # First-run setup: ask for folder locations
    Show-Header "FIRST TIME SETUP"
    Write-Host "  Choose where downloads will be saved." -ForegroundColor White
    Write-Host "  Press Enter on either prompt to use the default path shown." -ForegroundColor DarkGray
    Write-Host "  You can change these folders at any time from: Main Menu -> Settings -> Change Folders" -ForegroundColor DarkGray
    Write-Host ""

    $defaultVideo = "$scriptDir\Downloads\Video"
    $defaultAudio = "$scriptDir\Downloads\Audio"

    Write-Host "  Video folder [$defaultVideo]" -ForegroundColor Yellow
    $videoPath = (Read-Host "  Path").Trim()
    if ([string]::IsNullOrWhiteSpace($videoPath)) { $videoPath = $defaultVideo }

    Write-Host ""
    Write-Host "  Audio folder [$defaultAudio]" -ForegroundColor Yellow
    $audioPath = (Read-Host "  Path").Trim()
    if ([string]::IsNullOrWhiteSpace($audioPath)) { $audioPath = $defaultAudio }

    $cfg = [PSCustomObject]@{
        videoDir = $videoPath
        audioDir = $audioPath
        ytdlp    = $defYt
        spotdl   = $defSpot
    }
    $cfg | ConvertTo-Json -Depth 5 | Set-Content $configFile -Encoding utf8
    Write-Host ""
    Write-Host "  Config saved. You can change folders later in Settings." -ForegroundColor Green
    Start-Sleep -Seconds 1
    return $cfg
}

# Persist the current config object back to config.json
function Save-Config {
    param($cfg)
    $cfg | ConvertTo-Json -Depth 5 | Set-Content $configFile -Encoding utf8
}

# Create download directories if they don't exist yet
function Confirm-Dirs {
    param($cfg)
    foreach ($dir in @($cfg.videoDir, $cfg.audioDir)) {
        if (!(Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    }
}

# ============================================================
#  SECTION 6: SETTINGS PAGE
#
#  Renders two interactive setting screens (yt-dlp / spotdl).
#  Active settings are shown at the top with their current
#  values. Inactive settings are shown below with descriptions.
#  Selecting a number toggles booleans or prompts for a new
#  value (with preset options listed for value-type settings).
#
#  Download folder changes are also handled here under [3].
# ============================================================

# Render and handle interaction for one group of settings (ytdlp or spotdl)
function Show-SettingGroup {
    param(
        [string]$groupName,   # display name shown in the header
        [object]$settings,    # the live settings object (mutated in place)
        [array]$defs,         # the definition list for this group
        [object]$cfg          # full config object (needed for Save-Config)
    )
    while ($true) {
        Show-Header "SETTINGS - $groupName"

        # Separate active from inactive for display ordering
        $active   = @()
        $inactive = @()
        foreach ($d in $defs) {
            $val = $settings.($d.key)
            if ($d.type -eq "bool") {
                if ($val -eq $true) { $active += $d } else { $inactive += $d }
            } else {
                # Value-type settings are always "active" (they always have a value)
                $active += $d
            }
        }

        # Show active settings at the top (green)
        if ($active.Count -gt 0) {
            Write-Host "  -- ACTIVE --" -ForegroundColor Green
            $i = 1
            foreach ($d in $active) {
                $val = $settings.($d.key)
                if ($d.type -eq "bool") {
                    Write-Host "  [$i] [ON ]  $($d.key)" -ForegroundColor Green -NoNewline
                } else {
                    Write-Host ("  [{0}] [{1,-5}]  {2}" -f $i, $val, $d.key) -ForegroundColor Green -NoNewline
                }
                Write-Host "  - $($d.desc)" -ForegroundColor DarkGray
                $i++
            }
            Write-Host ""
        }

        # Show inactive boolean flags below (yellow), value-type settings are always above
        if ($inactive.Count -gt 0) {
            Write-Host "  -- OFF (click number to enable) --" -ForegroundColor DarkGray
            foreach ($d in $inactive) {
                Write-Host "  [$i] [OFF]   $($d.key)" -ForegroundColor DarkYellow -NoNewline
                Write-Host "  - $($d.desc)" -ForegroundColor DarkGray
                $i++
            }
            Write-Host ""
        }

        Write-Host "  [B] Back"
        Write-Host ""
        Write-Host "  Enter a number to toggle or change a setting." -ForegroundColor DarkGray
        Write-Host ""

        $allDefs = $active + $inactive
        $choice  = (Read-Host "  Choose").Trim().ToUpper()

        if ($choice -eq 'B') { return }

        if ($choice -match "^\d+$") {
            $idx = [int]$choice - 1
            if ($idx -ge 0 -and $idx -lt $allDefs.Count) {
                $selected   = $allDefs[$idx]
                $currentVal = $settings.($selected.key)

                if ($selected.type -eq "bool") {
                    # Toggle the boolean on/off
                    $newVal = -not $currentVal
                    $settings.($selected.key) = $newVal
                    $label  = if ($newVal) { "ON" } else { "OFF" }
                    Write-Host "  $($selected.key) set to $label" -ForegroundColor Cyan
                } else {
                    # Show preset options or accept free input for value-type settings
                    Write-Host ""
                    Write-Host "  Setting : $($selected.key)" -ForegroundColor Cyan
                    Write-Host "  Current : $currentVal" -ForegroundColor White
                    Write-Host "  Desc    : $($selected.desc)" -ForegroundColor DarkGray
                    Write-Host ""

                    if ($selected.options -and $selected.options.Count -gt 0) {
                        Write-Host "  Preset options:" -ForegroundColor DarkGray
                        $oi = 1
                        foreach ($opt in $selected.options) {
                            # Mark the currently selected option with an asterisk
                            $mark = if ($opt -eq $currentVal) { "*" } else { " " }
                            Write-Host "   [$oi]$mark $opt"
                            $oi++
                        }
                        Write-Host ""
                        $optChoice = (Read-Host "  Enter number or type a custom value").Trim()
                        if ($optChoice -match "^\d+$") {
                            $oidx = [int]$optChoice - 1
                            if ($oidx -ge 0 -and $oidx -lt $selected.options.Count) {
                                $settings.($selected.key) = $selected.options[$oidx]
                                Write-Host "  Set to: $($selected.options[$oidx])" -ForegroundColor Green
                            } else {
                                Write-Host "  Invalid option number." -ForegroundColor Red
                            }
                        } elseif (-not [string]::IsNullOrWhiteSpace($optChoice)) {
                            $settings.($selected.key) = $optChoice
                            Write-Host "  Set to: $optChoice" -ForegroundColor Green
                        }
                    } else {
                        # No preset options - free text input
                        $newVal = (Read-Host "  New value").Trim()
                        if (-not [string]::IsNullOrWhiteSpace($newVal)) {
                            $settings.($selected.key) = $newVal
                            Write-Host "  Set to: $newVal" -ForegroundColor Green
                        }
                    }
                }
                # Persist every change immediately
                Save-Config -cfg $cfg
                Start-Sleep -Seconds 1
            } else {
                Write-Host "  Invalid number." -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        } else {
            Write-Host "  Invalid choice." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}

# Settings top-level menu:
#   [1] yt-dlp settings
#   [2] spotdl settings
#   [3] Change download folders  <-- this is where directories are changed
function Show-SettingsMenu {
    param($cfg)
    while ($true) {
        Show-Header "SETTINGS"
        Write-Host "  [1]  yt-dlp settings   (audio quality, format, metadata, subtitles...)"
        Write-Host "  [2]  spotdl settings   (bitrate, lyrics provider, format, threads...)"
        Write-Host "  [3]  Change download folders"
        Write-Host "  [B]  Back to main menu"
        Write-Host ""
        Write-Host "  Current folders:" -ForegroundColor DarkGray
        Write-Host "    Audio : $($cfg.audioDir)" -ForegroundColor DarkGray
        Write-Host "    Video : $($cfg.videoDir)" -ForegroundColor DarkGray
        Write-Host ""

        $choice = (Read-Host "  Choose").Trim().ToUpper()
        switch ($choice) {
            '1' { Show-SettingGroup -groupName "yt-dlp"  -settings $cfg.ytdlp  -defs $ytdlpSettingsDefs  -cfg $cfg }
            '2' { Show-SettingGroup -groupName "spotdl"  -settings $cfg.spotdl -defs $spotdlSettingsDefs -cfg $cfg }
            '3' {
                # Change download folder paths. Press Enter to keep the current value.
                Write-Host ""
                Write-Host "  Press Enter on either prompt to keep the current path." -ForegroundColor DarkGray
                Write-Host ""
                Write-Host "  Video folder [$($cfg.videoDir)]" -ForegroundColor Yellow
                $v = (Read-Host "  New path").Trim()
                if (-not [string]::IsNullOrWhiteSpace($v)) { $cfg.videoDir = $v }

                Write-Host "  Audio folder [$($cfg.audioDir)]" -ForegroundColor Yellow
                $a = (Read-Host "  New path").Trim()
                if (-not [string]::IsNullOrWhiteSpace($a)) { $cfg.audioDir = $a }

                Confirm-Dirs -cfg $cfg
                Save-Config  -cfg $cfg
                Write-Host "  Folders updated." -ForegroundColor Green
                Start-Sleep -Seconds 1
            }
            'B' { return }
            default { Write-Host "  Invalid choice." -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    }
}

# ============================================================
#  SECTION 7: TOOL MANAGEMENT
#
#  Each tool has an Install-* and Initialize-* function.
#  Initialize-* is called at startup for every tool:
#    - If missing  -> install it
#    - If outdated -> offer to update (yt-dlp requires admin;
#                     spotdl does not)
#    - If current  -> report version and move on
#
#  Admin elevation is requested ONLY for yt-dlp (missing or
#  outdated). The user is told exactly why before being asked.
# ============================================================

# ---------- yt-dlp ------------------------------------------
# Fetch the latest yt-dlp release tag from GitHub API
function Get-YtDlpLatestVersion {
    try {
        $rel = Invoke-RestMethod "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest" -ErrorAction Stop
        return $rel.tag_name
    } catch { return $null }
}

# Download the latest yt-dlp.exe into the portable tools folder
function Install-YtDlp {
    $url = "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe"
    $ok  = Get-RemoteFile -url $url -dest $ytdlpExe -label "yt-dlp.exe"
    if ($ok) {
        Write-Host "    yt-dlp installed." -ForegroundColor Green
        Write-Log "yt-dlp installed."
    }
}

# Check yt-dlp version, install if missing, update if outdated.
# Requests elevation only if an install or update is needed.
function Initialize-YtDlp {
    Write-Host "  [yt-dlp]  " -NoNewline -ForegroundColor White

    if (!(Test-Path $ytdlpExe)) {
        Write-Host "Not found." -ForegroundColor Red
        if (!(Test-IsAdmin)) {
            Request-Elevation "yt-dlp is not installed. Installing it requires Administrator rights."
            Write-Host "    yt-dlp skipped." -ForegroundColor DarkYellow
            return
        }
        Install-YtDlp
        return
    }

    $local  = (& $ytdlpExe --version 2>&1).Trim()
    $latest = Get-YtDlpLatestVersion

    if ($null -eq $latest) {
        Write-Host "v$local (could not check for updates)" -ForegroundColor DarkYellow
        return
    }

    if ($local -ne $latest) {
        Write-Host "v$local -> v$latest available." -ForegroundColor Yellow
        if (!(Test-IsAdmin)) {
            Request-Elevation "yt-dlp has an update available (v$local -> v$latest). Updating requires Administrator rights."
            Write-Host "    Keeping v$local." -ForegroundColor DarkYellow
            return
        }
        Install-YtDlp
        $newVer = (& $ytdlpExe --version 2>&1).Trim()
        Write-Host "    Updated to v$newVer." -ForegroundColor Green
        Write-Log "yt-dlp updated $local -> $newVer"
    } else {
        Write-Host "v$local (up to date)" -ForegroundColor Green
    }
}

# ---------- Python (embeddable) -----------------------------
# Uses the embeddable zip package from python.org.
# No system installation; lives entirely inside tools\python\.
$pythonVersion = "3.12.9"
$pythonZipUrl  = "https://www.python.org/ftp/python/$pythonVersion/python-$pythonVersion-embed-amd64.zip"
$getPipUrl     = "https://bootstrap.pypa.io/get-pip.py"

function Install-Python {
    $zipPath = "$pythonDir\python-embed.zip"
    $ok = Get-RemoteFile -url $pythonZipUrl -dest $zipPath -label "Python $pythonVersion (embeddable)"
    if (-not $ok) { return }

    Write-Host "    Extracting Python..." -ForegroundColor Cyan
    Expand-Archive -Path $zipPath -DestinationPath $pythonDir -Force
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

    # The embeddable package ships with site-packages disabled by default.
    # Un-comment "import site" in the ._pth file to enable pip package imports.
    $pthFile = Get-ChildItem "$pythonDir" -Filter "*._pth" | Select-Object -First 1
    if ($pthFile) {
        $content = Get-Content $pthFile.FullName -Raw
        $content = $content -replace "#import site", "import site"
        Set-Content $pthFile.FullName -Value $content
    }

    # Bootstrap pip into the embeddable Python
    Write-Host "    Installing pip..." -ForegroundColor Cyan
    $getPipPath = "$pythonDir\get-pip.py"
    if (Get-RemoteFile -url $getPipUrl -dest $getPipPath -label "get-pip.py") {
        & $pythonExe $getPipPath --quiet
        Remove-Item $getPipPath -Force -ErrorAction SilentlyContinue
    }
    Write-Host "    Python $pythonVersion installed." -ForegroundColor Green
    Write-Log "Python $pythonVersion installed."
}

# Check Python is present; install if missing. No update logic needed
# for the embeddable package - it doesn't self-update.
function Initialize-Python {
    Write-Host "  [python]  " -NoNewline -ForegroundColor White
    if (!(Test-Path $pythonExe)) {
        Write-Host "Not found. Installing portable Python $pythonVersion..." -ForegroundColor Yellow
        Install-Python
        return
    }
    $v = (& $pythonExe --version 2>&1).Trim()
    Write-Host "$v (portable)" -ForegroundColor Green
}

# ---------- ffmpeg ------------------------------------------
# Downloads the essentials build from gyan.dev (~80 MB).
# Extracts only the three executables into tools\ffmpeg\.
$ffmpegZipUrl = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip"

function Install-FFmpeg {
    $zipPath    = "$ffmpegDir\ffmpeg.zip"
    $extractDir = "$ffmpegDir\__extract"

    $ok = Get-RemoteFile -url $ffmpegZipUrl -dest $zipPath -label "ffmpeg (~80 MB, please wait)"
    if (-not $ok) { return }

    Write-Host "    Extracting ffmpeg..." -ForegroundColor Cyan
    Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force

    # The zip contains a versioned subfolder with a bin\ directory inside
    $exes = Get-ChildItem "$extractDir" -Recurse `
                -Include "ffmpeg.exe","ffprobe.exe","ffplay.exe" |
            Where-Object { $_.DirectoryName -match "\\bin$" }
    foreach ($exe in $exes) { Copy-Item $exe.FullName -Destination $ffmpegDir -Force }

    Remove-Item $zipPath    -Force -Recurse -ErrorAction SilentlyContinue
    Remove-Item $extractDir -Force -Recurse -ErrorAction SilentlyContinue
    Write-Host "    ffmpeg installed." -ForegroundColor Green
    Write-Log "ffmpeg installed."
}

# Check ffmpeg is present; install if missing.
# ffmpeg does not auto-update; reinstall manually when needed.
function Initialize-FFmpeg {
    Write-Host "  [ffmpeg]  " -NoNewline -ForegroundColor White
    if (!(Test-Path $ffmpegExe)) {
        Write-Host "Not found. Installing..." -ForegroundColor Yellow
        Install-FFmpeg
        return
    }
    $v = ((& $ffmpegExe -version 2>&1)[0]) -replace "ffmpeg version ", ""
    Write-Host $v.Trim() -ForegroundColor Green
}

# ---------- spotdl ------------------------------------------
# Installed via pip into the portable Python environment.
# No admin required; runs entirely in tools\python\.
function Get-SpotDLLatestVersion {
    try {
        $info = Invoke-RestMethod "https://pypi.org/pypi/spotdl/json" -ErrorAction Stop
        return $info.info.version
    } catch { return $null }
}

function Install-SpotDL {
    Write-Host "    Installing spotdl via pip..." -ForegroundColor Cyan
    & $pythonExe -m pip install spotdl --quiet
    Write-Host "    spotdl installed." -ForegroundColor Green
    Write-Log "spotdl installed."
}

# Check spotdl version via Python import; install or update as needed
function Initialize-SpotDL {
    Write-Host "  [spotdl]  " -NoNewline -ForegroundColor White
    $check     = & $pythonExe -c "import spotdl; print(spotdl.__version__)" 2>&1
    $installed = ($LASTEXITCODE -eq 0 -and $check -notmatch "Error|No module")

    if (-not $installed) {
        Write-Host "Not found. Installing..." -ForegroundColor Yellow
        Install-SpotDL
        return
    }

    $local  = $check.Trim()
    $latest = Get-SpotDLLatestVersion
    Write-Host "v$local" -NoNewline -ForegroundColor Green

    if ($null -eq $latest) {
        Write-Host " (update check failed)" -ForegroundColor DarkGray
        return
    }

    if ($local -ne $latest) {
        Write-Host " -> v$latest. Updating..." -ForegroundColor Yellow
        & $pythonExe -m pip install --upgrade spotdl --quiet
        Write-Host "    Updated to v$latest." -ForegroundColor Green
        Write-Log "spotdl updated $local -> $latest"
    } else {
        Write-Host " (up to date)" -ForegroundColor DarkGray
    }
}

# Run all four tool checks/installs in sequence at startup
function Initialize-AllTools {
    Show-Header "TOOL SETUP"
    Write-Host "  Tools folder: $toolsDir" -ForegroundColor DarkGray
    Write-Host ""
    Initialize-YtDlp
    Write-Host ""
    Initialize-Python
    Write-Host ""
    Initialize-FFmpeg
    Write-Host ""
    Initialize-SpotDL
    Write-Host ""
    Write-Host "  All tools ready." -ForegroundColor Green
    Write-Log "Tool initialization complete."
    Start-Sleep -Seconds 2
}

# ============================================================
#  SECTION 8: ARGUMENT BUILDERS
#  Convert the config settings objects into actual CLI arg
#  arrays that are passed to yt-dlp and spotdl at runtime.
# ============================================================

# Build the yt-dlp argument list for audio extraction based on current config
function Build-AudioArgs {
    param($cfg, [string]$outputTemplate)
    $s    = $cfg.ytdlp
    $args = @(
        "--extract-audio",
        "--audio-format",     $s.audioFormat,
        "--audio-quality",    $s.audioQuality,
        "--output",           $outputTemplate,
        "--download-archive", $ytArchive,
        "--progress"
    )
    if ($s.embedThumbnail) { $args += "--embed-thumbnail" }
    if ($s.embedMetadata)  { $args += "--embed-metadata"  }
    if ($s.writeAutoSubs)  { $args += "--write-auto-subs" }
    if ($s.embedSubs)      { $args += "--embed-subs"      }
    if ($s.ignoreErrors)   { $args += "--ignore-errors"   }
    if ($s.sponsorBlock)   { $args += "--sponsorblock-remove"; $args += "sponsor" }
    if ($s.noPlaylist)     { $args += "--no-playlist"     }
    return $args
}

# Build the spotdl argument list based on current config.
# overrideOverwrite lets individual callers force "skip" or "force"
# regardless of the saved setting (used for duplicate re-downloads).
function Build-SpotArgs {
    param(
        $cfg,
        [string]$outputTemplate,
        [string]$overrideOverwrite = "",
        [string]$provider = "youtube-music"
    )
    $s  = $cfg.spotdl
    $ow = if ($overrideOverwrite) { $overrideOverwrite } else { $s.overwrite }
    $args = @(
        "--audio",    $provider,
        "--lyrics",   $s.lyrics,
        "--bitrate",  $s.bitrate,
        "--format",   $s.format,
        "--overwrite",$ow,
        "--threads",  $s.threadCount,
        "--output",   $outputTemplate
    )
    if ($s.generateLRC) { $args += "--generate-lrc" }
    if ($s.printErrors) { $args += "--print-errors"  }
    if ($s.saveFile)    { $args += "--save-errors"   }
    return $args
}

# ============================================================
#  SECTION 9: DOWNLOAD FUNCTIONS
# ============================================================

# Run spotdl with YouTube Music as the audio provider.
# If YouTube Music is unavailable (known error patterns), automatically
# retries the same download using plain YouTube as a fallback.
function Invoke-SpotifyDownload {
    param(
        [string]$url,
        [string]$outputDir,
        [string]$overwrite = ""
    )
    $outTemplate = "$outputDir\{album_artist} ft. {artists} - {title}.{ext}"

    Write-Host "  Trying YouTube Music provider..." -ForegroundColor Cyan
    $spotArgs = Build-SpotArgs -cfg $script:config -outputTemplate $outTemplate `
                               -overrideOverwrite $overwrite -provider "youtube-music"
    $result   = & $pythonExe -m spotdl $url @spotArgs 2>&1

    # Detect known YouTube Music connection/parser failures
    $ytmFailed = ($result | Where-Object {
        $_ -match "KeyError|DownloaderError|LookupError|check_ytmusic|Failed to check"
    }).Count -gt 0

    if ($ytmFailed) {
        Write-Host "  YouTube Music unavailable. Falling back to YouTube..." -ForegroundColor Yellow
        Write-Log "YouTube Music failed, retrying with YouTube." "WARN"
        $spotArgs = Build-SpotArgs -cfg $script:config -outputTemplate $outTemplate `
                                   -overrideOverwrite $overwrite -provider "youtube"
        & $pythonExe -m spotdl $url @spotArgs
    }
}

# Download a video from any yt-dlp supported site
# (YouTube, TikTok, Instagram, Twitter/X, Reddit, Twitch, etc.)
function Invoke-VideoDownload {
    param($cfg)
    Show-Header "VIDEO DOWNLOAD"
    Write-Host "  Supports: YouTube, TikTok, Instagram, Twitter/X, Reddit, Twitch and 1000+ sites." -ForegroundColor DarkGray
    Write-Host "  Just paste any video URL below." -ForegroundColor DarkGray
    Write-Host ""
    $url = Get-ValidURL "Enter video URL:"
    if ($null -eq $url) { return }
    Write-Host ""
    Write-Host "  Downloading..." -ForegroundColor Green
    Write-Host "  Output: $($cfg.videoDir)" -ForegroundColor DarkGray
    Write-Host ""

    & $ytdlpExe `
        -f "bv*+ba/b" `
        --merge-output-format mp4 `
        --embed-subs `
        --write-auto-subs `
        --output "$($cfg.videoDir)\%(title)s.%(ext)s" `
        --download-archive $ytArchive `
        --ignore-errors `
        --embed-metadata `
        --embed-thumbnail `
        --progress `
        $url

    Write-Log "Video downloaded: $url"
    Write-Host ""
    Write-Host "  Download complete." -ForegroundColor Green
    Pause-Return
}

# Download audio from YouTube (or any yt-dlp supported source).
# Uses the yt-dlp settings from config for format/quality/metadata options.
function Invoke-AudioDownload {
    param($cfg)
    Show-Header "AUDIO DOWNLOAD - YouTube"
    Write-Host "  For Spotify tracks, go back and use the Spotify option." -ForegroundColor DarkGray
    Write-Host ""
    $url = Get-ValidURL "Enter YouTube song or playlist URL:"
    if ($null -eq $url) { return }
    Write-Host ""
    Write-Host "  Downloading $($cfg.ytdlp.audioFormat) $($cfg.ytdlp.audioQuality)..." -ForegroundColor Green
    Write-Host "  Output: $($cfg.audioDir)" -ForegroundColor DarkGray
    Write-Host ""

    $outTemplate = "$($cfg.audioDir)\%(artist,album_artist,uploader)s - %(title)s.%(ext)s"
    $ytArgs      = Build-AudioArgs -cfg $cfg -outputTemplate $outTemplate
    & $ytdlpExe @ytArgs $url

    # Record downloaded titles in history for future duplicate detection
    try {
        $titles = (& $ytdlpExe --get-title --flat-playlist $url 2>$null)
        foreach ($t in $titles) { if ($t) { Add-ToHistory $t } }
    } catch {}

    Write-Log "Audio downloaded: $url"
    Write-Host ""
    Write-Host "  Download complete." -ForegroundColor Green
    Pause-Return
}

# Core Spotify download logic shared by both the manual URL entry
# and the favourites quick-download paths.
# Fetches the track list first, separates new vs duplicate tracks,
# downloads new tracks, then interactively handles duplicates.
function Invoke-SpotifyPlaylist {
    param([string]$url, [object]$cfg)
    Write-Host ""
    Write-Host "  Fetching track list from Spotify..." -ForegroundColor Cyan

    # Save the playlist metadata to a temp file so we can parse track names
    $tempFile = "$scriptDir\__temp.spotdl"
    & $pythonExe -m spotdl save $url --save-file $tempFile 2>&1 | Out-Null

    $tracks = @()
    if (Test-Path $tempFile) {
        try {
            $data   = Get-Content $tempFile -Raw | ConvertFrom-Json
            $tracks = @($data.songs | ForEach-Object { "$($_.artist) - $($_.name)" })
        } catch {
            Write-Host "  Could not parse track list - duplicate check skipped." -ForegroundColor DarkYellow
        }
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    }

    # Classify each track as new or already downloaded
    $duplicates = @()
    $newTracks  = @()
    foreach ($t in $tracks) {
        if (Test-InHistory $t) { $duplicates += $t } else { $newTracks += $t }
    }

    if ($tracks.Count -gt 0) {
        Write-Host "  Total   : $($tracks.Count)" -ForegroundColor White
        Write-Host "  New     : $($newTracks.Count)" -ForegroundColor Green
        Write-Host "  Dupes   : $($duplicates.Count)" -ForegroundColor Yellow
        Write-Host ""
    }

    # Download only the new tracks (skip duplicates at this stage)
    if ($newTracks.Count -gt 0 -or $tracks.Count -eq 0) {
        Invoke-SpotifyDownload -url $url -outputDir $cfg.audioDir
        foreach ($t in $newTracks) { Add-ToHistory $t }
        Write-Log "Spotify download completed: $url"
    } else {
        Write-Host "  No new tracks to download." -ForegroundColor DarkGray
    }

    # Handle duplicates interactively
    if ($duplicates.Count -gt 0) {
        Write-Host ""
        Write-Host "  ---- Duplicate Tracks ($($duplicates.Count)) ----" -ForegroundColor Yellow
        $i = 1
        foreach ($d in $duplicates) {
            Write-Host "   [$i] $d" -ForegroundColor DarkYellow
            $i++
        }
        Write-Host ""
        Write-Host "  What would you like to do with these duplicates?" -ForegroundColor Cyan
        Write-Host "   [A] Re-download ALL"
        Write-Host "   [S] Select specific ones to re-download"
        Write-Host "   [N] Skip all (keep existing files)"
        Write-Host ""

        $dupChoice    = (Read-Host "  Choice [A/S/N]").Trim().ToUpper()
        $toRedownload = @()

        switch ($dupChoice) {
            'A' { $toRedownload = $duplicates }
            'S' {
                # Accept a comma-separated list of numbers e.g. "1,3,5"
                $nums = (Read-Host "  Numbers (e.g. 1,3,5)") -split "," | ForEach-Object { $_.Trim() }
                foreach ($n in $nums) {
                    if ($n -match "^\d+$") {
                        $idx = [int]$n - 1
                        if ($idx -ge 0 -and $idx -lt $duplicates.Count) {
                            $toRedownload += $duplicates[$idx]
                        }
                    }
                }
            }
            'N' { Write-Host "  Skipping duplicates." -ForegroundColor DarkGray }
            default { Write-Host "  Invalid - skipping duplicates." -ForegroundColor Red }
        }

        # Re-download selected duplicates using "force" overwrite
        foreach ($track in $toRedownload) {
            $songName = ($track -split " - ", 2)[-1]
            Write-Host ""
            Write-Host "  Re-downloading: $track" -ForegroundColor Cyan
            Invoke-SpotifyDownload -url "`"$songName`"" -outputDir $cfg.audioDir -overwrite "force"
        }
    }

    Write-Host ""
    Write-Host "  All done!" -ForegroundColor Green
}

# Prompt for a Spotify URL then run the download.
# Offers to save the URL as a favourite after completion.
function Invoke-SpotifyManual {
    param($cfg)
    Show-Header "SPOTIFY DOWNLOAD"
    $url = Get-ValidURL "Enter Spotify track or playlist URL:"
    if ($null -eq $url) { return }
    Invoke-SpotifyPlaylist -url $url -cfg $cfg

    Write-Host ""
    $saveFav = (Read-Host "  Save this as a favourite? [Y/N]").Trim().ToUpper()
    if ($saveFav -eq 'Y') {
        $favName = (Read-Host "  Name for this playlist").Trim()
        if (-not [string]::IsNullOrWhiteSpace($favName)) {
            Add-Favourite -name $favName -url $url -type "spotify"
        }
    }
    Pause-Return
}

# Download a saved favourite playlist by its index in the favourites list
function Invoke-FavouriteDownload {
    param($cfg, [int]$favIndex)
    $favs = Get-Favourites
    if ($favIndex -lt 0 -or $favIndex -ge $favs.Count) {
        Write-Host "  Invalid selection." -ForegroundColor Red
        Pause-Return
        return
    }
    $fav = $favs[$favIndex]
    Show-Header "DOWNLOADING: $($fav.name)"
    Invoke-SpotifyPlaylist -url $fav.url -cfg $cfg
    Pause-Return
}

# ============================================================
#  SECTION 10: MENUS
# ============================================================

# Audio Download menu.
# Static options (YouTube, Spotify URL) are always shown first.
# Saved favourites are listed below as numbered shortcuts.
# Selecting a favourite opens a sub-menu: download or back.
function Show-AudioMenu {
    param($cfg)
    while ($true) {
        Show-Header "AUDIO DOWNLOAD"
        Write-Host "  [1]  YouTube Audio"
        Write-Host "  [2]  Spotify - enter URL"
        Write-Host ""

        # Dynamically list saved favourites starting at [3]
        $favs = Get-Favourites
        if ($favs.Count -gt 0) {
            Write-Host "  --- Spotify Favourites ---" -ForegroundColor Yellow
            $i = 3
            foreach ($f in $favs) {
                Write-Host "  [$i]  $($f.name)" -ForegroundColor Cyan
                Write-Host "       $($f.url)" -ForegroundColor DarkGray
                $i++
            }
            Write-Host ""
        }

        Write-Host "  [F]  Manage favourites"
        Write-Host "  [B]  Back"
        Write-Host ""

        $choice = (Read-Host "  Choose").Trim().ToUpper()

        if ($choice -match "^\d+$") {
            $num = [int]$choice
            switch ($num) {
                1 { Invoke-AudioDownload -cfg $cfg }
                2 { Invoke-SpotifyManual -cfg $cfg }
                default {
                    # Numbers 3+ map to favourites - show a confirm sub-menu
                    $favIdx = $num - 3
                    if ($favIdx -ge 0 -and $favIdx -lt $favs.Count) {
                        $fav = $favs[$favIdx]
                        while ($true) {
                            Show-Header "SPOTIFY FAVOURITE"
                            Write-Host "  Name : $($fav.name)" -ForegroundColor Cyan
                            Write-Host "  URL  : $($fav.url)" -ForegroundColor DarkGray
                            Write-Host ""
                            Write-Host "  [D]  Download this playlist"
                            Write-Host "  [B]  Back to audio menu"
                            Write-Host ""
                            $favChoice = (Read-Host "  Choose [D/B]").Trim().ToUpper()
                            switch ($favChoice) {
                                'D' {
                                    Invoke-FavouriteDownload -cfg $cfg -favIndex $favIdx
                                    break
                                }
                                'B' { break }
                                default {
                                    Write-Host "  Invalid choice." -ForegroundColor Red
                                    Start-Sleep -Seconds 1
                                }
                            }
                            # Exit the inner while loop on D or B
                            if ($favChoice -eq 'D' -or $favChoice -eq 'B') { break }
                        }
                    } else {
                        Write-Host "  Invalid choice." -ForegroundColor Red
                        Start-Sleep -Seconds 1
                    }
                }
            }
        } else {
            switch ($choice) {
                'F' { Show-FavouritesManager -cfg $cfg }
                'B' { return }
                default { Write-Host "  Invalid choice." -ForegroundColor Red; Start-Sleep -Seconds 1 }
            }
        }
    }
}

# Main menu - entry point after startup
function Show-MainMenu {
    param($cfg)
    while ($true) {
        Show-Header "CHAOS MEDIA DOWNLOADER"
        Write-Host "  [1]  Audio Download         (YouTube, Spotify)"
        Write-Host "  [2]  Video Download         (YouTube, TikTok, Instagram + 1000 more)"
        Write-Host "  [3]  Settings               (quality, format, lyrics, folders...)"
        Write-Host "  [4]  Exit"
        Write-Host ""
        Write-Host "  Audio : $($cfg.audioDir)" -ForegroundColor DarkGray
        Write-Host "  Video : $($cfg.videoDir)" -ForegroundColor DarkGray
        Write-Host ""
        $choice = (Read-Host "  Choose [1-4]").Trim()
        switch ($choice) {
            '1' { Show-AudioMenu      -cfg $cfg }
            '2' { Invoke-VideoDownload -cfg $cfg }
            '3' { Show-SettingsMenu   -cfg $cfg }
            '4' { Write-Host "  Bye!`n" -ForegroundColor Cyan; exit }
            default { Write-Host "  Invalid choice." -ForegroundColor Red; Start-Sleep -Seconds 1 }
        }
    }
}

# ============================================================
#  SECTION 11: ENTRY POINT
#  1. Initialize (check/install/update) all tools
#  2. Load config (or run first-time setup)
#  3. Ensure download directories exist
#  4. Launch main menu
# ============================================================
try {
    Initialize-AllTools

    # Migrate favourites.json: if it exists but was saved as a bare object
    # (not an array) by an older version, re-save it in correct array format.
    # Migrate old favourites.json to new one-line-per-record format.
    # Old format was a JSON array [] or bare object {} with no "type" field.
    # New format: one compact JSON object per line, each with name/url/type.
    if (Test-Path $favsFile) {
        try {
            $raw = Get-Content $favsFile -Raw -Encoding utf8
            $trimmed = $raw.Trim()
            # Detect old format: starts with [ or { (JSON array or bare object)
            if ($trimmed.StartsWith("[") -or $trimmed.StartsWith("{")) {
                $parsed = @()
                if ($trimmed.StartsWith("{")) {
                    $parsed = @($trimmed | ConvertFrom-Json)
                } else {
                    $parsed = @($trimmed | ConvertFrom-Json)
                }
                $lines = $parsed | ForEach-Object {
                    $t = if ($_.type) { $_.type } else { "spotify" }
                    [PSCustomObject]@{ name = $_.name; url = $_.url; type = $t } |
                        ConvertTo-Json -Depth 3 -Compress
                }
                $lines | Set-Content $favsFile -Encoding utf8
                Write-Host "  Favourites migrated to new format." -ForegroundColor DarkGray
            }
        } catch {}
    }

    $script:config = Get-Config
    Confirm-Dirs -cfg $script:config
    Show-MainMenu -cfg $script:config
} catch {
    Write-Host ""
    Write-Host "  UNHANDLED ERROR: $_" -ForegroundColor Red
    Write-Host "  Check $logFile for details." -ForegroundColor Yellow
    Write-Log "Fatal: $_" "ERROR"
    Pause-Return
}
