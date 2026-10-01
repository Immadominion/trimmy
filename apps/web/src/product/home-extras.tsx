import type {ReactNode} from 'react';
import {art} from './ui';
import {useT} from '../i18n/react';

/**
 * Mobile's Home (Desk) additions in the web frame: the compact Fast buy
 * (practice), the Updates inbox for signed-in accounts, the "Pick your trader"
 * invitation while no trader is chosen, and the Community block.
 */
export interface HomeParity {
  readonly onFastBuy: () => void;
  /** Present only for signed-in accounts, like mobile's onInbox. */
  readonly onUpdates?: (() => void) | undefined;
  /** Present only while no trader is chosen, like mobile's onChoosePersona. */
  readonly onChooseTrader?: (() => void) | undefined;
  readonly community: ReactNode;
}
/** Fast buy lives on the balance card; this row keeps only Updates. */
export function HomeActions({home}: {home: HomeParity}) {
  const tr = useT();
  if (!home.onUpdates) return null;
  return <div className="home-actions">
    <button className="home-updates" aria-label={tr('shell.home.updates')} onClick={home.onUpdates}><img src={art('icons/asset-bell.png')} alt="" width="24" height="24"/><span>{tr('shell.home.updates')}</span></button>
  </div>;
}
export function HomeInvitations({home}: {home: HomeParity}) {
  const tr = useT();
  return <>
    {home.onChooseTrader && <button className="home-invitation" aria-label={tr('shell.home.pickTrader')} onClick={home.onChooseTrader}>
      <img src={art('icons/nav-plumpy-profile.png')} alt=""/><span><strong>{tr('shell.home.pickTrader')}</strong><small>{tr('shell.home.pickTraderBody')}</small></span><span aria-hidden="true">↗</span></button>}
    {home.community}
  </>;
}
