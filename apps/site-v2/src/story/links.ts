/**
 * Where the page's buttons lead. Change them here only.
 *
 * `web` is the Trimmy web app (trimmy/apps/web). It is not hosted yet, so its
 * buttons stay hidden, and the Get the app panel lists it as coming soon,
 * until it has an address. The APK is the Stocklana demo build on GitHub,
 * there for the hackathon judges until the stores have Trimmy.
 */
export const LINKS: { web: string | null; apk: string; apkSize: string; x: string } = {
  web: null,
  apk: "https://github.com/Immadominion/trimmy/releases/download/stocklana-demo-2026-09-25/trimmy-android.apk",
  apkSize: "118 MB",
  x: "https://x.com/trimmyhq",
};
