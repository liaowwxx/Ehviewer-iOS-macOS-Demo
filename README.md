# EhViewer iOS / macOS

一款面向 iOS / iPadOS / macOS 的 **E-Hentai / ExHentai** 画廊浏览应用，参考项目 [Ehviewer_CN_SXJ](https://github.com/xiaojieonly/Ehviewer_CN_SXJ)，使用 SwiftUI 原生开发。

> 本应用仅用于个人学习与访问公开内容，请遵守当地法律法规与站点条款。
>
> 本项目使用 Codex 辅助开发，当前仍为测试版本，可能存在 Bug 或功能不完善之处；如遇问题欢迎通过 Issues 反馈。

---

## 主要功能

### 浏览与搜索

- 首页、订阅、热门、排行、收藏列表；支持高级搜索（分类、评分、页数等筛选）。
- 搜索框自带**标签联想**与**搜索历史**：输入即出现标签候选，点选自动补全为标签语法，支持多标签组合。
- 列表卡片显示：封面、标题、上传者、语言标签、上传时间、分类、页数与评分。

### 阅读

- 纵向连续阅读与左右/右左翻页；缩放、旋转、全屏、页内跳转。
- 自动记录阅读进度，支持将媒体保存到系统相册。

### 下载

- 单任务下载队列，断点续传，失败自动重试。
- 重启后自动恢复后台下载；下载页支持按状态筛选、多种排序与标签管理。
- 支持导出下载压缩包（含图片/视频）与恢复导入。

### 轻松从Android迁移

- **支持直接导入download压缩包或json**

---

## 安装

### 推荐：AltStore 侧载

1. 在电脑上安装 [AltStore](https://altstore.io)（Windows/macOS），登录 AltServer。
2. 在 [Releases](../../releases) 页面下载最新版 `EhViewer.ipa`。
3. 将 `.ipa` 通过隔空投送/文件传到 iPhone，用 **AltStore** 打开并安装。
4. 首次打开若提示「未受信任的开发者」，前往 **设置 → 通用 → VPN 与设备管理**，信任你的 Apple ID。
5. 免费 Apple ID 的签名有效期为 7 天；保持 iPhone 与电脑上的 AltServer 定期连接即可**自动续签**。

### 自行构建 IPA

```sh
xcodebuild -project EhViewer.xcodeproj -scheme EhViewer \
  -sdk iphoneos -configuration Release \
  -archivePath build/EhViewer.xcarchive archive
zsh make-ipa.sh build/EhViewer.xcarchive EhViewer.ipa
```

## 登录

- 无需登录即可浏览公开内容（游客模式）。
- 支持三种登录方式：**用户名&密码**、**网页登录**、**Cookie 登录**。
- 密码仅用于当次登录请求；会话 Cookie 加密存储于系统钥匙串。
- 登录后可收藏/评分/评论/关注标签，并访问 ExHentai。(未测试)

---

## 系统要求

- iOS / iPadOS 26.0 及以上；macOS 26.0 及以上。

## 隐私

- 所有数据仅保存在本机；图片缓存与下载文件均位于应用沙盒内。
- 不包含任何统计、追踪或联网上报组件。

## 许可

项目采用 [GNU General Public License v3.0](LICENSE) 许可。

参考实现 [Ehviewer_CN_SXJ](https://github.com/xiaojieonly/Ehviewer_CN_SXJ)；第三方组件许可见 [NOTICE](NOTICE) 与 [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md)。标签翻译库来自 [EhTagTranslation](https://github.com/EhTagTranslation/Database)（CC-BY-NC-SA-3.0）。
