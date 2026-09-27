import {useCallback, useEffect, useRef, useState} from 'react';
import {PracticeError} from './practice-client.js';
import {PendingMutations, ambiguous, careerApi, newMutationId} from './career-actions.js';
import type {ReasonPrivacy, ReasonPrivacyWrite, ReasonVisibility} from './career-actions.js';
import type {ProductApiClient, ProductIdentity} from './product-api.js';
import type {JourneyPrincipal} from './journey-store.js';

export type ReasonPrivacyNotice = 'saved' | 'changed-elsewhere' | null;
export interface ReasonPrivacyState {
  readonly privacy: ReasonPrivacy | null; readonly loading: boolean; readonly saving: boolean;
  readonly pending: ReasonPrivacyWrite | null; readonly failure: PracticeError | null; readonly notice: ReasonPrivacyNotice;
  choose(visibility: ReasonVisibility): Promise<void>; retry(): Promise<void>;
}

/** Mobile's ReasonPrivacyController: shows only what the server confirmed; a choice in flight reads as saving. */
export function useReasonPrivacy(options: {api: ProductApiClient | null; identity: ProductIdentity | null; principal: JourneyPrincipal | null; pending: PendingMutations | null; enabled: boolean}): ReasonPrivacyState {
  const {api, identity, principal, pending: store, enabled} = options;
  const [privacy, setPrivacy] = useState<ReasonPrivacy | null>(null);
  const [loading, setLoading] = useState(false), [saving, setSaving] = useState(false);
  const [pending, setPending] = useState<ReasonPrivacyWrite | null>(null);
  const [failure, setFailure] = useState<PracticeError | null>(null), [notice, setNotice] = useState<ReasonPrivacyNotice>(null);
  const epoch = useRef(0), busy = useRef(false);
  const toError = (error: unknown) => error instanceof PracticeError ? error : new PracticeError('PRACTICE_NETWORK_ERROR', 'Could not reach Trimmy.');

  const send = useCallback(async (write: ReasonPrivacyWrite, turn: number) => {
    if (!api || !identity || !principal || !store) return;
    setSaving(true); setFailure(null); setNotice(null);
    try {
      const saved = await careerApi.saveReasonPrivacy(api, identity, write);
      if (turn !== epoch.current) return;
      store.clear('reason-privacy', principal); setPending(null); setPrivacy(saved); setNotice('saved');
    } catch (error) {
      if (turn !== epoch.current) return;
      const problem = toError(error);
      if (!ambiguous(problem)) {store.clear('reason-privacy', principal); setPending(null);}
      if (problem.code === 'CAREER_REASON_PRIVACY_REVISION_CONFLICT') {
        try {const fresh = await careerApi.readReasonPrivacy(api, identity); if (turn === epoch.current) {setPrivacy(fresh); setNotice('changed-elsewhere'); return;}}
        catch { /* The conflict below still explains why nothing changed. */ }
      }
      setFailure(problem);
    } finally {if (turn === epoch.current) setSaving(false);}
  }, [api, identity, principal, store]);

  const load = useCallback(async () => {
    if (!api || !identity || !principal || !store || !enabled) return;
    const turn = epoch.current; setLoading(true); setFailure(null);
    try {
      const current = await careerApi.readReasonPrivacy(api, identity);
      if (turn !== epoch.current) return;
      setPrivacy(current);
      // An ambiguous earlier save replays its exact command once the desk is back online.
      const saved = store.read<ReasonPrivacyWrite>('reason-privacy', principal);
      if (saved) {setPending(saved); if (!busy.current) {busy.current = true; try {await send(saved, turn);} finally {busy.current = false;}}}
    } catch (error) {if (turn === epoch.current) setFailure(toError(error));}
    finally {if (turn === epoch.current) setLoading(false);}
  }, [api, identity, principal, store, enabled, send]);

  useEffect(() => {
    epoch.current++; setPrivacy(null); setPending(null); setFailure(null); setNotice(null); setSaving(false);
    void load();
    return () => {epoch.current++;};
  }, [load]);

  const choose = useCallback(async (visibility: ReasonVisibility) => {
    if (!privacy || !store || !principal || busy.current || saving) return;
    if (visibility === privacy.visibility && !pending) {setNotice(null); return;}
    const write: ReasonPrivacyWrite = {schemaVersion: 1, mutationId: newMutationId(), baseRevision: privacy.revision, visibility};
    try {store.save('reason-privacy', principal, write);} catch (error) {setFailure(toError(error)); return;}
    setPending(write); busy.current = true;
    try {await send(write, epoch.current);} finally {busy.current = false;}
  }, [privacy, store, principal, saving, pending, send]);

  const retry = useCallback(async () => {
    if (busy.current) return;
    if (pending) {busy.current = true; try {await send(pending, epoch.current);} finally {busy.current = false;} return;}
    await load();
  }, [pending, send, load]);

  return {privacy, loading, saving, pending, failure, notice, choose, retry};
}
