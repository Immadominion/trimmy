import { cp, mkdir, readFile, rm, stat, writeFile } from 'node:fs/promises';

const concept = new URL('./concept/', import.meta.url);
const legacy = new URL('./public/', import.meta.url);
const output = new URL('./live-dist/', import.meta.url);

const runtimeFiles = [
  'styles.css', 'fluid.css', 'room-details.css', 'motion.js', 'ada-actor.js',
  'ada-rig-data.js', 'liquid-token.js', 'paper-flight.js', 'scroll-scenes.js',
  'room-details.js', 'assets/mark.png', 'assets/token.webp',
  'activity-feedback.js', 'activity-feedback.css',
  'assets/ada-poster.webp', 'assets/ada-atlas.webp',
  'assets/fonts/BricolageGrotesque-Latin.woff2',
  'assets/fonts/BricolageGrotesque-OFL.txt',
  'assets/fonts/Manrope-Variable.ttf', 'assets/fonts/Manrope-OFL.txt',
];

await rm(output, { recursive: true, force: true });
await mkdir(output, { recursive: true });

let homepage = await readFile(new URL('index.html', concept), 'utf8');
homepage = homepage
  .replace('content="noindex,nofollow"', 'content="index,follow"')
  .replace(
    '  <meta name="description" content="Learn how stocks work in a mobile game. Join a fictional Wall Street firm, make decisions, and see what happens. Try a Trimmy activity.">',
    '  <meta name="description" content="Learn how stocks work in a mobile game. Join a fictional Wall Street firm, make decisions, and see what happens. Try a Trimmy activity.">\n  <link rel="canonical" href="https://trimmy.xyz/">\n  <meta property="og:title" content="Trimmy | The investing game">\n  <meta property="og:description" content="Learn how stocks work through short activities and a story you play on your phone.">\n  <meta property="og:url" content="https://trimmy.xyz/">\n  <meta property="og:type" content="website">\n  <meta property="og:image" content="https://trimmy.xyz/assets/token.webp">\n  <meta name="twitter:card" content="summary_large_image">',
  )
  .replace(/\n  <aside class="study-note"[\s\S]*?<\/aside>/, '');
await writeFile(new URL('index.html', output), homepage);

let bytes = Buffer.byteLength(homepage);
for (const file of runtimeFiles) {
  const target = new URL(file, output);
  await mkdir(new URL('./', target), { recursive: true });
  await cp(new URL(file, concept), target);
  bytes += (await stat(target)).size;
}
await cp(new URL('legal.css', concept), new URL('legal.css', output));
bytes += (await stat(new URL('legal.css', output))).size;
for (const path of ['privacy/index.html', 'terms/index.html', '404.html']) {
  let html = await readFile(new URL(path, legacy), 'utf8');
  html = html
    .replace('href="/favicon.svg" type="image/svg+xml"', 'href="/assets/mark.png" type="image/png"')
    .replace('href="/styles.css"', 'href="/legal.css"')
    .replace('href="/#the-experience"', 'href="/#the-game"')
    .replace('The experience</a', 'The game</a')
    .replace('content="#FAF9F6"', 'content="#EBE6FF"')
    .replaceAll('>trimmy<span aria-hidden="true">.</span>', '><img src="/assets/mark.png" width="39" height="39" alt="">trimmy')
    .replace('Learn. Question. Keep going.', 'Learn investing through play.');
  const target = new URL(path, output);
  await mkdir(new URL('./', target), { recursive: true });
  await writeFile(target, html);
  bytes += Buffer.byteLength(html);
}
for (const file of ['robots.txt', 'sitemap.xml']) {
  await cp(new URL(file, legacy), new URL(file, output));
  bytes += (await stat(new URL(file, output))).size;
}

const config = {
  framework: null,
  cleanUrls: true,
  trailingSlash: false,
  headers: [{
    source: '/(.*)',
    headers: [
      { key: 'X-Content-Type-Options', value: 'nosniff' },
      { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
      { key: 'Permissions-Policy', value: 'camera=(), microphone=(), geolocation=()' },
      { key: 'Content-Security-Policy', value: "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; font-src 'self'; connect-src 'none'; object-src 'none'; base-uri 'self'; frame-ancestors 'none'; form-action 'none'" },
    ],
  }],
};
const hostConfig = `${JSON.stringify(config, null, 2)}\n`;
await writeFile(new URL('vercel.json', output), hostConfig);
bytes += Buffer.byteLength(hostConfig);
console.log(`Built public Trimmy site: ${runtimeFiles.length + 8} files, ${bytes} uncompressed bytes.`);
