# EhViewer 独立漫画翻译应用（开发者模式）

## 安装和使用

独立应用和完整项目位于 `/Users/liao/Documents/Tools/EhViewerTranslationCompanion/`。双击其中的 `EhViewer Translation.app` 或 `启动 EhViewer 翻译应用.command` 启动。

应用拥有自己的 `.runtime` 和 `.venv`，Python 与依赖初始复制自已安装环境。模型及资源位于应用数据目录中的独立 `engine-runtime/` 副本；日志、缓存、依赖安装和设置保存均不写入 BallonsTranslator。外部引擎仅提供未经修改的 Python 源码。本次先前引入的上游修改已全部撤回，独立应用文件已迁出。此开发者模式应用包引用新项目目录；移动后应重新运行 `scripts/create_app.py --output <新路径.app>`。脚本拒绝覆盖已有应用包。当前包没有签名或公证，不作为可直接公开分发的安装包。

1. 打开独立翻译应用。
2. 打开本次更新后的 **macOS** 版 EhViewer，后台会自动发现并连接本机服务，无需验证码或手动填写地址。两款应用的启动顺序不限，翻译应用退出后重新启动也会自动恢复；详情页显示连接状态。
3. 点击「发送到翻译应用」。仅完整下载、页面索引连续且原始媒体完整的漫画可提交；原图字节经二进制流上传。
4. 在独立应用中选择任务。使用「选择预设」「复制为新预设」「导出预设」管理原生 JSON 配置。
5. 点击「设置与模型」，在独立应用自己的设置面板中配置源语言、目标语言、检测/OCR/翻译/修复模型、设备和模型参数、LLM 服务与模型，以及常用嵌字和输出参数。保存后点击「开始翻译」。设置过程不打开 BallonsTranslator 窗口，收到漫画不会自动调用外部服务。
6. 完成后 EhViewer 自动下载、校验整本并保存译件，再发送 ACK。详情页及阅读器可以选择原件或任意译件；同一本漫画共享阅读进度。各设备的首选版本独立保存。
7. 使用现有设备同步将原件、译件传至 iPhone/iPad。两端均须更新到同步协议 v5。旧客户端会收到版本不兼容提示。

独立应用首次创建自己的默认预设时复制现有配置；选择外部预设也会复制到独立应用管理目录。每次执行再次保存预设快照，修改后续设置不会改变运行任务。预设可能包含 API Key，导出时由文件对话框提示；凭据不放进 EhViewer 元数据或网络结果清单。

「重新翻译」创建新的执行记录；运行中任务应先取消。以前成功的结果与版本保留。完全相同原图、Gallery 身份和配置快照的新提交可以复用经过重新校验的结果；明确重新翻译会强制新执行。

设置 → 本地漫画 → **译件资料库**可找到所有 Gallery 的译件，包括已经移除原图的漫画。普通缓存清理和设置页的原图清理保留译件。下载列表删除含译件的漫画时，可选择保留译件或一并归档。移除译件会移入译件存储下的 `deleted_file/`，记录恢复路径；不会覆盖原图。

手动导入入口接受包含 `manifest.json` 和 `pages/` 的目录。清单必须符合 `GalleryTranslationManifest`，且 GalleryKey 与当前画廊相同。导入按完整版本提交，不接受半本译件。

## 当前代码调用链和职责

此实现基于两个当前检出仓库，未沿用历史记录中曾出现的进程控制版本。

原图路径：`GalleryDetailView` → `GalleryTranslationSection` → `LocalTranslationClient.prepare` → `DownloadFileStore.exportEntry` → 独立输入快照 → 本机 API。

执行路径：独立项目的 `companion.app.JobStore` → 等待用户选择预设 → `EngineQueue`（单子进程）→ `python -B -m companion.engine --runtime <独立资源目录> --job request.json --config preset.json` → 原版 `launch.main` → 外部 `ManagedWindow` 继承接入任务生命周期 → `openDir` / `on_run_imgtrans` → `ModuleManager` 的现有检测、OCR、翻译、修复管线 → 原版 `on_pagtrans_finished` 的排版与 `saveCurrentPage` → `ImgSaveThread` → `project/result/`。生命周期和 macOS 无界面兼容处理只存在于子进程内存，不修改引擎文件。当前上游验证版本为 `ea9dcd5e18fb26091ec5c44ed947ce5e11b6c8d8`，升级后需要重新验证。

收回路径：引擎结构化成功状态 + 子进程零退出码 + 完整输出验证 → `result.json` / `awaitingImport` → Swift 客户端按页下载 → `TranslationFileStore.importVersion` → 原子目录提交 → `AppTranslationLibrary.refresh` → ACK。

阅读路径：独立的 `ReadingEdition` 与现有 `ReaderContentSource` 共同交给 `AppModel.readerPageData`。单页、双页、连续阅读、缩略图及媒体保存均使用版本身份。iOS 的原生分页容器显式传递版本，并在切换时重建缓存页；macOS 和 iOS 的现有页码与进度逻辑继续使用 GalleryKey。

同步路径：`DeviceSyncManifest` v2 中分离原图清单与译件条目 → `DeviceSyncTranslationReconciler` → 原有 `DeviceSyncCoordinator`、加密配对、确认预览与有界传输连接 → 独立译页命名空间 → 译件文件存储完整提交。原有原图索引格式 v1 无需重写；译件索引由不可变版本清单和已校验的续传页面集合组成。进程内只加载一次，普通同步不会全库解码或重算译图摘要。

## 协议和恢复

服务只绑定 `127.0.0.1:49179`。API 前缀 `/v1`，当前协议版本 1。

| 方法与路径 | 行为 |
| --- | --- |
| GET `/health` | 无凭据健康检查及协议版本 |
| POST `/connect` | 原生本机客户端自动握手，校验协议并返回当前会话令牌 |
| GET `/capabilities` | 协议和页面数量/大小限制 |
| POST `/jobs` | 幂等创建；相同 requestID 的不同请求拒绝 |
| GET `/jobs`、`/jobs/{id}` | 恢复已知 Gallery 任务、查询状态 |
| PUT `/jobs/{id}/pages/{index}` | 流式原图，大小、SHA-256 和静态图像验证 |
| POST `/jobs/{id}/commit` | 验证完整输入，进入等待队列 |
| GET `/jobs/{id}/result` | 完整版本清单 |
| GET `/jobs/{id}/result/pages/{index}` | 流式译图 |
| POST `/jobs/{id}/ack` | 持久化接收确认；重复 ACK 安全 |

除健康检查和自动握手外均验证 Bearer 令牌。会话令牌仅存于内存，服务每次启动随机生成；Swift 客户端发现凭据过期后自动重新握手并重试一次，无需读写 Keychain。HTTP 校验精确 Host，拒绝 Origin、浏览器 Fetch 元数据和 Transfer-Encoding；握手额外要求 `X-EhViewer-Client: EhViewer-macOS` 和 JSON 协议版本。没有 CORS、任意路径读取或命令执行接口，浏览器跨域预检拒绝。此模式信任本机原生客户端，不向局域网开放。客户端拒绝 HTTP 重定向。JSON 请求最大 4 MiB，单页最大 256 MiB，最多 10,000 页，静态图像最多一亿像素。动画、视频和不支持的格式明确拒绝。

EhViewer 启动后每三秒检测连接，即使没有任务也会发现稍后启动的翻译应用；服务未运行或正常退出时安静等待，保留待恢复任务。仅有本次更新的两端支持自动连接；旧 `/pair` 接口及两端配对按钮已移除。设备之间的同步配对继续沿用原有流程。

SHA-256 使用小写十六进制。索引从零开始，原图名称固定宽度。每页结果保留原图 SHA-256；最终 versionID 在生成结果时确定，重复拉取及跨设备同步保留此身份。

队列位于 `~/Library/Application Support/EhViewerTranslationCompanion/`，SQLite 保存状态。未启动任务不会自动翻译；已选择配置并等待执行的任务可在服务重启后继续排队。运行任务重启后标为中断，支持建立新执行重试。子进程正常退出、完整页面映射及全部校验均通过才发布结果。写完完整清单后、数据库更新前崩溃的结果会在重启时重新校验恢复。

EhViewer 按资料空间保存请求与输入快照，断连后使用同一 requestID 重传。结果先保存到暂存目录，经逐页校验后整体提交。Swift 译件清单是存储提交记录，不更改 SwiftData 模型或迁移既有用户数据库。原图移除前，相关 Gallery 元数据保存在译件存储中供离线阅读及同步使用。

译页同步中断会保留已验证页面，下轮仅请求缺少的页；未完成版本不可阅读。同 versionID 的不同清单在同步预览之前拒绝，不静默覆盖。不同 versionID 非破坏合并。完成结果保留在翻译应用，ACK 仅改变交付状态；当前版本不自动清理项目、模型、失败工作区或已完成结果。

## 诊断、验证和发布边界

阶段记录（2026-10-16）：

| 阶段 | 实际修改范围 | 已验证结果 | 验收边界 |
| --- | --- | --- | --- |
| 0 仓库调查 | 本文记录当前下载、阅读、同步和引擎调用链 | 两仓库修改前均为干净工作区；读取各自 AGENTS.md | 历史方案只作调查线索，未假设已有实现 |
| 1 引擎原型 | 初版使用上游挂钩；2026-10-17 已撤回并迁为独立项目的 `companion/engine.py` 和 `companion/job.py`，上游保持原样 | 初版指定漫画的两页真实 OCR、LLM 翻译、修复与嵌字；输出均为 1280×1790，大小和 SHA-256 校验通过 | 小规模真实测试，未做整本质量评定；迁移验证记录见独立项目 |
| 2 译件管理 | `GalleryTranslationManifest.swift`、`TranslationFileStore.swift`、`TranslationPageReceiver.swift`、`AppTranslationLibrary.swift`，详情、阅读器、预览、保存和资料库入口 | 完整导入、损坏拒绝、多版本、归档、重启读取及资料空间偏好恢复通过 | 使用原子清单，无 SwiftData schema 变更；未打开用户旧资料空间作人工验收 |
| 3 本机通信 | `LocalTranslationClient.swift`、独立项目 `companion/app.py` 中的 HTTP/认证/持久化任务、macOS 本机 ATS 配置 | 原生客户端配对、上传、重建客户端、引擎渲染、导入和 ACK 联通测试通过，服务确认 Delivered | 联通测试使用生成图片和仅渲染预设，真实模型另行验证 |
| 4 配置与队列 | Qt 管理窗口、原生设置入口、托管预设快照、SQLite 队列、单进程执行、取消/重试/缓存复用 | Python 9 项针对性测试通过；Qt offscreen 构造、预设复制、退出正常，原配置字节未变 | 模型和参数 UI 复用现有 BallonsTranslator；未逐一运行所有模型组合 |
| 5 设备同步 | `DeviceSyncTranslation.swift`、`DeviceSyncManifest.swift`、`DeviceSyncCoordinator.swift`、同步预览统计及存储连接点 | 经现有帧传输层发送译页、缺页续传、版本冲突拒绝和重复同步规划通过 | 同步协议 v5、清单 v2；原图索引 v1 保留；未连接实体 iPhone/iPad |
| 6 开发者交付 | Xcode 文件注册、九份语言资源、独立 `.app` 构建脚本和 `.command` 启动器、本文档 | 45 项 Swift 测试通过；iOS Simulator/macOS 构建通过；资源/项目/应用 plist lint、脚本语法及 diff 检查通过 | 开发者模式交付；签名公证、实体设备、长时间压力及分发许可验收尚未进行 |

所有既有 Swift 业务文件只增加版本解析、存储或同步连接点；语言资源覆盖 zh-Hans、zh-Hant、en、ja、ko、es、fr、de、th。没有迁移或修改用户下载、模型及既有翻译项目。

独立应用的「诊断文件」打开私有任务工作区，包含配置快照、项目、结构化引擎状态及日志；不要公开上传整个工作区。`engine-diagnostic.json` 记录退出码和失败类型。语言、模型、计算设备与 LLM 参数由独立设置面板管理；模型目录通过只读子进程扫描静态元数据，不加载推理模型或打开原软件界面。「环境与模型状态」显示运行目录、选中模块及依赖安装情况。复杂的高级参数未全部提供专用控件，会保留在原生 JSON 预设中。

针对性验证命令：

```sh
swift test --filter 'TranslationTests|DeviceSyncManifestTests|DeviceSyncIndexTests|DeviceSyncStorageTests|ReaderInteractionTests'
xcodebuild -project EhViewer.xcodeproj -scheme EhViewer -sdk macosx CODE_SIGNING_ALLOWED=NO build
xcodebuild -project EhViewer.xcodeproj -scheme EhViewer -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
```

独立项目 `/Users/liao/Documents/Tools/EhViewerTranslationCompanion`：

```sh
.venv/bin/python -B -m unittest tests.test_companion tests.test_engine tests.test_settings -v
.venv/bin/python -B -m tests.settings_smoke
.venv/bin/python -B -m tests.companion_test_server
```

最后一个命令准备仅渲染、不调用推理或外部 API 的联通测试服务，并打印临时 source.jpg 路径。运行前关闭实际的 EhViewer 和翻译应用，以免实际客户端连接测试端口。使用 `EH_COMPANION_TEST=1 EH_COMPANION_SOURCE=<路径> swift test --filter nativeClientAutoConnectsReconnectsUploadsRestartsImportsAndAcknowledges` 检查无任务时自动发现、服务重启后重连、上传、重建客户端、导入和 ACK；测试通过临时目录标记控制服务启动和重启，使用内存中的临时凭据。

2026-10-17 独立迁移验证：11 项 Python 测试、原生设置离屏打开/语言修改/保存/关闭、外部适配器的仅渲染任务、原生客户端上传/导入/ACK 均通过。指定英文漫画的前两页也在未修改的上游引擎上重新通过真实 OCR、LLM 翻译、修复和嵌字验证，输出均为 1280×1790，页面映射及摘要通过。运行前后原引擎 69,572 个文件的大小和修改时间无变化，Git 工作区为空。本轮 EhViewer 仅更新文档，未重跑跨平台完整构建。

此后已将设置入口替换为独立应用自有面板，并移除外部适配器的原生设置启动模式。17 项 Python 测试、真实静态目录读取与独立设置保存通过；用面板保存的英文 OCR 配置完成一页真实处理并验证输出。常用设置不依赖原软件窗口；原生预设格式和既有任务配置快照继续兼容。

真实漫画验证使用用户提供目录中的前两页，以配置副本切换到 `macos_ocr` 和 English 来源，保留既有 LLM 翻译器、目标语言、修复与嵌字设置。真实 OCR/翻译/嵌字输出、Swift 整本导入及重启读取分别检查；未修改用户原始漫画和日常配置。自动化联通测试使用生成图片及仅渲染预设，与真实模型验证分开计数。

2026-10-17 本机自动连接更新：10 项 Python 服务测试通过；原生 Swift 客户端在无任务时等待服务启动，服务退出/重新启动并更换会话令牌后自动恢复，随后完成两页完整上传、客户端重建、译件导入和 ACK，测试服务确认 `DELIVERED 1`。macOS、iOS 模拟器构建及九种语言资源检查通过。测试使用生成图片与仅渲染配置，没有调用外部翻译/OCR 服务。

根据用户授权使用 Computer Use 检查最终两端窗口：翻译应用主窗口已移除配对按钮；macOS EhViewer 详情页在服务关闭时安静等待，服务启动后自动显示已连接，全程没有验证码或连接弹窗。检查时临时更改的下载布局已恢复。

尚未做实体 iPhone/iPad 验收，也未评定整本翻译质量、长时间内存压力、所有格式/模型组合或公开分发许可。已有数据库无需新增模型迁移，但仍应在发布前对实体设备做验收。BallonsTranslator 源仓库标注 GPL-3.0-or-later；公开打包分发前还需逐项确认依赖、模型权重及字体许可。
