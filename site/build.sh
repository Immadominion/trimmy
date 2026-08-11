#!/usr/bin/env bash
# Assemble the deployable site.
#
# The arming page's source of truth is ../web/. It is COPIED here rather than
# duplicated in git, because it has its own tests that import from ../lib and
# moving it would break them — and because two tracked copies of a page that
# authorises irreversible payments is exactly the kind of thing that drifts.
#
# Generates:
#   arm/           the arming page, from ../web/
#   index.md       the markdown twin of index.html
#   llms-full.txt  the whole site as one file, so an agent needs one fetch
#
# Usage: ./build.sh          (then: wrangler pages deploy . --project-name trimmy)
set -euo pipefail
cd "$(dirname "$0")"

echo "→ arming page"
rm -rf arm && mkdir -p arm
cp -R ../web/index.html ../web/arm.js ../web/lib arm/
# The test fixtures and the page's own README are not part of the deployment.
echo "  arm/ $(find arm -type f | wc -l | tr -d ' ') files"

echo "→ index.md (markdown twin)"
python3 - <<'PY'
import html, re
src = open('index.html', encoding='utf-8').read()

body = re.search(r'<main id="main">(.*)</main>', src, re.S).group(1)
body = re.sub(r'<!--.*?-->', '', body, flags=re.S)
body = re.sub(r'<(script|style|figcaption)\b.*?</\1>', '', body, flags=re.S)
# A <br> is a word boundary. Dropping it silently welds two sentences together
# ("Set the price.Then go to sleep.") — the twin's whole job is to be readable.
body = re.sub(r'<br\s*/?>', ' ', body)
# Keep links as links; a bare label like "See how it works" is noise in markdown.
body = re.sub(r'<a\b[^>]*href="([^"]+)"[^>]*>(.*?)</a>',
              lambda m: f'[{re.sub(r"<[^>]+>", "", m.group(2)).strip()}]({m.group(1)})',
              body, flags=re.S)

def block(m):
    inner = re.sub(r'<[^>]+>', '', m.group(2))
    return '\n\n```\n' + html.unescape(inner).strip('\n') + '\n```\n\n'
body = re.sub(r'<(pre)\b[^>]*>(.*?)</\1>', block, body, flags=re.S)

for lvl, tag in ((1, 'h1'), (2, 'h2'), (3, 'h3')):
    body = re.sub(rf'<{tag}\b[^>]*>(.*?)</{tag}>',
                  lambda m, l=lvl: '\n\n' + '#' * l + ' ' +
                  re.sub(r'\s+', ' ', re.sub(r'<[^>]+>', '', m.group(1))).strip() + '\n\n',
                  body, flags=re.S)

body = re.sub(r'<li\b[^>]*>', '\n- ', body)
# Tables carry most of the evidence, so they have to survive as tables. Cells
# become pipe-separated; without this the ledger collapses into "WhatAddressNote".
body = re.sub(r'<(th|td)\b[^>]*>', ' | ', body)
body = re.sub(r'</tr>', ' |\n', body)
body = re.sub(r'</(p|div|section|article|dd|dt)>', '\n', body)
body = re.sub(r'<[^>]+>', '', body)
body = html.unescape(body)
# Collapse runs of spaces, then strip per line — otherwise every line inherits
# the HTML source's indentation and markdown reads it as a code block.
body = re.sub(r'[ \t]+', ' ', body)
body = '\n'.join(l.rstrip() if l.startswith('```') or l.startswith('    ') else l.strip()
                 for l in body.split('\n'))
body = re.sub(r'\n{3,}', '\n\n', body).strip()

# The HTML source puts newlines between cells, so a row arrives split across
# several lines. Rejoin anything that opened a row but has not closed it.
rows, buf = [], ''
for line in body.split('\n'):
    if buf:
        buf += ' ' + line.strip()
        if buf.rstrip().endswith('|'):
            rows.append(buf); buf = ''
    elif line.startswith('|') and not line.rstrip().endswith('|'):
        buf = line.rstrip()
    else:
        rows.append(line)
if buf: rows.append(buf)
body = re.sub(r'\n{3,}', '\n\n', '\n'.join(rows))

head = ("# Trimmy — AI-friendly automation for XRP\n\n"
        "> Markdown twin of https://trimmy.xyz/ — same content, no markup.\n\n---\n\n")
open('index.md', 'w', encoding='utf-8').write(head + body + '\n')
print(f"  index.md {len(head)+len(body)} bytes")
PY

echo "→ llms-full.txt"
{
  cat llms.txt
  printf '\n\n---\n\n'
  cat index.md
} > llms-full.txt
echo "  llms-full.txt $(wc -c < llms-full.txt | tr -d ' ') bytes"

echo "done."
