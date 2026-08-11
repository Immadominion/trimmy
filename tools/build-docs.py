#!/usr/bin/env python3
"""Generate the docs HTML from its markdown source.

The markdown IS the source of truth and it is what is committed. The HTML is
built from it. That ordering matters for two reasons: a person editing a doc
should not have to touch markup, and the .md twin the AI-native layer serves is
then literally the same file a reader edits rather than a lossy re-derivation of
the rendered page.

Layout on disk:

    site/docs/<slug>/index.md          source, with frontmatter
    site/docs/<slug>/index.html        generated, do not edit
    site/developers/<slug>/index.md    source
    site/developers/<slug>/index.html  generated

Frontmatter, all required except order:

    ---
    title: Rule types
    summary: One sentence. Used as the meta description and the nav subtitle.
    order: 2
    ---

Requires: pip install markdown        (build-time only; the site ships static)
Usage:    python3 tools/build-docs.py
"""
from __future__ import annotations

import html
import pathlib
import re
import sys

try:
    import markdown
except ImportError:
    sys.exit("needs `pip install markdown` (build-time only, the site ships static)")

ROOT = pathlib.Path(__file__).resolve().parent.parent
SITE = ROOT / "site"

SECTIONS = [
    ("docs", "Using Trimmy", "The product manual."),
    ("developers", "Developer reference", "Contracts, formats, and evidence."),
]

EM_DASH = "—"


def read_source(path: pathlib.Path) -> dict:
    raw = path.read_text(encoding="utf-8")
    m = re.match(r"^---\n(.*?)\n---\n(.*)$", raw, re.S)
    if not m:
        sys.exit(f"{path}: missing frontmatter")
    meta = {}
    for line in m.group(1).splitlines():
        if ":" in line:
            k, v = line.split(":", 1)
            meta[k.strip()] = v.strip()
    for required in ("title", "summary"):
        if required not in meta:
            sys.exit(f"{path}: frontmatter is missing `{required}`")
    return {
        "meta": meta,
        "body": m.group(2),
        "slug": path.parent.name,
        "order": int(meta.get("order", 999)),
    }


def collect() -> dict[str, list[dict]]:
    """A page whose slug is `index` becomes the section root.

    Without this, `developers/index/index.md` publishes at /developers/index/
    and a visitor who types /developers/ gets a directory listing. The section
    root is the page most likely to be linked, so it cannot be the one that
    404s or, worse, exposes the file tree.
    """
    out = {}
    for key, _, _ in SECTIONS:
        base = SITE / key
        pages = [read_source(p) for p in sorted(base.glob("*/index.md"))]
        root = base / "index.md"
        if root.exists():
            p = read_source(root)
            p["slug"] = ""
            pages.append(p)
        out[key] = sorted(pages, key=lambda p: (p["order"], p["slug"]))
    return out


def out_dir(key: str, slug: str) -> pathlib.Path:
    return SITE / key if slug == "" else SITE / key / slug


def render_nav(all_pages, current_key, current_slug) -> str:
    groups = []
    for key, label, _ in SECTIONS:
        items = []
        for p in all_pages[key]:
            href = f"/{key}/" if p["slug"] == "" else f"/{key}/{p['slug']}/"
            cur = ' aria-current="page"' if (key == current_key and p["slug"] == current_slug) else ""
            items.append(f'<li><a href="{href}"{cur}>{html.escape(p["meta"]["title"])}</a></li>')
        groups.append(
            f'<div class="doc-nav__group">'
            f'<p class="doc-nav__title">{html.escape(label)}</p>'
            f'<ul>{"".join(items)}</ul></div>'
        )
    return "".join(groups)


def render_toc(body_html: str) -> str:
    heads = re.findall(r'<h2 id="([^"]+)">(.*?)</h2>', body_html, re.S)
    if len(heads) < 2:
        return ""
    items = "".join(
        f'<li><a href="#{i}">{re.sub(r"<[^>]+>", "", t).strip()}</a></li>' for i, t in heads
    )
    return (
        '<aside class="doc-toc" aria-label="On this page">'
        '<p class="doc-nav__title">On this page</p>'
        f"<ul>{items}</ul></aside>"
    )


SHELL = """<!doctype html>
<!-- GENERATED from {src}. Edit the markdown, then run tools/build-docs.py. -->
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title} | Trimmy</title>
<meta name="description" content="{summary}">
<link rel="canonical" href="https://trimmy.xyz/{key}/{slug}">
<link rel="icon" href="/assets/mark-64.png" sizes="64x64" type="image/png">
<link rel="icon" href="/assets/mark-32.png" sizes="32x32" type="image/png">
<link rel="apple-touch-icon" href="/assets/mark-180.png">
<meta property="og:type" content="article">
<meta property="og:url" content="https://trimmy.xyz/{key}/{slug}">
<meta property="og:title" content="{title} | Trimmy">
<meta property="og:description" content="{summary}">
<link rel="stylesheet" href="/assets/trimmy.css">
<link rel="stylesheet" href="/assets/docs.css">
</head>
<body>
<a href="#doc" class="skip">Skip to content</a>

<header class="site-header">
  <div class="container nav">
    <a class="brand" href="/" aria-label="Trimmy, home">
      <img src="/assets/mark-64.png" width="30" height="30" alt="" class="brand__mark">
      <span class="brand__word">Trimmy</span>
    </a>
    <nav class="nav__links" aria-label="Primary navigation">
      <a href="/docs/start-here/">Docs</a>
      <a href="/developers/">Developers</a>
      <a href="/rules/">Live rules</a>
    </nav>
    <div class="nav__end">
      <a class="nav__cta" href="/arm/">Try Trimmy</a>
    </div>
  </div>
</header>

<main class="container doc-shell">
  <details class="doc-nav__toggle"><summary>All pages</summary>
    <div><nav class="doc-nav" aria-label="Documentation">{nav}</nav></div>
  </details>
  <nav class="doc-nav doc-nav--wide" aria-label="Documentation">{nav}</nav>

  <article class="doc-body" id="doc">
    <p class="doc-kicker">{kicker}</p>
    <h1>{title}</h1>
    <p class="doc-lede">{summary}</p>
    <p class="doc-testnet"><b>Testnet.</b> <span>Trimmy runs on Flare Coston2. Nothing described
      here has run on Flare mainnet, and no page on this site describes real money.</span></p>
{body}
    <div class="doc-foot">
      <a href="https://github.com/Immadominion/trimmy">Source on GitHub</a>
      <span class="doc-foot__md">Read this page as markdown: <code>/{key}/{slug}index.md</code></span>
    </div>
  </article>

  {toc}
</main>

<footer class="site-footer">
  <div class="container footer__end">
    <p class="t-sm dim">Trimmy runs on Flare Coston2 testnet.
      <a href="https://github.com/Immadominion/trimmy">trimmy</a> &middot;
      <a href="https://github.com/Immadominion/plimsoll">plimsoll</a> &middot;
      <a href="https://github.com/Immadominion/flare-dart">flare-dart</a></p>
  </div>
</footer>
</body>
</html>
"""


def main() -> None:
    pages = collect()
    total = 0
    for key, label, _ in SECTIONS:
        for p in pages[key]:
            src = out_dir(key, p["slug"]) / "index.md"
            md = markdown.Markdown(
                extensions=["tables", "fenced_code", "attr_list", "toc", "sane_lists"],
                extension_configs={"toc": {"permalink": False}},
            )
            body_html = md.convert(p["body"])
            # Tables scroll inside their own box; a wide reference table must
            # never be what makes the page scroll sideways.
            body_html = re.sub(
                r"<table>(.*?)</table>",
                lambda m: f'<div class="doc-table"><table>{m.group(1)}</table></div>',
                body_html,
                flags=re.S,
            )
            out = SHELL.format(
                src=f"site/{key}/{p['slug']}/index.md".replace("//", "/"),
                key=key,
                slug=(p["slug"] + "/") if p["slug"] else "",
                title=html.escape(p["meta"]["title"]),
                summary=html.escape(p["meta"]["summary"]),
                kicker=html.escape(label),
                nav=render_nav(pages, key, p["slug"]),
                body=body_html,
                toc=render_toc(body_html),
            )
            if EM_DASH in out:
                sys.exit(f"{src}: contains an em dash. See tools/check-no-emdash.sh")
            (out_dir(key, p["slug"]) / "index.html").write_text(out, encoding="utf-8")
            total += 1
    print(f"built {total} pages across {len(SECTIONS)} sections")


if __name__ == "__main__":
    main()
