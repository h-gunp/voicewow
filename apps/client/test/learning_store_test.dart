import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicemate/features/pronunciation/data/learning_store.dart';

class DelayedStore implements LearningStore {
  final List<LearningSnapshot> saved = [];
  final gate = Completer<void>();
  @override
  Future<LearningSnapshot> load() async => LearningSnapshot();
  @override
  Future<void> save(LearningSnapshot value) async {
    if (saved.isEmpty) await gate.future;
    saved.add(value);
  }
}

class UnavailableStore implements LearningStore {
  @override
  Future<LearningSnapshot> load() async => throw StateError('unavailable');
  @override
  Future<void> save(LearningSnapshot value) async =>
      throw StateError('unavailable');
}

class ReadFailsStore implements LearningStore {
  LearningSnapshot value = LearningSnapshot(
    guides: [SavedGuide('기존 문장', DateTime.utc(2026))],
  );
  @override
  Future<LearningSnapshot> load() async => throw StateError('read failed');
  @override
  Future<void> save(LearningSnapshot next) async => value = next;
}

class RetryWriteStore implements LearningStore {
  LearningSnapshot value = LearningSnapshot();
  int attempts = 0;
  @override
  Future<LearningSnapshot> load() async => value;
  @override
  Future<void> save(LearningSnapshot next) async {
    if (++attempts == 1) throw StateError('write failed');
    value = next;
  }
}

void main() {
  test(
    'failed initial read cannot overwrite existing saved sentences',
    () async {
      final store = ReadFailsStore();
      final learning = LearningController(store);
      await learning.load();
      await learning.saveGuide('새 문장');
      expect(learning.guides.single.text, '새 문장');
      expect(store.value.guides.single.text, '기존 문장');
      expect(learning.storageUnavailable, isTrue);
      learning.dispose();
    },
  );

  test('a later save retries after a temporary write failure', () async {
    final store = RetryWriteStore();
    final learning = LearningController(store);
    await learning.load();
    await learning.saveGuide('첫 문장');
    expect(learning.storageUnavailable, isTrue);
    await learning.saveGuide('다음 문장');
    expect(learning.storageUnavailable, isFalse);
    expect(store.value.guides.map((guide) => guide.text), ['다음 문장', '첫 문장']);
    learning.dispose();
  });

  test('wrong answers, bookmarks and saved sentences survive reload', () async {
    final store = MemoryLearningStore();
    final first = LearningController(store);
    await first.load();
    await first.recordAnswer('one', false);
    await first.toggleBookmark('two');
    await first.saveGuide('같이 가요');
    final second = LearningController(store);
    await second.load();
    expect(second.wrongIds, {'one'});
    expect(second.bookmarkedIds, {'two'});
    expect(second.guides.single.text, '같이 가요');
    await second.recordAnswer('one', true);
    expect(second.wrongIds, isEmpty);
    expect(second.answers['one'], isTrue);
    first.dispose();
    second.dispose();
  });

  test('JSON round trip preserves Korean, dates and answer state', () {
    final value = LearningSnapshot(
      answers: {'word': false},
      wrongIds: {'word'},
      bookmarkedIds: {'word'},
      guides: [SavedGuide('같이 가요!', DateTime.utc(2026, 11, 2))],
    );
    final restored = LearningSnapshot.decode(value.encode());
    expect(restored.answers, value.answers);
    expect(restored.wrongIds, value.wrongIds);
    expect(restored.bookmarkedIds, value.bookmarkedIds);
    expect(restored.guides.single.text, value.guides.single.text);
    expect(restored.guides.single.savedAt, value.guides.single.savedAt);
    expect(() => LearningSnapshot.decode('{'), throwsFormatException);
    expect(
      () => LearningSnapshot.decode('{"version":2}'),
      throwsFormatException,
    );
  });

  test('a delayed old write cannot overwrite a later correction', () async {
    final store = DelayedStore();
    final learning = LearningController(store);
    await learning.load();
    final first = learning.recordAnswer('one', false);
    final second = learning.recordAnswer('one', true);
    await Future<void>.delayed(Duration.zero);
    expect(store.saved, isEmpty);
    store.gate.complete();
    await Future.wait([first, second]);
    expect(store.saved.last.answers['one'], isTrue);
    expect(store.saved.last.wrongIds, isEmpty);
    learning.dispose();
  });

  test(
    'storage failures retain usable in-memory practice and report failure',
    () async {
      final learning = LearningController(UnavailableStore());
      await learning.load();
      expect(learning.ready, isTrue);
      expect(learning.storageUnavailable, isTrue);
      await learning.recordAnswer('one', false);
      expect(learning.wrongIds, {'one'});
      expect(learning.storageUnavailable, isTrue);
      learning.dispose();
    },
  );

  test('saved sentences are deduplicated, capped and removable', () async {
    final learning = LearningController(MemoryLearningStore());
    await learning.load();
    for (var i = 0; i < 65; i++) {
      await learning.saveGuide('문장 $i');
    }
    expect(learning.guides.length, 60);
    await learning.saveGuide(' 문장 64 ');
    expect(learning.guides.length, 60);
    expect(learning.guides.first.text, '문장 64');
    await learning.deleteGuide('문장 64');
    expect(learning.guides.length, 59);
    expect(learning.guides.any((guide) => guide.text == '문장 64'), isFalse);
    learning.dispose();
  });
}
