# WebRTC Migration Phase 10 Android Mirror

Tanggal: 2026-07-17

## Hasil

Android kini memiliki renderer remote video WebRTC, lifecycle tab/app, fullscreen
system UI controller, dan mirror surface yang mempertahankan bentuk fullscreen
baseline. Modul baru belum dipasang ke `main.dart`; tab Mirror production masih
memakai TCP/JPEG sampai cutover holistik pada fase 11.

## Video Renderer

- `RTCVideoRenderer` diinisialisasi sebelum menerima remote stream dan selalu
  di-dispose oleh media engine.
- Remote track dengan stream WebRTC memakai stream tersebut secara langsung.
- Remote track tanpa stream membuat synthetic `MediaStream` native lalu menambah
  track yang diterima.
- Renderer memakai `trackId` eksplisit agar combined audio/video stream hanya
  merender video yang tepat.
- Renderer dimute untuk mencegah output audio ganda ketika event membawa combined
  media stream.
- First-frame dan resize callback menerbitkan phase, track ID, width, dan height.
- Track lama dinonaktifkan dan synthetic stream dilepas saat reconnect, perubahan
  kombinasi track, stop mirror, atau dispose.

## Engine Lifecycle

- `WebRtcMediaEngine` menyiapkan renderer hanya ketika video diminta.
- Video state baru menjadi `on` setelah remote video track berhasil dipasang.
- Remote video track disimpan seperti remote audio track dan dilepas sebelum peer
  lama ditutup.
- Reconnect bounded dari fase 7 otomatis memasang track session baru dan membuang
  texture/stream lama.
- Stop video tidak mematikan audio yang masih diminta; engine beralih ke session
  audio-only.
- Dispose engine selalu menutup renderer native.

## Tab dan App Lifecycle

- Mirror visible + Android resumed: video diminta.
- Keluar dari tab Mirror: video dihentikan dan PC melepaskan desktop capture.
- Android paused, inactive, hidden, atau detached: video dihentikan.
- Kembali resumed saat tab Mirror masih aktif: session video dibuat kembali.
- Retry hanya bekerja saat mirror terlihat dan membuat session baru secara
  eksplisit.
- Controller lifecycle tidak memiliki atau men-dispose engine bersama, sehingga
  audio dapat tetap dikelola secara independen.

## Fullscreen Surface

- Orientasi landscape kanan/kiri dan immersive sticky disediakan oleh system UI
  controller terisolasi.
- Exit mengembalikan edge-to-edge serta orientasi portrait.
- Surface berwarna hitam, tanpa app bar dan bottom navigation.
- Video tidak dimirror dan memakai contain fit agar desktop tidak terpotong.
- Loading, retry failure, tombol back, status first-frame, dan resolusi tersedia
  sebagai overlay kecil.
- Tidak ada touch injection, drag, atau pointer overlay pada renderer baru.

## Isolasi Baseline

- `main.dart` belum mengimpor modul mirror WebRTC.
- Socket TCP mirror, JPEG decoder, layout mirror production, trackpad, NFC, audio
  legacy, dan remote control tidak diubah.
- Android tidak dibangun menjadi APK pada fase ini.

## Verifikasi

- Dart formatter: lulus.
- Flutter Analyze: lulus tanpa issue.
- Sembilan unit test media/lifecycle: lulus.
- Android Kotlin debug compilation: lulus.
- Test mencakup attach/detach video, renderer dispose, reconfigure audio+video,
  tab visibility, Android pause/resume, retry, dan lifecycle dispose.
