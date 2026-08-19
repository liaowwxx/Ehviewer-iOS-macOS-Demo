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
