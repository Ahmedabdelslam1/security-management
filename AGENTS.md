# ملاحظات تشغيل المشروع (بيئة Base44)

هذا المستودع تطبيق **Google Apps Script** (إدارة الأمن — نظام إدارة العاملين اليومية).
التشغيل في المعاينة يتم محليًا دون أي تعديل على ملفات التطبيق.

## أي ملفات تُشغَّل فعلاً؟

- `Code.gs` : الخلفية (الدوال: `login`, `register`, `bootstrap`, `saveDay`, `settleWorkers`,
  `saveWorker`, `deleteWorkers`, `getImage`, `setUser`, `deleteUser`, `getMonitor`, `resetAll`, …).
- `Index.html` : **صفحة التطبيق المستخدمة في المعاينة** — وهي النسخة المضمّنة (ملف واحد) التي
  تنادي بالضبط الدوال الموجودة في `Code.gs`.
- `Index2.html` + `Styles.html` + `AppJs.html` : نسخة واجهة **غير متوافقة** مع `Code.gs` الحالي؛
  فهي تنادي دوالًا غير موجودة فيه (`apiLogin`, `apiGetWorkers`, `apiSaveDay`, `apiSession`, …).
  لذلك لا تُستخدم في التشغيل حتى تُزامَن مع الخلفية.

## التشغيل

```bash
docker compose -f docker-compose.base44.yml up -d                 # التشغيل
docker compose -f docker-compose.base44.yml restart web           # بعد تعديل devserver/server.js أو gas-env.js
```

- `devserver/server.js` : سيرفر Node بدون مكتبات خارجية. يقدّم `Index.html`، ويحوّل أي كود
  جافاسكربت مضمّن إلى ملف خارجي (`/__gas/inline/N.js`) لأن دوال الطباعة تحتوي النص
  `"<script>"` داخل سلاسل نصية، وهو ما يفسد تحليل الصفحة عند تمريرها عبر وسيط المعاينة.
  كما يحلّ تعليمات `include('…')` لو استُخدمت صفحة بقوالب لاحقًا.
- `devserver/gas-env.js` : محاكاة محلية لخدمات Apps Script المستخدمة فعليًا (`SpreadsheetApp`,
  `DriveApp`, `PropertiesService`, `CacheService`, `Utilities`, `LockService`). البيانات في حجم
  Docker باسم `gas-data` عند `/data/db.json` — وليست داخل المستودع.
- `devserver/gas-shim.js` : يعرّف `google.script.run` في المتصفح ويحوّل النداءات إلى `/__gas/run`،
  ويعيد تحميل المعاينة تلقائيًا عند تغيير أي ملف مصدر.
- `devserver/gas-preview-patch.js` : توجيه روابط صور العاملين إلى `/__gas/file/<id>` بدل روابط
  Google Drive (للمعاينة فقط).

### نقاط مهمة

- تعديلات `Code.gs` و`Index.html` وملفّي الجسر تُلتقط بدون إعادة تشغيل؛ تعديل `server.js`
  أو `gas-env.js` يحتاج `restart web`.
- الجلسات محفوظة في ذاكرة العملية، فأي إعادة تشغيل تعني إعادة تسجيل الدخول.
- الدخول الافتراضي للمدير: `admin` / `admin123` (يُنشَأ تلقائيًا عند أول دخول).

### التحقق

```bash
curl -s localhost:3000/__gas/health
curl -s -X POST localhost:3000/__gas/run -H 'Content-Type: application/json' \
  -d '{"fn":"login","args":["admin","admin123"]}'
```

## النشر

المعاينة المحلية لا تستبدل النشر: النشر الفعلي على Apps Script كما في `README.txt`
(لصق الملفات + نشر كتطبيق ويب)، وحينها يستخدم Google Sheets وDrive الحقيقيين.
المحاكاة هنا للتطوير والعرض فقط.
