import 'package:iran_iap/iran_iap.dart';

import '../config.dart';
import 'account_manager.dart';
import 'api_client.dart';

class BillingResult {
  const BillingResult.ok() : ok = true, cancelled = false, message = null;
  const BillingResult.cancelled() : ok = false, cancelled = true, message = null;
  const BillingResult.fail(this.message) : ok = false, cancelled = false;
  final bool ok;
  final bool cancelled;
  final String? message;
}

/// پرداخت درون‌برنامه‌ای (بازار/مایکت) + تأیید خرید در سرور خودمان.
/// فروشگاه هنگام ساخت (IRAN_IAP_STORE) انتخاب می‌شود. در نسخهٔ direct خرید نیست.
class Billing {
  static const String _myketKey = String.fromEnvironment('MYKET_PUBLIC_KEY');

  IranIap? _iap;

  bool get available => AppConfig.canBuy;

  Future<IranIap> _client() async {
    final iap = _iap ??= IranIap(
      config: IranIapConfig(storePublicKey: _myketKey.isEmpty ? null : _myketKey),
    );
    await iap.initialize();
    return iap;
  }

  /// قیمت نمایشی محصول پرو از خود فروشگاه (null اگر در دسترس نبود).
  Future<String?> proPrice() async {
    if (!available) return null;
    try {
      final iap = await _client();
      final list = await iap.queryProducts({
        AppConfig.proProductId,
      }, type: IapProductType.inApp);
      return list.isEmpty ? null : list.first.price;
    } catch (_) {
      return null;
    }
  }

  Future<BillingResult> buyPro() async {
    if (!available) return const BillingResult.fail('خرید در این نسخه فعال نیست');
    try {
      final iap = await _client();
      final outcome = await iap.purchase(
        IapPurchaseRequest(
          productId: AppConfig.proProductId,
          type: IapProductType.inApp,
          payload: '${account.user?.id ?? 0}',
        ),
      );
      if (outcome is PurchaseCancelled) return const BillingResult.cancelled();
      if (outcome is PurchaseCompleted) {
        final p = outcome.purchase;
        await account.verifyPurchase(
          store: AppConfig.store,
          productId: p.productId,
          purchaseToken: p.token,
          orderId: p.orderId ?? '',
        );
        return const BillingResult.ok();
      }
      return const BillingResult.fail('نتیجهٔ نامشخص از فروشگاه');
    } on IapException catch (e) {
      return BillingResult.fail(_iapMessage(e));
    } on ApiException catch (e) {
      // پول پرداخت شده ولی تأیید سرور نشد: کاربر با «بازیابی خرید» دوباره امتحان کند
      return BillingResult.fail(
        e.isNetwork || e.status == 503
            ? '${e.message}\nپرداخت شما ثبت شده؛ بعداً «بازیابی خرید» را بزنید.'
            : e.message,
      );
    }
  }

  /// خریدهای قبلی همین حساب فروشگاه را به سرور می‌دهد (نصب مجدد، گوشی جدید).
  Future<BillingResult> restore() async {
    if (!available) return const BillingResult.fail('خرید در این نسخه فعال نیست');
    try {
      final iap = await _client();
      final owned = await iap.queryPurchases(type: IapProductType.inApp);
      final mine = owned.where((p) => p.productId == AppConfig.proProductId);
      if (mine.isEmpty) {
        return const BillingResult.fail('خریدی در حساب فروشگاه شما پیدا نشد');
      }
      for (final p in mine) {
        await account.verifyPurchase(
          store: AppConfig.store,
          productId: p.productId,
          purchaseToken: p.token,
          orderId: p.orderId ?? '',
        );
      }
      return const BillingResult.ok();
    } on IapException catch (e) {
      return BillingResult.fail(_iapMessage(e));
    } on ApiException catch (e) {
      return BillingResult.fail(e.message);
    }
  }

  String _iapMessage(IapException e) => switch (e.code) {
    IapErrorCode.storeNotInstalled =>
      'برنامهٔ ${AppConfig.storeLabel} روی گوشی نصب نیست یا وارد حسابش نشده‌اید',
    IapErrorCode.serviceUnavailable =>
      'سرویس ${AppConfig.storeLabel} در دسترس نیست؛ بعداً دوباره امتحان کنید',
    IapErrorCode.operationInProgress => 'یک عملیات پرداخت در حال انجام است',
    _ => 'خطای پرداخت (${e.code.name})',
  };
}

final Billing billing = Billing();
