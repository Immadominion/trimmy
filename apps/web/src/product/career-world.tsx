import {useEffect, useLayoutEffect, useMemo, useRef, useState} from 'react';
import type {CSSProperties} from 'react';
import {Loading, art} from './ui';

export interface CareerWorldAssignment {
  readonly id: string;
  readonly ordinal: number;
  readonly title: string;
  readonly brief: string;
  readonly speaker: string;
  readonly art: string;
  readonly district: string;
  readonly completedAt: string | null;
  readonly step?: number;
}
export interface CareerWorldProps {
  readonly assignments: readonly CareerWorldAssignment[] | null;
  readonly loading?: boolean;
  readonly error?: string | null;
  readonly motion?: boolean;
  readonly onOpen: (id: string) => void;
  readonly onRetry?: () => void;
}

/** Existing generated mobile scenery; unknown server art never becomes an arbitrary URL. */
export const careerScenery = ['exchange', 'bull', 'ticker', 'coffee', 'desk', 'bell', 'newspaper', 'skyscraper', 'taxi',
  'street-sign', 'briefcase', 'calculator', 'reports', 'plant', 'clock', 'headset', 'pencil', 'safe', 'balance', 'chart-board',
  'conference', 'subway', 'fountain', 'folders', 'magnifier', 'mailbox', 'lobby', 'trophy', 'bridge', 'rooftop'] as const;
export function careerSceneryUrl(name: string): string {
  return art(`career-world/${careerScenery.find(value => value === name) ?? 'exchange'}.png`);
}
const positions = [.27, .68, .51, .77, .32, .61, .24, .71, .45, .26, .73, .49, .76, .34, .59, .23, .66, .42, .74, .28];
function nodeX(index: number, width: number): number {
  const fraction = positions[((index % positions.length) + positions.length) % positions.length]!;
  return Math.max(82, Math.min(width - 82, width * fraction));
}
function streetPath(width: number, rowHeight: number, count: number): string {
  const center = rowHeight * .44;
  let path = `M ${nodeX(-1, width)} ${center - rowHeight}`;
  for (let i = -1; i < count; i++) {
    const fromY = center + i * rowHeight, toY = fromY + rowHeight;
    const bend = .32 + ((i % 3 + 3) % 3) * .055;
    path += ` C ${nodeX(i, width)} ${fromY + rowHeight * bend} ${nodeX(i + 1, width)} ${toY - rowHeight * (1 - bend)} ${nodeX(i + 1, width)} ${toY}`;
  }
  return path;
}
function Seal() {
  return <svg className="career-world-seal" viewBox="0 0 48 48" aria-hidden="true"><path d="m24 2 5 4 6-.5 2.5 5.5 5.5 2.5-.5 6 4 4.5-4 5 .5 6-5.5 2.5-2.5 5.5-6-.5-5 4-4.5-4-6 .5-2.5-5.5L5 35l.5-6L2 24l3.5-4.5L5 13.5l5.5-2.5L13 5.5l6 .5Z" fill="#2c956c"/><path d="m15 24 6 6 12-13" fill="none" stroke="#fff" strokeWidth="3.5" strokeLinecap="round" strokeLinejoin="round"/></svg>;
}
function Lock() {
  return <svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><rect x="5.5" y="10" width="13" height="10" rx="3"/><path d="M8 10V7a4 4 0 0 1 8 0v3m-4 4v2"/></svg>;
}

export function CareerWorld({assignments, loading = false, error = null, motion = true, onOpen, onRetry}: CareerWorldProps) {
  const viewport = useRef<HTMLDivElement>(null), canvas = useRef<HTMLOListElement>(null);
  const positioned = useRef(false);
  const [geometry, setGeometry] = useState({width: 400, rowHeight: 300});
  const [futureCount, setFutureCount] = useState(10);
  const [pageVisible, setPageVisible] = useState(() => typeof document === 'undefined' || !document.hidden);
  const current = assignments?.find(item => !item.completedAt);
  const count = (assignments?.length ?? 0) + futureCount;
  const path = useMemo(() => streetPath(geometry.width, geometry.rowHeight, count), [geometry, count]);

  useEffect(() => {
    const update = () => setPageVisible(!document.hidden);
    document.addEventListener('visibilitychange', update);
    return () => document.removeEventListener('visibilitychange', update);
  }, []);
  useLayoutEffect(() => {
    const list = canvas.current, scroll = viewport.current;
    if (!list || !scroll) return;
    const firstRow = list.querySelector<HTMLElement>('.career-world-row');
    const measure = () => {
      const width = list.getBoundingClientRect().width, rowHeight = firstRow?.getBoundingClientRect().height ?? 0;
      if (width > 0 && rowHeight > 0) setGeometry(prior => prior.width === width && prior.rowHeight === rowHeight ? prior : {width, rowHeight});
      if (!positioned.current && width > 0) {
        const active = list.querySelector<HTMLElement>('[data-current="true"]');
        scroll.scrollTop = Math.max(0, (active?.offsetTop ?? 0) - (firstRow?.offsetTop ?? 0) - 24);
        positioned.current = true;
      }
    };
    measure();
    if (typeof ResizeObserver === 'undefined') {window.addEventListener('resize', measure); return () => window.removeEventListener('resize', measure);}
    const observer = new ResizeObserver(measure); observer.observe(list); if (firstRow) observer.observe(firstRow);
    return () => observer.disconnect();
  }, [assignments?.length]);

  if (!assignments?.length) return <section className="career-world-empty" aria-label="Your career path">{loading
    ? <Loading>Opening your assignments…</Loading>
    : <><img src={careerSceneryUrl('exchange')} alt="" width="160" height="160"/><p>{error ?? 'Your assignments couldn’t load.'}</p>{onRetry && <button className="text-button" onClick={onRetry}>Try again</button>}</>}</section>;

  return <div className="career-world" data-motion={motion && pageVisible ? 'on' : 'off'}>
    {error && <div className="career-world-error" role="status"><span>{error}</span>{onRetry && <button className="text-button" onClick={onRetry}>Retry</button>}</div>}
    <div className="career-world-scroll" role="region" aria-label="Your career path" tabIndex={0} ref={viewport}
      onScroll={event => {
        const element = event.currentTarget;
        if (element.scrollHeight > element.clientHeight && element.scrollHeight - element.clientHeight - element.scrollTop < 600)
          setFutureCount(value => Math.min(180, value + 10));
      }}>
      <ol className="career-world-street" ref={canvas}>
        <li className="career-world-road" aria-hidden="true"><svg width="100%" height={count * geometry.rowHeight} viewBox={`0 0 ${geometry.width} ${count * geometry.rowHeight}`} preserveAspectRatio="none"><path className="career-world-road-bed" d={path}/><path className="career-world-road-dots" d={path}/></svg></li>
        {Array.from({length: count}, (_, index) => {
          const assignment = assignments[index];
          const done = !!assignment?.completedAt, active = !!assignment && assignment.id === current?.id;
          const x = nodeX(index, geometry.width), artSize = Math.min(178, geometry.width * .41);
          const sceneryLeft = x < geometry.width / 2 ? geometry.width - artSize - 12 : 12;
          const titleLeft = Math.max(12, Math.min(geometry.width - 202, x - 95));
          const style = {'--world-node-x': `${x}px`, '--world-label-left': `${titleLeft}px`,
            '--world-art-left': `${sceneryLeft}px`, '--world-art-size': `${artSize}px`} as CSSProperties;
          const scenery = assignment?.art ?? careerScenery[index % careerScenery.length]!;
          const label = assignment ? `Day ${assignment.ordinal}, ${assignment.title}, ${done ? 'filed' : active ? 'current assignment' : 'locked'}` : 'Coming later';
          const nodeContents = done ? <Seal/> : active ? assignment!.ordinal : assignment ? <Lock/> : <span aria-hidden="true">···</span>;
          return <li className={`career-world-row${active ? ' current' : ''}${done ? ' filed' : ''}${!assignment ? ' future' : ''}`}
            key={assignment?.id ?? `future-${index}`} data-current={active ? 'true' : undefined} data-assignment-id={assignment?.id} style={style}>
            {(index % 5 === 0) && <p className="career-world-district">{assignment?.district ?? (index === assignments.length ? 'Beyond the first month' : 'The city keeps growing')}</p>}
            <img className="career-world-scenery" src={careerSceneryUrl(scenery)} width="178" height="178" loading="lazy" decoding="async" alt=""/>
            {index % 2 === 0 && <img className="career-world-small-scenery" src={careerSceneryUrl(careerScenery[(index * 7 + 3) % careerScenery.length]!)} width="64" height="64" loading="lazy" decoding="async" alt=""/>}
            {assignment && !active && !done ? <details className="career-world-locked">
              <summary className="career-world-node" aria-label={`${label}. Preview assignment.`}>{nodeContents}</summary>
              <div className="career-world-preview"><strong>{assignment.title}</strong><p>{assignment.brief}</p><small>Complete day {assignment.ordinal - 1} to open this desk.</small></div>
            </details> : assignment ? <button className="career-world-node" type="button" aria-label={label} aria-current={active ? 'step' : undefined} onClick={() => onOpen(assignment.id)}>{nodeContents}</button>
              : <div className="career-world-node" aria-label={label}>{nodeContents}</div>}
            <div className="career-world-label">{active && <span className="career-world-current-label">{(assignment?.step ?? 0) > 0 ? 'Continue' : 'Start here'}</span>}<strong>{assignment?.title ?? 'Coming later'}</strong>{done && <span className="career-world-filed-label">Filed</span>}</div>
          </li>;
        })}
      </ol>
    </div>
  </div>;
}
