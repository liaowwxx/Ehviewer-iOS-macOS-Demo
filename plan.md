# EhViewer iOS/macOS 原生移植计划

- 参考目录: `/Users/liao/Documents/Tools/Ehviewer_CN_SXJ`
## 概要

- 以 Android `BiLi_PC_Gamer` 分支 `17769e4`（2.0.2.3）为行为基线；原工程约 536 个 Java/Kotlin 源文件，目标目录目前为空。
- 新建一个共享代码的 SwiftUI 多平台工程，目标 iOS 26、iPadOS 26、macOS 26，使用 Swift 6.3、严格并发检查和 SwiftData。
- 采用 Apple 原生自适应界面：iPhone 使用标签页与 `NavigationStack`，iPad/Mac 使用 `NavigationSplitView`；不复刻 Android Activity/Fragment/OpenGL 架构。
- 首版完成登录、列表/搜索、详情、阅读、历史和可恢复下载；随后分阶段补齐账户与高级功能。
- 仅个人开发签名、本地数据、系统网络/VPN；不包含 App Store、CloudKit、Android 数据迁移或应用内 DoH/Hosts。

## 核心架构与接口

- 创建多平台 `EhViewer` App target，以及本地 Swift Package：
  - `EHDomain`：纯值类型、错误、查询和路由。
  - `EHNetworking`：URLSession、Cookie、SwiftSoup 解析器。
  - `EHPersistence`：SwiftData schema 与 `@ModelActor` 仓储。
  - `EHDownloads`：页面解析、缓存、下载状态机。
  - App 内按 Browse、Gallery、Reader、Downloads、Library、Settings 分功能组织 SwiftUI。
- 首版唯一外部依赖为 SwiftSoup，锁定实现时的稳定版本与 `Package.resolved`；图片、缓存、数据库、日志、认证全部使用 Apple 框架。后期本地 ZIP/7z/RAR 支持统一通过本地封装的 libarchive 模块提供。
- 定义稳定的包级接口：
  - `GalleryKey(gid, token)`、`GallerySummary`、`GalleryDetail`、`GalleryPageDescriptor`。
  - `GalleryListQuery`、`GalleryCursor`、`SiteMode`、`ImageResolution`。
  - `EHAPI`：列表、详情、预览、图片直链、登录、收藏、评论、评分、标签及归档操作。
  - `HTTPTransport`：可注入、可模拟的 URLSession 边界。
  - `SessionVault` actor：在本地、非同步 Keychain 保存 Cookie，并与临时 `WKWebView` 双向同步。
  - `ImagePipeline` actor：去重请求、内存/磁盘缓存、ImageIO 下采样与预取。
  - `DownloadCoordinator` actor：`enqueue/pause/resume/cancel/events`，通过有界 `AsyncStream` 发布状态。
  - `AppRoute`：统一声明式导航，避免重复注册 destination。
- SwiftData V1 模型：
  - `GalleryRecord`：画廊元数据、历史时间、阅读页码、本地收藏状态。
  - `DownloadJobRecord`：状态、标签、总页数、进度、错误和后台任务映射。
  - `DownloadPageRecord`：页码、文件名、字节数、直链状态和重试信息；随任务级联删除。
  - `DownloadLabelRecord`、`QuickSearchRecord`、`FilterRuleRecord`。
  - 使用索引和 `@ModelActor` 串行 upsert，不使用 CloudKit 不兼容的唯一约束；SwiftData 模型不跨 actor，只传 gid、持久化 ID 或值快照。
- `@MainActor @Observable` 状态模型只负责 UI；设置通过注入的 `UserDefaults` 封装，不在 Observable 类型中使用 `@AppStorage`。

## 分阶段实现

### 1. 工程与协议基线

- 建立 iOS/macOS target、签名配置、严格并发、资源和中英文本地化。
- 移植 URL 构造、E/EX 站点规则、Cookie 规则及错误映射。
- 将 Android 的 HTML/JSON 测试样本复制为有来源说明的 Swift 测试 fixtures；用 SwiftSoup 重写列表、详情、预览和图片页解析器。
- 保留原项目版权头，建立第三方许可清单；不直接移植 Android UI、JNI 或线程工具代码。

### 2. 首个可用版本

- 支持游客浏览、账号密码登录、临时 WKWebView 登录和手动 Cookie 登录；凭据本身不持久化，Cookie 存 Keychain。
- 实现首页、订阅、热门、排行、普通/高级搜索，支持列表和网格展示、分页、刷新与错误重试。
- 实现详情、标签、评分、预览和外部 URL 打开。
- 阅读器支持纵向连续、从左到右和从右到左分页、缩放、跳页、全屏、分享、保存、阅读进度及 Mac 键盘操作；使用纯 SwiftUI 滚动与缩放 API。
- 实现历史、本地收藏和下载队列。每次只运行一个画廊任务、默认并发下载 3 页，阅读器预取前 3 页和后 1 页。

### 3. 下载与缓存可靠性

- 临时图片进入 `Caches`，LRU 上限为 iOS 512 MiB、macOS 2 GiB；离线下载进入 `Application Support/EhViewer/Downloads` 并排除系统备份。
- 下载先写 `.part`，校验成功后原子改名；剩余空间低于 1 GiB 时暂停并提示。
- 已解析出的直链交给后台 URLSession；持久化系统 task ID，应用重新启动后重连并恢复。
- 后台任务被系统暂停属于正常状态；403/失效直链在回到前台后重新解析，509、限流、登录过期和解析失败使用独立错误状态，不进行无限重试。
- 普通失败最多重试 3 次；取消沿结构化并发传播并立即保存可恢复状态。

### 4. 完整功能补齐

- 远程收藏分类与批量操作、评论发布/编辑/投票、评分、关注标签。
- 快捷搜索、图片搜索、标签翻译数据库、过滤规则、黑名单、配额查看与重置。
- Torrent 文件、站点归档下载、本地 ZIP/7z/RAR 打开、下载标签与排序。
- Face ID/Touch ID 应用锁、分享扩展、URL/文档打开、Mac 独立阅读窗口、菜单栏命令与快捷键。
- 补齐 Android 已有的繁中、日、韩、西、法、德、泰文本；不移植 Firebase、APK 更新、MIUI/S Pen、Android 前台服务或 WiFi 数据迁移。

## 测试与验收

- 使用 Swift Testing 编写单元和集成测试；UI 自动化保留 XCTest：
  - 参数化测试 Android 的 E/EX 各列表模式、详情、页面 API、URL、收藏和 Torrent fixtures。
  - 模拟 `HTTPTransport` 验证 Cookie 域、请求头、重定向、登录过期、403/429/509、空响应和页面结构变化；CI 不访问真实站点。
  - 验证请求去重、并发上限、取消传播、事件流结束、失败重试及后台任务恢复，不使用固定延迟等待。
  - 使用内存 SwiftData 容器验证 upsert、索引查询、级联删除、阅读进度和 V1 migration。
  - XCTest 覆盖紧凑/宽屏导航、下载恢复、Mac 键盘操作和基本无障碍标签。
- 每个里程碑必须同时通过 iPhone、iPad Simulator 与本机 Mac 的 Debug/Release 构建，严格并发零错误；并建立单独的 Thread Sanitizer 测试 scheme。
- 首版人工验收：
  - 手动 Cookie 与 WKWebView 至少一种方式可稳定登录 E/EX。
  - 可完成“搜索 → 详情 → 阅读 → 退出 → 恢复进度”。
  - 下载在暂停、后台、强制退出和重新启动后无重复页、无损坏完成文件。
  - 动态字体、VoiceOver、深浅色和减少动态效果下主要流程可用。
  - 日志通过 OSLog 隐去 Cookie、查询内容和本地文件隐私信息。

## 已确定的假设

- 产品名暂定 `EhViewer`，默认 bundle ID 为 `com.liao.ehviewer`，使用 Xcode Automatic Signing；开发团队由本机配置。
- 首版仅简体中文和英文；不导入 Android 历史、收藏、数据库或下载目录。
- iOS 后台下载采用系统允许范围内的“尽力继续、可靠恢复”，不承诺 Android 前台服务式常驻。
- 仅个人使用，不配置商店、TestFlight、Developer ID 公证或遥测。未来若公开分发，需要重新审核许可证与内容合规；App Store 对露骨成人内容有明确限制，参见 [Apple App Review Guidelines 1.1.4](https://developer.apple.com/app-store/review/guidelines/)。
