import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const landing = readFileSync(new URL('../../site/index.html', import.meta.url), 'utf8');
const interactions = readFileSync(new URL('../../site/assets/page.js', import.meta.url), 'utf8');
const styles = readFileSync(new URL('../../site/assets/page.css', import.meta.url), 'utf8');

test('the hero example is an explicit replayable three-state product demo', () => {
  assert.match(landing, /data-demo-state="watching"/);
  assert.match(landing, /<button[^>]+data-rule-replay/);
  assert.match(landing, /data-rule-stage="condition"/);
  assert.match(landing, /data-rule-stage="action"/);
  assert.match(landing, /data-rule-receipt/);

  for (const state of ['watching', 'met', 'acted']) {
    assert.match(interactions, new RegExp(`\\b${state}: \\{`));
  }
  assert.match(interactions, /threshold: 0\.55/);
  assert.match(interactions, /ruleDemoUserStarted/);
  assert.match(interactions, /heroObserver\?\.disconnect\(\)/);
});

test('all four builder choices are visible controls and preserve the real preset handoff', () => {
  assert.doesNotMatch(landing, /<select\b/);

  for (const preset of ['below', 'swap', 'vault', 'private']) {
    assert.match(
      landing,
      new RegExp(`<input[^>]+name="preset"[^>]+value="${preset}"[^>]+data-builder-preset`)
    );
  }

  assert.match(interactions, /builderChoices\.forEach/);
  assert.match(interactions, /builderWindow\.animate/);
  assert.match(interactions, /builderContent\?\.animate/);
});

test('interaction assets use a matching cache-busting version', () => {
  const cssVersion = landing.match(/page\.css\?v=([^"']+)/)?.[1];
  const scriptVersion = landing.match(/page\.js\?v=([^"']+)/)?.[1];

  assert.ok(cssVersion);
  assert.equal(scriptVersion, cssVersion);
});

test('the desktop rule card cannot cover the XRP headline block', () => {
  assert.match(styles, /@media \(min-width:56\.0625rem\)/);
  assert.match(styles, /--hero-headline-reserve:31\.5rem/);
  assert.match(styles, /\.hero \.poster-line--split\{margin-left:auto;margin-right:var\(--hero-headline-reserve\)\}/);
  assert.match(styles, /\.hero-rule\{bottom:-\.75rem\}/);
  assert.match(styles, /@media \(min-width:68\.0625rem\)/);
  assert.match(styles, /--hero-headline-reserve:35rem/);
});
