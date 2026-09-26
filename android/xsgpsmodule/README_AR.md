# XsGPS — Android Test Module

هذا إصدار اختباري مخصص لتطبيق XsGPS التجريبي الذي نملك سورسه؛ ليس أداة دمج عامة لكل APK أو XAPK.

## الملفات

- `XsGPS-Test-Module.apk`: موديول Xposed تجريبي يضم واجهة XsGPS وموقع Android التجريبي الرسمي.
- `XsGPS-Demo.apk`: التطبيق التجريبي الوحيد الذي يتعامل معه الموديول حاليًا (`com.xsgps.android`).

## التجربة

1. ثبّت الملفين على جهاز Android مخصص للاختبار.
2. من خيارات المطور، اختر **XsGPS Test Module** كتطبيق الموقع الوهمي (Mock Location).
3. في LSPosed، فعّل الموديول لتطبيق **XsGPS Demo** فقط ثم أعد تشغيل التطبيق التجريبي.
4. افتح التطبيق؛ يظهر زر «XS GPS» لفتح الموديول واختبار واجهته.
5. جرّب موقعًا محددًا ثم أوقف الموقع التجريبي لاستعادة GPS الحقيقي.

الموديول مقيّد عمدًا بتطبيقنا التجريبي؛ لا يعترض واجهات الموقع في التطبيقات الأخرى ولا يتجاوز فحوص الحماية. لا حاجة إلى تغيير توقيع التطبيق الأصلي حين يُدمج من سورسه.

## البناء

من جذر المستودع:

```bash
cd android
gradle :app:assembleDebug :xsgpsmodule:assembleDebug
```

أو شغّل GitHub Actions باسم **Build XsGPS Test Module** في الفرع `feature/owned-app-module-demo` لتحميل الملفين من Artifacts.
