import type {ReactNode} from 'react';
import {art} from './ui';

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
  if (!home.onUpdates) return null;
  return <div className="home-actions">
    <button className="home-updates" aria-label="Updates" onClick={home.onUpdates}><img src={art('icons/asset-bell.png')} alt="" width="24" height="24"/><span>Updates</span></button>
  </div>;
}
export function HomeInvitations({home}: {home: HomeParity}) {
  return <>
    {home.onChooseTrader && <button className="home-invitation" aria-label="Pick your trader" onClick={home.onChooseTrader}>
      <img src={art('icons/nav-plumpy-profile.png')} alt=""/><span><strong>Pick your trader</strong><small>Make this desk yours.</small></span><span aria-hidden="true">↗</span></button>}
    {home.community}
  </>;
}
