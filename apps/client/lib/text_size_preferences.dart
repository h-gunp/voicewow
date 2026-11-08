import 'package:shared_preferences/shared_preferences.dart';

enum AppTextSize {
  basic('기본', 1),
  large('크게', 1.25),
  larger('더 크게', 1.5);

  const AppTextSize(this.label, this.factor);
  final String label;
  final double factor;
}

abstract interface class TextSizeStore {
  Future<AppTextSize> load();
  Future<void> save(AppTextSize value);
}

class PreferencesTextSizeStore implements TextSizeStore {
  static const key = 'voicemate.text-size.v1';
  late final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  @override
  Future<AppTextSize> load() async {
    final name = await _preferences.getString(key);
    return AppTextSize.values.firstWhere(
      (size) => size.name == name,
      orElse: () => AppTextSize.basic,
    );
  }

  @override
  Future<void> save(AppTextSize value) =>
      _preferences.setString(key, value.name);
}
