/**
 * Submitted real-money orders, newest first, with explorer links. Pending
 * rows are reconciled by id (reading chain status only, never dispatching)
 * while the page is visible. Amounts are reviewed quotes, not final fills.
 * Mirrors mobile's live_trade_history.dart.
 */
import {useCallback, useEffect, useRef, useState} from 'react';
import type {CompanyIdentity} from '../company-identity.js';
import {CompanyLogo} from '../ui.js';
import {formatRawUnits, rawDecimal, ShareScale} from './amounts.js';
import {explorerUrl, LiveOrderError, type TradeRecord, type TradeStatus} from './live-order-client.js';
import {useMoney} from './money-api.js';
import {coherentHoldings} from './wallet-controller.js';

const STATUS: Readonly<Record<TradeStatus, string>> = {pending: 'Confirming', confirmed: 'Confirmed', failed: 'Not completed', expired: 'Expired'};
const pad = (value: number) => String(value).padStart(2, '0');
function when(value: string): string {
  const date = new Date(value);
  return `${date.getDate()}/${date.getMonth() + 1}/${date.getFullYear()} · ${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

export function TradeHistoryScreen({onBack, onOpenAsset, identities}: {
  onBack(): void; onOpenAsset?(assetId: string, mint: string): void; identities?: ReadonlyMap<string, CompanyIdentity>;
}) {
  const money = useMoney();
  const client = money.orders;
  const [orders, setOrders] = useState<readonly TradeRecord[]>([]);
  const [cursor, setCursor] = useState<string | null>(null);
  const [loading, setLoading] = useState(true), [more, setMore] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [expanded, setExpanded] = useState<ReadonlySet<string>>(new Set());
  const generation = useRef(0), olderPages = useRef(false), ordersRef = useRef(orders); ordersRef.current = orders;
  const holdings = coherentHoldings(money.wallet);
  const scaleFor = (order: TradeRecord) => {
    const held = holdings?.stockTokens.find(token => token.mint === order.mint && token.decimals === order.decimals);
    return held ? ShareScale.fromDisplay(order.decimals, held.amountRaw, held.displayAmount) : ShareScale.plain(order.decimals);
  };
  const amount = (order: TradeRecord, raw: string, usdc: boolean) => usdc ? `${formatRawUnits(raw, 6) ?? rawDecimal(raw, 6)} USDC` : `${scaleFor(order).exact(raw)} ${order.symbol}`;

  const refresh = useCallback(async (silent = false) => {
    if (!client) {setLoading(false); setError('Sign in again to see your trades.'); return;}
    const turn = ++generation.current;
    if (!silent) {setLoading(ordersRef.current.length === 0); setError(null); setMore(false);}
    try {
      const page = await client.history();
      if (turn !== generation.current) return;
      if (silent && olderPages.current) {
        const ids = new Set(page.orders.map(order => order.id));
        setOrders(prior => [...page.orders, ...prior.filter(order => !ids.has(order.id))]);
      } else {setOrders(page.orders); setCursor(page.nextCursor); olderPages.current = false;}
      setError(null);
    } catch (reason) {
      if (turn !== generation.current) return;
      if (!silent) setError(reason instanceof LiveOrderError && reason.code === 'ACCOUNT_REQUIRED' ? 'Sign in again to see your trades.' : 'Couldn’t load your trades. Try again.');
    } finally {if (turn === generation.current) setLoading(false);}
  }, [client]);
  useEffect(() => {void refresh();}, [refresh]);

  // Reconcile up to three pending orders every 10 seconds, then re-read the first page quietly.
  const pending = orders.some(order => order.status === 'pending');
  useEffect(() => {
    if (!client || !pending) return;
    let running = false;
    const timer = window.setInterval(() => {
      if (running || more || document.visibilityState === 'hidden') return;
      running = true;
      const turn = generation.current;
      void (async () => {
        for (const order of ordersRef.current.filter(row => row.status === 'pending').slice(0, 3)) {
          try {
            const status = await client.order(order.id);
            if (turn !== generation.current || !status || status.id !== order.id || status.status === 'reviewed' || status.status === order.status) continue;
            setOrders(prior => prior.map(row => row.id === order.id ? {...row, status: status.status as TradeStatus} : row));
          } catch { /* Keep it pending; never infer a fill. */ }
        }
        if (turn === generation.current) await refresh(true);
      })().finally(() => {running = false;});
    }, 10_000);
    return () => clearInterval(timer);
  }, [client, pending, more, refresh]);

  async function loadMore() {
    if (!client || more || loading || cursor === null) return;
    const turn = ++generation.current;
    setMore(true); setError(null);
    try {
      const page = await client.history(cursor);
      if (turn !== generation.current) return;
      setOrders(prior => {const ids = new Set(prior.map(order => order.id)); return [...prior, ...page.orders.filter(order => !ids.has(order.id))];});
      setCursor(page.nextCursor); olderPages.current = true;
    } catch (reason) {
      if (turn === generation.current) setError(reason instanceof LiveOrderError && reason.code === 'ACCOUNT_REQUIRED' ? 'Sign in again to see your trades.' : 'Couldn’t load more trades. Try again.');
    } finally {if (turn === generation.current) setMore(false);}
  }

  return <section className="trade-history" aria-label="Your trades">
    <button className="company-back" onClick={onBack}>← Back to your desk</button>
    <div className="page-intro"><h1>Your trades</h1><p className="money-badge real">Real money</p></div>
    {loading && <div className="loading" role="status"><span className="loading-dot" aria-hidden="true"/>Loading your trades…</div>}
    {!loading && !orders.length && error === null && <div className="empty-page"><h2>Your first trade starts here</h2><p>Your orders will appear here.</p></div>}
    <div className="history-list">{orders.map(order => {
      const open = expanded.has(order.id), name = identities?.get(order.assetId)?.name ?? order.name;
      return <article key={order.id} className={`history-row ${order.status}`}>
        <button className="history-summary" aria-expanded={open} onClick={() => setExpanded(prior => {const next = new Set(prior); if (open) next.delete(order.id); else next.add(order.id); return next;})}>
          <CompanyLogo name={name} url={identities?.get(order.assetId)?.imageUrl ?? null} size={40}/>
          <span className="history-main"><strong>{order.buy ? 'Buy' : 'Sell'} {order.symbol}</strong><small>{amount(order, order.inputAmountRaw, order.buy)}</small></span>
          <span className="history-meta"><strong className={`history-status ${order.status}`}>{STATUS[order.status]}</strong><small>{when(order.createdAt)}</small></span>
        </button>
        {open && <div className="history-detail">
          <dl><div><dt>Quoted output</dt><dd>{amount(order, order.quotedOutputAmountRaw, !order.buy)}</dd></div>
            <div><dt>Minimum output</dt><dd>{amount(order, order.minimumOutputAmountRaw, !order.buy)}</dd></div></dl>
          <p className="trade-caption">Order estimates. See the transaction for the final amounts.</p>
          <div className="history-links"><a className="text-button" href={explorerUrl(order)} target="_blank" rel="noreferrer noopener">{order.rfq ? 'View wallet activity ↗' : 'View transaction ↗'}</a>
            {onOpenAsset && <button className="text-button" onClick={() => onOpenAsset(order.assetId, order.mint)}>Open stock</button>}</div>
        </div>}
      </article>;
    })}</div>
    {error !== null && <div className="quiet-error" role="alert"><strong>{error}</strong>{client && <button className="text-button" onClick={() => void refresh()}>Try again</button>}</div>}
    {cursor !== null && <button className="secondary load-more" disabled={more} onClick={() => void loadMore()}>{more ? 'Loading…' : 'More trades'}</button>}
  </section>;
}
