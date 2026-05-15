export 'io_native.dart'
    if (dart.library.html) 'io_web.dart'
    if (dart.library.js_interop) 'io_web.dart';
