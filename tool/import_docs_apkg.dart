import 'dart:io';
import 'package:archive/archive.dart';

/// Chương trình tự động quét toàn bộ file .apkg trong thư mục `docs/`
/// và giải nén cơ sở dữ liệu SQLite (`collection.anki2` / `collection.anki21`)
/// vào `assets/anki_dbs/` để ứng dụng Flutter nạp trực tiếp toàn bộ Topic và Từ vựng.
///
/// Cách chạy bất kỳ lúc nào bạn thêm file .apkg mới vào thư mục `docs/`:
///   dart run tool/import_docs_apkg.dart
void main() {
  final docsDir = Directory('docs');
  if (!docsDir.existsSync()) {
    stdout.writeln('Không tìm thấy thư mục docs/');
    exit(1);
  }

  final outDir = Directory('assets/anki_dbs');
  if (!outDir.existsSync()) {
    outDir.createSync(recursive: true);
  }

  final apkgFiles = docsDir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.apkg'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  stdout.writeln('Tìm thấy ${apkgFiles.length} file .apkg trong thư mục docs/:');

  for (int i = 0; i < apkgFiles.length; i++) {
    final file = apkgFiles[i];
    final bookIndex = i + 1;
    stdout.writeln('[$bookIndex/${apkgFiles.length}] Đang nạp: ${file.path} ...');

    final bytes = file.readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);

    ArchiveFile? dbEntry;
    for (final entry in archive) {
      if (entry.name == 'collection.anki21' || entry.name == 'collection.anki2') {
        dbEntry = entry;
        if (entry.name == 'collection.anki21') break;
      }
    }

    if (dbEntry == null) {
      stdout.writeln('  -> Bỏ qua vì không tìm thấy collection.anki2 trong file.');
      continue;
    }

    final outFile = File('${outDir.path}/book_$bookIndex.sqlite');
    outFile.writeAsBytesSync(dbEntry.content as List<int>, flush: true);
    final sizeKb = (outFile.lengthSync() / 1024).toStringAsFixed(1);
    stdout.writeln('  -> Đã trích xuất SQLite DB: ${outFile.path} ($sizeKb KB)');
  }

  stdout.writeln('Hoàn tất nạp dữ liệu từ thư mục docs/!');
}
