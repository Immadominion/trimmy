import {useEffect, type RefObject} from 'react';

const FOCUSABLE = 'a[href], button:not([disabled]), input:not([disabled]):not([type="hidden"]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';
let open = 0;

/**
 * For an open dialog: Tab and Shift+Tab stay inside it, focus goes back to
 * whatever opened it when it closes, and the page behind it does not scroll.
 * Each dialog still decides where focus starts.
 */
export function useModalFocus(panel: RefObject<HTMLElement | null>): void {
  useEffect(() => {
    const opener = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    const trap = (event: KeyboardEvent) => {
      const element = panel.current;
      if (event.key !== 'Tab' || !element) return;
      const items = [...element.querySelectorAll<HTMLElement>(FOCUSABLE)].filter(item => !item.closest('[hidden]'));
      if (!items.length) {event.preventDefault(); return;}
      const first = items[0]!, last = items[items.length - 1]!, active = document.activeElement;
      if (event.shiftKey ? active === first || !element.contains(active) : active === last || !element.contains(active)) {
        event.preventDefault();
        (event.shiftKey ? last : first).focus();
      }
    };
    document.addEventListener('keydown', trap);
    if (open++ === 0) document.documentElement.classList.add('modal-open');
    return () => {
      document.removeEventListener('keydown', trap);
      if (--open === 0) document.documentElement.classList.remove('modal-open');
      if (opener?.isConnected && !panel.current?.isConnected) opener.focus();
    };
  }, [panel]);
}
