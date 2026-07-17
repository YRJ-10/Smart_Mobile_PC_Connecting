# WebRTC Media Migration Plan

Migrasi dilakukan dalam 12 fase. Pengujian build dilakukan pada titik integrasi
penting, bukan setelah setiap edit kecil.

## Fase

- [x] Fase 0 - Kunci baseline, fitur, resource contract, dan rollback.
- [x] Fase 1 - Kontrak isolasi modul dan batas perubahan source.
- [x] Fase 2 - Proof of concept WebRTC lokal pada PC dan Android.
- [x] Fase 3 - Signaling lokal melalui PC Server yang sudah ada.
- [x] Fase 4 - Media worker PC yang lazy-start dan process-tree safe.
- [x] Fase 5 - Foundation peer connection WebRTC di Android.
- [x] Fase 6 - Capture system audio PC dan transport Opus 48 kHz.
- [x] Fase 7 - Playback audio Android, jitter handling, dan reconnect.
- [x] Fase 8 - Foreground media service, MediaSession, notification, dan lock screen.
- [x] Fase 9 - Screen capture PC dengan H.264/VP8 dan adaptive bitrate.
- [x] Fase 10 - Render mirror Android, fullscreen, lifecycle, dan reconnect.
- [x] Fase 11 - Uji holistik, resource audit, cutover, cleanup, dan release.

## Aturan Eksekusi

- Mesin lama tetap tersedia sampai pengganti lulus acceptance gate.
- Feature flag menentukan mesin media yang dipakai selama migrasi.
- Tidak ada fallback diam-diam yang menyembunyikan kegagalan WebRTC.
- Setiap fase mencatat file yang disentuh, perilaku yang dipertahankan, dan hasil
  sanity check.
- Dependency baru harus gratis, dapat didistribusikan, dan berfungsi di LAN tanpa
  layanan eksternal.
- Resource media harus nol atau mendekati nol saat fitur media tidak aktif.
