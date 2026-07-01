# Phase 1 Structure

Tanggal: 2026-07-01

Fase ini membuat struktur awal project Smart MPC di root repository.

## Folder

```text
Smart_MPC/
+-- android_app/
+-- pc_app/
+-- pc_worker/
+-- shared_protocol/
+-- docs/
+-- README.md
+-- .gitignore
```

## Modul

### android_app

Aplikasi Android Flutter dan native Android integration.

Fitur target:

- Pairing dan connect.
- Quick actions.
- File dan clipboard.
- Remote control.
- Audio receiver.
- Screen mirror.
- NFC/deep-link launcher.

### pc_app

Desktop app PC dan server utama.

Fitur target:

- Electron shell.
- Node server.
- Pairing/trusted devices.
- File dan clipboard API.
- Quick action API.
- Control/session broker.
- Bridge ke Python worker.

### pc_worker

Worker Python untuk OS-level integration.

Fitur target:

- PyAutoGUI commands.
- Audio loopback.
- Screen capture.
- Touch coordinate execution.

### shared_protocol

Kontrak komunikasi antar modul.

File awal:

- `shared_protocol/protocol.json`

## Keputusan Fase 1

- Root `Smart_MPC` menjadi project gabungan baru.
- Project referensi tetap tidak disentuh.
- `pc_app` adalah pusat auth/trust.
- `pc_worker` tidak menerima command bebas dari Android secara langsung.
- Full testing ditunda sampai fase integrasi besar.

## Fase Berikutnya

Fase 2: PC Server Core.

Target Fase 2:

- package awal `pc_app`.
- Node server core.
- config generator.
- local IP detection.
- `/health`.
- `/pair`.
- pairing token.
- trusted devices storage.
- register/revoke device.
- server state.
