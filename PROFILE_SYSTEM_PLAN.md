# 多 Profile 隔离、系统认证与完整删除

## Summary

在现有单一 `AppModel`、单一 SwiftData 容器和全局文件目录之上增加 profile 运行时层：

- 支持任意多个 profile。
- 启动时默认选中并直接恢复上次使用的 profile；在设置中切换 profile 时仍需完成系统认证。
- 按最终确认的方案取消应用自定义 PIN，不保存 profile 密码；使用 `LocalAuthentication` 的系统认证流程。iOS 优先使用 Face ID/Touch ID，macOS 使用 Touch ID 或系统设备认证，设备不支持生物识别时由系统回退到设备密码。
- 不因应用进入后台自动锁定；启动恢复不需要认证，只有用户切换 profile 时重新认证。
- 下载、SwiftData、本地缓存、历史、收藏、会话、阅读设置、过滤规则、搜索记录、标签数据库等所有用户状态和设置选项全部按 profile 隔离。
- 切换 profile 前暂停当前 profile 的下载和设备同步，保留已完成页面、部分下载文件和可恢复状态。
- 删除 profile 前再次进行系统认证并二次确认；至少保留一个 profile。删除失败时保留待删除状态，下一次启动继续清理，不把未清理完成的 profile 当作已删除。
- 设置中清除缓存/删除本地漫画仅针对当前profile生效。

## 核心实现变化

### 1. Profile 注册表、运行时和认证

新增应用级 `ProfileRegistry`/`ProfileSession` 层，职责与 `AppModel` 分离：

- `ProfileDescriptor` 保存 `id`、显示名称、创建时间、最近使用时间和存储格式版本等非敏感信息。
- 注册表使用应用级 JSON 文件保存，例如 `Application Support/EhViewer/Profiles/registry.json`；写入采用临时文件加原子替换。
- 新增待删除/删除日志状态，记录正在清理的 profile，支持应用崩溃后继续处理。
- `ProfileRuntime` 持有一个 profile 的完整运行时：
  - 对应的 `ModelContainer`；
  - 对应的 `AppModel`；
  - `PersistenceStore`；
  - `DownloadCoordinator`；
  - `DownloadFileStore`；
  - `GalleryCacheStore`；
  - `GalleryCoverLoader`；
  - `ImagePipeline`；
  - `TagSuggestionProvider`；
  - `DeviceSyncCoordinator` 和 `DeviceSyncIndexStore`；
  - profile 专属的 `SessionVault` 和偏好设置域。
- `ProfileSession` 负责启动、认证、创建、切换、关闭和删除 profile，避免让 `SettingsView` 直接重建 `AppModel` 或操作容器。

认证使用 `LocalAuthentication`：

- 调用系统的 `deviceOwnerAuthentication` 策略，让系统在支持时展示 Face ID/Touch ID，并允许系统回退到设备密码。
- 不新增应用 PIN、不保存明文密码、不保存自定义 PIN 校验值，也不维护应用自己的失败次数。
- iOS `Info.plist` 增加 Face ID 使用说明。
- profile 锁属于应用访问控制，不是独立的文件加密层；按照当前决定，拥有设备系统认证能力的人可以解锁任意 profile。

### 2. SwiftData 与文件存储隔离

采用“每个 profile 一个 SwiftData store”的方式，而不是给所有模型增加 `profileID` 字段。

扩展 `ModelContainerFactory`：

- 增加按指定 URL 创建容器的接口，例如 `make(storeURL:inMemory:)`。
- 保留现有 `SchemaV4` 模型和迁移兼容性；因为每个 profile 使用独立 store，不需要对 `GalleryRecord`、`DownloadJobRecord` 等所有模型增加 profile 字段。
- `PersistenceStore` 的所有查询天然只作用于当前 profile 容器，避免遗漏某个查询条件导致串数据。

为每个新 profile 建立独立目录，目录布局固定由 `ProfileStorageLayout` 生成，至少包含：

- SwiftData store；
- 下载文件；
- 画廊详情和预览缓存；
- 图片内存/磁盘缓存；
- 缩略图缓存；
- 标签数据库缓存；
- 设备同步索引；
- 设备同步事务日志；
- profile 偏好设置。

现有组件需要取消全局默认路径依赖：

- `GalleryCacheStore` 使用传入的 profile cache root。
- `ImagePipeline` 使用传入的 profile image-cache root。
- `GalleryCoverLoader` 不再由 `GalleryCoverLoader.shared` 共享 profile 数据，改为每个 `ProfileRuntime` 持有独立实例。
- `TagSuggestionProvider` 继续使用现有 `cacheURL` 注入能力，但 cache URL 改为当前 profile 目录。
- `DownloadFileStore` 使用当前 profile 的下载目录。
- `DeviceSyncIndexStore` 使用当前 profile 的索引目录。
- `DeviceSyncCoordinator` 的事务根目录从静态全局路径改为初始化时注入的 profile 事务目录。
- `UserDefaults.standard` 中的 `site`、阅读设置、下载排序/过滤设置和标签数据库标记改为 profile 专属 suite，例如 `com.liao.ehviewer.profile.<id>`；删除 profile 时移除该 suite 的 persistent domain。
- `SessionVault` 的 Keychain service/account 改为携带 profile ID，确保不同 profile 的 Cookie 永不共享。

下载后台任务必须携带 profile 身份：

- 当前任务描述从 `gid|token|pageIndex` 扩展为包含 profile ID 的格式。
- `taskObserver`、孤儿任务完成回调和恢复逻辑在写入 SwiftData 或文件前验证 profile ID。
- 如果收到属于非当前 profile 的旧任务回调，不得写入当前 profile；应将其标记为暂停、取消或交由对应 profile runtime 处理。
- 切换 profile 时先停止当前 `DownloadCoordinator`、取消当前 `BackgroundDownloadSession` 网络任务，再销毁旧 runtime。

`AppModel` 增加显式关闭接口，例如 `shutdown()`：

- 取消当前文件导入/导出和暂存任务；
- 停止下载并保存可恢复状态；
- 停止设备同步；
- 取消标签翻译、下载监听和其他后台任务；
- 取消未完成的后台网络请求；
- 清理只属于当前 runtime 的临时导出文件。

### 3. 启动、切换和设置界面

`EhViewerApp` 改为渲染 profile 会话宿主：

- 启动阶段读取 profile 注册表。
- 若存在上次使用的 profile，自动选中并直接恢复它，不显示启动解锁界面。
- 解锁界面提供“切换 profile”入口，可返回 profile 列表选择其他 profile。
- 启动恢复会在现有 readiness barrier 完成后创建并注入该 profile 的 `AppModel`、`ModelContainer` 和所有依赖；设置中的 profile 切换仍需在认证成功后执行同样的创建流程。
- 主界面使用 profile ID 或 runtime generation 作为 `.id(...)`，确保切换后旧的导航栈、`@Query`、列表缓存和异步任务不会复用到新 profile。
- macOS 阅读器窗口的 route 必须携带 profile 身份或 runtime generation；旧 profile 的 reader route 在切换后不能重新绑定到新 profile 的同一个 gallery key。

设置首页增加 profile 管理区域：

- 显示当前 profile 名称。
- 提供“切换 Profile”。
- 提供“新建 Profile”。
- 提供“重命名 Profile”。
- 提供“删除 Profile”。
- 显示每个 profile 的锁定状态和最近使用时间。
- 所有 profile 名称限制为非空、去除首尾空白并限制最大长度；名称用于识别，不参与认证。

切换流程：

1. 用户在设置中选择目标 profile。
2. 关闭当前设置页/导航状态。
3. 暂停下载、停止设备同步和取消当前 profile 的网络/文件任务。
4. 销毁旧 runtime 的 UI 引用。
5. 请求系统认证。
6. 认证成功后创建目标 profile runtime。
7. 只有新 runtime 成功恢复容器和基础依赖后才更新 `lastUsedProfileID`。
8. 认证取消或 runtime 初始化失败时留在 profile 选择/解锁页面，不改变当前 profile 数据。

### 4. Profile 删除

删除操作必须由 `ProfileSession` 统一执行，不由设置界面直接调用 `FileManager`。

删除顺序：

1. 检查目标不是最后一个 profile。
2. 请求系统认证。
3. 显示包含 profile 名称和数据范围的二次确认：
   - 下载任务和页面；
   - SwiftData 数据库；
   - 历史与收藏；
   - 普通画廊缓存；
   - 缩略图和图片缓存；
   - 标签数据库缓存；
   - 设备同步索引和事务日志；
   - profile 专属偏好设置；
   - profile 专属 Keychain 会话。
4. 如果目标是当前 profile，先暂停下载、停止同步并关闭当前 runtime。
5. 将 profile 标记为 `deleting`。
6. 按明确的 profile-owned target 清单逐项清理，不使用未解析的通配路径或全局递归路径。
7. 移除 profile 的 UserDefaults suite 和 Keychain session。
8. 检查所有目标不存在、Keychain 项不存在、注册表状态可更新。
9. 只有全部清理成功后才从注册表移除 profile。
10. 如果任何目标清理失败，保留 `deleting` 状态并显示失败项；下次启动继续重试，不能把 profile 列表项提前删除。

删除只作用于应用沙盒内由该 profile 拥有的文件。用户导出到系统“文件”或其他目录的备份、照片图库中的媒体以及用户手动保存到外部位置的文件不属于 profile-owned 数据，不自动删除。

### 5. 旧数据迁移

首次升级时，如果没有 profile 注册表但检测到现有单 profile 数据：

- 创建名称为“个人”的首个 profile。
- 将现有 SwiftData store、下载目录、画廊缓存、缩略图、图片缓存、标签数据库、设备同步索引和事务日志标记为首个 profile 所有。
- 为避免对现有 SwiftData 数据做高风险全量复制，首个 profile 可以采用 legacy storage layout，直接接管现有路径；从此以后新 profile 只能使用 profile 专属目录，旧默认路径不再作为全局共享路径。
- 将 `UserDefaults.standard` 中现有的 profile 相关键复制到首个 profile suite；确认复制成功后再清理这些旧键。
- 将默认 `SessionVault` 中的 Cookie 复制到首个 profile 专属 Keychain service；确认复制成功后清理旧 Keychain 项，避免删除 profile 后仍残留旧账号会话。
- 使用迁移 marker 和阶段日志保证迁移中断后可继续，不能在未完成复制/接管前宣称迁移完成。
- 新建的第二个及后续 profile 从空状态开始。

现有数据迁移后，所有用户可见数据仍留在“个人” profile，不清除登录、下载、历史、收藏或设置。

### 6. 导入、导出与设备同步

现有 `.ehgallery` 和 `.eharchive` 格式继续保持兼容，不把 Cookie、系统认证状态、profile 注册表或任何解锁凭据放进包内。

导出：

- 所有导出操作只读取当前已解锁 profile。
- 下载归档只包含当前 profile 的下载任务、下载元数据和当前 profile 的页面文件。
- 元数据导出只包含当前 profile 当前格式允许导出的画廊数据。
- 临时导出文件带有 profile 归属，切换/删除时只清理仍位于应用临时目录中的该 profile 临时文件。

导入：

- 先检查归档格式和内容，再让用户选择：
  - 导入到本机当前 profile；
  - 新建 profile 后导入。
- 选择新建 profile 时，用户输入名称，系统创建一个空 profile 并使用系统认证进入该 profile，然后只导入所选 `.ehgallery`/`.eharchive` 内容。
- 新 profile 不复制源 profile 的系统认证状态、Cookie、偏好、历史或收藏；只导入备份格式中实际存在的元数据、下载任务和页面文件。
- 导入失败时保留已成功导入的数据和新 profile，显示可重试状态，不静默删除部分结果。

设备同步：

- 设备同步始终使用双方当前激活的 profile runtime。
- 同步前在界面明确显示本机当前 profile 和对方当前 profile 名称，避免用户误同步。
- 不在同步协议中传输 Cookie、认证凭据、profile 注册表或系统解锁信息。
- 每个 profile 使用自己的设备同步索引和事务日志。
- 切换 profile 会停止当前同步并让目标 profile 使用自己的同步状态；不会读取旧 profile 的索引。

## Test Plan

新增或扩展以下测试范围：

- Profile 注册表：
  - 创建、重命名、最近使用 profile 持久化；
  - 多个 profile 可同时存在；
  - 原子写入失败后注册表保持上一份有效数据；
  - 删除状态可在模拟崩溃后恢复。
- SwiftData 隔离：
  - 两个 profile 使用相同 `GalleryKey` 时，标题、阅读进度、收藏、历史、下载任务和标签数据互不影响；
  - 删除一个 profile 的 store 后，另一个 profile 的 store 仍可正常打开并保留数据；
  - 现有 SchemaV4 数据可继续打开。
- 文件隔离：
  - 两个 profile 的下载文件、画廊缓存、缩略图、图片缓存、标签缓存和设备同步索引路径不同；
  - 相同 gallery key 在不同 profile 中不会读取到对方页面；
  - 删除一个 profile 后所有 profile-owned target 都不存在，其他 profile 的 target 仍存在。
- 会话隔离：
  - profile A 的 Cookie 不会被 profile B 的 `SessionVault` 读取；
  - 清除一个 profile 的 Cookie 不影响其他 profile；
  - 旧默认 Cookie 能安全迁移到首个 profile。
- 切换与并发：
  - 切换时运行中的下载被取消/暂停，已完成页面和队列状态保留；
  - 旧 runtime 的延迟回调不能写入新 profile；
  - 设备同步切换时会停止并释放旧 profile 的事务状态；
  - 后台任务描述中的 profile ID 不匹配时不会写入错误数据库。
- 删除：
  - 删除前必须经过系统认证和确认；
  - 当前 profile 删除后自动进入其他 profile 的解锁界面；
  - 最后一个 profile 不能删除；
  - 删除中途失败会保留待删除状态并支持重试；
  - 删除 profile 不影响其他 profile、外部备份文件或照片图库。
- 导入导出：
  - 当前 profile 导出只包含当前 profile 数据；
  - 导入到当前 profile 的行为保持现有兼容性；
  - 新建 profile 导入后只有归档实际包含的数据，未复制 Cookie、认证状态和偏好；
  - 旧版本归档仍可导入。
- UI 测试：
  - 启动直接进入上次使用的 profile；
  - 可以返回 profile 列表并切换；
  - 设置首页显示当前 profile；
  - 新建、重命名、删除入口具备稳定 accessibility identifier；
  - 测试通过注入的认证器或测试启动参数模拟系统认证，不依赖真实 Face ID/Touch ID。

验证命令仍以仓库现有命令为准：

```sh
swift test
xcodebuild -project EhViewer.xcodeproj -scheme EhViewer -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
xcodebuild -project EhViewer.xcodeproj -scheme EhViewer -sdk macosx CODE_SIGNING_ALLOWED=NO build
```

当前基线 `swift test` 在本机 Xcode beta 环境中因 SwiftPM sandbox 无法编译 manifest，工作区没有产生 tracked changes；实现后需要在该环境问题可用时重新执行。

## Assumptions

- 最终锁定方案以最新选择为准：取消应用 PIN，使用系统 Face ID/Touch ID/设备认证；不新增应用级 PIN 恢复流程。
- 启动自动选择并直接进入上次 profile；用户仍可以在设置中切换到其他 profile，切换操作需要系统认证。
- 应用回到前台不会自动重新锁定。
- 所有用户状态按 profile 隔离；系统语言等真正的应用级设置可以共享。
- 导入新 profile 时只导入所选备份内容，不复制源 profile 的偏好、历史、收藏、Cookie 或认证信息。
- 设备同步按照双方当前 profile 直接执行，不要求两台设备的 profile ID 相同。
- 删除必须至少保留一个 profile；当前 profile 可以删除，但会先关闭其 runtime 并切换到其他 profile 的解锁界面。
