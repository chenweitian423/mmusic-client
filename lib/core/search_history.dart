import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SearchHistoryStore {
  static const _key = 'searchHistory';
  static const _maxItems = 10;

  SharedPreferences? _sp;
  final ValueNotifier<List<String>> terms = ValueNotifier(<String>[]);

  Future<void> init() async {
    _sp = await SharedPreferences.getInstance();
    terms.value = _sp?.getStringList(_key) ?? <String>[];
  }

  Future<void> add(String term) async {
    final q = term.trim();
    if (q.isEmpty) return;
    final next = [
      q,
      ...terms.value.where((e) => e != q),
    ].take(_maxItems).toList();
    terms.value = next;
    await _sp?.setStringList(_key, next);
  }

  Future<void> remove(String term) async {
    final next = terms.value.where((e) => e != term).toList();
    terms.value = next;
    await _sp?.setStringList(_key, next);
  }

  Future<void> clear() async {
    terms.value = <String>[];
    await _sp?.remove(_key);
  }
}

final searchHistory = SearchHistoryStore();
