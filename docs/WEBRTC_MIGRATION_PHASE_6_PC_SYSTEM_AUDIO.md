# WebRTC Migration Phase 6 PC System Audio

Tanggal: 2026-07-17

## Hasil

Media worker PC kini dapat menangkap system audio Windows melalui Chromium
loopback dan memasangnya pada peer connection sebagai track audio WebRTC. SDP
answer dibatasi pada codec Opus dengan RTP clock 48 kHz.

Jalur audio PCM/UDP legacy belum diubah atau dihapus. Android production juga
belum mengaktifkan engine WebRTC, sehingga perilaku aplikasi yang dipakai saat ini
tetap mengikuti baseline sampai fase playback dan cutover.

## Capture Windows

- Capture memakai Electron display-media handler dengan `audio: "loopback"`.
- Handler berada pada Chromium session khusus media worker, bukan default session
  UI PC Server.
- Request hanya diterima dari file renderer media worker yang tepat.
- Source desktop dipilih tanpa thumbnail untuk menghindari pekerjaan gambar yang
  tidak diperlukan.
- `getDisplayMedia` meminta video minimal karena kontrak display capture; video
  dummy langsung dihentikan setelah track audio tersedia.
- Audio track memakai content hint `music`; voice-processing custom tidak
  ditambahkan pada loopback system audio.

## Transport

- Android offer menyediakan transceiver audio `recvonly`.
- PC mengikat clone system-audio track pada sender transceiver yang sama.
- Direction PC ditetapkan `sendonly`.
- Codec preference hanya menerima `audio/opus`.
- Answer aktual terverifikasi berisi Opus 48 kHz.
- ICE candidate yang tiba sebelum offer selesai disimpan lalu diterapkan setelah
  remote description tersedia.

## Resource Lifecycle

- PC Server startup tidak membuka loopback capture.
- Signaling session tanpa offer tidak membuka capture.
- Session video-only tidak membuka capture audio.
- Satu source loopback dibagi oleh seluruh session audio melalui clone track.
- Clone berhenti ketika session pemiliknya berhenti.
- Source loopback berhenti setelah session audio terakhir dilepas.
- Shutdown worker menghentikan seluruh clone, source audio, dan dummy video.
- Hasil capture async yang datang setelah session ditutup langsung dilepas.
- Device/source audio yang berhenti mendadak menerbitkan error untuk session yang
  terdampak dan membersihkan seluruh track.

Status runtime worker kini melaporkan `audio.active`, jumlah session audio, dan
settings track. Saat idle status kembali `active: false` dan `sessions: 0`.

## Verifikasi

- Node syntax check: lulus.
- Sebelas unit test PC media/signaling: lulus.
- Unit test audio mencakup shared capture, last-session cleanup, missing loopback,
  dan unexpected source end.
- Probe Electron end-to-end: lulus.
- Probe membuat receiver peer lokal, membuka Windows loopback aktual, menerima
  remote audio track, mencapai state connected, dan memverifikasi Opus 48 kHz.
- Probe lifecycle worker tiga siklus: lulus setelah capture session ditambahkan.
- Audit proses Windows setelah probe: tidak ada probe atau media worker tersisa.
- APK tidak dibangun pada fase ini.
