/// The relay base URL.
///
/// No provider base URL appears here or anywhere in `lib/` — the app speaks
/// to exactly one host, the relay, and never to a model provider directly.
/// That guarantee does not live in this file: `dio_client.dart` derives
/// `HostAllowlistInterceptor`'s allowed host from whatever [relayBaseUrl]
/// resolves to, so exactly one host is dialable no matter which value wins
/// below (FR-004).
///
/// Every build talks to the deployed worker. To point a build at a local
/// `wrangler dev` instead, pass `--dart-define=RELAY_BASE_URL=https://...`.
const String defaultRelayBaseUrl = 'https://dry-run-tutor-paypal.dryrun-app.workers.dev';

const String _relayBaseUrlDefine = String.fromEnvironment('RELAY_BASE_URL');

/// The relay origin this build talks to: `RELAY_BASE_URL` when present and
/// well-formed, otherwise [defaultRelayBaseUrl].
final String relayBaseUrl = _isValidRelayBaseUrl(_relayBaseUrlDefine)
    ? _relayBaseUrlDefine
    : defaultRelayBaseUrl;

/// A configured relay URL is accepted only as a bare `https` origin.
///
/// Not an arbitrary-string pass-through: `http` would put the whole wire
/// contract in the clear, and a path or a query would silently prefix every
/// endpoint the client builds. Anything else falls back rather than throwing
/// — a typo in a build flag should not turn into a crash on launch with no
/// way to read the reason on a device.
bool _isValidRelayBaseUrl(String value) {
  final Uri? uri = Uri.tryParse(value);
  if (uri == null) {
    return false;
  }
  return uri.isScheme('https') &&
      uri.host.isNotEmpty &&
      uri.hasEmptyPath &&
      !uri.hasQuery &&
      !uri.hasFragment;
}
