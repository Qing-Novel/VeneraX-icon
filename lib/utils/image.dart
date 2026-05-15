export 'image_native.dart'
    if (dart.library.html) 'image_web.dart'
    if (dart.library.js_interop) 'image_web.dart';
