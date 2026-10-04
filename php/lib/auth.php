<?php
declare(strict_types=1);
require_once __DIR__ . '/db.php';

const PERMS = ['workers', 'attendance', 'reports', 'gate'];

function auth(?string $token, $perm = null): array {
    bootStorage();
    if (!$token) throw new RuntimeException('SESSION');
    $sessions = readTable('sessions');
    $now = time();
    $username = null;
    $newSessions = [];
    foreach ($sessions as $s) {
        if (($s['expires'] ?? 0) < $now) continue;
        if (($s['token'] ?? '') === $token) {
            $username = $s['username'];
            $s['expires'] = $now + SESSION_TTL;
        }
        $newSessions[] = $s;
    }
    writeTable('sessions', $newSessions);
    if (!$username) throw new RuntimeException('SESSION');
    $u = null;
    foreach (readTable('users') as $row) {
        if ($row['username'] === $username) { $u = $row; break; }
    }
    if (!$u || $u['status'] !== 'approved') throw new RuntimeException('SESSION');
    $u['perms'] = parsePerms($u['perms']);
    if ($perm !== null && !can($u, $perm)) {
        throw new RuntimeException('غير مصرح لك بهذا الإجراء');
    }
    return $u;
}

function can(array $u, $perm): bool {
    if (($u['role'] ?? '') === 'admin') return true;
    if ($perm === 'admin') return false;
    $list = is_array($perm) ? $perm : [$perm];
    foreach ($list as $p) {
        if (!empty($u['perms'][$p])) return true;
    }
    return false;
}

function createSession(string $username): string {
    $token = bin2hex(random_bytes(32));
    $sessions = readTable('sessions');
    $now = time();
    $sessions = array_values(array_filter($sessions, fn($s) => ($s['expires'] ?? 0) >= $now));
    $sessions[] = ['token' => $token, 'username' => $username, 'expires' => $now + SESSION_TTL];
    writeTable('sessions', $sessions);
    return $token;
}

function destroySession(?string $token): void {
    if (!$token) return;
    $sessions = array_values(array_filter(readTable('sessions'), fn($s) => ($s['token'] ?? '') !== $token));
    writeTable('sessions', $sessions);
}

function updateUserFields(string $username, array $fields): void {
    if (!$fields) return;
    $users = readTable('users');
    foreach ($users as &$u) {
        if ($u['username'] === $username) {
            foreach ($fields as $k => $v) $u[$k] = (string)$v;
            break;
        }
    }
    unset($u);
    writeTable('users', $users);
}

function cleanPerms($perms): array {
    $p = [];
    foreach (PERMS as $k) {
        if (!empty($perms[$k])) $p[$k] = 1;
    }
    return $p;
}
