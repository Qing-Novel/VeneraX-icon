export 'download_native.dart'
    if (dart.library.html) 'download_web.dart'
    if (dart.library.js_interop) 'download_web.dart';
