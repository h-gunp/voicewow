import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SavedGuide {
  final String text;
  final DateTime savedAt;
  const SavedGuide(this.text, this.savedAt);
}

class LearningSnapshot {
  final Map<String, bool> answers;
  final Set<String> wrongIds;
  final Set<String> bookmarkedIds;
  final List<SavedGuide> guides;

  LearningSnapshot({
    Map<String, bool>? answers,
    Set<String>? wrongIds,
    Set<String>? bookmarkedIds,
    List<SavedGuide>? guides,
  }) : answers = Map.unmodifiable(answers ?? {}),
       wrongIds = Set.unmodifiable(wrongIds ?? {}),
       bookmarkedIds = Set.unmodifiable(bookmarkedIds ?? {}),
       guides = List.unmodifiable(guides ?? []);

  String encode() => jsonEncode({
    'version': 1,
    'answers': answers,
    'wrong': wrongIds.toList(),
    'bookmarks': bookmarkedIds.toList(),
    'guides': [
      for (final guide in guides)
        {'text': guide.text, 'savedAt': guide.savedAt.toIso8601String()},
    ],
  });

  factory LearningSnapshot.decode(String source) {
    final value = jsonDecode(source);
    if (value is! Map || value['version'] != 1) {
      throw const FormatException('지원하지 않는 학습 기록입니다.');
    }
    Set<String> strings(dynamic list) =>
        list is List ? list.whereType<String>().toSet() : {};
    final rawAnswers = value['answers'];
    final rawGuides = value['guides'];
    return LearningSnapshot(
      answers: rawAnswers is Map
          ? {
              for (final entry in rawAnswers.entries)
                if (entry.key is String && entry.value is bool)
                  entry.key as String: entry.value as bool,
            }
          : {},
      wrongIds: strings(value['wrong']),
      bookmarkedIds: strings(value['bookmarks']),
      guides: rawGuides is List
          ? [
              for (final item in rawGuides)
                if (item is Map &&
                    item['text'] is String &&
                    (item['text'] as String).trim().isNotEmpty &&
                    item['savedAt'] is String &&
                    DateTime.tryParse(item['savedAt']) != null)
                  SavedGuide(item['text'], DateTime.parse(item['savedAt'])),
            ].take(60).toList()
          : [],
    );
  }
}

abstract interface class LearningStore {
  Future<LearningSnapshot> load();
  Future<void> save(LearningSnapshot value);
}

class PreferencesLearningStore implements LearningStore {
  static const key = 'voicemate.pronunciation.v1';
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  @override
  Future<LearningSnapshot> load() async {
    final source = await _preferences.getString(key);
    return source == null
        ? LearningSnapshot()
        : LearningSnapshot.decode(source);
  }

  @override
  Future<void> save(LearningSnapshot value) =>
      _preferences.setString(key, value.encode());
}

class MemoryLearningStore implements LearningStore {
  LearningSnapshot value;
  MemoryLearningStore([LearningSnapshot? initial])
    : value = initial ?? LearningSnapshot();
  @override
  Future<LearningSnapshot> load() async => value;
  @override
  Future<void> save(LearningSnapshot value) async => this.value = value;
}

class LearningController extends ChangeNotifier {
  final LearningStore store;
  LearningSnapshot _snapshot = LearningSnapshot();
  Future<void> _writes = Future.value();
  bool ready = false;
  bool storageUnavailable = false;
  bool _loaded = false;
  bool _disposed = false;
  Future<void>? _loading;

  LearningController(this.store);
  LearningSnapshot get snapshot => _snapshot;
  Map<String, bool> get answers => _snapshot.answers;
  Set<String> get wrongIds => _snapshot.wrongIds;
  Set<String> get bookmarkedIds => _snapshot.bookmarkedIds;
  List<SavedGuide> get guides => _snapshot.guides;

  Future<void> load() => _loading ??= _load();
  Future<void> _load() async {
    try {
      _snapshot = await store.load();
      _loaded = true;
    } catch (_) {
      storageUnavailable = true;
    }
    ready = true;
    _notify();
  }

  Future<void> recordAnswer(String id, bool correct) {
    if (!ready || _disposed) return Future.value();
    final wrong = {...wrongIds};
    correct ? wrong.remove(id) : wrong.add(id);
    _snapshot = LearningSnapshot(
      answers: {...answers, id: correct},
      wrongIds: wrong,
      bookmarkedIds: bookmarkedIds,
      guides: guides,
    );
    return _persist();
  }

  Future<void> toggleBookmark(String id) {
    if (!ready || _disposed) return Future.value();
    final next = {...bookmarkedIds};
    next.contains(id) ? next.remove(id) : next.add(id);
    _snapshot = LearningSnapshot(
      answers: answers,
      wrongIds: wrongIds,
      bookmarkedIds: next,
      guides: guides,
    );
    return _persist();
  }

  Future<void> saveGuide(String text) {
    if (!ready || _disposed) return Future.value();
    final trimmed = text.trim();
    if (trimmed.isEmpty) return Future.value();
    _snapshot = LearningSnapshot(
      answers: answers,
      wrongIds: wrongIds,
      bookmarkedIds: bookmarkedIds,
      guides: [
        SavedGuide(trimmed, DateTime.now()),
        ...guides.where((guide) => guide.text != trimmed),
      ].take(60).toList(),
    );
    return _persist();
  }

  Future<void> deleteGuide(String text) {
    if (!ready || _disposed) return Future.value();
    _snapshot = LearningSnapshot(
      answers: answers,
      wrongIds: wrongIds,
      bookmarkedIds: bookmarkedIds,
      guides: guides.where((guide) => guide.text != text).toList(),
    );
    return _persist();
  }

  Future<void> _persist() {
    final value = _snapshot;
    _notify();
    if (!_loaded) return Future.value();
    // Keep a slower earlier write from replacing a newer answer.
    _writes = _writes.then((_) async {
      try {
        await store.save(value);
        storageUnavailable = false;
      } catch (_) {
        storageUnavailable = true;
      }
      _notify();
    });
    return _writes;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
