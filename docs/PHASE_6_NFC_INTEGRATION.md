# Phase 6 NFC Integration

Tanggal: 2026-07-01

Fase ini memasukkan kembali alur tap/NFC ke Smart MPC.

## Android Native

File baru:

```text
android_app/android/app/src/main/kotlin/com/smartmpc/app/NfcLaunchActivity.kt
```

Perubahan:

- `MainActivity` menyimpan `quickAction`.
- `MainActivity` menerima deep link dari native.
- `MainActivity` menyediakan `runTapAction`.
- Manifest menambahkan permission `android.permission.NFC`.
- Manifest menambahkan activity `NfcLaunchActivity`.
- Deep link dan NDEF route memakai `smartmpc://tap`.

## Quick Actions

Quick actions yang didukung:

- `send_file`
- `pull_clipboard`
- `request_files`
- `open_chrome`
- `lock_pc`
- `sleep_pc`

## Behavior

- `send_file`: buka file picker native lalu upload ke PC inbox.
- `pull_clipboard`: ambil PC clipboard dan simpan ke phone clipboard.
- `request_files`: buka app utama dan load file outbox PC.
- `open_chrome`: kirim command ke PC.
- `lock_pc`: kirim command ke PC.
- `sleep_pc`: kirim command ke PC.

## Android UI

Actions tab sekarang punya:

- Quick Action selector.
- Run Tap Action button.

## Belum Dikerjakan Di Fase Ini

- Menulis sticker NFC fisik.
- UI khusus untuk membuat payload NFC.
- Remote control live.
- Audio streaming.
- Screen mirror.
- Full device test.

## Fase Berikutnya

Fase 7: Remote Control Live.

Target:

- PC worker command executor.
- Realtime control channel.
- Android remote trackpad.
- Mouse move/click/scroll.
- Special keys.
- Live typing.
- Voice typing foundation.
