# Phase 3 PC Desktop Shell

Tanggal: 2026-07-01

Fase ini membuat shell desktop awal untuk PC app dengan Electron.

## Hasil

File baru:

```text
pc_app/
+-- renderer/
    +-- index.html
    +-- renderer.js
    +-- styles.css
+-- src/
    +-- electron/
        +-- main.mjs
        +-- preload.cjs
```

File diperbarui:

- `pc_app/package.json`
- `pc_app/README.md`
- `README.md`

## Fitur UI Awal

- Window Electron.
- Server auto-start saat app dibuka.
- Start/stop server dari UI.
- Status running/stopped.
- PC name.
- Port.
- Pairing token.
- Copy pairing token.
- Base URL list.
- Copy base URL dengan klik.
- Trusted devices list.
- Revoke trusted device.
- Activity log.
- Open inbox.
- Open outbox.
- Refresh state berkala.

## Keamanan

- Renderer memakai preload bridge.
- `nodeIntegration` dimatikan.
- `contextIsolation` dinyalakan.
- Renderer hanya mengakses API IPC terbatas.

## Belum Dikerjakan Di Fase Ini

- Packaging installer.
- Tray/menu app.
- Icon final.
- File transfer route.
- Clipboard route.
- Quick action execution.
- Worker bridge.
- Remote-control realtime channel.
- Audio/screen channel.
- Full UI screenshot verification.

## Cara Menjalankan Nanti

```powershell
cd pc_app
npm install
npm run start
```

Fase ini tidak menjalankan `npm install` otomatis.

## Fase Berikutnya

Fase 4: Android App Core.

Target:

- Flutter project awal.
- Connect screen.
- Manual IP input.
- Pairing code input.
- Find PC placeholder/flow.
- Trust phone request.
- Simpan config lokal.
- Navigasi dasar.
