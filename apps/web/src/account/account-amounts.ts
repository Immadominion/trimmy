/**
 * Exact presentation helpers for account reads. Raw integer strings never pass
 * through floating point, and nothing here prices a balance.
 */

/** Groups the whole part with commas and trims trailing fraction zeros; null on invalid input. */
export function formatRawUnits(raw: string, decimals: number): string | null {
  if (!Number.isInteger(decimals) || decimals < 0 || decimals > 30 || raw.length > 40) return null;
  if (!/^(0|[1-9][0-9]*)$/.test(raw)) return null;
  const padded = raw.padStart(decimals + 1, '0');
  const whole = padded.slice(0, padded.length - decimals);
  const fraction = padded.slice(padded.length - decimals).replace(/0+$/, '');
  let grouped = '';
  for (let index = 0; index < whole.length; index++) {
    const remaining = whole.length - index;
    grouped += whole[index];
    if (remaining > 1 && remaining % 3 === 1) grouped += ',';
  }
  return fraction.length === 0 ? grouped : `${grouped}.${fraction}`;
}

/** Start and end of a long address; the full value belongs in an accessible label. */
export function shortenAddress(address: string): string {
  if (address.length <= 12) return address;
  return `${address.slice(0, 4)}…${address.slice(-4)}`;
}

/** Local wall-clock HH:MM for "checked at" notes; null when the timestamp is unreadable. */
export function formatClockTime(iso: string): string | null {
  const value = new Date(iso);
  if (Number.isNaN(value.getTime())) return null;
  const two = (number: number) => String(number).padStart(2, '0');
  return `${two(value.getHours())}:${two(value.getMinutes())}`;
}
