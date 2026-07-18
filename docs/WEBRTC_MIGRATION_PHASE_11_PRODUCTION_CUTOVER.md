# WebRTC Migration Phase 11 Production Cutover

Tanggal: 2026-07-17

## Hasil

Audio dan mirror pada UI Android production kini memakai WebRTC. PCM/UDP dan
TCP/JPEG tidak lagi dipanggil dari `main.dart`. NFC, trackpad, pairing, discovery,
file, clipboard, command PC, dan layout selain status media tidak diubah.

Acceptance pengalaman nyata tetap dilakukan satu kali oleh pengguna melalui Run
di Android Studio setelah seluruh fase selesai. APK release belum dibangun.

## Cutover Android

- Runtime WebRTC dibuat lazy hanya setelah audio dinyalakan atau tab Mirror dibuka.
- Context signaling mengikuti base URL, device ID, device token, dan PC ID yang
  tersimpan. Perubahan IP hasil discovery membangun ulang runtime secara eksplisit.
- Tidak ada fallback diam-diam ke transport legacy saat WebRTC gagal.
- Audio tidak bergantung pada socket remote-control TCP; kegagalan trackpad tidak
  mematikan media dan kegagalan media tidak memutus trackpad.
- Start/refresh/stop audio memakai `WebRtcMediaEngine` dan foreground
  `WebRtcMediaService`.
- MediaSession menerima play, pause, dan stop dari notification/lock screen.
- Audio boleh tetap hidup ketika app berada di background atau layar terkunci.
- Mirror memakai `RTCVideoView`, landscape immersive, contain fit, first-frame
  status, reconnect, dan retry.
- Keluar dari Mirror kembali ke tab Actions dan portrait.
- Mirror production bersifat view-only; tidak ada touch injection.

## Lifecycle dan Resource

- Mirror hanya meminta video ketika tab terlihat dan app foreground.
- Keluar dari Mirror menghentikan video; audio tetap hidup bila sedang diminta.
- Stop audio tidak menghentikan mirror bila mirror masih aktif.
- Saat audio dan video sama-sama off, engine, peer, signaling client, remote track,
  renderer native, foreground service, wake lock, dan Wi-Fi lock dilepas.
- Hidden media worker PC tetap lazy dan berhenti setelah session terakhir.
- Listener PCM/UDP dan TCP/JPEG legacy tetap tersedia untuk rollback, tetapi tidak
  membuat capture atau worker tanpa client legacy.

## Verifikasi Otomatis

- Flutter Analyze: lulus tanpa issue.
- Sembilan unit test Android WebRTC/lifecycle: lulus.
- Android Kotlin debug compilation: lulus; APK tidak dibangun.
- Node syntax check: lulus.
- Empat belas test signaling, capture pool, dan cleanup: lulus.
- WebRTC capability probe: data channel tersambung, host candidate lokal, Opus,
  VP8, dan H.264 tersedia.
- Audio transport probe: remote audio track tersambung dan SDP memakai Opus 48 kHz.
- Video transport probe: frame nyata ter-decode sebagai VP8 pada 1920 x 1080,
  maksimum 30 fps, bitrate ceiling 12 Mbps, dan native congestion control.
- Tiga siklus worker: lazy start, shared worker, clean stop; state akhir worker
  `running=false`, session nol, audio/video inactive.
- Audit process setelah probe: tidak ada Electron, screen-streamer, atau media
  worker probe yang tertinggal.

## Acceptance Pengguna

Checklist fisik berada di `HOLISTIC_TEST_CHECKLIST.md`. Fokus utama media adalah
musik/dialog tanpa fadeout, latency yang tidak menumpuk, notification lock screen,
mirror gerak cepat/video, cleanup setelah off, serta feel trackpad dan NFC yang
tetap identik dengan release stabil.
