export function productApiBase(env: Record<string, unknown> = import.meta.env): string | null {
  const value = env['VITE_TRIMMY_PRODUCT_API_URL'];
  if (value === '/api' && env['DEV'] === true) return value;
  if (typeof value !== 'string') return null;
  try {
    const url = new URL(value);
    return url.protocol === 'https:' && url.origin === value && !url.username && !url.password ? value : null;
  } catch {return null;}
}
