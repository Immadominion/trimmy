import type {WalletTransferStore,StoredTransfer} from '../src/wallet-transfer-store.js';
/** Only for tests. Runtime always uses the PostgreSQL store. */
export class MemoryTransferStore implements WalletTransferStore {
  readonly rows=new Map<string,StoredTransfer>();
  async read(user:string,id?:string) {
    const matches=[...this.rows.values()].filter(r=>r.user_id===user && (!id || r.id===id));
    return matches.find(r=>r.status==='pending') ?? matches.at(-1) ?? null;
  }
  async create(user:string,row:StoredTransfer) {
    if([...this.rows.values()].some(r=>r.user_id===user && r.status==='pending'))throw Error('TRANSFER_PENDING');
    for(const r of this.rows.values())if(r.user_id===user && r.status==='reviewed')r.status='expired';
    this.rows.set(row.id,{...row});return row;
  }
  async begin(user:string,id:string,signature:string) {
    const row=await this.read(user,id);if(!row)throw Error('INVALID_REVIEW');
    if(row.signature===signature)return {...row,dispatch:false};
    if(row.status!=='reviewed')throw Error('REVIEW_EXPIRED');
    if([...this.rows.values()].some(r=>r.user_id===user && r.status==='pending'))throw Error('TRANSFER_PENDING');
    row.status='pending';row.signature=signature;return {...row,dispatch:true};
  }
  async resolve(user:string,id:string,status:'confirmed'|'failed'|'expired') {
    const row=await this.read(user,id);if(!row)throw Error('INVALID_REVIEW');
    if(row.status==='pending')row.status=status;return row;
  }
}
