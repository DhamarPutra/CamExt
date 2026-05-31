# build.ps1
# Script kompilasi modular aman untuk Windows PowerShell

Write-Host "[*] Memulai pembersihan folder build lama..." -ForegroundColor Cyan
if (Test-Path 'build') {
    Remove-Item 'build' -Recurse -Force
    Write-Host "[+] Folder build lama berhasil dibersihkan." -ForegroundColor Green
}

Write-Host "[*] Mengonfigurasi CMake dengan generator Visual Studio 18 2026..." -ForegroundColor Cyan
cmake -G "Visual Studio 18 2026" -A x64 -B build -S .

if ($LASTEXITCODE -ne 0) {
    Write-Error "[!] Gagal mengonfigurasi CMake!"
    exit 1
}

Write-Host "[*] Melakukan kompilasi Release menggunakan MSVC..." -ForegroundColor Cyan
cmake --build build --config Release

if ($LASTEXITCODE -ne 0) {
    Write-Error "[!] Gagal mem-build proyek C++!"
    exit 1
}

Write-Host "[+] Kompilasi Sukses! Semua target camext.dll & camext_receiver.exe berhasil dibangun." -ForegroundColor Green
