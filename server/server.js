import express from 'express';
import cors from 'cors';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  createUser,
  getUserByUsername,
  getUserById,
  listUsers,
  saveState,
  createSession,
  getUserByToken,
  deleteSession,
  verifyPassword,
  ensureAdmin,
  createGroup,
  getGroupById,
  getGroupByCode,
  addMember,
  removeMember,
  isMember,
  deleteGroup,
  listGroupsForUser,
  listGroupMembers,
} from './db.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const app = express();
const PORT = process.env.PORT || 4000;

// Landing page (with phone slideshow & download buttons) lives in docs/
const LANDING_DIR = fs.existsSync(path.join(__dirname, 'docs'))
  ? path.join(__dirname, 'docs')
  : path.join(__dirname, '..', 'docs');

// The public StudyDesk web app. When deployed we bundle the Flutter build into
// server/webapp; locally we fall back to the live build under study_desk/.
const APP_DIR = fs.existsSync(path.join(__dirname, 'webapp'))
  ? path.join(__dirname, 'webapp')
  : path.join(__dirname, '..', 'study_desk', 'build', 'web');

app.use(cors());
app.use(express.json({ limit: '1mb' }));

// Liveness probe for cloud hosts (Render/Railway/etc.).
app.get('/healthz', (_req, res) => res.json({ ok: true }));

// Serve the Landing Page at / (phone slideshow, features, direct download)
if (fs.existsSync(LANDING_DIR)) {
  app.use(express.static(LANDING_DIR));
}

// Serve the Flutter web app at /app
if (fs.existsSync(APP_DIR)) {
  app.use('/app', express.static(APP_DIR));
}

// Admin panel assets (admin.html) live under public/.
app.use(express.static(path.join(__dirname, 'public')));

// ---------- helpers ----------
function publicUser(u) {
  return { id: u.id, username: u.username, isAdmin: !!u.is_admin };
}

function bearer(req) {
  const h = req.headers.authorization || '';
  return h.startsWith('Bearer ') ? h.slice(7) : null;
}

function auth(req, res, next) {
  const user = getUserByToken(bearer(req));
  if (!user) return res.status(401).json({ error: 'unauthorized' });
  req.user = user;
  next();
}

function adminOnly(req, res, next) {
  if (!req.user?.is_admin) return res.status(403).json({ error: 'forbidden' });
  next();
}

function daysUntil(dateStr) {
  const now = new Date();
  const start = Date.UTC(now.getFullYear(), now.getMonth(), now.getDate());
  const [y, m, d] = String(dateStr).split('-').map(Number);
  const target = Date.UTC(y, m - 1, d);
  return Math.round((target - start) / 86400000);
}

// Compact summary used by the admin list view.
function summarize(u) {
  let state = {};
  try {
    state = JSON.parse(u.state || '{}');
  } catch {
    state = {};
  }
  const events = Array.isArray(state.events) ? state.events : [];
  const goals = Array.isArray(state.goals) ? state.goals : [];
  const subjects = Array.isArray(state.subjects) ? state.subjects : [];
  const upcoming = events
    .map((e) => ({ ...e, d: daysUntil(e.date) }))
    .filter((e) => e.d >= 0)
    .sort((a, b) => a.d - b.d);
  const totalTopics = subjects.reduce((a, s) => a + (s.topics?.length || 0), 0);
  const doneTopics = subjects.reduce(
    (a, s) => a + (s.topics?.filter((t) => t.done).length || 0),
    0
  );
  return {
    id: u.id,
    username: u.username,
    isAdmin: !!u.is_admin,
    updatedAt: u.updated_at,
    createdAt: u.created_at,
    countdowns: events.length,
    goals: goals.length,
    goalsDone: goals.filter((g) => g.done).length,
    syllabusPct: totalTopics ? Math.round((doneTopics / totalTopics) * 100) : 0,
    streak: state.streak?.best ?? 0,
    nextExam: upcoming[0]
      ? { title: upcoming[0].title, date: upcoming[0].date, daysLeft: upcoming[0].d }
      : null,
  };
}

// ---------- auth routes ----------
app.post('/api/register', (req, res) => {
  const username = String(req.body?.username || '').trim();
  const password = String(req.body?.password || '');
  if (username.length < 3 || password.length < 4) {
    return res
      .status(400)
      .json({ error: 'username ≥ 3 and password ≥ 4 characters required' });
  }
  if (getUserByUsername(username)) {
    return res.status(409).json({ error: 'username already taken' });
  }
  const user = createUser(username, password, 0);
  const token = createSession(user.id);
  res.json({ token, user: publicUser(user) });
});

app.post('/api/login', (req, res) => {
  const username = String(req.body?.username || '').trim();
  const password = String(req.body?.password || '');
  const user = getUserByUsername(username);
  if (!user || !verifyPassword(password, user.salt, user.pass_hash)) {
    return res.status(401).json({ error: 'invalid username or password' });
  }
  const token = createSession(user.id);
  res.json({ token, user: publicUser(user) });
});

app.post('/api/logout', auth, (req, res) => {
  deleteSession(bearer(req));
  res.json({ ok: true });
});

app.get('/api/me', auth, (req, res) => {
  res.json({ user: publicUser(req.user) });
});

// ---------- state sync ----------
app.get('/api/state', auth, (req, res) => {
  let state = null;
  try {
    const parsed = JSON.parse(req.user.state || '{}');
    state = parsed && Object.keys(parsed).length ? parsed : null;
  } catch {
    state = null;
  }
  res.json({ state, updatedAt: req.user.updated_at });
});

app.put('/api/state', auth, (req, res) => {
  const state = req.body?.state;
  if (state == null || typeof state !== 'object') {
    return res.status(400).json({ error: 'state object required' });
  }
  saveState(req.user.id, JSON.stringify(state));
  res.json({ ok: true, updatedAt: new Date().toISOString() });
});

// ---------- groups ("show up together") ----------
function localDateStr(d = new Date()) {
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

/**
 * What one member's group-mates are allowed to see. Deliberately narrow: a
 * presence signal and a streak, never the exam titles, notes or goals stored
 * in their state blob.
 */
function memberSummary(member) {
  let state = {};
  try {
    state = JSON.parse(member.state || '{}');
  } catch {
    state = {};
  }

  const today = localDateStr();
  const yesterday = localDateStr(new Date(Date.now() - 86400000));
  const log = (state.dayLogs || {})[today] || {};
  const habitsDone = (log.habits || []).length;
  const activity =
    habitsDone + (log.focus || 0) + (log.topics || 0) + (log.goals || 0);

  // Weekday as Mon=1..Sun=7, matching Habit.days on the client.
  const weekday = ((new Date().getDay() + 6) % 7) + 1;
  const habitsTotal = (state.habits || []).filter((h) =>
    (h.days || [1, 2, 3, 4, 5, 6, 7]).includes(weekday)
  ).length;

  // Mirrors AppState.liveStreak: a streak is only alive if it was touched
  // today or yesterday.
  const streak = state.streak || {};
  const live =
    streak.lastStudyDate === today || streak.lastStudyDate === yesterday
      ? streak.count || 0
      : 0;

  return {
    id: member.id,
    username: member.username,
    showedUpToday: activity > 0,
    activity,
    habitsDone,
    habitsTotal,
    streak: live,
    bestStreak: streak.best || 0,
    joinedAt: member.joined_at,
  };
}

function groupPayload(group, userId) {
  const members = listGroupMembers(group.id).map(memberSummary);
  return {
    id: group.id,
    name: group.name,
    code: group.code,
    isOwner: group.owner_id === userId,
    createdAt: group.created_at,
    memberCount: members.length,
    showedUpToday: members.filter((m) => m.showedUpToday).length,
    // Most active first, so the leaderboard reads top-down.
    members: members.sort((a, b) => b.activity - a.activity || b.streak - a.streak),
  };
}

app.get('/api/groups', auth, (req, res) => {
  res.json({
    groups: listGroupsForUser(req.user.id).map((g) => groupPayload(g, req.user.id)),
  });
});

app.post('/api/groups', auth, (req, res) => {
  const name = String(req.body?.name || '').trim();
  if (name.length < 2 || name.length > 40) {
    return res.status(400).json({ error: 'group name must be 2–40 characters' });
  }
  if (listGroupsForUser(req.user.id).length >= 20) {
    return res.status(400).json({ error: 'you are in too many groups' });
  }
  const group = createGroup(name, req.user.id);
  res.json({ group: groupPayload(group, req.user.id) });
});

app.post('/api/groups/join', auth, (req, res) => {
  const code = String(req.body?.code || '').trim().toUpperCase();
  const group = getGroupByCode(code);
  if (!group) return res.status(404).json({ error: 'no group with that code' });
  if (isMember(group.id, req.user.id)) {
    return res.status(409).json({ error: 'you are already in this group' });
  }
  addMember(group.id, req.user.id);
  res.json({ group: groupPayload(group, req.user.id) });
});

app.post('/api/groups/:id/leave', auth, (req, res) => {
  const group = getGroupById(Number(req.params.id));
  if (!group || !isMember(group.id, req.user.id)) {
    return res.status(404).json({ error: 'not found' });
  }
  // The owner leaving would strand the group, so that removes it outright.
  if (group.owner_id === req.user.id) {
    deleteGroup(group.id);
    return res.json({ ok: true, deleted: true });
  }
  removeMember(group.id, req.user.id);
  res.json({ ok: true, deleted: false });
});

app.delete('/api/groups/:id', auth, (req, res) => {
  const group = getGroupById(Number(req.params.id));
  if (!group || !isMember(group.id, req.user.id)) {
    return res.status(404).json({ error: 'not found' });
  }
  if (group.owner_id !== req.user.id) {
    return res.status(403).json({ error: 'only the owner can delete this group' });
  }
  deleteGroup(group.id);
  res.json({ ok: true });
});

// ---------- admin ----------
app.get('/api/admin/users', auth, adminOnly, (req, res) => {
  res.json({ users: listUsers().map(summarize) });
});

app.get('/api/admin/users/:id', auth, adminOnly, (req, res) => {
  const u = getUserById(Number(req.params.id));
  if (!u) return res.status(404).json({ error: 'not found' });
  let state = {};
  try {
    state = JSON.parse(u.state || '{}');
  } catch {
    state = {};
  }
  // Decorate events with live days-left for convenience.
  if (Array.isArray(state.events)) {
    state.events = state.events
      .map((e) => ({ ...e, daysLeft: daysUntil(e.date) }))
      .sort((a, b) => a.daysLeft - b.daysLeft);
  }
  res.json({
    user: { ...publicUser(u), createdAt: u.created_at, updatedAt: u.updated_at },
    summary: summarize(u),
    state,
  });
});

// Admin panel — separate from the public app, behind the admin login.
app.get('/admin', (_req, res) =>
  res.sendFile(path.join(__dirname, 'public', 'admin.html')));

// Anything else that isn't an API call → the app's index.html, so client-side
// routes and deep links load the StudyDesk app (single-page-app fallback).
app.get('*', (req, res) => {
  if (req.path.startsWith('/api/')) return res.status(404).json({ error: 'not found' });
  res.sendFile(path.join(APP_DIR, 'index.html'));
});

const seeded = ensureAdmin();
// Bind 0.0.0.0 so a cloud host (and, on a LAN, your phone) can reach it; on your
// own machine 127.0.0.1 still works exactly the same.
app.listen(PORT, '0.0.0.0', () => {
  console.log(`StudyDesk app + API listening on port ${PORT}`);
  console.log(`Public app at /   ·   Admin panel at /admin`);
  if (seeded.created) {
    console.log(`Seeded admin account -> username: ${seeded.username}  password: ${seeded.password}`);
    if (seeded.usingDefault) {
      console.warn('WARNING: using the default admin password. On a public deploy set ADMIN_PASSWORD (and ADMIN_USERNAME).');
    }
  }
});
