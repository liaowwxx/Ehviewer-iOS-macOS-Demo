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
      const hot = event.target.closest("a, button, summary, input, [data-tilt]");
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
   (layout mirrors the SwiftUI app: TabView / NavigationSplitView,
   BrowseView cards, DownloadsView cards, SettingsView form,
   GalleryDetailView header + info card + previews, ReaderView
   progress control)
   ============================================================ */
const showcase = document.getElementById("device-showcase");
if (showcase) {
  const lang = showcase.dataset.lang === "en" ? "en" : "zh";

  const ICONS = {
    search: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="11" cy="11" r="6.5"/><path d="m16 16 4.5 4.5"/></svg>',
    person: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="8.5" r="3.8"/><path d="M5 20c1.2-3.2 3.8-5 7-5s5.8 1.8 7 5"/></svg>',
    list: '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="4.5" width="18" height="15" rx="3"/><path d="M7.5 9h9M7.5 12.5h9M7.5 16h5"/></svg>',
    download: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="8.5"/><path d="M12 8v6.5"/><path d="m9.5 12.5 2.5 2.5 2.5-2.5"/><path d="M8 18h8"/></svg>',
    books: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 4.5A2.5 2.5 0 0 1 7.5 2H20v16.5H7.5A2.5 2.5 0 0 0 5 21.5Z"/><path d="M5 4.5v15A2.5 2.5 0 0 1 7.5 17H20"/></svg>',
    clock: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/></svg>',
    gear: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="3.2"/><path d="M12 2.8v3M12 18.2v3M21.2 12h-3M5.8 12h-3M18.5 5.5l-2.1 2.1M7.6 16.4l-2.1 2.1M18.5 18.5l-2.1-2.1M7.6 7.6 5.5 5.5"/></svg>',
    house: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 11 12 4l8 7"/><path d="M6 9.5V20h12V9.5"/></svg>',
    tag: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 4h7l9 9-7 7-9-9Z"/><circle cx="8.5" cy="8.5" r="1.4"/></svg>',
    chart: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 20V4"/><path d="m4 16 5-5 3.5 3L20 6.5"/><path d="M15 6.5h5v5"/></svg>',
    listNumber: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M9 6h11M9 12h11M9 18h11"/><path d="M4.2 5.2H3.1V4.3c.8-.5 1.6-.7 2.3-.6.7.1 1 .5 1 1 0 .6-.4 1-1 1.5l-1.6 1.5h2.6"/><path d="M4.6 12.1h-1l1.4-.9c.8-.5 1.1-1 1.1-1.5 0-.5-.3-.8-.9-.8-.5 0-.9.3-1.2.7"/><path d="M5 16.6c0-.7-.6-1.2-1.4-1.2-.5 0-1 .2-1.1.6l-.5-.4c.3-.6.9-1 1.7-1 1 0 1.8.5 1.8 1.4 0 .5-.3 1-1 1.3l-.8.4h1.8"/></svg>',
    heart: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 20s-7-4.6-9-9c-1.3-3 .8-6.5 4.2-6.5 2 0 3.6 1 4.8 2.8C13.2 5.5 14.8 4.5 16.8 4.5c3.4 0 5.5 3.5 4.2 6.5-2 4.4-9 9-9 9Z"/></svg>',
    back: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M14.5 5 7.5 12l7 7"/></svg>',
    play: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m9 6 9 6-9 6Z"/></svg>',
    plus: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>',
    forward: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m9.5 5 7 7-7 7"/></svg>',
    doc: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 3h7l4 4v14H7Z"/><path d="M14 3v4h4"/><path d="M9.5 12h5M9.5 15.5h5"/></svg>',
    star: '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" stroke="none" d="M12 3.5 14.6 9l6 .8-4.4 4.2 1.1 6-5.3-2.9-5.3 2.9 1.1-6L3.4 9.8l6-.8Z"/></svg>',
    slider: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 7h9M17 7h3M4 12h3M11 12h9M4 17h6M14 17h6"/><circle cx="15" cy="7" r="1.6"/><circle cx="8" cy="12" r="1.6"/><circle cx="12" cy="17" r="1.6"/></svg>',
    chevronUp: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m6 14 6-6 6 6"/></svg>',
    ellipsis: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="5.5" cy="12" r="1.3"/><circle cx="12" cy="12" r="1.3"/><circle cx="18.5" cy="12" r="1.3"/></svg>',
    checkmark: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m5 12 4 4L19 6"/></svg>',
    xmark: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg>',
    photo: '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="4" y="5" width="16" height="14" rx="2"/><circle cx="9" cy="10" r="1.5"/><path d="m5.5 17 3.5-3.5 3 3 3-3 3.5 3.5"/></svg>',
    trash: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 7h16M9 7V4h6v3M6.5 7l1 13h9l1-13"/><path d="M10 11v5M14 11v5"/></svg>',
    info: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="8.5"/><path d="M12 11v5"/><circle cx="12" cy="8" r=".4"/></svg>',
    arrowCircle: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="8.5"/><path d="M12 16.5V7.5"/><path d="m8.5 11 3.5-3.5L15.5 11"/></svg>',
    key: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="8" cy="15" r="3.5"/><path d="m10.5 12.5 9-9M16 7l3 3M13.5 9.5l2.5 2.5"/></svg>',
    safari: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="8.5"/><path d="m15.5 8.5-2 5-5 2 2-5Z"/></svg>',
    book: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 5.5A2.5 2.5 0 0 1 6.5 3H20v16.5H6.5A2.5 2.5 0 0 0 4 22Z"/><path d="M4 5.5v14A2.5 2.5 0 0 1 6.5 17H20"/></svg>',
    sidebar: '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3.5" y="4" width="17" height="16" rx="2.5"/><path d="M9.5 4v16M13 9h4M13 13h4"/></svg>',
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
          { id: "toplist", label: "排行", icon: "listNumber" },
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
      search: "搜索示例内容",
      panels: {
        home: { title: "浏览" }, subscriptions: { title: "订阅" }, popular: { title: "热门" },
        toplist: { title: "排行" }, favorites: { title: "收藏" },
        downloads: { title: "下载" }, local: { title: "本地" },
        history: { title: "历史" }, settings: { title: "设置" },
      },
      galleries: [
        { id: "g1", letter: "示", mc: "mc-1", cat: "示例", catColor: "#f44336", title: "示例 01", uploader: "example", lang: "—", pages: "—", rating: "—", ratingCount: "—", time: "—", fav: false },
        { id: "g2", letter: "示", mc: "mc-2", cat: "示例", catColor: "#ff9800", title: "示例 02", uploader: "example", lang: "—", pages: "—", rating: "—", ratingCount: "—", time: "—", fav: true },
        { id: "g3", letter: "示", mc: "mc-3", cat: "示例", catColor: "#fbc02d", title: "示例 03", uploader: "example", lang: "—", pages: "—", rating: "—", ratingCount: "—", time: "—", fav: false },
        { id: "g4", letter: "示", mc: "mc-4", cat: "示例", catColor: "#4caf50", title: "示例 04", uploader: "example", lang: "—", pages: "—", rating: "—", ratingCount: "—", time: "—", fav: false },
      ],
      downloads: [
        { letter: "示", mc: "mc-1", title: "示例 01", sub: "示例进度", pct: 64, status: "doing", statusText: "进行中", tags: ["example"] },
        { letter: "示", mc: "mc-4", title: "示例 04", sub: "示例进度", pct: 100, status: "done", statusText: "已完成", tags: ["example"] },
        { letter: "示", mc: "mc-2", title: "示例 02", sub: "示例进度", pct: 42, status: "paused", statusText: "已暂停", tags: ["example"] },
      ],
      history: [
        { letter: "示", mc: "mc-1", title: "示例 01", sub: "示例阅读进度", time: "—" },
        { letter: "示", mc: "mc-4", title: "示例 04", sub: "示例阅读进度", time: "—" },
        { letter: "示", mc: "mc-3", title: "示例 03", sub: "示例阅读进度", time: "—" },
      ],
      detail: {
        read: "阅读", add: "加入下载", back: "画廊",
        tagGroups: [
          { group: "示例", items: ["example"] },
        ],
        info: {
          languageLabel: "语言", pagesLabel: "页数", sizeLabel: "大小",
          favoritesLabel: "收藏次数", postedLabel: "发布于",
          language: "—", size: "—", favorites: "—", posted: "—"
        },
        description: "示例内容。",
        previews: "预览",
      },
      reader: { title: "阅读", pageLabel: "第 13/240 页", pageHint: "第 13 页" },
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
          { id: "toplist", label: "Toplist", icon: "listNumber" },
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
      search: "Search examples",
      panels: {
        home: { title: "Browse" }, subscriptions: { title: "Subscriptions" }, popular: { title: "Popular" },
        toplist: { title: "Toplist" }, favorites: { title: "Favorites" },
        downloads: { title: "Downloads" }, local: { title: "Local" },
        history: { title: "History" }, settings: { title: "Settings" },
      },
      galleries: [
        { id: "g1", letter: "E", mc: "mc-1", cat: "Example", catColor: "#f44336", title: "Example 01", uploader: "example", lang: "—", pages: "—", rating: "—", ratingCount: "—", time: "—", fav: false },
        { id: "g2", letter: "E", mc: "mc-2", cat: "Example", catColor: "#ff9800", title: "Example 02", uploader: "example", lang: "—", pages: "—", rating: "—", ratingCount: "—", time: "—", fav: true },
        { id: "g3", letter: "E", mc: "mc-3", cat: "Example", catColor: "#fbc02d", title: "Example 03", uploader: "example", lang: "—", pages: "—", rating: "—", ratingCount: "—", time: "—", fav: false },
        { id: "g4", letter: "E", mc: "mc-4", cat: "Example", catColor: "#4caf50", title: "Example 04", uploader: "example", lang: "—", pages: "—", rating: "—", ratingCount: "—", time: "—", fav: false },
      ],
      downloads: [
        { letter: "E", mc: "mc-1", title: "Example 01", sub: "Example progress", pct: 64, status: "doing", statusText: "In progress", tags: ["example"] },
        { letter: "E", mc: "mc-4", title: "Example 04", sub: "Example progress", pct: 100, status: "done", statusText: "Complete", tags: ["example"] },
        { letter: "E", mc: "mc-2", title: "Example 02", sub: "Example progress", pct: 42, status: "paused", statusText: "Paused", tags: ["example"] },
      ],
      history: [
        { letter: "E", mc: "mc-1", title: "Example 01", sub: "Example reading progress", time: "—" },
        { letter: "E", mc: "mc-4", title: "Example 04", sub: "Example reading progress", time: "—" },
        { letter: "E", mc: "mc-3", title: "Example 03", sub: "Example reading progress", time: "—" },
      ],
      detail: {
        read: "Read", add: "Add to Download", back: "Gallery",
        tagGroups: [
          { group: "Example", items: ["example"] },
        ],
        info: {
          languageLabel: "Language", pagesLabel: "Pages", sizeLabel: "Size",
          favoritesLabel: "Favorites", postedLabel: "Posted",
          language: "—", size: "—", favorites: "—", posted: "—"
        },
        description: "Example content.",
        previews: "Previews",
      },
      reader: { title: "Reader", pageLabel: "Page 13/240", pageHint: "Page 13" },
      favoritesNote: "No favorites yet",
      localBadge: "Local",
    },
  };

  const T = MOCK[lang];
  const state = { iphone: ["home"], ipad: ["home"], mac: ["home"] };

  const esc = (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  const galleryById = (id) => T.galleries.find((g) => g.id === id) || T.galleries[0];

  function coverArtwork(index) {
    const palette = [
      ["#ddc4bc", "#765b83", "#f7e1c7"],
      ["#bed6d2", "#3b6c75", "#ecbe84"],
      ["#d7c8e6", "#5d4f82", "#f0db9d"],
      ["#c8d3a2", "#4f7763", "#e9a1a0"],
    ][index % 4];
    const canvas = document.createElement("canvas");
    canvas.width = 180;
    canvas.height = 260;
    const ctx = canvas.getContext("2d");
    const gradient = ctx.createLinearGradient(0, 0, 180, 260);
    gradient.addColorStop(0, palette[0]);
    gradient.addColorStop(1, palette[1]);
    ctx.fillStyle = gradient;
    ctx.fillRect(0, 0, 180, 260);
    ctx.globalAlpha = .46;
    ctx.fillStyle = palette[2];
    ctx.beginPath();
    ctx.arc(140, 54, 63, 0, Math.PI * 2);
    ctx.fill();
    ctx.globalAlpha = .8;
    ctx.fillStyle = "#fff";
    ctx.fillRect(14, 18, 82, 6);
    ctx.fillRect(14, 31, 55, 3);
    ctx.globalAlpha = .52;
    ctx.strokeStyle = "#fff";
    ctx.lineWidth = 5;
    ctx.beginPath();
    ctx.moveTo(10, 205);
    ctx.bezierCurveTo(52, 156, 112, 241, 174, 168);
    ctx.stroke();
    ctx.globalAlpha = .96;
    ctx.fillStyle = "rgba(255,255,255,.84)";
    ctx.beginPath();
    ctx.arc(91, 126, 31, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = palette[1];
    ctx.beginPath();
    ctx.arc(91, 113, 14, 0, Math.PI * 2);
    ctx.fill();
    ctx.beginPath();
    ctx.ellipse(91, 163, 29, 36, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.globalAlpha = .68;
    ctx.fillStyle = "#fff";
    ctx.font = "700 12px system-ui";
    ctx.fillText("EXAMPLE " + String(index + 1).padStart(2, "0"), 14, 244);
    return canvas.toDataURL("image/png");
  }

  function applyPhoneArtwork(frame) {
    frame.querySelectorAll(".m-cover, .dl-cover, .d-cover, .preview-cell").forEach((cover, index) => {
      const artIndex = Number((cover.className.match(/mc-(\d)/) || [])[1] || index + 1) - 1;
      cover.style.setProperty("--cover-art", 'url("' + coverArtwork(artIndex) + '")');
      cover.classList.add("has-art");
    });
  }

  function galleryCardHTML(g) {
    return '<div class="m-card" data-gallery="' + g.id + '" data-title="' + esc(g.title) + '">' +
      '<span class="m-cover ' + g.mc + '" data-letter="' + g.letter + '"></span>' +
      '<div class="m-card-body">' +
        '<div class="m-title">' + esc(g.title) + '</div>' +
        '<div class="m-uploader">' + ICONS.person + esc(g.uploader) + '</div>' +
        '<div class="m-meta">' +
          '<span class="cat-badge" style="background:' + g.catColor + '">' + esc(g.cat).toUpperCase() + '</span>' +
          '<span class="m-lang">' + g.lang + '</span>' +
          '<span class="m-pages">' + g.pages + (lang === "en" ? " pages" : " 页") + '</span>' +
          (g.fav ? '<span class="m-fav">' + ICONS.heart + '</span>' : "") +
          '<span class="m-spacer"></span>' +
          '<span class="m-time">' + g.time + '</span>' +
          '<span class="m-rating">' + ICONS.star + g.rating + '</span>' +
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
    return '<div class="dl-list">' + T.downloads.map((d) =>
      '<div class="d-row">' +
        '<span class="dl-cover ' + d.mc + '" data-letter="' + d.letter + '"></span>' +
        '<div class="d-info">' +
          '<div class="d-title">' + esc(d.title) + (isLocal ? ' <span class="status done">' + T.localBadge + '</span>' : "") + '</div>' +
          (d.tags && d.tags.length
            ? '<div class="d-tags">' + d.tags.map((t) => '<span class="d-tag">' + esc(t) + '</span>').join("") + '</div>'
            : "") +
          (d.status === "done"
            ? '<div class="d-status"><span class="d-status-done">' + ICONS.checkmark + esc(d.statusText) + '</span><span class="d-count">' + esc(d.sub) + '</span></div>'
            : '<div class="progress"><i style="--p:' + d.pct + '%"></i></div>' +
              '<div class="d-status"><span>' + esc(d.statusText) + '</span><span class="d-count">' + esc(d.sub) + '</span></div>') +
        '</div>' +
      '</div>'
    ).join("") + '</div>';
  }

  function historyPanelHTML(isPhone) {
    const entries = '<div class="dl-list">' + T.history.map((h) =>
      '<div class="d-row has-time">' +
        '<span class="dl-cover ' + h.mc + '" data-letter="' + h.letter + '"></span>' +
        '<div class="d-info">' +
          '<div class="d-title">' + esc(h.title) + '</div>' +
          '<div class="d-sub">' + esc(h.sub) + '</div>' +
        '</div>' +
        '<span class="h-time">' + h.time + '</span>' +
      '</div>'
    ).join("") + '</div>';
    if (!isPhone) return entries;
    return phoneSegmentHTML("history") + '<p class="phone-list-label">' + (lang === "en" ? "Recently read" : "最近阅读") + '</p>' + entries;
  }

  function phoneSegmentHTML(active) {
    const labels = lang === "en" ? { history: "History", favorites: "Favorites" } : { history: "历史", favorites: "收藏" };
    return '<div class="phone-segment" role="tablist">' +
      ["history", "favorites"].map((id) => '<button class="' + (id === active ? "is-active" : "") + '" data-panel="' + id + '" type="button">' + labels[id] + '</button>').join("") +
    '</div>';
  }

  function favoritesPanelHTML() {
    const saved = T.galleries.slice(2);
    return '<div class="gal-list">' + saved.map(galleryCardHTML).join("") + '</div>';
  }

  function settingsPanelHTML(isPhone) {
    const isEn = lang === "en";
    const rows = [
      { section: isEn ? "Site" : "站点" },
      { label: isEn ? "Gallery site" : "画廊站点", value: "Example", icon: "forward" },
      { label: isEn ? "Session" : "会话状态", value: isEn ? "Guest" : "游客模式", icon: "person" },
      { section: isEn ? "Browsing" : "浏览" },
      { label: isEn ? "Japanese titles" : "显示日文标题", toggle: true, on: true },
      { label: isEn ? "Tag translations" : "显示标签翻译", toggle: true, on: true },
      { label: isEn ? "Detail cache" : "启用详情缓存", toggle: true, on: false },
      { label: isEn ? "Cache size" : "详情缓存占用", value: "—" },
      { label: isEn ? "Clear detail cache" : "清除详情缓存", destructive: true, icon: "trash" },
      { section: isEn ? "Login" : "登录" },
      { label: isEn ? "Username & password" : "用户名&密码登录", icon: "person" },
      { label: isEn ? "Web login" : "网页登录", icon: "safari" },
      { label: isEn ? "Cookie login" : "Cookie登录", icon: "key" },
      { label: isEn ? "Clear cookies" : "清除Cookie", destructive: true, icon: "xmark" },
      { section: "About" },
      { label: isEn ? "Version" : "版本", value: "Example" },
      { section: isEn ? "Help" : "帮助" },
      { label: isEn ? "User guide" : "使用说明", icon: "book" },
      { section: isEn ? "Migration / Backup" : "数据迁移/备份" },
      { label: isEn ? "Update downloaded gallery info" : "更新已下载画廊信息", icon: "arrowCircle" },
      { label: isEn ? "Import metadata (.ehgallery)" : "导入元数据(.ehgallery)", icon: "download" },
      { label: isEn ? "Import archive (.eharchive)" : "导入归档(.eharchive)", icon: "download" },
      { label: isEn ? "Export metadata (.ehgallery)" : "导出元数据(.ehgallery)", icon: "forward" },
      { label: isEn ? "Export archive (.eharchive)" : "导出归档(.eharchive)", icon: "forward" },
    ];
    const rowHTML = (r) => {
      const icon = r.icon ? '<span class="s-icon">' + ICONS[r.icon] + '</span>' : "";
      const value = r.value != null
        ? '<span class="s-val">' + esc(r.value) + '</span>'
        : r.toggle
          ? '<span class="toggle' + (r.on ? " on" : "") + '"></span>'
          : '<span class="s-chev' + (r.destructive ? " destructive" : "") + '">' + (r.icon ? ICONS[r.icon] : ICONS.forward) + '</span>';
      return '<div class="s-row"><span>' + icon + esc(r.label) + '</span>' + value + '</div>';
    };
    if (!isPhone) return '<div class="s-list">' + rows.map((r) => r.section ? '<div class="s-section">' + r.section + '</div>' : rowHTML(r)).join("") + '</div>';
    const groups = [];
    rows.forEach((row) => {
      if (row.section) groups.push({ title: row.section, rows: [] });
      else groups[groups.length - 1].rows.push(row);
    });
    return '<div class="s-list">' + groups.map((group) =>
      '<section class="s-group"><div class="s-section">' + group.title + '</div><div class="s-group-rows">' + group.rows.map(rowHTML).join("") + '</div></section>'
    ).join("") + '</div>';
  }

  function detailPanelHTML(g) {
    const info = T.detail.info;
    const infoCell = (label, value) =>
      '<div class="info-cell"><span class="info-label">' + label + '</span><span class="info-value">' + value + '</span></div>';
    return '<div class="detail-view">' +
      '<button class="detail-back" data-back type="button">' + ICONS.back + T.detail.back + '</button>' +
      '<div class="detail-header">' +
        '<span class="d-cover ' + g.mc + '" data-letter="' + g.letter + '"></span>' +
        '<div class="d-info">' +
          '<h4>' + esc(g.title) + '</h4>' +
          '<div class="d-uploader">' + ICONS.person + esc(g.uploader) + '</div>' +
          '<span class="cat-badge" style="background:' + g.catColor + '">' + esc(g.cat).toUpperCase() + '</span>' +
          '<div class="d-meta2">' +
            '<span>' + ICONS.doc + g.pages + (lang === "en" ? " pages" : " 页") + '</span>' +
            '<span>' + ICONS.star + g.rating + '</span>' +
            '<span>' + g.ratingCount + (lang === "en" ? " ratings" : " 人评分") + '</span>' +
          '</div>' +
        '</div>' +
      '</div>' +
      '<div class="info-card">' +
        '<div class="info-row">' +
          infoCell(info.languageLabel, info.language) +
          '<span class="info-divider-v"></span>' +
          infoCell(info.pagesLabel, g.pages + (lang === "en" ? " pages" : " 页")) +
          '<span class="info-divider-v"></span>' +
          infoCell(info.sizeLabel, info.size) +
        '</div>' +
        '<div class="info-divider-h"></div>' +
        '<div class="info-row">' +
          infoCell(info.favoritesLabel, info.favorites) +
          '<span class="info-divider-v"></span>' +
          infoCell(info.postedLabel, info.posted) +
        '</div>' +
      '</div>' +
      '<div class="d-actions">' +
        '<button class="m-btn primary" data-read type="button">' + ICONS.play + T.detail.read + '</button>' +
        '<button class="m-btn ghost" data-download-toggle type="button">' + ICONS.plus + T.detail.add + '</button>' +
        '<button class="m-btn ghost" data-favorite type="button">' + ICONS.heart + (lang === "en" ? "Favorite" : "收藏") + '</button>' +
      '</div>' +
      '<div class="tag-groups">' + T.detail.tagGroups.map((grp) =>
        '<div class="tag-group"><span class="tag-group-title">' + esc(grp.group) + '</span><div class="tag-chips">' +
        grp.items.map((t) => '<span class="tag-chip">' + esc(t) + '</span>').join("") +
        '</div></div>'
      ).join("") + '</div>' +
      '<div class="d-desc">' + esc(T.detail.description) + '</div>' +
      '<div class="d-previews">' +
        '<div class="d-previews-title">' + T.detail.previews + '</div>' +
        '<div class="preview-grid">' +
          Array.from({ length: Math.min(12, Number(g.pages) || 6) }).map((_, i) =>
            '<span class="preview-cell ' + g.mc + '"><i>' + (i + 1) + '</i></span>'
          ).join("") +
        '</div>' +
      '</div>' +
    '</div>';
  }

  function readerPanelHTML() {
    return '<div class="reader-view">' +
      '<button class="reader-page" data-reader-controls type="button"><span>' + T.reader.pageHint + '</span><small>' + (lang === "en" ? "Tap to hide controls" : "轻点隐藏控件") + '</small></button>' +
      '<div class="reader-progress">' +
        '<span class="rp-page">' + T.reader.pageLabel + '</span>' +
        '<input class="rp-slider" type="range" min="1" max="240" value="13" aria-label="' + (lang === "en" ? "Reading progress" : "阅读进度") + '">' +
        '<button class="rp-preview" data-reader-preview type="button" aria-label="' + (lang === "en" ? "Show previews" : "展开预览") + '">' + ICONS.chevronUp + '</button>' +
      '</div>' +
    '</div>';
  }

  function appMenuHTML() {
    const actions = lang === "en"
      ? [["arrowCircle", "Refresh"], ["person", "Account"], ["gear", "Settings"]]
      : [["arrowCircle", "刷新"], ["person", "账户"], ["gear", "设置"]];
    return '<div class="app-more-menu" data-app-more-menu>' +
      actions.map((item) => '<button type="button" data-app-menu-action="' + item[1] + '">' + ICONS[item[0]] + '<span>' + item[1] + '</span></button>').join("") +
    '</div>';
  }

  function sidebarHTML() {
    return '<div class="side">' +
      '<div class="side-header"><span class="window-controls" aria-hidden="true"><i></i><i></i><i></i></span><span class="side-app-icon">' + ICONS.books + '</span><span class="side-app-name">EhViewer</span><button class="side-collapse-toggle" data-split-sidebar-toggle type="button" aria-label="' + (lang === "en" ? "Collapse sidebar" : "收起侧边栏") + '" aria-expanded="true">' + ICONS.sidebar + '</button></div>' +
      T.side.map((sec) =>
        (sec.label ? '<div class="side-label">' + sec.label + '</div>' : "") +
        sec.items.map((it) => '<button class="side-item" data-panel="' + it.id + '" type="button">' + ICONS[it.icon] + '<span>' + it.label + '</span></button>').join("")
      ).join("") + '</div>';
  }

  function statusBarHTML() {
    return '<div class="status-bar" aria-hidden="true"></div>';
  }

  function phoneHTML() {
    return '<div class="phone"><div class="phone-screen">' +
      '<div class="phone-notch"></div>' +
      statusBarHTML() +
      '<div class="phone-body">' +
        '<div class="app-nav"><span class="nav-title" data-nav-title>浏览</span><button class="nav-more" data-app-menu type="button" aria-label="更多选项">' + ICONS.ellipsis + '</button></div>' +
        '<div class="search-field">' + ICONS.search + '<input type="text" placeholder="' + esc(T.search) + '" aria-label="' + esc(T.search) + '"></div>' +
        '<div class="panel-body"></div>' +
      '</div>' +
      '<div class="dock">' + T.dock.map((d) => '<button class="dock-item" data-panel="' + d.id + '" type="button">' + ICONS[d.icon] + '<span>' + d.label + '</span></button>').join("") + '</div>' +
    '</div></div>';
  }

  function splitHTML() {
    return sidebarHTML() +
      '<div class="app-detail">' +
        '<div class="detail-nav"><button class="split-sidebar-toggle" data-split-sidebar-toggle type="button" aria-label="' + (lang === "en" ? "Toggle sidebar" : "切换侧边栏") + '" aria-expanded="true">' + ICONS.sidebar + '</button><span class="nav-title" data-nav-title>浏览</span>' +
        '<div class="search-field">' + ICONS.search + '<input type="text" placeholder="' + esc(T.search) + '" aria-label="' + esc(T.search) + '"></div>' +
        '<button class="nav-more" data-app-menu type="button" aria-label="更多选项">' + ICONS.ellipsis + '</button></div>' +
        '<div class="panel-body"></div>' +
      '</div>';
  }

  function ipadHTML() {
    return '<div class="ipad"><div class="ipad-screen">' + splitHTML() + '</div></div>';
  }

  function macHTML() {
    return '<div class="mac"><div class="mac-screen">' + splitHTML() + '</div></div>';
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
      else if (panelId === "history") html = historyPanelHTML(device === "iphone");
      else if (panelId === "favorites") html = favoritesPanelHTML();
      else if (panelId === "settings") html = settingsPanelHTML(true);
      else html = galleryPanelHTML(panelId);
    }
    if (navTitle) navTitle.textContent = title;
    if (search) search.style.display = isDetail || isReader || (device === "ipad" && panelId === "settings") ? "none" : "";
    body.innerHTML = html;
    if (device === "iphone" || device === "ipad" || device === "mac") applyPhoneArtwork(frame);
    const phone = frame.querySelector(".phone");
    phone?.classList.toggle("is-settings", panelId === "settings");
    phone?.classList.toggle("is-history", panelId === "history");
    phone?.classList.toggle("is-detail", isDetail);
    phone?.classList.toggle("is-downloads", panelId === "downloads");
    phone?.classList.toggle("is-local", panelId === "local");
    const ipadScreen = frame.querySelector(".ipad-screen");
    ipadScreen?.classList.toggle("is-settings", panelId === "settings");
    ipadScreen?.classList.toggle("is-library", panelId === "local" || panelId === "downloads");
    const macScreen = frame.querySelector(".mac-screen");
    macScreen?.classList.toggle("is-settings", panelId === "settings");
    macScreen?.classList.toggle("is-library", panelId === "local" || panelId === "downloads");
    frame.querySelector("[data-app-more-menu]")?.remove();
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

  function selectRootPanel(device, panelId) {
    state[device] = [panelId];
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
      const splitToggle = event.target.closest("[data-split-sidebar-toggle]");
      if (splitToggle) {
        const splitScreen = frame.querySelector(device === "mac" ? ".mac-screen" : ".ipad-screen");
        const isCollapsed = splitScreen?.classList.toggle("sidebar-is-collapsed");
        frame.querySelectorAll("[data-split-sidebar-toggle]").forEach((toggle) => toggle.setAttribute("aria-expanded", String(!isCollapsed)));
        return;
      }
      const readerControls = event.target.closest("[data-reader-controls]");
      if (readerControls) {
        readerControls.closest(".reader-view")?.classList.toggle("controls-hidden");
        return;
      }
      const readerPreview = event.target.closest("[data-reader-preview]");
      if (readerPreview) {
        readerPreview.classList.toggle("is-expanded");
        return;
      }
      const backBtn = event.target.closest("[data-back]");
      if (backBtn) { popPanel(device); return; }
      const toggle = event.target.closest(".toggle");
      if (toggle) { toggle.classList.toggle("on"); return; }
      const appMenu = event.target.closest("[data-app-menu]");
      if (appMenu) {
        const existing = frame.querySelector("[data-app-more-menu]");
        if (existing) existing.remove();
        else appMenu.insertAdjacentHTML("afterend", appMenuHTML());
        return;
      }
      const appMenuAction = event.target.closest("[data-app-menu-action]");
      if (appMenuAction) {
        frame.querySelector("[data-app-more-menu]")?.remove();
        if (appMenuAction.textContent.trim().toLocaleLowerCase().includes(lang === "en" ? "settings" : "设置")) pushPanel(device, "settings");
        return;
      }
      const download = event.target.closest("[data-download-toggle]");
      if (download) {
        download.classList.add("is-complete");
        download.innerHTML = ICONS.checkmark + (lang === "en" ? "Added" : "已加入");
        return;
      }
      const favorite = event.target.closest("[data-favorite]");
      if (favorite) {
        favorite.classList.toggle("is-favorite");
        const saved = favorite.classList.contains("is-favorite");
        favorite.innerHTML = ICONS.heart + (lang === "en" ? (saved ? "Saved" : "Favorite") : (saved ? "已收藏" : "收藏"));
        return;
      }
      const panelBtn = event.target.closest("[data-panel]");
      if (panelBtn?.classList.contains("side-item")) { selectRootPanel(device, panelBtn.dataset.panel); return; }
      if (panelBtn) { pushPanel(device, panelBtn.dataset.panel); return; }
    });

    frame.addEventListener("input", (event) => {
      const slider = event.target.closest(".rp-slider");
      if (!slider) return;
      const page = slider.closest(".reader-progress")?.querySelector(".rp-page");
      if (page) page.textContent = lang === "en" ? "Page " + slider.value + "/240" : "第 " + slider.value + "/240 页";
    });
  });

  tabs.forEach((tab) => {
    tab.addEventListener("click", () => {
      tabs.forEach((t) => {
        const selected = t === tab;
        t.classList.toggle("is-active", selected);
        t.setAttribute("aria-selected", String(selected));
      });
      frames.forEach((f) => {
        const on = f.dataset.devicePanel === tab.dataset.device;
        f.classList.toggle("is-active", on);
        f.hidden = !on;
      });
    });
  });
}

/* ================= Reader feature demo =================
   Mirrors ReaderView's tap-to-toggle controls, ReaderSettingsMenu, and
   ReaderProgressControl without pretending to load remote gallery media. */
document.querySelectorAll("[data-reader-demo]").forEach((demo) => {
  const isEnglish = demo.dataset.lang === "en";
  const screen = demo.querySelector(".reader-ipad-screen");
  const art = demo.querySelector(".reader-art");
  const more = demo.querySelector(".reader-more");
  const menu = demo.querySelector("[data-reader-menu]");
  const slider = demo.querySelector("[data-reader-slider]");
  const page = demo.querySelector("[data-reader-page]");
  const label = demo.querySelector("[data-reader-label]");
  const preview = demo.querySelector("[data-reader-preview]");
  const thumbnails = demo.querySelector("[data-reader-thumbnails]");
  const total = Number(slider?.max || 240);
  let readingMode = "paged";
  let directionIsReversed = true;
  let startPosition = "lastRead";
  let rotation = "automatic";
  let volumePage = false;
  let reverseVolumePage = false;

  const pageText = (value) => isEnglish ? "Page " + value + " / " + total : "第 " + value + " / " + total + " 页";
  const setPage = (value) => {
    const next = Math.max(1, Math.min(total, Number(value) || 1));
    if (slider) slider.value = String(next);
    if (page) page.textContent = String(next);
    if (label) label.textContent = pageText(next);
    thumbnails?.querySelectorAll(".reader-thumb").forEach((thumb) => {
      thumb.classList.toggle("is-current", Number(thumb.dataset.page) === next);
    });
  };

  const updateMenu = () => {
    menu?.querySelectorAll("[data-reader-mode]").forEach((button) => {
      button.querySelector("b").textContent = button.dataset.readerMode === readingMode ? "✓" : "";
    });
    const direction = menu?.querySelector("[data-reader-direction] em");
    if (direction) direction.textContent = isEnglish
      ? (directionIsReversed ? "Right to left" : "Left to right")
      : (directionIsReversed ? "从右到左" : "从左到右");
    const directionButton = menu?.querySelector("[data-reader-direction]");
    if (directionButton) directionButton.hidden = readingMode !== "paged";
    const start = menu?.querySelector("[data-reader-start] em");
    const startText = isEnglish
      ? { lastRead: "Last read position", first: "Always first page", last: "Always last page" }
      : { lastRead: "上次阅读位置", first: "总是从第一页", last: "总是从最后一页" };
    if (start) start.textContent = startText[startPosition];
    const rotationLabel = menu?.querySelector("[data-reader-rotation] em");
    const rotationText = isEnglish
      ? { automatic: "Follow system", portrait: "Portrait", landscape: "Landscape" }
      : { automatic: "跟随系统", portrait: "竖屏", landscape: "横屏" };
    if (rotationLabel) rotationLabel.textContent = rotationText[rotation];
    const volumeSwitch = menu?.querySelector("[data-reader-volume] .reader-switch");
    volumeSwitch?.classList.toggle("is-on", volumePage);
    const reverseButton = menu?.querySelector("[data-reader-reverse]");
    if (reverseButton) reverseButton.hidden = !volumePage;
    const reverseSwitch = reverseButton?.querySelector(".reader-switch");
    reverseSwitch?.classList.toggle("is-on", reverseVolumePage);
    screen?.classList.toggle("is-continuous", readingMode === "vertical");
  };

  if (thumbnails) {
    thumbnails.innerHTML = Array.from({ length: 10 }, (_, index) => {
      const value = Math.max(1, Math.min(total, 9 + index));
      return '<button class="reader-thumb' + (value === 13 ? " is-current" : "") + '" type="button" data-page="' + value + '"><span class="reader-thumb-image"></span><span>' + value + '</span></button>';
    }).join("");
  }

  art?.addEventListener("click", () => {
    screen?.classList.toggle("controls-hidden");
    menu.hidden = true;
  });
  more?.addEventListener("click", (event) => {
    event.stopPropagation();
    screen?.classList.remove("controls-hidden");
    menu.hidden = !menu.hidden;
  });
  slider?.addEventListener("input", () => setPage(slider.value));
  preview?.addEventListener("click", () => {
    screen?.classList.remove("controls-hidden");
    thumbnails.hidden = !thumbnails.hidden;
    preview.classList.toggle("is-expanded", !thumbnails.hidden);
  });
  thumbnails?.addEventListener("click", (event) => {
    const thumb = event.target.closest("[data-page]");
    if (thumb) setPage(thumb.dataset.page);
  });
  menu?.addEventListener("click", (event) => {
    const mode = event.target.closest("[data-reader-mode]");
    if (mode) {
      readingMode = mode.dataset.readerMode;
      updateMenu();
      return;
    }
    if (event.target.closest("[data-reader-direction]")) {
      directionIsReversed = !directionIsReversed;
      updateMenu();
      return;
    }
    if (event.target.closest("[data-reader-start]")) {
      startPosition = startPosition === "lastRead" ? "first" : startPosition === "first" ? "last" : "lastRead";
      updateMenu();
      return;
    }
    if (event.target.closest("[data-reader-rotation]")) {
      rotation = rotation === "automatic" ? "portrait" : rotation === "portrait" ? "landscape" : "automatic";
      updateMenu();
      return;
    }
    if (event.target.closest("[data-reader-volume]")) {
      volumePage = !volumePage;
      if (!volumePage) reverseVolumePage = false;
      updateMenu();
      return;
    }
    if (event.target.closest("[data-reader-reverse]")) {
      reverseVolumePage = !reverseVolumePage;
      updateMenu();
    }
  });
  document.addEventListener("click", (event) => {
    if (!demo.contains(event.target)) menu.hidden = true;
  });
  updateMenu();
});

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
