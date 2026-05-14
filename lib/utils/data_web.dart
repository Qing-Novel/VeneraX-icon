import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';

import 'io.dart';

Future<File> exportAppData([bool sync = true]) async {
  final file = File(
    FilePath.join(
      App.cachePath,
      '${DateTime.now().millisecondsSinceEpoch}.venera',
    ),
  );
  final data = jsonDecode(jsonEncode(appdata.toJson())) as Map<String, dynamic>;
  if (sync) {
    final settings = data['settings'];
    if (settings is Map) {
      final disabledFields = appdata.splitField(
        appdata.settings['disableSyncFields'] as String,
      );
      for (final field in disabledFields) {
        settings.remove(field);
      }
    }
  }
  final bytes = utf8.encode(jsonEncode(data));
  final archive = Archive()
    ..addFile(ArchiveFile('appdata.json', bytes.length, bytes));
  await file.writeAsBytes(ZipEncoder().encode(archive));
  return file;
}

Future<void> importAppData(File file, [bool checkVersion = false]) async {
  final archive = ZipDecoder().decodeBytes(
    await file.readAsBytes(),
    verify: true,
  );
  final appdataEntry = archive.findFile('appdata.json');
  if (appdataEntry == null) {
    throw const FormatException('Missing appdata.json in backup');
  }
  final bytes = appdataEntry.readBytes();
  if (bytes == null) {
    throw const FormatException('Invalid appdata.json in backup');
  }
  final data = jsonDecode(utf8.decode(bytes));
  if (data is! Map) {
    throw const FormatException('Invalid appdata.json in backup');
  }
  final appDataJson = Map<String, dynamic>.from(data);
  if (checkVersion) {
    final settings = appDataJson['settings'];
    final version = settings is Map ? settings['dataVersion'] : null;
    final currentVersion = appdata.settings['dataVersion'];
    if (version is int &&
        currentVersion is num &&
        version <= currentVersion.toInt()) {
      return;
    }
  }
  appdata.syncData(appDataJson);
}

Future<void> importPicaData(File file) async {
  throw UnsupportedError('Pica data import is not supported on web.');
}
