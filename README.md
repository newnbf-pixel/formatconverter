# محوّل الصيغ (Format Converter) — Flutter

تطبيق Flutter يقوم بـ:
- **تحويل MHT/MHTML إلى PDF** (تلقائيًا بمجرد رفع الملف) — الميزة الرئيسية.
- تحويل الصور بين PNG / JPG / BMP / GIF.
- تحويل الملفات النصية بين TXT / CSV / JSON / MD، وتصديرها كـ PDF.
- كشف صيغة الملف المرفوع تلقائيًا، وعرض قائمة منسدلة بالصيغ الممكن التحويل إليها.
- إخبار المستخدم بمسار حفظ الملف الناتج بعد التحويل، مع زر لفتحه مباشرة.

---

## الخطوة 0 — لماذا لا يوجد رابط APK جاهز الآن؟

كتابة الكود شيء، وبناء ملف APK موقّع شيء آخر يحتاج بيئة فيها Flutter SDK + Android SDK
متصلة بالإنترنت لتنزيل الحزم. أنا كتبت لك **كل الكود جاهزًا**، وتبقى خطوة "البناء"
فقط، وهي 5 دقائق كما هو موضح تحت.

---

## الطريقة أ) البناء محليًا على جهازك (Windows / macOS / Linux)

### المتطلبات
1. تثبيت Flutter SDK: https://docs.flutter.dev/get-started/install
2. تشغيل `flutter doctor` والتأكد أن Android toolchain ✅

### الخطوات
```bash
# 1) أنشئ مشروع فلاتر فارغ (هذا يولّد مجلدي android/ و ios/ تلقائيًا بالإعدادات الصحيحة)
flutter create -t app --org com.example format_converter
cd format_converter

# 2) احذف lib/main.dart و pubspec.yaml الافتراضيين، وضع بدلًا منهما
#    الملفات المرفقة معي (pubspec.yaml + مجلد lib/ بالكامل)

# 3) نزّل الحزم
flutter pub get

# 4) (اختياري لكن يُنصح به) أضف صلاحية قراءة التخزين للأجهزة الأقدم من أندرويد 13
#    داخل android/app/src/main/AndroidManifest.xml قبل وسم <application>:
#    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
#    <uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>

# 5) بناء APK
flutter build apk --release

# الملف الناتج يكون هنا:
# build/app/outputs/flutter-apk/app-release.apk
```
انسخ هذا الملف لهاتفك وثبّته (فعّل "السماح بالتثبيت من مصادر غير معروفة" أول مرة).

---

## الطريقة ب) بناء سحابي بدون تنصيب أي برنامج (الأسهل)

### باستخدام Codemagic (مجاني لعدد محدود من البنايات شهريًا)
1. ارفع مجلد المشروع (بعد تنفيذ خطوات `flutter create` أعلاه ودمج الملفات) إلى
   مستودع GitHub جديد.
2. سجّل دخول على https://codemagic.io بحساب GitHub.
3. اختر المستودع → Flutter App → اختر "Android" كمنصة → ابدأ البناء (Start build).
4. بعد انتهاء البناء (~5-10 دقائق) ستجد رابط تنزيل ملف **APK** مباشرة من صفحة
   نتائج البناء (Artifacts).

### باستخدام GitHub Actions (مجاني بالكامل)
1. ارفع المشروع الى مستودع GitHub.
2. أضف ملف `.github/workflows/build.yml` بهذا المحتوى:
```yaml
name: Build APK
on: [push, workflow_dispatch]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.24.0'
      - run: flutter pub get
      - run: flutter build apk --release
      - uses: actions/upload-artifact@v4
        with:
          name: app-release
          path: build/app/outputs/flutter-apk/app-release.apk
```
3. بعد انتهاء الـ workflow، من تبويب **Actions** افتح آخر تشغيل، وحمّل ملف
   APK من قسم **Artifacts** — هذا هو رابط التنزيل المباشر لنسختك المبنية.

---

## ملاحظات تقنية مهمة

- **تحويل MHT → PDF**: يتم بتفكيك ملف MHT (وهو أرشيف MIME متعدد الأجزاء) واستخراج
  HTML الرئيسي وكل الصور/الموارد المرفقة به، ثم دمجها كلها في ملف HTML واحد
  مستقل بذاته (base64 data URI)، ثم تمريره لمكتبة `printing` التي تستخدم محرك
  WebView حقيقي على الجهاز لعرضه وتحويله PDF بنفس التنسيق تقريبًا.
- **حفظ الملفات**: تُحفظ داخل `Android/data/<package>/files/المحول` على التخزين
  الخارجي (لا تحتاج صلاحيات خاصة بفضل Scoped Storage في أندرويد الحديث)، ويظهر
  المسار الكامل للمستخدم داخل التطبيق مع زر لفتح الملف مباشرة.
- **صيغ الصور**: التحويل يدعم القراءة من PNG/JPG/BMP/GIF/WEBP/TGA والكتابة إلى
  PNG/JPG/BMP/GIF (تشفير WEBP غير مدعوم بمكتبات Dart النقية حاليًا).
- إذا أردت لاحقًا إضافة صيغ أخرى (مثل DOCX أو تحويل PDF→نص)، أخبرني وسأوسّع الكود.
