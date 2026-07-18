# WebRTC Migration Phase 8 Foreground Media

Tanggal: 2026-07-17

## Hasil

Android kini memiliki foreground media service khusus WebRTC, MediaSession,
notifikasi media, kontrol lock screen, dan bridge perintah Flutter yang terisolasi.
Audio receiver PCM/UDP legacy tidak diubah dan belum digantikan pada fase ini.

`main.dart` belum mengaktifkan service atau engine WebRTC. Cutover tombol audio
tetap menunggu fase integrasi agar baseline yang sudah dipakai tidak berubah
sebelum seluruh jalur media baru siap diuji bersama.

## Foreground Lifecycle

- Service memakai tipe `mediaPlayback` dan hanya dimulai atas perintah eksplisit.
- `START_NOT_STICKY` mencegah Android menghidupkan ulang stream tanpa permintaan.
- Start membuat MediaSession aktif dan menampilkan foreground notification.
- Stop menghapus notification, menonaktifkan MediaSession, melepas seluruh lock,
  lalu menghentikan service.
- Update, play, atau pause yang diterima saat session tidak aktif tidak membuat
  service idle tertinggal.
- Menutup halaman Android tidak otomatis menghentikan service selama playback
  memang masih diminta.

## Notification dan Lock Screen

- Notification memakai kategori transport, visibility public, dan MediaStyle.
- State playing/paused dan metadata `PC Audio` diterbitkan melalui MediaSession.
- Kontrol play/pause dan stop tersedia pada notification serta lock screen.
- Perintah kontrol dikirim ke Dart melalui channel `smart_mpc/webrtc_media`.
- Stop tetap membersihkan native service walaupun Flutter listener sudah tidak ada.
- Android 13 ke atas meminta izin notification melalui bridge Flutter saat start.
  Penolakan izin tidak mengubah lifecycle WebRTC, tetapi tampilan notification
  mengikuti pembatasan sistem Android.

## Resource Contract

- Partial wake lock dan low-latency/high-performance Wi-Fi lock hanya dipegang
  selama foreground audio session aktif.
- Kedua lock selalu dilepas pada stop dan `onDestroy`.
- Tidak ada polling, thread audio baru, Flutter engine kedua, atau proses Android
  tambahan pada service ini.
- Service tidak memulai peer WebRTC sendiri; ia hanya menjaga lifecycle playback
  yang kelak dimiliki `WebRtcMediaEngine`.

## Isolasi Baseline

- `AudioReceiverService` legacy tidak disentuh.
- Channel native lama `smart_mpc/preferences` dan seluruh method-nya dipertahankan.
- NFC, trackpad, pairing, file transfer, control channel, dan mirror legacy tidak
  diubah.
- Bridge baru belum diimpor oleh `main.dart` atau engine media lama.

## Verifikasi

- Android Kotlin debug compilation: lulus.
- Flutter Analyze: lulus tanpa issue.
- Enam regression test WebRTC: lulus.
- Android manifest merge dan resource compilation: lulus.
- APK tidak dibangun pada fase ini.
