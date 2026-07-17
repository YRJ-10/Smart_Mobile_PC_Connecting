# WebRTC Migration Phase 7 Android Audio Playback

Tanggal: 2026-07-17

## Hasil

Android WebRTC engine kini memiliki playback lifecycle untuk remote system-audio
track, media audio routing, connection timeout, disconnect grace period, dan
bounded reconnect. Implementasi tetap terisolasi dari UI dan audio legacy.

`main.dart` belum membuat `WebRtcMediaEngine`, sehingga tombol audio production
masih memakai PCM/UDP legacy sampai foreground service dan cutover diselesaikan.

## Playback Android

- Konfigurasi audio memakai preset `AndroidAudioConfiguration.media` sebelum
  native peer dibuat.
- Remote audio track diaktifkan dan volumenya diserahkan pada media volume Android.
- Mode komunikasi/telepon dan forced speakerphone tidak digunakan.
- Audio state baru menjadi `on` setelah peer connected dan remote audio track
  berhasil dipasang pada output.
- Stop/reconfigure menonaktifkan track lama dan membersihkan communication-device
  override sebelum peer ditutup.
- Remote track yang datang setelah session sudah diganti langsung dilepas.

## Jitter dan Playout

Tidak ada jitter buffer PCM, packet scheduler, concealment loop, auto-refresh, atau
resampling buatan aplikasi. WebRTC native menjadi satu-satunya pemilik:

- adaptive jitter buffer;
- RTP playout clock;
- Opus decode dan packet-loss concealment;
- packet reordering;
- audio device timing.

Keputusan ini menghilangkan dua clock dan dua buffer yang sebelumnya dapat saling
mengejar lalu menghasilkan delay drift atau burst mute.

## Reconnect Policy

- Negotiation yang belum connected dalam 12 detik dianggap gagal.
- Status disconnected diberi grace period 1,2 detik.
- Peer yang pulih dalam grace period mempertahankan session yang sama.
- Failure terminal menutup peer, track, signaling session, dan audio route sebelum
  retry.
- Retry dibatasi tiga kali dengan jeda 250 ms, 750 ms, dan 1.500 ms.
- Connected state mereset retry counter.
- Stop audio/video dan dispose membatalkan seluruh timer serta retry tertunda.
- Setelah batas retry habis, state tetap `failed`; tidak ada retry loop tanpa batas.

## Resource Lifecycle

- Tidak ada audio output, peer, polling, atau timer sebelum track diminta.
- Semua timer negotiation, disconnect, dan reconnect dapat dibatalkan.
- Perubahan kombinasi audio/video tetap diserialkan.
- Audio route reset tetap best-effort dan tidak boleh menghentikan state machine
  cleanup.
- Playback failure menghasilkan error eksplisit; tidak ada fallback diam-diam ke
  engine legacy.

## Verifikasi

- Dart formatter: lulus.
- Flutter Analyze: lulus tanpa issue.
- Enam unit test lifecycle: lulus.
- Test mencakup audio track attach/detach, state readiness, signaling/ICE,
  capability failure, native peer creation failure, reconnect ke session baru,
  retry cancellation saat stop, bounded retry, dan transient disconnect recovery.
- `main.dart`, NFC, trackpad, pairing, file, control channel, serta native audio
  service legacy tidak disentuh.
- APK tidak dibangun pada fase ini.
