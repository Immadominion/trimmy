/**
 * Home in Real mode: USDC is the cash headline, SOL is shown separately for
 * fees, and stock tokens are listed in shares without an invented valuation.
 * Total holdings and what an order can spend are shown apart. The Paper/Real
 * switch sits on both balance cards, as on mobile's wallet stack.
 */
import type {CompanyIdentity} from '../company-identity.js';
import {CompanyLogo, art} from '../ui.js';
import {formatRawUnits, groupedDecimal, usdcDollars, usdcLabel, ShareScale} from './amounts.js';
import {useMoney} from './money-api.js';
import {coherentHoldings} from './wallet-controller.js';
import type {WalletStockBalance} from './wallet-models.js';

export function MoneyModeSwitch({real, onSwitch}: {real: boolean; onSwitch(): void}) {
  return <button className={`money-mode-switch ${real ? 'real' : 'paper'}`} onClick={onSwitch}
    aria-label={real ? 'Switch to paper mode' : 'Switch to real money mode'}><span aria-hidden="true">⇄</span>{real ? 'Real' : 'Paper'}</button>;
}

/** Shares for a wallet holding: the RPC's scaled display amount, else plain token units. */
export function holdingShares(holding: WalletStockBalance, raw = holding.amountRaw): string {
  if (raw === holding.amountRaw && holding.displayAmount !== null) return groupedDecimal(holding.displayAmount);
  return ShareScale.fromDisplay(holding.decimals, holding.amountRaw, holding.displayAmount).label(raw);
}

export function RealBalanceCard({onSwitch, onFastBuy, onAddMoney}: {onSwitch(): void; onFastBuy(): void; onAddMoney(): void}) {
  const money = useMoney();
  const holdings = coherentHoldings(money.wallet);
  const missing = money.wallet.context?.embeddedSolanaWallet.status === 'missing';
  const cash = holdings ? usdcDollars(holdings.usdc.amountRaw) : null;
  const spendableDiffers = holdings !== null && holdings.usdc.availableToTradeRaw !== holdings.usdc.amountRaw;
  return <section className="balance-card real-balance" aria-label="Real money balance">
    <div className="balance-heading"><div className="balance-label">Cash balance</div><MoneyModeSwitch real onSwitch={onSwitch}/></div>
    <div className="balance-amount" data-testid="real-cash-balance">{cash ?? '—'}<small>USDC</small></div>
    <div className="balance-details real-details">
      <div><span>{missing ? 'Create your wallet to add money.' : money.walletFresh ? 'USDC available' : 'Updating balance…'}</span>
        <strong data-testid="real-sol-balance">{holdings ? `${formatRawUnits(holdings.nativeSolLamports, 9) ?? '0'} SOL for fees` : missing ? '' : 'Checking SOL…'}</strong></div>
      <div className="cash-marks" aria-label="USDC and SOL" role="img"><img src={art('money/cash-usdc.png')} alt=""/><img src={art('money/cash-sol.png')} alt=""/></div>
    </div>
    {spendableDiffers && <p className="checked">{usdcLabel(holdings.usdc.availableToTradeRaw)} is ready to trade. The rest is in another token account.</p>}
    <div className="balance-actions"><button onClick={onFastBuy}><span aria-hidden="true">+</span>Fast buy</button>
      <button onClick={onAddMoney}><span aria-hidden="true">↙</span>Add money</button></div>
  </section>;
}

export function RealHoldings({identities, onOpen, onExplore, onAddMoney, onHistory}: {
  identities: ReadonlyMap<string, CompanyIdentity>; onOpen(holding: WalletStockBalance): void;
  onExplore(): void; onAddMoney(): void; onHistory(): void;
}) {
  const money = useMoney();
  const holdings = coherentHoldings(money.wallet);
  const caps = money.capabilities;
  const heading = <div className="section-line"><h2>Holdings{holdings && holdings.stockTokens.length > 0 && <span className="desk-count">{holdings.stockTokens.length}</span>}</h2>
    <button className="text-button" onClick={onHistory}>History<span aria-hidden="true">↗</span></button></div>;
  if (!holdings) {
    const checking = money.wallet.context?.embeddedSolanaWallet.status === 'candidate' || !money.wallet.checked;
    return <section className="desk-section desk-positions real-holdings">{heading}<div className="empty-positions"><img src={art('career-world/safe.png')} alt=""/>
      <div><h3>{checking ? 'Checking your wallet…' : 'Your wallet starts here'}</h3>
        {!checking && <button className="text-button" onClick={onAddMoney}>Add money</button>}</div></div></section>;
  }
  if (!holdings.stockTokens.length) {
    return <section className="desk-section desk-positions real-holdings">{heading}<div className="empty-positions"><img src={art('rookie-briefcase-v1.png')} alt=""/>
      <div><h3>No stocks yet</h3><p>Your first stock starts here.</p><button className="text-button" onClick={onExplore}>Explore stocks</button></div></div></section>;
  }
  return <section className="desk-section desk-positions real-holdings">{heading}
    {holdings.stockTokens.map(holding => {
      const name = caps?.forMint(holding.mint)?.name ?? holding.name;
      const identity = identities.get(holding.assetId);
      const partial = holding.availableToTradeRaw !== holding.amountRaw;
      return <button className="position-row" key={holding.mint} onClick={() => onOpen(holding)}>
        <CompanyLogo name={identity?.name ?? name} url={identity?.imageUrl ?? null}/>
        <span className="position-main"><strong>{name}</strong><small>{holdingShares(holding)} {holding.symbol}{partial ? ` · ${holdingShares(holding, holding.availableToTradeRaw)} ready to sell` : ''}</small></span>
        {/* A share price must never be multiplied by raw token units; valuation needs a verified price feed. */}
        <span className="position-value">—<small>Value unavailable</small></span><span className="position-open" aria-hidden="true">↗</span>
      </button>;
    })}
  </section>;
}
