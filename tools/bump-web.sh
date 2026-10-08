#!/bin/sh
# شغّله قبل كل commit فيه تعديل على Index.html: يرفع رقم البناء فتحدّث كل الشاشات المفتوحة نفسها تلقائياً
cd "$(dirname "$0")/.." || exit 1
B=$(date +%s)
sed -i "s/^var BUILD=[0-9]*;/var BUILD=$B;/" Index.html
printf '{ "build": %s }\n' "$B" > web-version.json
echo "web build $B"
