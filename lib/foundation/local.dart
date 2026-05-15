export 'local_native.dart'
    if (dart.library.html) 'local_web.dart'
    if (dart.library.js_interop) 'local_web.dart';
