# FamilyChat Android Client

```powershell
flutter pub get

# Only needed if the Android scaffold is missing:
flutter create . --platforms=android

flutter test
flutter test integration_test -d emulator-5554
flutter run -d android
```

The Android client shares the same encrypted-room model as the web client and includes:

- host-side unit tests in `test/`
- device or emulator integration flows in `integration_test/`
- LiveKit call wiring with app-level fakes for deterministic runtime coverage
