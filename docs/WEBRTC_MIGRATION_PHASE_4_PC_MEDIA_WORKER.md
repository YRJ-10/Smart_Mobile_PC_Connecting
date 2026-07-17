# WebRTC Migration Phase 4 PC Media Worker

Tanggal: 2026-07-17

## Hasil

PC Server kini memiliki media worker WebRTC berbasis renderer Chromium tersembunyi
di dalam process tree Electron. Worker dibuat saat media session pertama dimulai,
dipakai bersama selama masih ada session aktif, dan dihancurkan setelah session
terakhir berhenti.

Fase ini belum melakukan capture audio atau layar. Engine media legacy juga belum
diganti, sehingga remote control, NFC, file, pairing, audio legacy, dan mirror
legacy tetap memakai jalur stabil sebelumnya.

## Arsitektur

- `MediaWorkerProcess` memiliki dan menghancurkan hidden `BrowserWindow`.
- Renderer memakai `RTCPeerConnection` native Chromium dengan `iceServers: []`.
- Preload sandbox hanya membuka IPC command/event khusus media.
- `MediaSessionManager` menjadi satu-satunya bridge antara signaling dan worker.
- Credential trusted-device berhenti di HTTP server dan tidak masuk renderer.
- Worker hanya menerima media session ID, pilihan track, dan signal WebRTC.

## Lifecycle dan Process Safety

- PC Server idle: worker tidak berjalan dan tidak memiliki session.
- Session pertama: worker dimulai dan ditunggu sampai mengirim status ready.
- Session tambahan: memakai worker yang sama tanpa proses baru.
- Session terakhir berhenti: peer ditutup, renderer dihentikan, lalu jendela
  dihancurkan.
- `stop()` baru selesai setelah jendela benar-benar menerima event `closed`.
- Renderer crash menghancurkan jendela pemilik dan menandai session terdampak
  sebagai gagal.
- Server stop selalu membersihkan seluruh signaling session dan worker.

Worker merupakan child renderer milik Electron, bukan executable PyInstaller
terpisah. Karena itu shutdown mengikuti process tree PC Server dan tidak membuat
`screen-streamer.exe` baru.

## Signaling

Worker fase ini menerima offer dan ICE candidate dari Android, lalu menghasilkan
answer dan ICE candidate server. State peer diteruskan kembali ke signaling
service. Capability `media_available` hanya aktif saat PC Server dijalankan melalui
Electron yang memiliki media worker; mode Node tanpa Electron menolak pembuatan
session dengan HTTP 503.

## Verifikasi

- Node syntax check: lulus.
- Delapan unit test signaling dan session manager: lulus.
- Probe Electron nyata: tiga siklus start/stop lulus.
- Tiap siklus membuka dua session paralel, mempertahankan worker saat satu session
  tersisa, lalu memastikan worker berhenti setelah session terakhir.
- Audit proses Windows setelah probe: tidak ada proses probe/worker tersisa.
- APK tidak dibangun pada fase ini.
