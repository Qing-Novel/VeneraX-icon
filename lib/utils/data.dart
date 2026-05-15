export 'data_native.dart'
    if (dart.library.html) 'data_web.dart'
    if (dart.library.js_interop) 'data_web.dart';
