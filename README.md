# Panovault — Cyber Graphic & Visual Strip Reader

[![Latest Release](https://img.shields.io/github/v/release/rafylabs/panovault?color=00F0FF&label=Release&style=for-the-badge)](https://github.com/rafylabs/panovault/releases/latest)
[![Download iOS](https://img.shields.io/badge/Download-iOS%20(.IPA)-00F0FF?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/rafylabs/panovault/releases/latest/download/Panovault.ipa)
[![Download Android](https://img.shields.io/badge/Download-Android%20(.APK)-3DDC84?style=for-the-badge&logo=android&logoColor=white)](https://github.com/rafylabs/panovault/releases/latest/download/Panovault.apk)

A high-performance sequential graphic and comic reader built with **Flutter**, featuring offline SQLite caching, multi-catalog aggregation, and seamless cross-platform deployment for **iOS (non-App Store sideloading)** and **Android**.

### 📲 Direct Downloads
| Platform | Format | Direct Download | Installation Instructions |
|---|---|---|---|
| **iOS** | `.ipa` (Universal) | [⬇️ **Download Panovault.ipa**](https://github.com/rafylabs/panovault/releases/latest/download/Panovault.ipa) | Sideload via AltStore, SideStore, TrollStore, or Sideloadly |
| **Android** | `.apk` (Release) | [⬇️ **Download Panovault.apk**](https://github.com/rafylabs/panovault/releases/latest/download/Panovault.apk) | Direct install APK (allow unknown sources) |

---

## ✨ Features

- **Multi-Source Catalog**: Browse, search, and discover visual strips, webtoons, and graphic narratives from multiple sources.
- **Smart Reader Engine**:
  - **Webtoon Mode**: Smooth, continuous vertical scrolling with adjacent-page preloading.
  - **Paged Mode (RTL & LTR)**: Standard right-to-left paging or Western comic left-to-right paging.
  - **Gesture Zoom**: Pinch-to-zoom and double-tap zoom via `ExtendedImage`.
- **Local Offline Storage**: SQLite-backed local vault (`sqflite`), reading progress tracking, and history timeline.
- **Zero-Restricted iOS Sideloading**: Preconfigured entitlements (`Info.plist`) allowing arbitrary HTTP/HTTPS CDN loads and document sharing for direct installation via AltStore, SideStore, TrollStore, or Sideloadly.
- **Cyber Dark & Light Theme**: High-contrast Cyber Cyan & Void aesthetic (`#00F0FF`, `#0A0E17`).

---

## 📱 How to Install on iOS (Without App Store)

Panovault is packaged as an unsigned `.ipa` ready for sideloading with any free Apple ID or permanent certificate:

### Method 1: AltStore / SideStore (Recommended)
1. Download `Panovault.ipa` from the [GitHub Releases](https://github.com/rafylabs/panovault/releases/latest).
2. Open **AltStore** or **SideStore** on your iPhone / iPad.
3. Tap the **+** button in the "My Apps" tab and choose `Panovault.ipa`.
4. Sign in with your Apple ID. The app will install directly to your Home Screen.

### Method 2: TrollStore (iOS 14.0 – 17.0)
1. Download `Panovault.ipa` directly in Safari on your iOS device.
2. Share / Open in **TrollStore**.
3. Tap **Install**. The app is permanently signed with no 7-day expiration.

### Method 3: Sideloadly / Scarlet (Mac or PC)
1. Connect your iPhone to your Mac/PC via USB or Wi-Fi sync.
2. Drag `Panovault.ipa` into **Sideloadly**.
3. Enter your Apple ID and click **Start**.

> **Note for iOS 16+**: Enable Developer Mode in `Settings > Privacy & Security > Developer Mode` and restart your device.

---

## 🛠️ Project Structure

```
lib/
├── core/
│   ├── database/
│   │   ├── app_database.dart       # SQLite persistence (Favorites, History, Chapters)
│   │   └── models/                 # Manga, MangaChapter, MangaPage, HistoryEntry
│   ├── network/
│   │   └── http_client.dart        # Dio client with CookieJar, iOS UA & Cloudflare headers
│   ├── parser/
│   │   ├── manga_parser.dart       # Abstract parser contract
│   │   ├── parser_registry.dart    # Active source repository
│   │   └── parsers/                # Built-in source parsers
│   └── theme/
│       └── app_theme.dart          # Dark Cyber Cyan & Light themes
├── features/
│   ├── catalog/                    # Browse, Search, Detail & Chapter List
│   ├── library/                    # Saved Bookmarks & Favorites
│   ├── history/                    # Reading Progress Timeline
│   ├── reader/                     # Webtoon & Paged Reader Engine with Gesture Zoom
│   └── settings/                   # Reading preferences & Sideload guide
└── main.dart                       # App entry point & Root IndexedStack navigation
```

---

## 🚀 Building the IPA Locally

On a macOS machine (such as your MacBook Air M4):

```bash
# 1. Fetch dependencies
flutter pub get

# 2. Verify code quality
flutter analyze

# 3. Build unsigned IPA package
./scripts/build-ipa.sh
```

The resulting `Panovault.ipa` will be output to `build/ios/ipa/Panovault.ipa`.
