import 'dart:convert';

/// Builds the full Xray config around the selected outbound.
/// The TUN fd and asset dir are injected natively (root "env").
String buildConfig(Map<String, dynamic> ob, bool bypassIran) {
  final proxy = Map<String, dynamic>.from(ob)..['tag'] = 'proxy';

  final rules = <Map<String, dynamic>>[
    {'type': 'field', 'ip': ['geoip:private'], 'outboundTag': 'direct'},
    if (bypassIran) ...[
      {'type': 'field', 'domain': ['geosite:category-ir'], 'outboundTag': 'direct'},
      {'type': 'field', 'ip': ['geoip:ir'], 'outboundTag': 'direct'},
    ],
  ];

  final cfg = {
    'log': {'loglevel': 'warning'},
    'dns': {
      'servers': ['1.1.1.1', '8.8.8.8']
    },
    'inbounds': [
      {
        'tag': 'tun-in',
        'protocol': 'tun',
        'settings': {'name': 'xray0', 'MTU': 1500},
        'sniffing': {
          'enabled': true,
          'destOverride': ['http', 'tls', 'quic']
        }
      }
    ],
    'outbounds': [
      proxy,
      {'tag': 'direct', 'protocol': 'freedom'},
      {'tag': 'block', 'protocol': 'blackhole'},
    ],
    'routing': {'domainStrategy': 'IPIfNonMatch', 'rules': rules},
  };
  return jsonEncode(cfg);
}
