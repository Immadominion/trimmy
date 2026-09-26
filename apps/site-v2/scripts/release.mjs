/**
 * Prepares dist/ for trimmy.xyz after `vite build`: leaves out files the
 * landing page never requests, then reports what will be uploaded.
 *
 * - world/, studies/: only the local /world-study review uses them.
 * - audio/music.mp3, audio/floor.mp3: the page plays reading-piano.mp3 and
 *   floor-quiet.mp3 in their place (see SoundSwitch.tsx and Ambience.tsx).
 *
 * Deploy with: npx vercel deploy dist --prod (project trimmy-site).
 */
import { readdir, rm, stat } from "node:fs/promises";

const dist = new URL("../dist/", import.meta.url);
const unused = ["world", "studies", "audio/music.mp3", "audio/floor.mp3"];
for (const path of unused) await rm(new URL(path, dist), { recursive: true, force: true });

let files = 0;
let bytes = 0;
async function walk(url) {
  for (const entry of await readdir(url, { withFileTypes: true })) {
    const child = new URL(entry.name + (entry.isDirectory() ? "/" : ""), url);
    if (entry.isDirectory()) await walk(child);
    else { files++; bytes += (await stat(child)).size; }
  }
}
await walk(dist);
console.log(`dist/ ready for trimmy.xyz: ${files} files, ${(bytes / 1e6).toFixed(1)} MB.`);
