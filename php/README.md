# إدارة الأمن — نسخة PHP

بديل مستقل لـ Google Apps Script، بنفس واجهة الويب ونفس بروتوكول API المستخدم في تطبيق الأندرويد.

## التشغيل

```bash
php -S localhost:8080
```

- الواجهة: http://localhost:8080/index.html
- API: http://localhost:8080/api.php
- الدخول: `admin` / `admin123`

## الاتصال بتطبيق الأندرويد

في شاشة الدخول / الإعدادات بالتطبيق الصق رابط الـ API، مثال:

```
https://your-domain.com/php/api.php
```

أو رابط المجلد:

```
https://your-domain.com/php/
```

البروتوكول مطابق لـ `doPost` في Code.gs:

```json
{ "action": "login", "args": ["admin", "admin123"] }
{ "action": "bootstrap", "args": ["TOKEN"] }
```

## الهيكل

```
php/
├── index.html   الواجهة
├── api.php      API موحّد (action/args)
├── config.php
├── lib/         db + auth
├── data/        ملفات JSON
└── uploads/     الصور
```
