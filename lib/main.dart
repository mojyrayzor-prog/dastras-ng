import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import 'config.dart';
import 'core.dart';
import 'models.dart';
import 'service.dart';

const kAppName = 'DastRas NG';
const kChannelUrl = 'https://t.me/dastras';
const kSupportUrl = 'https://t.me/Administrator';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      locale: const Locale('fa'),
      supportedLocales: const [Locale('fa'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF1E88E5),
        brightness: Brightness.dark,
      ),
      home: const Home(),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final store = Store();
  bool ready = false;
  bool busy = false;
  String status = 'stopped';
  String? lastShownError;
  Timer? timer;

  bool get running => status == 'running';
  bool get starting => status == 'starting';

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    await store.load();
    status = await Core.status();
    setState(() => ready = true);
    timer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
    if (store.subs.isNotEmpty && !running) _refreshSubs(silent: true);
  }

  Future<void> _poll() async {
    final s = await Core.status();
    if (!mounted) return;
    if (s != status) {
      setState(() => status = s);
    }
    if (s.startsWith('error:') && s != lastShownError) {
      lastShownError = s;
      _toast('خطا: ${s.substring(6)}');
    }
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _toggle() async {
    if (running || starting) {
      await Core.stop();
      return;
    }
    if (store.nodes.isEmpty) {
      _toast('ابتدا یک کانفیگ یا ساب اضافه کنید');
      return;
    }
    lastShownError = null;
    final node = store.nodes[store.selected];
    final res = await Core.start(buildConfig(node.ob, store.bypassIran));
    if (res == 'denied') _toast('دسترسی VPN داده نشد');
  }

  Future<void> _refreshSubs({bool silent = false}) async {
    if (store.subs.isEmpty) return;
    if (!silent) setState(() => busy = true);
    try {
      final all = <Node>[];
      for (final url in store.subs) {
        final text = await fetchSub(url);
        final obs = await convert(text);
        all.addAll(obs.map((o) => Node(o, 'sub')));
      }
      store.nodes = [...store.nodes.where((n) => n.src != 'sub'), ...all];
      if (store.selected >= store.nodes.length) store.selected = 0;
      await store.save();
      if (!silent) _toast('ساب به‌روز شد (${all.length} کانفیگ)');
    } catch (e) {
      if (!silent) _toast('خطا: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _addText(String text) async {
    text = text.trim();
    if (text.isEmpty) return;
    setState(() => busy = true);
    try {
      final isSub = !text.contains('\n') &&
          (text.startsWith('http://') || text.startsWith('https://'));
      if (isSub) {
        if (!store.subs.contains(text)) store.subs.add(text);
        await store.save();
        await _refreshSubs();
      } else {
        final obs = await convert(text);
        store.nodes.addAll(obs.map((o) => Node(o, 'manual')));
        await store.save();
        _toast('${obs.length} کانفیگ اضافه شد');
      }
    } catch (e) {
      _toast('خطا: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _ping() async {
    if (running || starting) {
      _toast('برای تست تأخیر ابتدا اتصال را قطع کنید');
      return;
    }
    if (store.nodes.isEmpty) return;
    setState(() => busy = true);
    try {
      final res = await pingBatch(store.nodes.map((n) => n.ob).toList());
      for (var i = 0; i < store.nodes.length && i < res.length; i++) {
        store.nodes[i].delay = res[i];
      }
      int? best;
      for (var i = 0; i < store.nodes.length; i++) {
        final d = store.nodes[i].delay;
        if (d != null && (best == null || d < (store.nodes[best].delay ?? 99999))) {
          best = i;
        }
      }
      if (best != null) {
        store.selected = best;
        await store.save();
      }
    } catch (e) {
      _toast('خطا: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _addDialog() {
    final c = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('افزودن کانفیگ'),
        content: TextField(
          controller: c,
          maxLines: 6,
          minLines: 3,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(
            hintText: 'لینک ساب یا لینک‌های vless / vmess / trojan / ss',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _addText(c.text);
            },
            child: const Text('افزودن'),
          ),
        ],
      ),
    );
  }

  void _settings() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SwitchListTile(
              title: const Text('عبور مستقیم سایت‌ها و IPهای ایرانی'),
              value: store.bypassIran,
              onChanged: (v) async {
                store.bypassIran = v;
                await store.save();
                set(() {});
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('حذف همه کانفیگ‌ها و ساب‌ها'),
              onTap: () async {
                Navigator.pop(ctx);
                store.nodes = [];
                store.subs = [];
                store.selected = 0;
                await store.save();
                if (mounted) setState(() {});
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('درباره'),
              onTap: () {
                Navigator.pop(ctx);
                _about();
              },
            ),
          ]),
        ),
      ),
    );
  }

  void _about() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(kAppName),
        content: const Text('کلاینت مبتنی بر هسته‌ی Xray\nبرای اخبار و پشتیبانی به کانال و ادمین سر بزنید.'),
        actions: [
          TextButton(onPressed: () => _open(kSupportUrl), child: const Text('پشتیبانی')),
          FilledButton(onPressed: () => _open(kChannelUrl), child: const Text('کانال تلگرام')),
        ],
      ),
    );
  }

  Future<void> _open(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = running
        ? 'متصل شد'
        : starting
            ? 'در حال اتصال...'
            : 'قطع';
    return Scaffold(
      appBar: AppBar(
        title: const Text(kAppName),
        actions: [
          IconButton(
            tooltip: 'کانال تلگرام',
            icon: const Icon(Icons.send),
            onPressed: () => _open(kChannelUrl),
          ),
          IconButton(
            tooltip: 'تست تأخیر',
            icon: const Icon(Icons.speed),
            onPressed: busy ? null : _ping,
          ),
          IconButton(
            tooltip: 'به‌روزرسانی ساب',
            icon: const Icon(Icons.refresh),
            onPressed: busy ? null : () => _refreshSubs(),
          ),
          IconButton(icon: const Icon(Icons.more_vert), onPressed: _settings),
        ],
        bottom: busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addDialog,
        child: const Icon(Icons.add),
      ),
      body: !ready
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              const SizedBox(height: 24),
              GestureDetector(
                onTap: _toggle,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: running ? Colors.green : (starting ? Colors.orange : cs.surfaceContainerHighest),
                  ),
                  child: const Icon(Icons.power_settings_new, size: 56),
                ),
              ),
              const SizedBox(height: 12),
              Text(label, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              const Divider(height: 1),
              Expanded(
                child: store.nodes.isEmpty
                    ? const Center(child: Text('هنوز کانفیگی اضافه نشده.\nبا دکمه‌ی + لینک ساب یا کانفیگ اضافه کنید.', textAlign: TextAlign.center))
                    : ListView.builder(
                        itemCount: store.nodes.length,
                        itemBuilder: (_, i) {
                          final n = store.nodes[i];
                          final sel = i == store.selected;
                          final d = n.delay;
                          return ListTile(
                            selected: sel,
                            leading: Icon(sel ? Icons.radio_button_checked : Icons.radio_button_off),
                            title: Text(n.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(d == null ? n.protocol : '${n.protocol} • $d ms'),
                            trailing: IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () async {
                                store.nodes.removeAt(i);
                                if (store.selected >= store.nodes.length) store.selected = 0;
                                await store.save();
                                setState(() {});
                              },
                            ),
                            onTap: () async {
                              store.selected = i;
                              await store.save();
                              setState(() {});
                            },
                          );
                        },
                      ),
              ),
            ]),
    );
  }
}
