/// Original learning examples, checked against National Institute of Korean
/// Language pronunciation rules. These are not copied exercises from a service.
///
/// Sentence options use word-by-word reading: optional connected-speech variants
/// across spaces and vowel length are outside this exercise's scoring scope.
enum TrainingCategory {
  words('단어', '소리별로 짧게 익혀요'),
  basic('기초 문장', '짧은 생활 표현을 연습해요'),
  extended('확장 문장', '상황에 맞는 문장을 익혀요'),
  business('비즈니스 문장', '업무에서 쓰는 표현을 연습해요');

  const TrainingCategory(this.label, this.subtitle);

  final String label;
  final String subtitle;
}

class QuizItem {
  const QuizItem({
    required this.id,
    required this.category,
    required this.group,
    required this.text,
    required this.pronunciation,
    required this.distractor,
    required this.explanation,
    required this.sourceUrl,
  });

  final String id;
  final TrainingCategory category;
  final String group;
  final String text;
  final String pronunciation;
  final String distractor;
  final String explanation;

  /// The official reference for the question's main pronunciation contrast.
  /// Other sentence words follow the same rules listed in [quizSources].
  final String sourceUrl;
}

const catalogReadingNote =
    '보기는 어절별로 끊어 읽는 연습 기준이에요. 소리의 길이와 말 사이의 이어 읽기는 표시하지 않아요.';

/// Official references used to check the changed portions of the original
/// sentences below. Explanations are written for this app, not copied passages.
const quizSources = <String, String>{
  '구개음화':
      'https://www.korean.go.kr/front/onlineQna/onlineQnaView.do?mn_id=261&qna_seq=327454',
  '구개음화·연음 해설':
      'https://www.korean.go.kr/front/onlineQna/onlineQnaView.do?mn_id=261&qna_seq=325270',
  '연음·된소리되기':
      'https://www.korean.go.kr/front/onlineQna/onlineQnaView.do?mn_id=216&qna_seq=323814',
  '비음화':
      'https://www.korean.go.kr/front/onlineQna/onlineQnaView.do?mn_id=216&qna_seq=313220',
  '유음화·ㄹ의 비음화':
      'https://www.korean.go.kr/front/onlineQna/onlineQnaView.do?mn_id=216&qna_seq=313409',
  'ㅎ의 발음':
      'https://www.korean.go.kr/front/onlineQna/onlineQnaView.do?mn_id=216&qna_seq=321749',
  '확인':
      'https://krdict.korean.go.kr/jpn/dicSearch/SearchView?ParaWordNo=73236&nation=jpn',
  '협력':
      'https://www.korean.go.kr/front/onlineQna/onlineQnaView.do?mn_id=216&qna_seq=330091',
};

const _palatal =
    'https://www.korean.go.kr/front/onlineQna/onlineQnaView.do?mn_id=261&qna_seq=327454';
const _liaison =
    'https://www.korean.go.kr/front/onlineQna/onlineQnaView.do?mn_id=216&qna_seq=323814';
const _nasal =
    'https://www.korean.go.kr/front/onlineQna/onlineQnaView.do?mn_id=216&qna_seq=313220';
const _liquid =
    'https://www.korean.go.kr/front/onlineQna/onlineQnaView.do?mn_id=216&qna_seq=313409';
const _h =
    'https://www.korean.go.kr/front/onlineQna/onlineQnaView.do?mn_id=216&qna_seq=321749';

const quizCatalog = <QuizItem>[
  QuizItem(
    id: 'word-g-01',
    category: TrainingCategory.words,
    group: 'ㄱ 소리',
    text: '같이',
    pronunciation: '가치',
    distractor: '가티',
    explanation: '‘같이’는 [가치]로 읽어요. 받침 ㅌ이 뒤의 ‘이’와 만나 ㅊ 소리로 바뀌어요.',
    sourceUrl: _palatal,
  ),
  QuizItem(
    id: 'word-g-02',
    category: TrainingCategory.words,
    group: 'ㄱ 소리',
    text: '굳이',
    pronunciation: '구지',
    distractor: '구디',
    explanation: '‘굳이’는 [구지]로 읽어요. 받침 ㄷ이 뒤의 ‘이’와 만나 ㅈ 소리로 바뀌어요.',
    sourceUrl:
        'https://www.korean.go.kr/front/onlineQna/onlineQnaView.do?mn_id=261&qna_seq=325270',
  ),
  QuizItem(
    id: 'word-g-03',
    category: TrainingCategory.words,
    group: 'ㄱ 소리',
    text: '국물',
    pronunciation: '궁물',
    distractor: '국물',
    explanation: '‘국물’은 [궁물]로 읽어요. 받침 ㄱ이 ㅁ 앞에서 ㅇ 소리로 바뀌어요.',
    sourceUrl: _nasal,
  ),
  QuizItem(
    id: 'word-g-04',
    category: TrainingCategory.words,
    group: 'ㄱ 소리',
    text: '국밥',
    pronunciation: '국빱',
    distractor: '국밥',
    explanation: '‘국밥’은 [국빱]으로 읽어요. 받침 ㄱ 뒤의 ㅂ을 된소리 ㅃ으로 읽어요.',
    sourceUrl: _liaison,
  ),
  QuizItem(
    id: 'word-b-01',
    category: TrainingCategory.words,
    group: 'ㅂ 소리',
    text: '밥상',
    pronunciation: '밥쌍',
    distractor: '밥상',
    explanation: '‘밥상’은 [밥쌍]으로 읽어요. 받침 ㅂ 뒤의 ㅅ을 된소리 ㅆ으로 읽어요.',
    sourceUrl: _liaison,
  ),
  QuizItem(
    id: 'word-b-02',
    category: TrainingCategory.words,
    group: 'ㅂ 소리',
    text: '박수',
    pronunciation: '박쑤',
    distractor: '박수',
    explanation: '‘박수’는 [박쑤]로 읽어요. 받침 ㄱ 뒤의 ㅅ을 된소리 ㅆ으로 읽어요.',
    sourceUrl: _liaison,
  ),
  QuizItem(
    id: 'word-b-03',
    category: TrainingCategory.words,
    group: 'ㅂ 소리',
    text: '밥물',
    pronunciation: '밤물',
    distractor: '밥물',
    explanation: '‘밥물’은 [밤물]로 읽어요. 받침 ㅂ이 ㅁ 앞에서 ㅁ 소리로 바뀌어요.',
    sourceUrl: _nasal,
  ),
  QuizItem(
    id: 'word-b-04',
    category: TrainingCategory.words,
    group: 'ㅂ 소리',
    text: '박물관',
    pronunciation: '방물관',
    distractor: '박물관',
    explanation: '‘박물관’은 [방물관]으로 읽어요. 받침 ㄱ이 ㅁ 앞에서 ㅇ 소리로 바뀌어요.',
    sourceUrl: _nasal,
  ),
  QuizItem(
    id: 'basic-talk-01',
    category: TrainingCategory.basic,
    group: '일상 대화',
    text: '같이 가요',
    pronunciation: '가치 가요',
    distractor: '가티 가요',
    explanation: '‘같이’의 읽는 소리는 [가치]예요. ‘가요’와 함께 짧게 연습해 보세요.',
    sourceUrl: _palatal,
  ),
  QuizItem(
    id: 'basic-talk-02',
    category: TrainingCategory.basic,
    group: '일상 대화',
    text: '같이 해요',
    pronunciation: '가치 해요',
    distractor: '가티 해요',
    explanation: '‘같이’의 ㅌ을 그대로 [티]로 읽지 않고 [치]로 읽어요.',
    sourceUrl: _palatal,
  ),
  QuizItem(
    id: 'basic-talk-03',
    category: TrainingCategory.basic,
    group: '일상 대화',
    text: '좋아요',
    pronunciation: '조아요',
    distractor: '조하요',
    explanation: '‘좋아요’는 [조아요]로 읽어요. ‘좋-’ 뒤에 모음으로 시작하는 어미가 와서 ㅎ이 나지 않아요.',
    sourceUrl: _h,
  ),
  QuizItem(
    id: 'basic-talk-04',
    category: TrainingCategory.basic,
    group: '일상 대화',
    text: '많아요',
    pronunciation: '마나요',
    distractor: '만하요',
    explanation: '‘많아요’는 [마나요]로 읽어요. ㄶ에서 ㅎ이 나지 않고 ㄴ을 뒤 모음에 이어 읽어요.',
    sourceUrl: _h,
  ),
  QuizItem(
    id: 'basic-life-01',
    category: TrainingCategory.basic,
    group: '외출·생활',
    text: '옷을 사요',
    pronunciation: '오슬 사요',
    distractor: '오들 사요',
    explanation: '‘옷을’은 [오슬]로 읽어요. 받침 ㅅ을 조사 ‘을’의 첫소리로 이어 읽어요.',
    sourceUrl: _liaison,
  ),
  QuizItem(
    id: 'basic-life-02',
    category: TrainingCategory.basic,
    group: '외출·생활',
    text: '꽃이 펴요',
    pronunciation: '꼬치 펴요',
    distractor: '꼬시 펴요',
    explanation: '‘꽃이’는 [꼬치]로 읽어요. 꽃의 받침 ㅊ을 조사 ‘이’의 첫소리로 옮겨요.',
    sourceUrl: _liaison,
  ),
  QuizItem(
    id: 'basic-life-03',
    category: TrainingCategory.basic,
    group: '외출·생활',
    text: '학교에 가요',
    pronunciation: '학꾜에 가요',
    distractor: '학교에 가요',
    explanation: '‘학교’의 ㄱ 받침 뒤에서 ㄱ을 된소리로 읽어 [학꾜]가 돼요.',
    sourceUrl: _liaison,
  ),
  QuizItem(
    id: 'basic-life-04',
    category: TrainingCategory.basic,
    group: '외출·생활',
    text: '식사해요',
    pronunciation: '식싸해요',
    distractor: '식사해요',
    explanation: '‘식사’는 [식싸]로 읽어요. 받침 ㄱ 뒤의 ㅅ이 된소리 ㅆ으로 나요.',
    sourceUrl: _liaison,
  ),
  QuizItem(
    id: 'extended-order-01',
    category: TrainingCategory.extended,
    group: '주문·요청',
    text: '국물을 더 주세요',
    pronunciation: '궁무를 더 주세요',
    distractor: '국무를 더 주세요',
    explanation: '‘국물’은 [궁물], ‘국물을’은 [궁무를]로 읽어요. ㄱ이 ㅁ 앞에서 ㅇ으로 바뀌어요.',
    sourceUrl: _nasal,
  ),
  QuizItem(
    id: 'extended-order-02',
    category: TrainingCategory.extended,
    group: '주문·요청',
    text: '밥을 더 주세요',
    pronunciation: '바블 더 주세요',
    distractor: '바플 더 주세요',
    explanation: '‘밥을’의 ㅂ을 뒤로 이어 [바블]로 읽어요. ㅍ 소리로 바꾸지 않아요.',
    sourceUrl: _liaison,
  ),
  QuizItem(
    id: 'extended-order-03',
    category: TrainingCategory.extended,
    group: '주문·요청',
    text: '꽃을 하나 주세요',
    pronunciation: '꼬츨 하나 주세요',
    distractor: '꼬슬 하나 주세요',
    explanation: '‘꽃을’은 [꼬츨]로 읽어요. 조사 ‘을’ 앞에서는 받침 ㅊ을 그대로 이어 읽어요.',
    sourceUrl: _liaison,
  ),
  QuizItem(
    id: 'extended-order-04',
    category: TrainingCategory.extended,
    group: '주문·요청',
    text: '옷을 보여 주세요',
    pronunciation: '오슬 보여 주세요',
    distractor: '오들 보여 주세요',
    explanation: '‘옷을’의 읽는 소리는 [오슬]이에요. [옫]으로 끝나는 ‘옷’과 구분해 연습해요.',
    sourceUrl: _liaison,
  ),
  QuizItem(
    id: 'extended-life-01',
    category: TrainingCategory.extended,
    group: '장소·설명',
    text: '학교에서 만나요',
    pronunciation: '학꾜에서 만나요',
    distractor: '학교에서 만나요',
    explanation: '‘학교에서’의 ‘교’는 ㄱ 받침 뒤에서 된소리가 나 [학꾜에서]로 읽어요.',
    sourceUrl: _liaison,
  ),
  QuizItem(
    id: 'extended-life-02',
    category: TrainingCategory.extended,
    group: '장소·설명',
    text: '국물이 뜨거워요',
    pronunciation: '궁무리 뜨거워요',
    distractor: '국무리 뜨거워요',
    explanation: '‘국물이’는 [궁무리]로 읽어요. ‘국물’의 비음화와 조사 ‘이’ 앞의 연음을 함께 연습해요.',
    sourceUrl: _nasal,
  ),
  QuizItem(
    id: 'extended-life-03',
    category: TrainingCategory.extended,
    group: '장소·설명',
    text: '난로가 따뜻해요',
    pronunciation: '날로가 따뜨태요',
    distractor: '난로가 따뜨태요',
    explanation: '‘난로’는 ㄴ이 ㄹ에 동화되어 [날로]로 읽어요. ‘따뜻해요’는 [따뜨태요]로 읽어요.',
    sourceUrl: _liquid,
  ),
  QuizItem(
    id: 'extended-life-04',
    category: TrainingCategory.extended,
    group: '장소·설명',
    text: '강릉으로 가요',
    pronunciation: '강능으로 가요',
    distractor: '강릉으로 가요',
    explanation: '‘강릉’은 [강능]으로 읽어요. 받침 ㅇ 뒤의 ㄹ이 ㄴ 소리로 바뀌어요.',
    sourceUrl: _liquid,
  ),
  QuizItem(
    id: 'business-request-01',
    category: TrainingCategory.business,
    group: '업무 대화',
    text: '자료를 같이 봐요',
    pronunciation: '자료를 가치 봐요',
    distractor: '자료를 가티 봐요',
    explanation: '‘같이’는 문장 안에서도 [가치]로 읽어요. 받침 ㅌ과 ‘이’가 만나 ㅊ 소리가 나요.',
    sourceUrl: _palatal,
  ),
  QuizItem(
    id: 'business-request-02',
    category: TrainingCategory.business,
    group: '업무 대화',
    text: '자료를 확인해요',
    pronunciation: '자료를 화긴해요',
    distractor: '자료를 확인해요',
    explanation: '‘확인’은 [화긴]으로 읽어요. ‘확인해요’에서도 ㄱ을 뒤 모음에 이어 [화긴해요]로 읽어요.',
    sourceUrl:
        'https://krdict.korean.go.kr/jpn/dicSearch/SearchView?ParaWordNo=73236&nation=jpn',
  ),
  QuizItem(
    id: 'business-request-03',
    category: TrainingCategory.business,
    group: '업무 대화',
    text: '오후에 연락해요',
    pronunciation: '오후에 열라캐요',
    distractor: '오후에 연라캐요',
    explanation: '‘연락’은 [열락]으로 읽어요. ‘연락해요’에서는 ㄱ과 ㅎ이 합쳐져 [열라캐요]가 돼요.',
    sourceUrl: _liquid,
  ),
  QuizItem(
    id: 'business-request-04',
    category: TrainingCategory.business,
    group: '업무 대화',
    text: '팀과 협력해요',
    pronunciation: '팀과 혐녀캐요',
    distractor: '팀과 협려캐요',
    explanation: '‘협력’은 [혐녁]으로 읽어요. ‘협력해요’에서는 ㄱ과 ㅎ도 합쳐져 [혐녀캐요]가 돼요.',
    sourceUrl:
        'https://www.korean.go.kr/front/onlineQna/onlineQnaView.do?mn_id=216&qna_seq=330091',
  ),
  QuizItem(
    id: 'business-guide-01',
    category: TrainingCategory.business,
    group: '일정·안내',
    text: '입구에서 만나요',
    pronunciation: '입꾸에서 만나요',
    distractor: '입구에서 만나요',
    explanation: '‘입구’는 [입꾸]로 읽어요. 받침 ㅂ 뒤의 ㄱ을 된소리 ㄲ으로 읽어요.',
    sourceUrl: _liaison,
  ),
  QuizItem(
    id: 'business-guide-02',
    category: TrainingCategory.business,
    group: '일정·안내',
    text: '식사 후에 만나요',
    pronunciation: '식싸 후에 만나요',
    distractor: '식사 후에 만나요',
    explanation: '‘식사’의 읽는 소리는 [식싸]예요. ㄱ 받침 뒤에서 ㅅ을 된소리로 읽어요.',
    sourceUrl: _liaison,
  ),
  QuizItem(
    id: 'business-guide-03',
    category: TrainingCategory.business,
    group: '일정·안내',
    text: '업무를 나눠요',
    pronunciation: '엄무를 나눠요',
    distractor: '업무를 나눠요',
    explanation: '‘업무’는 [엄무]로 읽어요. 받침 ㅂ이 뒤의 ㅁ을 만나 ㅁ 소리로 바뀌어요.',
    sourceUrl: _nasal,
  ),
  QuizItem(
    id: 'business-guide-04',
    category: TrainingCategory.business,
    group: '일정·안내',
    text: '입장을 알려 주세요',
    pronunciation: '입짱을 알려 주세요',
    distractor: '입장을 알려 주세요',
    explanation: '‘입장’은 [입짱]으로 읽어요. 받침 ㅂ 뒤의 ㅈ을 된소리 ㅉ으로 읽어요.',
    sourceUrl: _liaison,
  ),
];

List<String> groupsForCategory(TrainingCategory category) => [
  ...quizCatalog
      .where((item) => item.category == category)
      .map((item) => item.group)
      .toSet(),
];

List<QuizItem> itemsForGroup(TrainingCategory category, String group) =>
    quizCatalog
        .where((item) => item.category == category && item.group == group)
        .toList();
