# Reference Implementation Index

Dokumen ini adalah indeks sanitized untuk project acuan. Tidak ada path lokal absolut, username, hostname, atau nama direktori mesin pribadi.

Label:

- `NFC reference`: implementasi NFC quick-action Android/PC yang sudah terbukti.
- `Media reference`: implementasi mobile-to-PC remote/media yang sudah terbukti.
- `Smart MPC`: project gabungan saat ini.

## NFC Reference

File utama:

- `android_app/lib/main.dart`
- `android_app/android/app/src/main/AndroidManifest.xml`
- `android_app/android/app/src/main/kotlin/.../MainActivity.kt`
- `android_app/android/app/src/main/kotlin/.../NfcLaunchActivity.kt`
- `Pc Local Server/server.mjs`
- `Pc Local Server/electron/main.mjs`
- `Pc Local Server/electron/preload.cjs`
- `Pc Local Server/electron/renderer/index.html`
- `Pc Local Server/electron/renderer/renderer.js`
- `Pc Local Server/electron/renderer/styles.css`

Perilaku penting yang harus dipertahankan:

- MethodChannel Android: `instant_action/preferences`.
- SharedPreferences name: `instant_action`.
- Deep link NFC: `nfcinstant://tap`.
- NFC Activity terpisah dari Flutter Activity.
- `NfcLaunchActivity` memakai native launch screen, delay focus 250 ms, lalu menjalankan quick action.
- File picker native memakai `ACTION_OPEN_DOCUMENT`, `CATEGORY_OPENABLE`, `*/*`, dan `EXTRA_ALLOW_MULTIPLE`.
- Upload file memakai `POST /api/files?filename=...`, `Content-Type: application/octet-stream`, `setChunkedStreamingMode(0)`, header `X-Device-Id` dan `X-Device-Token`.
- Download request file memakai Android `DownloadManager`, destination public Downloads, dan auth header yang sama.
- Request file memakai model PC outbox -> Android refresh list -> Android download.
- Trust phone memakai `POST /api/devices/register` dengan `X-Pairing-Token`.
- Protected HTTP memakai `X-Device-Id` dan `X-Device-Token`.
- PC server utama memakai HTTP port `8765`.
- Endpoint penting: `/health`, `/pair`, `/api/devices/register`, `/api/intent`, `/api/files`, `/api/clipboard`, `/api/request-files`, `/api/request-files/download`.

## Media Reference

File utama:

- `flutter_client/lib/main.dart`
- `flutter_client/lib/screen_mirror.dart`
- `flutter_client/android/app/src/main/AndroidManifest.xml`
- `flutter_client/android/app/src/main/kotlin/.../MainActivity.kt`
- `python_server/server.py`

Perilaku penting yang harus dipertahankan:

- Remote control TCP port `8080`.
- Discovery UDP port `8081`.
- Audio UDP receiver Android juga memakai port `8081`.
- Video stream TCP port `8082`.
- Discovery request literal: `DISCOVER_MOBILEPC`.
- Discovery response literal: `MOBILEPC_SERVER`.
- Remote command transport: newline-delimited JSON over TCP.
- TCP socket memakai `tcpNoDelay`.
- Android native audio MethodChannel: `com.mobilepcmedia/audio`.
- Audio format: PCM 16-bit mono, sample rate `16000`.
- Audio capture frame server lama: `numframes=256`.
- Trackpad memakai `Listener`, bukan gesture widget sederhana.
- Mouse move throttle: 16 ms.
- Mouse move sensitivity: `4.0`.
- Scroll dua jari: kirim `SCROLL` dengan `dy: -dy * 0.5`.
- Server scroll multiplier: `pyautogui.scroll(int(dy * 60))`.
- Tap kiri: 1 jari, distance `< 400`, duration `< 350 ms`.
- Tap kanan: 2 jari, distance `< 500`, duration `< 400 ms`.
- Browser back/forward dari 2-jari swipe horizontal.
- Live typing menghitung common prefix, mengirim backspace untuk karakter terhapus, lalu mengirim karakter baru.
- Voice dictation memakai incremental recognized words.
- Mirror force landscape saat masuk, kembali portrait saat keluar.
- Mirror frame format: 4-byte unsigned big-endian length + JPEG bytes.
- Mirror render: `Image.memory`, `gaplessPlayback: true`, `fit: BoxFit.fill`, aspect ratio 16:9.
- Mirror touch mapping: `TOUCH_DOWN`, `TOUCH_MOVE`, `TOUCH_UP` dengan ratio `rx` dan `ry`.
- Server mirror capture: primary monitor, resize `1280x720`, JPEG quality `50`.

## Smart MPC Files To Reconcile

Android:

- `android_app/lib/main.dart`
- `android_app/android/app/src/main/AndroidManifest.xml`
- `android_app/android/app/src/main/kotlin/.../MainActivity.kt`
- `android_app/android/app/src/main/kotlin/.../NfcLaunchActivity.kt`

PC app:

- `pc_app/src/server.mjs`
- `pc_app/src/control-server.mjs`
- `pc_app/src/discovery-server.mjs`
- `pc_app/src/screen-server.mjs`
- `pc_app/src/config.mjs`
- `pc_app/src/network.mjs`
- `pc_app/renderer/index.html`
- `pc_app/renderer/renderer.js`
- `pc_app/renderer/styles.css`

Worker:

- `pc_worker/worker.py`
- `pc_worker/screen_streamer.py`

Rule untuk fase berikutnya:

- Kalau Smart MPC sudah sama atau lebih kompatibel, pertahankan.
- Kalau Smart MPC berbeda dari reference pada perilaku yang pernah terbukti, reference menang.
- Kalau ada security/auth baru yang berguna, tambahkan sebagai wrapper kompatibel, bukan mengganti flow lama secara diam-diam.
