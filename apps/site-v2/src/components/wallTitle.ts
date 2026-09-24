/**
 * Typesetting for a heading that stands alone on screen with a few words set
 * very large, the way the reference sets "INTO THE" small over a huge "AMAZON".
 *
 * "A wall gave a street its name." with WALL and STREET emphasised becomes:
 *
 *   wide screens               narrow screens
 *        1653                        1653
 *   A  WALL  GAVE A                   A
 *      STREET  ITS NAME.             WALL
 *                                   GAVE A
 *                                   STREET
 *                                  ITS NAME.
 *
 * The large words are always centred; the small words hang beside them when
 * they fit, and stack between them when they do not. The block is centred on
 * the screen. Drawing is in canvas pixels, so it can go into a WebGL texture.
 */

export type Token = { text: string; big: boolean };

/** Split a heading into runs of small words and single large words, in order. */
export function tokens(heading: string, emphasis: string[]): Token[] {
  const out: Token[] = [];
  let run: string[] = [];
  const flush = () => {
    if (run.length) out.push({ text: run.join(" "), big: false });
    run = [];
  };
  for (const word of heading.split(/\s+/).filter(Boolean)) {
    const bare = word.replace(/[^\p{L}]/gu, "").toLowerCase();
    if (emphasis.includes(bare)) {
      flush();
      out.push({ text: word, big: true });
    } else {
      run.push(word);
    }
  }
  flush();
  return out;
}

type Spaced = CanvasRenderingContext2D & { letterSpacing?: string };

const INK = "#fffdf7";
const bigFont = (size: number) => `800 ${size}px Bricolage, Arial, sans-serif`;
const smallFont = (size: number) => `700 ${size}px Manrope, Arial, sans-serif`;

/** Fonts that must be loaded before drawing. */
export const TITLE_FONTS = ["800 100px Bricolage", "700 16px Manrope"];

/** Draws the title and returns where its lowest line sits, as a share of the height. */
export function drawTitle(context: CanvasRenderingContext2D, width: number, height: number, scale: number, stamp: string, parts: Token[]): number {
  const c = context as Spaced;
  const upper = parts.map((part) => ({ ...part, text: part.text.toUpperCase() }));
  const bigs = upper.filter((part) => part.big);
  if (!bigs.length) return 0;

  const setBig = (size: number) => { c.font = bigFont(size); c.letterSpacing = `${-0.02 * size}px`; };
  const setSmall = (size: number) => { c.font = smallFont(size); c.letterSpacing = `${0.28 * size}px`; };
  // letterSpacing adds space after the last letter too; take it back off.
  const bigWidth = (text: string, size: number) => { setBig(size); return c.measureText(text).width + 0.02 * size; };
  const smallWidth = (text: string, size: number) => { setSmall(size); return c.measureText(text).width - 0.28 * size; };
  const smallFor = (big: number) => Math.max(12 * scale, Math.min(big * 0.1, 24 * scale));

  // Side layout: each large word is a row; small words before the first go
  // to its left, the rest go to the right of the large word they follow.
  type Row = { big: string; left?: string; right?: string };
  const rows: Row[] = [];
  let pendingLeft: string | undefined;
  for (const part of upper) {
    if (part.big) {
      rows.push({ big: part.text, left: rows.length ? undefined : pendingLeft });
      pendingLeft = undefined;
    } else if (rows.length) {
      const row = rows[rows.length - 1]!;
      row.right = row.right ? `${row.right} ${part.text}` : part.text;
    } else {
      pendingLeft = part.text;
    }
  }

  const margin = 0.05 * width;
  // Large enough to feel the buildings pass in front of it, never wider than
  // most of the screen.
  let big = Math.min(0.25 * height, 0.2 * width);
  const widest = (size: number) => Math.max(...bigs.map((part) => bigWidth(part.text, size)));
  while (widest(big) > 0.62 * width && big > 20) big *= 0.96;
  let small = smallFor(big);
  const gap = () => big * 0.12;
  const fitsSide = rows.every((row) => {
    const w = bigWidth(row.big, big);
    const left = row.left ? smallWidth(row.left, small) + gap() : 0;
    const right = row.right ? smallWidth(row.right, small) + gap() : 0;
    return width / 2 - w / 2 - left >= margin && width / 2 + w / 2 + right <= width - margin;
  });

  c.textBaseline = "alphabetic";
  c.fillStyle = INK;
  c.shadowColor = "rgba(20, 38, 70, 0.42)";
  c.shadowOffsetY = 2 * scale;

  const capOf = (size: number) => { setBig(size); return c.measureText("H").actualBoundingBoxAscent; };
  const smallCapOf = (size: number) => { setSmall(size); return c.measureText("H").actualBoundingBoxAscent; };
  const drawBig = (text: string, x: number, y: number) => {
    setBig(big); c.shadowBlur = 26 * scale; c.textAlign = "left"; c.fillText(text, x, y);
  };
  const drawSmall = (text: string, x: number, y: number, align: CanvasTextAlign) => {
    setSmall(small); c.shadowBlur = 12 * scale; c.textAlign = align;
    // Right-aligned text would carry the trailing letter space; shift it back.
    c.fillText(text, align === "right" ? x + 0.28 * small : x, y);
  };

  if (fitsSide) {
    const cap = capOf(big);
    const smallCap = smallCapOf(small);
    const rowGap = cap * 0.16;
    const stampGap = small * 2.2;
    const blockHeight = smallCap + stampGap + rows.length * cap + (rows.length - 1) * rowGap;
    let baseline = height * 0.47 - blockHeight / 2 + smallCap;
    if (stamp) drawSmall(stamp, width / 2 + 0.14 * small, baseline, "center");
    baseline += stampGap + cap;
    rows.forEach((row, index) => {
      const w = bigWidth(row.big, big);
      const x = width / 2 - w / 2;
      drawBig(row.big, x, baseline);
      const capTop = baseline - cap + smallCap;
      if (row.left) drawSmall(row.left, x - gap(), capTop, "right");
      // The last row's trailing words sit on its baseline, the others on its cap line.
      if (row.right) drawSmall(row.right, x + w + gap(), index === rows.length - 1 ? baseline : capTop, "left");
      baseline += cap + rowGap;
    });
    return (baseline - rowGap - cap) / height;
  }

  // Stacked: every run on its own centred line, the large words nearly the
  // full width of a phone.
  big = Math.min(0.25 * height, 0.34 * width);
  while (widest(big) > 0.86 * width && big > 20) big *= 0.96;
  small = smallFor(big);
  let cap = capOf(big);
  let smallCap = smallCapOf(small);
  const lineGap = () => small * 1.1;
  const stackHeight = () => {
    let h = stamp ? smallCap + lineGap() * 1.6 : 0;
    upper.forEach((part, index) => {
      h += part.big ? cap : smallCap;
      if (index < upper.length - 1) h += lineGap();
    });
    return h;
  };
  while (stackHeight() > 0.6 * height && big > 20) {
    big *= 0.95;
    small = smallFor(big);
    cap = capOf(big);
    smallCap = smallCapOf(small);
  }
  let top = height * 0.46 - stackHeight() / 2;
  if (stamp) {
    drawSmall(stamp, width / 2 + 0.14 * small, top + smallCap, "center");
    top += smallCap + lineGap() * 1.6;
  }
  for (const part of upper) {
    if (part.big) {
      const w = bigWidth(part.text, big);
      drawBig(part.text, width / 2 - w / 2, top + cap);
      top += cap + lineGap();
    } else {
      drawSmall(part.text, width / 2 + 0.14 * small, top + smallCap, "center");
      top += smallCap + lineGap();
    }
  }
  return (top - lineGap()) / height;
}
