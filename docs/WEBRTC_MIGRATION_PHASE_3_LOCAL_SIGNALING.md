# WebRTC Migration Phase 3 Local Signaling

Tanggal: 2026-07-17

## Hasil

PC Server kini memiliki signaling WebRTC lokal yang terpisah dari TCP control
channel. Android memiliki client signaling terisolasi, tetapi belum dipanggil oleh
UI atau startup aplikasi.

## Endpoint

Semua endpoint membutuhkan trusted-device auth:

```text
GET  /api/media/capabilities
POST /api/media/sessions
GET  /api/media/sessions/{id}/status
POST /api/media/sessions/{id}/signals
GET  /api/media/sessions/{id}/signals?after={sequence}&wait_ms={milliseconds}
POST /api/media/sessions/{id}/stop
```

`GET signals` menggunakan bounded long-poll maksimal 25 detik. Signaling tetap
berjalan pada HTTP server lokal port `8765`; tidak ada WebSocket, cloud, STUN, atau
TURN dependency.

## Auth dan Ownership

- Device ID/token atau trusted session token divalidasi oleh PC Server.
- Media worker tidak menerima pairing/device credential.
- Session memakai UUID acak dan dimiliki satu device.
- Device lain menerima not-found untuk session yang bukan miliknya.
- Session baru dari device yang sama menghentikan session sebelumnya.
- Revoke device dan server stop membersihkan signaling session milik device.

## Signal Contract

Android ke PC:

- `offer` dengan SDP;
- `ice-candidate`;
- `ice-complete`.

PC ke Android:

- `offer` atau `answer` dengan SDP;
- `ice-candidate`;
- `ice-complete`;
- `error`.

Setiap arah memiliki sequence number terpisah. Queue dibatasi 256 signal, SDP
dibatasi 1 MiB, candidate dibatasi 8 KiB, dan response Android dibatasi 2 MiB.

## Lifecycle

- Signaling service tidak membuat peer connection, capture, encoder, atau worker.
- Idle session dibersihkan setelah dua menit tanpa aktivitas.
- Pending long-poll langsung selesai ketika signal tersedia atau session berhenti.
- Cleanup idempotent dan tidak mengubah control socket.
- Capability melaporkan `media_available: false` sampai media worker Fase 4 siap.

## Android Client

`MediaSignalingClient` memiliki operasi capabilities, create, status, send signal,
poll signal, stop, dan dispose. Client tidak diimpor oleh `main.dart`, sehingga APK
yang dijalankan masih memakai engine legacy secara penuh.

## Verifikasi

- Node syntax check: lulus.
- Enam unit test signaling: lulus.
- Test mencakup local-only capabilities, single-session replacement, ownership,
  sequence, long-poll wakeup, stop cleanup, dan route isolation.
- Flutter Analyze: wajib lulus sebelum commit fase.
- APK tidak dibangun pada fase ini.
