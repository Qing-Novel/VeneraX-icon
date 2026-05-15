import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:venera/foundation/js_engine.dart' as source_js;

class Image {
  final Uint32List _data;
  final int width;
  final int height;

  Image(this._data, this.width, this.height) {
    if (_data.length != width * height) {
      throw ArgumentError(
        'Invalid argument: data length must be equal to width * height.',
      );
    }
  }

  Image.empty(this.width, this.height) : _data = Uint32List(width * height);

  static Future<Image> decodeImage(Uint8List data) async {
    final codec = await ui.instantiateImageCodec(data);
    final frame = await codec.getNextFrame();
    codec.dispose();
    final bytes = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    if (bytes == null) {
      throw Exception('Failed to decode image');
    }
    final image = Image(
      Uint32List.fromList(bytes.buffer.asUint32List()),
      frame.image.width,
      frame.image.height,
    );
    frame.image.dispose();
    return image;
  }

  Color getPixelAtIndex(int index) {
    if (index < 0 || index >= _data.length) {
      throw ArgumentError(
        'Invalid argument: index must be in the range of [0, ${_data.length}).',
      );
    }
    return Color.fromValue(_data[index]);
  }

  Image copyRange(int x, int y, int width, int height) {
    _checkRange(x, y, width, height, this.width, this.height);
    final data = Uint32List(width * height);
    for (var j = 0; j < height; j++) {
      for (var i = 0; i < width; i++) {
        data[j * width + i] = _data[(j + y) * this.width + i + x];
      }
    }
    return Image(data, width, height);
  }

  void fillImageAt(int x, int y, Image image) {
    fillImageRangeAt(x, y, image, 0, 0, image.width, image.height);
  }

  void fillImageRangeAt(
    int x,
    int y,
    Image image,
    int srcX,
    int srcY,
    int width,
    int height,
  ) {
    _checkRange(x, y, width, height, this.width, this.height);
    _checkRange(srcX, srcY, width, height, image.width, image.height);
    for (var j = 0; j < height; j++) {
      for (var i = 0; i < width; i++) {
        _data[(j + y) * this.width + i + x] =
            image._data[(j + srcY) * image.width + i + srcX];
      }
    }
  }

  Image copyAndRotate90() {
    final data = Uint32List(width * height);
    for (var j = 0; j < height; j++) {
      for (var i = 0; i < width; i++) {
        data[i * height + height - j - 1] = _data[j * width + i];
      }
    }
    return Image(data, height, width);
  }

  Color getPixel(int x, int y) {
    _checkRange(x, y, 1, 1, width, height);
    return Color.fromValue(_data[y * width + x]);
  }

  void setPixel(int x, int y, Color color) {
    _checkRange(x, y, 1, 1, width, height);
    _data[y * width + x] = color.value;
  }

  Future<Uint8List> encodePng() async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(
      _data.buffer.asUint8List(),
    );
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    final bytes = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    if (bytes == null) {
      throw Exception('Failed to encode image');
    }
    return bytes.buffer.asUint8List();
  }

  static void _checkRange(
    int x,
    int y,
    int width,
    int height,
    int imageWidth,
    int imageHeight,
  ) {
    if (x < 0 || y < 0 || width < 0 || height < 0) {
      throw ArgumentError('Invalid argument: range values must be positive.');
    }
    if (x + width > imageWidth) {
      throw ArgumentError(
        'Invalid argument: x + width must be less than or equal to image width.',
      );
    }
    if (y + height > imageHeight) {
      throw ArgumentError(
        'Invalid argument: y + height must be less than or equal to image height.',
      );
    }
  }
}

class Color {
  final int value;

  Color(int r, int g, int b, [int a = 255])
    : value = (a << 24) | (b << 16) | (g << 8) | r;

  Color.fromValue(this.value);

  int get r => value & 0xFF;
  int get g => (value >> 8) & 0xFF;
  int get b => (value >> 16) & 0xFF;
  int get a => (value >> 24) & 0xFF;
}

final _images = <int, Image>{};
var _nextImageKey = 0;
var _runningImageScripts = 0;

Object? handleImageMessage(dynamic message) {
  if (message is! Map) return null;
  if (message['method'] != 'image') return null;
  switch (message['function']) {
    case 'copyRange':
      final image = _images[message['key']];
      if (image == null) return null;
      return _setImage(
        image.copyRange(
          message['x'],
          message['y'],
          message['width'],
          message['height'],
        ),
      );
    case 'copyAndRotate90':
      final image = _images[message['key']];
      if (image == null) return null;
      return _setImage(image.copyAndRotate90());
    case 'fillImageAt':
      final image = _images[message['key']];
      final image2 = _images[message['image']];
      if (image == null || image2 == null) return null;
      image.fillImageAt(message['x'], message['y'], image2);
      return null;
    case 'fillImageRangeAt':
      final image = _images[message['key']];
      final image2 = _images[message['image']];
      if (image == null || image2 == null) return null;
      image.fillImageRangeAt(
        message['x'],
        message['y'],
        image2,
        message['srcX'],
        message['srcY'],
        message['width'],
        message['height'],
      );
      return null;
    case 'getWidth':
      return _images[message['key']]?.width;
    case 'getHeight':
      return _images[message['key']]?.height;
    case 'emptyImage':
      return _setImage(Image.empty(message['width'], message['height']));
  }
  return null;
}

int _setImage(Image image) {
  final key = _nextImageKey++;
  _images[key] = image;
  return key;
}

@visibleForTesting
String buildModifyImageScript(String script, int key) {
  return '''
$script
;(() => {
  const image = new Image($key);
  const result = modifyImage(image);
  return result && result.key;
})()
''';
}

Future<Uint8List> modifyImageWithScript(Uint8List data, String script) async {
  while (_runningImageScripts > 0) {
    await Future.delayed(const Duration(milliseconds: 50));
  }
  _runningImageScripts++;
  final image = await Image.decodeImage(data);
  final key = _setImage(image);
  int? resultKey;
  try {
    final result = source_js.JsEngine().runCode(
      buildModifyImageScript(script, key),
      '<modify-image>',
    );
    resultKey = result is num ? result.toInt() : null;
    final newImage = _images[resultKey];
    if (newImage == null) {
      throw StateError('modifyImage did not return an Image');
    }
    return await newImage.encodePng();
  } finally {
    _images.remove(key);
    if (resultKey != null) _images.remove(resultKey);
    _runningImageScripts--;
  }
}
