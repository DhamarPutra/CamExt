# 🎥 CamExt: Ultra-Low Latency Mobile to PC Virtual Camera Solution

[![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![C++](https://img.shields.io/badge/C++-00599C?style=for-the-badge&logo=c%2B%2B&logoColor=white)](https://isocpp.org)
[![CMake](https://img.shields.io/badge/CMake-064F8C?style=for-the-badge&logo=cmake&logoColor=white)](https://cmake.org)
[![OBS Studio](https://img.shields.io/badge/OBS_Studio-302E31?style=for-the-badge&logo=obs-studio&logoColor=white)](https://obsproject.com)

**CamExt** adalah solusi kamera virtual *mobile-to-PC* berspesifikasi tinggi, berlatensi ultra-rendah, dan sangat ringan yang dirancang khusus untuk **OBS Studio**. Proyek ini merupakan alternatif DroidCam / Iriun Webcam berkinerja tinggi, yang memanfaatkan dekoder perangkat keras GPU Windows native (**WIC - Windows Imaging Component**) dan konversi piksel native Android untuk streaming video tanpa lag.

---

## 🌟 Fitur Utama

- **⚡ Latensi Ultra-Rendah (< 50ms):** Penggunaan soket raw TCP/UDP asinkron yang dikombinasikan dengan optimasi `TCP_NODELAY` untuk pengiriman frame instan.
- **🖼️ Akselerasi Dekode Perangkat Keras GPU:** Menggunakan **Windows Imaging Component (WIC)** pada visualizer PC untuk mendekode frame JPEG secara langsung di GPU tanpa membebani CPU.
- **🚀 Konverter YUV-ke-JPEG Native Android:** Memproses frame mentah kamera langsung pada tingkat native C++/Kotlin menggunakan `android.graphics.YuvImage` guna memotong bottleneck komunikasi Flutter Platform Channel.
- **📐 Rasio Aspek Cerdas (Flicker-Free):** Render layar visualizer PC pintar yang mengadopsi teknik *Pillarbox/Letterbox* otomatis. Tidak meregangkan gambar (*anti-stretching*) dan bebas kedipan (*flicker-free*).
- **📱 Pilihan Resolusi Fleksibel:** Pengaturan resolusi langsung dari antarmuka HP (**1080p HQ**, **720p Balanced**, **480p Smooth/60FPS**).
- **🔌 Koneksi Kabel USB (ADB Reverse):** Dukungan penuh untuk streaming via USB Debugging yang stabil dengan kestabilan mutlak tanpa gangguan interferensi sinyal Wi-Fi.

---

## 🏗️ Arsitektur Proyek

Proyek ini terbagi menjadi dua bagian utama:

### 1. Klien Seluler (Flutter & Kotlin Native) - `/mobile`
Klien Android dibangun menggunakan **Clean Architecture** (Domain, Data, dan Presentation layers) untuk kestabilan kode:
- **Presentation Layer:** ValueNotifier untuk manajemen status UI reaktif rendah konsumsi memori, serta dashboard visual bertema gelap (*dark mode*) neon futuristik premium.
- **Data Layer (Kotlin Native):** Pipeline penangkapan frame kamera mengabaikan pengiriman raw data ke Dart. Konversi dari YUV_420_888 ke JPEG beresolusi tinggi langsung dikerjakan oleh native thread Android dengan akselerasi GPU, kemudian dibungkus header biner 20-byte Big-Endian sebelum dilempar ke socket.

### 2. Penerima PC & Plugin OBS Studio (C++ & Win32) - `/obs`
- **Standalone Visualizer (`camext_receiver.exe`):** Jendela preview super cepat Win32 API murni dengan akselerasi rendering GDI + WIC.
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
- [camext.dll] (file:obs/build/Release/camext.dll)
- [camext_receiver.exe] (file:obs/build/Release/camext_receiver.exe)

### C. Kompilasi Aplikasi HP (Flutter)
Jalankan perintah berikut di direktori `/mobile` untuk mem-build APK rilis:
```bash
flutter build apk --release --target-platform android-arm64
```
File APK akan terbentuk di `mobile/build/app/outputs/flutter-apk/app-release.apk`.

---

## 🔌 Cara Penggunaan via Kabel USB (Latensi Terendah)

1. Hubungkan HP Android ke PC via Kabel USB, pastikan **USB Debugging** aktif.
2. Jalankan perintah reverse forwarding pada terminal PC:
   ```bash
   adb reverse tcp:4455 tcp:4455
   ```
3. Jalankan `camext_receiver.exe` di PC.
4. Buka aplikasi **CamExt** di HP, masukkan IP Address `127.0.0.1`, pilih resolusi kamera yang diinginkan (misal: **720p** atau **480p** untuk 60 FPS), lalu klik **MULAI STREAMING**.

---

## 🤝 Mari Berkolaborasi! (Open Collaboration)

Proyek **CamExt** sepenuhnya merupakan proyek sumber terbuka (*open source*) yang menyambut hangat para kontributor untuk bergabung guna meningkatkan fitur, kestabilan, dan skalabilitas!

### Area Kontribusi yang Sangat Dinantikan:
- **🍏 Klien iOS (Swift):** Porting tangkapan kamera native AVFoundation dan konverter biner JPEG/H.264 ke soket untuk mendukung perangkat Apple iPhone.
- **⚡ Hardware Encoding H.264/H.265 (Android & iOS):** Mengganti kompresi MJPEG dengan raw NAL units streaming menggunakan hardware encoder MediaCodec (Android) dan VideoToolbox (iOS) untuk pemangkasan *bandwidth* jaringan lebih jauh lagi.
- **🖥️ Multiplatform Receiver:** Dukungan visualizer standalone untuk sistem operasi Linux dan macOS menggunakan OpenGL / Metal API.
- **🎨 Peningkatan UI/UX:** Desain transisi, kontrol pengaturan kamera yang lebih dalam (ISO, white balance, fokus manual), dan visualisasi statistik jaringan yang interaktif di dashboard seluler.

### Cara Berkontribusi:
1. **Fork** repositori ini.
2. Buat branch fitur Anda: `git checkout -b fitur/fitur-keren-anda`.
3. Komit perubahan Anda: `git commit -m 'Menambahkan fitur keren'`.
4. Push ke branch: `git push origin fitur/fitur-keren-anda`.
5. Buka **Pull Request** baru!

---

## 📄 Lisensi
Proyek ini dilisensikan di bawah **MIT License** - lihat file LICENSE untuk detailnya.

---
*Dibuat dengan 💻, ☕, dan semangat performa tinggi oleh DhamarPutra & Kontributor Open Source.*
