# Repair Phase 12 - Discovery Parity

Status: complete.

Tujuan fase ini adalah membuat Find PC mengikuti perilaku discovery lama yang terbukti, sambil tetap mempertahankan metadata Smart MPC.

## Yang Dipulihkan

- Android tetap mengirim legacy request `DISCOVER_MOBILEPC`.
- Android tetap mengirim Smart MPC request `DISCOVER_SMART_MPC`.
- Scan menunggu total sekitar `3` detik seperti referensi.
- Request dikirim berulang supaya paket broadcast yang hilang tidak langsung membuat scan gagal.
- Target broadcast mencakup `255.255.255.255` dan broadcast `/24` dari interface IPv4 aktif.
- Parser Android menerima:
  - JSON Smart MPC payload,
  - exact legacy response `MOBILEPC_SERVER`,
  - `MOBILEPC_SERVER {json}`,
  - `SMART_MPC_SERVER {json}`,
  - exact `SMART_MPC_SERVER`.
- Hasil discovery dedupe berdasarkan host agar response legacy dan metadata JSON tidak muncul dobel.
- Jika metadata JSON datang setelah response legacy exact, hasil metadata diprioritaskan.
- Find PC tetap otomatis mengisi `PC Address`, menyimpan config, dan mengisi daftar Discovered PCs.
- PC server membalas request legacy dengan exact `MOBILEPC_SERVER` untuk kompatibilitas lama.
- PC server juga mengirim payload JSON Smart MPC agar Android baru tetap mendapat base URL, PC id, dan port.

## File Yang Berubah

- `android_app/lib/main.dart`
- `pc_app/src/discovery-server.mjs`

## Catatan

- Discovery tetap memakai UDP port `8081`, sama seperti referensi.
- Audio receiver Android juga memakai port `8081`, tetapi discovery Android memakai ephemeral source port saat scan.
- Legacy exact response penting karena app lama hanya menerima string yang persis sama.
- Metadata JSON penting agar Smart MPC bisa mengisi HTTP base URL tanpa user menyalin IP manual.

## Verifikasi

- `flutter analyze`
- `npm run check`
