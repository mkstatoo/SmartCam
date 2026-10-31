/// تنظیمات زمان ساخت (با --dart-define در CI مقدار می‌گیرند).
class AppConfig {
  /// آدرس سرور حساب/مجوز، مثل https://api.example.ir (بدون / انتهایی).
  /// اگر خالی باشد برنامه بدون حساب کاربری و با همهٔ قابلیت‌ها باز اجرا می‌شود
  /// (فقط برای توسعه؛ ساخت release در CI بدون این مقدار رد می‌شود).
  static const String apiBase = String.fromEnvironment('API_BASE');

  static const String appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '1.1.0',
  );

  /// فروشگاهی که این نسخه برایش ساخته شده: bazaar | myket | direct
  static const String store = String.fromEnvironment(
    'IRAN_IAP_STORE',
    defaultValue: 'direct',
  );

  /// شناسهٔ محصول «پرو» در پنل بازار/مایکت (باید با DC_PRODUCTS سرور یکی باشد).
  static const String proProductId = 'pro_lifetime';

  /// آدرس عمومی سیاست حریم خصوصی (اختیاری؛ در صفحهٔ ثبت‌نام نشان داده می‌شود).
  static const String privacyUrl = String.fromEnvironment('PRIVACY_URL');

  static bool get accountsEnabled => apiBase.isNotEmpty;
  static bool get canBuy => store == 'bazaar' || store == 'myket';
  static String get storeLabel => switch (store) {
    'bazaar' => 'کافه‌بازار',
    'myket' => 'مایکت',
    _ => '',
  };
}
