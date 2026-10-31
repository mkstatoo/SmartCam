# سیاست حریم خصوصی — کارآگاه دوربین

آخرین به‌روزرسانی: ۱۴۰۵/۰۸/۰۹

> **پیش‌نویس:** این متن بر پایهٔ رفتار واقعی نسخهٔ فعلی برنامه نوشته شده است، ولی مشاورهٔ حقوقی نیست. قبل از انتشار، بخش «تماس» را کامل کنید و در صورت نیاز با مشاور حقوقی بررسی کنید. اگر برنامه تغییر کرد (مثلاً تحلیل ابری یا آمار اضافه شد) این متن هم باید تغییر کند.

## خلاصه
«کارآگاه دوربین» تصویر دوربین‌هایی را که خودتان معرفی می‌کنید **روی همین گوشی** تحلیل می‌کند. برنامه هیچ تصویر، ویدیو یا اطلاعات شخصی‌ای را به سرور توسعه‌دهنده یا هیچ سرور دیگری نمی‌فرستد، و آمارگیر (Analytics)، تبلیغات یا ردیاب ندارد.

## چه اطلاعاتی روی گوشی ذخیره می‌شود
- **تنظیمات دوربین‌ها:** نام، آدرس اتصال، نوع منبع، حساسیت‌ها و ناحیهٔ پایش.
- **نام کاربری و رمز دوربین‌ها:** در حافظهٔ امن سیستم‌عامل (Android Keystore) نگه‌داری می‌شود.
- **رویدادها:** زمان، نام دوربین، نوع رویداد (حرکت/آتش/دود/قطع اتصال) و یک عکس از لحظهٔ رویداد.
- **تنظیمات برنامه:** مثل نوع صدای هشدار.

همهٔ این اطلاعات فقط در حافظهٔ داخلی برنامه روی گوشی شماست. با حذف برنامه یا با «پاک کردن همه» در بخش رویدادها از بین می‌روند.

## ارتباط شبکه‌ای
برنامه فقط به دوربین‌هایی وصل می‌شود که شما آدرسشان را وارد می‌کنید (و در «یافتن خودکار ONVIF» به دستگاه‌های همان شبکهٔ محلی). اگر آدرس دوربین روی اینترنت باشد، تصویر از مسیر اینترنت به گوشی می‌رسد؛ امنیت آن مسیر به تنظیمات دوربین شما بستگی دارد. دوربین‌های `http` رمزنگاری ندارند.

## مجوزها و دلیل آن‌ها
| مجوز | دلیل |
|---|---|
| اینترنت / وضعیت شبکه / Wi‑Fi / multicast | اتصال به دوربین‌ها و یافتن دوربین‌های ONVIF |
| دوربین | فقط اگر «دوربین همین گوشی» را به‌عنوان منبع انتخاب کنید |
| اعلان‌ها و تمام‌صفحه‌ی هشدار | اعلام حرکت، آتش و دود |
| لرزش | هشدار |
| WAKE_LOCK و سرویس پیش‌زمینه | ادامهٔ پایش هنگام خاموش‌بودن صفحه |

## اشتراک‌گذاری
هیچ اطلاعاتی با اشخاص ثالث به اشتراک گذاشته نمی‌شود، چون هیچ اطلاعاتی از گوشی خارج نمی‌شود.

## مسئولیت کاربر
اگر دوربین مکانی را پایش می‌کنید که افراد دیگر در آن حضور دارند، مسئول رعایت قوانین حریم خصوصی و اطلاع‌رسانی به آن‌ها هستید. تشخیص آتش و دود این برنامه تقریبی است و **جایگزین دتکتور دود و حرارت استاندارد نیست**.

## کودکان
برنامه برای کودکان طراحی نشده و از آن‌ها اطلاعاتی جمع نمی‌کند.

## تغییرات
در صورت تغییر این سیاست، نسخهٔ جدید با تاریخ به‌روز در همین صفحه منتشر می‌شود.

## تماس
**[ایمیل یا راه تماس خودتان را اینجا بنویسید]**

---

# Privacy Policy — Detective Camera (English)

*Draft based on the app's actual behavior; not legal advice. Fill in the contact field before publishing.*

Detective Camera analyzes the camera feeds you configure **entirely on your device**. It does not send any images, video or personal data to the developer or any server, and contains no analytics, ads or trackers.

**Stored on your device only:** camera settings (name, URL, source type, sensitivities, monitored zones); camera usernames/passwords (in Android Keystore-backed secure storage); event records with a snapshot image; app settings. Removing the app or using "Clear all" deletes them.

**Network:** the app connects only to the cameras you enter (and to devices on your local network for ONVIF discovery). Plain `http` camera streams are not encrypted.

**Permissions:** internet/network state/Wi‑Fi/multicast (connect to cameras, ONVIF discovery); camera (only if you choose the phone's own camera as a source); notifications and full-screen alert (motion/fire/smoke alerts); vibration; wake lock and foreground service (keep monitoring while the screen is off).

**Not a safety device:** fire and smoke detection is heuristic and does not replace certified smoke/heat detectors.

**Contact:** [your contact e-mail here]
