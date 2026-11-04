import 'package:flutter_test/flutter_test.dart';
import 'package:voicemate/features/pronunciation/domain/quiz_catalog.dart';
import 'package:voicemate/features/pronunciation/domain/pronunciation_guide.dart';

void main() {
  test('125 curated questions fill the agreed categories exactly', () {
    expect(quizCatalog, hasLength(125));
    expect(TrainingCategory.values.map((category) => category.label), [
      '단어',
      '기초 문장',
      '확장 문장',
      '비즈니스 문장',
    ]);
    for (final category in TrainingCategory.values) {
      expect(
        quizCatalog.where((item) => item.category == category).length,
        category == TrainingCategory.words ? 50 : 25,
        reason: category.label,
      );
    }
  });

  test('word rules each contain ten distinct exercises under exact labels', () {
    const groups = [
      '이어 읽기 (연음 연습)',
      '된소리로 읽기 (된소리되기 연습)',
      '받침을 ㅇ·ㄴ·ㅁ으로 읽기 (비음화 연습)',
      'ㅈ·ㅊ으로 바꿔 읽기 (구개음화 연습)',
      'ㅋ·ㅌ·ㅍ·ㅊ으로 바꿔 읽기 (거센소리되기 연습)',
    ];
    expect(wordTrainingGroups, groups);
    expect(groupsForCategory(TrainingCategory.words), groups);
    for (final group in groups) {
      final items = itemsForGroup(TrainingCategory.words, group);
      expect(items, hasLength(10), reason: group);
      expect(items.map((item) => item.text).toSet(), hasLength(10));
    }
  });

  test('each sentence topic provides exactly one five-question session', () {
    const topics = {
      TrainingCategory.basic: [
        '함께하는 말',
        '생각과 느낌',
        '먹고 마시기',
        '외출과 약속',
        '옷과 주변 사물',
      ],
      TrainingCategory.extended: [
        '음식 주문',
        '물건 고르기',
        '장소와 이동',
        '생활 설명',
        '도움과 부탁',
      ],
      TrainingCategory.business: [
        '자료 검토',
        '협업과 업무',
        '연락과 일정',
        '방문과 안내',
        '요청과 회신',
      ],
    };
    for (final entry in topics.entries) {
      expect(groupsForCategory(entry.key), entry.value);
      for (final group in entry.value) {
        final items = itemsForGroup(entry.key, group);
        expect(items, hasLength(5), reason: '${entry.key.label}: $group');
        expect(items.every((item) => item.category == entry.key), isTrue);
        expect(items.every((item) => item.group == group), isTrue);
      }
    }
  });

  test('IDs and exercise texts do not collide across categories', () {
    expect(quizCatalog.map((item) => item.id).toSet(), hasLength(125));
    expect(quizCatalog.map((item) => item.text).toSet(), hasLength(125));
    expect(
      quizCatalog.every((item) => RegExp(r'^[a-z0-9-]+$').hasMatch(item.id)),
      isTrue,
    );
  });

  test(
    'each question has one distinct wrong option and an official reference',
    () {
      for (final item in quizCatalog) {
        expect(item.text.trim(), isNotEmpty, reason: item.id);
        expect(item.pronunciation.trim(), isNotEmpty, reason: item.id);
        expect(item.distractor.trim(), isNotEmpty, reason: item.id);
        expect(item.pronunciation, isNot(item.distractor), reason: item.id);
        expect(item.explanation.trim(), isNotEmpty, reason: item.id);
        final source = Uri.parse(item.sourceUrl);
        expect(source.scheme, 'https', reason: item.id);
        expect(
          source.host == 'korean.go.kr' ||
              source.host.endsWith('.korean.go.kr'),
          isTrue,
          reason: item.id,
        );
        // The presentation adds brackets, so stored options stay unbracketed.
        expect(item.pronunciation.contains('['), isFalse, reason: item.id);
        expect(item.distractor.contains('['), isFalse, reason: item.id);
      }
    },
  );

  test('all independently curated readings agree with the personal guide', () {
    const engine = PronunciationGuideEngine();
    final mismatches = <String>[];
    for (final item in quizCatalog) {
      final actual = engine.analyze(item.text).pronunciation;
      if (actual != item.pronunciation) {
        mismatches.add(
          '${item.id}: ${item.text} → $actual; expected ${item.pronunciation}',
        );
      }
    }
    // Expected answers are manually curated in the catalog. This test must not
    // generate or rewrite them from the engine under test.
    expect(mismatches, isEmpty, reason: mismatches.join('\n'));
  });

  test(
    'the original 32 IDs keep their texts and readings after regrouping',
    () {
      const original = <String, (String, String)>{
        'word-g-01': ('같이', '가치'),
        'word-g-02': ('굳이', '구지'),
        'word-g-03': ('국물', '궁물'),
        'word-g-04': ('국밥', '국빱'),
        'word-b-01': ('밥상', '밥쌍'),
        'word-b-02': ('박수', '박쑤'),
        'word-b-03': ('밥물', '밤물'),
        'word-b-04': ('박물관', '방물관'),
        'basic-talk-01': ('같이 가요', '가치 가요'),
        'basic-talk-02': ('같이 해요', '가치 해요'),
        'basic-talk-03': ('좋아요', '조아요'),
        'basic-talk-04': ('많아요', '마나요'),
        'basic-life-01': ('옷을 사요', '오슬 사요'),
        'basic-life-02': ('꽃이 펴요', '꼬치 펴요'),
        'basic-life-03': ('학교에 가요', '학꾜에 가요'),
        'basic-life-04': ('식사해요', '식싸해요'),
        'extended-order-01': ('국물을 더 주세요', '궁무를 더 주세요'),
        'extended-order-02': ('밥을 더 주세요', '바블 더 주세요'),
        'extended-order-03': ('꽃을 하나 주세요', '꼬츨 하나 주세요'),
        'extended-order-04': ('옷을 보여 주세요', '오슬 보여 주세요'),
        'extended-life-01': ('학교에서 만나요', '학꾜에서 만나요'),
        'extended-life-02': ('국물이 뜨거워요', '궁무리 뜨거워요'),
        'extended-life-03': ('난로가 따뜻해요', '날로가 따뜨태요'),
        'extended-life-04': ('강릉으로 가요', '강능으로 가요'),
        'business-request-01': ('자료를 같이 봐요', '자료를 가치 봐요'),
        'business-request-02': ('자료를 확인해요', '자료를 화긴해요'),
        'business-request-03': ('오후에 연락해요', '오후에 열라캐요'),
        'business-request-04': ('팀과 협력해요', '팀과 혐녀캐요'),
        'business-guide-01': ('입구에서 만나요', '입꾸에서 만나요'),
        'business-guide-02': ('식사 후에 만나요', '식싸 후에 만나요'),
        'business-guide-03': ('업무를 나눠요', '엄무를 나눠요'),
        'business-guide-04': ('입장을 알려 주세요', '입짱을 알려 주세요'),
      };
      expect(original, hasLength(32));
      for (final entry in original.entries) {
        final item = quizCatalog.singleWhere((item) => item.id == entry.key);
        expect((item.text, item.pronunciation), entry.value, reason: entry.key);
      }
    },
  );

  test('independent anchors cover every word rule and the ㅂ/ㅍ contrast', () {
    QuizItem exercise(String text) =>
        quizCatalog.singleWhere((item) => item.text == text);
    expect(exercise('꽃이').pronunciation, '꼬치');
    expect(exercise('깎아').pronunciation, '까까');
    expect(exercise('옆집').pronunciation, '엽찝');
    expect(exercise('국물').pronunciation, '궁물');
    expect(exercise('앞마당').pronunciation, '암마당');
    expect(exercise('땀받이').pronunciation, '땀바지');
    expect(exercise('닫히다').pronunciation, '다치다');
    expect(exercise('닳지').pronunciation, '달치');
    expect(exercise('입학').pronunciation, '이팍');
    expect(exercise('컵을 씻어요').pronunciation, '커블 씨서요');
    expect(exercise('앞을 봐요').pronunciation, '아플 봐요');
    expect(exercise('문을 열어요').pronunciation, '무늘 여러요');
    expect(exercise('손을 잡아요').pronunciation, '소늘 자바요');
    expect(exercise('옆에 앉아요').pronunciation, '여페 안자요');
  });

  test('group display helpers preserve full canonical filter values', () {
    expect(groupTitle(wordTrainingGroups.first), '이어 읽기');
    expect(groupPracticeLabel(wordTrainingGroups.first), '연음 연습');
    expect(groupTitle(wordTrainingGroups.last), 'ㅋ·ㅌ·ㅍ·ㅊ으로 바꿔 읽기');
    expect(groupPracticeLabel(wordTrainingGroups.last), '거센소리되기 연습');
    expect(groupTitle('음식 주문'), '음식 주문');
    expect(groupPracticeLabel('음식 주문'), isNull);
    expect(itemsForGroup(TrainingCategory.words, '없는 분류'), isEmpty);
  });

  test('sentence reading scope stays visible in catalog help', () {
    expect(catalogReadingNote, contains('어절별'));
    expect(catalogReadingNote, contains('소리의 길이'));
  });
}
