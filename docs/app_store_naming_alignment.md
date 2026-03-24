# App Store 名称与安装显示名对齐（2.3.8）

## 原因说明

审核意见「App Store 上的名称与安装后显示名不一致」常见原因：

1. **`InfoPlist.strings` 未加入 Xcode 的 Copy Bundle Resources**，本地化不生效，系统始终使用 `Info.plist` / `PRODUCT_NAME` 的单一名称。
2. **英文商店名**（如 Key Core）与 **包内默认 `PRODUCT_NAME`**（此前为「密枢」）不同，在**英文系统**下安装后仍显示中文名，易被判定不一致。

## 工程内已做调整

| 项目 | 说明 |
|------|------|
| `macos/Runner/Configs/AppInfo.xcconfig` | `PRODUCT_NAME = Key Core`，与英文商店名一致；安装包文件名为 `Key Core.app`。 |
| `macos/Runner/*/InfoPlist.strings` | 已加入 `Runner` 目标的 **InfoPlist.strings** 变体组（en / zh-Hans / zh-Hant），在简繁中文环境下 **显示名为「密枢」**。 |
| `lib/main.dart` | 使用 `onGenerateTitle` 与界面语言一致的应用标题。 |
| `macos/Runner/AppDelegate.swift` | 菜单栏图标 tooltip / 无障碍名称随 Bundle 本地化显示名变化。 |

## 请在 App Store Connect 中配置

- **英文（美国等）**：App 名称填 **Key Core**（与安装包默认英文名一致）。
- **简体中文 / 繁体中文**：App 名称填 **密枢**（与中文系统下 `CFBundleDisplayName` 一致）。

**不要**修改 Bundle ID（`cn.dlrow.keycore`）。

## 自测方式

1. 英文系统语言下安装：启动台、访达、关于本应用、菜单栏中应为 **Key Core**。
2. 简体中文下安装：上述位置应为 **密枢**。

若仅改 Connect 未改包内本地化，仍会出现审核所述不一致；需**同时**保证本仓库的 `InfoPlist.strings` 已随版本提交并归档。
