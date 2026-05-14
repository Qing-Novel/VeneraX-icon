// Web stubs for dart:io-dependent IO utilities.
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;
import 'dart:js_interop';
import 'dart:typed_data';

import 'io_compat_web.dart' as webfs;

export 'dart:typed_data';
export 'io_compat_web.dart' show File, Directory, FileStat, IOSink, exit;

int get pid => 0;

class IO {
  static bool _isSelectingFiles = false;

  static bool get isSelectingFiles => _isSelectingFiles;
}

class FilePath {
  const FilePath._();

  static String join(
    String path1,
    String path2, [
    String? path3,
    String? path4,
    String? path5,
  ]) {
    final parts = [
      path1,
      path2,
      path3,
      path4,
      path5,
    ].whereType<String>().where((s) => s.isNotEmpty);
    return parts.join('/');
  }
}

String sanitizeFileName(String fileName, {String? dir, int? maxLength}) {
  while (fileName.endsWith('.')) {
    fileName = fileName.substring(0, fileName.length - 1);
  }
  final invalidChars = RegExp(r'[<>:"/\\|?*]');
  var result = fileName.replaceAll(invalidChars, ' ').trim();
  if (result.isEmpty) throw Exception('Invalid File Name: Empty length.');
  final limit = maxLength ?? 255;
  if (result.length > limit) result = result.substring(0, limit);
  return result;
}

String bytesToReadableString(int bytes) {
  if (bytes < 1024) return "$bytes B";
  if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(2)} KB";
  if (bytes < 1024 * 1024 * 1024) {
    return "${(bytes / 1024 / 1024).toStringAsFixed(2)} MB";
  }
  return "${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB";
}

class FileSelectResult {
  final String path;
  final Uint8List _bytes;
  final String? _name;

  FileSelectResult(this.path, [Uint8List? bytes, String? name])
    : _bytes = bytes ?? Uint8List(0),
      _name = name;

  Future<void> saveTo(String dest) async {
    await webfs.File(dest).writeAsBytes(_bytes);
  }

  Future<Uint8List> readAsBytes() async => Uint8List.fromList(_bytes);

  String get name => _name ?? path.split('/').last;
}

Future<FileSelectResult?> selectFile({required List<String> ext}) async {
  final completer = Completer<FileSelectResult?>();
  final input = html.FileUploadInputElement();
  input.accept = ext.map((e) => e.startsWith('.') ? e : '.$e').join(',');
  input.style.display = 'none';

  void complete(FileSelectResult? result) {
    if (completer.isCompleted) return;
    IO._isSelectingFiles = false;
    input.remove();
    completer.complete(result);
  }

  IO._isSelectingFiles = true;
  html.document.body?.append(input);
  input.onChange.first.then((_) async {
    final file = input.files?.isNotEmpty == true ? input.files!.first : null;
    if (file == null) {
      complete(null);
      return;
    }
    try {
      final bytes = await _readBrowserFile(file);
      complete(FileSelectResult('/selected/${file.name}', bytes, file.name));
    } catch (_) {
      complete(null);
    }
  });
  input.addEventListener('cancel', (_) => complete(null));
  input.click();
  return completer.future;
}
Future<String?> selectDirectory() async => null;
Future<String?> selectDirectoryIOS() async => null;
Future<void> saveFile({
  Uint8List? data,
  required String filename,
  dynamic file,
}) async {
  if (data == null && file != null) {
    data = Uint8List.fromList(await file.readAsBytes());
  }
  if (data == null) return;
  _webDownloadBytes(data, sanitizeFileName(filename));
}

Future<Uint8List> _readBrowserFile(html.File file) async {
  final reader = html.FileReader();
  final completer = Completer<Uint8List>();
  reader.onLoad.first.then((_) {
    final result = reader.result;
    if (result is ByteBuffer) {
      completer.complete(Uint8List.view(result));
    } else if (result is Uint8List) {
      completer.complete(Uint8List.fromList(result));
    } else {
      completer.complete(Uint8List(0));
    }
  });
  reader.onError.first.then((_) {
    if (!completer.isCompleted) {
      completer.completeError(reader.error ?? StateError('File read failed'));
    }
  });
  reader.readAsArrayBuffer(file);
  return completer.future;
}

@JS('eval')
external JSFunction _jsEval(String code);

void _webDownloadBytes(Uint8List data, String filename) {
  final downloadFn = _jsEval('''(function(bytes, name) {
      var blob = new Blob([bytes], {type: 'application/octet-stream'});
      var url = URL.createObjectURL(blob);
      var a = document.createElement('a');
      a.href = url;
      a.download = name;
      a.style.display = 'none';
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
    })''');
  downloadFn.callAsFunction(null, data.toJS, filename.toJS);
}

class Share {
  static void shareFile({
    required Uint8List data,
    required String filename,
    required String mime,
  }) {}
  static void shareText(String text) {}
}

class DirectoryPicker {
  DirectoryPicker();
  Future<dynamic> pickDirectory({bool directAccess = false}) async => null;
}

class IOSDirectoryPicker {
  static Future<String?> selectDirectory() async => null;
}

Future<void> copyDirectory(dynamic source, dynamic destination) async {}
Future<void> copyDirectoryIsolate(dynamic source, dynamic destination) async {}

String findValidDirectoryName(String path, String directory) {
  return sanitizeFileName(directory);
}

dynamic overrideIO<T>(T Function() f) => f();

class Platform {
  static String get resolvedExecutable => '';
  static bool get isWindows => false;
  static bool get isMacOS => false;
  static bool get isLinux => false;
  static bool get isAndroid => false;
  static bool get isIOS => false;
  static bool get isFuchsia => false;
  static String get operatingSystem => 'web';
  static String get pathSeparator => '/';
  static Map<String, String> get environment => const {};
}

enum ProcessStartMode { normal, detached, detachedWithStdio, inheritStdio }

class ProcessResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  const ProcessResult(this.exitCode, this.stdout, this.stderr);
}

class Process {
  static Future<Process> start(
    String executable,
    List<String> arguments, {
    ProcessStartMode mode = ProcessStartMode.normal,
    Map<String, String>? environment,
    String? workingDirectory,
    bool runInShell = false,
  }) async => Process._();

  static Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    String? workingDirectory,
    bool runInShell = false,
  }) async => const ProcessResult(0, '', '');

  Process._();
}
