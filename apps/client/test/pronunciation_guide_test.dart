import 'package:flutter_test/flutter_test.dart';
import 'package:voicemate/features/pronunciation/domain/pronunciation_guide.dart';

void main() {
  const engine = PronunciationGuideEngine();

  group('받침과 연음', () {
    const examples = {
      '꽃': '꼳',
      '부엌': '부억',
      '밖': '박',
      '닭': '닥',
      '값': '갑',
      '여덟': '여덜',
      '옷이': '오시',
      '꽃을': '꼬츨',
      '있어': '이써',
      '값이': '갑씨',
      '넋이': '넉씨',
      '읽어': '일거',
      '삶이': '살미',
      '많아': '마나',
      '싫어요': '시러요',
      '밟아': '발바',
      '강이': '강이',
    };
    for (final example in examples.entries) {
      test('${example.key} → ${example.value}', () {
        expect(engine.analyze(example.key).pronunciation, example.value);
      });
    }
  });

  group('구개음화와 거센소리', () {
    const examples = {
      '같이': '가치',
      '굳이': '구지',
      '밭이': '바치',
      '미닫이': '미다지',
      '굳히다': '구치다',
      '닫히다': '다치다',
      '좋다': '조타',
      '놓고': '노코',
      '많다': '만타',
      '싫다': '실타',
      '좋소': '조쏘',
      '먹히다': '머키다',
      '밝히다': '발키다',
      '넓히다': '널피다',
      '앉히다': '안치다',
      '같아요': '가타요',
    };
    for (final example in examples.entries) {
      test('${example.key} → ${example.value}', () {
        expect(engine.analyze(example.key).pronunciation, example.value);
      });
    }
  });

  group('비음화·유음화·된소리', () {
    const examples = {
      '국물': '궁물',
      '먹는': '멍는',
      '있는': '인는',
      '없는': '엄는',
      '합니다': '함니다',
      '감사합니다': '감사함니다',
      '반갑습니다': '반갑씀니다',
      '읽는': '잉는',
      '밟는': '밤는',
      '신라': '실라',
      '설날': '설랄',
      '칼날': '칼랄',
      '담력': '담녁',
      '강릉': '강능',
      '협력': '혐녁',
      '막론': '망논',
      '앓는': '알른',
      '핥네': '할레',
      '국밥': '국빱',
      '학교': '학꾜',
      '옷감': '옫깜',
      '앉다': '안따',
      '젊다': '점따',
      '짧다': '짤따',
      '핥다': '할따',
      '밟다': '밥따',
      '읽다': '익따',
      '읽고': '일꼬',
      '맑게': '말께',
      '흙과': '흑꽈',
      '넓죽하다': '넙쭈카다',
      '넓둥글다': '넙뚱글다',
      '감기': '감기',
      '살다': '살다',
      '침대': '침대',
    };
    for (final example in examples.entries) {
      test('${example.key} → ${example.value}', () {
        expect(engine.analyze(example.key).pronunciation, example.value);
      });
    }
  });

  group('일부 단어 경계 예외', () {
    const examples = {
      '맛없다': '마덥따',
      '맛있다': '마싣따',
      '겉옷': '거돋',
      '겉옷을': '거도슬',
      '값어치': '가버치',
      '꽃잎': '꼰닙',
      '꽃잎이': '꼰니피',
      '깻잎': '깬닙',
      '솜이불': '솜니불',
      '색연필': '생년필',
      '물약': '물략',
      '서울역': '서울력',
      '생산량': '생산냥',
      '결단력이': '결딴녀기',
      '상견례': '상견녜',
      '문법': '문뻡',
    };
    for (final example in examples.entries) {
      test('${example.key} → ${example.value}', () {
        final result = engine.analyze(example.key);
        expect(result.pronunciation, example.value);
      });
    }
    test('단어의 구성에 의존한 처리라는 설명을 제공한다', () {
      final result = engine.analyze('꽃잎을 봐요');
      expect(result.notes.any((note) => note.contains('단어의 구성')), isTrue);
    });
  });

  test('뜻을 모르면 단정할 수 없는 동형어의 변환은 보류한다', () {
    for (final word in ['신고', '신고해요', '안다', '신라면', '밤일']) {
      final result = engine.analyze(word);
      expect(result.pronunciation, word);
      expect(result.notes.any((note) => note.contains('원문을 유지')), isTrue);
    }
  });

  test('띄어쓰기·줄바꿈·문장부호를 그대로 유지하며 경계를 넘지 않는다', () {
    const input = '  같이 가요!\n좋은\t아침, 밥 먹어요. 꽃 위  ';
    final result = engine.analyze(input);
    expect(result.original, input);
    expect(result.pronunciation, '  가치 가요!\n조은\t아침, 밥 머거요. 꼳 위  ');
    expect(result.notes.any((note) => note.contains('이어 읽을 때')), isTrue);
  });

  test('음절 끝 처리를 다음 단어의 모음에 연음하지 않는다', () {
    expect(engine.analyze('옷 안에').pronunciation, '옫 아네');
    expect(engine.analyze('꽃을').pronunciation, '꼬츨');
    expect(engine.analyze('꽃 을').pronunciation, '꼳 을');
  });

  test('숫자·영문·이모지와 별도로 입력된 자모는 변환하지 않는다', () {
    const input = '같이 3시에 OK🙂 ㄱ 가';
    final result = engine.analyze(input);
    expect(result.pronunciation, '가치 3시에 OK🙂 ㄱ 가');
    expect(result.notes.any((note) => note.contains('숫자와 영문')), isTrue);
    expect(result.notes.any((note) => note.contains('한글 자모')), isTrue);
  });

  test('한글이 없는 입력과 공백 입력을 성공한 변환처럼 취급하지 않는다', () {
    for (final input in ['', '   ', '123 hello!', 'ㄱㄴㄷ', '가']) {
      final result = engine.analyze(input);
      expect(result.hasHangul, isFalse);
      expect(result.pronunciation, input);
      expect(result.points, isEmpty);
      expect(result.notes.any((note) => note.contains('완성된 한글')), isTrue);
    }
  });

  test('설명은 실제로 바뀐 어절을 가리키고 같은 변경을 반복하지 않는다', () {
    final result = engine.analyze('같이 같이 국물 가요');
    expect(result.points.map((point) => point.before), ['같이', '국물']);
    expect(result.points.map((point) => point.after), ['가치', '궁물']);
    expect(
      result.points.every((point) => point.explanation.isNotEmpty),
      isTrue,
    );
    expect(result.points.first.explanation, contains('ㅈ·ㅊ'));
    expect(() => result.points.clear(), throwsUnsupportedError);
    expect(() => result.notes.clear(), throwsUnsupportedError);
  });

  test('변경이 없어도 모든 단어의 발음이 검증됐다고 하지 않는다', () {
    final result = engine.analyze('가요');
    expect(result.hasHangul, isTrue);
    expect(result.pronunciation, '가요');
    expect(result.notes.any((note) => note.contains('항상 같다는 뜻은')), isTrue);
  });

  test('최대 길이를 넘으면 자르거나 일부만 처리하지 않는다', () {
    final atLimit = List.filled(
      PronunciationGuideEngine.maxInputLength,
      '가',
    ).join();
    expect(engine.analyze(atLimit).pronunciation, atLimit);
    expect(() => engine.analyze('${atLimit}나'), throwsArgumentError);
    final emoji = List.filled(
      PronunciationGuideEngine.maxInputLength,
      '🙂',
    ).join();
    expect(engine.analyze(emoji).pronunciation, emoji);
    expect(() => engine.analyze('${emoji}🙂'), throwsArgumentError);
  });
}
