# Shared Protocol

Modul ini menyimpan kontrak komunikasi antara Android app, PC app, dan PC worker.

Isi awal:

- `protocol.json` untuk daftar endpoint, channel, command id, dan event.
- Kontrak auth dan trust.
- Kontrak command realtime.
- Kontrak stream audio/screen.

Prinsip:

- Semua fitur protected harus memakai trusted device/session.
- Command live tidak boleh bebas dieksekusi tanpa validasi.
- Nama command dibuat stabil agar Android, PC app, dan worker tidak saling menebak.
