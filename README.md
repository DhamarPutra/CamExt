# 🎥 CamExt: Ultra-Low Latency Mobile to PC Virtual Camera Solution

[![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![C++](https://img.shields.io/badge/C++-00599C?style=for-the-badge&logo=c%2B%2B&logoColor=white)](https://isocpp.org)
[![CMake](https://img.shields.io/badge/CMake-064F8C?style=for-the-badge&logo=cmake&logoColor=white)](https://cmake.org)
[![OBS Studio](https://img.shields.io/badge/OBS_Studio-302E31?style=for-the-badge&logo=obs-studio&logoColor=white)](https://obsproject.com)

**CamExt** adalah solusi kamera virtual *mobile-to-PC* berspesifikasi tinggi, berlatensi ultra-rendah, dan sangat ringan yang dirancang khusus untuk **OBS Studio**. Proyek ini merupakan alternatif DroidCam / Iriun Webcam berkinerja tinggi, yang memanfaatkan dekoder perangkat keras GPU Windows native (**WIC - Windows Imaging Component**) dan kompresi perangkat keras kamera Android untuk streaming video tanpa lag.

---

## 🌟 Fitur Utama (v1.0.3)

- **⚡ Latensi Ultra-Rendah (< 50ms):** Penggunaan soket raw TCP asinkron yang dikombinasikan dengan optimasi `TCP_NODELAY` untuk pengiriman frame instan.
- **📸 Akselerasi Hardware Encoder AVC/H.264 & HEVC/H.265:** Menggunakan kompresi perangkat keras bawaan perangkat Android (MediaCodec) untuk kompresi video H.264/H.265 berkinerja tinggi, menjaga FPS tetap stabil di **60 FPS** dengan penggunaan CPU minimum.
- **🛡️ Dynamic Hardware Capability Check (Baru):** Otomatis mendeteksi batas kemampuan hardware encoder bawaan HP untuk resolusi yang dipilih (misal 1080p, 2K, 4K) dan melakukan fallback otomatis ke MJPEG dengan mulus jika tidak didukung.
- **🔄 Auto Rotation & Stride-Aware (Baru):** Visualizer PC melakukan rotasi otomatis 90° CW untuk mode H.264 (sehingga orientasi sesuai) serta menangani dynamic stride padding memori dari GPU (flicker-free & crash-free).
- **🔇 Integrasi Audio Mikrofon Real-time:** Mendukung perekaman audio PCM 16-bit 48kHz Mono langsung dari mikrofon HP dan diputar secara real-time di PC menggunakan Windows native **waveOut API**.
- **🔌 Deteksi Koneksi Cerdas & Full TCP:** Otomatis mendeteksi tipe koneksi (**🔌 USB ADB Mode** jika IP `127.0.0.1`, atau **📶 Wireless Mode** jika IP Wi-Fi PC dimasukkan). Protokol koneksi sepenuhnya menggunakan TCP yang stabil.
- **📐 Rasio Aspek Cerdas:** Render layar visualizer PC pintar yang mengadopsi teknik *Pillarbox/Letterbox* otomatis. Tidak meregangkan gambar (*anti-stretching*).
- **📱 Pilihan Resolusi Dinamis:** Mendeteksi daftar resolusi kamera yang didukung secara dinamis dari perangkat keras HP (360p, 480p, 720p, 1080p, 2K, 4K).
- **⚙️ Optimalisasi ISP Kamera:** Mematikan pemrosesan pasca-gambar yang berat (Noise Reduction, Edge Enhancement, Color Aberration Correction, Hot Pixel Correction) untuk performa maksimum dan latensi zero-delay.

---

## 🏗️ Arsitektur Proyek

Proyek ini terbagi menjadi dua bagian utama:

### 1. Klien Seluler (Flutter & Kotlin Native) - `/mobile`
Klien Android dibangun menggunakan **Clean Architecture** (Domain, Data, dan Presentation layers) untuk kestabilan kode:
- **Presentation Layer:** ValueNotifier untuk manajemen status UI reaktif rendah konsumsi memori, serta dashboard visual bertema gelap (*dark mode*) neon futuristik premium.
- **Data Layer (Kotlin Native):** Pipeline penangkapan frame kamera mengabaikan pengiriman raw data ke Dart. Kamera dikonfigurasi untuk mengeluarkan data JPEG terkompresi perangkat keras, lalu dibungkus header biner 20-byte Big-Endian sebelum dikirim melalui socket TCP.

### 2. Penerima PC & Plugin OBS Studio (C++ & Win32) - `/obs`
- **Standalone Visualizer (`camext_receiver.exe`):** Jendela preview super cepat Win32 API murni dengan akselerasi rendering GDI + WIC dan pemutaran audio waveOut real-time.
- **Plugin OBS Studio (`camext.dll`):** Plugin native C++ yang mendaftarkan sumber video secara langsung ke libobs pipeline render OBS Studio.

---

## 🚀 Panduan Membangun (Build)

### A. Prasyarat Sistem
- **Windows PC:** Windows 10/11, Visual Studio 2022/2026 dengan C++ desktop workload, CMake (v3.20 atau terbaru).
- **Mobile Perangkat:** Android Studio, Flutter SDK (v3.x).

### B. Kompilasi Visualizer & Plugin PC (C++)
Buka PowerShell di dalam direktori `/obs` dan jalankan skrip kompilasi modular otomatis:
```powershell
powershell -ExecutionPolicy Bypass -File build.ps1
```
Output biner:
- [camext.dll](file:///d:/Project/OBSExtention/CamExt/obs/build/Release/camext.dll)
- [camext_receiver.exe](file:///d:/Project/OBSExtention/CamExt/obs/build/Release/camext_receiver.exe)

### C. Kompilasi Aplikasi HP (Flutter)
Jalankan perintah berikut di direktori `/mobile` untuk mem-build APK rilis:
```bash
flutter build apk --release --target-platform android-arm64
```
File APK akan terbentuk di `mobile/build/app/outputs/flutter-apk/app-release.apk`.

---

## 🔌 Cara Penggunaan

### Opsi A: Menggunakan Kabel USB (Latensi Terendah / Stabil)
1. Hubungkan HP Android ke PC via Kabel USB, pastikan **USB Debugging** di HP Anda telah diaktifkan.
2. Buka Terminal/CMD di PC Anda dan jalankan perintah *port reverse forwarding*:
   ```bash
   adb reverse tcp:4455 tcp:4455
   ```
3. Jalankan **`camext_receiver.exe`** di PC Anda.
4. Buka aplikasi **CamExt** di HP, ketikkan IP Address `127.0.0.1` (aplikasi otomatis mendeteksi sebagai **USB Mode**) dan Port `4455`, nyalakan switch **Streaming Audio** jika diperlukan, lalu ketuk **MULAI STREAMING**.

### Opsi B: Menggunakan Wi-Fi (Nirkabel)
1. Pastikan PC dan HP Android Anda terhubung ke **satu jaringan Wi-Fi / Router yang sama**.
2. Cari tahu IP lokal PC Anda (contoh: jalankan `ipconfig` di CMD Windows, temukan IPv4 Address seperti `192.168.1.5`).
3. Jalankan **`camext_receiver.exe`** di PC Anda.
4. Buka aplikasi **CamExt** di HP, masukkan IP Address PC Anda (misal: `192.168.1.5`, aplikasi otomatis mendeteksi sebagai **Wireless Mode**) dan Port `4455`, lalu ketuk **MULAI STREAMING**.

---

## 📄 Lisensi
Proyek ini dilisensikan di bawah **MIT License** - lihat file LICENSE untuk detailnya.

---
*Dibuat dengan 💻, ☕, dan semangat performa tinggi oleh DhamarPutra & Kontributor Open Source.*
