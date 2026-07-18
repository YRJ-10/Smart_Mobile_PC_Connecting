# WebRTC Migration Phase 1 Isolation Contract

Tanggal: 2026-07-17

## Tujuan

Dokumen ini menetapkan batas modul sebelum dependency WebRTC ditambahkan. Media
baru harus dapat dikembangkan, diuji, dimatikan, dan dihapus tanpa mengubah jalur
NFC, trackpad, file, pairing, atau PC commands.

## Masalah Struktur Saat Ini

- `android_app/lib/main.dart` memegang UI, lifecycle koneksi, audio, dan mirror.
- `AudioReceiverService.kt` menggabungkan foreground service, UDP receive,
  buffering, concealment, dan PCM playback.
- `pc_worker/worker.py` menggabungkan mouse/keyboard commands dengan audio capture.
- `screen-server.mjs` membuat executable screen capture langsung per socket.
- Worker screen berbentuk PyInstaller one-file dapat meninggalkan child process
  ketika wrapper dihentikan.

Migrasi tidak boleh menambahkan WebRTC langsung ke titik-titik campur tersebut.

## Batas Modul Android

Struktur target:

```text
android_app/lib/media/
+-- media_controller.dart
+-- media_engine.dart
+-- media_state.dart
+-- legacy_media_engine.dart
+-- webrtc_media_engine.dart
```

Tanggung jawab:

- `MediaController` adalah satu-satunya API yang dipanggil UI.
- `MediaEngine` mendefinisikan start/stop audio, start/stop video, state, dan
  cleanup.
- `LegacyMediaEngine` membungkus perilaku PCM/JPEG yang ada tanpa menulis ulang.
- `WebRtcMediaEngine` memiliki peer connection dan track WebRTC.
- `MediaState` memisahkan desired state dari actual state untuk audio dan video.
- UI tidak boleh memegang socket, peer connection, renderer, codec, atau worker.

Kontrak minimum engine:

```text
initialize(trusted PC context)
startAudio()
stopAudio()
startVideo()
stopVideo()
dispose()
state stream
```

`main.dart` hanya boleh menerima integrasi tipis pada handler audio/mirror dan
widget renderer. Trackpad, NFC, Actions, Connect, pairing, dan file transfer tidak
boleh dipindahkan ke modul media.

## Batas Native Android

- `AudioReceiverService.kt` tetap menjadi legacy implementation sampai cutover.
- WebRTC background playback memakai service/MediaSession baru, bukan menambah
  jitter-buffer logic ke service lama.
- `MainActivity.kt` hanya boleh mendapat bridge media yang terpisah. Handler
  config, file picker, download, deep link, dan NFC tidak boleh diubah perilakunya.
- `NfcLaunchActivity.kt` dan intent filter NFC tidak boleh disentuh oleh migrasi.
- Notification dan lock-screen controls hanya aktif saat audio WebRTC aktif.
- Stop audio wajib menghapus foreground notification, MediaSession, wake lock,
  dan Wi-Fi lock yang dimiliki modul media.

## Batas Modul PC

Struktur target:

```text
pc_app/src/media/
+-- media-capabilities.mjs
+-- media-session-manager.mjs
+-- media-signaling-routes.mjs
+-- media-worker-process.mjs

pc_media/
+-- source media worker production
```

Tanggung jawab:

- `media-capabilities` melaporkan engine dan codec yang benar-benar tersedia.
- `media-session-manager` memiliki state session, audio track, video track, dan
  cleanup.
- `media-signaling-routes` menangani offer, answer, ICE, start, stop, dan status
  dengan trusted-device auth.
- `media-worker-process` menjadi satu-satunya pemilik child process media.
- `pc_media` menangkap system audio/screen dan menjalankan stack WebRTC.
- PC Server boleh menjalankan listener signaling saat idle, tetapi tidak boleh
  menjalankan capture atau encoder.

Worker media tidak boleh:

- menjalankan mouse, keyboard, clipboard, file, monitor profile, atau PC command;
- membaca pairing token secara langsung;
- memilih sendiri trusted device;
- hidup saat tidak ada requested media track.

## Source Ownership Matrix

| Area | Status selama migrasi | Perubahan yang diizinkan |
| --- | --- | --- |
| `NfcLaunchActivity.kt` dan NFC manifest | Beku | Tidak ada |
| Trackpad/gesture di `main.dart` | Beku | Tidak ada |
| Pairing, discovery, file, clipboard | Beku | Tidak ada |
| `control-server.mjs` | Beku untuk input | Hanya compatibility hook yang tidak mengubah command |
| Mouse/keyboard di `worker.py` | Beku | Tidak ada |
| Audio lama di `worker.py` | Legacy fallback | Baru dihapus pada cutover |
| `screen-server.mjs` | Legacy fallback | Lifecycle fix terisolasi bila diperlukan |
| `server.mjs` | Extension point | Mount signaling/media status routes |
| Electron renderer | Extension point terbatas | Status media, tanpa memulai capture sendiri |
| `shared_protocol` | Extension point | Capability dan signaling contract baru |
| `pc_media` | Modul baru | Seluruh implementation media production |

## Dependency Direction

```text
Android UI
  -> MediaController
    -> selected MediaEngine
      -> signaling contract

PC HTTP server
  -> media-signaling-routes
    -> MediaSessionManager
      -> MediaWorkerProcess
        -> pc_media worker
```

Dependency tidak boleh berjalan terbalik. Media worker tidak boleh mengimpor PC
Server, dan control worker tidak boleh menjadi pemilik WebRTC session.

## Session dan Auth Contract

- Signaling memakai HTTP server lokal yang sudah ada dan trusted-device auth.
- Credential tidak diteruskan sebagai command-line argument worker.
- PC Server memvalidasi device sebelum meneruskan signaling payload.
- Satu device hanya boleh memiliki satu active media session.
- Session kedua untuk device yang sama mengganti session lama melalui cleanup
  terkontrol, bukan membuat worker tambahan.
- Session harus memiliki ID acak dan tidak menggunakan IP sebagai identitas.
- Media hanya memakai LAN peer-to-peer dan host ICE candidates.
- Tidak ada public STUN, TURN, telemetry, atau signaling eksternal.

## State Machine

State session:

```text
idle -> starting -> negotiating -> connected
connected -> stopping -> idle
starting/negotiating/connected -> failed -> stopping -> idle
```

Audio dan video memiliki requested state terpisah:

```text
audio: off | starting | on | stopping | failed
video: off | starting | on | stopping | failed
```

Kegagalan satu track tidak boleh otomatis mematikan track lain atau control
channel. Session berhenti total hanya ketika kedua track `off`, disconnect diminta,
atau trusted session dicabut.

## Engine Selection Contract

- Engine dipilih secara eksplisit: `legacy` atau `webrtc`.
- Selama migrasi, default production tetap `legacy`.
- Android harus membaca capability PC sebelum meminta `webrtc`.
- Ketidakcocokan engine menghasilkan status yang jelas.
- Tidak ada fallback diam-diam dari WebRTC ke legacy karena itu menyembunyikan
  kegagalan pengujian.
- Setelah acceptance gate lulus, default dapat dipindah ke `webrtc`; legacy baru
  dihapus pada fase cutover.

## Process dan Resource Contract

- PC app startup tidak boleh memulai media worker.
- Audio `ON` hanya mengaktifkan komponen audio yang diperlukan.
- Mirror `ON` hanya mengaktifkan komponen video yang diperlukan.
- Stop terakhir harus meminta graceful shutdown lalu melakukan forced process-tree
  cleanup jika batas dua detik terlewati.
- Cleanup harus idempotent dan aman dipanggil berulang.
- Parent exit, socket close, app exit, auth revoke, dan startup recovery wajib
  membersihkan session serta process tree.
- Android lifecycle stop hanya boleh mempertahankan audio jika foreground media
  service aktif; video selalu berhenti ketika mirror ditutup.
- Tidak boleh ada capture loop, encoder loop, renderer, wake lock, atau orphan
  process saat kedua media track `OFF`.

## Compatibility Rules

- Port dan payload legacy tidak diubah sebelum cutover.
- Tombol audio dan mirror tetap mempertahankan fungsi serta lokasi UI saat engine
  internal diganti.
- Kontrol volume/media tetap lewat control channel yang sudah terbukti.
- Mirror production adalah viewer; interaksi PC tetap melalui Remote/trackpad.
- Build production harus menyertakan hanya dependency runtime yang diperlukan.

## Exit Criteria Fase 1

- Batas Android, PC Server, control worker, dan media worker terdokumentasi.
- Source ownership matrix disetujui sebagai aturan kerja.
- State, auth, engine selection, dan resource lifecycle tidak ambigu.
- Tidak ada kode runtime atau dependency baru yang ditambahkan.
- Baseline `v2.2.2-baseline` tetap dapat dipakai tanpa perubahan.
