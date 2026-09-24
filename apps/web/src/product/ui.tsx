import {useEffect, useState} from 'react';
import type {CSSProperties, ReactNode} from 'react';

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
  return <img className={`sal-art ${className}`} width="960" height="800" alt="Sal, your Wall Street mentor, beside a purple office chair"
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

export function Loading({children = 'Loading your desk…'}: {children?: ReactNode}) {
  return <div className="loading" role="status"><span className="loading-dot" aria-hidden="true"/>{children}</div>;
}
export function Failure({title = 'We couldn’t load this just yet.', message, onRetry}: {title?: string; message?: string; onRetry?: () => void}) {
  return <div className="quiet-error" role="alert"><strong>{title}</strong>{message && <p>{message}</p>}
    {onRetry && <button className="text-button" onClick={onRetry}>Try again</button>}</div>;
}

/** Paper amounts never pass through floating point and never carry a dollar sign. */
export function micros(value: string, decimals = 2): string {
  const negative = value.startsWith('-');
  const digits = BigInt(negative ? value.slice(1) : value);
  const unit = 10n ** BigInt(6 - decimals), scale = 10n ** BigInt(decimals);
  const rounded = (digits + unit / 2n) / unit;
  const whole = (rounded / scale).toLocaleString('en-US');
  const fraction = (rounded % scale).toString().padStart(decimals, '0');
  return `${negative && digits !== 0n ? '−' : ''}${whole}${decimals ? `.${fraction}` : ''}`;
}
export function shares(value: string): string {return micros(value, 6).replace(/\.?0+$/, '') || '0';}
export function toPaperMicros(value: string): string | null {
  if (!/^(?:0|[1-9]\d{0,7})(?:\.\d{1,2})?$/.test(value)) return null;
  const [whole, fraction = ''] = value.split('.');
  const result = BigInt(whole!) * 1_000_000n + BigInt(fraction.padEnd(6, '0'));
  return result > 0n ? result.toString() : null;
}
export function usd(value: number | null | undefined): string {
  return value === null || value === undefined ? 'Unavailable' : new Intl.NumberFormat('en-US', {style: 'currency', currency: 'USD', minimumFractionDigits: 2, maximumFractionDigits: value < 1 ? 4 : 2}).format(value);
}
export function compactUsd(value: number | null): string {
  return value === null ? 'Unavailable' : value < 1_000_000 ? usd(value) : new Intl.NumberFormat('en-US', {style: 'currency', currency: 'USD', notation: 'compact', maximumFractionDigits: 2}).format(value);
}
export function change(value: number | null | undefined): string {
  return value === null || value === undefined ? '—' : `${value > 0 ? '+' : ''}${value.toFixed(2)}%`;
}
export function dateLabel(value: string): string {return new Date(value).toLocaleDateString('en-US', {month: 'short', day: 'numeric'});}
export function errorCopy(error: unknown): string {
  const code = error && typeof error === 'object' && 'code' in error ? String(error.code) : '';
  if (code.includes('STORAGE')) return 'Allow browser storage to keep this desk and its orders safe, then try again.';
  if (code.includes('LOCK')) return 'Use a browser with secure tab coordination, such as current Chrome, to keep paper orders safe.';
  if (code.includes('SESSION_CHANGED')) return 'Your desk changed in another tab. Reload this page before continuing.';
  if (code.includes('PREVIEW_EXPIRED')) return 'This quote expired. Get a new review before confirming.';
  if (/EXPIRED|REVOKED|UNAUTHENTICATED/.test(code)) return 'This session is no longer available. Your saved desk has not been replaced.';
  if (code.includes('CASH_INSUFFICIENT')) return 'This amount is more than the paper cash available.';
  if (code.includes('POSITION_INSUFFICIENT')) return 'Your position changed. Refresh your desk before selling.';
  if (code.includes('PORTFOLIO_CHANGED')) return 'Your desk changed. Refresh it and review a new quote.';
  if (code.includes('RATE_LIMIT')) return 'A few too many requests. Give it a moment, then try again.';
  if (code.includes('PENDING')) return 'An earlier order still needs checking. Return to your desk to recover it first.';
  if (code.includes('PRICE') || code.includes('ADVISORY')) return 'A current paper quote isn’t available for this token. Try another company or come back later.';
  return 'Check your connection and try again. Your saved desk is unchanged.';
}
