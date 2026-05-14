import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/log.dart';

import 'io.dart';

const webPendingDbImportKey = 'webPwaPendingDbImport';
const _webDbEntries = [
  'data/venera.db',
  'history.db',
  'local_favorite.db',
  'cookie.db',
];

typedef WebDbExtractClient =
    Future<Map<String, dynamic>> Function(String dataBase64);

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
  final zipBytes = await file.readAsBytes();
  final archive = ZipDecoder().decodeBytes(zipBytes, verify: true);
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
  final pendingDbImport = await collectWebDbImportStatus(zipBytes, archive);
  appdata.syncData(appDataJson);
  if (pendingDbImport != null) {
    appdata.implicitData[webPendingDbImportKey] = pendingDbImport;
    appdata.writeImplicitData();
    Log.warning(
      'Import Data',
      'Imported appdata.json; sqlite DB entries are pending Web merge: '
          '${(pendingDbImport['entries'] as Map).keys.join(', ')}',
    );
  }
}

Future<void> importPicaData(File file) async {
  throw UnsupportedError('Pica data import is not supported on web.');
}

@visibleForTesting
Future<Map<String, dynamic>> extractWebDbWithHelper(
  String dataBase64, {
  Dio? dio,
}) async {
  final client =
      dio ??
      Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 60),
          sendTimeout: const Duration(seconds: 60),
        ),
      );
  final response = await client.post(
    '/sync/webdav/extract-db',
    data: {'dataBase64': dataBase64},
    options: Options(extra: const {'maskDataInLog': true}),
  );
  final data = response.data;
  if (data is Map) {
    return data.cast<String, dynamic>();
  }
  throw StateError('Unexpected helper response');
}

@visibleForTesting
Future<Map<String, dynamic>?> collectWebDbImportStatus(
  List<int> zipBytes,
  Archive archive, {
  WebDbExtractClient? extractDb,
  DateTime? now,
}) async {
  final presentEntries = _webDbEntries
      .where((entry) => archive.findFile(entry) != null)
      .toList();
  if (presentEntries.isEmpty) {
    return null;
  }

  final status = <String, dynamic>{
    'version': 1,
    'state': 'pending_merge',
    'createdAt': (now ?? DateTime.now()).toIso8601String(),
    'reason': 'Web import restored appdata only; sqlite DB merge is pending.',
    'entries': {
      for (final entry in presentEntries)
        entry: {'present': true, 'extracted': false, 'merged': false},
    },
  };

  try {
    final helperData = await (extractDb ?? extractWebDbWithHelper)(
      base64Encode(zipBytes),
    );
    final databases = helperData['databases'];
    if (databases is! Map) {
      throw StateError('Unexpected extract-db response');
    }
    status['helperOk'] = true;
    status['entries'] = _summarizeExtractedDatabases(presentEntries, databases);
  } catch (e, s) {
    status['helperOk'] = false;
    status['error'] = e.toString();
    Log.warning(
      'Import Data',
      'Failed to extract sqlite data via helper: $e\n$s',
    );
  }

  return status;
}

Map<String, dynamic> _summarizeExtractedDatabases(
  List<String> presentEntries,
  Map<dynamic, dynamic> databases,
) {
  final result = <String, dynamic>{};
  for (final entryName in presentEntries) {
    final rawDatabase = databases[entryName];
    if (rawDatabase is! Map) {
      result[entryName] = {
        'present': true,
        'extracted': false,
        'merged': false,
        'error': 'Missing helper result',
      };
      continue;
    }

    final database = rawDatabase.cast<String, dynamic>();
    final tableSummaries = <Map<String, dynamic>>[];
    var rowCount = 0;
    final tables = database['tables'];
    if (tables is List) {
      for (final rawTable in tables) {
        if (rawTable is! Map) {
          continue;
        }
        final table = rawTable.cast<String, dynamic>();
        final rows = table['rows'];
        final rowsCount = rows is List ? rows.length : 0;
        rowCount += rowsCount;
        tableSummaries.add({
          'name': table['name']?.toString() ?? '',
          'rows': rowsCount,
        });
      }
    }

    result[entryName] = {
      'present': true,
      'extracted': database['ok'] == true,
      'merged': false,
      if (database['error'] != null) 'error': database['error'].toString(),
      'tables': tableSummaries,
      'rowCount': rowCount,
    };
  }
  return result;
}
