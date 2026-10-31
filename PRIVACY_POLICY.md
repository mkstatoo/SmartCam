# سیاست حریم خصوصی — کارآگاه دوربین

آخرین به‌روزرسانی: ۱۴۰۵/۰۸/۱۰

> **پیش‌نویس:** این متن بر پایهٔ رفتار واقعی نسخهٔ ۱٫۱ برنامه نوشته شده، ولی مشاورهٔ حقوقی نیست. قبل از انتشار، بخش «تماس» را کامل کنید و در صورت نیاز با مشاور حقوقی بررسی کنید. اگر برنامه یا سرور تغییر کرد این متن هم باید تغییر کند.

## خلاصه
«کارآگاه دوربین» تصویر دوربین‌هایی را که خودتان معرفی می‌کنید **روی همین گوشی** تحلیل می‌کند. **هیچ تصویر، ویدیو یا عکس رویدادی به سرور ما یا هیچ سرور دیگری فرستاده نمی‌شود.** برای ساخت حساب کاربری، فعال‌سازی نسخهٔ پرو و بهبود برنامه، مقدار محدودی اطلاعات به سرور ما می‌رود که در زیر آمده است. برنامه تبلیغ و ردیاب شخص ثالث ندارد.

## اطلاعاتی که به سرور ما فرستاده می‌شود
- **حساب:** ایمیل یا شمارهٔ موبایل، نام (اختیاری) و رمز عبور (فقط به‌صورت هش‌شدهٔ یک‌طرفه ذخیره می‌شود).
- **دستگاه:** شناسهٔ تصادفی نصب (نه شناسهٔ سخت‌افزاری)، مدل گوشی، نسخهٔ برنامه، فروشگاه نصب.
- **آمار عددی مصرف:** تعداد دوربین‌ها و تعداد رویدادها به تفکیک نوع (حرکت، آتش، دود، قطع ارتباط) در هر روز؛ فقط عدد، بدون زمان دقیق، نام دوربین یا تصویر.
- **خرید:** وضعیت نسخهٔ پرو و توکن خرید فروشگاه (برای تأیید خرید و جلوگیری از استفادهٔ همزمان چند حساب از یک خرید).
- **فنی:** آدرس IP در درخواست‌های شبکه و زمان آخرین فعالیت حساب.

## اطلاعاتی که هرگز ارسال نمی‌شود
تصویر و ویدیوی دوربین‌ها، عکس رویدادها، نام و آدرس و نام کاربری و رمز دوربین‌ها، محتوای تنظیمات دوربین‌ها.

## چه چیزی روی گوشی ذخیره می‌شود
- تنظیمات دوربین‌ها (نام، آدرس، نوع منبع، حساسیت‌ها، ناحیهٔ پایش).
- نام کاربری و رمز دوربین‌ها در حافظهٔ امن سیستم‌عامل (Android Keystore).
- رویدادها: زمان، نام دوربین، نوع، و عکس لحظهٔ رویداد.
- نشست ورود به حساب (در حافظهٔ امن) و آخرین وضعیت مجوز.

با حذف برنامه یا «پاک کردن همه» در بخش رویدادها، داده‌های محلی پاک می‌شود.

## استفاده از اطلاعات
ورود به حساب، فعال‌سازی و تأیید نسخهٔ پرو، جلوگیری از سوءاستفاده (مثلاً اشتراک یک خرید بین چند حساب)، پشتیبانی کاربر، و درک اینکه برنامه چقدر و چگونه استفاده می‌شود. اطلاعات فروخته یا برای تبلیغات به اشخاص ثالث داده نمی‌شود. تأیید خرید با سرور فروشگاهی (کافه‌بازار/مایکت) که از آن خرید کرده‌اید انجام می‌شود.

## نگهداری و حذف
اطلاعات حساب تا وقتی حساب دارید نگه‌داری می‌شود. با «حذف حساب» در صفحهٔ حساب کاربری، اطلاعات حساب، دستگاه‌ها و آمار شما از سرور پاک می‌شود. فقط توکن خرید بدون ارتباط با هویت شما برای جلوگیری از تقلب نگه‌داشته می‌شود.

## ارتباط شبکه‌ای
ارتباط با سرور ما فقط روی HTTPS است. برنامه به دوربین‌هایی وصل می‌شود که خودتان آدرس می‌دهید (و برای «یافتن خودکار ONVIF» به دستگاه‌های شبکهٔ محلی). دوربین‌های `http` رمزنگاری ندارند و امنیت آن مسیر با تنظیمات دوربین شماست.

## مجوزها و دلیل آن‌ها
| مجوز | دلیل |
|---|---|
| اینترنت / وضعیت شبکه / Wi‑Fi / multicast | اتصال به دوربین‌ها، حساب کاربری و یافتن دوربین‌های ONVIF |
| دوربین | فقط اگر «دوربین همین گوشی» را به‌عنوان منبع انتخاب کنید |
| اعلان‌ها و صفحهٔ هشدار تمام‌صفحه | اعلام حرکت، آتش و دود |
| لرزش | هشدار |
| WAKE_LOCK و سرویس پیش‌زمینه | ادامهٔ پایش هنگام خاموش‌بودن صفحه (نسخهٔ پرو) |

## مسئولیت کاربر
اگر دوربین مکانی را پایش می‌کنید که افراد دیگر در آن حضور دارند، مسئول رعایت قوانین حریم خصوصی و اطلاع‌رسانی به آن‌ها هستید. تشخیص آتش و دود این برنامه تقریبی است و **جایگزین دتکتور دود و حرارت استاندارد نیست**.

## کودکان
برنامه برای کودکان طراحی نشده و از آن‌ها آگاهانه اطلاعاتی جمع نمی‌کند.

## تغییرات
در صورت تغییر این سیاست، نسخهٔ جدید با تاریخ به‌روز در همین صفحه منتشر می‌شود.

## تماس
**[ایمیل یا راه تماس خودتان را اینجا بنویسید]**

---

# Privacy Policy — Detective Camera (English)

*Draft based on the app's actual behavior in v1.1; not legal advice. Fill in the contact field before publishing.*

Detective Camera analyzes the camera feeds you configure **entirely on your device**. **No images, video or event snapshots are ever sent to us or to any server.** To provide accounts, the Pro upgrade and to improve the app, a small amount of data is sent to our server. There are no ads or third-party trackers.

**Sent to our server:** account (e-mail or mobile number, optional name, password stored only as a one-way hash); device (random install ID, phone model, app version, install store); numeric usage counters per day (number of cameras and number of motion/fire/smoke/offline events — numbers only, no timestamps, camera names or images); purchase status and the store purchase token (to verify the purchase and prevent one purchase being used by several accounts); technical data (IP address of requests, last activity time).

**Never sent:** camera images/video, event snapshots, camera names, URLs, usernames or passwords.

**Stored on your device:** camera settings; camera credentials in Android Keystore-backed secure storage; event records with snapshots; your login session and the last license state.

**Use:** sign-in, verifying the Pro upgrade, abuse prevention, support, and understanding app usage. Data is not sold or shared for advertising. Purchases are verified with the store you bought from (Cafe Bazaar/Myket).

**Retention and deletion:** data is kept while you have an account. "Delete account" in the app removes your account, devices and usage data from our server; only an unlinked purchase token is retained to prevent fraud.

**Network:** communication with our server uses HTTPS only. Plain `http` camera streams are not encrypted.

**Permissions:** internet/network state/Wi‑Fi/multicast; camera (only if you choose the phone's own camera); notifications and full-screen alert; vibration; wake lock and foreground service (Pro background monitoring).

**Not a safety device:** fire and smoke detection is heuristic and does not replace certified smoke/heat detectors.

**Contact:** [your contact e-mail here]
