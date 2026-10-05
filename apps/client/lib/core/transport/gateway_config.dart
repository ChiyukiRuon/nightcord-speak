/// Build-time browser configuration. A bundled token is visible to visitors.
class GatewayConfig {
  const GatewayConfig({this.url = '', this.token = ''});

  const GatewayConfig.environment()
    : url = const String.fromEnvironment(
        'NIGHTCORD_GATEWAY_URL',
        defaultValue: String.fromEnvironment('NIGHTCORD_GATEWAY'),
      ),
      token = const String.fromEnvironment('NIGHTCORD_GATEWAY_TOKEN');

  final String url;
  final String token;
  bool get autoConnect => url.trim().isNotEmpty;

  String address(Uri page) {
    // Never send a configured credential to an endpoint chosen by a URL link.
    if (token.trim().isNotEmpty) return url.trim();
    return page.queryParameters['gw'] ??
        (url.trim().isEmpty
            ? Uri(
                scheme: page.scheme == 'https' ? 'wss' : 'ws',
                host: page.host.isEmpty ? 'localhost' : page.host,
                port: 8787,
                path: '/ws',
              ).toString()
            : url.trim());
  }
}
