import {useEffect, useState} from 'react';
import type {CSSProperties, ReactNode} from 'react';
import {t} from '../i18n/runtime';
import {useT} from '../i18n/react';
import * as fmt from '../i18n/format';

export const art = (file: string) => `/trimmy/${file}`;

export function SalArt({motion = true, className = ''}: {motion?: boolean; className?: string}) {
  const [animate, setAnimate] = useState(false);
  useEffect(() => {
    const query = window.matchMedia('(prefers-reduced-motion: reduce)');
    let finished = false;
    const update = () => {if (query.matches || document.hidden) finished = true; setAnimate(motion && !finished);};
    update();
    const timer = window.setTimeout(() => {finished = true; setAnimate(false);}, 3600);
    query.addEventListener('change', update); document.addEventListener('visibilitychange', update);
    return () => {clearTimeout(timer); query.removeEventListener('change', update); document.removeEventListener('visibilitychange', update);};
  }, [motion]);
  const tr = useT();
  return <img className={`sal-art ${className}`} width="960" height="800" alt={tr('common.salArtAlt')}
    src={art(animate ? 'sal-chair-welcome-v3.webp' : 'sal-chair-welcome-v3-still.png')}/>;
}

export function CompanyLogo({name, url, large = false, size}: {name: string; url?: string | null; large?: boolean; size?: number}) {
  const [failedUrl, setFailedUrl] = useState<string | null>(null);
  const initial = Array.from(name.trim())[0]?.toLocaleUpperCase() ?? '?';
  return <span className={`company-logo company-coin${large ? ' large' : ''}`} aria-hidden="true"
    style={size === undefined ? undefined : {'--company-coin-size': `${size}px`} as CSSProperties}>
    <span className="company-logo-face">{url && url !== failedUrl
      ? <img key={url} src={url} alt="" loading="lazy" decoding="async" referrerPolicy="no-referrer" onError={() => setFailedUrl(url)}/>
      : <span className="company-logo-initial">{initial}</span>}</span>
  </span>;
}

export function Loading({children}: {children?: ReactNode}) {
  const tr = useT();
  return <div className="loading" role="status"><span className="loading-dot" aria-hidden="true"/>{children ?? tr('common.loadingDesk')}</div>;
}
export function Failure({title, message, onRetry}: {title?: string; message?: string; onRetry?: () => void}) {
  const tr = useT();
  return <div className="quiet-error" role="alert"><strong>{title ?? tr('common.loadFailed')}</strong>{message && <p>{message}</p>}
    {onRetry && <button className="text-button" onClick={onRetry}>{tr('common.tryAgain')}</button>}</div>;
}

/**
 * Paper amounts never pass through floating point and never carry a dollar
 * sign. `micros` and `shares` are for reading, in the page's language;
 * `paperPlain` and `sharesPlain` are the same figures in English form, for
 * logic and (through `fmt.decimalInput`) for amount fields.
 */
export function micros(value: string, decimals = 2): string {return fmt.number(paperPlain(value, decimals));}
export function shares(value: string): string {return fmt.number(sharesPlain(value));}
export function paperPlain(value: string, decimals = 2): string {
  const negative = value.startsWith('-');
  const digits = BigInt(negative ? value.slice(1) : value);
  const unit = 10n ** BigInt(6 - decimals), scale = 10n ** BigInt(decimals);
  const rounded = (digits + unit / 2n) / unit;
  const whole = (rounded / scale).toLocaleString('en-US');
  const fraction = (rounded % scale).toString().padStart(decimals, '0');
  return `${negative && digits !== 0n ? '−' : ''}${whole}${decimals ? `.${fraction}` : ''}`;
}
export function sharesPlain(value: string): string {return paperPlain(value, 6).replace(/\.?0+$/, '') || '0';}
/** A typed paper amount to micros. Either decimal mark is accepted outside English (see `fmt.normalizeDecimalInput`). */
export function toPaperMicros(typed: string): string | null {
  const value = fmt.normalizeDecimalInput(typed);
  if (!/^(?:0|[1-9]\d{0,7})(?:\.\d{1,2})?$/.test(value)) return null;
  const [whole, fraction = ''] = value.split('.');
  const result = BigInt(whole!) * 1_000_000n + BigInt(fraction.padEnd(6, '0'));
  return result > 0n ? result.toString() : null;
}
/** A US dollar price. Prices under $1 keep up to four decimals. */
export function usd(value: number | null | undefined): string {
  return value === null || value === undefined ? t('common.unavailable') : fmt.usd(new Intl.NumberFormat('en-US', {style: 'currency', currency: 'USD', minimumFractionDigits: 2, maximumFractionDigits: value < 1 ? 4 : 2}).format(value));
}
/** Large US dollar figures (volume, market cap) in short form from one million up. */
export function compactUsd(value: number | null): string {
  return value === null ? t('common.unavailable') : value < 1_000_000 ? usd(value) : fmt.usd(new Intl.NumberFormat('en-US', {style: 'currency', currency: 'USD', notation: 'compact', maximumFractionDigits: 2}).format(value));
}
/** A day's price change in percent: `+1.23%`, `-0.50%`; the no-value mark when unknown. */
export function change(value: number | null | undefined): string {
  return value === null || value === undefined ? t('common.noValue') : fmt.percent(`${value > 0 ? '+' : ''}${value.toFixed(2)}%`);
}
export function dateLabel(value: string): string {return fmt.date(value, 'en-US', {month: 'short', day: 'numeric'});}
export function errorCopy(error: unknown): string {
  const code = error && typeof error === 'object' && 'code' in error ? String(error.code) : '';
  if (code.includes('STORAGE')) return t('common.error.storage');
  if (code.includes('LOCK')) return t('common.error.lock');
  if (code.includes('SESSION_CHANGED')) return t('common.error.sessionChanged');
  if (code.includes('PREVIEW_EXPIRED')) return t('common.error.previewExpired');
  if (/EXPIRED|REVOKED|UNAUTHENTICATED/.test(code)) return t('common.error.sessionEnded');
  if (code.includes('CASH_INSUFFICIENT')) return t('common.error.cashInsufficient');
  if (code.includes('POSITION_INSUFFICIENT')) return t('common.error.positionInsufficient');
  if (code.includes('PORTFOLIO_CHANGED')) return t('common.error.portfolioChanged');
  if (code.includes('RATE_LIMIT')) return t('common.error.rateLimited');
  if (code.includes('PENDING')) return t('common.error.pending');
  if (code.includes('PRICE') || code.includes('ADVISORY')) return t('common.error.price');
  return t('common.error.network');
}
