# Phase 10 - Discovery and Holistic Prep

Tujuan fase ini adalah menutup integrasi sebelum uji holistik dengan auto-discovery PC dan runbook pengujian.

Yang ditambahkan:

- UDP discovery server di PC pada port `8081`.
- Request baru `DISCOVER_SMART_MPC`.
- Request kompatibilitas `DISCOVER_MOBILEPC`.
- Response discovery berisi nama PC, id PC, HTTP base URL, dan port realtime.
- Tombol Find PC di Android Connect tab.
- Daftar Discovered PCs di Android.
- Status Discovery di desktop shell PC.
- Checklist uji holistik.

Port map:

- HTTP API: `8765`.
- TCP control: `8080`.
- UDP discovery: `8081`.
- UDP audio stream ke Android: `8081` di sisi Android receiver.
- TCP screen mirror: `8082`.

Catatan:

- Discovery tidak mengganti manual address input; keduanya tetap tersedia.
- Discovery tidak melakukan trust otomatis. Pairing token dan Trust Phone tetap wajib.
- Response legacy exact `MOBILEPC_SERVER` disediakan supaya discovery lama tetap terbawa.
- Response JSON Smart MPC tetap dikirim agar Android baru bisa mengisi base URL dan metadata PC.
- Full uji lintas device dilakukan setelah fase ini.
