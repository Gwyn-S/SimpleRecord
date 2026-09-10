---
name: buildwinapk
description: Use when the user asks to build/package SimpleRecord for release ("构建", "打包", "打apk", "打APK", "windows", "build", "出包", "版本"). Builds the Windows release exe and the Android arm64-v8a APK, reports artifact paths and sizes. Only build when explicitly requested by the user.
---

# Build Win + APK

构建 SimpleRecord 的 Windows 版和 Android APK。工作目录固定为 `E:\KeepBook\app`。

## 前置步骤

1. **关闭正在运行的 Windows 程序**（否则链接阶段报 `LNK1104 无法打开 simple_record.exe`）：
   ```powershell
   Get-Process -Name simple_record -ErrorAction SilentlyContinue | Stop-Process -Force
   ```
2. 先运行 `flutter analyze`（工作目录 `E:\KeepBook\app`），有错误先修复再构建。

## 构建命令（均在 `D:\My_Note\simple-record\app` 下执行）

1. **Windows release**：
   ```powershell
   flutter build windows --release
   ```
   产物：`build\windows\x64\runner\Release\simple_record.exe`

2. **Android arm64-v8a APK**：
   ```powershell
   flutter build apk --release --split-per-abi --target-platform android-arm64
   ```
   产物：`build\app\outputs\flutter-apk\app-arm64-v8a-release.apk`（约 19MB）

### 内置云端配置（发布给家人的成品版）

- 云端配置（Supabase URL/anon key）与腾讯云语音识别密钥通过构建时注入实现，密件不入 Git：
  复制 `app\.env.release.example` 为 `app\.env.release`（已被 `.gitignore` 忽略），
  填上真实值后，构建命令追加 `--dart-define-from-file=.env.release`：
  ```powershell
  flutter build windows --release --dart-define-from-file=.env.release
  flutter build apk --release --split-per-abi --target-platform android-arm64 --dart-define-from-file=.env.release
  ```
- `.env.release` 属于个人凭据，**永不提交、不放入构建说明的默认命令**——只有用户明确要"发布成品版"时才加注入参数。
- 未注入时 App 的云同步与语音识别（ASR）不可用（登录/共享账本、语音记账均依赖注入的内置密钥），WebDAV/AI 手动配置不受影响。

## 收尾

- 用 `Get-Item` 确认两个产物存在，报告实际大小。
- 若构建失败：阅读报错定位修复（常见：exe 被占用 → 前置杀进程；依赖下载慢 → 重试；Gradle 缓存 → 重试）。

## 约定

- 回答使用中文。
- **默认不构建**：改完代码后不自动出包，由用户自行构建。只有用户明确要求构建时才执行。
- 若用户要求构建：默认两个平台都要构建；若用户只要其中一个，按用户要求执行。
- 构建是副产品，**不提交构建产物到 git**（构建会改动 generated_plugin_*.cc/.cmake 与 pubspec.lock 的镜像源，不要 add 这些）。
