# Phase 5 File Clipboard Quick Actions

Tanggal: 2026-07-01

Fase ini memasukkan fitur aksi pertama yang benar-benar dipakai setelah pairing.

## PC Server

Endpoint baru:

- `POST /api/intent`
- `POST /api/files`
- `GET /api/clipboard`
- `GET /api/request-files`
- `GET /api/request-files/download`

Intent awal:

- `url`
- `clipboard`
- `file`
- `command`
- `continue`

Command awal:

- `open_inbox`
- `open_downloads`
- `open_chrome`
- `lock_pc`
- `sleep_pc`

File support:

- Android upload masuk ke runtime `inbox/`.
- PC outbox files bisa dilist dan didownload Android.
- Electron shell bisa menambahkan file ke outbox.
- Filename disanitasi sebelum disimpan/dibaca.
- Download dibatasi ke outbox directory.

Clipboard support:

- Android kirim teks ke PC clipboard.
- Android pull PC clipboard.

## Android App

Actions tab sekarang berisi:

- Send File.
- Request Files.
- Download file dari outbox.
- Read Phone clipboard.
- Send clipboard to PC.
- Pull clipboard from PC.
- Open URL on PC.
- PC command buttons.

Native bridge baru:

- `pickAndUploadFiles`
- `downloadToDownloads`
- `nativeStatus`

## PC Desktop Shell

Tambahan UI:

- Add files to outbox.
- Outbox file preview.

## Belum Dikerjakan Di Fase Ini

- NFC/deep-link quick trigger.
- Remote control live.
- Voice typing.
- Audio streaming.
- Screen mirror.
- Full end-to-end test.

## Fase Berikutnya

Fase 6: NFC Integration.

Target:

- NFC/deep-link Activity.
- Quick action preference.
- Tap action runner.
- NFC send file.
- NFC pull clipboard.
- NFC request files fallback.
- NFC open Chrome.
- NFC lock/sleep PC.
