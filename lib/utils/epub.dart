export 'epub_native.dart'
    if (dart.library.html) 'epub_web.dart'
    if (dart.library.js_interop) 'epub_web.dart';
