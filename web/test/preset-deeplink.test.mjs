import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url));
const page = readFileSync(join(HERE, '..', 'index.html'), 'utf8');
const armScript = readFileSync(join(HERE, '..', 'arm.js'), 'utf8');
const ruleShapeStart = armScript.indexOf('// ---- rule shape');
const ruleBuilderStart = armScript.indexOf('function ruleFromForm()', ruleShapeStart);

assert.notEqual(ruleShapeStart, -1, 'rule-shape script marker');
assert.notEqual(ruleBuilderStart, -1, 'rule builder function');

const presetScript = armScript.slice(ruleShapeStart, ruleBuilderStart);

test('the arming page loads its entry module from a CSP-compatible same-origin file', () => {
  assert.match(page, /<script type="module" src="\.\/arm\.js"><\/script>/);
  assert.doesNotMatch(page, /<script type="module">/);
});

test('current rules approve only what the rule may spend, not a result-asset fee cap', () => {
  assert.match(armScript, /allowance:\s*rule\.totalSellAmount,/);
  assert.doesNotMatch(armScript, /allowance:\s*rule\.totalSellAmount\s*\+\s*rule\.keeperFeeBudget/);
  assert.doesNotMatch(armScript, /Reserved for whoever runs it/);
});

function loadPreset(search) {
  const listeners = new Map();
  const priceField = { style: {} };
  const elements = {
    preset: {
      value: 'below',
      addEventListener(type, listener) {
        listeners.set(type, listener);
      },
    },
    priceRow: { style: {} },
    everyField: { style: {} },
    amount: { value: '0.01' },
    priceLabel: { textContent: '' },
    price: { parentElement: priceField },
  };

  runInNewContext(presetScript, {
    $: (id) => elements[id],
    URLSearchParams,
    window: { location: { search } },
  });

  return { elements, listeners, priceField };
}

test('landing deep links select only supported presets and initialise their fields', () => {
  for (const preset of ['below', 'swap', 'vault', 'private']) {
    const { elements, priceField } = loadPreset(`?preset=${preset}`);
    const showsPrice = preset === 'below' || preset === 'private';
    const showsSchedule = preset === 'swap' || preset === 'vault';

    assert.equal(elements.preset.value, preset, preset);
    assert.equal(elements.priceRow.style.display, showsPrice ? '' : 'none', preset);
    assert.equal(priceField.style.display, showsPrice ? '' : 'none', preset);
    assert.equal(elements.everyField.style.display, showsSchedule ? '' : 'none', preset);
    assert.equal(elements.amount.value, preset === 'vault' ? '1' : '0.01', preset);
    assert.equal(
      elements.priceLabel.textContent,
      preset === 'private'
        ? 'Secret price — never published on chain (FLR per XRP)'
        : 'Sell if 1 XRP falls to (FLR)',
      preset,
    );
  }
});

test('unknown preset deep links retain the safe default', () => {
  for (const search of ['', '?preset=price', '?preset=BELOW', '?preset=__proto__']) {
    const { elements, priceField } = loadPreset(search);

    assert.equal(elements.preset.value, 'below', search);
    assert.equal(elements.priceRow.style.display, '', search);
    assert.equal(priceField.style.display, '', search);
    assert.equal(elements.everyField.style.display, 'none', search);
    assert.equal(elements.amount.value, '0.01', search);
  }
});

test('changing the selected preset reuses the initial visibility update', () => {
  const { elements, listeners, priceField } = loadPreset('?preset=swap');

  elements.preset.value = 'private';
  listeners.get('change')();

  assert.equal(elements.priceRow.style.display, '');
  assert.equal(priceField.style.display, '');
  assert.equal(elements.everyField.style.display, 'none');
  assert.equal(elements.amount.value, '0.01');
  assert.equal(
    elements.priceLabel.textContent,
    'Secret price — never published on chain (FLR per XRP)',
  );
});
