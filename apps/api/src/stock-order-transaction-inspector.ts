import {createHash} from 'node:crypto';
import {address, getAddressEncoder, getCompiledTransactionMessageDecoder, getCompiledTransactionMessageEncoder,
  getTransactionDecoder, getTransactionEncoder, isOffCurveAddress} from '@solana/kit';

export type StockTransactionStructureErrorCode = 'TRANSACTION_INVALID' | 'SIGNER_MISMATCH';
export class StockTransactionStructureError extends Error {
  constructor(readonly code: StockTransactionStructureErrorCode) {
    super('The unsigned Solana transaction structure is invalid.');
    this.name = 'StockTransactionStructureError';
  }
}

export interface StockTransactionLookupDescriptor {
  readonly lookupTableAddress: string;
  readonly writableIndexes: readonly number[];
  readonly readonlyIndexes: readonly number[];
}
export type StockTransactionAccountReference = Readonly<{
  readonly kind: 'static'; readonly accountIndex: number; readonly address: string;
}> | Readonly<{
  readonly kind: 'lookup'; readonly accountIndex: number; readonly lookupTablePosition: number;
  readonly lookupTableAddress: string; readonly lookupIndex: number; readonly writable: boolean;
}>;
export interface StockTransactionCompiledInstruction {
  readonly instructionIndex: number;
  readonly programAddressIndex: number;
  readonly program: StockTransactionAccountReference;
  readonly accountIndices: readonly number[];
  /** Instruction bytes remain private; only their length and digest leave the inspector. */
  readonly dataLengthBytes: number;
  readonly dataSha256: string;
}
export interface UnsignedV0TransactionStructure {
  readonly schemaVersion: 1;
  readonly kind: 'unsigned_solana_v0_structure';
  readonly transactionVersion: 0;
  readonly transactionSizeBytes: number;
  readonly transactionHash: string;
  readonly transactionMessageHash: string;
  readonly requiredSigner: Readonly<{readonly address: string; readonly accountIndex: 0; readonly role: 'fee_payer_and_taker'}>;
  readonly signatures: Readonly<{
    readonly required: 1; readonly present: 0; readonly absent: 1; readonly unsigned: true;
  }>;
  readonly header: Readonly<{
    readonly numSignerAccounts: 1;
    readonly numReadonlySignerAccounts: 0;
    readonly numReadonlyNonSignerAccounts: number;
  }>;
  readonly lifetimeToken: Readonly<{
    readonly value: string;
    readonly expectedUse: 'recent_blockhash';
    readonly semanticKindVerified: false;
    readonly mainnetRecencyVerified: false;
  }>;
  readonly staticAccountKeys: readonly string[];
  readonly addressTableLookups: readonly StockTransactionLookupDescriptor[];
  readonly accountIndexSpace: Readonly<{
    readonly static: number; readonly lookupWritable: number; readonly lookupReadonly: number; readonly total: number;
  }>;
  readonly instructions: readonly StockTransactionCompiledInstruction[];
  readonly assessment: Readonly<{
    readonly status: 'structurally_valid_but_incomplete';
    readonly structuralIntegrity: 'verified';
    readonly requiredSignerBinding: 'verified';
    readonly staticAccountResolution: 'complete';
    readonly lookupTableResolution: 'required' | 'not_applicable';
    readonly recentBlockhash: 'unverified';
    readonly instructionSemantics: 'unverified';
    readonly accountState: 'unverified';
    readonly transactionTerms: 'unverified';
    readonly simulation: 'not_run';
    readonly approvable: false;
    readonly readyForSimulation: false;
    readonly signingEnabled: false;
    readonly broadcastEnabled: false;
    readonly financialOperationsEnabled: false;
  }>;
}

const maximumTransactionBytes = 1_232;
const maximumAccounts = 64;
const maximumInstructions = 64;
const zeroAddress = '11111111111111111111111111111111';
const digest = (bytes: Uint8Array) => createHash('sha256').update(bytes).digest('hex');
const fail = (code: StockTransactionStructureErrorCode): never => { throw new StockTransactionStructureError(code); };

function expectedSigner(value: unknown): string {
  try {
    if (typeof value !== 'string' || value.length > 44) return fail('SIGNER_MISMATCH');
    const signer = address(value);
    if (signer === zeroAddress || isOffCurveAddress(signer) || getAddressEncoder().encode(signer).every(byte => byte === 0)) {
      return fail('SIGNER_MISMATCH');
    }
    return signer;
  } catch { return fail('SIGNER_MISMATCH'); }
}

function indexReference(index: number, staticAccounts: readonly string[],
  lookups: readonly StockTransactionLookupDescriptor[]): StockTransactionAccountReference {
  if (index < staticAccounts.length) {
    const resolved = staticAccounts[index];
    if (resolved === undefined) return fail('TRANSACTION_INVALID');
    return Object.freeze({kind: 'static', accountIndex: index, address: resolved});
  }
  let offset = index - staticAccounts.length;
  for (const [lookupTablePosition, table] of lookups.entries()) {
    if (offset < table.writableIndexes.length) {
      const lookupIndex = table.writableIndexes[offset];
      if (lookupIndex === undefined) return fail('TRANSACTION_INVALID');
      return Object.freeze({kind: 'lookup', accountIndex: index, lookupTablePosition,
        lookupTableAddress: table.lookupTableAddress, lookupIndex, writable: true});
    }
    offset -= table.writableIndexes.length;
  }
  for (const [lookupTablePosition, table] of lookups.entries()) {
    if (offset < table.readonlyIndexes.length) {
      const lookupIndex = table.readonlyIndexes[offset];
      if (lookupIndex === undefined) return fail('TRANSACTION_INVALID');
      return Object.freeze({kind: 'lookup', accountIndex: index, lookupTablePosition,
        lookupTableAddress: table.lookupTableAddress, lookupIndex, writable: false});
    }
    offset -= table.readonlyIndexes.length;
  }
  return fail('TRANSACTION_INVALID');
}

/**
 * Bounded, deterministic wire inspection only. This function performs no RPC,
 * lookup-table resolution, instruction decoding, simulation, signing or send.
 */
export function inspectUnsignedV0TransactionStructure(bytes: Uint8Array,
  requiredTaker: string): UnsignedV0TransactionStructure {
  const taker = expectedSigner(requiredTaker);
  if (!(bytes instanceof Uint8Array) || bytes.byteLength < 1 || bytes.byteLength > maximumTransactionBytes) {
    return fail('TRANSACTION_INVALID');
  }
  const wire = Uint8Array.from(bytes);
  try {
    const transaction = getTransactionDecoder().decode(wire);
    const messageBytes = Uint8Array.from(transaction.messageBytes);
    const message = getCompiledTransactionMessageDecoder().decode(messageBytes);
    if (!Buffer.from(getTransactionEncoder().encode(transaction)).equals(Buffer.from(wire)) ||
        !Buffer.from(getCompiledTransactionMessageEncoder().encode(message)).equals(Buffer.from(messageBytes)) ||
        message.version !== 0) return fail('TRANSACTION_INVALID');

    const header = message.header;
    const staticAccounts = Object.freeze([...message.staticAccounts]);
    const signatureAddresses = Object.keys(transaction.signatures);
    if (header.numSignerAccounts !== 1 || header.numReadonlySignerAccounts !== 0 || staticAccounts[0] !== taker ||
        signatureAddresses.length !== 1 || signatureAddresses[0] !== taker ||
        !Object.hasOwn(transaction.signatures, taker) || transaction.signatures[address(taker)] !== null) {
      return fail('SIGNER_MISMATCH');
    }
    if (staticAccounts.length < 2 || staticAccounts.length > maximumAccounts ||
        new Set(staticAccounts).size !== staticAccounts.length ||
        header.numReadonlyNonSignerAccounts > staticAccounts.length - header.numSignerAccounts ||
        message.lifetimeToken === zeroAddress) return fail('TRANSACTION_INVALID');

    const rawLookups = message.addressTableLookups ?? [];
    const seenTables = new Set<string>();
    let writableCount = 0, readonlyCount = 0;
    const lookups: StockTransactionLookupDescriptor[] = [];
    for (const table of rawLookups) {
      const writableIndexes = [...table.writableIndexes], readonlyIndexes = [...table.readonlyIndexes];
      const allIndexes = [...writableIndexes, ...readonlyIndexes];
      if (seenTables.has(table.lookupTableAddress) || allIndexes.length === 0 ||
          new Set(allIndexes).size !== allIndexes.length ||
          allIndexes.some(index => !Number.isInteger(index) || index < 0 || index > 255)) return fail('TRANSACTION_INVALID');
      seenTables.add(table.lookupTableAddress); writableCount += writableIndexes.length; readonlyCount += readonlyIndexes.length;
      lookups.push(Object.freeze({lookupTableAddress: table.lookupTableAddress,
        writableIndexes: Object.freeze(writableIndexes), readonlyIndexes: Object.freeze(readonlyIndexes)}));
    }
    const accountCount = staticAccounts.length + writableCount + readonlyCount;
    if (accountCount > maximumAccounts || message.instructions.length < 1 ||
        message.instructions.length > maximumInstructions) return fail('TRANSACTION_INVALID');

    const frozenLookups = Object.freeze(lookups);
    const instructions: StockTransactionCompiledInstruction[] = [];
    for (const [instructionIndex, instruction] of message.instructions.entries()) {
      const programAddressIndex = instruction.programAddressIndex;
      const accountIndices = [...(instruction.accountIndices ?? [])];
      if (!Number.isInteger(programAddressIndex) || programAddressIndex < 1 || programAddressIndex >= accountCount ||
          accountIndices.some(index => !Number.isInteger(index) || index < 0 || index >= accountCount)) {
        return fail('TRANSACTION_INVALID');
      }
      const data = Uint8Array.from(instruction.data ?? []);
      instructions.push(Object.freeze({instructionIndex, programAddressIndex,
        program: indexReference(programAddressIndex, staticAccounts, frozenLookups),
        accountIndices: Object.freeze(accountIndices), dataLengthBytes: data.byteLength, dataSha256: digest(data)}));
    }

    return Object.freeze({schemaVersion: 1, kind: 'unsigned_solana_v0_structure', transactionVersion: 0,
      transactionSizeBytes: wire.byteLength, transactionHash: digest(wire), transactionMessageHash: digest(messageBytes),
      requiredSigner: Object.freeze({address: taker, accountIndex: 0, role: 'fee_payer_and_taker'}),
      signatures: Object.freeze({required: 1, present: 0, absent: 1, unsigned: true}),
      header: Object.freeze({numSignerAccounts: 1, numReadonlySignerAccounts: 0,
        numReadonlyNonSignerAccounts: header.numReadonlyNonSignerAccounts}),
      lifetimeToken: Object.freeze({value: message.lifetimeToken, expectedUse: 'recent_blockhash',
        semanticKindVerified: false, mainnetRecencyVerified: false}),
      staticAccountKeys: staticAccounts, addressTableLookups: frozenLookups,
      accountIndexSpace: Object.freeze({static: staticAccounts.length, lookupWritable: writableCount,
        lookupReadonly: readonlyCount, total: accountCount}),
      instructions: Object.freeze(instructions),
      assessment: Object.freeze({status: 'structurally_valid_but_incomplete', structuralIntegrity: 'verified',
        requiredSignerBinding: 'verified', staticAccountResolution: 'complete',
        lookupTableResolution: lookups.length ? 'required' : 'not_applicable', recentBlockhash: 'unverified',
        instructionSemantics: 'unverified', accountState: 'unverified', transactionTerms: 'unverified',
        simulation: 'not_run', approvable: false, readyForSimulation: false, signingEnabled: false,
        broadcastEnabled: false, financialOperationsEnabled: false})});
  } catch (error) {
    if (error instanceof StockTransactionStructureError) throw error;
    return fail('TRANSACTION_INVALID');
  }
}
