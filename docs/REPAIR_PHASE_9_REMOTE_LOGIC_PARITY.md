# Repair Phase 9 - Remote Logic Parity

Status: complete.

Tujuan fase ini adalah mengembalikan perilaku remote control Android agar mengikuti logika project media remote yang sudah terbukti, bukan mengganti dengan implementasi baru.

## Yang Dipulihkan

- Trackpad single-finger move memakai akumulasi delta, throttle 16 ms, dan sensitivity 4.0.
- Single-finger tap mengirim left click dengan ambang jarak dan durasi seperti referensi.
- Two-finger continuous gesture mengirim scroll halus dengan multiplier 0.5.
- Two-finger tap mengirim right click.
- Two-finger horizontal swipe mengirim browser back/browser forward.
- Live typing memakai common-prefix diff:
  - karakter lama yang berubah dikirim sebagai backspace,
  - karakter baru dikirim sebagai `TYPE_TEXT`,
  - perubahan tengah teks tidak lagi diabaikan.
- Voice dictation memakai `speech_to_text` dan mengirim incremental recognized words sebagai `TYPE_TEXT`.
- Lifecycle keyboard mengikuti referensi: ketika keyboard tertutup, input live typing di-clear dan focus dilepas.
- Permission microphone ditambahkan agar voice dictation bisa berjalan di Android.

## File Yang Berubah

- `android_app/lib/main.dart`
- `android_app/pubspec.yaml`
- `android_app/pubspec.lock`
- `android_app/android/app/src/main/AndroidManifest.xml`

## Catatan

- Nilai gesture kecil seperti sensitivity, throttle, threshold tap, dan multiplier scroll dipertahankan karena itu bagian dari rasa trackpad yang sudah diuji.
- API `speech_to_text` memakai `SpeechListenOptions` karena versi package saat ini menandai parameter lama sebagai deprecated, tetapi listen mode tetap `dictation`.
- Fase ini tidak mengubah PC server karena command remote yang dipakai tetap command kontrak lama: `MOUSE_MOVE`, `MOUSE_CLICK`, `SCROLL`, `SPECIAL_KEY`, dan `TYPE_TEXT`.

## Verifikasi

- `flutter pub get`
- `flutter analyze`
- `gradlew :app:compileDebugKotlin`
