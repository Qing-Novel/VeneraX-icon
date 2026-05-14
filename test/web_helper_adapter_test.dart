import 'package:flutter_test/flutter_test.dart';
import 'package:venera/network/cors_proxy.dart';
import 'package:venera/network/web_helper_browser.dart';

void main() {
  test('normalizes same-origin helper proxy endpoint', () {
    expect(
      normalizeCorsProxyEndpoint('https://example.com/app/'),
      'https://example.com/app/proxy',
    );
    expect(
      normalizeCorsProxyEndpoint('https://example.com/proxy'),
      'https://example.com/proxy',
    );
    expect(
      resolveCorsProxyEndpoint(
        useSameOriginDefault: true,
        currentUri: Uri.parse('https://host.test:60098/index.html'),
      ),
      'https://host.test:60098/proxy',
    );
  });

  test('builds proxy and helper route urls', () {
    final endpoint = 'https://host.test:60098/proxy';
    expect(
      buildCorsProxyUrl(endpoint, Uri.parse('https://remote.test/a?b=1')),
      'https://host.test:60098/proxy?url=https%3A%2F%2Fremote.test%2Fa%3Fb%3D1',
    );
    expect(
      buildHelperRouteUrl(endpoint, 'browser/session/abc/state'),
      'https://host.test:60098/browser/session/abc/state',
    );
  });

  test('preserves source headers for helper proxy metadata', () {
    final headers = <String, dynamic>{
      'User-Agent': 'UA',
      'Cookie': 'a=b',
      'Referer': 'https://ref.test',
      'X-Test': '1',
      'Accept-Encoding': 'gzip',
      'Sec-Fetch-Site': 'none',
    };
    preserveCorsProxySourceHeaders(headers);

    expect(headers[corsProxyUserAgentHeader], 'UA');
    expect(headers[corsProxyCookieHeader], 'a=b');
    expect(headers[corsProxyRefererHeader], 'https://ref.test');
    expect(headers.containsKey('User-Agent'), isFalse);
    expect(headers.containsKey('Cookie'), isFalse);
    expect(headers.containsKey('Accept-Encoding'), isTrue);
    expect(
      decodeCorsProxyForwardHeaderNames(headers[corsProxyForwardHeadersHeader]),
      ['X-Test'],
    );
  });

  test('parses login import cookies and tokens', () {
    final data = WebLoginImportData.parse('''
Cookie: sid=abc; token=Bearer abcdefghijklmnop
User-Agent: TestUA
Authorization: Bearer qwertyuiopasdfgh
''');

    expect(data.userAgent, 'TestUA');
    expect(data.valuesForCookieFields(['sid', 'missing']), ['abc', '']);
    expect(data.token, 'qwertyuiopasdfgh');
    expect(data.hasLoginPayload, isTrue);
  });

  test('builds login import route from helper endpoint', () {
    final client = WebHelperBrowserClient(
      proxyEndpoint: 'https://host.test:60098/proxy',
    );
    expect(
      client.loginImportUrl('source key'),
      'https://host.test:60098/login-import/source%20key',
    );
    expect(
      client.eventsUrl('abc', url: 'https://remote.test/login'),
      'https://host.test:60098/browser/session/abc/events?url=https%3A%2F%2Fremote.test%2Flogin',
    );
  });
}
