export 'platform_abi_native.dart'
    if (dart.library.html) 'platform_abi_web.dart'
    if (dart.library.js_interop) 'platform_abi_web.dart';
