# Website product preview assets

These files are copied from the existing Trimmy mobile project, not newly generated.

- `sal-teaching.png`: `apps/mobile/assets/images/ui_review/sal/sal-teaching-v2.png`.
- `apple.webp`, `nvidia.webp`, `meta.webp`: the AAPLx, NVDAx and METAx assets in `apps/mobile/assets/images/ui_review/wall-street-orbit/`.
- The preview palette follows `apps/mobile/lib/product/design/product_theme.dart`; layouts reference the existing Desk and Market, with illustrative local demo values.

The demo does not connect to a market feed, saved account, order API or wallet.

`public/app/` holds what the phone's live screens use, also copied from the mobile project:
- `sal-teaching.webp`, `sal-proud.webp`, `sal-celebrating.webp`: `apps/mobile/assets/images/ui_review/sal/sal-*-v2.png`, resized.
- `briefcase.webp`: `apps/mobile/assets/images/ui_review/rookie-briefcase-v1.png`, resized.
- `nav-*.png`, `bell.png`, `search.png`, `streak.png`: the app's Icons8 icons in `apps/mobile/assets/images/ui_review/icons8/` (Plumpy style, as the app's tab bar uses them).
- Colours and type follow `apps/mobile/lib/product/design/product_theme.dart`; the site sets them in Manrope and Bricolage.
