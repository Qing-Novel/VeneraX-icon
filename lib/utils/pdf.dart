export 'pdf_native.dart'
    if (dart.library.html) 'pdf_web.dart'
    if (dart.library.js_interop) 'pdf_web.dart';
