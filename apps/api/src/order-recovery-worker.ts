import type {Pool} from 'pg';
import type {LiveStockOrders} from './live-stock-orders.js';

export interface OrderRecoveryStore {
 claim():Promise<{id:string;userId:string}[]>;
 release(id:string):Promise<void>;
}
export function postgresOrderRecovery(pool:Pool):OrderRecoveryStore {
 return {
  claim:async()=>(await pool.query('SELECT trimmy.live_order_recovery_claim() AS orders')).rows[0].orders,
  release:async id=>{await pool.query('SELECT trimmy.live_order_recovery_release($1)',[id]);},
 };
}
/** Reuses the chain-verification path, including RFQ recovery. Only status is
 * accessible here: the worker cannot quote, sign, or resubmit a transaction. */
export class OrderRecoveryWorker {
 #active:Promise<void>|null=null; #timer:ReturnType<typeof setTimeout>|null=null; #stopped=true;
 constructor(private readonly store:OrderRecoveryStore,private readonly service:Pick<LiveStockOrders,'status'>,private readonly onError:()=>void=()=>{}){}
 start(){if(!this.#stopped)return;this.#stopped=false;this.#schedule(0);}
 #schedule(ms=5_000){if(!this.#stopped)this.#timer=setTimeout(()=>{void this.tick().finally(()=>this.#schedule());},ms);}
 tick():Promise<void>{
  if(this.#active)return this.#active;
  this.#active=this.#run().catch(()=>this.onError()).finally(()=>{this.#active=null;});return this.#active;
 }
 async #run(){
  for(const order of await this.store.claim()) {
   try {await this.service.status(order.userId,order.id);}
   finally {await this.store.release(order.id);}
  }
 }
 async stop(){this.#stopped=true;if(this.#timer)clearTimeout(this.#timer);await this.#active;}
}
