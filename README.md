# Chibi Flashcard Tiếng Anh (Android & iOS)

Ứng dụng học từ vựng tiếng Anh bằng Flashcard phong cách Chibi Anime Nhật Bản (tông màu Xanh Dương iPhone 15 Plus).

---

## 🍎 Hướng dẫn Build iOS trên máy Mac

Khi bạn kéo dự án về máy Mac để build cho iPhone / iPad:

### Bước 1: Tạo thư mục nền tảng `ios/` và tự động áp dụng Logo App trên máy Mac
Mở Terminal tại thư mục dự án trên máy Mac và chạy:
```bash
flutter pub get
flutter create --platforms=ios --org com.chibi.flashcard --project-name chibi_flashcard .
dart run flutter_launcher_icons
```

### Bước 2: Thêm quyền Micro & Nhận diện giọng nói vào `ios/Runner/Info.plist`
Mở file `ios/Runner/Info.plist` và thêm các khóa sau vào bên trong thẻ `<dict>...</dict>` (bắt buộc để tính năng **Thu âm kiểm tra phát âm** hoạt động trên iOS):

```xml
	<key>NSMicrophoneUsageDescription</key>
	<string>Ứng dụng cần quyền Micro để thu âm và kiểm tra phát âm từ vựng tiếng Anh của bạn.</string>
	<key>NSSpeechRecognitionUsageDescription</key>
	<string>Ứng dụng cần quyền Nhận diện giọng nói để đối chiếu phát âm tiếng Anh của bạn.</string>
	<key>NSLocalNetworkUsageDescription</key>
	<string>Ứng dụng cần quyền Mạng cục bộ (LAN) để đồng bộ Flashcard, Ghi chú và tiến độ Ôn tập giữa 2 điện thoại cùng Wi-Fi.</string>
	<key>NSAppTransportSecurity</key>
	<dict>
		<key>NSAllowsLocalNetworking</key>
		<true/>
	</dict>
	<key>UIBackgroundModes</key>
	<array>
		<string>audio</string>
	</array>
```

### Bước 3: Cài đặt CocoaPods và Build iOS
Đảm bảo trong `ios/Podfile` dòng `platform :ios, '13.0'` (hoặc `'14.0'`) đã được mở comment, sau đó chạy:
```bash
cd ios
pod install
cd ..
flutter build ios
# Hoặc chạy trực tiếp lên máy thật / Simulator:
flutter run -d ios
```

---

## 🤖 Hướng dẫn Build Android
```bash
flutter pub get
flutter run
# Hoặc xuất file APK:
flutter build apk --release
```

## 📚 Cập nhật thêm dữ liệu `.apkg` từ thư mục `docs/`
Khi thêm file `.apkg` mới vào thư mục `docs/`, chạy lệnh sau để chương trình tự động nạp cơ sở dữ liệu SQLite vào ứng dụng:
```bash
dart run tool/import_docs_apkg.dart
```
