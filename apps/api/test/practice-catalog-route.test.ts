import assert from 'node:assert/strict';
import { test } from 'node:test';
import { buildApp } from '../src/app.js';

test('public practice catalog advertises the ordered authored versioned content without enabling storage', async () => {
  const app = buildApp({logger: false});
  try {
    const response = await app.inject({method: 'GET', url: '/v1/practice/catalog'});
    assert.equal(response.statusCode, 200, response.body);
    const body = response.json();
    assert.equal(body.schemaVersion, 2);
    assert.equal(body.currentPayloadVersion, 6);
    assert.deepEqual(body.supportedPayloadVersions, [3, 4, 5, 6]);
    assert.equal(body.contentVersion, '2026-09-15.1');
    assert.equal(body.activities.length, 14);
    assert.equal(body.activities[0].prerequisiteId, null);
    for (const [index, activity] of body.activities.entries()) {
      assert.equal(activity.floor, index < 4 ? 1 : index < 8 ? 2 : index < 11 ? 3 : 4);
      assert.ok(activity.choiceIds.includes(activity.correctChoiceId));
      assert.ok(activity.acceptedChoiceIds.includes(activity.correctChoiceId));
      if (index > 0) assert.equal(activity.prerequisiteId, body.activities[index - 1].id);
      if (index >= 11) assert.equal(activity.introducedIn, 6);
      else if (index >= 8) assert.equal(activity.introducedIn, 5);
    }
    assert.equal(body.activities[7].id, 'prepare-the-comparison');
    assert.equal(body.activities[13].id, 'write-the-plan');
    assert.deepEqual(body.activities[8].acceptedChoiceIds, [
      'share-qualified-sales', 'request-missing-costs',
    ]);
    assert.equal(response.body.includes('userId'), false);
    assert.equal((await app.inject('/v1/practice/progress')).statusCode, 503);
    assert.equal((await app.inject({method: 'GET', url: '/v1/practice/catalog?userId=private'})).statusCode, 400);
    assert.equal((await app.inject({method: 'PUT', url: '/v1/practice/catalog', payload: {}})).statusCode, 503);
  } finally { await app.close(); }
});
