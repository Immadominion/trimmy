/** Configure an open-font public checkout without redistributing commercial fonts.
 * Leaves a licensed working copy unchanged. Run before Flutter or web builds.
 */
import {existsSync, readFileSync, writeFileSync, copyFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {join, dirname} from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
const manifestPath = join(root, 'apps/mobile/pubspec.yaml');
let manifest = readFileSync(manifestPath, 'utf8');
let changed = 0;
manifest = manifest.replace(/assets\/fonts\/dejanire\/DejanireSans-[A-Za-z]+\.otf/g, path => {
  if (existsSync(join(dirname(manifestPath), path))) return path;
  changed++;
  return 'assets/fonts/manrope/Manrope-Variable.ttf';
});
if (changed) writeFileSync(manifestPath, manifest);

const cssPath = join(root, 'apps/web/src/product/product.css');
let css = readFileSync(cssPath, 'utf8');
let webChanged = 0;
css = css.replace(/url\('\/trimmy\/fonts\/(DejanireSans-[A-Za-z]+\.otf)'\) format\('opentype'\)/g, (match, file) => {
  if (existsSync(join(root, 'apps/web/public/trimmy/fonts', file))) return match;
  webChanged++;
  return "url('/fonts/Manrope-Variable.ttf') format('truetype')";
});
if (webChanged) writeFileSync(cssPath, css);
console.log(`Public font fallback: ${changed} Flutter and ${webChanged} web references updated. Licensed files, when present, are untouched.`);

// Use the project's own synthesis cues where source-distribution restrictions
// exclude the branded library mixes. Never overwrite an existing local mix.
const audio = join(root, 'apps/mobile/assets/audio');
for (const [target, source] of [
  ['wall_street_orbit_v4.wav', 'arrival.wav'],
  ['welcome_press_v1.wav', 'soft_tap.wav'],
]) {
  if (!existsSync(join(audio, target))) copyFileSync(join(audio, source), join(audio, target));
}

// The public marketing preview has no licensed crowd ambience. Supply an
// explicitly silent preview track; the CC BY piano recording stays intact.
const siteAudio = join(root, 'apps/site-v2/public/audio');
if (!existsSync(join(siteAudio, 'floor-quiet.mp3'))) {
  const samples = 48000 * 2;
  const wav = Buffer.alloc(44 + samples * 2);
  wav.write('RIFF'); wav.writeUInt32LE(wav.length - 8, 4); wav.write('WAVEfmt ', 8);
  wav.writeUInt32LE(16, 16); wav.writeUInt16LE(1, 20); wav.writeUInt16LE(1, 22);
  wav.writeUInt32LE(48000, 24); wav.writeUInt32LE(96000, 28);
  wav.writeUInt16LE(2, 32); wav.writeUInt16LE(16, 34);
  wav.write('data', 36); wav.writeUInt32LE(samples * 2, 40);
  writeFileSync(join(siteAudio, 'floor-public.wav'), wav);
  const ambience = join(root, 'apps/site-v2/src/components/Ambience.tsx');
  if (existsSync(ambience)) {
    writeFileSync(ambience, readFileSync(ambience, 'utf8').replaceAll('/audio/floor-quiet.mp3', '/audio/floor-public.wav'));
  }
}
