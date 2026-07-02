# Repair Phase 13 - PC Server Compatibility Bridge

Status: complete.

Tujuan fase ini adalah memastikan PC server menjadi bridge kompatibel untuk flow lama dan kontrak Smart MPC, tanpa membuang trust/auth yang sudah dibangun.

## Yang Dipulihkan

- Endpoint lama dari project NFC tetap dipertahankan:
  - `GET /pair`
  - `POST /api/devices/register`
  - `POST /api/intent`
  - `POST /api/files`
  - `GET /api/clipboard`
  - `GET /api/request-files`
  - `GET /api/request-files/download`
- Protected route tetap memakai trusted device header.
- `POST /api/session/start` ditambahkan sesuai kontrak shared protocol.
- `POST /api/session/stop` ditambahkan sesuai kontrak shared protocol.
- Protected route sekarang bisa memakai `X-Session-Token` selain trusted device credentials.
- Session runtime dibersihkan saat server stop.
- Server state menampilkan jumlah session aktif, bukan token mentah.
- Command response dibuat lebih kompatibel dengan server lama:
  - `lock_pc` mengembalikan `result: locked`
  - `sleep_pc` mengembalikan `result: sleep_requested`
  - `open_chrome` dan open path mengembalikan `result: opened`
- Config command lama berbentuk `open_path` dengan field `path` tetap didukung.

## File Yang Berubah

- `pc_app/src/constants.mjs`
- `pc_app/src/server.mjs`
- `pc_app/README.md`

## Catatan

- Session token hanya disimpan in-memory.
- Session bridge tidak mengganti auth lama; ini hanya compatibility layer untuk kontrak yang sudah tercatat.
- Worker tetap tidak menerima command bebas langsung dari Android. Semua command tetap lewat PC server/control server yang melakukan validasi.
- Runtime path lokal tidak ditulis ke README atau dokumen publik baru.

## Verifikasi

- `npm run check`
- `flutter analyze`
- `gradlew :app:compileDebugKotlin`
