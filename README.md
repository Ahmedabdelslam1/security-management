# إدارة الأمن — نظام حضور العاملين (ويب + أندرويد + PHP)

نظام واحد لإدارة حضور وتسويات العاملين ودفتر البوابة، بثلاث واجهات تتصل بنفس بروتوكول الـ API.

```
┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐
│  Index.html     │   │  Flutter APK    │   │  php/index.html │
│  (ويب GAS)      │   │  (أندرويد)      │   │  (ويب PHP)      │
└────────┬────────┘   └────────┬────────┘   └────────┬────────┘
         │ google.script.run   │ POST JSON            │ fetch
         │                     │ {action, args}       │
         ▼                     ▼                      ▼
┌─────────────────────────────┐            ┌──────────────────┐
│  Code.gs  (doGet + doPost)  │            │  php/api.php     │
│  Google Sheets + Drive      │            │  JSON files      │
└─────────────────────────────┘            └──────────────────┘
```

**بروتوكول موحّد للموبايل وأي سيرفر خارجي:**

```json
POST { "action": "login", "args": ["admin", "admin123"] }
→ { "ok": true, "data": { "token": "..." } }

POST { "action": "bootstrap", "args": ["TOKEN"] }
→ { "ok": true, "data": { "user": ..., "workers": ..., "att": ... } }
```

## محتويات المستودع

| المسار | الوصف |
|---|---|
| `Code.gs` | سيرفر Google Apps Script — Sheets + Drive + بوابة JSON (`doPost`) للأندرويد |
| `Index.html` | واجهة الويب داخل Apps Script |
| `appsscript.json` | إعدادات مشروع Apps Script |
| `flutter_app/` | تطبيق أندرويد (Flutter) — يتصل بـ GAS أو PHP |
| `php/` | نسخة PHP كاملة (بديل مستقل بدون Google) |
| `.github/workflows/` | نشر تلقائي لـ Apps Script + بناء APK |
| `dev-server/` | سيرفر تطوير محلي للمطورين |

## 1) نسخة الويب (Google Apps Script)

1. أنشئ مشروعًا في [script.google.com](https://script.google.com)
2. الصق `Code.gs` و `Index.html` و `appsscript.json`
3. شغّل `setup()` مرة واحدة
4. **نشر ← نشر كتطبيق ويب** (تنفيذ: أنا — وصول: أي شخص)
5. الرابط المنتهي بـ `/exec` هو رابط السيرفر للتطبيق والموبايل

أو ارفع على هذا المستودع مع إعداد أسرار النشر (راجع `DEPLOY.md`) ليُنشر تلقائيًا عبر GitHub Actions.

**الدخول الافتراضي:** `admin` / `admin123`

## 2) تطبيق الأندرويد (APK)

1. ارفع أي تعديل على `flutter_app/` → يعمل workflow **بناء تطبيق أندرويد (APK)**
2. من تبويب **Actions** حمّل الـ Artifact `security-management-apk`
3. ثبّت `app-debug.apk` على الموبايل
4. في أول تشغيل:
   - **رابط GAS:** الصق رابط `/exec`
   - **رابط PHP:** الصق رابط مجلد الـ PHP أو `.../api.php`

التطبيق يتعرف تلقائيًا على نوع السيرفر ويرسل نفس طلبات `{action, args}`.

## 3) نسخة PHP (بديل مستقل)

```bash
cd php
php -S localhost:8080
```

- الواجهة: http://localhost:8080/index.html
- الـ API: http://localhost:8080/api.php
- الدخول: `admin` / `admin123`

يمكن لتطبيق الأندرويد الاتصال بهذا الـ API مباشرة (نفس البروتوكول).

> ملاحظة: بيانات PHP منفصلة عن Google Sheets — اختر سيرفرًا واحدًا للتشغيل الفعلي
> (GAS للإنتاج المشترك، أو PHP لاستضافة خاصة).

## الشاشات المشتركة

- الحضور والتسوية والمرتبات
- العاملين (صور البطاقة والصورة الشخصية)
- التقارير وخطاب الاعتماد
- دفتر دخول البوابة
- المستخدمين والصلاحيات والمتابعة (للمدير)

## النشر التلقائي

| الحدث | النتيجة |
|---|---|
| تعديل `Code.gs` أو `Index.html` على `main` | نشر إلى Google Apps Script (إن وُجدت الأسرار) |
| تعديل داخل `flutter_app/` | بناء APK جديد في Actions |

تفاصيل إعداد clasp: [`DEPLOY.md`](DEPLOY.md)
