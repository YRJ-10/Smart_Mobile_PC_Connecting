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

## Jalankan

```powershell
cd android_app
flutter pub get
flutter run
```

Catatan: Android harus satu Wi-Fi dengan PC. Gunakan IP PC lokal, bukan loopback address.
