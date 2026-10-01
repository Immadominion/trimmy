/**
 * Fast buy from Home. Paper searches the Market and opens the company's paper
 * order. Real lists every token the trading capabilities offer, searched on
 * this device, and opens that exact token. Mirrors mobile's fast_buy_sheet.
 */
import {useEffect, useId, useRef, useState} from 'react';
import type {ProductMarketClient, StockCard} from '../market-client.js';
import {CompanyLogo} from '../ui.js';
import {marketLabel} from './live-trading.js';
import {useMoney} from './money-api.js';
import {useT} from '../../i18n/react.js';
import {useBackCloses} from '../use-back-closes';
import {useModalFocus} from '../use-modal-focus';

export interface FastBuyChoice {readonly assetId: string; readonly mint: string | null; readonly card?: StockCard}

export function FastBuySheet({market, knownCards, onOpen, onClose}: {
  market: ProductMarketClient; knownCards: ReadonlyMap<string, StockCard>; onOpen(choice: FastBuyChoice): void; onClose(): void;
}) {
  const fastBuySheetDialog = useRef<HTMLElement>(null);
  useModalFocus(fastBuySheetDialog);
  const money = useMoney();
  const tr = useT();
  const titleId = useId();
  const [query, setQuery] = useState('');
  const [cards, setCards] = useState<readonly StockCard[] | null>(null);
  const [paperFailed, setPaperFailed] = useState(false), [revision, setRevision] = useState(0);
  const input = useRef<HTMLInputElement>(null), opener = useRef<Element | null>(null);
  useBackCloses(onClose);
  useEffect(() => {opener.current = document.activeElement; input.current?.focus();
    return () => {if (opener.current instanceof HTMLElement) opener.current.focus();};}, []);
  useEffect(() => {if (money.real) void money.refreshCapabilities();}, [money.real, money.refreshCapabilities]);
  useEffect(() => {
    if (money.real) return;
    const controller = new AbortController();
    setPaperFailed(false);
    const timer = window.setTimeout(() => {
      const text = query.trim();
      void (text ? market.cards(text, {signal: controller.signal}).then(page => page.results) : market.catalog(0, {signal: controller.signal}).then(page => page.cards))
        .then(rows => {if (!controller.signal.aborted) setCards(rows);}, () => {if (!controller.signal.aborted) setPaperFailed(true);});
    }, query ? 300 : 0);
    return () => {clearTimeout(timer); controller.abort();};
  }, [market, money.real, query, revision]);

  const caps = money.capabilities;
  const text = query.trim().toLowerCase().replace(/^\$/, '');
  const tradeable = caps?.enabled ? caps.tradeableAssets.map(asset => ({asset, card: knownCards.get(asset.assetId),
    issuer: caps.issuers.get(asset.issuerId)?.name ?? tr('money.issuer.fallbackName')})).filter(row => !text ||
    [row.card?.name ?? '', row.asset.name, row.asset.symbol, row.issuer].some(field => field.toLowerCase().includes(text))) : [];
  let body;
  if (money.real) {
    if (!caps && money.capabilitiesFailed) body = <div className="fast-buy-message"><p>{tr('money.fastBuy.tradingFailed')}</p><button className="text-button" onClick={() => void money.refreshCapabilities(true)}>{tr('money.fastBuy.retry')}</button></div>;
    else if (!caps) body = <div className="loading" role="status"><span className="loading-dot" aria-hidden="true"/>{tr('money.checkingTrading')}</div>;
    else if (!tradeable.length) body = <div className="fast-buy-message"><p>{text ? tr('money.fastBuy.noMatch') : tr('money.fastBuy.noneAvailable')}</p></div>;
    else body = <ul className="fast-buy-list">{tradeable.map(({asset, card, issuer}) => <li key={asset.mint}>
      <button onClick={() => onOpen({assetId: asset.assetId, mint: asset.mint, ...(card ? {card} : {})})}>
        <CompanyLogo name={card?.name ?? asset.name} url={card?.imageUrl ?? null} size={42}/>
        <span><strong>{card?.name ?? asset.name}</strong><small>{asset.symbol} · {issuer}{asset.market && (asset.market.status !== 'open' || asset.market.usSessions) ? ` · ${marketLabel(asset.market)}` : ''}</small></span>
        <span aria-hidden="true">›</span></button></li>)}</ul>;
  } else if (paperFailed) body = <div className="fast-buy-message"><p>{tr('money.fastBuy.marketSlow')}</p><button className="text-button" onClick={() => setRevision(value => value + 1)}>{tr('money.fastBuy.retry')}</button></div>;
  else if (cards === null) body = <div className="loading" role="status"><span className="loading-dot" aria-hidden="true"/>{tr('money.fastBuy.finding')}</div>;
  else if (!cards.length) body = <div className="fast-buy-message"><p>{tr('money.fastBuy.noMatches')}</p></div>;
  else body = <ul className="fast-buy-list">{cards.map(card => <li key={card.assetId}><button onClick={() => onOpen({assetId: card.assetId, mint: card.primaryVariant?.mint ?? null, card})}>
    <CompanyLogo name={card.name ?? card.assetId} url={card.imageUrl} size={42}/>
    <span><strong>{card.name ?? card.assetId}</strong><small>${(card.symbol ?? '').replace(/^\$/, '')}</small></span><span aria-hidden="true">›</span></button></li>)}</ul>;

  return <div className="money-sheet-backdrop" onMouseDown={event => {if (event.target === event.currentTarget) onClose();}}>
    <section className={`money-sheet fast-buy ${money.real ? 'real' : 'paper'}`} ref={fastBuySheetDialog} role="dialog" aria-modal="true" aria-labelledby={titleId}
      onKeyDown={event => {if (event.key === 'Escape') {event.stopPropagation(); onClose();}}}>
      <header className="money-sheet-head"><h2 id={titleId}>{tr('money.fastBuy.title')}</h2><p className={`money-badge ${money.real ? 'real' : 'paper'}`}>{money.real ? tr('money.realMoney') : tr('money.mode.paper')}</p>
        <button className="money-close" aria-label={tr('money.fastBuy.close')} onClick={onClose}>×</button></header>
      <label className="sr-only" htmlFor={`${titleId}-search`}>{tr('money.fastBuy.search')}</label>
      <input ref={input} id={`${titleId}-search`} className="fast-buy-search" type="search" autoComplete="off" autoCorrect="off" autoCapitalize="none" spellCheck={false} maxLength={80}
        placeholder={tr('money.fastBuy.search')} value={query} onChange={event => setQuery(event.target.value)}/>
      {body}
    </section>
  </div>;
}
