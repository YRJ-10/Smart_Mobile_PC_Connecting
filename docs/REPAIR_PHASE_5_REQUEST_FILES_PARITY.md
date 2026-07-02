# Repair Phase 5 - Request Files Parity

Status: complete.

Fase ini mengunci ulang metode request file lama:

1. PC user menambahkan file ke outbox dari PC app.
2. Android menekan Request Files/Refresh.
3. Android menerima list file dari outbox.
4. Android menekan icon download.
5. Android `DownloadManager` mengunduh file ke Downloads.

## Flow Matrix

| Step | File | Behavior |
| --- | --- | --- |
| Add files on PC | `pc_app/src/electron/main.mjs` | Dialog `openFile` + `multiSelections`, lalu copy ke outbox |
| Copy to outbox | `pc_app/src/server.mjs` | `addFilesToOutbox()` menyalin file dan menjaga nama unik |
| PC state preview | `pc_app/renderer/renderer.js` | Menampilkan seluruh outbox preview, bukan hanya 5 file |
| Android refresh | `android_app/lib/main.dart` | `GET /api/request-files` dengan trusted device headers |
| Android list | `android_app/lib/main.dart` | List file dengan nama, ukuran, dan icon download |
| Android download | `android_app/lib/main.dart` + `MainActivity.kt` | `DownloadManager` ke public Downloads dengan auth headers |

## Perubahan

- Server outbox listing sekarang sorted newest-first berdasarkan `modified_at`, mengikuti reference.
- PC app outbox preview tidak lagi memotong daftar ke 5 file.
- Flow endpoint lama dipertahankan:
  - `GET /api/request-files`
  - `GET /api/request-files/download?filename=...`
- Auth headers tetap dipertahankan:
  - `X-Device-Id`
  - `X-Device-Token`

## Yang Sudah Sesuai Reference

- PC app punya tombol Add Files.
- Add Files tidak memindahkan file asli; file disalin ke outbox.
- Android refresh mengambil daftar dari outbox.
- Android memakai icon download per file.
- Download memakai Android native `DownloadManager`, bukan manual stream Flutter.
- Filename dikirim via query parameter encoded.

## File

- `pc_app/src/server.mjs`
- `pc_app/renderer/renderer.js`
- `android_app/lib/main.dart`
- `android_app/android/app/src/main/kotlin/com/smartmpc/app/MainActivity.kt`

## Verification

- `node --check pc_app/src/server.mjs`: success.
- `node --check pc_app/renderer/renderer.js`: success.
- `npm.cmd run check`: success.
- `flutter analyze`: no issues.
