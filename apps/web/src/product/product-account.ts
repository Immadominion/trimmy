import {PracticeClient, PracticeError, parsePracticeSubject} from './practice-client.js';
import type {PracticeAccountProof} from './practice-client.js';
import {PracticeSession} from './practice-session.js';
import type {PracticeCrypto, PracticeStorage} from './practice-session.js';

export interface ConnectProductAccountInput extends PracticeAccountProof {readonly openExistingAccount?: boolean}
export interface ProductAccountConnection {
  readonly accountId: string; readonly guestDisposition: 'claimed' | 'none' | 'preserved';
}
export interface ProductAccountConnectorOptions {
  readonly client: PracticeClient; readonly storage: PracticeStorage; readonly crypto?: PracticeCrypto;
  readonly now?: () => number; readonly locks?: Pick<LockManager, 'request'>;
}
/** No guest means bootstrap only. A guest must be claimed before account provisioning. */
export function createProductAccountConnector(options: ProductAccountConnectorOptions):
  (input: ConnectProductAccountInput) => Promise<ProductAccountConnection> {
  return async input => {
    parsePracticeSubject(input.subject);
    if (input.signal.aborted) throw new PracticeError('PRACTICE_ABORTED', 'Sign-in was cancelled.');
    const guestSession = new PracticeSession(options);
    try {
      const guestDisposition = await guestSession.claimForAccount(input, input.openExistingAccount ?? false);
      const accountId = await options.client.openAccount(input, input.signal);
      if (input.signal.aborted) throw new PracticeError('PRACTICE_ABORTED', 'Sign-in was cancelled.');
      // Validate the saved account journal before the provider exposes this account.
      const accountSession = new PracticeSession({...options, account: {...input, accountId}});
      accountSession.close();
      return {accountId, guestDisposition};
    } finally {guestSession.close();}
  };
}
