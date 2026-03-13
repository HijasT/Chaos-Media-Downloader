# Chaos Media Downloader

![Chaos Media Downloader Banner](https://img.shields.io/badge/Chaos%20Media%20Downloader-Portable%20Media%20Toolkit-blue?style=for-the-badge)

![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-5391FE?logo=powershell&logoColor=white)
![Windows](https://img.shields.io/badge/Platform-Windows-blue)
![yt-dlp](https://img.shields.io/badge/yt--dlp-supported-red)
![spotDL](https://img.shields.io/badge/spotDL-supported-green)
![FFmpeg](https://img.shields.io/badge/FFmpeg-enabled-orange)
![License](https://img.shields.io/badge/license-MIT-green)
![Status](https://img.shields.io/badge/status-active-success)

---

## Overview

**Chaos Media Downloader** is a **portable PowerShell media downloader** built around:

- yt-dlp
- spotDL
- FFmpeg
- Python

It allows downloading **video and music from hundreds of platforms** while keeping everything **fully self-contained and portable**.

No system installation required.

All tools run locally inside the project folder.

---

## Features

- Fully portable architecture
- Built-in **yt-dlp support**
- Built-in **spotDL support for Spotify**
- Uses **FFmpeg for media processing**
- Uses **local Python runtime**
- Download archive system (prevents duplicates)
- Favorite links manager
- Song tracking
- JSON configuration
- Structured logging
- Clean terminal interface

---

## Supported Sources

### Via yt-dlp

- YouTube
- Twitter / X
- Instagram
- TikTok
- Vimeo
- Facebook
- Reddit
- Hundreds of additional supported websites

### Via spotDL

- Spotify tracks
- Spotify albums
- Spotify playlists

---

## Folder Structure

```
project-root/
│
├── MediaDownloader.ps1
│
├── config.json
├── favourites.json
│
├── downloaded-songs.txt
├── yt-dlp-archive.txt
│
├── Logs/
│   └── log.txt
│
└── tools/
    ├── yt-dlp/
    │   └── yt-dlp.exe
    │
    ├── spotdl/
    │   └── spotdl.exe
    │
    ├── python/
    │   └── python.exe
    │
    └── ffmpeg/
        └── ffmpeg.exe
```

All dependencies are stored locally inside the **tools** directory.

---

## Requirements

- Windows
- PowerShell **5.1 or newer**
- Internet connection

No global installation of:

- Python
- FFmpeg
- yt-dlp
- spotDL

is required.

---

## Installation

Clone the repository:

```bash
git clone https://github.com/yourusername/Chaos-media-downloader.git
```

Or download the ZIP and extract it.

Navigate into the folder.

---

## Running the Script

Run the script:

```powershell
powershell -ExecutionPolicy Bypass -File MediaDownloader.ps1
```

If PowerShell blocks script execution:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
```

Then run the script again.

---

## Configuration

Configuration file:

```
config.json
```

You can customize:

- Download folders
- Audio format
- Video format
- Quality settings
- yt-dlp parameters
- spotDL settings

---

## Logging

Logs are written to:

```
Logs/log.txt
```

Example:

```
2026-03-13 21:02:11 [INFO] Download started
2026-03-13 21:02:30 [INFO] Download finished
```

---

## Duplicate Download Protection

Two archive files prevent repeated downloads.

| File | Purpose |
|-----|-----|
| yt-dlp-archive.txt | Tracks downloaded videos |
| downloaded-songs.txt | Tracks downloaded songs |

---

## Version

Current Version

```
v1.0
```

---

## Version History

### v1.0

Initial release

Features included:

- Portable downloader
- yt-dlp integration
- spotDL integration
- FFmpeg support
- Python runtime
- Download archive system
- Favorites manager
- JSON configuration
- Logging system

---

## Tools Used

This project bundles the following open source tools.

- yt-dlp
- spotDL
- FFmpeg
- Python

---

## License

MIT License

You are free to use, modify, and distribute this software.

---

## Disclaimer

Use responsibly and respect copyright laws and platform terms of service when downloading media.
