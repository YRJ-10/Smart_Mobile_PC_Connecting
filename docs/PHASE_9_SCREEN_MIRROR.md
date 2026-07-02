# Phase 9 - Screen Mirror

Tujuan fase ini adalah mengaktifkan mirror layar PC ke Android beserta touch mapping dasar tanpa menghapus fitur fase sebelumnya.

Yang ditambahkan:

- TCP screen channel di port `8082`.
- Auth awal screen channel memakai trusted device id dan token.
- Node screen server yang berjalan bersama server utama.
- Python screen streamer untuk capture monitor dan encode JPEG.
- Android Mirror tab untuk connect/disconnect dan render frame.
- Touch down/move/up di area mirror dikirim kembali ke PC lewat control channel.
- Desktop shell menampilkan status screen channel.

Format screen stream awal:

- Pesan pertama dari Android: JSON auth line.
- Respons awal dari PC: JSON status line.
- Frame berikutnya: 4-byte big-endian length + JPEG bytes.
- Ukuran frame: `1280x720`.
- JPEG quality: `50`.

Catatan implementasi:

- Worker memakai `mss`, `numpy`, dan `opencv-python`.
- Screen stream tetap dilindungi trusted device auth.
- Touch mapping awal memakai koordinat relatif `0.0..1.0`.
- `InteractiveViewer` memakai `panEnabled: false`, `minScale: 1`, dan `maxScale: 5`.
- Mirror view mengunci landscape saat masuk dan kembali portrait saat keluar.

Belum dikerjakan di fase ini:

- Multi-monitor picker.
- Adaptive FPS/quality.
- Input mapping yang mengoreksi letterbox/aspect ratio secara presisi.
- Full integration test lintas device.
