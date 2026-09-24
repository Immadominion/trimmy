/** Entirely fictional local examples. These are not issuer assets or market feeds. */
import type { PracticeAssetId } from '@trimmy/domain';
export const FIXTURE_DATE = '2026-09-11';
export const CHART_RANGES = ['1D', '1W', '1M', '3M', '1Y'] as const;
export type ChartRange = typeof CHART_RANGES[number];
export type Sector = 'Technology' | 'Energy' | 'Consumer' | 'Finance';
export type WorkspaceView = 'portfolio' | 'watchlist' | 'explore';
export interface Stock {
  readonly id: PracticeAssetId;
  readonly symbol: string;
  readonly name: string;
  readonly sector: Sector;
  readonly priceCents: number;
  readonly dayChangeBps: number;
  readonly quantityMilli: number;
  readonly costBasisCents: number;
  readonly color: string;
  readonly ink: string;
  readonly mark: 'diamond' | 'orbit' | 'leaf' | 'arch' | 'steps' | 'wave' | 'grid' | 'sun';
  readonly description: string;
  readonly marketCap: string;
  readonly volume: string;
  readonly yearLowCents: number;
  readonly yearHighCents: number;
}

export const STOCKS: readonly Stock[] = Object.freeze([
  {id: 'forma', symbol: 'FRMA', name: 'Forma Studio', sector: 'Technology', priceCents: 18432, dayChangeBps: 182, quantityMilli: 42000, costBasisCents: 712400, color: '#E4DAF4', ink: '#574372', mark: 'diamond', description: 'Design tools for the next generation of independent businesses. Forma brings everyday creative work into one connected workspace.', marketCap: '$42.8B', volume: '2.4M', yearLowCents: 12340, yearHighCents: 20180},
  {id: 'orbital', symbol: 'ORBT', name: 'Orbital Systems', sector: 'Technology', priceCents: 24780, dayChangeBps: 246, quantityMilli: 17500, costBasisCents: 392000, color: '#DDE9FA', ink: '#315A91', mark: 'orbit', description: 'Orbital builds computing infrastructure for ambitious teams, from small research labs to connected cities.', marketCap: '$86.2B', volume: '5.1M', yearLowCents: 16820, yearHighCents: 27350},
  {id: 'grove', symbol: 'GRVE', name: 'Grove Energy', sector: 'Energy', priceCents: 8625, dayChangeBps: -74, quantityMilli: 56000, costBasisCents: 460800, color: '#DEEDDF', ink: '#3A6C40', mark: 'leaf', description: 'Cleaner energy, closer to home. Grove develops local renewable networks and energy storage for growing communities.', marketCap: '$18.5B', volume: '1.8M', yearLowCents: 6720, yearHighCents: 9840},
  {id: 'harbor', symbol: 'HBR', name: 'Harbor Financial', sector: 'Finance', priceCents: 13240, dayChangeBps: 63, quantityMilli: 28000, costBasisCents: 346700, color: '#F2E4CE', ink: '#886536', mark: 'arch', description: 'Everyday banking built around small businesses. Harbor develops payments, accounts and financial tools for local entrepreneurs.', marketCap: '$31.4B', volume: '1.2M', yearLowCents: 10460, yearHighCents: 14910},
  {id: 'mesa', symbol: 'MESA', name: 'Mesa Collective', sector: 'Consumer', priceCents: 5670, dayChangeBps: 114, quantityMilli: 39000, costBasisCents: 207880, color: '#F8DFD4', ink: '#A34D34', mark: 'steps', description: 'Thoughtfully made objects for everyday living. Mesa works with independent makers to bring useful, lasting design to more homes.', marketCap: '$8.7B', volume: '842K', yearLowCents: 3840, yearHighCents: 6420},
  {id: 'nori', symbol: 'NORI', name: 'Nori Foods', sector: 'Consumer', priceCents: 7280, dayChangeBps: -128, quantityMilli: 0, costBasisCents: 0, color: '#E4EBCF', ink: '#657833', mark: 'wave', description: 'Nori connects food producers with neighborhood shops through a simpler, less wasteful supply chain.', marketCap: '$12.1B', volume: '965K', yearLowCents: 5320, yearHighCents: 8260},
  {id: 'pollen', symbol: 'PLLN', name: 'Pollen Networks', sector: 'Technology', priceCents: 11685, dayChangeBps: 318, quantityMilli: 0, costBasisCents: 0, color: '#F7EDC4', ink: '#8C7125', mark: 'grid', description: 'A connected layer for connected places. Pollen creates reliable networking tools for teams that work beyond a single office.', marketCap: '$24.6B', volume: '3.6M', yearLowCents: 7530, yearHighCents: 12800},
  {id: 'helios', symbol: 'HLIO', name: 'Helios Works', sector: 'Energy', priceCents: 9450, dayChangeBps: 86, quantityMilli: 0, costBasisCents: 0, color: '#F8E6CE', ink: '#976226', mark: 'sun', description: 'Helios designs practical solar systems for commercial buildings, with a focus on making existing spaces more efficient.', marketCap: '$16.2B', volume: '1.6M', yearLowCents: 6860, yearHighCents: 11090},
]);

export const DEFAULT_WATCHLIST = ['forma', 'orbital', 'pollen', 'nori'] as const;
export const SECTORS: readonly Sector[] = ['Technology', 'Energy', 'Consumer', 'Finance'];

export interface ChartPoint {readonly label: string; readonly valueCents: number}
const SHAPE = [0, 0.13, 0.05, 0.25, 0.18, 0.3, 0.2, 0.36, 0.33, 0.53, 0.44, 0.58, 0.5, 0.66, 0.61, 0.68, 0.79, 0.7, 0.88, 0.82, 0.91, 0.84, 0.96, 1] as const;
const RANGE_CHANGE: Record<ChartRange, number> = {'1D': 0, '1W': 0.028, '1M': 0.074, '3M': 0.112, '1Y': 0.238};

export function chartSeries(stock: Stock, range: ChartRange): ChartPoint[] {
  const seed = STOCKS.findIndex(item => item.id === stock.id) + 1;
  const change = range === '1D' ? stock.dayChangeBps / 10000 : RANGE_CHANGE[range] * (0.7 + seed * 0.09);
  const start = stock.priceCents / (1 + change);
  return SHAPE.map((progress, index) => {
    const wobble = index === 0 || index === SHAPE.length - 1 ? 0 : Math.sin((index + seed) * 2.15) * Math.abs(change) * 0.1;
    return {label: pointLabel(range, index, SHAPE.length), valueCents: Math.round(start + (stock.priceCents - start) * progress + stock.priceCents * wobble)};
  });
}

function pointLabel(range: ChartRange, index: number, count: number): string {
  const fraction = index / (count - 1);
  if (range === '1D') {
    const minutes = 9 * 60 + 30 + Math.round(fraction * 390);
    return `${String(Math.floor(minutes / 60)).padStart(2, '0')}:${String(minutes % 60).padStart(2, '0')}`;
  }
  const days = {'1W': 7, '1M': 30, '3M': 90, '1Y': 365}[range];
  const day = new Date(`${FIXTURE_DATE}T12:00:00.000Z`);
  day.setUTCDate(day.getUTCDate() - Math.round(days * (1 - fraction)));
  return new Intl.DateTimeFormat('en-US', {month: 'short', day: 'numeric', timeZone: 'UTC'}).format(day);
}

export function holdingValueCents(stock: Stock): number {
  return Math.round(stock.priceCents * stock.quantityMilli / 1000);
}

export function portfolioSeries(range: ChartRange): ChartPoint[] {
  const holdings = STOCKS.filter(stock => stock.quantityMilli > 0);
  const series = holdings.map(stock => chartSeries(stock, range));
  return SHAPE.map((_, index) => ({
    label: pointLabel(range, index, SHAPE.length),
    valueCents: holdings.reduce((sum, stock, holdingIndex) => sum + Math.round((series[holdingIndex]?.[index]?.valueCents ?? stock.priceCents) * stock.quantityMilli / 1000), 0),
  }));
}

export const money = (cents: number): string => new Intl.NumberFormat('en-US', {style: 'currency', currency: 'USD'}).format(cents / 100);
export const percent = (basisPoints: number): string => `${basisPoints >= 0 ? '+' : ''}${(basisPoints / 100).toFixed(2)}%`;
