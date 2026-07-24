import { DatabaseSync } from 'node:sqlite';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
// DB_PATH lets a cloud host point the database at a persistent disk; locally it
// just lives next to this file.
const DB_PATH = process.env.DB_PATH || path.join(__dirname, 'studydesk.db');
const db = new DatabaseSync(DB_PATH);

db.exec(`
  PRAGMA journal_mode = WAL;

  CREATE TABLE IF NOT EXISTS users (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    username   TEXT UNIQUE NOT NULL,
    pass_hash  TEXT NOT NULL,
    salt       TEXT NOT NULL,
    is_admin   INTEGER NOT NULL DEFAULT 0,
    state      TEXT NOT NULL DEFAULT '{}',
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  );

  CREATE TABLE IF NOT EXISTS sessions (
    token      TEXT PRIMARY KEY,
    user_id    INTEGER NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
  );

  -- "Show up together": a group is just a name plus a shareable join code.
  -- Named study_groups because GROUPS is a reserved word in modern SQLite.
  CREATE TABLE IF NOT EXISTS study_groups (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    name       TEXT NOT NULL,
    code       TEXT UNIQUE NOT NULL,
    owner_id   INTEGER NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY (owner_id) REFERENCES users(id) ON DELETE CASCADE
  );

  CREATE TABLE IF NOT EXISTS group_members (
    group_id  INTEGER NOT NULL,
    user_id   INTEGER NOT NULL,
    joined_at TEXT NOT NULL,
    PRIMARY KEY (group_id, user_id),
    FOREIGN KEY (group_id) REFERENCES study_groups(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id)  REFERENCES users(id) ON DELETE CASCADE
  );

  CREATE INDEX IF NOT EXISTS idx_group_members_user ON group_members(user_id);
`);

// ---------- password hashing (built-in scrypt, no native deps) ----------
export function hashPassword(password, salt = crypto.randomBytes(16).toString('hex')) {
  const hash = crypto.scryptSync(password, salt, 64).toString('hex');
  return { hash, salt };
}

export function verifyPassword(password, salt, expectedHash) {
  const hash = crypto.scryptSync(password, salt, 64).toString('hex');
  const a = Buffer.from(hash, 'hex');
  const b = Buffer.from(expectedHash, 'hex');
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

const now = () => new Date().toISOString();

// ---------- users ----------
export function createUser(username, password, isAdmin = 0) {
  const { hash, salt } = hashPassword(password);
  const ts = now();
  const info = db
    .prepare(
      `INSERT INTO users (username, pass_hash, salt, is_admin, state, created_at, updated_at)
       VALUES (?, ?, ?, ?, '{}', ?, ?)`
    )
    .run(username, hash, salt, isAdmin, ts, ts);
  return getUserById(Number(info.lastInsertRowid));
}

export function getUserByUsername(username) {
  return db.prepare('SELECT * FROM users WHERE username = ?').get(username);
}

export function getUserById(id) {
  return db.prepare('SELECT * FROM users WHERE id = ?').get(id);
}

export function listUsers() {
  return db
    .prepare(
      'SELECT id, username, is_admin, state, created_at, updated_at FROM users ORDER BY created_at ASC'
    )
    .all();
}

export function saveState(userId, stateJson) {
  db.prepare('UPDATE users SET state = ?, updated_at = ? WHERE id = ?').run(
    stateJson,
    now(),
    userId
  );
}

// ---------- sessions ----------
export function createSession(userId) {
  const token = crypto.randomBytes(32).toString('hex');
  db.prepare('INSERT INTO sessions (token, user_id, created_at) VALUES (?, ?, ?)').run(
    token,
    userId,
    now()
  );
  return token;
}

export function getUserByToken(token) {
  if (!token) return null;
  const row = db
    .prepare(
      `SELECT u.* FROM sessions s JOIN users u ON u.id = s.user_id WHERE s.token = ?`
    )
    .get(token);
  return row || null;
}

export function deleteSession(token) {
  db.prepare('DELETE FROM sessions WHERE token = ?').run(token);
}

// ---------- groups ----------
// Ambiguous characters (0/O, 1/I) are left out so a code can be read aloud.
const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

function generateGroupCode() {
  for (let attempt = 0; attempt < 20; attempt++) {
    let code = '';
    for (let i = 0; i < 6; i++) {
      code += CODE_ALPHABET[crypto.randomInt(CODE_ALPHABET.length)];
    }
    if (!getGroupByCode(code)) return code;
  }
  throw new Error('could not allocate a unique group code');
}

export function createGroup(name, ownerId) {
  const ts = now();
  const code = generateGroupCode();
  const info = db
    .prepare(
      'INSERT INTO study_groups (name, code, owner_id, created_at) VALUES (?, ?, ?, ?)'
    )
    .run(name, code, ownerId, ts);
  const groupId = Number(info.lastInsertRowid);
  addMember(groupId, ownerId);
  return getGroupById(groupId);
}

export function getGroupById(id) {
  return db.prepare('SELECT * FROM study_groups WHERE id = ?').get(id);
}

export function getGroupByCode(code) {
  return db.prepare('SELECT * FROM study_groups WHERE code = ?').get(code);
}

export function addMember(groupId, userId) {
  db.prepare(
    `INSERT INTO group_members (group_id, user_id, joined_at) VALUES (?, ?, ?)
     ON CONFLICT (group_id, user_id) DO NOTHING`
  ).run(groupId, userId, now());
}

export function removeMember(groupId, userId) {
  db.prepare('DELETE FROM group_members WHERE group_id = ? AND user_id = ?').run(
    groupId,
    userId
  );
}

export function isMember(groupId, userId) {
  return !!db
    .prepare('SELECT 1 FROM group_members WHERE group_id = ? AND user_id = ?')
    .get(groupId, userId);
}

export function deleteGroup(groupId) {
  db.prepare('DELETE FROM group_members WHERE group_id = ?').run(groupId);
  db.prepare('DELETE FROM study_groups WHERE id = ?').run(groupId);
}

export function listGroupsForUser(userId) {
  return db
    .prepare(
      `SELECT g.* FROM study_groups g
       JOIN group_members m ON m.group_id = g.id
       WHERE m.user_id = ?
       ORDER BY g.created_at ASC`
    )
    .all(userId);
}

/// Members of a group, each with the state blob needed to summarise activity.
export function listGroupMembers(groupId) {
  return db
    .prepare(
      `SELECT u.id, u.username, u.state, m.joined_at
       FROM group_members m JOIN users u ON u.id = m.user_id
       WHERE m.group_id = ?
       ORDER BY m.joined_at ASC`
    )
    .all(groupId);
}

// ---------- seed a default admin ----------
// On a PUBLIC deploy, set ADMIN_USERNAME / ADMIN_PASSWORD so the admin panel
// isn't protected by the well-known default. Falls back to admin/admin123 only
// for local use.
export function ensureAdmin() {
  const existing = db.prepare('SELECT COUNT(*) AS n FROM users WHERE is_admin = 1').get();
  if (existing.n === 0) {
    const username = process.env.ADMIN_USERNAME || 'admin';
    const password = process.env.ADMIN_PASSWORD || 'admin123';
    createUser(username, password, 1);
    return { username, password, created: true, usingDefault: !process.env.ADMIN_PASSWORD };
  }
  return { created: false };
}

export default db;
