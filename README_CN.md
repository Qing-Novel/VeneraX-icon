# Venera

[![Flutter](https://img.shields.io/badge/flutter-3.41.4-blue)](https://flutter.dev/)
[![License](https://img.shields.io/github/license/kyosee/venera)](https://github.com/kyosee/venera/blob/master/LICENSE)
[![Stars](https://img.shields.io/github/stars/kyosee/venera?style=flat)](https://github.com/kyosee/venera/stargazers)
[![Release](https://img.shields.io/github/v/release/kyosee/venera)](https://github.com/kyosee/venera/releases)

**中文 | [English](README.md)**

跨平台漫画阅读器，支持自托管 Web 前端。

> **声明：** 此仓库所有内容仅用于个人学习！

## 警告

**禁止将 Web 前端部署在公网！** 仅适用于可信内网环境下的个人自用。暴露到公网可能导致攻击、流量滥用及数据泄露（Cookie、WebDAV 配置、个人数据）。由此产生的法律和安全风险自行承担。

## 功能

- 多平台：Windows、Linux、macOS、Android、iOS
- 基于 JavaScript 的漫画源插件（原生端 QuickJS，服务端 Node.js）
- 自托管 Web 前端，支持 Docker 部署
- WebDAV 备份与同步
- Windows 自动更新

## 快速开始

### 原生应用

```bash
flutter build apk        # Android
flutter build windows    # Windows
flutter build linux      # Linux
flutter build macos      # macOS
```

### Web 前端（Docker）

```bash
pwsh ./tool/build_web_helper_bundle.ps1
cd build/web-helper-bundle
docker compose up -d --build
```

默认访问地址：`http://localhost:60098`

## 从源码构建

1. 克隆仓库
2. 安装 [Flutter](https://flutter.dev/docs/get-started/install)
3. 安装 [Rust](https://rustup.rs/)（服务端需要）
4. Web 前端需要 Node.js 20+、Rust 和 Docker

## 迁移提示

从 [venera-app/venera](https://github.com/venera-app/venera) 迁移时，请为 WebDAV 同步指定独立目录，不要与原项目共用。迁移前建议备份旧数据。

## 文档

| 文档 | 链接 |
|------|------|
| 本地漫画导入 | [doc/import_comic.md](doc/import_comic.md) |
| Headless 模式 | [doc/headless_doc.md](doc/headless_doc.md) |

## 致谢

- [EhTagTranslation](https://github.com/EhTagTranslation/Database) — 漫画标签中文翻译
