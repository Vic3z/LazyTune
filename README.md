<img src="assets/icon.png" width="160" height="160" alt="LazyTune app icon" align="left"/>

<h3>LazyTune</h3>

**All-in-one macOS per-app audio mixer and universal media key controller (`F7` / `F8` / `F9`).**
Control the volume of every app independently, route audio to different speakers, and control playback across **Spotify, YouTube, SoundCloud, Twitch, Safari, Chrome, Brave, Arc, VLC, IINA**, and **100+ web players** without macOS ever launching Apple Music by mistake. Engineered for minimal resource usage (**~50 MB RAM**, **0.0% idle CPU**, lazy-loaded EQ, and zero background update telemetry).

<br clear="all"/>

<p align="center">
  <a href="https://github.com/Vic3z/LazyTune/releases/latest/download/LazyTune.zip"><img src="assets/download-badge.svg" alt="Download for macOS" height="32"></a>
  <a href="https://github.com/Vic3z/LazyTune"><img src="https://img.shields.io/badge/Repo-Vic3z%2FLazyTune-0A84FF?style=for-the-badge&labelColor=1c1c1e&logo=github&logoColor=white" alt="GitHub Repository"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-GPLv3-3a3a3c?style=for-the-badge&labelColor=1c1c1e" alt="License: GPL v3"></a>
  <a href="https://www.apple.com/macos/"><img src="https://img.shields.io/badge/macOS-15.4%2B-3a3a3c?style=for-the-badge&labelColor=1c1c1e&logo=apple&logoColor=white" alt="macOS 15.4+"></a>
  <img src="https://img.shields.io/badge/RAM-~50_MB-30D158?style=for-the-badge&labelColor=1c1c1e" alt="RAM ~50 MB">
  <img src="https://img.shields.io/badge/Idle_CPU-0.0%25-30D158?style=for-the-badge&labelColor=1c1c1e" alt="Idle CPU 0.0%">
</p>

<p align="center">
  <img src="assets/screenshot-media.png" alt="LazyTune popup showing the Now Playing mini-player bar, per-device output volume sliders, and per-app audio mixer" width="510">
</p>

---

## ✨ What's New in LazyTune

### 🎵 Universal Media Keys (`F7` / `F8` / `F9`) & Web/Native Player Control
- **Universal `F7` (Previous), `F8` (Play/Pause), `F9` (Next)** — Hardware media keys control whichever media player or browser tab is currently active, without ever waking or launching Apple Music when it's closed.
- **CoreAudio-Aware Smart Target Resolution** — LazyTune combines browser/player inspection with its real-time CoreAudio process tap to automatically know which tab or app is actually producing sound right now.
- **Now Playing Mini-Player in Menu Bar** — View current track title, artist, album, and artwork directly at the top of the popup, with instant Play/Pause, Next, Previous, Favorite/Like, Bring-to-Front, and a target selector menu to pin any open player or browser tab.
- **103 Built-in Web Media Adapters + Universal HTML5 Fallback** — Works out of the box with **YouTube, YouTube Music, SoundCloud, Spotify Web, Twitch, Bandcamp, Netflix, Tidal, Deezer, MixCloud, Apple Podcasts, Coursera, Udemy**, and any website with an HTML5 `<video>` or `<audio>` element across **Safari, Google Chrome, Brave, Arc, Microsoft Edge, Vivaldi, Orion, and Opera**.
- **Native Desktop Players** — Native control and real-time push notifications (`DistributedNotificationCenter`) for **Spotify, VLC, IINA, VOX, Swinsian, TIDAL, Qobuz, Deezer, Amazon Music, and Apple Music**.
- **Auto-Pause on Headphone Unplug & Sleep** — Automatically pauses active playback when Bluetooth headphones (AirPods, Sony, Bose) or external USB DACs disconnect, or when your Mac goes to sleep.
- **Tahoe Now Playing HUD** — Optional on-screen glass HUD displaying track metadata and playback state transitions when pressing media keys or switching players.

### ⚡ Ultra-Lightweight & Zero-Overhead Engine
- **Zero-Touch Passthrough (Sticky)** — Apps left at default parameters (`100%` volume, `1x` boost, no EQ/AutoEQ/Loudness, system default output) bypass CoreAudio Process Taps completely for bit-perfect native macOS audio, `0 ms` extra latency, and zero crackling. Taps attach on-demand on first adjustment and clean up automatically after 30s of inactivity or on Mac sleep/wake. *(Toggleable in Settings → Audio).*
- **Native macOS Bluetooth & Device Switching** — Connects Bluetooth headphones, USB DACs, and external displays with standard macOS behavior out of the box (optional *Enforce Output Priority Order* toggle in Settings → Audio).
- **Sleep/Wake CoreAudio Resilience** — Automatically tears down active taps on sleep and rebuilds them cleanly after wake, disables unnecessary sub-tap drift resampling on shared hardware clock domains, and runs a dynamic Anti-App Nap guard strictly while taps are active.
- **~50 MB RAM Footprint (-76% vs upstream)** — All 103 web media strategies are pre-compiled into a static JSON bundle (`MediaStrategies.json`), completely eliminating `JavaScriptCore` (`WebKit malloc`) from runtime memory.
- **0.0% Idle CPU** — Uses native macOS push notifications (`DistributedNotificationCenter`) and in-memory CoreAudio peak levels instead of background AppleScript polling; pauses UI VU-meter timers completely while the popup is closed.
- **Lazy-Loaded EQ & AutoEQ** — The 10-band biquad filter banks and the 6,000+ headphone AutoEQ catalog consume **0 bytes of RAM and 0% CPU** unless you explicitly enable EQ or open the AutoEQ picker.
- **Zero Background Update Checks** — `Sparkle.framework` background update telemetry is completely removed.

---

## 🚀 Download & Install

### Option 1: Download Prebuilt App (Recommended)
1. Download **[`LazyTune.zip`](https://github.com/Vic3z/LazyTune/releases/latest/download/LazyTune.zip)** from the [Releases](https://github.com/Vic3z/LazyTune/releases) page.
2. Double-click `LazyTune.zip` to extract **LazyTune.app** and drag it into your **Applications** folder.
3. Since LazyTune is signed ad-hoc (without a paid Apple Developer ID), if macOS Gatekeeper blocks the first launch, run:
   ```bash
   xattr -cr /Applications/LazyTune.app
   ```

### Option 2: Build from Source (Works with Command Line Tools)

```bash
git clone https://github.com/Vic3z/LazyTune.git
cd LazyTune
./scripts/build-local-app.sh
cp -R build/LazyTune.app /Applications/LazyTune.app
open /Applications/LazyTune.app
```

---

## 🛠 Full Feature Overview

### 🎚 Per-App Audio Mixer & Routing
- **Per-app volume & mute** — Individual sliders and mute toggles for each running application
- **Per-app volume boost** — `1x / 2x / 3x / 4x` gain boost for quiet apps or videos
- **Multi-device output & per-app routing** — Send specific apps to different audio outputs (e.g. music to speakers, calls to headphones) or route to multiple devices simultaneously
- **Device priority & auto-restore** — Automatically switch to your preferred output/input device when connected and restore per-app settings on reconnect
- **Smart volume backend (Hardware / DDC / Software)** — Control volume on built-in speakers, Bluetooth headphones, USB DACs, and external HDMI/DisplayPort monitors (via DDC)

### ⌨️ Global Shortcuts & URL Automation
- **Global hotkeys** — Configurable shortcuts for Play/Pause, Next, Previous, Like/Favorite, Switch Active Media Player, Pin Active Tab, Show Track Info HUD, App Volume Up/Down/Mute, and Toggle Popup
- **URL schemes (`lazytune://` & `finetune://`)** — Automate playback and mixer actions from Raycast, Alfred, Apple Shortcuts, or shell scripts:
  ```bash
  open "lazytune://media-play-pause"
  open "lazytune://media-next"
  open "lazytune://media-previous"
  open "lazytune://media-switch-player"
  ```

### 🎛 Lazy-Loaded EQ & Audio Shaping
- **10-band graphic EQ** — 20 built-in presets + custom per-app presets (allocated only when enabled)
- **AutoEQ headphone correction** — On-demand search across 6,000+ headphone profiles or custom `ParametricEQ.txt` import
- **ISO 226:2023 Loudness Compensation** — Optional equal-loudness contour compensation at low listening volumes

---

## 📋 Requirements

- **macOS 15.4** or later (Apple Silicon)
- **Audio Capture Permission** (prompted on first launch for per-app volume mixing)
- **Automation / Apple Events Permission** (prompted when controlling Spotify or browser tabs)

---

## 🙏 Credits & Acknowledgments

- **LazyTune** is developed and maintained by **[Vic3z](https://github.com/Vic3z)**.
- Forked from and built upon the core audio mixer architecture of **[FineTune](https://github.com/ronitsingh10/FineTune)** by **Ronit Singh**.

## 📄 License

Released under the [GNU General Public License v3.0 (GPL-3.0)](LICENSE).
