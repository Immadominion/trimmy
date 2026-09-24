/**
 * One live, read-only fetch of the public PreStocks catalog through the strict
 * reader, to prove the boundary works end to end against the real provider. It
 * writes a record with the listings' symbols, mints and premium, never a price
 * presented as tradable and never a key. Read only: no wallet, no transaction.
 */
import { writeFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import { HttpPreStocks, PreStocksError } from '../../apps/api/src/prestocks-reader.ts';

export async function runPreStocksLive() {
  const catalog = await new HttpPreStocks().catalog();
  return {
    schemaVersion: 1, kind: 'prestocks_live_read', recordedAt: new Date().toISOString(),
    provider: catalog.provider, sourceUrl: catalog.sourceUrl, observedAt: catalog.observedAt,
    priceKind: catalog.priceKind, executionEnabled: catalog.executionEnabled, eligibility: catalog.eligibility,
    mintVerification: catalog.mintVerification, listingCount: catalog.listings.length,
    listings: catalog.listings.map(item => ({symbol: item.symbol, name: item.name,
      contractAddress: item.contractAddress, premiumBasisPoints: item.premiumBasisPoints})),
    passed: true,
  };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (process.argv.length !== 3 || process.argv[2] !== '--live-read') {
    console.log(JSON.stringify({passed: false, errorCode: 'PRESTOCKS_LIVE_ARGUMENTS_INVALID'}));
    process.exitCode = 1;
  } else {
    try {
      const record = await runPreStocksLive();
      await writeFile(new URL('../../artifacts/verification/PRESTOCKS_LIVE_READ.json', import.meta.url),
        `${JSON.stringify(record, null, 2)}\n`);
      console.log(JSON.stringify({passed: record.passed, listingCount: record.listingCount,
        symbols: record.listings.map(l => l.symbol)}));
    } catch (error) {
      console.log(JSON.stringify({passed: false, errorCode: error instanceof PreStocksError ? error.code : 'PRESTOCKS_LIVE_FAILED'}));
      process.exitCode = 1;
    }
  }
}
