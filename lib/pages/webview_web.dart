import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:venera/utils/translations.dart';

export 'package:flutter_inappwebview/flutter_inappwebview.dart'
    show WebUri, URLRequest;

extension WebviewExtension on InAppWebViewController {
  Future<List<dynamic>?> getCookies(String url) async => const [];

  Future<String?> getUA() async => null;
}

class AppWebview extends StatelessWidget {
  const AppWebview({
    super.key,
    required this.initialUrl,
    this.initialHeaders,
    this.onTitleChange,
    this.onNavigation,
    this.onStarted,
    this.onLoadStop,
    this.singlePage = false,
    this.webViewEnvironment,
  });

  final String initialUrl;
  final Map<String, String>? initialHeaders;
  final void Function(String title, dynamic controller)? onTitleChange;
  final bool Function(String url, dynamic controller)? onNavigation;
  final void Function(dynamic controller)? onStarted;
  final void Function(dynamic controller)? onLoadStop;
  final bool singlePage;
  final dynamic webViewEnvironment;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(initialUrl)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.open_in_browser, size: 56),
                const SizedBox(height: 16),
                Text(initialUrl, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => launchUrlString(initialUrl),
                  icon: const Icon(Icons.open_in_new),
                  label: Text('Open in browser'.tl),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DesktopWebview {
  DesktopWebview({
    required this.initialUrl,
    this.onTitleChange,
    this.onNavigation,
    this.onStarted,
    this.onClose,
    this.userDataFolderWindows,
  });

  final String initialUrl;
  final void Function(String title, DesktopWebview controller)? onTitleChange;
  final void Function(String url, DesktopWebview webview)? onNavigation;
  final void Function(DesktopWebview controller)? onStarted;
  final void Function()? onClose;
  final String? userDataFolderWindows;

  String? get userAgent => null;

  static Future<bool> isAvailable() async => false;

  Future<void> open() async {
    await launchUrlString(initialUrl);
    onClose?.call();
  }

  Future<String?> evaluateJavascript(String code) async => null;

  Future<Map<String, String>> getCookies(String url) async => const {};

  void close() => onClose?.call();
}
