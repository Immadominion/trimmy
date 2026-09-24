import {useCallback, useState} from 'react';
import type {ReactElement} from 'react';
import type {StockResearchClient} from './client.js';
import type {StockResearchConfig} from './config.js';
import {preStocksIssueMessage, premiumLabel, StockResearchError} from './prestocks.js';
import type {PreStockListing, PreStocksCatalog} from './prestocks.js';

export interface PreStocksPanelProps {
  readonly config: StockResearchConfig;
  /** Present only when the configuration is enabled; the panel owns the read. */
  readonly client: StockResearchClient | null;
}

type PanelState =
  | {readonly phase: 'idle'}
  | {readonly phase: 'loading'}
  | {readonly phase: 'ready'; readonly catalog: PreStocksCatalog}
  | {readonly phase: 'error'; readonly message: string};

function shortMint(value: string): string {
  return value.length <= 12 ? value : `${value.slice(0, 4)}…${value.slice(-4)}`;
}

function ListingRow({listing}: {readonly listing: PreStockListing}): ReactElement {
  const premium = premiumLabel(listing.premiumBasisPoints);
  return (
    <li className="prestocks-row">
      <div className="prestocks-row-head">
        <span className="prestocks-symbol">{listing.symbol}</span>
        <span className="prestocks-name">{listing.name}</span>
        {premium !== null && <span className="prestocks-premium">{premium} vs mark</span>}
      </div>
      <p className="prestocks-description">{listing.description}</p>
      <dl className="prestocks-figures">
        <div><dt>Token price</dt><dd>{listing.tokenPrice}</dd></div>
        <div><dt>Mark price</dt><dd>{listing.markPrice}</dd></div>
        <div><dt>Implied valuation</dt><dd>{listing.impliedValuation}</dd></div>
        <div><dt>Supply</dt><dd>{listing.supply}</dd></div>
        <div><dt>Mint</dt><dd title={listing.contractAddress}>{shortMint(listing.contractAddress)}</dd></div>
      </dl>
      <a className="prestocks-link" href={listing.externalUrl} target="_blank" rel="noreferrer noopener">
        Read about {listing.symbol}
      </a>
    </li>
  );
}

/**
 * A read-only panel of PreStocks tokenized pre-IPO stocks. It loads only when
 * asked, shows indicative marks as the provider's own figures, and never offers
 * a buy, a balance or an amount to trade.
 */
export function PreStocksPanel({config, client}: PreStocksPanelProps): ReactElement | null {
  const [state, setState] = useState<PanelState>({phase: 'idle'});

  const load = useCallback(async () => {
    if (!client) { setState({phase: 'error', message: preStocksIssueMessage('PRESTOCKS_UNAVAILABLE')}); return; }
    setState({phase: 'loading'});
    try {
      const catalog = await client.preStocks();
      setState({phase: 'ready', catalog});
    } catch (error) {
      const code = error instanceof StockResearchError ? error.code : 'PRESTOCKS_PROVIDER_UNAVAILABLE';
      setState({phase: 'error', message: preStocksIssueMessage(code)});
    }
  }, [client]);

  if (config.kind !== 'enabled') return null;

  return (
    <section className="prestocks-panel" aria-label="Pre-IPO stocks">
      <div className="prestocks-header">
        <h2>Pre-IPO stocks</h2>
        <span className="prestocks-pill">Read-only</span>
      </div>
      <p className="prestocks-lede">
        Tokenized pre-IPO companies from PreStocks. These are indicative marks for learning, not prices you can trade here.
      </p>
      <button type="button" className="prestocks-load" onClick={() => { void load(); }}
        disabled={state.phase === 'loading'}>
        {state.phase === 'ready' ? 'Check again' : state.phase === 'loading' ? 'Loading…' : 'Load pre-IPO stocks'}
      </button>
      {state.phase === 'error' && <p className="prestocks-issue" role="status">{state.message}</p>}
      {state.phase === 'ready' && (
        <>
          <ul className="prestocks-list">
            {state.catalog.listings.map(listing => <ListingRow key={listing.contractAddress} listing={listing}/>)}
          </ul>
          <p className="prestocks-notice">{state.catalog.notice}</p>
        </>
      )}
    </section>
  );
}
