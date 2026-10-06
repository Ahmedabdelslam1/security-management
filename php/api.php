<?php
/**
 * إدارة الأمن — API (تخزين JSON)
 */
declare(strict_types=1);
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

require_once __DIR__ . '/lib/auth.php';
bootStorage();

$input = json_decode(file_get_contents('php://input') ?: '{}', true) ?: [];

/*
 * بروتوكول موحّد مع Google Apps Script (doPost) وتطبيق Flutter:
 *   {"action":"اسم_الدالة","args":[...]}
 *   في النداءات الموثّقة يكون الـ token أول عنصر في args (كما في Flutter Api.auth).
 *
 * بروتوكول الواجهة PHP (index.html):
 *   {"fn":"اسم_الدالة","args":[...],"token":"..."}
 */
$fn = (string)($input['action'] ?? $input['fn'] ?? '');
$args = is_array($input['args'] ?? null) ? $input['args'] : [];
$token = $input['token'] ?? null;

// استخراج الـ token من أول وسيطة للدوال التي تتوقع token أولًا (متوافق مع Flutter)
$needsTokenFirst = [
    'logout','changePassword','ping','addLog','bootstrap','saveDay','settleWorkers',
    'listPayroll','updatePayrollAdj','saveWorker','deleteWorkers','getImage',
    'setUser','addUser','resetUserPassword','deleteUser','getMonitor',
    'listGate','saveGate','deleteGate','getGateImage','resetAll',
];
if ($token === null && in_array($fn, $needsTokenFirst, true) && count($args) > 0) {
    $token = is_string($args[0]) ? $args[0] : (string)$args[0];
    $args = array_slice($args, 1);
}

try {
    $result = withLock(function () use ($fn, $args, $token) {
        return dispatch($fn, $args, $token);
    });
    echo json_encode(['ok' => true, 'data' => $result], JSON_UNESCAPED_UNICODE);
} catch (Throwable $e) {
    $msg = $e->getMessage();
    echo json_encode(['ok' => false, 'error' => $msg], JSON_UNESCAPED_UNICODE);
}

function dispatch(string $fn, array $args, ?string $token) {
    switch ($fn) {
        case 'login': return apiLogin($args[0] ?? '', $args[1] ?? '');
        case 'logout': return apiLogout($token);
        case 'register': return apiRegister($args[0] ?? '', $args[1] ?? '', $args[2] ?? '');
        case 'changePassword': return apiChangePassword($token, $args[0] ?? '', $args[1] ?? '');
        case 'ping': return apiPing($token);
        case 'bootstrap': return apiBootstrap($token);
        case 'saveDay': return apiSaveDay($token, $args[0] ?? '', $args[1] ?? []);
        case 'settleWorkers': return apiSettleWorkers($token, $args[0] ?? [], $args[1] ?? '', $args[2] ?? '', $args[3] ?? [], $args[4] ?? null);
        case 'listPayroll': return apiListPayroll($token, $args[0] ?? '', $args[1] ?? '');
        case 'updatePayrollAdj': return apiUpdatePayrollAdj($token, $args[0] ?? '', $args[1] ?? '', $args[2] ?? 0, $args[3] ?? 0, $args[4] ?? 0);
        case 'saveWorker': return apiSaveWorker($token, $args[0] ?? []);
        case 'deleteWorkers': return apiDeleteWorkers($token, $args[0] ?? []);
        case 'getImage': return apiGetImage($token, $args[0] ?? '', $args[1] ?? '');
        case 'setUser': return apiSetUser($token, $args[0] ?? '', $args[1] ?? []);
        case 'addUser': return apiAddUser($token, $args[0] ?? '', $args[1] ?? '', $args[2] ?? '', $args[3] ?? [], !empty($args[4]));
        case 'resetUserPassword': return apiResetUserPassword($token, $args[0] ?? '', $args[1] ?? '');
        case 'deleteUser': return apiDeleteUser($token, $args[0] ?? '');
        case 'getMonitor': return apiGetMonitor($token);
        case 'listGate': return apiListGate($token);
        case 'saveGate': return apiSaveGate($token, $args[0] ?? []);
        case 'deleteGate': return apiDeleteGate($token, $args[0] ?? '');
        case 'getGateImage': return apiGetGateImage($token, $args[0] ?? '', $args[1] ?? 0);
        case 'resetAll': return apiResetAll($token);
        case 'addLog': return apiAddLog($token, $args[0] ?? '', $args[1] ?? '', $args[2] ?? '');
        default: throw new RuntimeException('دالة غير معروفة: ' . $fn);
    }
}

const STATUSES = ['حضور', 'حضور + وقت اضافى', 'حضور + مبيت'];
const EXTRA_STATUSES = ['حضور + وقت اضافى', 'حضور + مبيت'];

/* ===================== دخول ===================== */
function apiLogin(string $username, string $password): array {
    ensureAdmin();
    $username = strtolower(clip($username, 40));
    $fkey = 'F_' . $username;
    $fails = (int)(propGet($fkey) ?: 0);
    if ($fails >= 5) throw new RuntimeException('تم تجاوز عدد المحاولات، حاول بعد 10 دقائق');
    $u = null;
    foreach (readTable('users') as $row) {
        if ($row['username'] === $username) { $u = $row; break; }
    }
    if (!$u || hashPass($u['salt'], (string)$password) !== $u['hash']) {
        propSet($fkey, (string)($fails + 1));
        throw new RuntimeException('بيانات الدخول غير صحيحة');
    }
    if ($u['status'] === 'pending') throw new RuntimeException('حسابك بانتظار موافقة الإدارة');
    if ($u['status'] !== 'approved') throw new RuntimeException('تم إيقاف هذا الحساب');
    propSet($fkey, '0');
    $token = createSession($username);
    updateUserFields($username, ['lastLogin' => nowStr(), 'lastActive' => (string)(int)(microtime(true) * 1000)]);
    logAction($u['name'], 'دخول', 'النظام', $username);
    return ['token' => $token];
}

function apiLogout(?string $token): bool {
    try {
        $u = auth($token);
        logAction($u['name'], 'خروج', 'النظام', $u['username']);
    } catch (Throwable $e) { /* */ }
    destroySession($token);
    return true;
}

function apiRegister(string $name, string $username, string $password): bool {
    $name = clip($name, 60);
    $username = strtolower(clip($username, 30));
    $password = (string)$password;
    if (mb_strlen($name) < 2) throw new RuntimeException('اكتب الاسم بالكامل');
    if (!preg_match('/^[a-z0-9_.]{3,30}$/', $username)) {
        throw new RuntimeException('اسم المستخدم: حروف إنجليزية صغيرة وأرقام فقط (3 أحرف على الأقل)');
    }
    if (strlen($password) < 6) throw new RuntimeException('كلمة المرور 6 أحرف على الأقل');
    ensureAdmin();
    $users = readTable('users');
    foreach ($users as $u) {
        if ($u['username'] === $username) throw new RuntimeException('اسم المستخدم مستخدم من قبل');
    }
    $pending = count(array_filter($users, fn($u) => ($u['status'] ?? '') === 'pending'));
    if ($pending >= 50) throw new RuntimeException('عدد الطلبات المعلقة كبير، تواصل مع الإدارة');
    $salt = bin2hex(random_bytes(16));
    $users[] = [
        'username' => $username, 'name' => $name, 'salt' => $salt,
        'hash' => hashPass($salt, $password), 'status' => 'pending', 'role' => 'user',
        'perms' => '{}', 'lastLogin' => '', 'lastActive' => '',
    ];
    writeTable('users', $users);
    logAction($name, 'طلب تسجيل', 'النظام', $username);
    return true;
}

function apiChangePassword(?string $token, string $oldPass, string $newPass): bool {
    $u = auth($token);
    $newPass = (string)$newPass;
    if (strlen($newPass) < 6) throw new RuntimeException('كلمة المرور الجديدة 6 أحرف على الأقل');
    $row = null;
    foreach (readTable('users') as $x) {
        if ($x['username'] === $u['username']) { $row = $x; break; }
    }
    if (!$row || hashPass($row['salt'], (string)$oldPass) !== $row['hash']) {
        throw new RuntimeException('كلمة المرور الحالية غير صحيحة');
    }
    $salt = bin2hex(random_bytes(16));
    updateUserFields($u['username'], ['salt' => $salt, 'hash' => hashPass($salt, $newPass)]);
    logAction($u['name'], 'تغيير كلمة المرور', 'النظام', $u['username']);
    return true;
}

function apiPing(?string $token): bool {
    $u = auth($token);
    updateUserFields($u['username'], ['lastActive' => (string)(int)(microtime(true) * 1000)]);
    return true;
}

function apiAddLog(?string $token, string $action, string $page, string $details): bool {
    $u = auth($token);
    logAction($u['name'], $action, $page, $details);
    return true;
}

/* ===================== bootstrap ===================== */
function lastSetMap(): array {
    $m = [];
    foreach (readTable('settlements') as $r) {
        $to = $r['to'] ?? '';
        if ($to && (!isset($m[$r['wid']]) || $to > $m[$r['wid']])) {
            $m[$r['wid']] = $to;
        }
    }
    return $m;
}

function workerOut(array $w, bool $full, array $ls): array {
    $legacy = (string)($w['lastSet'] ?? '');
    $led = $ls[$w['id']] ?? '';
    return [
        'id' => $w['id'], 'name' => $w['name'],
        'card' => $full ? ($w['card'] ?? '') : '',
        'phone' => $full ? ($w['phone'] ?? '') : '',
        'wage' => num($w['wage'] ?? 0),
        'hours' => num($w['hours'] ?? 8, 8) ?: 8,
        'lastSet' => $legacy > $led ? $legacy : $led,
        'hasCard' => !empty($w['cardImg']),
        'hasPhoto' => !empty($w['photo']),
    ];
}

function recValue(array $r, ?array $w): float {
    $h = $w ? ((num($r['wage'] ?? 0) ?: num($w['wage'] ?? 0)) / (num($w['hours'] ?? 8, 8) ?: 8)) : 0;
    return round((num($r['wage'] ?? 0) + num($r['xh'] ?? 0) * $h) * 100) / 100;
}

function allLocs(array $att = []): array {
    $seen = []; $list = [];
    foreach (readTable('locations') as $x) {
        $l = trim($x['name'] ?? '');
        if ($l && !isset($seen[$l])) { $seen[$l] = 1; $list[] = $l; }
    }
    foreach ($att as $r) {
        $l = trim((string)($r['loc'] ?? ''));
        if ($l && !isset($seen[$l])) { $seen[$l] = 1; $list[] = $l; }
    }
    return $list;
}

function apiBootstrap(?string $token): array {
    $u = auth($token);
    updateUserFields($u['username'], ['lastActive' => (string)(int)(microtime(true) * 1000)]);
    $full = can($u, 'workers');
    $ls = lastSetMap();
    $workers = array_map(fn($w) => workerOut($w, $full, $ls), readTable('workers'));
    $att = [];
    foreach (readTable('attendance') as $r) {
        $att[] = [
            'date' => $r['date'], 'wid' => $r['wid'], 'name' => $r['name'] ?? '',
            'status' => $r['status'] ?? '', 'loc' => $r['loc'] ?? '',
            'wage' => num($r['wage'] ?? 0), 'xh' => num($r['xh'] ?? 0),
            'notes' => $r['notes'] ?? '', 'settleId' => $r['settleId'] ?? '',
            'paidAmt' => num($r['paidAmt'] ?? 0),
        ];
    }
    $out = [
        'user' => publicUser($u),
        'workers' => $workers,
        'att' => $att,
        'locs' => allLocs($att),
    ];
    if ($u['role'] === 'admin') {
        $out['users'] = array_map('publicUser', readTable('users'));
    }
    return $out;
}

/* ===================== حضور ===================== */
function apiSaveDay(?string $token, string $date, array $recs): array {
    $u = auth($token, 'attendance');
    if (!validDate($date)) throw new RuntimeException('تاريخ غير صحيح');
    if (!is_array($recs)) throw new RuntimeException('بيانات غير صحيحة');
    $workers = [];
    foreach (readTable('workers') as $w) $workers[$w['id']] = $w;
    $paid = [];
    foreach (readTable('attendance') as $r) {
        if ($r['date'] === $date && !empty($r['settleId'])) {
            $paid[$r['wid']] = ['sid' => $r['settleId'], 'amt' => $r['paidAmt'] ?? ''];
        }
    }
    $fresh = []; $seen = [];
    foreach ($recs as $r) {
        $wid = (string)($r['wid'] ?? '');
        $w = $workers[$wid] ?? null;
        if (!$w || isset($seen[$w['id']])) continue;
        if (!in_array($r['status'] ?? '', STATUSES, true)) continue;
        $seen[$w['id']] = 1;
        $extra = in_array($r['status'], EXTRA_STATUSES, true);
        $fresh[] = [
            'date' => $date, 'wid' => $w['id'], 'name' => $w['name'],
            'status' => $r['status'], 'loc' => clip($r['loc'] ?? '', 80),
            'wage' => num($r['wage'] ?? 0) > 0 ? num($r['wage']) : num($w['wage'] ?? 0),
            'xh' => $extra ? max(0, num($r['xh'] ?? 0)) : 0,
            'notes' => clip($r['notes'] ?? '', 300),
            'settleId' => isset($paid[$w['id']]) ? $paid[$w['id']]['sid'] : '',
            'paidAmt' => isset($paid[$w['id']]) ? $paid[$w['id']]['amt'] : '',
        ];
    }
    $all = array_values(array_filter(readTable('attendance'), fn($r) => $r['date'] !== $date));
    $all = array_merge($all, $fresh);
    writeTable('attendance', $all);
    $known = array_column(readTable('locations'), 'name');
    $add = [];
    foreach ($fresh as $r) {
        if ($r['loc'] && !in_array($r['loc'], $known, true) && !in_array($r['loc'], $add, true)) $add[] = $r['loc'];
    }
    if ($add) {
        $locs = readTable('locations');
        foreach ($add as $n) $locs[] = ['name' => $n];
        writeTable('locations', $locs);
    }
    logAction($u['name'], 'حفظ يوم حضور', 'الحضور', $date . ' (' . count($fresh) . ')');
    $attOut = array_map(function ($r) {
        return [
            'date' => $r['date'], 'wid' => $r['wid'], 'name' => $r['name'],
            'status' => $r['status'], 'loc' => $r['loc'],
            'wage' => $r['wage'], 'xh' => $r['xh'], 'notes' => $r['notes'],
            'settleId' => $r['settleId'], 'paidAmt' => num($r['paidAmt']),
        ];
    }, $fresh);
    return ['att' => $attOut, 'locs' => allLocs(readTable('attendance'))];
}

/* ===================== تسوية ===================== */
function apiSettleWorkers(?string $token, array $ids, string $from, string $to, array $adj, $loc): array {
    $u = auth($token, ['workers', 'attendance']);
    if (!validDate($to)) throw new RuntimeException('تاريخ غير صحيح');
    if ($from && !validDate($from)) throw new RuntimeException('تاريخ غير صحيح');
    $from = $from ?: '0000-00-00';
    if (!is_array($ids) || !count($ids)) throw new RuntimeException('حدد عاملًا واحدًا على الأقل');
    $workers = [];
    foreach (readTable('workers') as $w) $workers[$w['id']] = $w;
    $sid = 's' . time() . random_int(0, 999);
    $att = readTable('attendance');
    $per = []; $keys = [];
    foreach ($att as &$r) {
        $w = $workers[$r['wid']] ?? null;
        if (!$w || !in_array($r['wid'], $ids, true)) continue;
        if (empty($r['status']) || $r['status'] === '--') continue;
        if ($r['date'] < $from || $r['date'] > $to) continue;
        if ($loc && (string)($r['loc'] ?? '') !== (string)$loc) continue;
        $counts = trim((string)($r['loc'] ?? '')) !== '';
        if (empty($r['settleId']) && !$counts) continue;
        $val = $counts ? recValue($r, $w) : 0;
        $diff = round(($val - (!empty($r['settleId']) ? num($r['paidAmt'] ?? 0) : 0)) * 100) / 100;
        if (abs($diff) < 0.005) continue;
        $wasPaid = !empty($r['settleId']);
        $otPart = $wasPaid ? $diff : ($counts ? num($r['xh'] ?? 0) * ((num($r['wage'] ?? 0) ?: num($w['wage'] ?? 0)) / (num($w['hours'] ?? 8, 8) ?: 8)) : 0);
        $r['settleId'] = $sid;
        $r['paidAmt'] = (string)$val;
        if (!isset($per[$r['wid']])) $per[$r['wid']] = ['days' => 0, 'amt' => 0, 'ot' => 0, 'name' => $w['name']];
        if (!$wasPaid) $per[$r['wid']]['days']++;
        $per[$r['wid']]['amt'] += $diff;
        $per[$r['wid']]['ot'] += $otPart;
        $keys[] = $r['date'] . '|' . $r['wid'];
    }
    unset($r);
    $wids = array_keys($per);
    if (!count($wids)) throw new RuntimeException('لا توجد مبالغ مستحقة للصرف ضمن التحديد');
    writeTable('attendance', $att);
    $total = 0; $bTot = 0; $dTot = 0; $tTot = 0;
    $t = nowStr(); $d = todayStr();
    $settlements = readTable('settlements');
    foreach ($wids as $id) {
        $p = $per[$id];
        $a = round($p['amt'] * 100) / 100;
        $x = $adj[$id] ?? [];
        $b = max(0, num($x['b'] ?? 0));
        $ded = max(0, num($x['d'] ?? 0));
        $tx = max(0, num($x['t'] ?? 0));
        $net = round(($a + $b - $ded - $tx) * 100) / 100;
        $ot = round($p['ot'] * 100) / 100;
        $total += $a; $bTot += $b; $dTot += $ded; $tTot += $tx;
        $settlements[] = [
            'id' => $sid, 'date' => $d, 'from' => $from === '0000-00-00' ? '' : $from, 'to' => $to,
            'wid' => $id, 'name' => $p['name'], 'days' => $p['days'], 'amount' => $a,
            'user' => $u['name'], 'createdAt' => $t, 'bonus' => $b, 'ded' => $ded, 'tax' => $tx, 'net' => $net, 'ot' => $ot,
        ];
    }
    writeTable('settlements', $settlements);
    $total = round($total * 100) / 100;
    $extra = ($bTot || $dTot || $tTot) ? ' (مكافآت ' . $bTot . ' / خصومات ' . $dTot . ' / ضرائب ' . $tTot . ')' : '';
    logAction($u['name'], 'تسوية', 'التسوية', count($wids) . ' عامل — ' . $total . ' ج' . $extra . ' حتى ' . $to);
    return ['sid' => $sid, 'count' => count($wids), 'amount' => $total, 'to' => $to, 'wids' => $wids, 'keys' => $keys];
}

function apiListPayroll(?string $token, string $from, string $to): array {
    auth($token, ['workers', 'attendance']);
    if ($from && !validDate($from)) throw new RuntimeException('تاريخ غير صحيح');
    if ($to && !validDate($to)) throw new RuntimeException('تاريخ غير صحيح');
    $out = [];
    foreach (readTable('settlements') as $r) {
        if ($from && ($r['date'] ?? '') < $from) continue;
        if ($to && ($r['date'] ?? '') > $to) continue;
        $a = num($r['amount'] ?? 0); $b = num($r['bonus'] ?? 0); $d = num($r['ded'] ?? 0); $t = num($r['tax'] ?? 0);
        $out[] = [
            'id' => $r['id'], 'date' => $r['date'], 'from' => $r['from'] ?? '', 'to' => $r['to'] ?? '',
            'wid' => $r['wid'], 'name' => $r['name'] ?? '',
            'days' => num($r['days'] ?? 0), 'amount' => $a, 'ot' => num($r['ot'] ?? 0),
            'bonus' => $b, 'ded' => $d, 'tax' => $t,
            'net' => (!isset($r['net']) || $r['net'] === '') ? round(($a + $b - $d - $t) * 100) / 100 : num($r['net']),
            'user' => $r['user'] ?? '',
        ];
    }
    usort($out, function ($x, $y) {
        if ($x['date'] === $y['date']) return $x['id'] < $y['id'] ? 1 : -1;
        return $x['date'] < $y['date'] ? 1 : -1;
    });
    return $out;
}

function apiUpdatePayrollAdj(?string $token, string $id, string $wid, $b, $d, $t): array {
    $u = auth($token, ['workers', 'attendance']);
    $b = max(0, num($b)); $d = max(0, num($d)); $t = max(0, num($t));
    $rows = readTable('settlements');
    $found = false; $name = '';
    foreach ($rows as &$r) {
        if ((string)$r['id'] === (string)$id && (string)$r['wid'] === (string)$wid) {
            $a = num($r['amount'] ?? 0);
            $net = round(($a + $b - $d - $t) * 100) / 100;
            $r['bonus'] = $b; $r['ded'] = $d; $r['tax'] = $t; $r['net'] = $net;
            $name = $r['name'] ?? '';
            $found = true;
            break;
        }
    }
    unset($r);
    if (!$found) throw new RuntimeException('السطر غير موجود');
    writeTable('settlements', $rows);
    logAction($u['name'], 'تعديل مرتب', 'المرتبات', $name . ' — مكافآت ' . $b . ' / خصومات ' . $d . ' / ضرائب ' . $t);
    return ['id' => $id, 'wid' => $wid, 'bonus' => $b, 'ded' => $d, 'tax' => $t, 'net' => $net];
}

/* ===================== عاملين ===================== */
function apiSaveWorker(?string $token, array $w): array {
    $u = auth($token, 'workers');
    $name = clip($w['name'] ?? '', 80);
    if (!$name) throw new RuntimeException('اكتب اسم العامل');
    $workers = readTable('workers');
    $cur = null;
    if (!empty($w['id'])) {
        foreach ($workers as &$x) {
            if ($x['id'] === (string)$w['id']) { $cur = &$x; break; }
        }
        if (!$cur) throw new RuntimeException('العامل غير موجود');
    } else {
        $cur = [
            'id' => 'w' . time() . random_int(0, 999),
            'lastSet' => '', 'cardImg' => '', 'photo' => '',
        ];
        $workers[] = &$cur;
    }
    $cur['name'] = $name;
    $cur['card'] = clip($w['card'] ?? '', 30);
    $cur['phone'] = clip($w['phone'] ?? '', 20);
    $cur['wage'] = max(0, num($w['wage'] ?? 0));
    $cur['hours'] = max(1, num($w['hours'] ?? 8, 8)) ?: 8;
    if (!empty($w['cardImgData'])) {
        trashImg($cur['cardImg'] ?? null);
        $cur['cardImg'] = saveImg($w['cardImgData'], 'card');
    }
    if (!empty($w['photoData'])) {
        trashImg($cur['photo'] ?? null);
        $cur['photo'] = saveImg($w['photoData'], 'photo');
    }
    writeTable('workers', $workers);
    logAction($u['name'], !empty($w['id']) ? 'تعديل عامل' : 'إضافة عامل', 'العاملين', $name);
    return workerOut($cur, true, lastSetMap());
}

function apiDeleteWorkers(?string $token, array $ids): array {
    $u = auth($token, 'workers');
    if (!is_array($ids) || !count($ids)) throw new RuntimeException('حدد عاملًا واحدًا على الأقل');
    $keep = []; $n = 0;
    foreach (readTable('workers') as $w) {
        if (in_array($w['id'], $ids, true)) {
            trashImg($w['cardImg'] ?? null);
            trashImg($w['photo'] ?? null);
            $n++;
        } else {
            $keep[] = $w;
        }
    }
    writeTable('workers', $keep);
    logAction($u['name'], 'حذف عاملين', 'العاملين', $n . ' عامل');
    return ['count' => $n];
}

function apiGetImage(?string $token, string $id, string $kind): ?string {
    auth($token, ['workers', 'attendance']);
    foreach (readTable('workers') as $w) {
        if ($w['id'] === (string)$id) {
            $fid = $kind === 'card' ? ($w['cardImg'] ?? '') : ($w['photo'] ?? '');
            return imgDataUrl($fid ?: null);
        }
    }
    return null;
}

/* ===================== مستخدمين ===================== */
function apiSetUser(?string $token, string $username, array $patch): array {
    $me = auth($token, 'admin');
    $username = strtolower(clip($username, 40));
    $users = readTable('users');
    $found = false;
    foreach ($users as &$u) {
        if ($u['username'] !== $username) continue;
        $found = true;
        if ($u['role'] === 'admin') throw new RuntimeException('لا يمكن تعديل حساب المدير');
        if (!empty($patch['status'])) {
            if (!in_array($patch['status'], ['approved', 'pending', 'suspended'], true)) {
                throw new RuntimeException('حالة غير صحيحة');
            }
            $u['status'] = $patch['status'];
            logAction($me['name'], 'تغيير حالة مستخدم', 'المستخدمين', $u['name'] . ' → ' . $patch['status']);
        }
        if (isset($patch['perms'])) {
            $u['perms'] = json_encode(cleanPerms($patch['perms']), JSON_UNESCAPED_UNICODE);
            logAction($me['name'], 'تعديل صلاحيات', 'المستخدمين', $u['name']);
        }
        break;
    }
    unset($u);
    if (!$found) throw new RuntimeException('المستخدم غير موجود');
    writeTable('users', $users);
    return array_map('publicUser', $users);
}

function apiAddUser(?string $token, string $name, string $username, string $password, array $perms, bool $isAdmin): array {
    $me = auth($token, 'admin');
    $name = clip($name, 60);
    $username = strtolower(clip($username, 30));
    $password = (string)$password;
    if (mb_strlen($name) < 2) throw new RuntimeException('اكتب الاسم بالكامل');
    if (!preg_match('/^[a-z0-9_.]{3,30}$/', $username)) {
        throw new RuntimeException('اسم المستخدم: حروف إنجليزية صغيرة وأرقام فقط (3 أحرف على الأقل)');
    }
    if (strlen($password) < 6) throw new RuntimeException('كلمة المرور 6 أحرف على الأقل');
    $users = readTable('users');
    foreach ($users as $u) {
        if ($u['username'] === $username) throw new RuntimeException('اسم المستخدم مستخدم من قبل');
    }
    $salt = bin2hex(random_bytes(16));
    $users[] = [
        'username' => $username, 'name' => $name, 'salt' => $salt,
        'hash' => hashPass($salt, $password), 'status' => 'approved',
        'role' => $isAdmin ? 'admin' : 'user',
        'perms' => json_encode(cleanPerms($perms), JSON_UNESCAPED_UNICODE),
        'lastLogin' => '', 'lastActive' => '',
    ];
    writeTable('users', $users);
    logAction($me['name'], 'إضافة مستخدم', 'المستخدمين', $name . ' (' . $username . ')');
    return array_map('publicUser', $users);
}

function apiResetUserPassword(?string $token, string $username, string $newPass): bool {
    $me = auth($token, 'admin');
    $username = strtolower(clip($username, 40));
    $newPass = (string)$newPass;
    if (strlen($newPass) < 6) throw new RuntimeException('كلمة المرور 6 أحرف على الأقل');
    $u = null;
    foreach (readTable('users') as $x) {
        if ($x['username'] === $username) { $u = $x; break; }
    }
    if (!$u) throw new RuntimeException('المستخدم غير موجود');
    if ($u['role'] === 'admin') throw new RuntimeException('غيّر كلمة مرور المدير من زر 🔑 داخل حسابه');
    $salt = bin2hex(random_bytes(16));
    updateUserFields($username, ['salt' => $salt, 'hash' => hashPass($salt, $newPass)]);
    logAction($me['name'], 'إعادة تعيين كلمة مرور', 'المستخدمين', $u['name']);
    return true;
}

function apiDeleteUser(?string $token, string $username): array {
    $me = auth($token, 'admin');
    $username = strtolower(clip($username, 40));
    $users = readTable('users');
    $u = null;
    foreach ($users as $x) {
        if ($x['username'] === $username) { $u = $x; break; }
    }
    if (!$u) throw new RuntimeException('المستخدم غير موجود');
    if ($u['role'] === 'admin') throw new RuntimeException('لا يمكن حذف حساب المدير');
    $users = array_values(array_filter($users, fn($x) => $x['username'] !== $username));
    writeTable('users', $users);
    $sessions = array_values(array_filter(readTable('sessions'), fn($s) => ($s['username'] ?? '') !== $username));
    writeTable('sessions', $sessions);
    logAction($me['name'], 'حذف مستخدم', 'المستخدمين', $u['name']);
    return array_map('publicUser', $users);
}

function apiGetMonitor(?string $token): array {
    auth($token, 'admin');
    $log = readTable('log');
    $nowMs = (int)(microtime(true) * 1000);
    $users = [];
    foreach (readTable('users') as $u) {
        $mine = array_values(array_filter($log, fn($l) => ($l['user'] ?? '') === $u['name']));
        $last = count($mine) ? $mine[count($mine) - 1]['action'] : '';
        $act = (int)($u['lastActive'] ?: 0);
        $users[] = [
            'name' => $u['name'], 'username' => $u['username'],
            'lastLogin' => $u['lastLogin'] ?? '',
            'online' => $act && ($nowMs - $act) < ONLINE_MS,
            'count' => count($mine), 'lastAction' => $last,
        ];
    }
    $logSlice = array_slice($log, -300);
    return ['users' => $users, 'log' => array_reverse($logSlice)];
}

/* ===================== بوابة ===================== */
function gateImgs(array $g): array {
    $a = is_string($g['images'] ?? null) ? json_decode($g['images'], true) : ($g['images'] ?? []);
    return is_array($a) ? $a : [];
}

function gateOut(array $g): array {
    return [
        'id' => $g['id'], 'seq' => (int)num($g['seq'] ?? 0), 'weekday' => $g['weekday'] ?? '',
        'date' => $g['date'], 'plate' => $g['plate'] ?? '', 'time' => $g['time'] ?? '',
        'driver' => $g['driver'] ?? '', 'statement' => $g['statement'] ?? '', 'notes' => $g['notes'] ?? '',
        'managers' => $g['managers'] ?? '', 'host' => $g['host'] ?? '',
        'imgCount' => count(gateImgs($g)), 'createdBy' => $g['createdBy'] ?? '',
    ];
}

function apiListGate(?string $token): array {
    auth($token, 'gate');
    $rows = array_map('gateOut', readTable('gate'));
    usort($rows, function ($a, $b) {
        if ($a['date'] === $b['date']) return $b['seq'] - $a['seq'];
        return $a['date'] < $b['date'] ? 1 : -1;
    });
    return array_slice($rows, 0, 3000);
}

function apiSaveGate(?string $token, array $e): array {
    $u = auth($token, 'gate');
    $date = (string)($e['date'] ?? '');
    if (!validDate($date)) throw new RuntimeException('حدد التاريخ');
    $time = clip($e['time'] ?? '', 5);
    if ($time && !preg_match('/^\d{2}:\d{2}$/', $time)) throw new RuntimeException('الوقت غير صحيح');
    $plate = clip($e['plate'] ?? '', 40);
    if (!$plate) throw new RuntimeException('اكتب رقم السيارة');
    $fresh = is_array($e['newImages'] ?? null) ? $e['newImages'] : [];
    if (count($fresh) > 10) throw new RuntimeException('الحد الأقصى 10 صور في المرة الواحدة');
    $rows = readTable('gate');
    $cur = null;
    if (!empty($e['id'])) {
        foreach ($rows as &$x) {
            if ($x['id'] === (string)$e['id']) { $cur = &$x; break; }
        }
        if (!$cur) throw new RuntimeException('السجل غير موجود');
    } else {
        $mx = 0;
        foreach ($rows as $x) $mx = max($mx, (int)num($x['seq'] ?? 0));
        $cur = [
            'id' => 'g' . time() . random_int(0, 999),
            'seq' => $mx + 1, 'images' => '[]',
            'createdBy' => $u['name'], 'createdAt' => nowStr(),
        ];
        $rows[] = &$cur;
    }
    $imgs = gateImgs($cur);
    $rm = array_map('intval', is_array($e['removeIdx'] ?? null) ? $e['removeIdx'] : []);
    $keep = [];
    foreach ($imgs as $i => $id) {
        if (in_array($i, $rm, true)) trashImg($id);
        else $keep[] = $id;
    }
    if (count($keep) + count($fresh) > 20) throw new RuntimeException('الحد الأقصى 20 صورة للتسجيل الواحد');
    foreach ($fresh as $d) $keep[] = saveImg($d, 'gate');
    $cur['date'] = $date;
    $cur['weekday'] = weekdayAr($date);
    $cur['time'] = $time;
    $cur['plate'] = $plate;
    $cur['driver'] = clip($e['driver'] ?? '', 80);
    $cur['statement'] = clip($e['statement'] ?? '', 200);
    $cur['notes'] = clip($e['notes'] ?? '', 300);
    $cur['managers'] = clip($e['managers'] ?? '', 200);
    $cur['host'] = clip($e['host'] ?? '', 80);
    $cur['images'] = json_encode($keep, JSON_UNESCAPED_UNICODE);
    writeTable('gate', $rows);
    logAction($u['name'], !empty($e['id']) ? 'تعديل دخول بوابة' : 'تسجيل دخول بوابة', 'دفتر البوابة', $plate . ' — ' . $date);
    return gateOut($cur);
}

function apiDeleteGate(?string $token, string $id): bool {
    $u = auth($token, 'gate');
    $keep = []; $hit = null;
    foreach (readTable('gate') as $g) {
        if ($g['id'] === (string)$id) $hit = $g;
        else $keep[] = $g;
    }
    if (!$hit) throw new RuntimeException('السجل غير موجود');
    foreach (gateImgs($hit) as $fid) trashImg($fid);
    writeTable('gate', $keep);
    logAction($u['name'], 'حذف دخول بوابة', 'دفتر البوابة', ($hit['plate'] ?? '') . ' — ' . ($hit['date'] ?? ''));
    return true;
}

function apiGetGateImage(?string $token, string $id, $idx): ?string {
    auth($token, 'gate');
    foreach (readTable('gate') as $g) {
        if ($g['id'] === (string)$id) {
            $imgs = gateImgs($g);
            return imgDataUrl($imgs[(int)$idx] ?? null);
        }
    }
    return null;
}

function apiResetAll(?string $token): bool {
    $u = auth($token, 'admin');
    foreach (readTable('workers') as $w) {
        trashImg($w['cardImg'] ?? null);
        trashImg($w['photo'] ?? null);
    }
    writeTable('workers', []);
    writeTable('attendance', []);
    writeTable('locations', []);
    writeTable('settlements', []);
    logAction($u['name'], 'تصفير البرنامج', 'النظام', '');
    return true;
}
