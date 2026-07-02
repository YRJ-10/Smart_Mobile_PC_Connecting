# Repair Phase 2 - Android Connect Tab Cleanup

Status: complete.

Fase ini hanya mengubah Android Connect tab. Tidak ada perubahan pada remote, NFC action, request files, audio, mirror, atau PC server.

## Perubahan

- Menghapus tombol `Health` dari section `PC Server`.
- Menghapus tombol `Pair Info` dari section `PC Server`.
- Menghapus section `PC Addresses`.
- Menghapus state/helper internal yang hanya dipakai oleh PC Addresses.
- Mempertahankan `PC Address`, `Pairing Token`, `Find PC`, `Trust Phone`, dan `Save`.
- Mempertahankan section `Device` termasuk `Clear Local Trust`.
- Mempertahankan `Discovered PCs`.

## Find PC Behavior

`Find PC` tetap menjalankan discovery jaringan lokal.

Ketika PC ditemukan:

- hasil discovery disimpan ke `Discovered PCs`;
- PC pertama otomatis mengisi `PC Address`;
- nama PC disimpan untuk status UI;
- `pcId` disimpan bila tersedia dari response;
- config langsung disimpan agar alamat tidak perlu diisi ulang saat app dibuka lagi.

Ketika user memilih item di `Discovered PCs`:

- `PC Address` diisi dengan alamat item tersebut;
- nama PC dan `pcId` diperbarui bila ada;
- config disimpan.

## Source Of Truth

Keputusan fase ini mengikuti catatan user:

- Health dan Pair Info tidak dipakai.
- PC Addresses tidak perlu.
- Find PC harus berguna dan mengisi PC Address.
- Trust Phone dan Save wajib tetap ada.
- Device section dan Clear Local Trust bisa diterima.
- Discovered PCs masih bisa diterima.

## File

- `android_app/lib/main.dart`
