# Repair Phase Plan

Rencana ini menggantikan pendekatan integrasi awal. Tujuannya adalah mengembalikan parity terhadap project referensi melalui forensic porting.

## Phase 0 - Freeze and Audit

- Bekukan penambahan fitur baru.
- Catat hasil uji awal.
- Tetapkan project referensi sebagai source of truth.
- Catat aturan copy/adaptasi minimal.

## Phase 1 - Full Reference Mapping

- Baca dua project referensi.
- Buat mapping fitur ke file/function/layout/sequence.
- Tandai fitur yang boleh dipertahankan dari Smart MPC dan fitur yang harus di-port ulang.

## Phase 2 - Android Connect Tab Cleanup

- Hapus Health.
- Hapus Pair Info.
- Hapus PC Addresses.
- Pertahankan Find PC, Trust Phone, Save, Device, Discovered PCs.
- Find PC harus mengisi PC Address ketika berhasil.

## Phase 3 - NFC Forensic Port

- Port manifest, activity, deep link, NDEF, lifecycle, pending action, fallback.
- Gunakan implementasi lama sebagai blueprint.

## Phase 4 - NFC Action Parity

- Port aksi NFC satu per satu.
- Send file, pull clipboard, request files, open Chrome, lock, sleep.

## Phase 5 - Request Files Parity

- Pertahankan metode lama: PC outbox, Add Files dari PC app, Android refresh/list/download icon.
- Sesuaikan auth saja jika perlu.

## Phase 6 - File Upload/Download Parity

- Port file picker, multiple upload, DownloadManager, filename handling, headers, error handling.

## Phase 7 - Clipboard and Quick Actions Parity

- Port send clipboard, pull clipboard, open URL, continue intent, command whitelist.

## Phase 8 - Remote UI Parity

- Remote tab mengikuti project referensi.
- Layout trackpad, ukuran, posisi tombol, toggle, grouping, audio controls.
- Mirror boleh tetap tab terpisah.

## Phase 9 - Remote Logic Parity

- Port mouse move, click, scroll, sensitivity, throttle, browser gestures, zoom, media, special keys, live typing.

## Phase 10 - Audio Parity

- Port audio toggle, UDP behavior, native AudioTrack receiver, buffer, sample rate, start/stop order.

## Phase 11 - Mirror Parity

- Port capture, JPEG compression, frame size, FPS, TCP framing, Android render, touch mapping, pinch behavior.

## Phase 12 - Discovery Parity

- Port discovery request/response, broadcast timing, parsing, UI behavior.

## Phase 13 - PC Server Compatibility Bridge

- Sesuaikan PC server agar mendukung flow lama tanpa membuang trust/auth Smart MPC.
- Fokus bridge, bukan rewrite worker yang sudah terbukti.

## Phase 14 - Holistic Test Prep

- Update checklist.
- Jalankan sanity checks.
- Siapkan uji holistik ulang.
