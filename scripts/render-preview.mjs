import { readFileSync, writeFileSync, mkdirSync, cpSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const DOCS = join(HERE, "..", "docs");
const OUT = join(HERE, "..", "_preview", "Ehviewer-iOS-macOS-Demo");

const site = { title: "EhViewer", description: "desc", url: "https://liaowwxx.github.io", baseurl: "/Ehviewer-iOS-macOS-Demo" };

function esc(s) { return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }

function renderLiquid(src, page, dark) {
  let s = src;
  s = s.replace(/\{%\s*if page\.lang == 'en'\s*%\}([\s\S]*?)\{\%\s*else\s*%\}([\s\S]*?)\{\%\s*endif\s*%\}/g, (_, a, b) => (page.lang === "en" ? a : b));
  s = s.replace(/\{%\s*if page\.lang == 'en'\s*%\}([\s\S]*?)\{\%\s*endif\s*%\}/g, (_, a) => (page.lang === "en" ? a : ""));
  s = s.replace(/\{\{\s*page\.lang\s*\|\s*default:\s*'zh-Hans'\s*\}\}/g, page.lang);
  s = s.replace(/\{\{\s*site\.title\s*\|\s*escape\s*\}\}/g, esc(site.title));
  s = s.replace(/\{\{\s*page\.title\s*\|\s*default:\s*site\.title\s*\|\s*escape\s*\}\}/g, esc(page.title || site.title));
  s = s.replace(/\{\{\s*page\.title\s*\|\s*default:\s*'([^']+)'\s*\}\}/g, (_, d) => esc(page.title || d));
  s = s.replace(/\{\{\s*page\.description\s*\|\s*default:\s*site\.description\s*\|\s*escape\s*\}\}/g, esc(page.description || site.description));
  s = s.replace(/\{\{\s*page\.url\s*\|\s*absolute_url\s*\}\}/g, site.url + site.baseurl + page.url);
  s = s.replace(/\{\{\s*'([^']+)'\s*\|\s*relative_url\s*\}\}/g, (_, p) => site.baseurl + p);
  s = s.replace(/\{\{\s*'([^']+)'\s*\|\s*absolute_url\s*\}\}/g, (_, p) => site.url + site.baseurl + p);
  s = s.replace(/\{\{\s*'now'\s*\|\s*date:\s*'%Y'\s*\}\}/g, String(new Date().getFullYear()));
  if (dark) s = s.replace("<html lang=", '<html data-theme="dark" lang=');
  return s;
}

function inline(t) {
  return t
    .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
    .replace(/`([^`]+)`/g, "<code>$1</code>")
    .replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2">$1</a>');
}

function mdToHtml(md) {
  const lines = md.split("\n");
  const out = [];
  let i = 0, inCode = false, codeBuf = [], listBuf = [], listType = null, paraBuf = [];
  const flushList = () => {
    if (listBuf.length) {
      const tag = listType === "ul" ? "ul" : "ol";
      out.push("<" + tag + ">\n" + listBuf.map((li) => "  <li>" + inline(li) + "</li>").join("\n") + "\n</" + tag + ">");
      listBuf = []; listType = null;
    }
  };
  const flushPara = () => { if (paraBuf.length) { out.push("<p>" + inline(paraBuf.join(" ")) + "</p>"); paraBuf = []; } };
  for (; i < lines.length; i++) {
    const line = lines[i];
    if (line.startsWith("```")) {
      flushList(); flushPara();
      if (inCode) { out.push("<pre><code>" + codeBuf.join("\n").replace(/</g, "&lt;") + "</code></pre>"); codeBuf = []; inCode = false; }
      else inCode = true;
      continue;
    }
    if (inCode) { codeBuf.push(line); continue; }
    const h = line.match(/^(#{1,4})\s+(.*)$/);
    if (h) { flushList(); flushPara(); const n = h[1].length; const txt = h[2].replace(/[^\w\u4e00-\u9fa5]+/g, "-").replace(/^-+|-+$/g, "").toLowerCase(); out.push("<h" + n + ' id="' + txt + '">' + inline(h[2]) + "</h" + n + ">"); continue; }
    if (/^\s*[-*]\s+/.test(line)) { flushPara(); if (listType !== "ul") { flushList(); listType = "ul"; } listBuf.push(line.replace(/^\s*[-*]\s+/, "")); continue; }
    if (/^\s*\d+\.\s+/.test(line)) { flushPara(); if (listType !== "ol") { flushList(); listType = "ol"; } listBuf.push(line.replace(/^\s*\d+\.\s+/, "")); continue; }
    if (/^\s*>\s?/.test(line)) { flushList(); flushPara(); out.push("<blockquote><p>" + inline(line.replace(/^\s*>\s?/, "")) + "</p></blockquote>"); continue; }
    if (/^---+$/.test(line.trim())) { flushList(); flushPara(); out.push("<hr>"); continue; }
    if (line.trim() === "") { flushList(); flushPara(); continue; }
    if (line.trim().startsWith("<") && line.trim().endsWith(">")) { flushList(); flushPara(); out.push(line); continue; }
    paraBuf.push(line.trim());
  }
  flushList(); flushPara();
  return out.join("\n");
}

const pages = [
  { file: "index.md", out: "index.html", url: "/", lang: "zh-Hans", title: "EhViewer" },
  { file: "index.en.md", out: "en/index.html", url: "/en/", lang: "en", title: "EhViewer" },
  { file: "guide.md", out: "guide/index.html", url: "/guide/", lang: "zh-Hans", title: "使用说明" },
  { file: "guide.en.md", out: "en/guide/index.html", url: "/en/guide/", lang: "en", title: "User Guide" },
];

mkdirSync(join(OUT, "en"), { recursive: true });
mkdirSync(join(OUT, "guide"), { recursive: true });
mkdirSync(join(OUT, "en/guide"), { recursive: true });
cpSync(join(DOCS, "assets"), join(OUT, "assets"), { recursive: true });

for (const dark of [false, true]) {
  for (const p of pages) {
    const layout = readFileSync(join(DOCS, "_layouts", p.file.startsWith("index") ? "home.html" : "default.html"), "utf8");
    let body = readFileSync(join(DOCS, p.file), "utf8");
    body = body.replace(/^---[\s\S]*?---\n/, "");
    body = renderLiquid(body, p, dark);
    let html = renderLiquid(layout, p, dark).replace("{{ content }}", p.file.startsWith("index") ? body : mdToHtml(body));
    const suffix = dark ? ".dark" : "";
    const name = p.out.replace(/\.html$/, "") + suffix + ".html";
    mkdirSync(dirname(join(OUT, p.out)), { recursive: true });
    writeFileSync(join(OUT, name), html);
  }
}
console.log("✓ 预览文件已生成到 _preview/");
