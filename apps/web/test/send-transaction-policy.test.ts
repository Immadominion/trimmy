import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {checkSendTransaction} from '../src/product/money/send-transaction-policy.js';
import {parseTransferReview} from '../src/product/money/wallet-transfer-client.js';
const fixtures: {name:string;accepted:boolean;envelope:unknown}[] = JSON.parse(await readFile(
  new URL('../../../tool/testing/fixtures/client-send-policy.json', import.meta.url), 'utf8'));
for (const fixture of fixtures) test(`offline send policy: ${fixture.name}`, async () => {
  const review = parseTransferReview(fixture.envelope);
  if (fixture.accepted) await checkSendTransaction(review);
  else await assert.rejects(checkSendTransaction(review));
});
