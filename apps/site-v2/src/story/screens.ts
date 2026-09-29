/**
 * Story beats in order. Native scroll moves continuously between them.
 *
 * Product availability is shared with the phone preview in availability.ts.
 */
import {PRODUCT_AVAILABILITY} from './availability';

export type Screen = {
  id: string;
  /** A year. Small, above the text. */
  stamp?: string;
  /** The line the screen is about. */
  heading?: string;
  /** Words of the heading set very large when it stands alone on screen. */
  emphasis?: string[];
  /** Supporting lines under a heading, or the main lines when there is no heading. One string per line. */
  body?: string[];
  /** A "Large line" in V4: set alone, at heading size. */
  large?: string;
  /** Close with "with trimmy" as the logo lockup, and the Solana line. */
  signature?: boolean;
  /** An ambient sound that plays while this screen is up. A path under public/. */
  sound?: string;
  /** Short supporting note, separate from the main explanation. */
  note?: string;
  /**
   * How much scroll this screen takes, in viewports. Default 1. Screens whose
   * rendered shots run long get more, so the move has room to play out instead
   * of flashing past in one flick: the opening, the market (the camera flies
   * on through the doors at its end) and the exchange floor.
   */
  length?: number;
  /** Build status is explicit rather than implied by a product preview. */
  status?: { label: string; text: string }[];
  /** Show the Get the app button (and Play on the web, once hosted) under the copy. */
  cta?: boolean;
  /** The last line of the page; the X, Privacy and Terms links go under it. */
  footer?: string;
};

export const SCREENS: Screen[] = [
  { id: "intern", heading: "It’s your first day on Wall Street, intern." },
  { id: "speed", heading: "So let’s get you up to speed." },
  { id: "1653", stamp: "1653", heading: "A wall gave a street its name.", emphasis: ["wall", "street"], length: 2.6 },
  {
    id: "1790",
    stamp: "1790",
    length: 2.3,
    heading: "The war debt became IOUs you could trade.",
    body: ["They were called bonds. People bought and sold them, and New York became the place to do it."],
  },
  {
    id: "1792",
    stamp: "1792",
    length: 2.3,
    heading: "Twenty-four brokers. One agreement.",
    body: ["They set rules for trading with one another. The New York Stock Exchange traces its beginning to that agreement."],
  },
  { id: "market", large: "The street became the market.", length: 2.3 },
  {
    id: "ticker",
    length: 1.25,
    heading: "Then the numbers learned to run.",
    body: [
      "The stock ticker arrived in 1867. Prices moved on paper tape.",
      "Phones followed. The market got faster.",
    ],
  },
  {
    id: "floor",
    length: 1.3,
    heading: "Then the floor found its voice.",
    sound: "/audio/floor.mp3",
    body: [
      "Buyers, sellers and brokers gathered around trading posts.",
      "Orders called across the room. Prices changing. The opening bell.",
    ],
  },
  {
    id: "performance",
    length: 1.1,
    large: "The market was numbers. Wall Street made it a performance.",
  },
  {
    id: "hand",
    heading: "Now the floor fits in your hand.",
    body: ["Buy and sell stocks for practice. Learn as you go."],
    signature: true,
    cta: true,
  },
  {
    id: "virtual-money",
    heading: "10,000 in virtual money. Yours to start with.",
    body: ["Pick your first stock. Buy, sell and see what happens, without spending your own money."],
  },
  {
    id: "stocks",
    heading: "Real stock prices. Your decisions.",
    body: ["Follow companies you know. Watch their prices move. Choose when to buy or sell."],
    note: "Prices in this website demo are examples.",
  },
  {
    id: "sal",
    heading: "A little guidance from Sal.",
    body: ["Your boss has work for you. Check the evidence, make your call and file your update. Twenty intern assignments to get you started."],
  },
  {
    id: "trim",
    heading: "Sell some. Keep the rest.",
    body: ["When a stock goes up, sell part of it to keep some of the gain. The shares you keep can still grow. That’s a trim."],
    note: "Try it on the phone. It’s only a demo.",
  },
  {
    id: "career",
    heading: "Rookie today. Legend one day.",
    body: ["Complete missions. Earn points called Trims. Build a streak and work your way through six ranks."],
  },
  {
    id: "build",
    heading: "Here’s where we’re at.",
    status: PRODUCT_AVAILABILITY.map(group => ({label: group.label, text: group.items.join('. ') + '.'})),
    note: "Real-money trading uses tokenized assets. Availability depends on the asset, issuer and your location. Card checkout is still in testing.",
  },
  {
    id: "close",
    heading: "Your desk is ready.",
    body: ["Play in your browser or get Trimmy for Android, including Solana Seeker."],
    footer: "Trimmy is a Wall Street simulation game.",
  },
];

/** Scroll length of each screen, in viewports. */
export const LENGTHS = SCREENS.map((screen) => screen.length ?? 1);

/**
 * Height of the scroll track, in viewports: every screen's length except the
 * last, plus one viewport so the last screen can come fully into view.
 */
export const TRACK = LENGTHS.slice(0, -1).reduce((a, b) => a + b, 0) + 1;
