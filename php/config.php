<?php
/**
 * إدارة الأمن — إعدادات PHP
 */
declare(strict_types=1);

define('APP_ROOT', __DIR__);
define('DB_PATH', APP_ROOT . '/data/amn.sqlite');
define('UPLOAD_DIR', APP_ROOT . '/uploads');
define('TZ', 'Africa/Cairo');
define('SESSION_TTL', 21600);       // 6 ساعات
define('ONLINE_MS', 5 * 60 * 1000);
define('MAX_LOG_ROWS', 5000);
define('DEFAULT_ADMIN_USER', 'admin');
define('DEFAULT_ADMIN_PASS', 'admin123');

date_default_timezone_set(TZ);

if (!is_dir(UPLOAD_DIR)) {
    mkdir(UPLOAD_DIR, 0755, true);
}
if (!is_dir(dirname(DB_PATH))) {
    mkdir(dirname(DB_PATH), 0755, true);
}
