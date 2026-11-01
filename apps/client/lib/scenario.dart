class Scenario {
  final String id, title, subtitle;
  final int referenceLower, referenceUpper;
  const Scenario(
    this.id,
    this.title,
    this.subtitle,
    this.referenceLower,
    this.referenceUpper,
  );
  static const values = [
    Scenario('quiet', '일대일 대화', '가까운 상대와 말을 주고받는 상황이다.', 53, 75),
    Scenario('noisy', '1:1 대화', '소음이 있는 공간에서', 58, 80),
    Scenario('meeting', '발표', '여러 사람에게 내용을 전달하는 상황이다.', 68, 78),
    Scenario('auditorium', '강당 발표', '넓은 공간에서', 65, 75),
  ];
  String get displayTitle => switch (id) {
    'quiet' => '일대일 대화',
    'noisy' => '소음이 있는 1:1 대화',
    _ => title,
  };
}
