/** Opens and closes the Get the app panel from anywhere on the page. */

let open = false;
let opener: HTMLElement | null = null;
const listeners = new Set<() => void>();

function set(next: boolean) {
  if (open === next) return;
  open = next;
  for (const listener of listeners) listener();
}

export const isGetAppOpen = () => open;

export function subscribeGetApp(listener: () => void) {
  listeners.add(listener);
  return () => { listeners.delete(listener); };
}

export function openGetApp() {
  opener = document.activeElement instanceof HTMLElement ? document.activeElement : null;
  set(true);
}

/** Closes the panel and gives focus back to whatever opened it. */
export function closeGetApp() {
  set(false);
  opener?.focus({ preventScroll: true });
  opener = null;
}
