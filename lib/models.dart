import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class Node {
  final Map<String, dynamic> ob;
  final String src; // 'sub' or 'manual'
  int? delay;
  Node(this.ob, this.src);

  String get name => (ob['tag'] ?? ob['protocol'] ?? 'node').toString();
  String get protocol => (ob['protocol'] ?? '').toString().toUpperCase();

  Map<String, dynamic> toJson() => {'ob': ob, 'src': src};

  factory Node.fromJson(Map<String, dynamic> j) => Node(
      Map<String, dynamic>.from(j['ob'] as Map), (j['src'] ?? 'manual').toString());
}

class Store {
  late SharedPreferences _p;
  List<Node> nodes = [];
  List<String> subs = [];
  int selected = 0;
  bool bypassIran = true;

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    final raw = _p.getString('nodes');
    if (raw != null) {
      try {
        nodes = (jsonDecode(raw) as List)
            .map((e) => Node.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      } catch (_) {
        nodes = [];
      }
    }
    subs = _p.getStringList('subs') ?? [];
    selected = _p.getInt('selected') ?? 0;
    bypassIran = _p.getBool('bypassIran') ?? true;
    if (selected >= nodes.length) selected = 0;
  }

  Future<void> save() async {
    await _p.setString('nodes', jsonEncode(nodes.map((e) => e.toJson()).toList()));
    await _p.setStringList('subs', subs);
    await _p.setInt('selected', selected);
    await _p.setBool('bypassIran', bypassIran);
  }
}
