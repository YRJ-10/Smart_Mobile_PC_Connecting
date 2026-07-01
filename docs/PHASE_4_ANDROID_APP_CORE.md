# Phase 4 Android App Core

Tanggal: 2026-07-01

Fase ini membuat aplikasi Android inti untuk koneksi awal ke PC server.

## Hasil

Folder `android_app` sekarang berisi Flutter Android app.

Bagian utama:

```text
android_app/
+-- lib/
    +-- main.dart
+-- android/
    +-- app/
        +-- src/main/
            +-- AndroidManifest.xml
            +-- kotlin/com/smartmpc/app/MainActivity.kt
```

## Fitur Android Core

- App identity `Smart MPC`.
- Package Android `com.smartmpc.app`.
- Manual PC server URL.
- Pairing token input.
- Health check ke `GET /health`.
- Pair info request ke `GET /pair`.
- Trust phone request ke `POST /api/devices/register`.
- Device id lokal.
- Device token lokal.
- PC id lokal.
- Native preferences via MethodChannel `smart_mpc/preferences`.
- Clear local trust.
- Basic navigation shell:
  - Connect
  - Actions placeholder
  - Remote placeholder
  - Mirror placeholder

## Belum Dikerjakan Di Fase Ini

- NFC/deep-link Activity.
- File picker/upload.
- Clipboard actions.
- Remote control live channel.
- Voice typing.
- Audio receiver.
- Screen mirror.
- Discovery UDP.
- Full Android build/test.

## Keputusan

- Android app memakai dependency Flutter dasar dulu.
- Penyimpanan config memakai native SharedPreferences lewat MethodChannel, tanpa package tambahan.
- Package lama dari prototype tidak dibawa ke project publik.
- Path lokal dan identitas mesin tidak boleh ditulis ke dokumen atau source publik.

## Fase Berikutnya

Fase 5: File, Clipboard, and Quick Actions.

Target:

- Endpoint file transfer di PC server.
- Clipboard route di PC server.
- Quick action route execution.
- Android UI untuk file/clipboard/action.
- Command whitelist dasar.
