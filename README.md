# Smart MPC

Smart MPC adalah project gabungan baru untuk menyatukan ide dari dua project referensi:

- `C:\Users\yeryi\AndroidStudioProjects\NFC_Instan_Action`
- `C:\Users\yeryi\AndroidStudioProjects\MobilePCMedia`

Aturan utama:

- Dua project referensi tidak disentuh.
- Semua fitur dari dua project referensi harus masuk ke Smart MPC.
- Bagian yang diperlukan boleh disalin ke root project ini, lalu diadaptasi.
- Pengujian penuh dilakukan setelah fitur besar selesai digabung.

Dokumen awal:

- [Phase 0 Feature Lock](docs/PHASE_0_FEATURE_LOCK.md)
- [Phase 1 Structure](docs/PHASE_1_STRUCTURE.md)

Struktur modul:

- [android_app](android_app/README.md) - aplikasi Android Flutter, NFC entry, dan native audio receiver.
- [pc_app](pc_app/README.md) - desktop app PC, Node server utama, pairing, file, clipboard, dan bridge ke worker.
- [pc_worker](pc_worker/README.md) - worker Python untuk kontrol PC, audio loopback, dan screen capture.
- [shared_protocol](shared_protocol/README.md) - kontrak endpoint, command, event, channel, dan auth.
