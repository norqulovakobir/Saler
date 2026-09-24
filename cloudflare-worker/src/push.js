/// Firebase Cloud Messaging (HTTP v1) — Worker ichidan push yuborish.
///
/// FCM v1 oddiy API kaliti bilan ishlamaydi: har so'rov Google OAuth2
/// access token'ini talab qiladi, u esa xizmat hisobining (service account)
/// yopiq kaliti bilan imzolangan JWT evaziga olinadi. Workers'da Node crypto
/// yo'q, shuning uchun imzolash Web Crypto (RS256) orqali qilinadi.
///
/// Sozlanmagan bo'lsa (sir qo'yilmagan) hamma funksiya jim qaytadi —
/// push yo'qligi buyurtma oqimini to'xtatmasligi kerak.

import { all, one, run } from './lib.js';

const TOKEN_URL = 'https://oauth2.googleapis.com/token';
const SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';

/// Access token qisqa muddatli (1 soat). Har xabarda qaytadan olmaslik uchun
/// isolate xotirasida saqlanadi — Worker qayta ishga tushsa o'zi yangilanadi.
let cached = { token: null, expiresAt: 0 };

function serviceAccount(env) {
  const raw = env && env.FIREBASE_SERVICE_ACCOUNT;
  if (!raw) return null;
  try {
    const json = typeof raw === 'string' ? JSON.parse(raw) : raw;
    if (!json.client_email || !json.private_key || !json.project_id) return null;
    return json;
  } catch {
    console.error('FIREBASE_SERVICE_ACCOUNT JSON emas');
    return null;
  }
}

export const pushEnabled = (env) => serviceAccount(env) !== null;

const b64Url = (bytes) => {
  let raw = '';
  for (const byte of new Uint8Array(bytes)) raw += String.fromCharCode(byte);
  return btoa(raw).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
};
const b64UrlText = (text) => b64Url(new TextEncoder().encode(text));

/// PEM (`-----BEGIN PRIVATE KEY-----`) dan Web Crypto kalitiga
async function importKey(pem) {
  const body = pem.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey('pkcs8', der,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
}

async function accessToken(env) {
  const account = serviceAccount(env);
  if (!account) return null;
  const now = Math.floor(Date.now() / 1000);
  // 60 soniya zaxira: yo'lda turgan so'rov muddati o'tib ketmasin
  if (cached.token && cached.expiresAt - 60 > now) return cached.token;

  const claim = {
    iss: account.client_email,
    scope: SCOPE,
    aud: TOKEN_URL,
    iat: now,
    exp: now + 3600,
  };
  const unsigned = `${b64UrlText(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))}.${b64UrlText(JSON.stringify(claim))}`;
  const key = await importKey(account.private_key);
  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key,
    new TextEncoder().encode(unsigned));
  const jwt = `${unsigned}.${b64Url(signature)}`;

  const response = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });
  if (!response.ok) {
    console.error('FCM token olinmadi', response.status, (await response.text()).slice(0, 200));
    return null;
  }
  const data = await response.json();
  cached = { token: data.access_token, expiresAt: now + (data.expires_in || 3600) };
  return cached.token;
}

/// Bitta qurilmaga yuborish. Token eskirgan bo'lsa bazadan o'chiriladi —
/// aks holda o'lik tokenlar yig'ilib, har safar behuda so'rov ketadi.
async function sendTo(env, token, message) {
  const account = serviceAccount(env);
  const auth = await accessToken(env);
  if (!account || !auth) return false;
  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`,
    {
      method: 'POST',
      headers: { Authorization: `Bearer ${auth}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ message: { ...message, token } }),
    },
  );
  if (response.ok) return true;
  const text = await response.text();
  if (response.status === 404 || /UNREGISTERED|INVALID_ARGUMENT/i.test(text)) {
    await run(env, 'DELETE FROM push_tokens WHERE token=?', [token]).catch(() => null);
    return false;
  }
  console.error('FCM xato', response.status, text.slice(0, 200));
  return false;
}

/// Tanlangan qabul qiluvchilarga xabar. `to` — {courierId} | {shopId} | {userId}
export async function push(env, to, { title, body, data = {} } = {}) {
  if (!pushEnabled(env)) return 0;
  const where = to.courierId ? 'courier_id=?' : to.shopId ? 'shop_id=?' : 'user_id=?';
  const value = to.courierId || to.shopId || to.userId;
  if (!value) return 0;
  const rows = await all(env, `SELECT token FROM push_tokens WHERE ${where}`, [value]);
  if (!rows.length) return 0;
  const message = {
    notification: { title, body },
    // Barcha qiymatlar matn bo'lishi shart — FCM boshqasini qabul qilmaydi
    data: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)])),
    android: { priority: 'high', notification: { channel_id: 'orders', sound: 'default' } },
    apns: { payload: { aps: { sound: 'default' } } },
  };
  const results = await Promise.all(rows.map((r) => sendTo(env, r.token, message).catch(() => false)));
  return results.filter(Boolean).length;
}

/// Qurilma tokenini ro'yxatdan o'tkazish. Bitta token bir vaqtda faqat bitta
/// egaga tegishli: foydalanuvchi rol almashtirsa eski bog'lanish yangilanadi.
export async function registerToken(env, context, input) {
  const token = String(input.token || '').trim();
  if (token.length < 20 || token.length > 4096) return { ok: false };
  const platform = ['android', 'ios', 'web'].includes(input.platform) ? input.platform : 'android';
  const stamp = new Date().toISOString();
  await run(env, `INSERT INTO push_tokens(token, user_id, courier_id, shop_id, platform, created_at, seen_at)
    VALUES(?,?,?,?,?,?,?)
    ON CONFLICT(token) DO UPDATE SET user_id=excluded.user_id, courier_id=excluded.courier_id,
      shop_id=excluded.shop_id, platform=excluded.platform, seen_at=excluded.seen_at`,
    [token, context.user?.id ?? null, context.courier?.id ?? null, context.shop?.id ?? null, platform, stamp, stamp]);
  return { ok: true };
}

export async function unregisterToken(env, input) {
  const token = String(input.token || '').trim();
  if (token) await run(env, 'DELETE FROM push_tokens WHERE token=?', [token]);
  return { ok: true };
}

/// Kunlik turtki: buyurtma bor, lekin kuryer kam bo'lsa — offline kuryerlarga
/// "onlayn bo'ling" xabari. Matn haqiqiy songa asoslanadi, shuning uchun
/// qurilmadagi oldindan yozilgan eslatmadan foydaliroq.
export async function nudgeOfflineCouriers(env) {
  if (!pushEnabled(env)) return 0;
  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const demand = await one(env,
    "SELECT COUNT(*) AS n FROM orders WHERE created_at>? AND archived=0", [since]);
  const orders = Number(demand?.n || 0);
  // Buyurtma yo'q bo'lsa bezovta qilishning ma'nosi yo'q
  if (orders < 3) return 0;
  const idle = await all(env,
    `SELECT id FROM couriers WHERE active=1 AND online=0
     AND (location_at IS NULL OR location_at < ?)`, [since]);
  let sent = 0;
  for (const courier of idle) {
    sent += await push(env, { courierId: courier.id }, {
      title: 'Bugun buyurtmalar ko\'p',
      body: `Oxirgi sutkada ${orders} ta buyurtma berildi. Onlayn bo'ling — xaridorlar sizni xaritada ko'rishsin.`,
      data: { type: 'nudge' },
    });
  }
  return sent;
}
