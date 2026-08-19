---
layout: home
title: EhViewer
description: An open-source E-Hentai / ExHentai client for iPhone, iPad, and Mac. Browse, read, download, and migrate.
lang: en
permalink: /en/
---

<section class="hero" id="hero">
  <div class="hero-spot" aria-hidden="true"></div>
  <div class="hero-grid wrap">
    <div class="hero-copy" data-reveal>
      <p class="kicker">E-Hentai / ExHentai client</p>
      <h1 class="display">EhViewer For<br><em>iOS / macOS</em></h1>
      <p class="hero-sub">Browse galleries, read manga, and manage downloads on iPhone, iPad, and Mac. Open source and free.</p>
      <div class="hero-actions" data-reveal style="--d:.14s">
        <a class="btn btn-primary" data-magnetic href="https://github.com/liaowwxx/ehviewer-iosdemo" rel="noreferrer" target="_blank">
          GitHub
          <svg class="arrow" viewBox="0 0 16 16" aria-hidden="true"><path d="M4 12 12 4M6.5 4H12v5.5"/></svg>
        </a>
        <a class="btn btn-ghost" data-magnetic href="{{ '/en/guide/' | relative_url }}">
          User guide
          <svg class="arrow" viewBox="0 0 16 16" aria-hidden="true"><path d="M4 12 12 4M6.5 4H12v5.5"/></svg>
        </a>
      </div>
      <ul class="hero-meta">
        <li>Open source · GPL-3.0</li>
        <li>iOS / iPadOS / macOS 26+</li>
        <li>Built with SwiftUI</li>
      </ul>
    </div>

    <div class="hero-stage" data-tilt data-reveal style="--d:.1s">
      <div class="device-showcase" id="device-showcase" data-lang="en">
        <div class="device-tabs" role="tablist" aria-label="Device preview">
          <button class="device-tab is-active" data-device="iphone" type="button">iPhone</button>
          <button class="device-tab" data-device="ipad" type="button">iPad</button>
          <button class="device-tab" data-device="mac" type="button">macOS</button>
        </div>
        <div class="device-stage">
          <div class="device-frame is-active" data-device-panel="iphone"></div>
          <div class="device-frame" data-device-panel="ipad" hidden></div>
          <div class="device-frame" data-device-panel="mac" hidden></div>
          <div class="float-chip fc-1"><span class="chip-dot ok"></span>ExHentai connected</div>
          <div class="float-chip fc-2"><span class="chip-dot progress"></span>Downloaded · 214 pages</div>
          <div class="float-chip fc-3"><span class="chip-dot"></span>Progress synced</div>
        </div>
        <p class="device-hint">Click Dock / sidebar items to switch pages · click a gallery for details</p>
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

      <article class="feature-card" data-tilt data-reveal style="--d:.06s">
        <div class="glare" aria-hidden="true"></div>
        <div class="feature-icon">
          <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3 5 6v5c0 4.6 3 8.4 7 10 4-1.6 7-5.4 7-10V6Z"/><path d="m9.2 11.8 2 2 3.6-3.9"/></svg>
        </div>
        <h3>Privacy</h3>
        <p>Data stays on your device and sessions live in the system keychain. Network requests only go where you choose.</p>
      </article>

      <article class="feature-card" data-tilt data-reveal style="--d:.12s">
        <div class="glare" aria-hidden="true"></div>
        <div class="feature-icon">
          <svg viewBox="0 0 24 24" aria-hidden="true"><path d="m8 8-4.5 4L8 16"/><path d="m16 8 4.5 4L16 16"/><path d="M13.5 5.5 10.5 18.5"/></svg>
        </div>
        <h3>Open Source</h3>
        <p>Built with SwiftUI and SwiftData, licensed under GPL-3.0. Build it yourself and make it yours.</p>
      </article>
    </div>
  </div>
</section>

<section class="section reader-band" id="reader">
  <div class="wrap reader-grid">
    <div class="reader-copy" data-reveal>
      <p class="kicker">Reader</p>
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
    <div class="reader-stage" data-reveal style="--d:.12s">
      <div class="reader-mock" aria-hidden="true">
        <div class="sheet sheet-back"></div>
        <div class="sheet sheet-front">
          <div class="sheet-topbar"><span>CHAPTER 12</span><span>12 / 240</span></div>
          <div class="sheet-body">
            <div class="sheet-line"></div>
            <div class="sheet-line short"></div>
            <div class="sheet-panel">靜</div>
            <div class="sheet-line short"></div>
            <div class="sheet-line"></div>
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
      <a class="btn btn-primary" data-magnetic href="https://github.com/liaowwxx/ehviewer-iosdemo/releases" rel="noreferrer" target="_blank">
        Download .ipa
        <svg class="arrow" viewBox="0 0 16 16" aria-hidden="true"><path d="M4 12 12 4M6.5 4H12v5.5"/></svg>
      </a>
      <a class="btn btn-ghost" data-magnetic href="{{ '/en/guide/' | relative_url }}">User guide</a>
    </div>
  </div>
</section>

<section class="section faq" id="faq">
  <div class="wrap faq-wrap">
    <div class="section-head" data-reveal>
      <p class="kicker">FAQ</p>
      <h2 class="display">FAQ</h2>
      <p class="lede">Full details are in the <a href="{{ '/en/guide/' | relative_url }}">user guide</a>. For anything else, open an <a href="https://github.com/liaowwxx/ehviewer-iosdemo/issues" rel="noreferrer">issue on GitHub</a>.</p>
    </div>
    <div class="faq-list" data-reveal>
      <details class="faq-item" open>
        <summary>Do I need to sign in?<span class="plus" aria-hidden="true">+</span></summary>
        <div class="faq-body"><p>Only for favorites, ExHentai content, or when an account session is required. Use <strong>Settings → Login</strong> with username and password, web login, or cookies.</p></div>
      </details>
      <details class="faq-item">
        <summary>Should I export metadata or an archive?<span class="plus" aria-hidden="true">+</span></summary>
        <div class="faq-body"><p>Choose <code>.ehgallery</code> to sync gallery lists and reading info; choose <code>.eharchive</code> when downloaded images or videos should come along.</p></div>
      </details>
      <details class="faq-item">
        <summary>Gallery images fail to load — why?<span class="plus" aria-hidden="true">+</span></summary>
        <div class="faq-body"><p>The site may be rate-limiting, the network unavailable, or the session invalid. Check the network and refresh; for ExHentai, confirm the account has access.</p></div>
      </details>
    </div>
  </div>
</section>
