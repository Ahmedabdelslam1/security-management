/*
 * تعديلات خاصة بالمعاينة المحلية (تطوير فقط).
 *
 * البرنامج يعرض صور العاملين عبر رابط مصغّرات Google Drive، وهو رابط غير موجود
 * خارج بيئة Google، فنحوّله إلى السيرفر المحلي الذي يعيد الملفات المحفوظة.
 */
(function () {
  window.imgThumb = function (id) {
    if (!id) return '';
    return '/__gas/file/' + encodeURIComponent(id);
  };
})();
