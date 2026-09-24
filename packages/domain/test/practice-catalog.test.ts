import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { practiceCatalogActivityIds, practiceCatalogById, practiceCatalogContentVersion,
  practiceCatalogFloors, practiceCatalogPayloadVersion, practiceCatalogSchemaVersion } from '../src/practice-catalog.generated.js';

test('compiled catalog retains every field from the versioned JSON and is deeply immutable', () => {
  const source = JSON.parse(readFileSync(new URL('../../../content/practice-catalog.json', import.meta.url), 'utf8')) as {
    schemaVersion: number; contentVersion: string; payloadVersion: number;
    floors: {number: number; title: string}[];
    activities: {id: string; floor: number; title: string; correctChoiceId: string;
      acceptedChoiceIds: string[]; choiceIds: string[]; introducedIn: number; prerequisiteId: string | null}[];
  };
  assert.equal(practiceCatalogSchemaVersion, source.schemaVersion);
  assert.equal(practiceCatalogContentVersion, source.contentVersion);
  assert.equal(practiceCatalogPayloadVersion, source.payloadVersion);
  assert.deepEqual(practiceCatalogFloors, Object.fromEntries(source.floors.map(floor => [floor.number, floor.title])));
  assert.deepEqual(practiceCatalogActivityIds, source.activities.map(entry => entry.id));
  assert.deepEqual(practiceCatalogActivityIds.map(id => practiceCatalogById[id]), source.activities);
  assert.ok(Object.isFrozen(practiceCatalogById));
  assert.ok(Object.isFrozen(practiceCatalogActivityIds));
  for (const entry of Object.values(practiceCatalogById)) {
    assert.ok(Object.isFrozen(entry)); assert.ok(Object.isFrozen(entry.choiceIds));
    assert.ok(Object.isFrozen(entry.acceptedChoiceIds));
    assert.throws(() => Object.assign(entry, {title: 'Mutated release'}), TypeError);
  }
});
