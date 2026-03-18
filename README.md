# HAPxFer

**Free, open-source macOS app for transferring music to the Sony HAP-Z1ES.**

Replaces the discontinued Sony HAP Music Transfer app that no longer works on modern macOS.

---

## Why This App Exists

The Sony HAP-Z1ES is a high-resolution music player with a built-in hard drive. Sony provided a companion app called "HAP Music Transfer" to sync music from your computer to the player over the local network.

That app no longer works on modern macOS for two reasons:

- **SMB1 removed** — macOS dropped SMB1 support starting with High Sierra (2017). The HAP-Z1ES only speaks SMB1.
- **32-bit app removed** — HAP Music Transfer was 32-bit. macOS Catalina (2019) dropped all 32-bit app support.

Sony has effectively end-of-lifed the software with no further updates. **HAPxFer fills this gap.**

## Features

- **SMB1 file transfer** — Connects to the HAP-Z1ES's internal share using the same protocol the original app used
- **Folder sync** — Monitor folders on your Mac and sync new, modified, and deleted files to the player
- **Artist tag override** — Optionally set the Artist metadata to the folder name before upload, solving the HAP-Z1ES's lack of Album Artist sorting (source files are never modified)
- **Wake-on-LAN** — Wake the device from standby before syncing
- **Scheduled sync** — Set an interval to sync automatically while the app is open
- **Browse device** — View and manage files on the HAP-Z1ES directly, with HDD space and track/album counts
- **Activity log** — Full log of uploads, deletions, and errors with CSV export
- **Drag & drop** — Drop folders from Finder to add them to the monitor list
- **Universal binary** — Runs natively on Apple Silicon and Intel Macs

## Supported Audio Formats

| Category | Formats |
|----------|---------|
| DSD | DSF, DFF (2.8/5.6 MHz) |
| Lossless | FLAC, WAV, AIFF, ALAC |
| Lossy | MP3, AAC/M4A |
| Other | WMA, ATRAC (OMA, AA3) |

## Getting Started

### Requirements

- macOS 14 Sonoma or later
- Sony HAP-Z1ES on the same local network
- Network Standby enabled on the HAP-Z1ES (for Wake-on-LAN)

### Installation

1. Download the latest release from the [Releases](https://github.com/danielrweber/HAPxFer/releases) page
2. Move `HAPxFer.app` to your Applications folder
3. Right-click → Open (required since the app is not notarized)

### First Use

1. **Find your HAP-Z1ES IP address** — Check your router's connected devices list, or look in the HAP-Z1ES settings under Network Settings
2. **Enter the IP** and click **Connect**
3. **Add folders** — Click the + button or drag folders from Finder into the Monitored Folders view
4. **Sync** — Click Sync Now to transfer your music

The HAP-Z1ES will automatically detect and analyze new files after transfer.

## Artist Tag Override

The HAP-Z1ES does not support browsing by Album Artist. When an album features multiple artists, the player's library can become fragmented — the same album may appear under several different artist names.

HAPxFer offers an optional Artist Tag Override (per folder) that sets the Artist metadata field to the top-level folder name (the main artist) before uploading. Your source files are never modified — changes are applied to a temporary copy during transfer.

To enable: toggle "Override Artist tag" on a folder in the Monitored Folders view.

To apply to files already on the device: Settings → Artist Override → Re-sync.

## Building from Source

### Prerequisites

- Xcode 16+
- The project includes pre-built universal (arm64 + x86_64) Samba/libsmbclient dylibs in the `Frameworks/` directory

### Build

1. Clone the repo
2. Open `HAPxFer.xcodeproj` in Xcode
3. Build and run (⌘R)

The bundled frameworks are self-contained — no Homebrew or other dependencies needed at runtime.

## How It Works

HAPxFer uses [Samba's](https://www.samba.org/) `libsmbclient` library to speak SMB1 (NT1 protocol) directly to the HAP-Z1ES. The device exposes an `HAP_Internal` SMB share where music files are stored.

The sync engine:
1. Scans monitored folders for audio files
2. Compares against a local database of previously synced files
3. Uploads new/modified files and optionally deletes removed files
4. Tracks all operations in an activity log

## License

HAPxFer is free software licensed under the [GNU General Public License v3.0](LICENSE).

This project uses libsmbclient from the [Samba project](https://www.samba.org/) (GPL-3.0). See [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES) for all dependency licenses.

## Disclaimer

HAPxFer is not affiliated with or endorsed by Sony Corporation. Sony, HAP-Z1ES, and HAP Music Transfer are trademarks of Sony Corporation.
