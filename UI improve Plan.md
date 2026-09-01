1. ## 侧边栏：

   * 选中时颜色匹配目前应用整体强调色而不是系统默认强调色，选中时文本边上的图标颜色记得跟随文本变化。
   * 设置页面中目前几乎每一行都是一个group，改为3个section：1.配置文件；2.设置；3.关于 。每个section内一整个group。
   * 新建/重命名profile等窗口在macOS上出现布局问题
2. ## 数据备份&同步设置页面：

   * 去掉大部分浅灰色大卡片背景。
     “数据与备份 / 导入 / 导出 / 设备间同步”直接作为设置 Section 展开，使用 macOS 原生 `Form` / `List` / grouped settings 的感觉。现在每一组都套一个大圆角矩形，更接近 iOS 卡片式设计，不太像桌面端。
   * 去掉绿色胶囊按钮。

像：

* 更新已下载画廊信息
* 导入元数据
* 导出元数据
* 重建设备同步索引

  都建议改成普通设置行，例如：
  **导入元数据**　　　　　　　　　`导入…`

  从 `.ehgallery` 文件导入元数据
  或者直接使用普通 `Button("导入…")`，不要给文字额外套淡绿色圆角底。

* **把“动作名称”和“文件格式”分层。**

  现在“导入元数据 (.ehgallery)”整句话作为按钮文字，信息密度偏高。可以改成：

  * 主标题：`导入元数据`
  * Secondary text：`从 .ehgallery 文件导入`

  这样更加符合 Apple 设置页的信息层级。
* **缩小 Section 之间的垂直间距。**

  当前“数据与备份 → 导入 → 导出 → 设备间同步”间距太大，但卡片内部又比较空，因此页面会产生一种“又松又杂”的感觉。macOS 设置通常应该更紧凑一些。
* **统一成 Settings Row 模式。**

  最适合这一页的是：

  <pre class="overflow-visible! px-0!" data-start="816" data-end="1339"><div class="relative w-full mt-4 mb-1"><div class=""><div class="contents"><div class="relative"><div class="h-full min-h-0 min-w-0"><div class="h-full min-h-0 min-w-0"><div class="border border-token-border-light border-radius-3xl corner-superellipse/1.1 rounded-3xl"><div class="h-full w-full border-radius-3xl bg-(--code-block-surface) corner-superellipse/1.1 overflow-clip rounded-3xl [--code-block-surface:var(--bg-elevated-secondary)] dark:[--code-block-surface:var(--composer-surface-primary)] lxnfua_clipPathFallback"><div class="pointer-events-none absolute end-1.5 top-1 z-2 md:end-2 md:top-1"></div><div class="relative"><div class="pe-11 pt-3"><div class="relative z-0 flex max-w-full"><div id="code-block-viewer" dir="ltr" class="q9tKkq_viewer cm-editor z-10 light:cm-light dark:cm-light flex h-full w-full flex-col items-stretch ͼd ͼr"><div class="cm-scroller"><pre class="cm-content q9tKkq_readonly m-0"><code><span>数据与备份

  画廊信息
  更新已下载画廊的元数据                       更新…


  导入与导出

  元数据                                     导入…
  .ehgallery 文件

  归档                                       导入…
  .eharchive 文件

  ─────────────────────────────────

  元数据                                     导出…
  .ehgallery 文件

  归档                                       导出…
  .eharchive 文件


  设备间同步

  设备间同步                                  >
  在附近的 EhViewer 设备之间同步漫画、阅读进度和元数据。

  同步索引                                   重建…</span></code></pre></div></div></div></div></div></div></div></div></div><div class=""><div class=""></div></div></div></div></div></div></pre>

  我甚至建议把现在单独的  **“导入”和“导出”合并为“导入与导出”** ，因为它们本质属于同一类数据管理操作。这样直接少一个视觉层级。
* **“设备间同步”不要同时出现两个强操作。**

  现在“重建设备同步索引”和“设备间同步 >”放在同一块里，两者视觉权重差不多，但实际上前者明显属于维护/故障排查操作。建议：
* `设备间同步`：正常设置入口
* `重建同步索引…`：放在下面，使用 secondary / bordered button
* 如果这个操作非常少用，甚至放进“高级”或同步详情页

## 整体设计逻辑：

所有页面都遵循同一套语言：

* **内容优先，装饰退后** ：界面的主要任务是呈现信息和操作，不依赖大量卡片、渐变、阴影、描边制造层级。
* **层级依靠排版与间距建立** ：优先使用标题、正文、secondary text、分组间距、separator，而不是不断增加背景容器。
* **原生组件优先** ：优先采用 SwiftUI 原生 `List`、`Form`、`Section`、`NavigationSplitView`、`Toolbar`、`Toggle`、`Picker`、`Button` 等，让系统承担交互和视觉规范。
* **减少“组件化外观”** ：不是每个功能都需要圆角卡片、胶囊按钮或独立边框。默认应当是普通行，只有真正需要强调或承载复杂内容时才使用容器。
* **强调克制的视觉权重** ：一个页面只保留少数真正需要强调的元素。普通操作、次要说明、辅助状态应主动弱化。
* **使用系统语义而非固定视觉值** ：颜色使用 semantic colors，图标使用 SF Symbols，背景和材质使用系统 Material，避免硬编码大量 RGB、阴影和圆角。
* **信息密度随平台自然变化** ：iOS 可以更触控友好、更纵向；iPadOS 强调分栏和空间利用；macOS 更紧凑、横向对齐、减少大块留白，但三端保持同一信息架构。
* **一致性高于局部“炫技”** ：相同类型的设置项、按钮、导航、提示信息必须使用相同模式，不为单个页面创造新的视觉语法。
* **减少视觉边界，强化结构边界** ：能用间距区分的不用背景，能用分组区分的不用描边，能用标题区分的不用卡片。
* **交互控件表达行为，而不是品牌装饰** ：按钮看起来首先应该像按钮，导航项像导航项，状态像状态，不要为了品牌色把普通文字全部变成高亮胶囊。
* **品牌存在于细节，而不是覆盖系统语言** ：品牌色用于 accent、选中状态和少量关键元素，不应替代 Apple 原生视觉体系。
* **界面应具有“安静感”** ：默认状态下页面应该稳定、简洁、低噪声；只有用户需要关注某件事时才提高颜色、对比度或视觉面积。
