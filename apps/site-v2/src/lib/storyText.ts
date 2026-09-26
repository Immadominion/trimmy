/**
 * When and where a screen's copy shows, for screens whose pictures are
 * rendered frames. The section that plays the frames knows when each shot
 * comes to rest and where its picture leaves room for type, so it sets these;
 * Screen reads them every frame.
 *
 * Times are in viewports of scroll, relative to where the screen starts.
 */
export type TextBox = { left: number; top: number; width: number; height: number; center: boolean; middle: boolean };
export type TextPlan = { fadeIn: [number, number]; fadeOut: [number, number]; box?: TextBox };

const plans = new Map<number, TextPlan>();
let version = 0;

export function setTextPlans(next: Map<number, TextPlan>) {
  plans.clear();
  for (const [index, plan] of next) plans.set(index, plan);
  version++;
}

export const getTextPlan = (index: number) => plans.get(index);

/** Changes whenever the plans do, so readers can skip work when it has not. */
export const textPlanVersion = () => version;
