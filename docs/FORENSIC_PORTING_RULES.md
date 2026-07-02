# Forensic Porting Rules

Dokumen ini wajib dibaca sebelum mengerjakan fase repair mana pun.

## Aturan Utama

Smart MPC bukan remake.

Tugas repair adalah:

```text
copy -> adapt minimal -> integrate -> verify
```

Bukan:

```text
reinterpret -> redesign -> rebuild
```

## Apa Yang Harus Diambil

Dari project referensi, ambil:

- UI layout yang sudah terbukti
- urutan logic
- handler event
- native bridge
- manifest entry
- permission
- intent filter
- socket transport
- payload format
- timeout
- retry
- throttle
- buffer size
- compression setting
- state transition
- fallback path
- error handling
- file naming
- storage location

Jika ada detail yang terlihat tidak rapi, anggap dulu itu workaround penting.

## Cara Membuat Mapping

Untuk setiap fitur, buat mapping:

```text
Feature:
Reference project:
Reference files:
Reference functions/classes:
UI/layout source:
Sequence:
Parameters:
Smart MPC current files:
Delta:
Porting decision:
Verification:
```

## Kapan Boleh Mengubah

Perubahan boleh dilakukan hanya jika:

- bentrok dengan sistem trust/auth baru
- bentrok dengan struktur multi-tab gabungan
- perlu menghindari data sensitif
- perlu agar dua project bisa hidup dalam satu app

Setiap perubahan harus kecil dan dijelaskan.

## Hal Yang Tidak Boleh Diubah Sepihak

- layout remote utama
- ukuran dan posisi trackpad
- sensitivitas mouse/scroll
- live typing behavior
- NFC lifecycle
- request files flow
- audio start/stop order
- mirror compression dan frame behavior
- discovery message format lama

## Output Setiap Fase Repair

Setiap fase repair harus menghasilkan:

- mapping singkat fitur lama ke Smart MPC
- daftar file yang disalin/adaptasi
- daftar detail lama yang dipertahankan
- daftar perubahan yang terpaksa dilakukan
- sanity check minimal
