/** Test fixtures only: official pinned codecs, deterministic addresses, no RPC or funds. */
import {address, createNoopSigner, createTransactionMessage, setTransactionMessageFeePayerSigner,
  setTransactionMessageLifetimeUsingBlockhash, appendTransactionMessageInstructions, compileTransaction,
  getBase64EncodedWireTransaction, getAddressEncoder, getProgramDerivedAddress} from '@solana/kit';
import {getSetComputeUnitLimitInstruction, getSetComputeUnitPriceInstruction} from '@solana-program/compute-budget';
import {getTransferSolInstruction} from '@solana-program/system';
import {getTransferCheckedInstruction, getApproveInstruction, getCreateAssociatedTokenIdempotentInstruction,
  TOKEN_PROGRAM_ADDRESS, ASSOCIATED_TOKEN_PROGRAM_ADDRESS} from '@solana-program/token';
import {writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';

export const WALLET = 'FVen3X669xLzsi6N2V91DoiyzHzg1uAgqiT8jZ9nS96Z';
export const FRIEND = '9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM';
export const STOCK = 'GbfDNU3Mx1nHrGdDqWhk3kqVtbzbx9frxMV8Srb6vEtd';
const USDC = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';
const TOKEN2022 = 'TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb';
const BLOCK = '5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d';
async function ata(owner, mint, program) {
  const enc = getAddressEncoder();
  return (await getProgramDerivedAddress({programAddress: ASSOCIATED_TOKEN_PROGRAM_ADDRESS,
    seeds: [enc.encode(address(owner)), enc.encode(address(program)), enc.encode(address(mint))]}))[0];
}
export async function buildSendReview(options = {}) {
  const {wallet = WALLET, destination = FRIEND, asset = 'USDC', amountRaw = '5000000', createsAccount = asset !== 'SOL',
    decimals = asset === 'SOL' ? 9 : asset === 'USDC' ? 6 : 9, mutation = ''} = options;
  const mint = asset === 'SOL' ? null : asset === 'USDC' ? USDC : asset;
  const program = address(options.program ?? (asset === 'USDC' ? TOKEN_PROGRAM_ADDRESS : TOKEN2022));
  const signer = createNoopSigner(address(wallet));
  const units = asset === 'SOL' ? 2000 : createsAccount ? 60000 : 20000;
  const instructions = [getSetComputeUnitLimitInstruction({units}),
    getSetComputeUnitPriceInstruction({microLamports: mutation === 'excess-fee' ? 900000000n : 50000n})];
  let transfer;
  const wireDestination = mutation === 'wrong-recipient' ? STOCK : destination;
  const wireAmount = BigInt(amountRaw) + (mutation === 'extra-amount' ? 1n : 0n);
  if (asset === 'SOL') transfer = getTransferSolInstruction({source: signer, destination: address(wireDestination), amount: wireAmount});
  else {
    const wireMint = mutation === 'wrong-mint' ? STOCK : mint;
    const source = await ata(wallet, wireMint, program), target = await ata(wireDestination, wireMint, program);
    if (createsAccount && mutation !== 'missing-creation') instructions.push(getCreateAssociatedTokenIdempotentInstruction({
      payer: signer, ata: target, owner: address(wireDestination), mint: address(wireMint), tokenProgram: program}));
    transfer = getTransferCheckedInstruction({source, mint: address(wireMint), destination: target, authority: signer,
      amount: wireAmount, decimals: mutation === 'wrong-decimals' ? decimals + 1 : decimals}, {programAddress: program});
    if (mutation === 'delegate') instructions.push(getApproveInstruction({source, delegate: address(STOCK), owner: signer, amount: 999999999n}, {programAddress: program}));
  }
  instructions.push(transfer);
  if (mutation === 'double-transfer') instructions.push(transfer);
  if (mutation === 'extra-sol') instructions.push(getTransferSolInstruction({source: signer, destination: address(STOCK), amount: 1000000n}));
  if (mutation === 'duplicate-budget') instructions.push(instructions[0]);
  if (mutation === 'unknown-program') instructions.push({programAddress: address(STOCK), accounts: [], data: new Uint8Array([1])});
  if (mutation === 'late-creation' && createsAccount) instructions.push(instructions.splice(2, 1)[0]);
  let message = setTransactionMessageFeePayerSigner(signer, createTransactionMessage({version: 0}));
  message = setTransactionMessageLifetimeUsingBlockhash({blockhash: BLOCK, lastValidBlockHeight: 1000n}, message);
  message = appendTransactionMessageInstructions(instructions, message);
  let wire = Buffer.from(getBase64EncodedWireTransaction(compileTransaction(message)), 'base64');
  if (mutation === 'trailing-bytes') wire = Buffer.concat([wire, Buffer.from([0])]);
  if (mutation === 'pre-signed') wire[1] = 1;
  if (mutation === 'truncated') wire = wire.subarray(0, wire.length - 1);
  if (mutation === 'noncanonical-length') wire = Buffer.concat([Buffer.from([0x81, 0]), wire.subarray(1)]);
  if (mutation === 'lookup-table') wire = Buffer.concat([wire.subarray(0, wire.length - 1), Buffer.from([1]), Buffer.alloc(32, 9), Buffer.from([1, 0, 0])]);
  return {id:'77777777-7777-4777-8777-777777777777', review: {
    asset: {kind: mint === null ? 'sol' : 'token', mint, symbol: asset === STOCK ? 'NVDAon' : asset, decimals, uiMultiplier: asset === STOCK ? '1.5' : '1'},
    from: wallet, destination, amountRaw, receivedRaw: amountRaw, createsAccount,
    accountRentLamports: createsAccount ? '2039280' : '0', networkFeeLamports: String(5000 + units * 0.05),
    expiresAt:'2026-10-01T00:00:00.000Z'}, unsignedTransaction: wire.toString('base64'), reviewToken: 'payload.mac'};
}
export async function cases() {
  const values = [];
  for (const [name, options] of Object.entries({sol:{asset:'SOL'}, usdc:{}, 'usdc-existing':{createsAccount:false},
    stock:{asset:STOCK,amountRaw:'1000000000'}, 'stock-existing':{asset:STOCK,createsAccount:false}, 'classic-stock':{asset:STOCK,program:TOKEN_PROGRAM_ADDRESS}})) {
    values.push({name, accepted:true, envelope:await buildSendReview(options)});
    for (const mutation of ['wrong-recipient','extra-amount','excess-fee','double-transfer','extra-sol','duplicate-budget','unknown-program',
      'trailing-bytes','pre-signed','truncated','noncanonical-length','lookup-table',
      ...(options.asset === 'SOL' ? [] : ['wrong-decimals','delegate']),
      ...(options.createsAccount === false || options.asset === 'SOL' ? [] : ['missing-creation','late-creation'])]) {
      values.push({name:`${name}/${mutation}`,accepted:false,envelope:await buildSendReview({...options,mutation})});
    }
  }
  values.push({name:'usdc/wrong-mint',accepted:false,envelope:await buildSendReview({mutation:'wrong-mint'})});
  return values;
}
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  await writeFile(new URL('./fixtures/client-send-policy.json', import.meta.url), JSON.stringify(await cases(), null, 2)+'\n');
}
