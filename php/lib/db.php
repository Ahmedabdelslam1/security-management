<?php
declare(strict_types=1);
require_once __DIR__ . '/../config.php';

if (!function_exists('mb_substr')) {
    function mb_substr($s, $start, $len = null) {
        $s = (string)$s;
        if ($len === null) return substr($s, $start);
        return substr($s, $start, $len);
    }
}
if (!function_exists('mb_strlen')) {
    function mb_strlen($s) { return strlen((string)$s); }
}


/**
 * تخزين JSON بسيط (بديل SQLite عند عدم توفر PDO)
 * كل جدول = ملف JSON في data/
 */

function dataFile(string $name): string {
    return dirname(DB_PATH) . '/' . $name . '.json';
}

function readTable(string $name): array {
    $f = dataFile($name);
    if (!is_file($f)) return [];
    $j = json_decode((string)file_get_contents($f), true);
    return is_array($j) ? $j : [];
}

function writeTable(string $name, array $rows): void {
    $f = dataFile($name);
    $dir = dirname($f);
    if (!is_dir($dir)) mkdir($dir, 0755, true);
    $tmp = $f . '.tmp.' . getmypid();
    file_put_contents($tmp, json_encode(array_values($rows), JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT));
    rename($tmp, $f);
}

function withLock(callable $fn) {
    $lockFile = dirname(DB_PATH) . '/.lock';
    $fp = fopen($lockFile, 'c+');
    if (!$fp) throw new RuntimeException('تعذر قفل البيانات');
    if (!flock($fp, LOCK_EX)) {
        fclose($fp);
        throw new RuntimeException('تعذر قفل البيانات');
    }
    try {
        return $fn();
    } finally {
        flock($fp, LOCK_UN);
        fclose($fp);
    }
}

function ensureAdmin(): void {
    $users = readTable('users');
    if (count($users) > 0) return;
    $salt = bin2hex(random_bytes(16));
    $users[] = [
        'username' => DEFAULT_ADMIN_USER,
        'name' => 'مدير النظام',
        'salt' => $salt,
        'hash' => hashPass($salt, DEFAULT_ADMIN_PASS),
        'status' => 'approved',
        'role' => 'admin',
        'perms' => '{}',
        'lastLogin' => '',
        'lastActive' => '',
    ];
    writeTable('users', $users);
}

function hashPass(string $salt, string $pass): string {
    return hash('sha256', $salt . ':' . $pass);
}

function nowStr(): string {
    return date('Y-m-d H:i:s');
}

function todayStr(): string {
    return date('Y-m-d');
}

function propGet(string $key): ?string {
    $props = readTable('props');
    foreach ($props as $p) {
        if (($p['key'] ?? '') === $key) return $p['value'] ?? null;
    }
    return null;
}

function propSet(string $key, string $val): void {
    $props = readTable('props');
    $found = false;
    foreach ($props as &$p) {
        if (($p['key'] ?? '') === $key) {
            $p['value'] = $val;
            $found = true;
            break;
        }
    }
    unset($p);
    if (!$found) $props[] = ['key' => $key, 'value' => $val];
    writeTable('props', $props);
}

function num($v, $d = 0): float {
    if ($v === null || $v === '') return (float)$d;
    $x = (float)$v;
    return is_finite($x) ? $x : (float)$d;
}

function clip($v, int $n): string {
    return mb_substr(trim((string)($v ?? '')), 0, $n);
}

function validDate($d): bool {
    return (bool)preg_match('/^\d{4}-\d{2}-\d{2}$/', (string)$d);
}

function parsePerms($p): array {
    if (is_array($p)) return $p;
    $o = json_decode((string)($p ?: '{}'), true);
    return is_array($o) ? $o : [];
}

function publicUser(array $u): array {
    return [
        'name' => $u['name'],
        'username' => $u['username'],
        'role' => $u['role'],
        'status' => $u['status'],
        'perms' => parsePerms($u['perms'] ?? '{}'),
    ];
}

function logAction(string $user, string $action, string $page, string $details = ''): void {
    $log = readTable('log');
    $log[] = [
        'id' => count($log) ? (max(array_column($log, 'id') ?: [0]) + 1) : 1,
        'time' => nowStr(),
        'user' => clip($user, 60),
        'action' => clip($action, 60),
        'page' => clip($page, 60),
        'details' => clip($details, 200),
    ];
    if (count($log) > MAX_LOG_ROWS) {
        $log = array_slice($log, -MAX_LOG_ROWS);
    }
    writeTable('log', $log);
}

function saveImg(string $dataUrl, string $label): string {
    if (!preg_match('#^data:(image/(?:png|jpeg|webp));base64,([A-Za-z0-9+/=]+)$#', $dataUrl, $m)) {
        throw new RuntimeException('صيغة الصورة غير مدعومة');
    }
    if (strlen($m[2]) > 3000000) {
        throw new RuntimeException('حجم الصورة كبير');
    }
    $bin = base64_decode($m[2], true);
    if ($bin === false) throw new RuntimeException('صورة غير صالحة');
    $ext = $m[1] === 'image/png' ? 'png' : ($m[1] === 'image/webp' ? 'webp' : 'jpg');
    $id = $label . '-' . time() . '-' . bin2hex(random_bytes(4)) . '.' . $ext;
    $path = UPLOAD_DIR . '/' . $id;
    if (!is_dir(UPLOAD_DIR)) mkdir(UPLOAD_DIR, 0755, true);
    if (file_put_contents($path, $bin) === false) {
        throw new RuntimeException('تعذر حفظ الصورة');
    }
    return $id;
}

function trashImg(?string $id): void {
    if (!$id) return;
    $path = UPLOAD_DIR . '/' . $id;
    if (is_file($path)) @unlink($path);
}

function imgDataUrl(?string $id): ?string {
    if (!$id) return null;
    $path = UPLOAD_DIR . '/' . $id;
    if (!is_file($path)) return null;
    $bin = file_get_contents($path);
    $ext = strtolower(pathinfo($path, PATHINFO_EXTENSION));
    $mime = $ext === 'png' ? 'image/png' : ($ext === 'webp' ? 'image/webp' : 'image/jpeg');
    return 'data:' . $mime . ';base64,' . base64_encode($bin);
}

function weekdayAr(string $d): string {
    $days = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];
    $ts = strtotime($d . ' 12:00:00');
    return $days[(int)date('w', $ts)];
}

/** تهيئة عند أول طلب */
function bootStorage(): void {
    static $done = false;
    if ($done) return;
    $done = true;
    if (!is_dir(dirname(DB_PATH))) mkdir(dirname(DB_PATH), 0755, true);
    if (!is_dir(UPLOAD_DIR)) mkdir(UPLOAD_DIR, 0755, true);
    ensureAdmin();
}
