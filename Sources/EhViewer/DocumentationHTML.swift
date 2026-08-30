/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai 画廊浏览客户端
 * Copyright (C) 2026 EhViewer Contributors
 */

import Foundation

enum DocumentationHTML {
    static func document(content: String) -> String {
        """
        <!doctype html>
        <html lang="zh-Hans">
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
            <meta name="color-scheme" content="light dark">
            <style>
                :root {
                    color-scheme: light;
                    --paper: #f4f1ec;
                    --surface: #fffdf9;
                    --surface-2: #faf7f2;
                    --ink: #211d19;
                    --ink-2: #4b443c;
                    --muted: #7c7367;
                    --hairline: #e0d9cf;
                    --hairline-strong: #cbc2b4;
                    --accent: #429488;
                    --accent-ink: #2e6e64;
                    --accent-wash: #dff0eb;
                    --accent-glow: rgba(66, 148, 136, 0.16);
                    --spot: rgba(66, 148, 136, 0.10);
                    --shadow-sm: 0 1px 2px rgba(33, 29, 25, 0.05), 0 10px 30px -18px rgba(33, 29, 25, 0.22);
                    --shadow-md: 0 2px 6px rgba(33, 29, 25, 0.05), 0 32px 70px -28px rgba(33, 29, 25, 0.28);
                    --sans: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", "PingFang SC", "Hiragino Sans GB", sans-serif;
                    --serif: -apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC", "Hiragino Sans GB", "Noto Sans CJK SC", sans-serif;
                    --mono: ui-monospace, "SF Mono", SFMono-Regular, Menlo, Consolas, monospace;
                }

                @media (prefers-color-scheme: dark) {
                    :root {
                        color-scheme: dark;
                        --paper: #171410;
                        --surface: #221e19;
                        --surface-2: #1b1814;
                        --ink: #f0ebe3;
                        --ink-2: #c4baad;
                        --muted: #96897a;
                        --hairline: #322c25;
                        --hairline-strong: #4a4238;
                        --accent: #64b8a9;
                        --accent-ink: #93d2c4;
                        --accent-wash: #1f3b36;
                        --accent-glow: rgba(100, 184, 169, 0.18);
                        --spot: rgba(100, 184, 169, 0.12);
                        --shadow-sm: 0 1px 2px rgba(0, 0, 0, 0.3), 0 12px 32px -18px rgba(0, 0, 0, 0.6);
                        --shadow-md: 0 2px 6px rgba(0, 0, 0, 0.3), 0 36px 80px -30px rgba(0, 0, 0, 0.7);
                    }
                }

                *, *::before, *::after { box-sizing: border-box; }

                html {
                    min-width: 0;
                    background: var(--paper);
                    -webkit-text-size-adjust: 100%;
                }

                body {
                    min-width: 0;
                    min-height: 100vh;
                    margin: 0;
                    padding: max(18px, env(safe-area-inset-top)) max(16px, env(safe-area-inset-right)) calc(34px + env(safe-area-inset-bottom)) max(16px, env(safe-area-inset-left));
                    background: radial-gradient(720px circle at 100% 0%, var(--spot), transparent 58%), var(--paper);
                    color: var(--ink);
                    font-family: var(--sans);
                    font-size: clamp(16px, calc(15px + 0.25vw), 18px);
                    line-height: 1.68;
                    text-rendering: optimizeLegibility;
                    -webkit-font-smoothing: antialiased;
                    overflow-wrap: anywhere;
                }

                .page-shell {
                    display: grid;
                    grid-template-columns: minmax(164px, 220px) minmax(0, 880px);
                    gap: clamp(20px, 3.2vw, 38px);
                    align-items: start;
                    width: min(100%, 1160px);
                    margin: 0 auto;
                }

                main { min-width: 0; }

                .toc {
                    position: sticky;
                    top: max(18px, env(safe-area-inset-top));
                    max-height: calc(100vh - max(36px, env(safe-area-inset-top) + env(safe-area-inset-bottom)));
                    overflow-y: auto;
                    padding: 17px 13px 15px;
                    border: 1px solid var(--hairline);
                    border-radius: 16px;
                    background: color-mix(in srgb, var(--surface) 88%, transparent);
                    box-shadow: var(--shadow-sm);
                    scrollbar-width: thin;
                }

                .toc-kicker {
                    margin: 0 8px 5px;
                    color: var(--accent-ink);
                    font-family: var(--mono);
                    font-size: 0.68rem;
                    font-weight: 700;
                    letter-spacing: 0.08em;
                    line-height: 1.3;
                    text-transform: uppercase;
                }

                .toc-heading {
                    margin: 0 8px 12px;
                    color: var(--ink);
                    font-family: var(--serif);
                    font-size: 1.1rem;
                    font-weight: 650;
                    line-height: 1.25;
                }

                .toc nav { display: grid; gap: 2px; }

                .toc a {
                    display: block;
                    padding: 7px 8px;
                    border-left: 2px solid transparent;
                    border-radius: 0 8px 8px 0;
                    color: var(--muted);
                    font-size: 0.82rem;
                    line-height: 1.35;
                    text-decoration: none;
                    transition: background-color 160ms ease, border-color 160ms ease, color 160ms ease;
                }

                .toc a.level-3 { padding-left: 20px; font-size: 0.76rem; }
                .toc a:hover { color: var(--accent-ink); background: var(--accent-wash); }
                .toc a.active {
                    border-left-color: var(--accent);
                    background: var(--accent-wash);
                    color: var(--accent-ink);
                    font-weight: 650;
                }

                .toc-empty {
                    margin: 0 8px;
                    color: var(--muted);
                    font-size: 0.82rem;
                }

                article {
                    width: 100%;
                    margin: 0 auto;
                    padding: clamp(28px, 5vw, 54px) clamp(20px, 6vw, 64px) clamp(36px, 6vw, 70px);
                    border: 1px solid var(--hairline);
                    border-radius: clamp(18px, 3vw, 26px);
                    background: color-mix(in srgb, var(--surface) 92%, transparent);
                    box-shadow: var(--shadow-md);
                }

                h1, h2, h3, h4 {
                    color: var(--ink);
                    font-family: var(--serif);
                    overflow-wrap: anywhere;
                }

                h1 {
                    position: relative;
                    margin: 0 0 0.85em;
                    padding-bottom: 0.75em;
                    font-size: clamp(2rem, 7vw, 3.35rem);
                    font-weight: 650;
                    letter-spacing: -0.025em;
                    line-height: 1.08;
                }

                h1::after {
                    content: "";
                    position: absolute;
                    left: 0;
                    bottom: 0;
                    width: 3.2em;
                    height: 4px;
                    border-radius: 999px;
                    background: var(--accent);
                    box-shadow: 0 4px 16px var(--accent-glow);
                }

                h2 {
                    margin: 2.45em 0 0.8em;
                    padding-top: 1.15em;
                    border-top: 1px solid var(--hairline);
                    font-size: clamp(1.35rem, 3.2vw, 1.9rem);
                    font-weight: 650;
                    letter-spacing: -0.015em;
                    line-height: 1.2;
                }

                h3 { margin: 1.9em 0 0.55em; font-size: 1.15em; line-height: 1.25; }
                h4 { margin: 1.5em 0 0.45em; font-size: 1em; line-height: 1.3; }
                h2, h3, h4 { scroll-margin-top: 24px; }

                p, ul, ol, blockquote, pre, table { margin: 0 0 1.05em; }
                ul, ol { padding-left: 1.45em; }
                li { padding-left: 0.15em; }
                li + li { margin-top: 0.48em; }
                li::marker { color: var(--accent-ink); font-weight: 700; }
                strong { font-weight: 700; }

                a {
                    color: var(--accent-ink);
                    text-decoration-thickness: 1px;
                    text-underline-offset: 3px;
                }

                blockquote {
                    padding: 0.85em 1em;
                    border: 1px solid color-mix(in srgb, var(--accent) 28%, var(--hairline));
                    border-left: 4px solid var(--accent);
                    border-radius: 0 12px 12px 0;
                    background: var(--accent-wash);
                    color: var(--ink-2);
                }

                code {
                    padding: 0.16em 0.42em;
                    border-radius: 6px;
                    background: var(--accent-wash);
                    color: var(--accent-ink);
                    font-family: var(--mono);
                    font-size: 0.86em;
                    overflow-wrap: anywhere;
                }

                pre {
                    max-width: 100%;
                    overflow-x: auto;
                    padding: 1em 1.1em;
                    border: 1px solid var(--hairline);
                    border-radius: 14px;
                    background: var(--surface-2);
                    box-shadow: var(--shadow-sm);
                    -webkit-overflow-scrolling: touch;
                }

                pre code {
                    padding: 0;
                    background: transparent;
                    color: var(--ink-2);
                    white-space: pre;
                    overflow-wrap: normal;
                }

                hr { margin: 2em 0; border: 0; border-top: 1px solid var(--hairline); }
                img, video, svg { display: block; max-width: 100%; height: auto; }
                table { display: block; max-width: 100%; overflow-x: auto; border-collapse: collapse; }
                th, td { padding: 0.55em 0.8em; border: 1px solid var(--hairline); text-align: left; }
                th { background: var(--surface-2); }

                @media (max-width: 980px) {
                    .page-shell { display: block; max-width: 880px; }
                    .toc {
                        position: static;
                        max-height: none;
                        margin-bottom: 16px;
                    }
                    .toc nav { grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); }
                }

                @media (max-width: 560px) {
                    body { padding-right: max(12px, env(safe-area-inset-right)); padding-left: max(12px, env(safe-area-inset-left)); }
                    .toc { padding: 14px 10px 12px; border-radius: 14px; }
                    .toc nav { display: block; }
                    article { padding-right: 18px; padding-left: 18px; border-radius: 18px; }
                    h2 { margin-top: 2em; }
                }

                @media (prefers-reduced-motion: reduce) {
                    *, *::before, *::after { scroll-behavior: auto !important; transition: none !important; }
                }
            </style>
        </head>
        <body>
            <div class="page-shell">
                <aside class="toc" aria-label="当前文档目录">
                    <div class="toc-kicker">CURRENT DOCUMENT</div>
                    <div class="toc-heading">本页目录</div>
                    <nav id="toc" aria-label="章节快速跳转"></nav>
                </aside>
                <main>
                    <article id="document">\(content)</article>
                </main>
            </div>
            <script>
                (() => {
                    const article = document.getElementById("document");
                    const toc = document.getElementById("toc");
                    if (!article || !toc) return;

                    const headings = Array.from(article.querySelectorAll("h2, h3"));
                    if (headings.length === 0) {
                        toc.innerHTML = '<p class="toc-empty">暂无章节</p>';
                        return;
                    }

                    const links = headings.map((heading) => {
                        const link = document.createElement("a");
                        link.href = `#${heading.id}`;
                        link.className = `level-${heading.tagName.slice(1)}`;
                        link.dataset.target = heading.id;
                        link.textContent = heading.textContent.trim();
                        link.addEventListener("click", (event) => {
                            event.preventDefault();
                            const behavior = window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth";
                            heading.scrollIntoView({ behavior, block: "start" });
                            history.replaceState(null, "", link.href);
                        });
                        toc.appendChild(link);
                        return link;
                    });

                    const activate = (id) => {
                        links.forEach((link) => {
                            const isActive = link.dataset.target === id;
                            link.classList.toggle("active", isActive);
                            if (isActive) {
                                link.setAttribute("aria-current", "location");
                            } else {
                                link.removeAttribute("aria-current");
                            }
                        });
                    };

                    const observer = new IntersectionObserver((entries) => {
                        const visible = entries
                            .filter((entry) => entry.isIntersecting)
                            .sort((first, second) => first.boundingClientRect.top - second.boundingClientRect.top)[0];
                        if (visible) activate(visible.target.id);
                    }, { rootMargin: "-12% 0px -70% 0px", threshold: [0, 1] });

                    headings.forEach((heading) => observer.observe(heading));
                    const initialID = decodeURIComponent(location.hash.slice(1));
                    activate(headings.some((heading) => heading.id === initialID) ? initialID : headings[0].id);
                })();
            </script>
        </body>
        </html>
        """
    }
}
