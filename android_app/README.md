# Android App

Flutter client untuk Smart MPC.

## Fase 4: Android Core

- manual PC server URL
- pairing token input
- register Android sebagai trusted device
- simpan config lokal via native preferences
- test `GET /health`
- basic navigation shell
- status trusted/untrusted

## Fase 5: File, Clipboard, Quick Actions

Fitur tambahan:

- upload file Android ke PC inbox via native picker
- request/list PC outbox files
- download PC file ke Android Downloads
- send clipboard text to PC
- pull PC clipboard to phone
- open URL on PC
- PC command buttons

## Fase 6: NFC Integration

Fitur tambahan:

- NFC permission dan NDEF intent filter.
- Deep link `smartmpc://tap`.
- Native tap action launcher.
- Quick action selector.
- Run Tap Action simulation.
- NFC send file.
- NFC pull PC clipboard.
- NFC request PC files fallback ke app.
- NFC open Chrome.
- NFC lock PC.
- NFC sleep PC.

## Jalankan

```powershell
cd android_app
flutter pub get
flutter run
```

Catatan: Android harus satu Wi-Fi dengan PC. Gunakan IP PC lokal, bukan loopback address.
