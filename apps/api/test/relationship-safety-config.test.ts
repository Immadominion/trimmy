import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readRelationshipSafetyEnabled, relationshipSafetyAvailable} from
  '../src/relationship-safety-config.js';

test('relationship safety is explicitly parsed and defaults off', () => {
  assert.equal(readRelationshipSafetyEnabled({}), false);
  assert.equal(readRelationshipSafetyEnabled({TRIMMY_RELATIONSHIP_SAFETY_ENABLED: ''}), false);
  assert.equal(readRelationshipSafetyEnabled({TRIMMY_RELATIONSHIP_SAFETY_ENABLED: 'false'}), false);
  assert.equal(readRelationshipSafetyEnabled({TRIMMY_RELATIONSHIP_SAFETY_ENABLED: 'true'}), true);
  for (const value of ['TRUE', 'False', '1', 'yes', ' true ', '0']) {
    assert.throws(() => readRelationshipSafetyEnabled({TRIMMY_RELATIONSHIP_SAFETY_ENABLED: value}),
      /must be true or false/u);
  }
});

test('configuration requires an independent live readiness proof', async () => {
  assert.equal(await relationshipSafetyAvailable(false, async () => true), false);
  assert.equal(await relationshipSafetyAvailable(true), false);
  assert.equal(await relationshipSafetyAvailable(true, async () => false), false);
  assert.equal(await relationshipSafetyAvailable(true, async () => true), true);
  assert.equal(await relationshipSafetyAvailable(true, async () => { throw new Error('private'); }), false);
});
