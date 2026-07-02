# Repair Phase 3 - NFC Forensic Port

Status: complete.

Fase ini memperbaiki jalur NFC native agar kembali mengikuti reference NFC, dengan adaptasi minimal untuk nama app dan config Smart MPC.

## Perubahan

- `NfcLaunchActivity` tetap menjadi Activity native terpisah dari Flutter Activity.
- Manifest tetap memakai `NDEF_DISCOVERED` dan `VIEW` intent filter.
- Manifest sekarang menerima dua scheme:
  - `smartmpc://tap`
  - `nfcinstant://tap`
- Flutter deep link handler juga menerima dua scheme tersebut.
- `flutter_deeplinking_enabled` tetap `false`, supaya deep link dikendalikan native seperti reference.
- `NfcLaunchActivity` tetap mulai proses setelah window focus.
- Delay awal tetap `250 ms`.
- Delay selesai dikembalikan ke reference:
  - file upload result: `1800 ms`
  - quick command result: `1400 ms`
  - open main app/request files: `300 ms`
- Native launch screen dikembalikan mendekati reference:
  - background `#0D1117`
  - message awal `Reading context...`
- Native HTTP timeout dikembalikan mendekati reference:
  - upload connect timeout `3000 ms`
  - upload read timeout `30000 ms`
  - clipboard/intent connect timeout `3000 ms`
  - clipboard/intent read timeout `5000 ms`
- File upload NFC kembali menangani kondisi belum trusted sebagai status `Not connected`, bukan generic failure.

## Yang Sengaja Dipertahankan Dari Smart MPC

- Package name Smart MPC.
- MethodChannel Smart MPC.
- SharedPreferences name `smart_mpc`.
- Default deep link internal `smartmpc://tap`.
- Pending deep link fallback melalui SharedPreferences untuk request files.
- MainActivity native bridge lain, termasuk upload manual dan audio receiver, tidak diubah di fase ini.

## Source Of Truth

Detail yang dipakai dari reference NFC:

- native Activity lifecycle;
- `ACTION_OPEN_DOCUMENT`;
- `CATEGORY_OPENABLE`;
- `*/*`;
- multiple file picker;
- `setChunkedStreamingMode(0)`;
- direct stream upload dari `contentResolver`;
- protected headers `X-Device-Id` dan `X-Device-Token`;
- native clipboard pull;
- native command post;
- launch screen timing.

## File

- `android_app/android/app/src/main/AndroidManifest.xml`
- `android_app/android/app/src/main/kotlin/com/smartmpc/app/NfcLaunchActivity.kt`
- `android_app/android/app/src/main/res/values-night/styles.xml`
- `android_app/lib/main.dart`

## Verification

- `flutter analyze`: no issues.
- `:app:compileDebugKotlin`: success.
