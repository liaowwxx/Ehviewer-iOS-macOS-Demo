---
layout: home
title: EhViewer
description: An E-Hentai / ExHentai client for iPhone, iPad, and Mac.
lang: en
permalink: /en/
---

<section class="hero" id="hero">
  <div class="hero-spot" aria-hidden="true"></div>
  <div class="hero-grid wrap">
    <div class="hero-copy" data-reveal>
      <p class="kicker">E-Hentai / ExHentai client</p>
      <h1 class="display">EhViewer For<br><em>iOS / macOS</em></h1>
      <p class="hero-sub">Browse galleries, read manga, and manage downloads on iPhone, iPad, and Mac.</p>
      <div class="hero-actions" data-reveal style="--d:.14s">
        <a class="btn btn-primary" href="https://github.com/liaowwxx/ehviewer-iosdemo" rel="noreferrer" target="_blank">
          GitHub
          <svg class="arrow" viewBox="0 0 16 16" aria-hidden="true"><path d="M4 12 12 4M6.5 4H12v5.5"/></svg>
        </a>
        <a class="btn btn-ghost" href="{{ '/en/guide/' | relative_url }}">
          User guide
          <svg class="arrow" viewBox="0 0 16 16" aria-hidden="true"><path d="M4 12 12 4M6.5 4H12v5.5"/></svg>
        </a>
      </div>
      <ul class="hero-meta">
        <li>iOS / iPadOS / macOS 26+</li>
      </ul>
    </div>

    <div class="hero-stage" data-tilt data-reveal style="--d:.1s">
      <div class="device-showcase" id="device-showcase" data-lang="en">
        <div class="device-tabs" role="tablist" aria-label="Device preview">
          <button class="device-tab is-active" role="tab" aria-selected="true" data-device="iphone" type="button">iPhone</button>
          <button class="device-tab" role="tab" aria-selected="false" data-device="ipad" type="button">iPad</button>
          <button class="device-tab" role="tab" aria-selected="false" data-device="mac" type="button">macOS</button>
        </div>
        <div class="device-stage">
          <div class="device-frame is-active" data-device-panel="iphone"></div>
          <div class="device-frame" data-device-panel="ipad" hidden></div>
          <div class="device-frame" data-device-panel="mac" hidden></div>
                                      </div>
        <p class="device-hint">For reference only</p>
      </div>
    </div>
  </div>
  <div class="hero-scroll" aria-hidden="true">Scroll</div>
</section>

<section class="section features" id="features">
  <div class="wrap">
    <div class="section-head" data-reveal>
      <p class="kicker">Features</p>
      <h2 class="display">Key features</h2>
      <p class="lede">Browse, search, download, read, and migrate.</p>
    </div>

    <div class="feature-grid">
      <article class="feature-card" data-tilt data-reveal>
        <div class="glare" aria-hidden="true"></div>
        <div class="feature-icon">
          <svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="11" cy="11" r="6.5"/><path d="m16 16 4.5 4.5"/><path d="M8.5 11h5"/></svg>
        </div>
        <h3>Browse &amp; Search</h3>
        <p>Home, subscriptions, popular, toplists, and favorites. Tag suggestions, multi-tag queries, and advanced search.</p>
      </article>

      <article class="feature-card" data-tilt data-reveal style="--d:.06s">
        <div class="glare" aria-hidden="true"></div>
        <div class="feature-icon">
          <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 5.5A2.5 2.5 0 0 1 6.5 3H20v16.5H6.5A2.5 2.5 0 0 0 4 22Z"/><path d="M4 5.5v14A2.5 2.5 0 0 1 6.5 17H20"/></svg>
        </div>
        <h3>Reader</h3>
        <p>Continuous or paged reading, zoom, rotation, and volume-key paging. Reading progress is saved automatically.</p>
      </article>

      <article class="feature-card" data-tilt data-reveal style="--d:.12s">
        <div class="glare" aria-hidden="true"></div>
        <div class="feature-icon">
          <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3v12"/><path d="m7.5 10.5 4.5 4.5 4.5-4.5"/><path d="M4 16v3.5A1.5 1.5 0 0 0 5.5 21h13a1.5 1.5 0 0 0 1.5-1.5V16"/></svg>
        </div>
        <h3>Downloads</h3>
        <p>Queuing, resumable transfers, automatic retries, and background recovery. Filter, sort, and tag your library.</p>
      </article>

      <article class="feature-card" data-tilt data-reveal>
        <div class="glare" aria-hidden="true"></div>
        <div class="feature-icon">
          <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M8 7h9.5A2.5 2.5 0 0 1 20 9.5v0A2.5 2.5 0 0 1 17.5 12H8"/><path d="m11.5 4.5-3.5 3 3.5 3"/><path d="M16 17H6.5A2.5 2.5 0 0 1 4 14.5v0A2.5 2.5 0 0 1 6.5 12H16"/><path d="m12.5 20.5 3.5-3-3.5-3"/></svg>
        </div>
        <h3>Migration</h3>
        <p>Export .ehgallery metadata or .eharchive archives and AirDrop them to a new device. Android archives are supported too.</p>
      </article>

    </div>
  </div>
</section>

<section class="section reader-band" id="reader">
  <div class="wrap reader-grid">
    <div class="reader-copy" data-reveal>
      <p class="kicker">Reading</p>
      <h2 class="display">Reader</h2>
      <p>Supports continuous and paged reading. Paging direction, screen rotation, and volume-key gestures are configurable.</p>
      <ul class="check-list">
        <li>Continuous scroll or left/right paging, with zoom and rotation</li>
        <li>Reading progress saved automatically</li>
        <li>Save media to the system photo library</li>
        <li>Arrow keys and trackpad gestures on Mac</li>
      </ul>
      <a class="text-link" href="{{ '/en/guide/' | relative_url }}">Reader guide <span aria-hidden="true">→</span></a>
    </div>
    <div class="reader-stage" data-reader-demo data-lang="en" data-reveal style="--d:.12s">
      <div class="reader-ipad">
        <div class="reader-ipad-screen">
          <div class="reader-top">
            <button class="reader-back" type="button" aria-label="Back to gallery"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M14.5 5 7.5 12l7 7"/></svg>Gallery</button>
            <span class="reader-title">Example content</span>
            <button class="reader-more" type="button" aria-label="Reader options"><svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="5.5" cy="12" r="1.3"/><circle cx="12" cy="12" r="1.3"/><circle cx="18.5" cy="12" r="1.3"/></svg></button>
          </div>
          <button class="reader-art" type="button" aria-label="Toggle reader controls">
            <span class="reader-media-sheet" aria-hidden="true"><span></span></span>
            <span class="reader-loading-state"><i></i><em>Page</em><b data-reader-page>13</b></span>
            <small>Tap page to hide controls</small>
          </button>
          <div class="reader-controls">
            <div class="reader-bottom">
              <output class="reader-page-label" data-reader-label>Page 13 / 240</output>
              <input class="reader-slider" data-reader-slider type="range" min="1" max="240" value="13" aria-label="Reading progress">
              <button class="reader-chevron" data-reader-preview type="button" aria-label="Show previews"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="m6 14 6-6 6 6"/></svg></button>
            </div>
            <div class="reader-thumbnails" data-reader-thumbnails hidden></div>
          </div>
          <div class="reader-menu" data-reader-menu hidden>
            <p>Reading</p>
            <button type="button" data-reader-mode="paged"><span>Horizontal paging</span><b>✓</b></button>
            <button type="button" data-reader-mode="vertical"><span>Vertical paging</span><b></b></button>
            <button type="button" data-reader-direction><span>Paging direction</span><em>Right to left</em></button>
            <button type="button" data-reader-start><span>Start position</span><em>Last read position</em></button>
            <p>Display</p>
            <button type="button" data-reader-rotation><span>Screen rotation</span><em>Follow system</em></button>
            <p>Controls</p>
            <button type="button" data-reader-volume><span>Volume-key paging</span><i class="reader-switch" aria-hidden="true"></i></button>
            <button type="button" data-reader-reverse hidden><span>Reverse volume direction</span><i class="reader-switch" aria-hidden="true"></i></button>
          </div>
        </div>
      </div>
    </div>
  </div>
</section>

<section class="section start" id="start">
  <div class="wrap">
    <div class="section-head" data-reveal>
      <p class="kicker">Install</p>
      <h2 class="display">Install</h2>
      <p class="lede">Sideload with AltStore.</p>
    </div>

    <ol class="steps">
      <li class="step" data-reveal>
        <div class="step-num">01</div>
        <h3>Get the .ipa</h3>
        <p>Download the latest .ipa from GitHub Releases. No jailbreak needed.</p>
      </li>
      <li class="step" data-reveal style="--d:.1s">
        <div class="step-num">02</div>
        <h3>Install with AltStore</h3>
        <p>AirDrop the .ipa or open it from Files with AltStore. Trust your developer certificate on first launch.</p>
      </li>
      <li class="step" data-reveal style="--d:.2s">
        <div class="step-num">03</div>
        <h3>Start using it</h3>
        <p>Pick a site, search, or sign in — then start browsing galleries.</p>
      </li>
    </ol>

    <div class="start-actions" data-reveal>
      <a class="btn btn-primary" href="https://github.com/liaowwxx/ehviewer-iosdemo/releases" rel="noreferrer" target="_blank">
        Download .ipa
        <svg class="arrow" viewBox="0 0 16 16" aria-hidden="true"><path d="M4 12 12 4M6.5 4H12v5.5"/></svg>
      </a>
      <a class="btn btn-ghost" href="{{ '/en/guide/' | relative_url }}">User guide</a>
    </div>
  </div>
</section>
