# Trimmy mobile

The actual Flutter app starts at `lib/main.dart` and mounts `lib/product/app/product_app.dart`. It includes guided first stock purchase, Desk, Market, Career, Profile, account flows and wallet funding.

Run `node tool/prepare-public-assets.mjs` from the repository root before a public checkout's first build. Then follow the [development guide](../../docs/DEVELOPMENT.md) for client configuration and native setup.

```bash
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter run --flavor production --dart-define-from-file=account-config.local.json
```

`account-config.local.json` is ignored. Use `account-config.example.json` as its template. Only public client configuration belongs in that file.

Historical `design_study.dart` and UI review entry points are retained for regression coverage; they are not the production entry point. Never uninstall a user's app or clear its data merely to test navigation.
