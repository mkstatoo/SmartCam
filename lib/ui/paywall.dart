import 'package:flutter/material.dart';

import '../config.dart';
import '../services/account_manager.dart';
import '../services/billing.dart';

/// برگهٔ ارتقا به «پرو». [reason] توضیح می‌دهد چرا نمایش داده شد.
Future<void> showPaywall(BuildContext context, {String? reason}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Directionality(
      textDirection: TextDirection.rtl,
      child: _PaywallSheet(reason: reason),
    ),
  );
}

class _PaywallSheet extends StatefulWidget {
  const _PaywallSheet({this.reason});
  final String? reason;

  @override
  State<_PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends State<_PaywallSheet> {
  String? _price;
  bool _busy = false;
  String? _msg;

  @override
  void initState() {
    super.initState();
    billing.proPrice().then((p) {
      if (mounted) setState(() => _price = p);
    });
  }

  Future<void> _run(Future<BillingResult> Function() f) async {
    setState(() {
      _busy = true;
      _msg = null;
    });
    final r = await f();
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('نسخهٔ پرو فعال شد. ممنون از حمایت شما!')),
      );
    } else if (!r.cancelled) {
      setState(() => _msg = r.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.workspace_premium, color: cs.primary, size: 32),
                const SizedBox(width: 10),
                const Text(
                  'ارتقا به نسخهٔ پرو',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            if (widget.reason != null) ...[
              const SizedBox(height: 10),
              Text(widget.reason!, style: const TextStyle(color: Colors.amberAccent)),
            ],
            const SizedBox(height: 14),
            const _Feature('دوربین نامحدود', 'رایگان: ۲ دوربین'),
            const _Feature('تشخیص آتش و دود با آژیر', 'رایگان: فقط تشخیص حرکت'),
            const _Feature('تعیین ناحیهٔ پایش و نادیده‌گرفتن', 'رایگان: کل تصویر'),
            const _Feature(
              'پایش در پس‌زمینه و با صفحهٔ خاموش',
              'رایگان: فقط وقتی برنامه باز است',
            ),
            const _Feature('تاریخچهٔ بلندتر رویدادها', 'رایگان: ۲۰ رویداد'),
            const SizedBox(height: 6),
            const Text(
              'یک‌بار پرداخت؛ بدون اشتراک ماهانه.',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 16),
            if (AppConfig.canBuy) ...[
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: _busy ? null : () => _run(billing.buyPro),
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_price == null ? 'خرید نسخهٔ پرو' : 'خرید نسخهٔ پرو — $_price'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _run(billing.restore),
                  child: const Text('بازیابی خرید قبلی'),
                ),
              ),
            ] else
              Text(
                'خرید فقط در نسخهٔ کافه‌بازار و مایکت فعال است. '
                'برنامه را از یکی از آن دو نصب کنید.',
                style: TextStyle(color: cs.secondary),
              ),
            if (_msg != null) ...[
              const SizedBox(height: 10),
              Text(_msg!, style: const TextStyle(color: Colors.redAccent)),
            ],
            if (account.user != null) ...[
              const SizedBox(height: 10),
              Text(
                'حساب: ${account.user!.identifier}',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
                textDirection: TextDirection.ltr,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature(this.title, this.free);
  final String title;
  final String free;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.check_circle, color: Colors.greenAccent, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(free, style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
        ),
      ],
    ),
  );
}
