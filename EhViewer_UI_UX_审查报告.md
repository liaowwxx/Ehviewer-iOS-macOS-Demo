# EhViewer UI / UX 与产品逻辑全面审查报告

## 审查结论

当前版本可以编译，核心单元测试通过，首页与跨平台导航的基础结构也已成形；但仍有 1 个启动级风险和 9 个应优先处理的 P1 问题。风险主要来自：

- 新旧浏览状态模型并存，导致错误恢复、站点和过滤规则状态错位。
- 下载删除与持久化不是事务式操作。
- 阅读器缺少失败恢复、生命周期保存和内存淘汰。
- 高级搜索、搜索历史等能力存在入口回归。
- iPad 尺寸切换、多窗口和 macOS 平台行为没有形成独立产品逻辑。

Apple 建议不可逆、非常用的数据破坏操作提供确认，也要求 iPad 窗口适配窄、紧凑和中间宽度；触控按钮通常至少应有 44×44 pt 命中区域。[Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts)、[Split views](https://developer.apple.com/design/human-interface-guidelines/split-views)、[Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons)

## P0

### 1. 本地数据库打开失败会直接终止应用

- 类型：Bug / 数据可用性问题
- 位置：[EhViewerApp.swift:30](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/EhViewerApp.swift:30)、[PersistenceStore.swift:46](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EHPersistence/PersistenceStore.swift:46)
- 当前行为：`ModelContainerFactory.make()` 失败后直接 `fatalError`。当前容器也没有 `VersionedSchema` 或 `SchemaMigrationPlan`。
- 问题：磁盘损坏、模型不兼容或未来升级迁移失败时，用户无法启动应用、导出数据或进入恢复界面。
- 建议：引入明确的版本化 Schema 和迁移计划；启动失败时显示恢复界面，提供重试、诊断信息、数据导出，以及经再次确认后的重建选项，不能自动丢弃旧库。SwiftData 官方提供了专门的 [`SchemaMigrationPlan`](https://developer.apple.com/documentation/swiftdata/schemamigrationplan)。
- 收益：避免升级或存储异常演变为全量不可用。
- 证据：静态确定；正常构建无法触发损坏库场景。

## P1

### 2. 全局错误框的“重试”经常重试错误任务

- 类型：Bug / 架构问题
- 位置：[RootView.swift:18](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/RootView.swift:18)、[BrowseView.swift:89](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/BrowseView.swift:89)、[AppModel.swift:296](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/AppModel.swift:296)、[GalleryDetailView.swift:138](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/GalleryDetailView.swift:138)、[ReaderView.swift:65](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/ReaderView.swift:65)
- 当前行为：登录、评论、评分、归档、Keychain、详情和新 `BrowsePageModel` 的错误都写入同一个 `errorMessage`；弹窗“重试”固定执行旧 `AppModel.load(activeQuery)`。
- 问题：详情或阅读器加载失败后会永久停留在 `ProgressView`；点击重试却刷新另一个列表。新页面模型的失败也不会被真正重试。
- 建议：定义带来源和重试闭包的错误状态；列表、详情、阅读器、登录和导入在各自界面展示局部错误及正确操作。
- 收益：恢复路径可预测，消除永久 Loading。
- 证据：静态确定；无签名 iPhone 走查中实际看到 Keychain 环境错误也被统一赋予“重试列表”操作。Keychain 错误本身属于无签名环境，不作为产品缺陷。

### 3. 新旧浏览 Source of Truth 并存，站点和过滤规则会失真

- 类型：Bug / 架构问题
- 位置：[AppModel.swift:23](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/AppModel.swift:23)、[BrowsePageModel.swift:13](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/BrowsePageModel.swift:13)、[BrowsePageModel.swift:29](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/BrowsePageModel.swift:29)、[BrowsePageModel.swift:161](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/BrowsePageModel.swift:161)
- 当前行为：`AppModel` 仍保存 galleries、搜索、分页和请求状态；当前界面改用独立 `BrowsePageModel`；页面模型初始化时复制一次 `site`，过滤规则也只读取一次。
- 问题：设置页切换站点或修改过滤规则后，已存在的首页仍使用旧配置；旧模型上的刷新、测试和快捷键也可能对可见页面无效。
- 建议：移除旧列表状态，建立单一浏览状态所有者；站点和过滤配置应是可观察依赖，变更后明确取消旧请求并重新加载。
- 收益：消除“设置已改但内容没变”、错误重试错位和测试假覆盖。
- 成本：高。
- 证据：静态确定。

### 4. ExHentai 设置无法可靠保存

- 类型：Bug / 数据逻辑问题
- 位置：[SettingsView.swift:20](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/SettingsView.swift:20)、[AppModel.swift:59](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/AppModel.swift:59)、[AppModel.swift:865](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/AppModel.swift:865)、[AppModelTests.swift:73](/Users/liao/Documents/Tools/ehviewer-iosdemo/Tests/EhViewerTests/AppModelTests.swift:73)
- 当前行为：设置页允许已登录用户选择 ExHentai，但初始化、会话刷新和登录完成都会强制改回 E-Hentai，并覆盖 UserDefaults。现有测试还固定了这个行为。
- 问题：界面承诺可选择站点，产品逻辑却将其重置。
- 建议：明确区分“默认站点”和“用户当前站点”；只有游客态或 ExHentai 权限失效时才回退，并向用户说明原因。
- 收益：站点选择符合预期，避免跨站请求和内容错位。
- 成本：小到中。
- 证据：静态确定，且测试明确证明当前重置逻辑。

### 5. 高级搜索、搜索历史和直接画廊 URL 存在入口回归

- 类型：Bug / UX 问题
- 位置：[AdvancedSearchView.swift:4](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/AdvancedSearchView.swift:4)、[BrowseView.swift:113](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/BrowseView.swift:113)、[BrowseView.swift:143](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/BrowseView.swift:143)、[BrowseSearchSuggestions.swift:8](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/BrowseSearchSuggestions.swift:8)、[AppModel.swift:208](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/AppModel.swift:208)
- 当前行为：`AdvancedSearchView` 没有任何调用入口；搜索建议只展示标签，持久化的搜索历史不再显示；提交搜索统一作为关键字处理，没有先识别粘贴的画廊 URL。
- 问题：已经实现并持久化的核心搜索能力在当前 UI 中不可达。
- 建议：在“更多”或搜索建议中恢复高级搜索；恢复历史分区及删除操作；提交时优先识别画廊 URL 并直接导航。
- 收益：降低复杂查询和回访任务成本。
- 成本：中。
- 证据：静态确定；现有 UI 测试只验证“搜索结果”标题出现，不验证查询内容和结果。

### 6. 删除下载无确认，且磁盘、SwiftData、内存可能不一致

- 类型：Bug / UX 问题 / 数据逻辑问题
- 位置：[DownloadsView.swift:316](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/DownloadsView.swift:316)、[DownloadCoordinator.swift:182](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EHDownloads/DownloadCoordinator.swift:182)、[AppModel.swift:118](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/AppModel.swift:118)
- 当前行为：菜单中的“删除下载”立即执行；协调器先从内存移除，然后忽略 SwiftData 删除失败和文件删除失败。
- 问题：误触会不可逆地丢失本地页；数据库删除失败时任务可能重启后复活，文件删除失败则留下孤儿文件。
- 建议：增加带标题和文件影响说明的确认；删除操作返回结构化结果，在持久化与文件处理成功前保留可见任务，失败时显示可恢复状态。
- 收益：避免数据丢失和幽灵下载。
- 成本：中。
- 证据：静态确定。

### 7. 详情页异步操作缺少进行中状态，评论失败会丢失草稿

- 类型：Bug / UX 问题
- 位置：[GalleryDetailView.swift:49](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/GalleryDetailView.swift:49)、[GalleryDetailView.swift:70](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/GalleryDetailView.swift:70)、[GalleryDetailView.swift:125](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/GalleryDetailView.swift:125)
- 当前行为：收藏、加入下载、评分和评论通过未跟踪的 `Task` 执行，按钮保持可点击；评论文本在请求开始前清空。
- 问题：快速重复点击可能产生并发远端操作；成功或失败缺少局部反馈；评论失败后用户输入无法恢复。
- 建议：为每类操作建立 idle/loading/success/error 状态；操作期间禁用重复提交；评论仅在成功后清空，失败时保留草稿。
- 收益：减少重复请求和用户输入丢失。
- 成本：中。
- 证据：静态确定。

### 8. 分页阅读器会无限保留已访问页面控制器和解码图像

- 类型：架构问题 / 性能问题
- 位置：[ReaderPagedView.swift:128](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/ReaderPagedView.swift:128)、[ReaderPagedView.swift:258](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/ReaderPagedView.swift:258)、[ReaderPage.swift:109](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/ReaderPage.swift:109)、[ImagePipeline.swift:15](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EHNetworking/ImagePipeline.swift:15)
- 当前行为：每个访问过的页控制器永久保存在字典中；每页最多解码到 2400 像素；iOS 原始数据内存缓存上限又是 512 MB。
- 问题：长画廊连续翻页时，控制器、解码图像和原始 Data 叠加增长，容易产生明显内存压力甚至终止。
- 建议：仅保留当前页及前后页，使用可淘汰缓存；响应内存警告；根据设备内存和页面尺寸动态控制原始 Data 缓存。
- 收益：长篇阅读稳定性显著提高。
- 成本：中到高。
- 证据：静态确定；尚未进行长画廊内存仪表压测。

### 9. 阅读进度、失败恢复和屏幕方向生命周期不完整

- 类型：Bug / 数据逻辑问题
- 位置：[ReaderView.swift:99](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/ReaderView.swift:99)、[ReaderView.swift:128](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/ReaderView.swift:128)、[ReaderView.swift:186](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/ReaderView.swift:186)、[ReaderView.swift:212](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/ReaderView.swift:212)、[ReaderPage.swift:35](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/ReaderPage.swift:35)
- 当前行为：阅读进度只在 `onDisappear` 保存；图片失败只有“页面加载失败”，没有重试；退出时只恢复常亮状态，没有恢复进入阅读器前的方向约束；详情加载失败会一直显示“准备阅读器…”。
- 问题：应用被终止或长期后台时可能丢失进度；瞬时网络错误无法原地恢复；离开阅读器后其他界面可能仍受方向限制。
- 建议：在页码变化和场景转后台时节流保存；使用明确加载状态与重试；记录并恢复进入前的方向策略。
- 收益：阅读恢复可靠，失败不必退出重进。
- 成本：中。
- 证据：静态确定。

### 10. iPad 尺寸变化和多窗口会重建或串联导航状态

- 类型：架构问题 / UX 问题
- 位置：[RootView.swift:9](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/RootView.swift:9)、[RootView.swift:59](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/RootView.swift:59)、[RootView.swift:120](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/RootView.swift:120)、[EhViewerApp.swift:27](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/EhViewerApp.swift:27)
- 当前行为：紧凑和常规尺寸分别创建整套不同根视图和独立路径；所有 WindowGroup 又共享一个 `AppModel.selectedRoute` 和全局错误。
- 问题：iPad Split View 跨越 size class 时可能丢失当前详情、搜索结果和滚动位置；一个窗口的导航或错误可能影响其他窗口。
- 建议：保持稳定的导航容器并只改变呈现方式；把路径、选中项、错误和搜索上下文提升为每 Scene 独立状态，必要时使用场景存储。
- 收益：窗口缩放和多窗口行为可预测。
- 成本：高。
- 证据：iPad 横竖屏常规宽度实际表现正常；跨 size class 和多窗口风险为静态推断。

### 11. macOS 功能存在无效设置和错误语义

- 类型：Bug / UX 问题
- 位置：[EhViewerApp.swift:63](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/EhViewerApp.swift:63)、[ReaderSettingsMenu.swift:35](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/ReaderSettingsMenu.swift:35)、[AppModel.swift:350](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/AppModel.swift:350)、[ReaderPage.swift:62](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/ReaderPage.swift:62)
- 当前行为：`⌘R` 刷新旧 `AppModel` 列表，不一定刷新可见 `BrowsePageModel`；macOS 仍展示屏幕旋转、电量、常亮和音量键翻页等 iOS 专属选项；macOS“保存图片”实际写入应用下载目录，提示却称“已保存到系统照片”。
- 建议：命令路由到当前场景的可见页面；按平台隐藏设置；macOS 使用保存面板或 Finder 可访问位置并提供正确反馈。
- 收益：符合桌面用户预期。
- 成本：中。
- 证据：macOS 实际走查确认菜单、设置项存在；数据路径由静态代码确定。

### 12. 本地归档不是可连续阅读的产品流程

- 类型：UX 问题
- 位置：[LocalArchiveView.swift:22](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/LocalArchiveView.swift:22)、[LocalArchiveView.swift:53](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/LocalArchiveView.swift:53)
- 当前行为：先显示文件名列表，每张图单独打开 Sheet；看下一页必须关闭后再选。
- 问题：多页 ZIP/7z/RAR 的核心阅读任务操作成本极高，也无法使用统一阅读器的翻页、缩放、进度和全屏能力。
- 建议：将本地归档实现为 Reader 的第三种内容源，直接按图片排序进入连续/分页阅读。
- 收益：归档功能从“文件检查器”升级为真正阅读器。
- 成本：中到高。
- 证据：静态确定。

## P2

### 13. 导航语义仍有不一致

- 类型：Bug / 架构问题
- 位置：[RootView.swift:102](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/RootView.swift:102)、[LibraryView.swift:14](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/LibraryView.swift:14)、[DownloadsView.swift:278](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/DownloadsView.swift:278)
- 当前行为：紧凑模式收到 `.favorites` 时只切换到历史标签，但 `LibraryView` 仍默认显示历史；下载页同时混用 destination-style 和 value-style `NavigationLink`。
- 建议：让资料库模式成为路由的一部分；同一导航层级统一使用 value navigation。
- 收益：深链、状态恢复和返回路径更可靠。
- 成本：小到中。
- 证据：静态确定。

### 14. 存在明确的可访问性和字符串错误

- 类型：Bug / UX 问题
- 位置：[GalleryDetailView.swift:275](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/GalleryDetailView.swift:275)、[BrowseView.swift:174](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/BrowseView.swift:174)、[LocalArchiveView.swift:40](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/LocalArchiveView.swift:40)、[LocalArchiveReader.swift:85](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EHDownloads/LocalArchiveReader.swift:85)
- 当前行为：标签按钮最小高度只有 22 pt；未知页数被 VoiceOver 读成“0 页”；`"打开 (entry.path)"`、归档格式和大小错误信息缺少 Swift 字符串插值。
- 建议：扩大标签命中区域至至少 44 pt；未知页数不朗读数字；修复 `\(…)` 插值并补相应用例。
- 收益：VoiceOver 信息准确，触控更可靠。
- 成本：小。
- 证据：静态确定；大字号 iPhone 实测主导航仍可用。

### 15. 历史列表把备用标题误当成阅读进度

- 类型：Bug / UX 问题
- 位置：[LibraryView.swift:20](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/LibraryView.swift:20)
- 当前行为：副标题显示 `alternateTitle ?? "未记录进度"`，并没有读取实际阅读页。
- 问题：已有进度但没有备用标题的记录会被标成“未记录进度”。
- 建议：持久化查询结果显式携带当前页和总页数，副标题显示“阅读到 12/80 页”；备用标题单独展示。
- 收益：历史页真正支持恢复判断。
- 成本：小到中。
- 证据：静态确定。

### 16. 过滤规则不可删除，分享扩展失败则静默退出

- 类型：UX 问题
- 位置：[SettingsView.swift:60](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/SettingsView.swift:60)、[PersistenceStore.swift:328](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EHPersistence/PersistenceStore.swift:328)、[ShareViewController.swift:14](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewerShare/ShareViewController.swift:14)
- 当前行为：过滤规则只能新增或禁用；Share Extension 遇到不支持的内容、URL 解析失败或主应用打开失败时直接完成请求。
- 建议：为过滤规则增加删除/编辑；扩展失败时显示简短说明和取消按钮，并检查 `open` 返回值。
- 收益：设置可维护，分享失败不再像“什么都没发生”。
- 成本：小到中。
- 证据：静态确定。

### 17. 下载批量操作缺少 Disabled 状态

- 类型：UX 问题
- 位置：[DownloadsView.swift:93](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/DownloadsView.swift:93)
- 当前行为：“开始全部”和“暂停全部”始终启用，即使没有可开始或可暂停任务。
- 建议：根据当前快照禁用不适用的操作，并在导入恢复期间限制冲突操作。
- 收益：减少无反馈点击和状态竞争。
- 成本：小。
- 证据：静态确定。

## P3

### 18. iPad 与 macOS 列表没有利用宽度

- 类型：可选优化
- 位置：[BrowseView.swift:32](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/BrowseView.swift:32)、[BrowseView.swift:199](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/BrowseView.swift:199)
- 当前行为：所有平台固定单列、78×108 缩略图。
- 建议：宽窗口采用有最大内容宽度的双列/自适应网格，紧凑宽度保持当前单列。
- 收益：提高 iPad、macOS 扫描效率。
- 成本：中。
- 证据：macOS 实际走查中确认宽窗口存在大量水平空白。

### 19. 阅读状态覆盖层始终每秒刷新

- 类型：可选优化
- 位置：[ReaderView.swift:249](/Users/liao/Documents/Tools/ehviewer-iosdemo/Sources/EhViewer/ReaderView.swift:249)
- 当前行为：即使关闭时钟，仅显示页码或百分比也使用每秒 `TimelineView`。
- 建议：只有显示时钟时使用周期时间线，其余状态使用普通视图。
- 收益：减少不必要的阅读器重绘和能耗。
- 成本：小。
- 证据：静态确定。

## 建议保持现状

以下实现合理，不建议仅为“统一风格”而重写：

- `BrowsePageModel` 已区分 `CancellationError`，并使用 request ID 防止旧请求覆盖新请求。
- 下载协调器使用 Actor、单画廊调度和有限页面批次。
- 下载文件先写临时文件再提升，并验证图片格式。
- 会话存入 Keychain；下载存入 Application Support 且排除备份；图片和标签数据放入 Caches，职责边界总体正确。
- 应用启动时会对下载元数据和实际可读文件进行重新核对。
- 迁移界面已经明确说明下载图片不会被打包。

## 测试覆盖缺口

- [AppModelTests.swift:249](/Users/liao/Documents/Tools/ehviewer-iosdemo/Tests/EhViewerTests/AppModelTests.swift:249) 的竞态、分页测试调用旧 `AppModel.load`，当前界面实际使用 `BrowsePageModel`。
- [EhViewerUITests.swift:44](/Users/liao/Documents/Tools/ehviewer-iosdemo/Tests/EhViewerUITests/EhViewerUITests.swift:44) 只确认搜索结果页标题出现，没有验证加载、失败、取消或结果内容。
- 缺少 `BrowsePageModel` 的请求竞态、分页失败、站点/过滤变更测试。
- 缺少 SwiftData 旧 Schema 到新 Schema 的真实磁盘迁移测试。
- 缺少下载数据库删除失败、文件删除失败及重启恢复测试。
- 缺少详情/阅读器失败与重试、后台进度保存、多窗口、iPad 尺寸切换和 macOS 命令测试。
- 缺少 VoiceOver、大字号、Reduce Motion、对比度和键盘焦点测试。

## 最主要的 5 个 UX 问题

1. 错误框重试错误任务，详情和阅读器可能永久 Loading。
2. 高级搜索、搜索历史和粘贴画廊 URL 的入口回归。
3. 删除下载无确认且失败不可见。
4. 收藏、评分、评论缺少进行中与结果反馈，评论失败会丢草稿。
5. 本地归档不能连续阅读，阅读页失败也不能原地重试。

## 最主要的 5 个架构 / 数据问题

1. `AppModel` 与 `BrowsePageModel` 双重 Source of Truth。
2. SwiftData 无版本化迁移且打开失败直接 `fatalError`。
3. 下载删除先更新内存并吞掉数据库、文件错误。
4. 分页阅读器和图像缓存缺少淘汰策略。
5. 导航、错误和选择状态跨 Scene 共享，阅读进度又只在离开时保存。

## 各平台最高价值改进

- iPhone：先完成局部失败状态、评论草稿保护、下载删除确认和阅读进度生命周期保存。
- iPad：把导航状态改为 Scene 级，并保证 regular/compact 切换不重建任务流。
- macOS：修正 `⌘R`、保存图片路径和平台专属阅读设置，再优化宽窗口双列布局。

## 分阶段实施顺序

1. 数据与崩溃保护：引入 Schema 版本迁移和启动恢复；修正下载删除一致性；为阅读器空页和加载失败加保护。
2. 状态模型收敛：移除旧浏览 Source of Truth；建立带来源和重试操作的错误状态；让站点和过滤规则可响应更新。
3. 核心流程恢复：恢复高级搜索、历史建议和 URL 导航；补齐详情异步状态、评论草稿和归档阅读器。
4. 阅读与多窗口稳定性：实施页面缓存淘汰、场景级导航、进度后台保存和方向恢复。
5. 跨平台与无障碍优化：修正 macOS 命令/保存语义、iPad 宽度适配、44 pt 命中区域、VoiceOver 文案及大字号 UI 测试。
