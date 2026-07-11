import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards against reintroducing native-FFI APIs with known memory-safety
/// defects. Each entry documents the defect so a failure explains itself.
void main() {
  test('lib/ does not use known-unsafe native APIs', () {
    final forbidden = <RegExp, String>{
      // zip_flutter: openAndExtract registers its arg pointer with a GC
      // finalizer AND frees it manually — the finalizer then frees it a
      // second time and libmalloc aborts the process. This was the root
      // cause of the sync-import startup crash loop. openAndExtractAsync
      // is a separate, safe implementation and stays allowed.
      RegExp(r'\bopenAndExtract\('):
          'use extractZip() from utils/archive.dart instead of '
          'ZipFile.openAndExtract (double-free, aborts the process)',
      // lodepng_flutter: the convenience wrappers free the native buffer and
      // then return a typed-data view over the freed memory.
      RegExp(r'lodepng\.(decodePng|encodePng)\('):
          'use decodePngToPointer/encodePngToPointer with '
          'ByteBuffer.finalizer instead (wrappers return a view over '
          'freed memory)',
    };

    final violations = <String>[];
    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final entry in forbidden.entries) {
          if (entry.key.hasMatch(lines[i])) {
            violations.add(
              '${file.path}:${i + 1}: ${lines[i].trim()}\n'
              '  -> ${entry.value}',
            );
          }
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
