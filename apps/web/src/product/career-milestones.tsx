import {useCallback, useEffect, useRef, useState} from 'react';
import {PracticeError} from './practice-client';
import type {CareerMission, CareerMissionBoard, CareerRank, CareerSummary, PaperPortfolio} from './practice-client';
import {PendingMutations, ambiguous, careerApi, newMutationId} from './career-actions';
import type {PromotionReceipt, PromotionWrite, TradeReasonReceipt, TradeReasonWrite} from './career-actions';
import type {ProductApiClient, ProductIdentity} from './product-api';
import type {JourneyPrincipal} from './journey-store';
import {art, shares, sharesPlain} from './ui';
import {t, type MessageKey} from '../i18n/runtime';
import {useT} from '../i18n/react';
import * as fmt from '../i18n/format';
import {useModalFocus} from './use-modal-focus';

const RANK_KEYS: Readonly<Record<CareerRank, MessageKey>> = {rookie: 'career.rank.rookie', analyst: 'career.rank.analyst', trader: 'career.rank.trader',
  'senior-trader': 'career.rank.seniorTrader', partner: 'career.rank.partner', legend: 'career.rank.legend'};
/** A rank's name in the page's language. */
export const rankLabel = (rank: CareerRank) => t(RANK_KEYS[rank]);
/**
 * A rank the API sent with its English label: English shows the API's label
 * exactly as before, other languages the client's name for that rank.
 */
export function rankName(rank: {readonly id: CareerRank; readonly label: string}): string {
  return fmt.isEnglish() || !Object.hasOwn(RANK_KEYS, rank.id) ? rank.label : rankLabel(rank.id);
}
const MISSION_KEYS: Readonly<Record<string, readonly [MessageKey, MessageKey]>> = {
  'first-paper-buy': ['career.mission.firstPaperBuy', 'career.mission.firstPaperBuyHow'],
  'write-a-reason': ['career.mission.writeAReason', 'career.mission.writeAReasonHow'],
  'hold-through-red-day': ['career.mission.holdThroughRedDay', 'career.mission.holdThroughRedDayHow']};
/** A mission's title and instruction: English shows the API's text exactly, other languages the client's, by mission id. */
export function missionText(mission: Pick<CareerMission, 'id' | 'title' | 'instruction'>): {readonly title: string; readonly instruction: string} {
  const keys = Object.hasOwn(MISSION_KEYS, mission.id) ? MISSION_KEYS[mission.id] : undefined;
  return fmt.isEnglish() || !keys ? {title: mission.title, instruction: mission.instruction} : {title: t(keys[0]), instruction: t(keys[1])};
}

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

/** The copy for a failed reason save, by error code. Kept as a key so it follows a language change. */
function reasonFailure(error: unknown): MessageKey {
  const code = error instanceof PracticeError ? error.code : '';
  if (code === 'CAREER_INVALID_INPUT') return 'career.reason.error.invalid';
  if (code === 'PRACTICE_NETWORK_ERROR') return 'career.reason.error.offline';
  if (code === 'PRACTICE_TIMEOUT') return 'career.reason.error.timeout';
  if (error instanceof PracticeError && error.status === 401) return 'career.reason.error.session';
  if (code === 'CAREER_PROFILE_REQUIRED') return 'career.reason.error.profile';
  if (code === 'CAREER_ORDER_NOT_FOUND') return 'career.reason.error.orderMissing';
  if (code === 'CAREER_BUY_ORDER_REQUIRED') return 'career.reason.error.buyRequired';
  if (code === 'CAREER_POSITION_REQUIRED') return 'career.reason.error.positionRequired';
  if (code === 'CAREER_REASON_EXISTS') return 'career.reason.error.exists';
  if (code === 'CAREER_IDEMPOTENCY_CONFLICT') return 'career.reason.error.conflict';
  if (error instanceof PracticeError && error.status === 429) return 'career.reason.error.busy';
  return 'career.reason.error.default';
}

/** Mobile's PaperReasonFlow: one line, 180 characters, saved once with a durable mutation ID. */
export function ReasonComposer({target, companyName, pending, onSave, onClose}: {
  target: ReasonTarget; companyName: string | null; pending: TradeReasonWrite | null;
  onSave: (note: string) => Promise<TradeReasonReceipt>; onClose: (saved: boolean) => void;
}) {
  const reasonComposerDialog = useRef<HTMLDivElement>(null);
  useModalFocus(reasonComposerDialog);
  const [note, setNote] = useState(pending?.orderId === target.orderId ? pending.note : '');
  const tr = useT();
  const [busy, setBusy] = useState(false), [error, setError] = useState<MessageKey | null>(null), [exists, setExists] = useState(false);
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
    <div className="settings-modal reason-composer" ref={reasonComposerDialog} role="dialog" aria-modal="true" aria-labelledby="reason-composer-title">
      <button className="rank-close" aria-label={tr('career.reason.close')} disabled={busy} onClick={() => onClose(receipt !== null)}>×</button>
      <p className="daily-label">{tr('career.reason.held', {name: companyName ?? target.symbol,
        shares: new fmt.Shown(Number(sharesPlain(target.heldQuantityMicros).replaceAll(',', '')), shares(target.heldQuantityMicros))})}</p>
      <h2 id="reason-composer-title">{receipt ? tr('career.reason.savedTitle') : tr('career.reason.title')}</h2>
      {receipt ? <>
        <blockquote className="reason-saved-note">{receipt.note}</blockquote>
        <p className="reason-reward">{receipt.trimsAwarded > 0 ? tr('career.trimsGained', {count: receipt.trimsAwarded}) : tr('career.reason.missionRecorded')}</p>
        <button className="primary full" onClick={() => onClose(true)}>{tr('common.done')}</button>
      </> : <>
        <label className="settings-phrase" htmlFor="reason-note"><span>{tr('career.reason.prompt')}</span></label>
        <input ref={field} id="reason-note" className="reason-note" maxLength={180} autoComplete="off" placeholder={tr('career.reason.placeholder')} value={note} disabled={busy}
          onChange={event => {setNote(event.target.value.replace(/[\r\n]/gu, ' ')); setError(null);}} onKeyDown={event => {if (event.key === 'Enter') {event.preventDefault(); void save();}}}/>
        <p className="reason-count" aria-live="polite">{[...note].length} / 180</p>
        {error && <p className="intro-error" role="alert">{tr(error)}</p>}
        {exists ? <button className="primary full" onClick={() => onClose(true)}>{tr('career.reason.closeRefresh')}</button>
          : <button className="primary full" disabled={busy || !valid} onClick={() => void save()}>{busy ? tr('career.saving') : retrying ? tr('career.reason.retry') : tr('career.reason.save')}</button>}
        <p className="intro-disclosure">{tr('career.reason.disclosure')}</p>
      </>}
    </div>
  </div>;
}

/** Mobile's PromotionMoment after a confirmed promotion. */
export function PromotionMoment({receipt, onContinue}: {receipt: PromotionReceipt; onContinue: () => void}) {
  const promotionDialog = useRef<HTMLDivElement>(null);
  useModalFocus(promotionDialog);
  const heading = useRef<HTMLHeadingElement>(null);
  const tr = useT();
  useEffect(() => {heading.current?.focus();}, []);
  return <div className="settings-modal-backdrop"><div className="settings-modal promotion-moment" ref={promotionDialog} role="dialog" aria-modal="true" aria-labelledby="promotion-title">
    <img src={art('career-world/trophy.png')} alt="" className="promotion-art"/>
    <h2 id="promotion-title" ref={heading} tabIndex={-1}>{tr('career.promotion.title', {rank: receipt.toRank, name: rankLabel(receipt.toRank)})}</h2>
    <p>{tr('career.promotion.subtitle')}</p>
    <dl className="promotion-facts"><div><dt>{tr('career.promotion.from')}</dt><dd>{rankLabel(receipt.fromRank)}</dd></div><div><dt>{tr('career.promotion.newRank')}</dt><dd>{rankLabel(receipt.toRank)}</dd></div><div><dt>{tr('career.promotion.earned')}</dt><dd>{tr('career.trims', {count: receipt.trimsAwarded})}</dd></div></dl>
    <button className="primary full" onClick={onContinue}>{tr('career.backToCareer')}</button>
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
  /** A message key, so the copy follows a language change. */
  const [message, setMessage] = useState<MessageKey | null>(null);
  const [composer, setComposer] = useState<ReasonTarget | null>(null);
  const reasoned = useRef(new Set<string>());
  const eligible = eligiblePromotion(options.career, options.missions);

  const promote = useCallback(async (mission: CareerMission): Promise<boolean> => {
    const {career, missions, refresh} = latest.current;
    if (promoting || !api || !identity || !principal || !pending) return false;
    const current = eligiblePromotion(career, missions);
    if (!current || current.id !== mission.id || !current.promotesToRank) {setMessage('career.milestones.refreshBeforePromotion'); void refresh(); return false;}
    const target = current.promotesToRank as PromotionWrite['targetRank'];
    const saved = pending.read<PromotionWrite>('promotion', principal);
    const body: PromotionWrite = saved?.targetRank === target ? saved : {schemaVersion: 1, mutationId: newMutationId(), targetRank: target};
    try {if (saved !== body) pending.save('promotion', principal, body);} catch {setMessage('career.milestones.promotionNotPrepared'); return false;}
    setPromoting(true); setMessage(null);
    try {
      const receipt = await careerApi.promote(api, identity, body);
      pending.clear('promotion', principal);
      setPromotion(receipt); setMoment(true);
      await refresh();
      return true;
    } catch (error) {
      if (!ambiguous(error)) pending.clear('promotion', principal);
      setMessage(error instanceof PracticeError && error.status === 409 ? 'career.milestones.careerChanged' : 'career.milestones.promotionNotSaved');
      void refresh();
      return false;
    } finally {setPromoting(false);}
  }, [promoting, api, identity, principal, pending]);

  const openComment = useCallback(() => {
    const {portfolio, career} = latest.current;
    const target = selectReasonTarget(portfolio, career?.firstConfirmedBuy ?? null, reasoned.current);
    if (!target) {setMessage('career.milestones.needsHeldBuy'); return false;}
    setMessage(null); setComposer(target); return true;
  }, []);

  /** Saves a reason for one confirmed buy, replaying an unconfirmed identical command. */
  const saveReasonFor = useCallback(async (orderId: string, note: string): Promise<TradeReasonReceipt> => {
    if (!api || !identity || !principal || !pending) throw new PracticeError('CAREER_UNAVAILABLE', 'Unavailable.');
    const saved = pending.read<TradeReasonWrite>('trade-reason', principal);
    const body: TradeReasonWrite = saved && saved.orderId === orderId && saved.note === note ? saved
      : {schemaVersion: 1, mutationId: newMutationId(), orderId, note};
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
  }, [api, identity, principal, pending]);
  const saveComment = useCallback(async (note: string): Promise<TradeReasonReceipt> => {
    if (!composer) throw new PracticeError('CAREER_UNAVAILABLE', 'Unavailable.');
    return saveReasonFor(composer.orderId, note);
  }, [composer, saveReasonFor]);

  const closeComment = useCallback((saved: boolean) => {setComposer(null); if (saved) void latest.current.refresh();}, []);
  const pendingComment = principal && pending ? pending.read<TradeReasonWrite>('trade-reason', principal) : null;
  return {eligible, promote, promoting, promotion, moment: moment && promotion !== null, dismissPromotion: () => setMoment(false), message, dismissMessage: () => setMessage(null),
    composer, openComment, saveComment, closeComment, pendingComment, saveReasonFor};
}
export type CareerMilestones = ReturnType<typeof useCareerMilestones>;
