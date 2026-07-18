# WebRTC Migration Phase 9 PC Screen Video

Tanggal: 2026-07-17

## Hasil

Media worker PC kini menangkap primary display Windows dan mengirimkannya sebagai
video track WebRTC. Frame tidak lagi dikompresi menjadi JPEG satu per satu atau
dikirim melalui TCP pada engine baru. Mirror TCP/JPEG legacy tetap tersedia dan
belum diganti sebelum cutover akhir.

Android production belum merender track ini. Fase 10 akan memasang renderer,
fullscreen lifecycle, dan reconnect pada aplikasi Android.

## Capture Windows

- Electron memilih source yang `display_id`-nya sama dengan primary display aktif.
- Pergantian profil monitor yang mengubah primary display otomatis menentukan
  source pada session mirror berikutnya.
- Capture mempertahankan native source resolution dan membatasi frame rate pada
  maksimum 30 fps.
- Cursor diminta selalu termasuk dalam desktop track.
- Content hint `motion` dipakai agar encoder memahami bahwa gerakan cepat penting.
- Satu source display dibagi oleh session video aktif melalui clone track.

## Codec dan Transport

- H.264 constrained-baseline/packetization-mode 1 diprioritaskan bila tersedia.
- VP8 tetap tersedia sebagai codec interoperabilitas dan dipilih pada probe aktual.
- RTX, RED, ULPFEC, dan FlexFEC yang tersedia dipertahankan sebagai codec pendukung.
- Sender memakai native WebRTC congestion control, bukan frame scheduler custom.
- Ceiling bitrate mengikuti native source resolution:
  - sampai 1080p: 12 Mbps;
  - di atas 1080p sampai 1440p: 20 Mbps;
  - di atas 1440p: 36 Mbps.
- Native resolution dan maksimum 30 fps diterapkan setelah SDP negotiation.
- Preference `maintain-resolution` mencegah Chromium menetap pada encode 480p
  ketika source sebenarnya 1080p.

Ceiling bukan bitrate konstan. WebRTC tetap mengukur bandwidth LAN dan menyesuaikan
bitrate aktual di bawah batas tersebut. Encoder juga dapat memakai bitrate jauh
lebih kecil ketika desktop statis.

## Resource Lifecycle

- Startup PC Server tidak membuka desktop capture atau encoder.
- Session tanpa offer tidak membuka capture.
- Session audio-only tidak mempertahankan video source setelah dummy track audio
  capture dilepas.
- Clone video berhenti ketika session pemiliknya berhenti.
- Source desktop berhenti setelah session video terakhir dilepas.
- Shutdown worker menghentikan seluruh clone, source, sender, dan peer.
- Video capture tetap berada dalam hidden Chromium worker; tidak ada executable
  screen-streamer tambahan untuk engine WebRTC.
- Status worker melaporkan source settings dan sender encoding profile saat aktif,
  lalu kembali kosong saat idle.

## Verifikasi

- Node syntax check: lulus.
- Empat belas unit test media/signaling: lulus.
- Unit test video mencakup shared capture, native-resolution constraint, last
  session cleanup, missing video track, dan unexpected source end.
- Probe Electron video end-to-end: lulus.
- Probe aktual menerima VP8, decode frame nyata, dan mencapai 1920 x 1080 dari
  source primary display 1920 x 1080 pada 30 fps.
- Regression probe audio: lulus, track Opus 48 kHz tetap connected.
- Probe lifecycle worker tiga siklus: lazy start, shared worker, dan clean stop
  seluruhnya lulus.
- APK tidak dibangun pada fase ini.
