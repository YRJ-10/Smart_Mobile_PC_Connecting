# PC App

Modul ini akan berisi desktop app PC dan server utama.

Tanggung jawab:

- Electron desktop shell.
- Node local server utama.
- Server start/stop.
- Local IP display.
- Pairing token display.
- Trusted device management.
- Revoke device.
- Request/activity log.
- File inbox/outbox.
- Clipboard API.
- Quick action API.
- Auth/trust enforcement.
- Bridge ke `pc_worker` untuk fitur kontrol PC, audio, dan screen.

Sumber referensi read-only:

- `C:\Users\yeryi\AndroidStudioProjects\NFC_Instan_Action\Pc Local Server`
- `C:\Users\yeryi\AndroidStudioProjects\MobilePCMedia\python_server`

Catatan:

- `pc_app` menjadi pusat trust/auth.
- Channel remote-control dari worker harus dilindungi oleh trusted device/session.
- Runtime data lokal seperti `config.json`, `inbox`, `outbox`, dan logs tidak masuk git.
