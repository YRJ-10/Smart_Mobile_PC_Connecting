# Phase 2 PC Server Core

Tanggal: 2026-07-01

Fase ini membuat server inti PC app. Fokusnya adalah fondasi koneksi, pairing, trusted device, dan state server.

## Hasil

File baru:

```text
pc_app/
+-- package.json
+-- src/
    +-- constants.mjs
    +-- config.mjs
    +-- index.mjs
    +-- network.mjs
    +-- request-log.mjs
    +-- server.mjs
```

## Fitur Server Core

- Package awal `pc_app`.
- Script `npm run server`.
- Script `npm run check`.
- Config generator runtime.
- Runtime `config.json` diabaikan oleh git.
- Runtime `inbox/` dan `outbox/` diabaikan oleh git.
- Local IP detection.
- Server state.
- Request log in-memory.
- Pairing token.
- Trusted device storage.
- Register trusted device.
- Revoke device API internal via class method.
- Header auth:
  - `X-Pairing-Token`
  - `X-Device-Id`
  - `X-Device-Token`

## Endpoint Awal

- `GET /health`
- `GET /pair`
- `POST /api/devices/register`
- `GET /api/server/state`

## Belum Dikerjakan Di Fase Ini

- Electron UI.
- File transfer routes.
- Clipboard routes.
- Quick action execution.
- Python worker bridge.
- Realtime remote-control channel.
- Discovery UDP.
- Audio stream.
- Screen stream.

## Keputusan

- `pc_app` menjadi authority utama untuk trust/auth.
- Worker tidak menerima command langsung dari Android.
- Server core dibuat tanpa dependency eksternal dulu.
- Full integration test tetap ditunda sampai fase gabungan.

## Fase Berikutnya

Fase 3: PC Desktop App shell.

Target:

- Electron shell.
- Renderer UI awal.
- Start/stop server dari UI.
- Pairing token display.
- IP/base URL display.
- Trusted devices list.
- Activity log display.
