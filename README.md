# Smart MPC

Smart MPC adalah project gabungan baru untuk menyatukan ide dari dua project referensi lokal:

- prototype NFC quick-action Android/PC
- prototype mobile-to-PC media remote

Aturan utama:

- Dua project referensi tidak disentuh.
- Semua fitur dari dua project referensi harus masuk ke Smart MPC.
- Bagian yang diperlukan boleh disalin ke root project ini, lalu diadaptasi.
- Pengujian penuh dilakukan setelah fitur besar selesai digabung.

Dokumen awal:

- [Phase 0 Feature Lock](docs/PHASE_0_FEATURE_LOCK.md)
- [Phase 1 Structure](docs/PHASE_1_STRUCTURE.md)
- [Phase 2 PC Server Core](docs/PHASE_2_PC_SERVER_CORE.md)
- [Phase 3 PC Desktop Shell](docs/PHASE_3_PC_DESKTOP_SHELL.md)
- [Phase 4 Android App Core](docs/PHASE_4_ANDROID_APP_CORE.md)
- [Phase 5 File Clipboard Quick Actions](docs/PHASE_5_FILE_CLIPBOARD_QUICK_ACTIONS.md)
- [Phase 6 NFC Integration](docs/PHASE_6_NFC_INTEGRATION.md)
- [Phase 7 Remote Control Live](docs/PHASE_7_REMOTE_CONTROL_LIVE.md)
- [Phase 8 Audio Streaming](docs/PHASE_8_AUDIO_STREAMING.md)
- [Phase 9 Screen Mirror](docs/PHASE_9_SCREEN_MIRROR.md)
- [Phase 10 Discovery and Prep](docs/PHASE_10_DISCOVERY_AND_PREP.md)
- [Holistic Test Checklist](docs/HOLISTIC_TEST_CHECKLIST.md)

Dokumen repair:

- [Repair Phase 0 Freeze and Audit](docs/REPAIR_PHASE_0_FREEZE_AUDIT.md)
- [Forensic Porting Rules](docs/FORENSIC_PORTING_RULES.md)
- [Repair Phase Plan](docs/REPAIR_PHASE_PLAN.md)
- [Reference Implementation Index](docs/REFERENCE_IMPLEMENTATION_INDEX.md)
- [Repair Phase 1 Reference Mapping](docs/REPAIR_PHASE_1_REFERENCE_MAPPING.md)
- [Repair Phase 2 Connect Tab](docs/REPAIR_PHASE_2_CONNECT_TAB.md)
- [Repair Phase 3 NFC Forensic Port](docs/REPAIR_PHASE_3_NFC_FORENSIC_PORT.md)
- [Repair Phase 4 NFC Action Parity](docs/REPAIR_PHASE_4_NFC_ACTION_PARITY.md)
- [Repair Phase 5 Request Files Parity](docs/REPAIR_PHASE_5_REQUEST_FILES_PARITY.md)
- [Repair Phase 6 File Upload Download Parity](docs/REPAIR_PHASE_6_FILE_UPLOAD_DOWNLOAD_PARITY.md)
- [Repair Phase 7 Clipboard Quick Actions Parity](docs/REPAIR_PHASE_7_CLIPBOARD_QUICK_ACTIONS_PARITY.md)
- [Repair Phase 8 Remote UI Parity](docs/REPAIR_PHASE_8_REMOTE_UI_PARITY.md)
- [Repair Phase 9 Remote Logic Parity](docs/REPAIR_PHASE_9_REMOTE_LOGIC_PARITY.md)
- [Repair Phase 10 Audio Parity](docs/REPAIR_PHASE_10_AUDIO_PARITY.md)
- [Repair Phase 11 Mirror Parity](docs/REPAIR_PHASE_11_MIRROR_PARITY.md)
- [Repair Phase 12 Discovery Parity](docs/REPAIR_PHASE_12_DISCOVERY_PARITY.md)
- [Repair Phase 13 PC Server Compatibility Bridge](docs/REPAIR_PHASE_13_PC_SERVER_COMPATIBILITY_BRIDGE.md)
- [Repair Phase 14 Holistic Test Prep](docs/REPAIR_PHASE_14_HOLISTIC_TEST_PREP.md)

Migrasi media production:

- [WebRTC Migration Phase 0 Baseline](docs/WEBRTC_MIGRATION_PHASE_0_BASELINE.md)
- [WebRTC Migration Phase 1 Isolation Contract](docs/WEBRTC_MIGRATION_PHASE_1_ISOLATION_CONTRACT.md)
- [WebRTC Media Migration Plan](docs/WEBRTC_MIGRATION_PLAN.md)

Struktur modul:

- [android_app](android_app/README.md) - aplikasi Android Flutter, NFC entry, dan native audio receiver.
- [pc_app](pc_app/README.md) - desktop app PC, Node server utama, pairing, file, clipboard, dan bridge ke worker.
- [pc_worker](pc_worker/README.md) - worker Python untuk kontrol PC, audio loopback, dan screen capture.
- [shared_protocol](shared_protocol/README.md) - kontrak endpoint, command, event, channel, dan auth.

Script lokal:

- `scripts/prepare_runtime.cmd` - install dependency Node, Flutter, dan Python worker.
- `scripts/start_pc_app.cmd` - buka desktop PC app.
- `scripts/start_pc_server.cmd` - jalankan PC server tanpa UI.
- `scripts/run_android.cmd` - jalankan Android Flutter app.
