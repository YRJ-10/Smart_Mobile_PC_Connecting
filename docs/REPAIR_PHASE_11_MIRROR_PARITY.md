# Repair Phase 11 - Mirror Parity

Status: complete.

Tujuan fase ini adalah mengembalikan screen mirror agar mengikuti perilaku project media remote yang sudah terbukti, sambil tetap mempertahankan auth handshake Smart MPC sebelum stream frame.

## Yang Dipulihkan

- Android masuk landscape ketika tab Mirror dibuka dan kembali portrait ketika keluar.
- Mirror view dibuat full black, tanpa card, dengan tombol back overlay seperti referensi.
- Mirror auto-connect saat tab Mirror dibuka.
- Render tetap memakai `Image.memory`, `gaplessPlayback: true`, `fit: BoxFit.fill`, dan aspect ratio `16:9`.
- `InteractiveViewer` memakai `panEnabled: false`, `minScale: 1`, `maxScale: 5`.
- Touch satu jari mengirim `TOUCH_DOWN` dan `TOUCH_MOVE` dengan `rx/ry`.
- Touch move mirror di-throttle `16 ms`.
- Dua jari melepas touch dengan `TOUCH_UP`, agar pinch viewer tidak dianggap drag mouse.
- Pointer up/cancel terakhir mengirim `TOUCH_UP`.
- Screen frame lama dibersihkan saat connect/disconnect agar tidak menampilkan frame stale.
- PC screen streamer kembali memakai `mss`, `numpy`, dan `opencv-python`.
- Capture primary monitor di-resize fixed ke `1280x720`.
- JPEG quality kembali ke `50`.
- TCP framing tetap 4-byte unsigned big-endian length + JPEG bytes.

## File Yang Berubah

- `android_app/lib/main.dart`
- `pc_worker/screen_streamer.py`
- `pc_worker/requirements.txt`
- `docs/PHASE_9_SCREEN_MIRROR.md`
- `docs/REPAIR_PHASE_1_REFERENCE_MAPPING.md`

## Catatan

- Auth awal screen channel tetap dipertahankan karena itu bagian security Smart MPC.
- Setelah auth sukses, payload frame tetap mengikuti stream referensi.
- Dependency worker diselaraskan dengan implementasi acuan: `numpy==2.2.6` dan `opencv-python==4.12.0.88`.

## Verifikasi

- `flutter analyze`
- `gradlew :app:compileDebugKotlin`
- `python -m py_compile pc_worker/worker.py pc_worker/screen_streamer.py`
- Import check `cv2`, `numpy`, dan `mss`
- `npm run check`
