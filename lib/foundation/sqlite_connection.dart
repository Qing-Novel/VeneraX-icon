export 'sqlite_connection_native.dart'
    if (dart.library.html) 'sqlite_connection_web.dart'
    if (dart.library.js_interop) 'sqlite_connection_web.dart';
