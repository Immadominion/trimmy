import {useEffect, useRef} from 'react';

/**
 * Browser and Android Back close an open sheet instead of changing the page
 * under it. Opening adds one history entry at the same address; Back takes it
 * and closes the sheet, or, while `busy` (an order or send being confirmed),
 * puts it back and leaves the sheet open. Closing the sheet another way
 * removes the entry again, unless a navigation has already moved past it.
 */
export function useBackCloses(onClose: () => void, busy = false): void {
  const close = useRef(onClose), held = useRef(busy);
  close.current = onClose; held.current = busy;
  useEffect(() => {
    const token = `${Date.now().toString(36)}${Math.random().toString(36).slice(2)}`;
    const mark = () => window.history.pushState({...(window.history.state ?? {}), trimmySheet: token}, '');
    mark();
    let popped = false;
    const back = () => {
      if (held.current) {mark(); return;}
      popped = true; close.current();
    };
    window.addEventListener('popstate', back);
    return () => {
      window.removeEventListener('popstate', back);
      // Later, so a remount in development (or a navigation in this tick) is seen first.
      window.setTimeout(() => {if (!popped && window.history.state?.trimmySheet === token) window.history.back();}, 0);
    };
  }, []);
}
