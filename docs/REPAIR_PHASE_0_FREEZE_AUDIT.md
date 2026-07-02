# Repair Phase 0 - Freeze and Audit

Tanggal: 2026-07-02

Dokumen ini membekukan arah kerja setelah uji holistik awal menunjukkan bahwa Smart MPC berhasil secara koneksi/UI, tetapi gagal secara fungsionalitas.

## Status Saat Ini

Smart MPC saat ini dianggap sebagai draft integrasi, bukan source of truth.

Hasil uji awal:

- PC server terlihat stabil dan dapat dipertahankan sebagai basis integrasi.
- Aplikasi Android terbuka dan terkoneksi.
- UI dasar tidak menjadi masalah utama.
- Fungsionalitas Android banyak gagal atau tidak sesuai.
- Beberapa detail penting dari project referensi tidak ikut terbawa.

Kesimpulan:

- Pendekatan lama terlalu banyak redesign.
- Pendekatan berikutnya harus forensic porting.
- Tidak boleh menambah fitur baru sebelum parity terhadap project referensi dipulihkan.

## Source of Truth

Project referensi adalah tolok ukur utama.

Yang harus dianggap sebagai hasil validasi, bukan hiasan:

- sintaks penting
- urutan logic
- lifecycle Android/native
- manifest dan intent filter
- payload dan format pesan
- port dan channel
- retry, delay, throttle, buffer
- ukuran trackpad
- posisi tombol
- sensitivitas input
- layout remote
- kompresi mirror
- audio sample rate dan buffer
- fallback ketika app/server belum siap

Default keputusan:

- salin dulu
- adaptasi minimal
- baru rapikan jika aman

## Larangan Selama Repair

- Jangan redesign fitur yang sudah berhasil di project referensi.
- Jangan mengganti layout remote dengan layout baru.
- Jangan membuat protokol baru jika protokol lama sudah terbukti.
- Jangan mengubah urutan logic tanpa alasan konkret.
- Jangan menghapus fallback lama.
- Jangan menganggap angka, ukuran, timing, atau buffer sebagai detail kosmetik.
- Jangan menyentuh project referensi.

## Prinsip Porting

Untuk setiap fitur:

1. Baca file lama yang relevan.
2. Catat function/class lama.
3. Catat urutan event.
4. Catat UI/layout lama.
5. Catat parameter penting.
6. Bandingkan dengan Smart MPC.
7. Copy/adaptasi implementasi lama ke Smart MPC.
8. Pertahankan auth/trust Smart MPC hanya sebagai wrapper jika diperlukan.

## Catatan Android Dari Uji Awal

### Connect Tab

Section PC Server:

- Hilangkan Health.
- Hilangkan Pair Info.
- Find PC tetap digunakan.
- Find PC harus benar-benar mengisi PC Address jika PC ditemukan.
- Trust Phone tetap digunakan.
- Save tetap digunakan untuk menyimpan PC Address dan pairing token.

Section Device:

- Bisa dipertahankan.
- Clear Local Trust bisa dipertahankan.

Section PC Addresses:

- Hilangkan.

Section Discovered PCs:

- Masih bisa diterima.

Catatan:

- Jangan redundan.
- Flow harus efisien.
- Manual PC Address dan Find PC harus saling melengkapi.

### Actions Tab

- Pengelompokan section bisa dipertahankan.
- Request Files harus mengikuti metode project referensi.
- Fitur lain harus diuji ulang terhadap implementasi lama.

### Remote Tab

- Harus mengikuti project remote referensi secara literal.
- Layout trackpad, ukuran, tombol, sensitivitas, on/off, audio, dan remote controls harus dipertahankan.
- Mirror boleh tetap dipisah ke tab sendiri.

## Area Prioritas

Urutan repair:

1. Android Connect tab cleanup.
2. NFC forensic port.
3. Request files parity.
4. File upload/download parity.
5. Clipboard dan quick actions parity.
6. Remote UI parity.
7. Remote logic parity.
8. Audio parity.
9. Mirror parity.
10. Discovery parity.
11. PC server compatibility bridge.
12. Holistic test prep.

## Definition of Done Fase 0

- Arah kerja baru terdokumentasi.
- Smart MPC dibekukan sebagai draft, bukan acuan final.
- Aturan forensic porting terdokumentasi.
- Catatan Android dari hasil uji terdokumentasi.
- Tidak ada perubahan fungsional baru.
