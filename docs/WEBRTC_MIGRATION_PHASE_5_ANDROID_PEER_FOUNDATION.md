# WebRTC Migration Phase 5 Android Peer Foundation

Tanggal: 2026-07-17

## Hasil

Android kini memiliki foundation media engine WebRTC yang terpisah dari UI dan
engine legacy. Foundation dapat membuat trusted signaling session, membentuk
receiver-only peer connection, melakukan offer/answer serta pertukaran host ICE,
dan membersihkan peer serta session secara idempoten.

`main.dart` belum mengimpor atau membuat engine baru. Audio PCM/UDP dan mirror
JPEG/TCP production tetap berjalan melalui implementasi legacy yang sudah stabil.

## Modul

- `media_engine.dart`: kontrak engine dan trusted PC context.
- `media_state.dart`: state session, audio, dan video yang immutable.
- `media_signaling_client.dart`: HTTP signaling transport dan implementation.
- `webrtc_peer.dart`: adapter tipis untuk native `flutter_webrtc`.
- `webrtc_media_engine.dart`: pemilik lifecycle peer dan signaling session.

UI kelak hanya menggunakan `MediaEngine`; UI tidak memegang peer connection,
candidate, SDP, codec, atau polling signaling.

## Peer Contract

- Android menjadi offerer dan media receiver.
- Audio/video memakai transceiver `recvonly` sesuai requested tracks.
- Konfigurasi memakai Unified Plan dan `iceServers: []`.
- Offer dikirim melalui trusted signaling PC Server.
- Answer dan ICE candidate PC diterapkan berdasarkan sequence number.
- Candidate yang tiba sebelum answer ditahan sampai remote description siap.
- Remote track diterbitkan melalui stream terisolasi untuk fase playback/render.

## Lifecycle

- Semua start/stop diserialkan agar perintah UI berdekatan tidak saling balap.
- Kombinasi requested track yang sama tidak membuat session baru.
- Perubahan kombinasi track menutup peer/session lama sebelum membuat pengganti.
- Session berhenti total ketika audio dan video sama-sama `off`.
- Dispose menutup peer, signaling session, HTTP client, dan stream controller.
- Native peer creation failure tetap menghentikan signaling session PC yang sudah
  telanjur dibuat.
- Peer failure menutup resource aktif dan menghasilkan state `failed` yang jelas.

Reconnect otomatis belum diaktifkan pada fase ini. Kebijakan reconnect audio dan
playback lifecycle ditambahkan setelah track audio production tersedia, sehingga
tidak ada retry loop yang belum dapat diuji end-to-end.

## Capability Gate

Sebelum session pertama, Android memeriksa capability PC. Session WebRTC hanya
dibuat ketika `signaling_available` dan `media_available` bernilai true. Tidak ada
fallback diam-diam ke engine legacy.

## Verifikasi

- Dart formatter: lulus.
- Flutter Analyze: lulus tanpa issue.
- Tiga unit test lifecycle: lulus.
- Test mencakup offer/answer, ICE sebelum answer, local ICE forwarding, perubahan
  audio ke audio+video lalu video-only, cleanup session, capability failure, dan
  native peer creation failure.
- `main.dart`, NFC, trackpad, pairing, file, dan control channel tidak disentuh.
- APK tidak dibangun pada fase ini.
