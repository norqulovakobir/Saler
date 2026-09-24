export const REGIONS = [
  'Toshkent shahri', 'Toshkent viloyati', 'Andijon', "Farg'ona", 'Namangan', 'Samarqand', 'Buxoro', 'Navoiy',
  'Qashqadaryo', 'Surxondaryo', 'Jizzax', 'Sirdaryo', 'Xorazm', "Qoraqalpog'iston",
];

const REGION_COORDS = {
  'Toshkent shahri': [41.311, 69.240], 'Toshkent viloyati': [41.040, 69.357], Andijon: [40.783, 72.344], "Farg'ona": [40.389, 71.787],
  Namangan: [40.998, 71.673], Samarqand: [39.655, 66.960], Buxoro: [39.768, 64.421], Navoiy: [40.103, 65.374],
  Qashqadaryo: [38.861, 65.790], Surxondaryo: [37.224, 67.278], Jizzax: [40.116, 67.842], Sirdaryo: [40.490, 68.784],
  Xorazm: [41.550, 60.631], "Qoraqalpog'iston": [42.460, 59.603],
};

const PURPOSES = {
  buyer: 'Hisobni tasdiqlash',
  seller: "Do'kon ochish",
  courier: "Kuryer sifatida ro'yxatdan o'tish",
  cargo: "Yuk tashuvchi sifatida ro'yxatdan o'tish",
  reset: 'Parolni tiklash',
};

// Cloudflare Workers Web Crypto PBKDF2 uchun hozirgi yuqori chegara 100 000.
// 210 000 ishlatilsa account yaratishda NotSupportedError yuz beradi.
const PBKDF2_ITERATIONS = 100000;

export class HttpError extends Error {
  constructor(status, message, extra = {}) {
    super(message);
    this.status = status;
    this.extra = extra;
  }
}

export const now = () => new Date().toISOString();
export const str = (value, fallback = '') => value == null ? fallback : String(value);
export const num = (value, fallback = 0) => {
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
};
export const bool = (value) => value === true || value === 1 || value === '1';

export function json(value, init = {}) {
  const headers = new Headers(init.headers || {});
  headers.set('Content-Type', 'application/json; charset=utf-8');
  headers.set('Access-Control-Allow-Origin', '*');
  headers.set('Access-Control-Allow-Headers', 'Authorization, Content-Type, X-Device, X-App, X-Location');
  headers.set('Access-Control-Allow-Methods', 'GET, POST, PUT, PATCH, DELETE, OPTIONS');
  return new Response(JSON.stringify(value), { ...init, headers });
}

export function cors(response) {
  const headers = new Headers(response.headers);
  headers.set('Access-Control-Allow-Origin', '*');
  headers.set('Access-Control-Allow-Headers', 'Authorization, Content-Type, X-Device, X-App, X-Location');
  headers.set('Access-Control-Allow-Methods', 'GET, POST, PUT, PATCH, DELETE, OPTIONS');
  return new Response(response.body, { status: response.status, statusText: response.statusText, headers });
}

export async function body(request) {
  const type = request.headers.get('content-type') || '';
  if (!type.includes('application/json')) return {};
  try {
    const value = await request.json();
    return value && typeof value === 'object' && !Array.isArray(value) ? value : {};
  } catch {
    throw new HttpError(400, "So'rov ma'lumoti noto'g'ri");
  }
}

export async function all(env, sql, params = []) {
  const result = await env.DB.prepare(sql).bind(...params).all();
  return result.results || [];
}

export async function one(env, sql, params = []) {
  return (await env.DB.prepare(sql).bind(...params).first()) || null;
}

export async function run(env, sql, params = []) {
  return env.DB.prepare(sql).bind(...params).run();
}

export function parseJson(value, fallback = {}) {
  if (value == null || value === '') return fallback;
  if (typeof value === 'object') return value;
  try { return JSON.parse(value); } catch { return fallback; }
}

export function parseList(value) {
  const out = parseJson(value, []);
  return Array.isArray(out) ? out : [];
}

function randomBytes(size) {
  const bytes = new Uint8Array(size);
  crypto.getRandomValues(bytes);
  return bytes;
}

function b64Url(bytes) {
  let raw = '';
  for (const byte of bytes) raw += String.fromCharCode(byte);
  return btoa(raw).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

function fromB64Url(value) {
  const raw = atob(value.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((value.length + 3) % 4));
  return Uint8Array.from(raw, (char) => char.charCodeAt(0));
}

export const newId = (prefix = '') => `${prefix}${b64Url(randomBytes(12))}`;
export const newToken = () => b64Url(randomBytes(32));

export async function sha256(value) {
  const bytes = new TextEncoder().encode(String(value));
  const hash = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes));
  return [...hash].map((x) => x.toString(16).padStart(2, '0')).join('');
}

function sameText(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i += 1) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

export async function hashPassword(password) {
  const salt = randomBytes(16);
  const source = new TextEncoder().encode(String(password));
  const key = await crypto.subtle.importKey('raw', source, 'PBKDF2', false, ['deriveBits']);
  const derived = await crypto.subtle.deriveBits(
    { name: 'PBKDF2', hash: 'SHA-256', salt, iterations: PBKDF2_ITERATIONS }, key, 256,
  );
  return `pbkdf2$${PBKDF2_ITERATIONS}$${b64Url(salt)}$${b64Url(new Uint8Array(derived))}`;
}

export async function checkPassword(password, stored) {
  const [kind, rounds, saltText, expected] = str(stored).split('$');
  const iterations = Number(rounds);
  if (kind !== 'pbkdf2' || !Number.isInteger(iterations) || iterations < 100000 || iterations > PBKDF2_ITERATIONS || !saltText || !expected) return false;
  try {
    const source = new TextEncoder().encode(String(password));
    const key = await crypto.subtle.importKey('raw', source, 'PBKDF2', false, ['deriveBits']);
    const derived = await crypto.subtle.deriveBits(
      { name: 'PBKDF2', hash: 'SHA-256', salt: fromB64Url(saltText), iterations }, key, 256,
    );
    return sameText(b64Url(new Uint8Array(derived)), expected);
  } catch {
    return false;
  }
}

export const normEmail = (value) => {
  const email = str(value).trim().toLowerCase();
  return email.length <= 120 && /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email) ? email : null;
};

export const normPhone = (value) => {
  const digits = str(value).replace(/\D/g, '');
  if (digits.length === 9) return `+998${digits}`;
  if (digits.length === 12 && digits.startsWith('998')) return `+${digits}`;
  return null;
};

export function personName(value, label) {
  const clean = str(value).trim().replace(/\s+/g, ' ').slice(0, 40);
  if (clean.length < 2) throw new HttpError(400, `${label}ni kiriting`, { field: label === 'Ism' ? 'firstName' : 'lastName' });
  return clean;
}

export function needPhone(value) {
  const phone = normPhone(value);
  if (!phone) throw new HttpError(400, "Telefon raqamini to'liq kiriting: +998 XX XXX XX XX", { field: 'phone' });
  return phone;
}

export function needEmail(value) {
  const email = normEmail(value);
  if (!email) throw new HttpError(400, "Email manzilini to'g'ri kiriting", { field: 'email' });
  return email;
}

export function needLogin(value) {
  const login = str(value).trim().toLowerCase();
  if (!/^[a-z0-9_.]{3,30}$/.test(login)) {
    throw new HttpError(400, 'Login 3–30 belgi: lotin harflari, raqam, _ yoki .', { field: 'login' });
  }
  return login;
}

export function needPassword(value) {
  const password = str(value);
  if (password.length < 6) throw new HttpError(400, 'Parol kamida 6 belgi', { field: 'password' });
  if (password.length > 100) throw new HttpError(400, 'Parol juda uzun', { field: 'password' });
  return password;
}

export function needTelegram(value) {
  const raw = str(value).trim().replace(/^https?:\/\/(www\.)?t\.me\//i, '');
  const username = raw.replace(/^@/, '');
  if (/^[A-Za-z][A-Za-z0-9_]{4,31}$/.test(username)) return `@${username}`;
  const phone = normPhone(raw);
  if (phone) return phone;
  throw new HttpError(400, 'Telegram: @username yoki telefon raqamini kiriting', { field: 'telegram' });
}

export function distanceKm(lat1, lon1, lat2, lon2) {
  if ([lat1, lon1, lat2, lon2].some((value) => !Number.isFinite(Number(value)))) return null;
  const rad = (degree) => degree * Math.PI / 180;
  const dLat = rad(Number(lat2) - Number(lat1));
  const dLon = rad(Number(lon2) - Number(lon1));
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(rad(Number(lat1))) * Math.cos(rad(Number(lat2))) * Math.sin(dLon / 2) ** 2;
  return Math.round(6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a)) * 10) / 10;
}

export function regionRouteKm(from, to) {
  const a = REGION_COORDS[from];
  const b = REGION_COORDS[to];
  if (!a || !b) return null;
  if (from === to) return 40;
  return Math.round(distanceKm(a[0], a[1], b[0], b[1]) * 1.25);
}

export const tariffPrice = (base, perKm, km) => {
  if (km == null || (!num(base) && !num(perKm))) return null;
  return Math.round((num(base) + num(perKm) * km) / 1000) * 1000;
};

export const shopLevel = (sales) => {
  if (num(sales) >= 30) return 'Platina';
  if (num(sales) >= 15) return 'Oltin';
  if (num(sales) >= 5) return 'Kumush';
  if (num(sales) >= 1) return 'Bronza';
  return 'Yangi';
};

export const shopRating = (sales) => Math.min(5, Math.round((1 + Math.log10(1 + num(sales)) * 1.6) * 10) / 10);

const IMAGE_EXTENSIONS = {
  'image/jpeg': 'jpg',
  'image/jpg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
  'image/avif': 'avif',
  'image/gif': 'gif',
};

const immutableMediaCache = 'public, max-age=31536000, immutable';

/// Ilovada saqlanadigan rasm reference'i faqat Worker yaratgan shaklda bo'lishi
/// mumkin. Bu `data:` bo'lmagan ixtiyoriy matnni keyinchalik URL sifatida
/// ishlatib yuborishning oldini oladi.
export function isMediaRef(value) {
  const ref = str(value).trim();
  return /^r2:images\/\d{4}\/\d{2}\/ph_[A-Za-z0-9_-]{12,}\.(?:jpg|png|webp|avif|gif)$/.test(ref);
}

/// Rasmlar faqat R2 da saqlanadi. Binding yo'q bo'lsa yuklash to'xtaydi —
/// jimgina D1 ga yozib, uning 5 GB ini rasmlar bilan to'ldirmaslik uchun.
export const r2Enabled = (env) => Boolean(
  env && env.MEDIA && typeof env.MEDIA.put === 'function' && typeof env.MEDIA.get === 'function',
);

function imageBuffer(value) {
  if (value instanceof ArrayBuffer) return value;
  if (ArrayBuffer.isView(value)) {
    return value.buffer.slice(value.byteOffset, value.byteOffset + value.byteLength);
  }
  throw new HttpError(400, "Rasm ma'lumoti noto'g'ri");
}

function validImageMime(value) {
  const mime = str(value).toLowerCase().split(';')[0].trim();
  if (!IMAGE_EXTENSIONS[mime]) throw new HttpError(400, 'JPEG, PNG, WebP, AVIF yoki GIF rasm yuklang', { field: 'image' });
  return mime;
}

function r2Key(ref, mime) {
  const month = new Date().toISOString().slice(0, 7).replace('-', '/');
  return `images/${month}/${ref}.${IMAGE_EXTENSIONS[mime]}`;
}

function mediaHeaders(mime) {
  return new Headers({
    'Content-Type': mime,
    'Cache-Control': immutableMediaCache,
    'Access-Control-Allow-Origin': '*',
  });
}

export async function storeImageBytes(env, value, mime, { maxBytes = 4 * 1024 * 1024 } = {}) {
  const imageMime = validImageMime(mime);
  const bytes = imageBuffer(value);
  if (!bytes.byteLength) throw new HttpError(400, "Rasm bo'sh");
  if (bytes.byteLength > maxBytes) {
    throw new HttpError(400, `Rasm juda katta (maks ${Math.floor(maxBytes / 1024 / 1024)} MB)`, { field: 'image' });
  }

  if (!r2Enabled(env)) throw new HttpError(503, 'Rasm ombori ulanmagan');

  const key = r2Key(newId('ph_'), imageMime);
  try {
    await env.MEDIA.put(key, bytes, {
      httpMetadata: { contentType: imageMime, cacheControl: immutableMediaCache },
    });
  } catch (error) {
    console.error('R2 media upload error', error);
    throw new HttpError(502, 'Rasm omboriga yuklab bo\'lmadi. Keyinroq urinib ko\'ring');
  }
  // Kalitni ma'lumotlar jadvalida saqlash shart emas: ref ichida R2 kaliti
  // bor. Shunday qilib D1 faqat biznes ma'lumotlari uchun qoladi.
  return `r2:${key}`;
}

export async function storeDataUri(env, value, { maxBytes = 900 * 1024 } = {}) {
  if (value == null || value === '') return null;
  if (typeof value !== 'string') throw new HttpError(400, "Rasm ma'lumoti noto'g'ri");
  // Oldin yuklangan ref qayta saqlanmaydi. Shu xususiyat mahsulotni
  // tahrirlashda R2 obyektlarini yana yuklashning oldini oladi.
  if (!value.startsWith('data:')) {
    const ref = value.trim();
    if (!isMediaRef(ref)) throw new HttpError(400, "Rasm ma'lumoti noto'g'ri", { field: 'image' });
    return ref;
  }
  const match = value.match(/^data:([\w/+.-]+);base64,([A-Za-z0-9+/=\s]+)$/s);
  if (!match) throw new HttpError(400, 'Faqat rasm yuklash mumkin');
  let raw;
  try {
    raw = atob(match[2].replace(/\s/g, ''));
  } catch {
    throw new HttpError(400, "Rasm ma'lumoti buzilgan");
  }
  if (raw.length > maxBytes) {
    throw new HttpError(400, `Rasm juda katta (maks ${Math.floor(maxBytes / 1024)} KB)`);
  }
  return storeImageBytes(env, Uint8Array.from(raw, (char) => char.charCodeAt(0)), match[1], { maxBytes });
}

export async function mediaResponse(env, ref, request = null, execution = null) {
  if (ref.startsWith('r2:')) {
    const key = ref.slice(3);
    if (!key.startsWith('images/') || key.includes('..') || key.length > 220) {
      throw new HttpError(404, 'Rasm topilmadi');
    }
    if (!r2Enabled(env)) throw new HttpError(503, 'Rasm ombori hali ulanmagan');

    // Cache API R2 dan bir xil rasmni qayta-qayta o'qishni kamaytiradi.
    // Cache kalitida Authorization bo'lmagani uchun bitta ommaviy rasm
    // barcha foydalanuvchilar uchun bitta edge cache nusxasidan ochiladi.
    const cache = typeof caches !== 'undefined' ? caches.default : null;
    const cacheKey = cache && request
      ? new Request(new URL(request.url).origin + `/api/photo/${encodeURIComponent(ref)}`)
      : null;
    if (cacheKey) {
      const cached = await cache.match(cacheKey);
      if (cached) return cached;
    }

    const object = await env.MEDIA.get(key);
    if (!object) throw new HttpError(404, 'Rasm topilmadi');
    const headers = mediaHeaders(object.httpMetadata?.contentType || 'application/octet-stream');
    if (typeof object.writeHttpMetadata === 'function') object.writeHttpMetadata(headers);
    headers.set('Cache-Control', immutableMediaCache);
    if (object.httpEtag) headers.set('ETag', object.httpEtag);
    if (request && object.httpEtag && request.headers.get('if-none-match') === object.httpEtag) {
      return new Response(null, { status: 304, headers });
    }
    const response = new Response(object.body, { headers });
    if (cacheKey) {
      const save = cache.put(cacheKey, response.clone()).catch((error) => console.warn('R2 cache write error', error));
      if (execution?.waitUntil) execution.waitUntil(save);
      else await save;
    }
    return response;
  }

  // Faqat r2: shaklidagi ref qoladi — eski D1 BLOB'lari R2 ga ko'chirilgan.
  throw new HttpError(404, 'Rasm topilmadi');
}

function emailHtml({ name, code, purpose }) {
  const title = PURPOSES[purpose] || 'Tasdiqlash';
  const safeName = escapeHtml(name || 'Foydalanuvchi');
  return `<!doctype html><html lang="uz"><body style="margin:0;background:#f5f6f8;font-family:Arial,sans-serif;color:#15202b"><div style="max-width:520px;margin:32px auto;background:#fff;border-radius:18px;padding:32px"><div style="font-size:22px;font-weight:800">Rydex</div><h1 style="font-size:22px;margin:28px 0 8px">${escapeHtml(title)}</h1><p>Salom, ${safeName}. Tasdiqlash kodingiz:</p><div style="letter-spacing:9px;font-size:32px;font-weight:800;background:#f1f5ff;border-radius:12px;padding:18px 22px;text-align:center">${code}</div><p style="margin-top:24px;color:#667085">Kod 10 daqiqa amal qiladi. Uni hech kimga bermang.</p></div></body></html>`;
}

export function escapeHtml(value) {
  return str(value).replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]));
}

export async function sendCode(env, { email, purpose, name }) {
  if (!PURPOSES[purpose]) throw new HttpError(400, "Noma'lum amal");
  const previous = await one(env, 'SELECT * FROM email_codes WHERE email=? AND purpose=?', [email, purpose]);
  const current = Date.now();
  if (previous) {
    const since = current - new Date(previous.sent_at).getTime();
    if (since < 60_000) {
      const retryAfter = Math.max(1, Math.ceil((60_000 - since) / 1000));
      throw new HttpError(429, `Kodni qayta yuborish uchun ${retryAfter} soniya kuting`, { retryAfter });
    }
    const withinHour = current - new Date(previous.window_at).getTime() < 3_600_000;
    if (withinHour && num(previous.sent_count) >= 6) {
      throw new HttpError(429, "Juda ko'p urinish. Bir soatdan keyin qayta urinib ko'ring");
    }
  }
  if (!env.BREVO_API_KEY || !env.BREVO_SENDER_EMAIL) {
    throw new HttpError(503, "Email xizmati hali to'liq sozlanmagan. Keyinroq urinib ko'ring");
  }
  const code = String(crypto.getRandomValues(new Uint32Array(1))[0] % 1_000_000).padStart(6, '0');
  let response;
  try {
    response = await fetch('https://api.brevo.com/v3/smtp/email', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'api-key': env.BREVO_API_KEY },
      body: JSON.stringify({
        sender: { email: env.BREVO_SENDER_EMAIL, name: env.BREVO_SENDER_NAME || 'Rydex' },
        to: [{ email, name: name || 'Foydalanuvchi' }],
        subject: `Rydex — ${PURPOSES[purpose]} kodi`,
        htmlContent: emailHtml({ name, code, purpose }),
      }),
    });
  } catch (error) {
    console.error('Brevo transport error', error);
    throw new HttpError(502, "Emailga kod yuborib bo'lmadi. Internet yoki email sozlamasini tekshiring");
  }
  if (!response.ok) {
    console.error('Brevo email error', response.status, await response.text().catch(() => ''));
    throw new HttpError(502, "Emailga kod yuborib bo'lmadi. Email manzilini tekshirib, qayta urinib ko'ring");
  }
  const timestamp = now();
  const previousWindowIsOld = !previous || current - new Date(previous.window_at).getTime() >= 3_600_000;
  await run(env, `INSERT INTO email_codes(email, purpose, code_hash, attempts, sent_at, expires_at, sent_count, window_at)
    VALUES(?,?,?,?,?,?,?,?)
    ON CONFLICT(email,purpose) DO UPDATE SET
      code_hash=excluded.code_hash, attempts=0, sent_at=excluded.sent_at, expires_at=excluded.expires_at,
      sent_count=CASE WHEN email_codes.window_at < ? THEN 1 ELSE email_codes.sent_count + 1 END,
      window_at=CASE WHEN email_codes.window_at < ? THEN excluded.window_at ELSE email_codes.window_at END`, [
    email, purpose, await sha256(`${email}|${purpose}|${code}`), 0, timestamp,
    new Date(current + 10 * 60_000).toISOString(), 1, timestamp,
    new Date(current - 3_600_000).toISOString(), new Date(current - 3_600_000).toISOString(),
  ]);
  return { codeSent: true, email, expiresIn: 600, resendIn: 60 };
}

export async function checkCode(env, { email, purpose, code }) {
  const row = await one(env, 'SELECT * FROM email_codes WHERE email=? AND purpose=?', [email, purpose]);
  if (!row) throw new HttpError(400, 'Avval tasdiqlash kodini oling', { codeInvalid: true });
  if (new Date(row.expires_at).getTime() < Date.now()) throw new HttpError(400, "Kodning muddati tugagan. Yangi kod oling", { codeExpired: true });
  if (num(row.attempts) >= 5) throw new HttpError(429, "Kod ko'p marta xato kiritildi. Yangi kod oling", { codeExpired: true });
  const normalized = str(code).replace(/\D/g, '');
  const actual = await sha256(`${email}|${purpose}|${normalized}`);
  if (normalized.length !== 6 || !sameText(actual, row.code_hash)) {
    await run(env, 'UPDATE email_codes SET attempts=attempts+1 WHERE email=? AND purpose=?', [email, purpose]);
    const left = 4 - num(row.attempts);
    throw new HttpError(400, left > 0 ? `Kod noto'g'ri. Yana ${left} ta urinish qoldi` : "Kod noto'g'ri. Yangi kod oling", { codeInvalid: true, codeExpired: left <= 0 });
  }
}

export const consumeCode = (env, email, purpose) => run(env, 'DELETE FROM email_codes WHERE email=? AND purpose=?', [email, purpose]);

export async function loadContext(request, env) {
  const match = (request.headers.get('authorization') || '').match(/^Bearer\s+(.+)$/i);
  if (!match) throw new HttpError(401, "Token yo'q");
  const session = await one(env, 'SELECT * FROM sessions WHERE token=?', [match[1]]);
  if (!session) throw new HttpError(401, 'Token eskirgan');
  const user = await one(env, 'SELECT * FROM users WHERE id=?', [session.user_id]);
  if (!user) throw new HttpError(401, 'Foydalanuvchi topilmadi');
  const [shop, courier] = await Promise.all([
    session.shop_id ? one(env, 'SELECT * FROM shops WHERE id=?', [session.shop_id]) : null,
    session.courier_id ? one(env, 'SELECT * FROM couriers WHERE id=?', [session.courier_id]) : null,
  ]);
  return { token: match[1], session, user, shop, courier };
}

export function needBuyer(ctx) {
  if (!ctx.user.registered_at) {
    throw new HttpError(403, "Davom etish uchun ismingiz, telefon va emailingizni tasdiqlang", { needAuth: true });
  }
  if (bool(ctx.user.blocked)) throw new HttpError(403, "Hisobingiz bloklangan. Qo'llab-quvvatlash xizmatiga murojaat qiling");
  return ctx.user;
}

export function needShop(ctx) {
  if (!ctx.shop) throw new HttpError(403, 'Sotuvchi sifatida kiring');
  if (!bool(ctx.shop.active)) throw new HttpError(403, "Do'koningiz bloklangan. Qo'llab-quvvatlash xizmatiga murojaat qiling");
  return ctx.shop;
}

export function needCourier(ctx) {
  if (!ctx.courier) throw new HttpError(403, 'Kuryer sifatida kiring');
  if (!bool(ctx.courier.active)) throw new HttpError(403, "Hisobingiz bloklangan. Qo'llab-quvvatlash xizmatiga murojaat qiling");
  return ctx.courier;
}

export function publicUser(user) {
  return {
    id: user.id, name: user.name, firstName: user.first_name || '', lastName: user.last_name || '', phone: user.phone || null,
    email: user.email || null, telegram: user.telegram || null, emailVerified: Boolean(user.email_verified_at), registered: Boolean(user.registered_at),
  };
}

export function serializeShop(shop, extra = {}) {
  const sales = num(shop.sales);
  return {
    id: shop.id, name: shop.name, sellerName: shop.seller_name || 'Madina', ownerName: shop.owner_name || '', phone: shop.phone || '', logo: shop.logo || null,
    description: shop.description || '', login: shop.login || null, firstName: shop.first_name || '', lastName: shop.last_name || '', email: shop.email || '',
    emailVerified: Boolean(shop.email_verified_at), region: shop.region || '',
    location: shop.lat != null && shop.lon != null ? { lat: num(shop.lat), lon: num(shop.lon), address: shop.address || '' } : null,
    productCount: num(shop.product_count), sales, rating: shopRating(sales), level: shopLevel(sales), followers: num(shop.followers),
    createdAt: shop.created_at, ...extra,
  };
}

export function serializeProduct(product) {
  return {
    id: product.id, shopId: product.shop_id, name: product.name, category: product.category || null, price: num(product.price),
    description: product.description || '', photos: parseList(product.photos), active: bool(product.active), views: num(product.views), createdAt: product.created_at,
  };
}

export function serializeOrder(order) {
  return {
    id: order.id, status: order.status, createdAt: order.created_at, productName: order.product_name, price: num(order.price),
    customerName: order.customer_name || '', phone: order.phone || '', address: order.address || '', buyerLink: order.customer_name || 'Ilova',
    items: parseList(order.items), shopId: order.shop_id, shopName: order.shop_name || '', shopPhone: order.shop_phone || '',
    courierId: order.courier_id || null, deliveryStatus: order.delivery_status || null,
    shopLocation: order.shop_lat != null && order.shop_lon != null ? { lat: num(order.shop_lat), lon: num(order.shop_lon), address: order.shop_address || '' } : null,
    location: order.lat != null && order.lon != null ? { lat: num(order.lat), lon: num(order.lon) } : null,
    courierName: order.courier_name || '', courierPhone: order.courier_phone || '',
    deliveryFee: order.delivery_fee != null ? num(order.delivery_fee) : null, routeKm: order.route_km != null ? num(order.route_km) : null,
    pickedAt: order.picked_at || null, deliveredAt: order.delivered_at || null,
  };
}

export function serializeCourier(courier, extra = {}) {
  return {
    id: courier.id, type: courier.type, name: courier.name, phone: courier.phone || '', email: courier.email || '', login: courier.login || '', photo: courier.photo || null,
    firstName: courier.first_name || '', lastName: courier.last_name || '', region: courier.region || '', plate: courier.plate || '',
    emailVerified: Boolean(courier.email_verified_at), active: bool(courier.active), vehicle: courier.vehicle || 'car', vehicleType: courier.vehicle_type || '',
    capacityKg: num(courier.capacity_kg), regions: parseList(courier.regions), pricePerKm: num(courier.price_per_km), basePrice: num(courier.base_price),
    about: courier.about || '', online: bool(courier.online),
    location: courier.lat != null && courier.lon != null
      ? {
        lat: num(courier.lat),
        lon: num(courier.lon),
        updatedAt: courier.location_at || null,
        // Harakat tomoni (gradus) va tezlik (m/s) — xaritada belgini
        // burish va kelish vaqtini baholash uchun.
        heading: courier.heading != null ? num(courier.heading) : null,
        speed: courier.speed != null ? num(courier.speed) : null,
      }
      : null,
    deliveries: num(courier.deliveries), rating: num(courier.rating, 5), createdAt: courier.created_at, ...extra,
  };
}

export function serializeCargo(order) {
  const km = order.kind === 'cargo' ? regionRouteKm(order.from_region, order.to_region) : null;
  return {
    id: order.id, status: order.status, kind: order.kind, fromRegion: order.from_region || '', toRegion: order.to_region || '', date: order.date || '', cargo: order.cargo || '',
    weightKg: num(order.weight_kg), customerName: order.customer_name || '', phone: order.phone || '', address: order.address || '',
    carrierName: order.carrier_name || '', carrierPhone: order.carrier_phone || '', carrierId: order.carrier_id || null, createdAt: order.created_at,
    price: order.price != null ? num(order.price) : null, distanceKm: km,
    suggestedPrice: tariffPrice(order.carrier_base, order.carrier_per_km, km), acceptedAt: order.accepted_at || null, doneAt: order.done_at || null,
  };
}

export async function notifyShop(env, shopId, type, title, text, meta = {}) {
  await run(env, 'INSERT INTO notifications(id, shop_id, type, title, text, meta, read, created_at) VALUES(?,?,?,?,?,?,0,?)', [
    newId('n_'), shopId, type, title, text, JSON.stringify(meta), now(),
  ]);
}

export async function shopWithStats(env, id) {
  return one(env, `SELECT s.*,
    (SELECT COUNT(*) FROM products p WHERE p.shop_id=s.id AND p.active=1) AS product_count,
    (SELECT COUNT(*) FROM orders o WHERE o.shop_id=s.id AND o.status='done' AND o.archived=0) AS sales,
    (SELECT COUNT(*) FROM follows f WHERE f.shop_id=s.id) AS followers
    FROM shops s WHERE s.id=?`, [id]);
}

export const cleanPhotoRefs = async (env, photos) => {
  if (!Array.isArray(photos)) throw new HttpError(400, "Rasmlar ro'yxati noto'g'ri", { field: 'photos' });
  if (photos.length > 10) throw new HttpError(400, "Ko'pi bilan 10 ta rasm yuklash mumkin", { field: 'photos' });
  const refs = [];
  for (const photo of photos) {
    const ref = await storeDataUri(env, photo);
    if (ref) refs.push(ref);
  }
  return refs;
};
