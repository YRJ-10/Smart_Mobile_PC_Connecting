# Holistic Test Checklist

Gunakan checklist ini untuk uji lengkap setelah semua fase repair selesai. Jalankan dengan sabar dari atas ke bawah agar jika ada kegagalan, titik gagalnya jelas.

## Persiapan Runtime

- Jalankan `scripts/prepare_runtime.cmd` jika dependency belum pernah disiapkan setelah perubahan terakhir.
- Jalankan `scripts/start_pc_app.cmd` untuk membuka desktop shell PC.
- Pastikan server HTTP, remote control, discovery, dan screen status berjalan di desktop shell.
- Pastikan firewall mengizinkan jaringan lokal untuk port `8765`, `8080`, `8081`, dan `8082`.
- Catat pairing token dari desktop shell.

## Persiapan Android

- Jalankan Android app dari Android Studio.
- Buka tab Connect.
- Tekan Find PC.
- Pastikan PC Address terisi otomatis jika PC ditemukan.
- Jika Find PC gagal, isi PC Address manual.
- Masukkan pairing token.
- Tekan Trust Phone.
- Tekan Save.
- Tutup dan buka ulang app Android, lalu pastikan PC Address dan token masih tersimpan.

## Connect Tab

- Device ID muncul.
- Trusted indicator aktif setelah Trust Phone.
- Clear Local Trust menghapus trust lokal.
- Discovered PCs muncul setelah Find PC berhasil.
- Mengetuk item Discovered PCs mengisi PC Address.
- Tidak ada section Health, Pair Info, atau PC Addresses.

## Actions Tab

- Send File mengirim file Android ke inbox PC.
- PC shell Add Files memasukkan file ke outbox.
- Request Files menampilkan daftar outbox di Android.
- Tombol download tiap file menyimpan file ke Downloads Android.
- Send Clipboard mengirim teks Android ke clipboard PC.
- Pull Clipboard mengambil clipboard PC ke Android.
- Open URL membuka URL di PC.
- Command Open Chrome bekerja.
- Lock PC bekerja jika aman diuji.
- Sleep PC hanya diuji jika memang aman.

## NFC Quick Actions

- Tap action `send_file` membuka picker lalu upload ke PC.
- Tap action `pull_clipboard` mengambil clipboard PC.
- Tap action `request_files` membuka app ke flow request files.
- Tap action `open_chrome` menjalankan command PC.
- Tap action `lock_pc` menjalankan lock jika aman.
- Tap action `sleep_pc` hanya diuji jika aman.
- Deep link `smartmpc://tap` masih diproses.
- Legacy scheme `nfcinstant://tap` masih diproses.

## Remote Tab

- Connect Remote berhasil.
- Trackpad satu jari menggerakkan mouse dengan sensitivitas yang terasa seperti project acuan.
- Tap satu jari menjadi left click.
- Tap dua jari menjadi right click.
- Scroll dua jari berjalan.
- Swipe horizontal dua jari menjadi browser back/forward.
- Live typing mengirim teks.
- Edit tengah teks mengirim backspace dan teks baru dengan benar.
- Tombol Alt+Tab, Enter, Backspace, Refresh, Copy, dan Paste bekerja.
- Voice dictation mengirim teks ke PC.

## Audio

- Tekan Audio ON.
- Audio PC terdengar di Android.
- Remote control tetap responsif saat audio aktif.
- Tekan Audio OFF.
- Audio berhenti bersih.
- Disconnect Remote mematikan audio receiver Android.

## Mirror

- Buka tab Mirror.
- Android masuk landscape.
- Mirror auto-connect.
- Frame layar PC muncul.
- Frame memenuhi area 16:9.
- Pinch zoom viewer bekerja.
- Satu jari pada mirror mengontrol pointer PC.
- Dua jari melepas mouse dan tidak membuat drag tersangkut.
- Tombol back overlay keluar dari mirror dan kembali portrait.
- Disconnect mirror berhenti bersih.

## Discovery

- Find PC menemukan PC lewat UDP.
- Legacy request `DISCOVER_MOBILEPC` tetap dijawab.
- Smart request `DISCOVER_SMART_MPC` tetap dijawab.
- Jika PC ditemukan lewat legacy response lebih dulu, metadata JSON tetap memperbarui hasil saat datang.

## Catatan Hasil

- Catat fitur yang gagal.
- Catat langkah terakhir sebelum gagal.
- Catat pesan status Android.
- Catat activity log PC shell.
- Catat apakah kegagalan terkait firewall, dependency worker, pairing/trust, atau input mapping.
