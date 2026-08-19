(() => {
  "use strict";

  const root = document.documentElement;
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const finePointer = window.matchMedia("(pointer: fine)").matches;

  /* ================= Theme ================= */
  const themeKey = "ehviewer-docs-theme";
  const savedTheme = localStorage.getItem(themeKey);
  if (savedTheme === "light" || savedTheme === "dark") root.dataset.theme = savedTheme;

  const themeToggle = document.getElementById("theme-toggle");
  if (themeToggle) {
    const updateThemeState = () => {
      const current = root.dataset.theme || "auto";
      themeToggle.setAttribute("aria-pressed", current === "dark" ? "true" : "false");
      themeToggle.setAttribute(
        "aria-label",
        current === "dark" ? "Switch to light theme" : "Switch to dark theme"
      );
    };
    themeToggle.addEventListener("click", () => {
      const current = root.dataset.theme || "auto";
      const next = current === "auto" ? "dark" : current === "dark" ? "light" : "auto";
      root.dataset.theme = next;
      if (next === "auto") localStorage.removeItem(themeKey);
      else localStorage.setItem(themeKey, next);
      updateThemeState();
    });
    updateThemeState();
  }

  /* ================= Nav scroll state ================= */
  const nav = document.getElementById("site-nav");
  if (nav) {
    const onScroll = () => nav.classList.toggle("is-scrolled", window.scrollY > 8);
    window.addEventListener("scroll", onScroll, { passive: true });
    onScroll();
  }

  /* ================= Cursor aura ================= */
  const aura = document.getElementById("cursor-aura");
  if (aura && finePointer && !reduceMotion) {
    let targetX = window.innerWidth / 2;
    let targetY = window.innerHeight / 2;
    let x = targetX;
    let y = targetY;

    window.addEventListener("pointermove", (event) => {
      targetX = event.clientX;
      targetY = event.clientY;
      aura.classList.add("is-on");
    }, { passive: true });

    document.addEventListener("pointerover", (event) => {
      const hot = event.target.closest("a, button, summary, input, [data-tilt], [data-magnetic]");
      aura.classList.toggle("is-hot", Boolean(hot));
    }, { passive: true });

    const tick = () => {
      x += (targetX - x) * 0.16;
      y += (targetY - y) * 0.16;
      aura.style.translate = x + "px " + y + "px";
      requestAnimationFrame(tick);
    };
    tick();
  } else if (aura) {
    aura.style.display = "none";
  }

  /* ================= Hero spotlight + parallax ================= */
  const hero = document.getElementById("hero");
  if (hero && !reduceMotion) {
    let targetX = 0.5;
    let targetY = 0.42;
    let x = 0.5;
    let y = 0.42;

    hero.addEventListener("pointermove", (event) => {
      const rect = hero.getBoundingClientRect();
      targetX = (event.clientX - rect.left) / rect.width;
      targetY = (event.clientY - rect.top) / rect.height;
    }, { passive: true });

    const tick = () => {
      x += (targetX - x) * 0.07;
      y += (targetY - y) * 0.07;
      hero.style.setProperty("--mx", (x * 100).toFixed(2) + "%");
      hero.style.setProperty("--my", (y * 100).toFixed(2) + "%");
      const px = ((x - 0.5) * 2).toFixed(3);
      const py = ((y - 0.5) * 2).toFixed(3);
      hero.style.setProperty("--px", px);
      hero.style.setProperty("--py", py);
      requestAnimationFrame(tick);
    };
    tick();
  }

  /* ================= 3D tilt cards ================= */
  const tiltables = document.querySelectorAll("[data-tilt]");
  if (tiltables.length && !reduceMotion) {
    tiltables.forEach((card) => {
      let raf = 0;

      const reset = () => {
        card.classList.remove("is-tilting");
        card.style.setProperty("--rx", "0deg");
        card.style.setProperty("--ry", "0deg");
      };

      card.addEventListener("pointermove", (event) => {
        const rect = card.getBoundingClientRect();
        const px = (event.clientX - rect.left) / rect.width;
        const py = (event.clientY - rect.top) / rect.height;
        card.classList.add("is-tilting");
        cancelAnimationFrame(raf);
        raf = requestAnimationFrame(() => {
          card.style.setProperty("--rx", ((py - 0.5) * -7).toFixed(2) + "deg");
          card.style.setProperty("--ry", ((px - 0.5) * 9).toFixed(2) + "deg");
          card.style.setProperty("--gx", (px * 100).toFixed(1) + "%");
          card.style.setProperty("--gy", (py * 100).toFixed(1) + "%");
        });
      }, { passive: true });

      card.addEventListener("pointerleave", reset);
    });
  } else {
    tiltables.forEach((card) => {
      card.style.transform = "none";
      card.style.setProperty("--rx", "0deg");
      card.style.setProperty("--ry", "0deg");
    });
  }

  /* ================= Magnetic buttons ================= */
  if (!reduceMotion) {
    document.querySelectorAll("[data-magnetic]").forEach((el) => {
      let raf = 0;
      el.addEventListener("pointermove", (event) => {
        const rect = el.getBoundingClientRect();
        const dx = (event.clientX - rect.left - rect.width / 2) * 0.22;
        const dy = (event.clientY - rect.top - rect.height / 2) * 0.3;
        cancelAnimationFrame(raf);
        raf = requestAnimationFrame(() => {
          el.style.translate = dx.toFixed(1) + "px " + dy.toFixed(1) + "px";
        });
      }, { passive: true });
      el.addEventListener("pointerleave", () => {
        cancelAnimationFrame(raf);
        el.style.translate = "0px 0px";
      });
    });
  }

  /* ================= Reveal on scroll ================= */
  const reveals = [...document.querySelectorAll("[data-reveal]")];

  const revealNow = () => {
    const viewportBottom = window.innerHeight * 0.95;
    reveals.forEach((el) => {
      if (el.classList.contains("is-in")) return;
      const rect = el.getBoundingClientRect();
      if (rect.top < viewportBottom && rect.bottom > 0) el.classList.add("is-in");
    });
  };

  if (reduceMotion) {
    reveals.forEach((el) => el.classList.add("is-in"));
  } else {
    if ("IntersectionObserver" in window) {
      const revealObserver = new IntersectionObserver(
        (entries) => {
          entries.forEach((entry) => {
            if (entry.isIntersecting) {
              entry.target.classList.add("is-in");
              revealObserver.unobserve(entry.target);
            }
          });
        },
        { threshold: 0.12, rootMargin: "0px 0px -6% 0px" }
      );
      reveals.forEach((el) => revealObserver.observe(el));
    }
    window.addEventListener("load", revealNow);
    window.addEventListener("scroll", revealNow, { passive: true });
    revealNow();
  }

  /* ================= Scroll-spy for landing nav ================= */
  const navLinks = document.querySelectorAll('.nav-links a[href^="#"]');
  if (navLinks.length && "IntersectionObserver" in window) {
    const ids = [...navLinks].map((link) => link.getAttribute("href").slice(1));
    const spy = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          navLinks.forEach((link) => {
            link.classList.toggle("is-active", link.getAttribute("href") === "#" + entry.target.id);
          });
        });
      },
      { rootMargin: "-38% 0px -55% 0px", threshold: 0 }
    );
    ids.forEach((id) => {
      const section = document.getElementById(id);
      if (section) spy.observe(section);
    });
  }

/* ============================================================
   Device showcase — interactive iPhone / iPad / macOS mock
   ============================================================ */
const showcase = document.getElementById("device-showcase");
if (showcase) {
  const lang = showcase.dataset.lang === "en" ? "en" : "zh";

  const ICONS = {
    search: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="11" cy="11" r="6.5"/><path d="m16 16 4.5 4.5"/></svg>',
    person: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="8.5" r="3.8"/><path d="M5 20c1.2-3.2 3.8-5 7-5s5.8 1.8 7 5"/></svg>',
    list: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M9 6h11M9 12h11M9 18h11"/><circle cx="4.5" cy="6" r="1.3"/><circle cx="4.5" cy="12" r="1.3"/><circle cx="4.5" cy="18" r="1.3"/></svg>',
    download: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 4v11"/><path d="m7.5 11 4.5 4.5L16.5 11"/><path d="M5 19h14"/></svg>',
    books: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 4.5A2.5 2.5 0 0 1 7.5 2H20v17H7.5A2.5 2.5 0 0 0 5 21.5Z"/><path d="M5 4.5v15A2.5 2.5 0 0 1 7.5 17H20"/></svg>',
    clock: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/></svg>',
    gear: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="3.2"/><path d="M12 2.8v3M12 18.2v3M21.2 12h-3M5.8 12h-3M18.5 5.5l-2.1 2.1M7.6 16.4l-2.1 2.1M18.5 18.5l-2.1-2.1M7.6 7.6 5.5 5.5"/></svg>',
    house: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 11 12 4l8 7"/><path d="M6 9.5V20h12V9.5"/></svg>',
    tag: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 4h7l9 9-7 7-9-9Z"/><circle cx="8.5" cy="8.5" r="1.4"/></svg>',
    chart: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 20V4"/><path d="m4 16 5-5 3.5 3L20 6.5"/></svg>',
    heart: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 20s-7-4.6-9-9c-1.3-3 .8-6.5 4.2-6.5 2 0 3.6 1 4.8 2.8C13.2 5.5 14.8 4.5 16.8 4.5c3.4 0 5.5 3.5 4.2 6.5-2 4.4-9 9-9 9Z"/></svg>',
    back: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M14.5 5 7.5 12l7 7"/></svg>',
    play: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m9 6 9 6-9 6Z"/></svg>',
    plus: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>',
    forward: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m9.5 5 7 7-7 7"/></svg>',
  };

  const MOCK = {
    zh: {
      dock: [
        { id: "home", label: "浏览", icon: "list" },
        { id: "downloads", label: "下载", icon: "download" },
        { id: "local", label: "本地", icon: "books" },
        { id: "history", label: "历史", icon: "clock" },
        { id: "settings", label: "设置", icon: "gear" },
      ],
      side: [
        { label: "浏览", items: [
          { id: "home", label: "首页", icon: "house" },
          { id: "subscriptions", label: "订阅", icon: "tag" },
          { id: "popular", label: "热门", icon: "chart" },
          { id: "toplist", label: "排行", icon: "list" },
        ]},
        { label: "个人", items: [
          { id: "downloads", label: "下载", icon: "download" },
          { id: "local", label: "本地", icon: "books" },
          { id: "history", label: "历史", icon: "clock" },
          { id: "favorites", label: "收藏", icon: "heart" },
        ]},
        { label: "", items: [
          { id: "settings", label: "设置", icon: "gear" },
        ]},
      ],
      search: "搜索画廊或标签",
      panels: {
        home: { title: "首页" }, subscriptions: { title: "订阅" }, popular: { title: "热门" },
        toplist: { title: "排行" }, favorites: { title: "收藏" },
        downloads: { title: "下载" }, local: { title: "本地" },
        history: { title: "历史" }, settings: { title: "设置" },
      },
      galleries: [
        { id: "g1", letter: "夜", mc: "mc-1", cat: "Doujinshi", catColor: "#4a7dbd", title: "夜空下的星屑", uploader: "sora_1123", lang: "CN", pages: 128, rating: "4.6", time: "3小时前" },
        { id: "g2", letter: "春", mc: "mc-2", cat: "Manga", catColor: "#4c9a6b", title: "春日的午后", uploader: "hana_momo", lang: "JP", pages: 96, rating: "4.8", time: "昨天" },
        { id: "g3", letter: "街", mc: "mc-3", cat: "Artist CG", catColor: "#c05a4a", title: "城市速写簿", uploader: "ink_studio", lang: "EN", pages: 240, rating: "4.2", time: "2天前" },
        { id: "g4", letter: "港", mc: "mc-4", cat: "Game CG", catColor: "#8a6db8", title: "港湾灯火", uploader: "night_pixel", lang: "JP", pages: 320, rating: "4.9", time: "3天前" },
      ],
      downloads: [
        { letter: "夜", mc: "mc-1", title: "夜空下的星屑", sub: "128 页 · 已下载 82 页", pct: 64, status: "doing", statusText: "下载中" },
        { letter: "港", mc: "mc-4", title: "港湾灯火", sub: "320 页 · 已下载 320 页", pct: 100, status: "done", statusText: "已完成" },
        { letter: "春", mc: "mc-2", title: "春日的午后", sub: "96 页 · 已下载 40 页", pct: 42, status: "paused", statusText: "暂停" },
      ],
      history: [
        { letter: "夜", mc: "mc-1", title: "夜空下的星屑", sub: "阅读到 45/128 页 · 3小时前" },
        { letter: "港", mc: "mc-4", title: "港湾灯火", sub: "阅读到 12/320 页 · 昨天" },
        { letter: "街", mc: "mc-3", title: "城市速写簿", sub: "阅读到 200/240 页 · 4天前" },
      ],
      detail: { read: "阅读", add: "加入下载", back: "返回", tags: ["doujinshi", "原创", "治愈", "星空"] },
      reader: { title: "阅读", pages: "12 / 240" },
      favoritesNote: "暂无收藏",
      localBadge: "本地",
    },
    en: {
      dock: [
        { id: "home", label: "Browse", icon: "list" },
        { id: "downloads", label: "Downloads", icon: "download" },
        { id: "local", label: "Local", icon: "books" },
        { id: "history", label: "History", icon: "clock" },
        { id: "settings", label: "Settings", icon: "gear" },
      ],
      side: [
        { label: "Browse", items: [
          { id: "home", label: "Home", icon: "house" },
          { id: "subscriptions", label: "Subscriptions", icon: "tag" },
          { id: "popular", label: "Popular", icon: "chart" },
          { id: "toplist", label: "Toplist", icon: "list" },
        ]},
        { label: "Personal", items: [
          { id: "downloads", label: "Downloads", icon: "download" },
          { id: "local", label: "Local", icon: "books" },
          { id: "history", label: "History", icon: "clock" },
          { id: "favorites", label: "Favorites", icon: "heart" },
        ]},
        { label: "", items: [
          { id: "settings", label: "Settings", icon: "gear" },
        ]},
      ],
      search: "Search galleries or tags",
      panels: {
        home: { title: "Home" }, subscriptions: { title: "Subscriptions" }, popular: { title: "Popular" },
        toplist: { title: "Toplist" }, favorites: { title: "Favorites" },
        downloads: { title: "Downloads" }, local: { title: "Local" },
        history: { title: "History" }, settings: { title: "Settings" },
      },
      galleries: [
        { id: "g1", letter: "N", mc: "mc-1", cat: "Doujinshi", catColor: "#4a7dbd", title: "Stardust at Night", uploader: "sora_1123", lang: "EN", pages: 128, rating: "4.6", time: "3h ago" },
        { id: "g2", letter: "S", mc: "mc-2", cat: "Manga", catColor: "#4c9a6b", title: "Spring Afternoon", uploader: "hana_momo", lang: "JP", pages: 96, rating: "4.8", time: "yesterday" },
        { id: "g3", letter: "C", mc: "mc-3", cat: "Artist CG", catColor: "#c05a4a", title: "City Sketchbook", uploader: "ink_studio", lang: "EN", pages: 240, rating: "4.2", time: "2d ago" },
        { id: "g4", letter: "H", mc: "mc-4", cat: "Game CG", catColor: "#8a6db8", title: "Harbor Lights", uploader: "night_pixel", lang: "JP", pages: 320, rating: "4.9", time: "3d ago" },
      ],
      downloads: [
        { letter: "N", mc: "mc-1", title: "Stardust at Night", sub: "128 pages · 82 downloaded", pct: 64, status: "doing", statusText: "Active" },
        { letter: "H", mc: "mc-4", title: "Harbor Lights", sub: "320 pages · 320 downloaded", pct: 100, status: "done", statusText: "Done" },
        { letter: "S", mc: "mc-2", title: "Spring Afternoon", sub: "96 pages · 40 downloaded", pct: 42, status: "paused", statusText: "Paused" },
      ],
      history: [
        { letter: "N", mc: "mc-1", title: "Stardust at Night", sub: "Read to page 45/128 · 3h ago" },
        { letter: "H", mc: "mc-4", title: "Harbor Lights", sub: "Read to page 12/320 · yesterday" },
        { letter: "C", mc: "mc-3", title: "City Sketchbook", sub: "Read to page 200/240 · 4d ago" },
      ],
      detail: { read: "Read", add: "Add to Download", back: "Back", tags: ["doujinshi", "original", "slice of life", "stars"] },
      reader: { title: "Reader", pages: "12 / 240" },
      favoritesNote: "No favorites yet",
      localBadge: "Local",
    },
  };

  const T = MOCK[lang];
  const state = { iphone: ["home"], ipad: ["home"], mac: ["home"] };

  const esc = (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  const galleryById = (id) => T.galleries.find((g) => g.id === id) || T.galleries[0];

  function galleryCardHTML(g) {
    return '<div class="m-card" data-gallery="' + g.id + '" data-title="' + esc(g.title) + '">' +
      '<span class="m-cover ' + g.mc + '" data-letter="' + g.letter + '"></span>' +
      '<div class="m-card-body">' +
        '<div class="m-title">' + esc(g.title) + '</div>' +
        '<div class="m-meta">' +
          '<span class="cat-badge" style="background:' + g.catColor + '">' + g.cat + '</span>' +
          '<span class="m-uploader">' + ICONS.person + esc(g.uploader) + '</span>' +
          '<span>' + g.lang + '</span>' +
          '<span>' + g.pages + (lang === "en" ? " pages" : " 页") + '</span>' +
          '<span class="m-rating">★ ' + g.rating + '</span>' +
          '<span class="m-time">' + g.time + '</span>' +
        '</div>' +
      '</div>' +
    '</div>';
  }

  function galleryPanelHTML(panelId) {
    let list = T.galleries;
    if (panelId === "subscriptions") list = T.galleries.slice(0, 2);
    if (panelId === "popular") list = T.galleries.slice(1, 3);
    if (panelId === "toplist") list = T.galleries.slice(2);
    return '<div class="gal-list">' + list.map(galleryCardHTML).join("") + '</div>';
  }

  function downloadsPanelHTML(isLocal) {
    return '<div>' + T.downloads.map((d) =>
      '<div class="d-row">' +
        '<span class="m-cover ' + d.mc + '" data-letter="' + d.letter + '"></span>' +
        '<div class="d-info">' +
          '<div class="d-title">' + esc(d.title) + (isLocal ? ' <span class="status done">' + T.localBadge + '</span>' : "") + '</div>' +
          '<div class="d-sub">' + d.sub + '</div>' +
          '<div class="progress"><i style="--p:' + d.pct + '%"></i></div>' +
        '</div>' +
        '<span class="status ' + d.status + '">' + d.statusText + '</span>' +
      '</div>'
    ).join("") + '</div>';
  }

  function historyPanelHTML() {
    return '<div>' + T.history.map((h) =>
      '<div class="d-row">' +
        '<span class="m-cover ' + h.mc + '" data-letter="' + h.letter + '"></span>' +
        '<div class="d-info">' +
          '<div class="d-title">' + esc(h.title) + '</div>' +
          '<div class="d-sub">' + h.sub + '</div>' +
        '</div>' +
        '<span class="status paused">' + ICONS.clock + '</span>' +
      '</div>'
    ).join("") + '</div>';
  }

  function favoritesPanelHTML() {
    return '<div class="gal-list">' + T.galleries.slice(2).map(galleryCardHTML).join("") + '</div>';
  }

  function settingsPanelHTML() {
    const rows = [
      { section: lang === "en" ? "Site" : "站点" },
      { label: lang === "en" ? "Gallery site" : "画廊站点", value: "E-Hentai", chev: true },
      { label: lang === "en" ? "Session" : "会话状态", value: lang === "en" ? "Guest" : "游客模式" },
      { section: lang === "en" ? "Browsing" : "浏览" },
      { label: lang === "en" ? "Japanese titles" : "显示日文标题", toggle: true, on: true },
      { label: lang === "en" ? "Tag translations" : "显示标签翻译", toggle: true, on: true },
      { label: lang === "en" ? "Detail cache" : "启用详情缓存", toggle: true, on: false },
      { section: lang === "en" ? "Login" : "登录" },
      { label: lang === "en" ? "Username & password" : "用户名&密码登录", chev: true },
      { label: lang === "en" ? "Web login" : "网页登录", chev: true },
      { label: lang === "en" ? "Cookie login" : "Cookie登录", chev: true },
      { section: lang === "en" ? "Migration / Backup" : "数据迁移/备份" },
      { label: lang === "en" ? "Export metadata (.ehgallery)" : "导出元数据(.ehgallery)", chev: true },
      { label: lang === "en" ? "Import archive (.eharchive)" : "导入归档(.eharchive)", chev: true },
      { section: "About" },
      { label: lang === "en" ? "Version" : "版本", value: "1.0.0" },
    ];
    return '<div class="s-list">' + rows.map((r) => {
      if (r.section) return '<div class="s-section">' + r.section + '</div>';
      return '<div class="s-row"><span>' + r.label + '</span>' +
        (r.toggle ? '<span class="toggle' + (r.on ? " on" : "") + '"></span>'
          : r.chev ? '<span class="s-chev">' + ICONS.forward + '</span>'
          : '<span class="s-val">' + (r.value || "") + '</span>') + '</div>';
    }).join("") + '</div>';
  }

  function detailPanelHTML(g) {
    return '<div class="detail-view">' +
      '<button class="detail-back" data-back type="button">' + ICONS.back + T.detail.back + '</button>' +
      '<div class="detail-hero">' +
        '<span class="d-cover ' + g.mc + '" data-letter="' + g.letter + '"></span>' +
        '<div class="d-info">' +
          '<h4>' + esc(g.title) + '</h4>' +
          '<div class="d-meta">' +
            '<span class="cat-badge" style="background:' + g.catColor + '">' + g.cat + '</span>' +
            '<span>' + esc(g.uploader) + '</span><span>' + g.lang + '</span>' +
            '<span>' + g.pages + (lang === "en" ? " pages" : " 页") + '</span>' +
            '<span class="m-rating">★ ' + g.rating + '</span>' +
          '</div>' +
          '<div class="d-actions">' +
            '<button class="m-btn primary" data-read type="button">' + ICONS.play + T.detail.read + '</button>' +
            '<button class="m-btn ghost" type="button">' + ICONS.plus + T.detail.add + '</button>' +
          '</div>' +
        '</div>' +
      '</div>' +
      '<div class="d-tags">' + T.detail.tags.map((t) => '<span class="d-tag">' + esc(t) + '</span>').join("") + '</div>' +
    '</div>';
  }

  function readerPanelHTML() {
    return '<div class="reader-view">' +
      '<div class="reader-top"><button class="detail-back" data-back type="button">' + ICONS.back + T.detail.back + '</button><span>' + T.reader.pages + '</span></div>' +
      '<div class="reader-pages"><div class="reader-page"></div><div class="reader-page"></div></div>' +
      '<div class="reader-bar"><span>◀</span><div class="progress"><i style="--p:5%"></i></div><span>▶</span></div>' +
    '</div>';
  }

  function sidebarHTML() {
    return '<div class="side">' + T.side.map((sec) =>
      (sec.label ? '<div class="side-label">' + sec.label + '</div>' : "") +
      sec.items.map((it) => '<button class="side-item" data-panel="' + it.id + '" type="button">' + ICONS[it.icon] + '<span>' + it.label + '</span></button>').join("")
    ).join("") + '</div>';
  }

  function statusBarHTML() {
    return '<div class="status-bar"><span>9:41</span><span class="status-icons"><span>▂▄▆</span><span>◠</span><span>▮▮▮</span></span></div>';
  }

  function phoneHTML() {
    return '<div class="phone"><div class="phone-screen">' +
      '<div class="phone-notch"></div>' +
      statusBarHTML() +
      '<div class="app-nav"><span class="nav-title" data-nav-title>首页</span></div>' +
      '<div class="phone-body">' +
        '<div class="search-field">' + ICONS.search + '<input type="text" placeholder="' + esc(T.search) + '" aria-label="' + esc(T.search) + '"></div>' +
        '<div class="panel-body"></div>' +
      '</div>' +
      '<div class="dock">' + T.dock.map((d) => '<button class="dock-item" data-panel="' + d.id + '" type="button">' + ICONS[d.icon] + '<span>' + d.label + '</span></button>').join("") + '</div>' +
    '</div></div>';
  }

  function splitHTML() {
    return sidebarHTML() +
      '<div class="app-detail">' +
        '<div class="detail-nav"><span class="nav-title" data-nav-title>首页</span>' +
        '<div class="search-field">' + ICONS.search + '<input type="text" placeholder="' + esc(T.search) + '" aria-label="' + esc(T.search) + '"></div></div>' +
        '<div class="panel-body"></div>' +
      '</div>';
  }

  function ipadHTML() {
    return '<div class="ipad"><div class="ipad-screen">' + splitHTML() + '</div></div>';
  }

  function macHTML() {
    return '<div class="mac">' +
      '<div class="mac-bar"><span class="dot"></span><span class="dot"></span><span class="dot"></span><span class="mac-title">EhViewer</span></div>' +
      '<div class="mac-screen">' + splitHTML() + '</div>' +
    '</div>';
  }

  function renderPanel(frame, device, panelId) {
    const navTitle = frame.querySelector("[data-nav-title]");
    const body = frame.querySelector(".panel-body");
    const search = frame.querySelector(".search-field");
    const isDetail = panelId.indexOf("detail-") === 0;
    const isReader = panelId === "reader";
    const panel = T.panels[panelId] || {};

    let title;
    let html = "";
    if (isDetail) {
      const g = galleryById(panelId.slice(7));
      title = g.title;
      html = detailPanelHTML(g);
    } else if (isReader) {
      title = T.reader.title;
      html = readerPanelHTML();
    } else {
      title = panel.title || "";
      if (panelId === "downloads" || panelId === "local") html = downloadsPanelHTML(panelId === "local");
      else if (panelId === "history") html = historyPanelHTML();
      else if (panelId === "favorites") html = favoritesPanelHTML();
      else if (panelId === "settings") html = settingsPanelHTML();
      else html = galleryPanelHTML(panelId);
    }
    if (navTitle) navTitle.textContent = title;
    if (search) search.style.display = isDetail || isReader ? "none" : "";
    body.innerHTML = html;
    frame.querySelectorAll(".dock-item, .side-item").forEach((el) => {
      el.classList.toggle("is-active", !isDetail && !isReader && el.dataset.panel === panelId);
    });
  }

  function frameOf(device) {
    return showcase.querySelector('[data-device-panel="' + device + '"]');
  }

  function pushPanel(device, panelId) {
    state[device].push(panelId);
    renderPanel(frameOf(device), device, panelId);
  }

  function popPanel(device) {
    if (state[device].length > 1) state[device].pop();
    renderPanel(frameOf(device), device, state[device][state[device].length - 1]);
  }

  const frames = [...showcase.querySelectorAll(".device-frame")];
  const tabs = [...showcase.querySelectorAll(".device-tab")];

  frames.forEach((frame) => {
    const device = frame.dataset.devicePanel;
    frame.innerHTML = device === "iphone" ? phoneHTML() : device === "mac" ? macHTML() : ipadHTML();
    renderPanel(frame, device, "home");

    const input = frame.querySelector(".search-field input");
    input?.addEventListener("input", () => {
      const q = input.value.trim().toLocaleLowerCase();
      frame.querySelectorAll(".m-card").forEach((card) => {
        const title = (card.dataset.title || "").toLocaleLowerCase();
        card.style.display = !q || title.includes(q) ? "" : "none";
      });
    });

    frame.addEventListener("click", (event) => {
      const gallery = event.target.closest("[data-gallery]");
      if (gallery) { pushPanel(device, "detail-" + gallery.dataset.gallery); return; }
      const readBtn = event.target.closest("[data-read]");
      if (readBtn) { pushPanel(device, "reader"); return; }
      const backBtn = event.target.closest("[data-back]");
      if (backBtn) { popPanel(device); return; }
      const toggle = event.target.closest(".toggle");
      if (toggle) { toggle.classList.toggle("on"); return; }
      const panelBtn = event.target.closest("[data-panel]");
      if (panelBtn) { pushPanel(device, panelBtn.dataset.panel); return; }
    });
  });

  tabs.forEach((tab) => {
    tab.addEventListener("click", () => {
      tabs.forEach((t) => t.classList.toggle("is-active", t === tab));
      frames.forEach((f) => {
        const on = f.dataset.devicePanel === tab.dataset.device;
        f.classList.toggle("is-active", on);
        f.hidden = !on;
      });
    });
  });
}
  /* ============================================================
     Docs page: sidebar, TOC, search, page navigation
     ============================================================ */
  const article = document.getElementById("doc-content");
  if (!article) return;

  const sidebar = document.getElementById("sidebar");
  const sidebarToggle = document.getElementById("sidebar-toggle");
  const sidebarBackdrop = document.getElementById("sidebar-backdrop");
  const toc = document.getElementById("sidebar-toc");
  const searchInput = document.getElementById("doc-search");
  const searchPanel = document.getElementById("search-panel");
  const searchResults = document.getElementById("search-results");
  const searchCount = document.getElementById("search-count");
  const pageNav = document.getElementById("page-nav");
  const isEnglish = root.lang.toLowerCase().startsWith("en");

  const ui = {
    previous: isEnglish ? "Previous section" : "上一节",
    next: isEnglish ? "Next section" : "下一节",
    overview: isEnglish ? "Overview" : "概览",
    noResults: isEnglish ? "No matching content found." : "没有找到匹配内容。",
    resultCount: (count) => (isEnglish ? count + " result" + (count === 1 ? "" : "s") : count + " 个结果"),
  };

  const headings = [...article.querySelectorAll("h2, h3")];
  const sections = [...article.querySelectorAll("h2")];

  function createToc() {
    const list = document.createElement("ul");
    let currentSublist = null;

    headings.forEach((heading) => {
      if (!heading.id) return;
      const item = document.createElement("li");
      const link = document.createElement("a");
      link.href = "#" + heading.id;
      link.textContent = heading.textContent;
      link.dataset.headingId = heading.id;
      item.append(link);

      if (heading.tagName === "H2") {
        list.append(item);
        currentSublist = document.createElement("ul");
        item.append(currentSublist);
      } else if (currentSublist) {
        currentSublist.append(item);
      } else {
        list.append(item);
      }
    });

    toc.replaceChildren(list);
  }

  function sectionText(section) {
    const next = sections[sections.indexOf(section) + 1];
    const nodes = [];
    let node = section.nextElementSibling;
    while (node && node !== next) {
      nodes.push(node);
      node = node.nextElementSibling;
    }
    return [section, ...nodes].map((item) => item.textContent).join(" ").replace(/\s+/g, " ").trim();
  }

  function searchRecords() {
    const records = sections.map((section) => ({
      anchor: section.id,
      title: section.textContent,
      text: sectionText(section),
    }));
    const firstSection = sections[0];
    const firstHeading = article.querySelector("h1");
    if (!firstHeading || !firstSection) return records;

    const introNodes = [];
    let node = firstHeading.nextElementSibling;
    while (node && node !== firstSection) {
      introNodes.push(node);
      node = node.nextElementSibling;
    }
    const introText = [firstHeading, ...introNodes].map((item) => item.textContent).join(" ").replace(/\s+/g, " ").trim();
    if (introText) records.unshift({ anchor: firstHeading.id, title: ui.overview, text: introText });
    return records;
  }

  function renderSearch(query) {
    const normalized = query.trim().toLocaleLowerCase();
    if (!normalized) {
      searchPanel.hidden = true;
      searchResults.replaceChildren();
      searchCount.textContent = "";
      return;
    }

    const matches = searchRecords().filter((entry) => entry.text.toLocaleLowerCase().includes(normalized));
    searchPanel.hidden = false;
    searchCount.textContent = ui.resultCount(matches.length);
    searchResults.replaceChildren();

    if (matches.length === 0) {
      const empty = document.createElement("p");
      empty.className = "search-empty";
      empty.textContent = ui.noResults;
      searchResults.append(empty);
      return;
    }

    matches.forEach(({ anchor, title, text }) => {
      const link = document.createElement("a");
      link.className = "search-result";
      link.href = "#" + anchor;
      const titleNode = document.createElement("strong");
      titleNode.textContent = title;
      const snippet = document.createElement("span");
      const index = text.toLocaleLowerCase().indexOf(normalized);
      const start = Math.max(0, index - 48);
      snippet.textContent = (start > 0 ? "…" : "") + text.slice(start, start + 150) + (start + 150 < text.length ? "…" : "");
      link.append(titleNode, snippet);
      searchResults.append(link);
    });
  }

  function createPageNavigation() {
    if (sections.length < 2) return;

    const updateNavigation = () => {
      const scrollPosition = window.scrollY + 150;
      let index = 0;
      sections.forEach((section, candidate) => {
        if (section.offsetTop <= scrollPosition) index = candidate;
      });
      const links = [];
      if (index > 0) {
        const link = document.createElement("a");
        link.href = "#" + sections[index - 1].id;
        link.innerHTML = "<small>" + ui.previous + "</small><span>" + sections[index - 1].textContent + "</span>";
        links.push(link);
      } else {
        links.push(document.createElement("span"));
      }
      if (index < sections.length - 1) {
        const link = document.createElement("a");
        link.href = "#" + sections[index + 1].id;
        link.innerHTML = "<small>" + ui.next + "</small><span>" + sections[index + 1].textContent + "</span>";
        links.push(link);
      } else {
        links.push(document.createElement("span"));
      }
      pageNav.replaceChildren(...links);
    };

    window.addEventListener("scroll", updateNavigation, { passive: true });
    updateNavigation();
  }

  function closeSidebar() {
    document.body.classList.remove("sidebar-open");
    sidebarToggle?.setAttribute("aria-expanded", "false");
    if (sidebarBackdrop) sidebarBackdrop.hidden = true;
  }

  function openSidebar() {
    document.body.classList.add("sidebar-open");
    sidebarToggle?.setAttribute("aria-expanded", "true");
    if (sidebarBackdrop) sidebarBackdrop.hidden = false;
  }

  createToc();
  createPageNavigation();

  searchInput?.addEventListener("input", () => renderSearch(searchInput.value));
  sidebarToggle?.addEventListener("click", () => {
    if (document.body.classList.contains("sidebar-open")) closeSidebar();
    else openSidebar();
  });
  sidebarBackdrop?.addEventListener("click", closeSidebar);
  toc?.addEventListener("click", (event) => {
    if (event.target instanceof HTMLAnchorElement) closeSidebar();
  });
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") closeSidebar();
  });

  if ("IntersectionObserver" in window) {
    const links = [...toc.querySelectorAll("a[data-heading-id]")];
    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          links.forEach((link) => link.classList.toggle("active", link.dataset.headingId === entry.target.id));
        });
      },
      { rootMargin: "-100px 0px -70% 0px", threshold: 0 }
    );
    headings.forEach((heading) => observer.observe(heading));
  }


})();
