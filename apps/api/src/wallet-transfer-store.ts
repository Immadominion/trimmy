import type {Pool} from 'pg';
import type {TransferReview} from './wallet-transfers.js';

export interface StoredTransfer {
  id: string; user_id: string; wallet: string; review: TransferReview;
  unsignedTransaction: string; reviewToken: string; lastValidBlockHeight: number;
  blockhash: string; observationSlot: number;
  status: 'reviewed' | 'pending' | 'confirmed' | 'failed' | 'expired';
  signature: string | null; dispatch?: boolean;
}
export interface WalletTransferStore {
  read(user: string, id?: string): Promise<StoredTransfer | null>;
  create(user: string, transfer: StoredTransfer): Promise<StoredTransfer>;
  begin(user: string, id: string, signature: string): Promise<StoredTransfer>;
  resolve(user: string, id: string, status: 'confirmed'|'failed'|'expired'): Promise<StoredTransfer>;
}
export class PostgresWalletTransferStore implements WalletTransferStore {
  constructor(private readonly pool: Pool) {}
  private async call(user: string, sql: string, params: unknown[]): Promise<StoredTransfer|null> {
    const client=await this.pool.connect();
    try {
      await client.query('BEGIN');
      await client.query("SELECT set_config('trimmy.practice_user_id',$1,true)",[user]);
      const result=await client.query(sql,params);
      await client.query('COMMIT');
      return result.rows[0]?.value ?? null;
    } catch(error) {await client.query('ROLLBACK');throw error;} finally {client.release();}
  }
  read(user:string,id?:string) {return this.call(user,'SELECT trimmy.wallet_transfer_read($1,$2) AS value',[user,id??null]);}
  async create(user:string,transfer:StoredTransfer) {return (await this.call(user,'SELECT trimmy.wallet_transfer_create($1,$2,$3) AS value',[user,transfer.id,JSON.stringify(transfer)]))!;}
  async begin(user:string,id:string,signature:string) {return (await this.call(user,'SELECT trimmy.wallet_transfer_begin($1,$2,$3) AS value',[user,id,signature]))!;}
  async resolve(user:string,id:string,status:'confirmed'|'failed'|'expired') {return (await this.call(user,'SELECT trimmy.wallet_transfer_resolve($1,$2,$3) AS value',[user,id,status]))!;}
}
