import {useCallback, useEffect, useRef, useState} from 'react';
import {PracticeError} from './practice-client';
import type {CareerMission, CareerMissionBoard, CareerRank, CareerSummary, PaperPortfolio} from './practice-client';
import {PendingMutations, ambiguous, careerApi, newMutationId} from './career-actions';
import type {PromotionReceipt, PromotionWrite, TradeReasonReceipt, TradeReasonWrite} from './career-actions';
import type {ProductApiClient, ProductIdentity} from './product-api';
import type {JourneyPrincipal} from './journey-store';
import {art, shares} from './ui';

export const rankLabel = (rank: CareerRank) => ({rookie: 'Rookie', analyst: 'Analyst', trader: 'Trader', 'senior-trader': 'Senior Trader', partner: 'Partner', legend: 'Legend'})[rank];

/** Mobile's eligibleCareerPromotion: a coherent board, the threshold met and its promotion mission complete. */
export function eligiblePromotion(summary: CareerSummary | null, board: CareerMissionBoard | null): CareerMission | null {
  const next = summary?.nextRank;
  if (!summary || !board || !next || !next.promotionRequired || next.trimsRemaining !== 0 ||
    board.revision !== summary.revision || board.currentRank !== summary.rank.id) return null;
  const matches = board.missions.filter(mission => mission.kind === 'promotion' && mission.chapterRank === summary.rank.id &&
    mission.promotesToRank === next.id && mission.status === 'complete');
  return matches.length === 1 ? matches[0]! : null;
}

export interface ReasonTarget {readonly orderId: string; readonly assetId: string; readonly variantMint: string; readonly symbol: string; readonly heldQuantityMicros: string}
/** Mobile's selectPaperReasonTarget: the first confirmed buy if still held, else the newest held buy. */
export function selectReasonTarget(portfolio: PaperPortfolio | null, first: CareerSummary['firstConfirmedBuy'], excluded: ReadonlySet<string> = new Set()): ReasonTarget | null {
  if (!portfolio) return null;
  const held = (assetId: string, variantMint: string) => portfolio.positions.find(p => p.assetId === assetId && p.variantMint === variantMint && BigInt(p.quantityMicros) > 0n);
  const target = (order: {id: string; assetId: string; variantMint: string; symbol: string}): ReasonTarget | null => {
    if (excluded.has(order.id)) return null;
    const position = held(order.assetId, order.variantMint);
    return position ? {orderId: order.id, assetId: order.assetId, variantMint: order.variantMint, symbol: order.symbol, heldQuantityMicros: position.quantityMicros} : null;
  };
  if (first) {
    const order = portfolio.recentOrders.find(item => item.id === first.orderId);
    if (order && order.action === 'buy' && order.assetId === first.assetId && order.variantMint === first.variantMint) {
      const found = target({id: first.orderId, assetId: first.assetId, variantMint: first.variantMint, symbol: first.symbol});
      if (found) return found;
    }
  }
  const buys = portfolio.recentOrders.filter(order => order.action === 'buy')
    .sort((a, b) => Date.parse(b.committedAt) - Date.parse(a.committedAt) || (b.id < a.id ? -1 : b.id > a.id ? 1 : 0));
  for (const order of buys) {const found = target(order); if (found) return found;}
  return null;
}

function reasonFailure(error: unknown): string {
  const code = error instanceof PracticeError ? error.code : '';
  if (code === 'CAREER_INVALID_INPUT') return 'Use one line and 180 characters or fewer.';
  if (code === 'PRACTICE_NETWORK_ERROR') return 'You are offline. Your reason was not saved. Try again.';
  if (code === 'PRACTICE_TIMEOUT') return 'Saving took too long. Try again.';
  if (error instanceof PracticeError && error.status === 401) return 'Refresh your session before saving this reason.';
  if (code === 'CAREER_PROFILE_REQUIRED') return 'Finish setting up your profile before saving this reason.';
  if (code === 'CAREER_ORDER_NOT_FOUND') return 'This paper buy was not found. Refresh your desk.';
  if (code === 'CAREER_BUY_ORDER_REQUIRED') return 'A reason can be added only to a confirmed paper buy.';
  if (code === 'CAREER_POSITION_REQUIRED') return 'You need to still hold this stock before saving a reason.';
  if (code === 'CAREER_REASON_EXISTS') return 'This paper buy already has a reason. Refresh your Career.';
  if (code === 'CAREER_IDEMPOTENCY_CONFLICT') return 'This retry could not be matched. Refresh your Career.';
  if (error instanceof PracticeError && error.status === 429) return 'Reasons are busy right now. Try again shortly.';
  return 'Your reason was not saved. Try again.';
}

/** Mobile's PaperReasonFlow: one line, 180 characters, saved once with a durable mutation ID. */
export function ReasonComposer({target, companyName, pending, onSave, onClose}: {
  target: ReasonTarget; companyName: string | null; pending: TradeReasonWrite | null;
  onSave: (note: string) => Promise<TradeReasonReceipt>; onClose: (saved: boolean) => void;
}) {
  const [note, setNote] = useState(pending?.orderId === target.orderId ? pending.note : '');
  const [busy, setBusy] = useState(false), [error, setError] = useState<string | null>(null), [exists, setExists] = useState(false);
  const [receipt, setReceipt] = useState<TradeReasonReceipt | null>(null);
  // Mobile's _pendingReason: an unconfirmed save is retried with the same command.
  const [retrying, setRetrying] = useState(pending?.orderId === target.orderId);
  const field = useRef<HTMLInputElement>(null), mounted = useRef(true);
  useEffect(() => {mounted.current = true; field.current?.focus(); return () => {mounted.current = false;};}, []);
  useEffect(() => {
    const key = (event: KeyboardEvent) => {if (event.key === 'Escape' && !busy) {event.preventDefault(); onClose(receipt !== null);}};
    window.addEventListener('keydown', key); return () => window.removeEventListener('keydown', key);
  }, [busy, onClose, receipt]);
  const text = note.trim(), valid = text.length > 0 && [...text].length <= 180;
  async function save() {
    if (busy || !valid) return; setBusy(true); setError(null);
    try {const saved = await onSave(text); if (mounted.current) setReceipt(saved);}
    catch (reason) {if (mounted.current) {setError(reasonFailure(reason)); setExists(reason instanceof PracticeError && reason.code === 'CAREER_REASON_EXISTS'); setRetrying(ambiguous(reason));}}
    finally {if (mounted.current) setBusy(false);}
  }
  return <div className="settings-modal-backdrop" onClick={event => {if (event.target === event.currentTarget && !busy) onClose(receipt !== null);}}>
    <div className="settings-modal reason-composer" role="dialog" aria-modal="true" aria-labelledby="reason-composer-title">
      <button className="rank-close" aria-label="Close" disabled={busy} onClick={() => onClose(receipt !== null)}>×</button>
      <p className="daily-label">{companyName ?? target.symbol} · {shares(target.heldQuantityMicros)} shares held</p>
      <h2 id="reason-composer-title">{receipt ? 'Reason saved' : 'Write your reason'}</h2>
      {receipt ? <>
        <blockquote className="reason-saved-note">{receipt.note}</blockquote>
        <p className="reason-reward">{receipt.trimsAwarded > 0 ? `+${receipt.trimsAwarded} Trims` : 'Mission recorded'}</p>
        <button className="primary full" onClick={() => onClose(true)}>Done</button>
      </> : <>
        <label className="settings-phrase" htmlFor="reason-note"><span>What made you buy?</span></label>
        <input ref={field} id="reason-note" className="reason-note" maxLength={180} autoComplete="off" placeholder="Your take on this stock…" value={note} disabled={busy}
          onChange={event => {setNote(event.target.value.replace(/[\r\n]/gu, ' ')); setError(null);}} onKeyDown={event => {if (event.key === 'Enter') {event.preventDefault(); void save();}}}/>
        <p className="reason-count" aria-live="polite">{[...note].length} / 180</p>
        {error && <p className="intro-error" role="alert">{error}</p>}
        {exists ? <button className="primary full" onClick={() => onClose(true)}>Close and refresh</button>
          : <button className="primary full" disabled={busy || !valid} onClick={() => void save()}>{busy ? 'Saving…' : retrying ? 'Retry reason' : 'Save reason'}</button>}
        <p className="intro-disclosure">Paper trade comment. {`Who can see it follows your comment privacy in Settings.`}</p>
      </>}
    </div>
  </div>;
}

/** Mobile's PromotionMoment after a confirmed promotion. */
export function PromotionMoment({receipt, onContinue}: {receipt: PromotionReceipt; onContinue: () => void}) {
  const heading = useRef<HTMLHeadingElement>(null);
  useEffect(() => {heading.current?.focus();}, []);
  return <div className="settings-modal-backdrop"><div className="settings-modal promotion-moment" role="dialog" aria-modal="true" aria-labelledby="promotion-title">
    <img src={art('career-world/trophy.png')} alt="" className="promotion-art"/>
    <h2 id="promotion-title" ref={heading} tabIndex={-1}>You’re {receipt.toRank === 'analyst' ? 'an' : 'a'} {rankLabel(receipt.toRank)}!</h2>
    <p>A new chapter on the floor.</p>
    <dl className="promotion-facts"><div><dt>From</dt><dd>{rankLabel(receipt.fromRank)}</dd></div><div><dt>New rank</dt><dd>{rankLabel(receipt.toRank)}</dd></div><div><dt>Earned</dt><dd>{receipt.trimsAwarded} Trims</dd></div></dl>
    <button className="primary full" onClick={onContinue}>Back to Career</button>
  </div></div>;
}

/**
 * Promotion and comment actions for this workspace's desk. Both save their exact
 * command before dispatch; an ambiguous result replays the same mutation ID.
 */
export function useCareerMilestones(options: {
  api: ProductApiClient | null; identity: ProductIdentity | null; principal: JourneyPrincipal | null; pending: PendingMutations | null;
  career: CareerSummary | null; missions: CareerMissionBoard | null; portfolio: PaperPortfolio | null; refresh: () => Promise<void>;
}) {
  const {api, identity, principal, pending} = options;
  const latest = useRef(options); latest.current = options;
  const [promoting, setPromoting] = useState(false), [promotion, setPromotion] = useState<PromotionReceipt | null>(null), [moment, setMoment] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [composer, setComposer] = useState<ReasonTarget | null>(null);
  const reasoned = useRef(new Set<string>());
  const eligible = eligiblePromotion(options.career, options.missions);

  const promote = useCallback(async (mission: CareerMission): Promise<boolean> => {
    const {career, missions, refresh} = latest.current;
    if (promoting || !api || !identity || !principal || !pending) return false;
    const current = eligiblePromotion(career, missions);
    if (!current || current.id !== mission.id || !current.promotesToRank) {setMessage('Refresh Career before claiming this promotion.'); void refresh(); return false;}
    const target = current.promotesToRank as PromotionWrite['targetRank'];
    const saved = pending.read<PromotionWrite>('promotion', principal);
    const body: PromotionWrite = saved?.targetRank === target ? saved : {schemaVersion: 1, mutationId: newMutationId(), targetRank: target};
    try {if (saved !== body) pending.save('promotion', principal, body);} catch {setMessage('Your promotion could not be prepared. Try again.'); return false;}
    setPromoting(true); setMessage(null);
    try {
      const receipt = await careerApi.promote(api, identity, body);
      pending.clear('promotion', principal);
      setPromotion(receipt); setMoment(true);
      await refresh();
      return true;
    } catch (error) {
      if (!ambiguous(error)) pending.clear('promotion', principal);
      setMessage(error instanceof PracticeError && error.status === 409 ? 'Your career changed. Refresh Career and try again.' : 'Your promotion could not be saved. Try again.');
      void refresh();
      return false;
    } finally {setPromoting(false);}
  }, [promoting, api, identity, principal, pending]);

  const openComment = useCallback(() => {
    const {portfolio, career} = latest.current;
    const target = selectReasonTarget(portfolio, career?.firstConfirmedBuy ?? null, reasoned.current);
    if (!target) {setMessage('This mission needs a confirmed paper buy you still hold. Choose a stock when you are ready.'); return false;}
    setMessage(null); setComposer(target); return true;
  }, []);

  const saveComment = useCallback(async (note: string): Promise<TradeReasonReceipt> => {
    if (!api || !identity || !principal || !pending || !composer) throw new PracticeError('CAREER_UNAVAILABLE', 'Unavailable.');
    const saved = pending.read<TradeReasonWrite>('trade-reason', principal);
    const body: TradeReasonWrite = saved && saved.orderId === composer.orderId && saved.note === note ? saved
      : {schemaVersion: 1, mutationId: newMutationId(), orderId: composer.orderId, note};
    if (saved !== body) pending.save('trade-reason', principal, body);
    try {
      const receipt = await careerApi.saveTradeReason(api, identity, body);
      pending.clear('trade-reason', principal); reasoned.current.add(receipt.orderId);
      void latest.current.refresh();
      return receipt;
    } catch (error) {
      if (!ambiguous(error)) pending.clear('trade-reason', principal);
      throw error;
    }
  }, [api, identity, principal, pending, composer]);

  const closeComment = useCallback((saved: boolean) => {setComposer(null); if (saved) void latest.current.refresh();}, []);
  const pendingComment = principal && pending ? pending.read<TradeReasonWrite>('trade-reason', principal) : null;
  return {eligible, promote, promoting, promotion, moment: moment && promotion !== null, dismissPromotion: () => setMoment(false), message, dismissMessage: () => setMessage(null),
    composer, openComment, saveComment, closeComment, pendingComment};
}
export type CareerMilestones = ReturnType<typeof useCareerMilestones>;
