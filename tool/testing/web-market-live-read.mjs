import {createHash} from 'node:crypto';
import {chmod, mkdir, writeFile} from 'node:fs/promises';
import {dirname} from 'node:path';
import {fileURLToPath} from 'node:url';

import {buildApp} from '../../apps/api/src/app.ts';
import {RaydiumStockQuoteReader} from '../../apps/api/src/raydium-stock-quotes.ts';
import {TokensStockHistory} from '../../apps/api/src/stock-history.ts';
import {StockResearchClient} from '../../apps/web/src/markets/client.ts';
import {RESEARCH_AAPLX_MINT} from '../../apps/web/src/markets/estimate.ts';

const artifactUrl = new URL('../../artifacts/verification/WEB_LIVE_MARKET_READS.json', import.meta.url);
const expectedArgs = new Set(['--live-read-only']);

function fail(message) {
  throw new Error(message);
}

function hashProjection(value) {
  return createHash('sha256').update(JSON.stringify(value)).digest('hex');
}

async function main() {
  if (process.argv.length !== 3 || !expectedArgs.has(process.argv[2])) {
    fail('Run with --live-read-only to permit exactly one history read and one Raydium compute read.');
  }
  const apiKey = process.env.TOKENS_API_KEY;
  if (typeof apiKey !== 'string' || apiKey.length < 8 || apiKey.length > 512 || !/^[\x21-\x7e]+$/u.test(apiKey)) {
    fail('TOKENS_API_KEY is missing or invalid.');
  }

  const app = buildApp({
    logLevel: 'silent',
    stockHistory: new TokensStockHistory({apiKey}),
    raydiumStockQuotes: new RaydiumStockQuoteReader(),
  });
  let client;
  try {
    const origin = await app.listen({host: '127.0.0.1', port: 0});
    client = new StockResearchClient({
      apiOrigin: origin,
      allowLoopbackForTests: true,
      timeoutMs: 10_000,
    });
    const nowMs = Date.now();
    const to = Math.floor(nowMs / 1_000 / 3_600) * 3_600;
    const from = to - 7 * 86_400;
    const request = Object.freeze({
      assetId: 'apple',
      variantMint: RESEARCH_AAPLX_MINT,
      interval: '1H',
      fromUnixSeconds: String(from),
      toUnixSeconds: String(to),
    });
    const history = await client.history(request);
    const quote = await client.raydiumQuote(Object.freeze({
      assetId: 'apple',
      variantMint: RESEARCH_AAPLX_MINT,
      side: 'buy',
      amountRaw: '10000000',
    }));

    const safe = Object.freeze({
      schemaVersion: 1,
      observedAt: new Date().toISOString(),
      path: 'loopback API -> live providers -> strict web client',
      history: Object.freeze({
        provider: history.provider,
        assetId: history.assetId,
        variantMint: history.variantMint,
        interval: history.interval,
        candleCount: history.candles.length,
        numericEncoding: history.numericEncoding,
        priceUnit: history.priceUnit,
        volumeUnit: history.volumeUnit,
        canonicalEquityHistory: history.canonicalEquityHistory,
        executionEnabled: history.executionEnabled,
        bodyProjectionSha256: hashProjection(history),
      }),
      raydium: Object.freeze({
        provider: quote.provider,
        assetId: quote.assetId,
        variantMint: quote.variantMint,
        side: quote.side,
        inputSymbol: quote.input.symbol,
        outputSymbol: quote.output.symbol,
        hopCount: quote.route.hopCount,
        comparisonOnly: quote.comparisonOnly,
        executionEnabled: quote.executionEnabled,
        executable: quote.executable,
        bodyProjectionSha256: hashProjection(quote),
      }),
    });
    const path = fileURLToPath(artifactUrl);
    await mkdir(dirname(path), {recursive: true});
    await writeFile(path, `${JSON.stringify(safe, null, 2)}\n`, {mode: 0o600});
    await chmod(path, 0o600);
    process.stdout.write(`${JSON.stringify({
      historyStatus: 'accepted',
      historyCandles: safe.history.candleCount,
      raydiumStatus: 'accepted',
      raydiumHops: safe.raydium.hopCount,
      executionEnabled: false,
    })}\n`);
  } finally {
    client?.close();
    await app.close();
  }
}

try {
  await main();
} catch {
  process.stderr.write('The bounded live web market read failed.\n');
  process.exitCode = 1;
}
