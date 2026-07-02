# Repair Phase 6 - File Upload and Download Parity

Status: complete.

Fase ini mengunci detail file upload/download native agar mengikuti reference NFC dan tidak kembali ke implementasi baru yang hanya mirip konsep.

## Upload From Android To PC

Jalur upload Android:

- Actions tab `Send File`
- NFC quick action `send_file`

Detail yang dipertahankan:

- Native Android file picker.
- `Intent.ACTION_OPEN_DOCUMENT`.
- `Intent.CATEGORY_OPENABLE`.
- MIME `*/*`.
- `Intent.EXTRA_ALLOW_MULTIPLE`.
- Request code `7291`.
- Multiple URI extraction via `clipData`.
- Fallback single URI via `data`.
- Filename dari `OpenableColumns.DISPLAY_NAME`.
- Fallback filename `upload-{timestamp}`.
- Upload langsung dari `contentResolver.openInputStream(uri)`.
- `setChunkedStreamingMode(0)`.
- `Content-Type: application/octet-stream`.
- Header `X-Device-Id`.
- Header `X-Device-Token`.
- Endpoint `POST /api/files?filename=...`.
- JSON response wajib `ok: true`.

Timeout upload disamakan:

- connect timeout `3000 ms`.
- read timeout `30000 ms`.

## Download From PC To Android

Jalur download Android:

- Actions tab `Request Files`.
- Refresh dari `/api/request-files`.
- Tiap file punya icon download.
- Download memakai native Android `DownloadManager`.

Detail yang dipertahankan:

- Endpoint `GET /api/request-files/download?filename=...`.
- Filename query memakai `Uri.encodeQueryComponent`.
- Download title memakai safe filename.
- Destination `Environment.DIRECTORY_DOWNLOADS`.
- Notification `VISIBILITY_VISIBLE_NOTIFY_COMPLETED`.
- Header `X-Device-Id`.
- Header `X-Device-Token`.

## PC Server Filename Handling

Server filename sanitizer dikembalikan mendekati reference:

- hanya mengizinkan huruf, angka, spasi, `.`, `_`, `-`, `(`, `)`, `[`, `]`;
- karakter lain dibuang;
- filename kosong fallback ke `file-{timestamp}`;
- duplicate filename memakai suffix increment;
- request download tetap dibatasi ke child path outbox.

## File

- `android_app/android/app/src/main/kotlin/com/smartmpc/app/MainActivity.kt`
- `android_app/android/app/src/main/kotlin/com/smartmpc/app/NfcLaunchActivity.kt`
- `android_app/lib/main.dart`
- `pc_app/src/server.mjs`

## Verification

- `flutter analyze`: no issues.
- `:app:compileDebugKotlin`: success.
- `node --check pc_app/src/server.mjs`: success.
- `npm.cmd run check`: success.
