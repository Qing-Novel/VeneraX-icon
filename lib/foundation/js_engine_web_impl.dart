import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:venera/foundation/app.dart';
import 'package:venera/network/app_dio.dart';

const _bridgeFunctionMark = '__venera_fn__';
const _bridgeFunctionRefMark = '__venera_fn_ref__';
const _bridgeBytesMark = '__venera_bytes__';

class JSInvokable {
  JSInvokable(this._functionId);

  final int _functionId;
  bool _released = false;

  int get functionId => _functionId;

  dynamic invoke(List<dynamic> args) => call(args);

  dynamic call(List<dynamic> args) {
    if (_released) {
      throw StateError('JS function $_functionId has been released');
    }
    final encodedArgs = _encodeBridgePayload(args);
    final raw = _callBridgeFunction(_functionId, encodedArgs);
    final decoded = _decodeBridgeResult(raw);
    if (decoded is Future) {
      return decoded.then(_throwIfBridgeError);
    }
    return _throwIfBridgeError(decoded);
  }

  void dup() {}

  void free() => destroy();

  void destroy() {
    if (_released) {
      return;
    }
    _released = true;
    _releaseBridgeFunction(_functionId);
  }
}

mixin JsEngineImpl {
  bool _closed = true;
  Dio? _dio;

  bool get engineClosed => _closed;

  static const _bridgeSetup = r'''
(function() {
  const FN_MARK = '__venera_fn__';
  const FN_REF_MARK = '__venera_fn_ref__';
  const BYTES_MARK = '__venera_bytes__';

  const bridge = {
    nextId: 1,
    functions: new Map(),

    saveFunction(fn) {
      const id = this.nextId++;
      this.functions.set(id, fn);
      return id;
    },

    encode(value) {
      if (value === undefined || value === null) return null;

      if (typeof value === 'function') {
        return { [FN_MARK]: this.saveFunction(value) };
      }

      if (value instanceof Uint8Array) {
        return { [BYTES_MARK]: Array.from(value) };
      }

      if (ArrayBuffer.isView(value)) {
        return {
          [BYTES_MARK]: Array.from(
            new Uint8Array(value.buffer, value.byteOffset, value.byteLength)
          )
        };
      }

      if (value instanceof ArrayBuffer) {
        return { [BYTES_MARK]: Array.from(new Uint8Array(value)) };
      }

      if (Array.isArray(value)) {
        return value.map((v) => this.encode(v));
      }

      if (value instanceof Map) {
        const out = {};
        for (const [key, mapValue] of value.entries()) {
          out[String(key)] = this.encode(mapValue);
        }
        return out;
      }

      if (typeof value === 'object') {
        const out = {};
        for (const key of Object.keys(value)) {
          out[key] = this.encode(value[key]);
        }
        return out;
      }

      return value;
    },

    decode(value) {
      if (value === undefined || value === null) return null;

      if (Array.isArray(value)) {
        return value.map((v) => this.decode(v));
      }

      if (typeof value === 'object') {
        if (Object.prototype.hasOwnProperty.call(value, FN_REF_MARK)) {
          const id = Number(value[FN_REF_MARK]);
          return this.functions.get(id) || null;
        }
        if (Object.prototype.hasOwnProperty.call(value, BYTES_MARK)) {
          return new Uint8Array(value[BYTES_MARK]);
        }
        const out = {};
        for (const key of Object.keys(value)) {
          out[key] = this.decode(value[key]);
        }
        return out;
      }

      return value;
    },

    decodeArgs(argsJson) {
      try {
        const raw = JSON.parse(argsJson);
        const decoded = this.decode(raw);
        return Array.isArray(decoded) ? decoded : [];
      } catch (_) {
        return [];
      }
    },

    encodeResult(value) {
      return JSON.stringify(this.encode(value));
    },

    encodeError(error) {
      const message = String((error && (error.stack || error.message || error)) || error);
      return this.encodeResult({
        "__veneraBridgeError__": message,
      });
    },

    evalCode(code) {
      try {
        const Convert = globalThis.Convert;
        const Network = globalThis.Network;
        const UI = globalThis.UI;
        const APP = globalThis.APP;
        const fetch = globalThis.__veneraFetch || globalThis.fetch;
        const value = eval(code);
        if (value && typeof value.then === 'function') {
          return Promise.resolve(value)
            .then((v) => this.encodeResult(v))
            .catch((e) => this.encodeError(e));
        }
        return this.encodeResult(value);
      } catch (e) {
        return this.encodeError(e);
      }
    },

    callFunction(id, argsJson) {
      try {
        const fn = this.functions.get(Number(id));
        if (!fn) {
          throw new Error('JS function not found: ' + id);
        }
        const args = this.decodeArgs(argsJson);
        const value = fn(...args);
        if (value && typeof value.then === 'function') {
          return Promise.resolve(value)
            .then((v) => this.encodeResult(v))
            .catch((e) => this.encodeError(e));
        }
        return this.encodeResult(value);
      } catch (e) {
        return this.encodeError(e);
      }
    },

    releaseFunction(id) {
      this.functions.delete(Number(id));
    }
  };

  globalThis.__veneraBridge = bridge;

  function sendMessage(msg) {
    const dartSendMessage = globalThis._dartSendMessage;
    if (!dartSendMessage) return null;
    const payload = JSON.stringify(bridge.encode(msg));
    const result = dartSendMessage(payload);

    if (result && typeof result.then === 'function') {
      return result.then((res) => {
        if (typeof res !== 'string' || res.length === 0) return null;
        return bridge.decode(JSON.parse(res));
      });
    }

    if (typeof result !== 'string' || result.length === 0) return null;
    return bridge.decode(JSON.parse(result));
  }

  globalThis.sendMessage = sendMessage;
  if (!globalThis.__veneraUnhandledRejectionHandlerInstalled &&
      typeof globalThis.addEventListener === 'function') {
    globalThis.__veneraUnhandledRejectionHandlerInstalled = true;
    globalThis.addEventListener('unhandledrejection', function(event) {
      const reason = event && event.reason;
      const message = String((reason && (reason.stack || reason.message || reason)) || reason);
      try {
        if (message && message !== 'Invalid Data') {
          sendMessage({
            method: 'log',
            level: 'warning',
            title: 'ComicSource',
            content: 'Unhandled source promise rejection: ' + message,
          });
        }
      } catch (_) {}
      if (event && typeof event.preventDefault === 'function') {
        event.preventDefault();
      }
    });
  }
  globalThis.__veneraAwaitPromise = function(promise, onSuccess, onError) {
    Promise.resolve(promise).then(onSuccess).catch(onError);
  };
})();
''';

  // Browser eval() treats class declarations as block-scoped (like let/const),
  // so they don't appear on globalThis. We append code to init.js that
  // explicitly exports all needed globals, executed in the same eval() call.
  static const _globalExportSuffix = '''

;(function() {
  var _names = [
    'ComicSource','Comic','ComicDetails','Comment','ImageLoadingConfig',
    'Image','HtmlDocument','HtmlElement','HtmlNode','Cookie','_Timer',
    'createUuid','randomInt','randomDouble','setInterval','setTimeout',
    'Convert','Network','UI','APP','log','setClipboard','getClipboard',
    'compute','sendMessage',
  ];
  for (var _i = 0; _i < _names.length; _i++) {
    try { globalThis[_names[_i]] = eval(_names[_i]); } catch(_e) {}
  }
  try { globalThis.__veneraFetch = eval('fetch'); } catch(_e) {}
})();
''';

  Future<void> initEngine(
    String jsInit,
    Object? Function(dynamic) messageReceiver,
  ) async {
    _closed = false;
    _evalJs(_bridgeSetup);
    _installCallback(messageReceiver);
    _evalJs(
      'globalThis.__savedSetTimeout = globalThis.setTimeout;'
      'globalThis.__savedConsole = globalThis.console;'
      'globalThis.__savedFetch = globalThis.fetch;',
    );
    _evalJs('globalThis.appVersion = ${jsonEncode(App.version)};');
    // Execute init.js + global export in a single eval so class declarations
    // are visible to the export IIFE at the end.
    _evalJs(jsInit + _globalExportSuffix);
    _evalJs(
      'globalThis.setTimeout = globalThis.__savedSetTimeout;'
      'globalThis.console = globalThis.__savedConsole;'
      'globalThis.fetch = globalThis.__savedFetch;',
    );
  }

  void _installCallback(Object? Function(dynamic) receiver) {
    final wrapper = ((JSAny? msg) {
      try {
        final dynamic dartMsg = _decodeBridgePayloadFromJs(msg);
        final result = receiver(dartMsg);
        if (result is Future) {
          return _futureStringToPromise(
            result.then((value) => _encodeBridgePayload(value)),
          );
        }
        return _encodeBridgePayload(result).toJS;
      } catch (_) {
        return ''.toJS;
      }
    }).toJS;
    globalContext['_dartSendMessage'] = wrapper;
  }

  dynamic runCode(String js, [String? name]) {
    final raw = _evalJs('__veneraBridge.evalCode(${jsonEncode(js)})');
    final decoded = _decodeBridgeResult(raw);
    if (decoded is Future) {
      return decoded.then(_throwIfBridgeError);
    }
    return _throwIfBridgeError(decoded);
  }

  void dispose() {
    _closed = true;
  }

  String getPlatformName() => 'web';

  Future<dynamic> runInPool(String func, List<dynamic> args) async {
    final encodedArgs = _encodeBridgePayload(args);
    final jsCode =
        '''
(() => {
  const __args = __veneraBridge.decode(${jsonEncode(encodedArgs)});
  return ($func)(...__args);
})()
''';
    final result = runCode(jsCode);
    if (result is Future) {
      return await result;
    }
    return result;
  }

  Future<Dio> buildIoDio() async => _dio ??= Dio();
}

@JS('eval')
external JSAny? _evalJs(String code);

@JS('globalThis')
external JSObject get globalContext;

@JS('globalThis.__veneraAwaitPromise')
external void _awaitPromise(
  JSAny promise,
  JSFunction onSuccess,
  JSFunction onError,
);

JSAny? _callBridgeFunction(int functionId, String encodedArgs) {
  return _evalJs(
    '__veneraBridge.callFunction($functionId, ${jsonEncode(encodedArgs)})',
  );
}

void _releaseBridgeFunction(int functionId) {
  _evalJs('__veneraBridge.releaseFunction($functionId)');
}

dynamic _decodeBridgeResult(JSAny? raw) {
  if (raw == null) {
    return null;
  }
  if (raw.isA<JSPromise>()) {
    return _promiseToFuture(raw).then(_decodeBridgePayloadFromDynamic);
  }
  return _decodeBridgePayloadFromJs(raw);
}

dynamic _throwIfBridgeError(dynamic value) {
  if (value is Map && value['__veneraBridgeError__'] != null) {
    throw StateError(value['__veneraBridgeError__'].toString());
  }
  return value;
}

dynamic _decodeBridgePayloadFromJs(JSAny? value) {
  if (value == null) {
    return null;
  }
  if (value.isA<JSString>()) {
    return _decodeBridgePayload((value as JSString).toDart);
  }
  if (value.isA<JSNumber>()) {
    final n = (value as JSNumber).toDartDouble;
    return n == n.truncateToDouble() ? n.toInt() : n;
  }
  if (value.isA<JSBoolean>()) {
    return (value as JSBoolean).toDart;
  }
  return null;
}

dynamic _decodeBridgePayloadFromDynamic(Object? raw) {
  if (raw == null) {
    return null;
  }
  if (raw is String) {
    return _decodeBridgePayload(raw);
  }
  return raw;
}

dynamic _decodeBridgePayload(String payload) {
  if (payload.isEmpty) {
    return null;
  }
  try {
    final decoded = jsonDecode(payload);
    return _restoreBridgeValue(decoded);
  } catch (_) {
    // Bridge payloads can be plain strings (not JSON-wrapped), in
    // which case we hand back the raw payload. Logging would spam.
    return payload;
  }
}

dynamic _restoreBridgeValue(dynamic value) {
  if (value is List) {
    return value.map(_restoreBridgeValue).toList();
  }
  if (value is Map) {
    if (value.length == 1 && value.containsKey(_bridgeFunctionMark)) {
      final id = value[_bridgeFunctionMark];
      if (id is num) {
        return JSInvokable(id.toInt());
      }
    }
    if (value.length == 1 && value.containsKey(_bridgeBytesMark)) {
      final bytes = value[_bridgeBytesMark];
      if (bytes is List) {
        return Uint8List.fromList(
          bytes
              .map((e) => e is num ? e.toInt() : int.parse(e.toString()))
              .toList(),
        );
      }
    }
    final map = <String, dynamic>{};
    for (final entry in value.entries) {
      map[entry.key.toString()] = _restoreBridgeValue(entry.value);
    }
    return map;
  }
  return value;
}

String _encodeBridgePayload(dynamic value) {
  return jsonEncode(_prepareBridgeValue(value));
}

dynamic _prepareBridgeValue(dynamic value) {
  if (value == null || value is bool || value is num || value is String) {
    return value;
  }

  if (value is Uint8List) {
    return <String, dynamic>{_bridgeBytesMark: value.toList()};
  }

  if (value is JSInvokable) {
    return <String, dynamic>{_bridgeFunctionRefMark: value.functionId};
  }

  if (value is List) {
    return value.map(_prepareBridgeValue).toList();
  }

  if (value is Map) {
    final map = <String, dynamic>{};
    value.forEach((k, v) {
      map[k.toString()] = _prepareBridgeValue(v);
    });
    return map;
  }

  if (value is DateTime) {
    return value.toIso8601String();
  }

  return value.toString();
}

JSPromise _futureStringToPromise(Future<String> future) {
  return JSPromise(
    (JSFunction resolve, JSFunction reject) {
      future.then(
        (v) {
          resolve.callAsFunction(null, v.toJS);
        },
        onError: (e, s) {
          reject.callAsFunction(null, e.toString().toJS);
        },
      );
    }.toJS,
  );
}

Future<Object?> _promiseToFuture(JSAny promiseAny) {
  final completer = Completer<Object?>();
  _awaitPromise(
    promiseAny,
    ((JSAny? value) {
      if (!completer.isCompleted) {
        completer.complete(_jsAnyToDynamic(value));
      }
      return;
    }).toJS,
    ((JSAny? error) {
      if (!completer.isCompleted) {
        completer.completeError(_jsAnyToDynamic(error) ?? 'Promise rejected');
      }
      return;
    }).toJS,
  );
  return completer.future;
}

Object? _jsAnyToDynamic(JSAny? value) {
  if (value == null) {
    return null;
  }
  if (value.isA<JSString>()) {
    return (value as JSString).toDart;
  }
  if (value.isA<JSNumber>()) {
    final n = (value as JSNumber).toDartDouble;
    return n == n.truncateToDouble() ? n.toInt() : n;
  }
  if (value.isA<JSBoolean>()) {
    return (value as JSBoolean).toDart;
  }
  return null;
}

class JSAutoFreeFunction {
  final JSInvokable func;

  JSAutoFreeFunction(this.func) {
    func.dup();
    finalizer.attach(this, func);
  }

  dynamic call(List<dynamic> args) => func(args);

  static final finalizer = Finalizer<JSInvokable>((func) {
    func.destroy();
  });
}
