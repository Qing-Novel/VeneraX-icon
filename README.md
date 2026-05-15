# Venera

[![Flutter](https://img.shields.io/badge/flutter-3.41.4-blue)](https://flutter.dev/)
[![License](https://img.shields.io/github/license/kyosee/venera)](https://github.com/kyosee/venera/blob/master/LICENSE)
[![Stars](https://img.shields.io/github/stars/kyosee/venera?style=flat)](https://github.com/kyosee/venera/stargazers)
[![Release](https://img.shields.io/github/v/release/kyosee/venera)](https://github.com/kyosee/venera/releases)

**[中文](README_CN.md) | English**

A cross-platform manga/comic reader with self-hosted Web frontend support.

> **Disclaimer:** This repository is for personal learning and use only.

## Warning

**Do NOT deploy the Web frontend on the public internet.** It is designed for personal use on a trusted LAN only. Exposing it publicly may lead to attacks, traffic abuse, and data leaks (cookies, WebDAV config, personal data). All legal and security risks are your own.

## Features

- Multi-platform: Windows, Linux, macOS, Android, iOS
- JavaScript-based comic source plugins (QuickJS on native, Node.js on server)
- Self-hosted Web frontend with Docker support
- WebDAV backup & sync
- Windows auto-updater

## Quick Start

### Native App

```bash
flutter build apk        # Android
flutter build windows    # Windows
flutter build linux      # Linux
flutter build macos      # macOS
```

### Web Frontend (Docker)

```bash
pwsh ./tool/build_web_helper_bundle.ps1
cd build/web-helper-bundle
docker compose up -d --build
```

Default access: `http://localhost:60098`

## Build from Source

1. Clone the repository
2. Install [Flutter](https://flutter.dev/docs/get-started/install)
3. Install [Rust](https://rustup.rs/) (for server)
4. For Web frontend: Node.js 20+, Rust, and Docker

## Migration

If migrating from [venera-app/venera](https://github.com/venera-app/venera), use a separate WebDAV sync directory. Back up your old data before migrating.

## Documentation

| Document | Link |
|----------|------|
| Local Comic Import | [doc/import_comic.md](doc/import_comic.md) |
| Headless Mode | [doc/headless_doc.md](doc/headless_doc.md) |

## Acknowledgments

- [EhTagTranslation](https://github.com/EhTagTranslation/Database) — Chinese tag translations
