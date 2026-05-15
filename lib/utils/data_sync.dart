export 'data_sync_native.dart'
    if (dart.library.html) 'data_sync_web.dart'
    if (dart.library.js_interop) 'data_sync_web.dart';
