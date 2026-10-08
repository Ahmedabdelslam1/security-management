# النشر التلقائي على Google Apps Script

بعد الإعداد (مرة واحدة)، أي تعديل على `Code.gs` أو `Index.html` يُرفع إلى GitHub
يُحدّث السكريبت ورابط التطبيق تلقائيًا (خلال دقيقة تقريبًا).

## الإعداد لمرة واحدة
1. فعّل Apps Script API: https://script.google.com/home/usersettings ← **Google Apps Script API: On**
2. على جهاز به Node.js:
   ```
   npm install -g @google/clasp
   clasp login
   ```
   سيُنشئ الملف `~/.clasprc.json` (على ويندوز: `C:\Users\<اسمك>\.clasprc.json`).
3. من مشروع Apps Script: **Project Settings ← Script ID** (انسخه).
4. رقم النشر: **Deploy ← Manage deployments** ← انسخ **Deployment ID** الخاص بتطبيق الويب (يبدأ بـ `AKfycb...`).
5. في GitHub: **Settings ← Secrets and variables ← Actions ← New repository secret**، وأضف:

| الاسم | القيمة |
|---|---|
| `CLASPRC_JSON` | محتوى الملف `~/.clasprc.json` كاملًا |
| `SCRIPT_ID` | رقم السكريبت (الخطوة 3) |
| `DEPLOYMENT_ID` | رقم النشر (الخطوة 4) |

6. من تبويب **Actions** شغّل `Deploy to Google Apps Script` يدويًا مرة للتجربة.

> ملاحظة: يبقى الرابط (`/exec`) كما هو، ولا يحتاج التطبيق إلى إعادة نشر يدوي.
> الجلسة محفوظة، فلا يتم تسجيل الخروج عند التحديث.

## تحديث تلقائي للسكريبت من GitHub (بدون clasp)
مرة واحدة فقط: في Apps Script امسح كل محتوى ملف Code.gs والصق بدلاً منه محتوى `loader/Loader.gs`، ثم Deploy ← Manage deployments ← Edit ← New version.
بعدها أي تعديل على `Code.gs` و`Index.html` في GitHub يصل تلقائياً خلال ~5 دقائق (التخزين المؤقت).
ملاحظة: المحمّل ينفّذ الكود الموجود في مستودعك، فاحرص على حماية الحساب. لو أضفت دالة جديدة لـ apiMap_ أضف اسمها في `FN_` وغلافها في Loader.gs (يتطلب لصق المحمّل مرة أخرى).

### لو ظهر خطأ "تعذر تحميل الكود من GitHub"
في محرر Apps Script اختر الدالة `authorize` من القائمة أعلى الصفحة واضغط ▶ تشغيل، ثم وافق على الأذونات (مراجعة الأذونات ← حسابك ← متقدم ← السماح). ثم أعد نشر Deploy ← New version. الرسالة تعرض الآن سبب الفشل بعد النقطتين.
