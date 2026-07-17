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

- prototype NFC quick-action PC server/app
- prototype media remote Python server

Catatan:

- `pc_app` menjadi pusat trust/auth.
- Channel remote-control dari worker harus dilindungi oleh trusted device/session.
- Runtime data lokal seperti `config.json`, `inbox`, `outbox`, dan logs tidak masuk git.

## Fase 2: Server Core

Server core awal tersedia di `src/`.

Script:

```powershell
npm run server
npm run check
```

Endpoint awal:

- `GET /health`
- `GET /pair`
- `POST /api/devices/register`
- `POST /api/session/start`
- `POST /api/session/stop`
- `GET /api/media/capabilities`
- `POST /api/media/sessions`
- `GET /api/media/sessions/{id}/status`
- `POST /api/media/sessions/{id}/signals`
- `GET /api/media/sessions/{id}/signals`
- `POST /api/media/sessions/{id}/stop`
- `GET /api/server/state`
- `POST /api/intent`
- `POST /api/files`
- `GET /api/clipboard`
- `GET /api/request-files`
- `GET /api/request-files/download`

Compatibility bridge:

- Protected HTTP routes accept trusted device headers.
- Protected HTTP routes also accept `X-Session-Token` after `POST /api/session/start`.
- Legacy NFC endpoints and response shapes remain supported.
- Legacy `open_path` commands with a configured `path` remain supported.

Remote control:

- TCP JSON-lines channel di port `8080`.
- Pesan pertama harus auth trusted device.
- Command remote divalidasi di `src/control-server.mjs`.
- Eksekusi OS diteruskan ke `pc_worker`.
- Audio toggle memakai control channel untuk start/stop worker audio stream ke Android.
- Screen mirror memakai TCP channel `8082`, trusted auth, dan worker screen streamer.
- Discovery memakai UDP port `8081` dan merespons request baru maupun legacy.

Runtime files yang dibuat saat server dijalankan:

- `config.json`
- `inbox/`
- `outbox/`

File runtime tersebut tidak masuk git.

Chrome profile optional dapat diatur di `config.json` lokal:

```json
{
  "chrome_profile": "Profile 1",
  "chrome_user_data_dir": ""
}
```

Kosongkan nilainya untuk memakai behavior default Chrome.

## Fase 3: Desktop Shell

Electron shell awal tersedia.

Script:

```powershell
npm install
npm run start
```

UI awal:

- server status
- start/stop server
- PC name
- port
- pairing token
- base URL list
- trusted devices list
- revoke trusted device
- activity log
- open inbox/outbox
- add files to outbox
- outbox file preview

Catatan:

- Dependency Electron belum di-install otomatis oleh fase ini.
- Full UI verification ditunda sampai fase testing gabungan.
