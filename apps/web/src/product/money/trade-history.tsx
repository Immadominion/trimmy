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
import {useT} from '../../i18n/react.js';
import {t, type MessageKey} from '../../i18n/runtime.js';
import * as fmt from '../../i18n/format.js';

const STATUS: Readonly<Record<TradeStatus, MessageKey>> = {pending: 'money.history.status.pending', confirmed: 'money.history.status.confirmed',
  failed: 'money.history.status.failed', expired: 'money.history.status.expired'};
const pad = (value: number) => String(value).padStart(2, '0');
/** English keeps mobile's day/month/year and 24-hour clock; other languages use their region's date and time. */
function when(value: string): string {
  const date = new Date(value);
  if (!fmt.isEnglish()) return t('money.history.when', {date: fmt.date(date, undefined, {day: 'numeric', month: 'numeric', year: 'numeric'}),
    time: fmt.time(date, undefined, {hour: '2-digit', minute: '2-digit'})});
  return t('money.history.when', {date: `${date.getDate()}/${date.getMonth() + 1}/${date.getFullYear()}`, time: `${pad(date.getHours())}:${pad(date.getMinutes())}`});
}

export function TradeHistoryScreen({onBack, onOpenAsset, identities, pollMs = 10_000}: {
  onBack(): void; onOpenAsset?(assetId: string, mint: string): void; identities?: ReadonlyMap<string, CompanyIdentity>;
  /** Test-only: how often pending rows are reconciled (10 seconds, as on mobile). */
  pollMs?: number;
}) {
  const money = useMoney();
  const tr = useT();
  const client = money.orders;
  const [orders, setOrders] = useState<readonly TradeRecord[]>([]);
  const [cursor, setCursor] = useState<string | null>(null);
  const [loading, setLoading] = useState(true), [more, setMore] = useState(false);
  const [error, setError] = useState<MessageKey | null>(null);
  const [expanded, setExpanded] = useState<ReadonlySet<string>>(new Set());
  const generation = useRef(0), olderPages = useRef(false), ordersRef = useRef(orders); ordersRef.current = orders;
  const holdings = coherentHoldings(money.wallet);
  const scaleFor = (order: TradeRecord) => {
    const held = holdings?.stockTokens.find(token => token.mint === order.mint && token.decimals === order.decimals);
    return held ? ShareScale.fromDisplay(order.decimals, held.amountRaw, held.displayAmount) : ShareScale.plain(order.decimals);
  };
  const amount = (order: TradeRecord, raw: string, usdc: boolean) => usdc ? `${fmt.number(formatRawUnits(raw, 6) ?? rawDecimal(raw, 6))} USDC` : `${scaleFor(order).exact(raw)} ${order.symbol}`;

  const refresh = useCallback(async (silent = false) => {
    if (!client) {setLoading(false); setError('money.history.signInAgain'); return;}
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
      if (!silent) setError(reason instanceof LiveOrderError && reason.code === 'ACCOUNT_REQUIRED' ? 'money.history.signInAgain' : 'money.history.loadFailed');
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
    }, pollMs);
    return () => clearInterval(timer);
  }, [client, pending, more, refresh, pollMs]);

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
      if (turn === generation.current) setError(reason instanceof LiveOrderError && reason.code === 'ACCOUNT_REQUIRED' ? 'money.history.signInAgain' : 'money.history.moreFailed');
    } finally {if (turn === generation.current) setMore(false);}
  }

  return <section className="trade-history" aria-label={tr('money.history.title')}>
    <button className="company-back" onClick={onBack}>{tr('money.history.back')}</button>
    <div className="page-intro"><h1>{tr('money.history.title')}</h1><p className="money-badge real">{tr('money.realMoney')}</p></div>
    {loading && <div className="loading" role="status"><span className="loading-dot" aria-hidden="true"/>{tr('money.history.loading')}</div>}
    {!loading && !orders.length && error === null && <div className="empty-page"><h2>{tr('money.history.emptyTitle')}</h2><p>{tr('money.history.emptyBody')}</p></div>}
    <div className="history-list">{orders.map(order => {
      const open = expanded.has(order.id), name = identities?.get(order.assetId)?.name ?? order.name;
      return <article key={order.id} className={`history-row ${order.status}`}>
        <button className="history-summary" aria-expanded={open} onClick={() => setExpanded(prior => {const next = new Set(prior); if (open) next.delete(order.id); else next.add(order.id); return next;})}>
          <CompanyLogo name={name} url={identities?.get(order.assetId)?.imageUrl ?? null} size={40}/>
          <span className="history-main"><strong>{tr('money.trade.label', {side: order.buy ? 'buy' : 'sell', symbol: order.symbol})}</strong><small>{amount(order, order.fill?.inputAmountRaw ?? order.inputAmountRaw, order.buy)}</small></span>
          <span className="history-meta"><strong className={`history-status ${order.status}`}>{tr(STATUS[order.status])}</strong><small>{when(order.createdAt)}</small></span>
        </button>
        {open && <div className="history-detail">
          {order.fill ? <>
            <dl><div><dt>{order.buy ? tr('money.history.youPaid') : tr('money.history.youSold')}</dt><dd>{amount(order, order.fill.inputAmountRaw, order.buy)}</dd></div>
              <div><dt>{tr('money.history.youReceived')}</dt><dd>{amount(order, order.fill.outputAmountRaw, !order.buy)}</dd></div></dl>
            <p className="trade-caption">{tr('money.history.finalNote')}</p>
          </> : <>
            <dl><div><dt>{tr('money.history.quotedOutput')}</dt><dd>{amount(order, order.quotedOutputAmountRaw, !order.buy)}</dd></div>
              <div><dt>{tr('money.history.minimumOutput')}</dt><dd>{amount(order, order.minimumOutputAmountRaw, !order.buy)}</dd></div></dl>
            <p className="trade-caption">{tr('money.history.estimateNote')}</p>
          </>}
          <div className="history-links"><a className="text-button" href={explorerUrl(order)} target="_blank" rel="noreferrer noopener">{order.rfq ? tr('money.explorer.walletActivity') : tr('money.explorer.transaction')}</a>
            {onOpenAsset && <button className="text-button" onClick={() => onOpenAsset(order.assetId, order.mint)}>{tr('money.history.openStock')}</button>}</div>
        </div>}
      </article>;
    })}</div>
    {error !== null && <div className="quiet-error" role="alert"><strong>{tr(error)}</strong>{client && <button className="text-button" onClick={() => void refresh()}>{tr('common.tryAgain')}</button>}</div>}
    {cursor !== null && <button className="secondary load-more" disabled={more} onClick={() => void loadMore()}>{more ? tr('money.history.loadingMore') : tr('money.history.more')}</button>}
  </section>;
}
