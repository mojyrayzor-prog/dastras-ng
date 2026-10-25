import 'dart:convert';
import 'package:http/http.dart' as http;
import 'core.dart';

/// Converts share links / subscription text into Xray outbounds via libXray.
Future<List<Map<String, dynamic>>> convert(String text) async {
  final r = await Core.invoke('convertShareLinksToXrayJson', {'text': text});
  if (r['success'] != true) {
    throw Exception((r['error'] ?? 'تبدیل ناموفق بود').toString());
  }
  final data = r['data'];
  final list = (data is Map ? data['outbounds'] : null) as List?;
  if (list == null || list.isEmpty) throw Exception('کانفیگ قابل استفاده‌ای پیدا نشد');
  return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
}

Future<String> fetchSub(String url) async {
  final res = await http
      .get(Uri.parse(url), headers: {'User-Agent': 'DastRasNG/1.0'})
      .timeout(const Duration(seconds: 25));
  if (res.statusCode != 200) throw Exception('خطای دریافت ساب (${res.statusCode})');
  return res.body;
}

/// Tests delays (max 5 configs per batch). Returns delay in ms per input, null on failure.
Future<List<int?>> pingBatch(List<Map<String, dynamic>> obs) async {
  final out = <int?>[];
  for (var i = 0; i < obs.length; i += 5) {
    final chunk = obs.sublist(i, i + 5 > obs.length ? obs.length : i + 5);
    final r = await Core.invoke('pingBatch', {
      'configs': [
        for (final ob in chunk)
          {
            'xrayJson': jsonEncode({
              'outbounds': [ob]
            })
          }
      ],
      'timeout': 5,
      'url': 'https://cp.cloudflare.com/',
    });
    List items = const [];
    final d = r['data'];
    if (d is List) {
      items = d;
    } else if (d is Map) {
      items = (d['results'] ?? d['items'] ?? d['delays'] ?? d['configs'] ?? const []) as List;
    }
    for (var k = 0; k < chunk.length; k++) {
      int? v;
      if (k < items.length && items[k] is Map) {
        final dl = (items[k] as Map)['delay'];
        if (dl is num && dl < 10000) v = dl.toInt();
      }
      out.add(v);
    }
  }
  return out;
}
