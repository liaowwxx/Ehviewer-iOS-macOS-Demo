---
layout: home
title: EhViewer
description: 面向 iPhone、iPad 与 Mac 的 E-Hentai / ExHentai 画廊客户端。
lang: zh-Hans
permalink: /
---

<section class="hero" id="hero">
  <div class="hero-spot" aria-hidden="true"></div>
  <div class="hero-grid wrap">
    <div class="hero-copy" data-reveal>
      <p class="kicker">E-Hentai 浏览器</p>
      <h1 class="display">EhViewer For<br><em>iOS / macOS</em></h1>
      <p class="hero-sub">浏览画廊、离线阅读、管理本地资料库，并在 Apple 设备间同步下载内容。</p>
      <div class="hero-actions" data-reveal style="--d:.14s">
        <a class="btn btn-primary" href="https://github.com/liaowwxx/ehviewer-iosdemo" rel="noreferrer" target="_blank">
          GitHub 仓库
          <svg class="arrow" viewBox="0 0 16 16" aria-hidden="true"><path d="M4 12 12 4M6.5 4H12v5.5"/></svg>
        </a>
        <a class="btn btn-ghost" href="{{ '/guide/' | relative_url }}">
          使用说明
          <svg class="arrow" viewBox="0 0 16 16" aria-hidden="true"><path d="M4 12 12 4M6.5 4H12v5.5"/></svg>
        </a>
      </div>
      <ul class="hero-meta">
        <li>iOS / iPadOS 18+ · macOS 15+</li>
      </ul>
    </div>

    <div class="hero-stage" data-tilt data-reveal style="--d:.1s">
      <div class="device-showcase" id="device-showcase" data-lang="zh">
        <div class="device-tabs" role="tablist" aria-label="设备预览">
          <button class="device-tab is-active" role="tab" aria-selected="true" data-device="iphone" type="button">iPhone</button>
          <button class="device-tab" role="tab" aria-selected="false" data-device="ipad" type="button">iPad</button>
          <button class="device-tab" role="tab" aria-selected="false" data-device="mac" type="button">macOS</button>
        </div>
        <div class="device-stage">
          <div class="device-frame is-active" data-device-panel="iphone"></div>
          <div class="device-frame" data-device-panel="ipad" hidden></div>
          <div class="device-frame" data-device-panel="mac" hidden></div>
                                      </div>
        <p class="device-hint">页面仅供参考</p>
      </div>
    </div>
  </div>
  <div class="hero-scroll" aria-hidden="true">Scroll</div>
</section>

<section class="section features" id="features">
  <div class="wrap">
    <div class="section-head" data-reveal>
      <p class="kicker">功能</p>
      <h2 class="display">主要功能</h2>
      <p class="lede">从在线发现到离线资料库，再到附近设备安全同步。</p>
    </div>

    <div class="feature-grid">
      <article class="feature-card" data-tilt data-reveal>
        <div class="glare" aria-hidden="true"></div>
        <div class="feature-icon">
          <svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="11" cy="11" r="6.5"/><path d="m16 16 4.5 4.5"/><path d="M8.5 11h5"/></svg>
        </div>
        <h3>浏览与搜索</h3>
        <p>首页、订阅、热门、排行与收藏；支持标签联想、多标签组合、高级搜索和过滤规则。</p>
      </article>

      <article class="feature-card" data-tilt data-reveal style="--d:.06s">
        <div class="glare" aria-hidden="true"></div>
        <div class="feature-icon">
          <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 5.5A2.5 2.5 0 0 1 6.5 3H20v16.5H6.5A2.5 2.5 0 0 0 4 22Z"/><path d="M4 5.5v14A2.5 2.5 0 0 1 6.5 17H20"/></svg>
        </div>
        <h3>阅读</h3>
        <p>连续滚动与翻页、缩放旋转、音量键翻页；自动保存阅读进度。</p>
      </article>

      <article class="feature-card" data-tilt data-reveal style="--d:.12s">
        <div class="glare" aria-hidden="true"></div>
        <div class="feature-icon">
          <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3v12"/><path d="m7.5 10.5 4.5 4.5 4.5-4.5"/><path d="M4 16v3.5A1.5 1.5 0 0 0 5.5 21h13a1.5 1.5 0 0 0 1.5-1.5V16"/></svg>
        </div>
        <h3>下载</h3>
        <p>队列、暂停继续、失败重试与后台恢复；支持搜索、分类/状态筛选、排序和批量管理。</p>
      </article>

      <article class="feature-card" data-tilt data-reveal>
        <div class="glare" aria-hidden="true"></div>
        <div class="feature-icon">
          <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 4.5A2.5 2.5 0 0 1 7.5 2H20v16.5H7.5A2.5 2.5 0 0 0 5 21.5Z"/><path d="M5 4.5v15A2.5 2.5 0 0 1 7.5 17H20"/><path d="M9 7h7M9 11h5"/></svg>
        </div>
        <h3>本地资料库</h3>
        <p>已下载内容离线可读；支持本地搜索、分类筛选、列表/卡片布局、阅读历史与本地收藏。</p>
      </article>

      <article class="feature-card" data-tilt data-reveal style="--d:.06s">
        <div class="glare" aria-hidden="true"></div>
        <div class="feature-icon">
          <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 7h10a3 3 0 0 1 3 3"/><path d="m17 4 3 3-3 3"/><path d="M17 17H7a3 3 0 0 1-3-3"/><path d="m7 20-3-3 3-3"/><path d="M9 11.5h6v5H9z"/></svg>
        </div>
        <h3>设备间同步 <span class="feature-beta">Beta</span></h3>
        <p>在同一局域网发现附近设备，通过验证码和双方确认建立加密连接，双向补齐缺失画廊与页面。</p>
      </article>

      <article class="feature-card" data-tilt data-reveal style="--d:.12s">
        <div class="glare" aria-hidden="true"></div>
        <div class="feature-icon">
          <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M8 7h9.5A2.5 2.5 0 0 1 20 9.5v0A2.5 2.5 0 0 1 17.5 12H8"/><path d="m11.5 4.5-3.5 3 3.5 3"/><path d="M16 17H6.5A2.5 2.5 0 0 1 4 14.5v0A2.5 2.5 0 0 1 6.5 12H16"/><path d="m12.5 20.5 3.5-3-3.5-3"/></svg>
        </div>
        <h3>备份与迁移</h3>
        <p>导入导出 .ehgallery 元数据或 .eharchive 完整归档，支持选择部分本地画廊和迁移 Android 下载。</p>
      </article>

    </div>
  </div>
</section>

<section class="section reader-band" id="reader">
  <div class="wrap reader-grid">
    <div class="reader-copy" data-reveal>
      <p class="kicker">阅读</p>
      <h2 class="display">阅读器</h2>
      <p>支持连续阅读与翻页阅读，翻页方向、屏幕旋转与音量键手势都可以按习惯设置。</p>
      <ul class="check-list">
        <li>连续滚动与左右翻页，支持缩放与旋转</li>
        <li>自动保存阅读进度</li>
        <li>媒体可保存到系统相册</li>
        <li>Mac 支持方向键与触控板翻页</li>
      </ul>
      <a class="text-link" href="{{ '/guide/' | relative_url }}">阅读相关说明 <span aria-hidden="true">→</span></a>
    </div>
    <div class="reader-stage" data-reader-demo data-lang="zh" data-reveal style="--d:.12s">
      <div class="reader-ipad">
        <div class="reader-ipad-screen">
          <div class="reader-top">
            <button class="reader-back" type="button" aria-label="返回画廊"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M14.5 5 7.5 12l7 7"/></svg>画廊</button>
            <span class="reader-title">示例内容</span>
            <button class="reader-more" type="button" aria-label="阅读选项"><svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="5.5" cy="12" r="1.3"/><circle cx="12" cy="12" r="1.3"/><circle cx="18.5" cy="12" r="1.3"/></svg></button>
          </div>
          <button class="reader-art" type="button" aria-label="切换阅读控件">
            <span class="reader-media-sheet" aria-hidden="true"><span></span></span>
            <span class="reader-loading-state"><i></i><b data-reader-page>13</b><em>页</em></span>
            <small>轻点页面隐藏控件</small>
          </button>
          <div class="reader-controls">
            <div class="reader-bottom">
              <output class="reader-page-label" data-reader-label>第 13 / 240 页</output>
              <input class="reader-slider" data-reader-slider type="range" min="1" max="240" value="13" aria-label="阅读进度">
              <button class="reader-chevron" data-reader-preview type="button" aria-label="展开预览"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="m6 14 6-6 6 6"/></svg></button>
            </div>
            <div class="reader-thumbnails" data-reader-thumbnails hidden></div>
          </div>
          <div class="reader-menu" data-reader-menu hidden>
            <p>阅读</p>
            <button type="button" data-reader-mode="paged"><span>左右翻页</span><b>✓</b></button>
            <button type="button" data-reader-mode="vertical"><span>上下翻页</span><b></b></button>
            <button type="button" data-reader-direction><span>翻页方向</span><em>从右到左</em></button>
            <button type="button" data-reader-start><span>开始位置</span><em>上次阅读位置</em></button>
            <p>显示</p>
            <button type="button" data-reader-rotation><span>屏幕旋转</span><em>跟随系统</em></button>
            <p>控制</p>
            <button type="button" data-reader-volume><span>音量键翻页</span><i class="reader-switch" aria-hidden="true"></i></button>
            <button type="button" data-reader-reverse hidden><span>反转音量键方向</span><i class="reader-switch" aria-hidden="true"></i></button>
          </div>
        </div>
      </div>
    </div>
  </div>
</section>

<section class="section start" id="start">
  <div class="wrap">
    <div class="section-head" data-reveal>
      <p class="kicker">安装</p>
      <h2 class="display">安装</h2>
      <p class="lede">使用 AltStore 侧载安装。</p>
    </div>

    <ol class="steps">
      <li class="step" data-reveal>
        <div class="step-num">01</div>
        <h3>获取 .ipa</h3>
        <p>在 GitHub Releases 下载最新 .ipa 文件，无需越狱。</p>
      </li>
      <li class="step" data-reveal style="--d:.1s">
        <div class="step-num">02</div>
        <h3>用 AltStore 安装</h3>
        <p>隔空投送或从文件 App 打开 .ipa，用 AltStore 安装；首次使用请信任开发者证书。</p>
      </li>
      <li class="step" data-reveal style="--d:.2s">
        <div class="step-num">03</div>
        <h3>开始使用</h3>
        <p>选择站点、搜索或登录，即可开始浏览画廊。</p>
      </li>
    </ol>

    <div class="start-actions" data-reveal>
      <a class="btn btn-primary" href="https://github.com/liaowwxx/ehviewer-iosdemo/releases" rel="noreferrer" target="_blank">
        下载 .ipa
        <svg class="arrow" viewBox="0 0 16 16" aria-hidden="true"><path d="M4 12 12 4M6.5 4H12v5.5"/></svg>
      </a>
      <a class="btn btn-ghost" href="{{ '/guide/' | relative_url }}">使用说明</a>
    </div>
  </div>
</section>
