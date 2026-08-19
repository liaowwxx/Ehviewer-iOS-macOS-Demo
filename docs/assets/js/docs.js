(() => {
  "use strict";

  const root = document.documentElement;
  const article = document.querySelector("#doc-content");
  const sidebar = document.querySelector("#sidebar");
  const sidebarToggle = document.querySelector("#sidebar-toggle");
  const sidebarBackdrop = document.querySelector("#sidebar-backdrop");
  const toc = document.querySelector("#sidebar-toc");
  const searchInput = document.querySelector("#doc-search");
  const searchPanel = document.querySelector("#search-panel");
  const searchResults = document.querySelector("#search-results");
  const searchCount = document.querySelector("#search-count");
  const pageNav = document.querySelector("#page-nav");
  const themeToggle = document.querySelector("#theme-toggle");
  const isEnglish = document.documentElement.lang.toLowerCase().startsWith("en");
  const ui = {
    previous: isEnglish ? "Previous page" : "上一页",
    next: isEnglish ? "Next page" : "下一页",
    overview: isEnglish ? "Document overview" : "文档概览",
    noResults: isEnglish ? "No matching content found." : "没有找到匹配内容。",
    resultCount: (count) => isEnglish ? `${count} result${count === 1 ? "" : "s"}` : `${count} 个结果`,
    theme: isEnglish ? "Theme" : "主题",
    themeValues: isEnglish ? { dark: "Dark", light: "Light", auto: "Auto" } : { dark: "深色", light: "浅色", auto: "自动" },
  };

  if (!article) return;

  const headings = [...article.querySelectorAll("h2, h3")];
  const sections = [...article.querySelectorAll("h2")];

  function createToc() {
    const list = document.createElement("ul");
    let currentSublist = null;

    headings.forEach((heading) => {
      if (!heading.id) return;
      const item = document.createElement("li");
      const link = document.createElement("a");
      link.href = `#${heading.id}`;
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
    const introText = [firstHeading, ...introNodes]
      .map((item) => item.textContent)
      .join(" ")
      .replace(/\s+/g, " ")
      .trim();
    if (introText) {
      records.unshift({ anchor: firstHeading.id, title: ui.overview, text: introText });
    }
    return records;
  }

  function createPageNavigation() {
    if (sections.length < 2) return;
    const currentIndex = 0;
    const previous = document.createElement("span");
    previous.className = "page-nav-placeholder";
    const next = document.createElement("a");
    next.href = `#${sections[currentIndex + 1].id}`;
    next.innerHTML = `<small>${ui.next}</small><span>${sections[currentIndex + 1].textContent}</span>`;
    pageNav.replaceChildren(previous, next);

    const updateNavigation = () => {
      const scrollPosition = window.scrollY + 140;
      let index = 0;
      sections.forEach((section, candidateIndex) => {
        if (section.offsetTop <= scrollPosition) index = candidateIndex;
      });
      const links = [];
      if (index > 0) {
        const link = document.createElement("a");
        link.href = `#${sections[index - 1].id}`;
        link.innerHTML = `<small>${ui.previous}</small><span>${sections[index - 1].textContent}</span>`;
        links.push(link);
      } else {
        links.push(document.createElement("span"));
      }
      if (index < sections.length - 1) {
        const link = document.createElement("a");
        link.href = `#${sections[index + 1].id}`;
        link.innerHTML = `<small>${ui.next}</small><span>${sections[index + 1].textContent}</span>`;
        links.push(link);
      } else {
        links.push(document.createElement("span"));
      }
      pageNav.replaceChildren(...links);
    };

    window.addEventListener("scroll", updateNavigation, { passive: true });
    updateNavigation();
  }

  function renderSearch(query) {
    const normalizedQuery = query.trim().toLocaleLowerCase();
    if (!normalizedQuery) {
      searchPanel.hidden = true;
      searchResults.replaceChildren();
      searchCount.textContent = "";
      return;
    }

    const matches = searchRecords().filter((entry) => entry.text.toLocaleLowerCase().includes(normalizedQuery));

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

    matches.forEach(({ anchor, title: recordTitle, text }) => {
      const link = document.createElement("a");
      link.className = "search-result";
      link.href = `#${anchor}`;
      const title = document.createElement("strong");
      title.textContent = recordTitle;
      const snippet = document.createElement("span");
      const matchIndex = text.toLocaleLowerCase().indexOf(normalizedQuery);
      const start = Math.max(0, matchIndex - 48);
      snippet.textContent = `${start > 0 ? "…" : ""}${text.slice(start, start + 150)}${start + 150 < text.length ? "…" : ""}`;
      link.append(title, snippet);
      searchResults.append(link);
    });
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

  function setupTheme() {
    const key = "ehviewer-docs-theme";
    const saved = localStorage.getItem(key);
    if (saved === "light" || saved === "dark") root.dataset.theme = saved;

    const updateLabel = () => {
      const current = root.dataset.theme || "auto";
      themeToggle.textContent = `${ui.theme}: ${ui.themeValues[current]}`;
      themeToggle.setAttribute("aria-pressed", current === "dark" ? "true" : "false");
    };

    themeToggle?.addEventListener("click", () => {
      const current = root.dataset.theme || "auto";
      const next = current === "auto" ? "dark" : current === "dark" ? "light" : "auto";
      root.dataset.theme = next;
      if (next === "auto") localStorage.removeItem(key);
      else localStorage.setItem(key, next);
      updateLabel();
    });
    updateLabel();
  }

  createToc();
  createPageNavigation();
  setupTheme();

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
    const observer = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        links.forEach((link) => link.classList.toggle("active", link.dataset.headingId === entry.target.id));
      });
    }, { rootMargin: "-100px 0px -70% 0px", threshold: 0 });
    headings.forEach((heading) => observer.observe(heading));
  }
})();
