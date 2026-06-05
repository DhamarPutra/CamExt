cd obs
powershell -ExecutionPolicy Bypass -File build.ps1
cd ../mobile
flutter build apk --release --target-platform android-arm64