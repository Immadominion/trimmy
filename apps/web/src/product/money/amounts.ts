/**
 * Exact own-money amounts. Raw integer strings never pass through floating
 * point, and nothing here invents a price for a balance. Ported from mobile's
 * account_amounts.dart and live_trading.dart so both apps round the same way.
 */
export const USDC_MINT = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';
export const USDC_DECIMALS = 6;
export const SOL_DECIMALS = 9;

const RAW = /^(?:0|[1-9][0-9]*)$/;
const DECIMAL = /^([0-9]+)(?:\.([0-9]+))?$/;

export function isRawAmount(value: unknown, maxDigits = 20): value is string {
  return typeof value === 'string' && value.length <= maxDigits && RAW.test(value);
}

/** Grouped whole part, trailing zeros trimmed. Invalid input is null, never a guess. */
export function formatRawUnits(raw: string, decimals: number): string | null {
  if (!Number.isInteger(decimals) || decimals < 0 || decimals > 30 || raw.length > 40 || !RAW.test(raw)) return null;
  const padded = raw.padStart(decimals + 1, '0');
  const whole = padded.slice(0, padded.length - decimals);
  const fraction = padded.slice(padded.length - decimals).replace(/0+$/, '');
  const grouped = whole.replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  return fraction ? `${grouped}.${fraction}` : grouped;
}

/** A plain decimal for an amount field: no separators, trailing zeros trimmed. */
export function rawDecimal(raw: string, decimals: number): string {
  if (decimals === 0) return raw;
  const text = raw.padStart(decimals + 1, '0');
  const value = `${text.slice(0, text.length - decimals)}.${text.slice(text.length - decimals)}`;
  return value.replace(/\.?0+$/, '');
}

/** Exact typed amount to raw units. Null when invalid, too precise or zero. */
export function amountRaw(text: string, decimals: number): string | null {
  const value = text.trim();
  if (!Number.isInteger(decimals) || decimals < 0 || decimals > 18 || value.length > 40 ||
      !/^[0-9]+(?:\.[0-9]*)?$/.test(value)) return null;
  const [whole = '0', fraction = ''] = value.split('.');
  if (fraction.length > decimals) return null;
  const result = BigInt(whole) * 10n ** BigInt(decimals) + BigInt(fraction.padEnd(decimals, '0') || '0');
  return result > 0n ? result.toString() : null;
}

/** A plain decimal string with thousands separators and no trailing zeros. */
export function groupedDecimal(decimal: string): string {
  const match = DECIMAL.exec(decimal);
  if (!match) return decimal;
  const whole = match[1]!.replace(/^0+(?=[0-9])/, '');
  const fraction = (match[2] ?? '').replace(/0+$/, '');
  const grouped = whole.replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  return fraction ? `${grouped}.${fraction}` : grouped;
}

/** Basis points as a short percentage: 300 is 3%, 20 is 0.2%. */
export function percentFromBps(bps: number): string {
  const whole = Math.trunc(bps / 100), rest = Math.abs(bps % 100);
  if (rest === 0) return `${whole}%`;
  return `${whole}.${rest.toString().padStart(2, '0').replace(/0$/, '')}%`;
}

/** USDC cash as dollars, truncated to cents, like mobile's cash card. */
export function usdcDollars(raw: string): string | null {
  if (!isRawAmount(raw)) return null;
  const cents = BigInt(raw) / 10_000n;
  const whole = (cents / 100n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  return `$${whole}.${(cents % 100n).toString().padStart(2, '0')}`;
}

export function usdcLabel(raw: string): string {return `${formatRawUnits(raw, USDC_DECIMALS) ?? rawDecimal(raw, USDC_DECIMALS)} USDC`;}
export function solLabel(lamports: string): string {return `${formatRawUnits(lamports, SOL_DECIMALS) ?? rawDecimal(lamports, SOL_DECIMALS)} SOL`;}

/** Signed lamports (a simulation may return SOL) as an unsigned SOL amount and its sign. */
export function signedLamports(value: string): {negative: boolean; lamports: string} | null {
  const match = /^(-?)(0|[1-9][0-9]{0,19})$/.exec(value);
  return match ? {negative: match[1] === '-' && match[2] !== '0', lamports: match[2]!} : null;
}

export function shortenAddress(address: string): string {
  return address.length <= 12 ? address : `${address.slice(0, 4)}…${address.slice(-4)}`;
}

function gcd(a: bigint, b: bigint): bigint {while (b) [a, b] = [b, a % b]; return a;}

/**
 * Raw token units to the shares people see. Token-2022 scaled UI amounts make
 * shares = raw / 10^decimals × multiplier. The multiplier comes from the
 * reviewed order or the wallet's own display amount over its raw amount, and
 * is kept as an exact fraction. Without a reading the multiplier is 1.
 */
export class ShareScale {
  static readonly shareDigits = 6;
  private constructor(readonly decimals: number, private readonly numerator: bigint, private readonly denominator: bigint) {}

  static plain(decimals: number): ShareScale {return new ShareScale(decimals, 1n, 1n);}

  /** The multiplier the server read at review time, e.g. `1.0009180758490996`. */
  static fromMultiplier(decimals: number, multiplier: unknown): ShareScale {
    const match = typeof multiplier === 'string' && multiplier.length <= 64 ? DECIMAL.exec(multiplier) : null;
    if (!match || decimals < 0 || decimals > 18) return ShareScale.plain(decimals);
    const fraction = match[2] ?? '';
    const numerator = BigInt(`${match[1]}${fraction}`);
    if (numerator <= 0n) return ShareScale.plain(decimals);
    const denominator = 10n ** BigInt(fraction.length);
    const divisor = gcd(numerator, denominator);
    return new ShareScale(decimals, numerator / divisor, denominator / divisor);
  }

  static fromDisplay(decimals: number, amountRawValue: string, displayAmount: string | null): ShareScale {
    const raw = isRawAmount(amountRawValue) ? BigInt(amountRawValue) : null;
    const display = displayAmount !== null && displayAmount.length <= 80 ? DECIMAL.exec(displayAmount) : null;
    if (decimals < 0 || decimals > 18 || raw === null || raw <= 0n || !display) return ShareScale.plain(decimals);
    const fraction = display[2] ?? '';
    const shown = BigInt(`${display[1]}${fraction}`);
    if (shown <= 0n) return ShareScale.plain(decimals);
    const numerator = shown * 10n ** BigInt(decimals), denominator = raw * 10n ** BigInt(fraction.length);
    const divisor = gcd(numerator, denominator);
    return new ShareScale(decimals, numerator / divisor, denominator / divisor);
  }

  get scaled(): boolean {return this.numerator !== this.denominator;}

  private scaledShares(raw: string, nearest = false): [bigint, number] {
    if (!isRawAmount(raw, 40)) return [0n, 0];
    const value = BigInt(raw);
    if (value <= 0n) return [0n, 0];
    const at = (digits: number): [bigint, number] => {
      const top = value * this.numerator;
      const bottom = this.denominator * 10n ** BigInt(this.decimals - digits);
      return [nearest ? (top * 2n + bottom) / (bottom * 2n) : top / bottom, digits];
    };
    const short = at(Math.min(this.decimals, ShareScale.shareDigits));
    return short[0] > 0n ? short : at(this.decimals);
  }

  private static read([units, digits]: [bigint, number]): string {
    return formatRawUnits(units.toString(), digits) ?? rawDecimal(units.toString(), digits);
  }

  /** Shares for an amount field: rounded down, no separators. */
  shares(raw: string): string {const [units, digits] = this.scaledShares(raw); return rawDecimal(units.toString(), digits);}
  /** Balances and minimums: rounded down, grouped. */
  label(raw: string): string {return ShareScale.read(this.scaledShares(raw));}
  /** Quoted figures: rounded to nearest so a typed amount reads back the same. */
  approx(raw: string): string {return ShareScale.read(this.scaledShares(raw, true));}
  /** Records such as history: full precision, rounded down. */
  exact(raw: string): string {
    if (!isRawAmount(raw, 40) || raw === '0') return '0';
    return ShareScale.read([BigInt(raw) * this.numerator / this.denominator, this.decimals]);
  }
  /** Raw units for typed shares, to the nearest raw unit. Null when invalid or zero. */
  raw(shares: string): string | null {
    const typed = amountRaw(shares, this.decimals);
    if (typed === null) return null;
    const result = (BigInt(typed) * this.denominator * 2n + this.numerator) / (this.numerator * 2n);
    return result > 0n ? result.toString() : null;
  }
}
