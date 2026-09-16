import crypto from 'node:crypto';
import { q, one } from './db.js';
import { HttpError, log, normPhone, str } from './util.js';

// EmailJS: https://dashboard.emailjs.com — Email Services (service ID), Email Templates (template ID),
// Account > General (Public key), Account > Security (Private key + "Allow EmailJS API for non-browser applications")
const EMAILJS = {
  service: process.env.EMAILJS_SERVICE_ID || '',
  template: process.env.EMAILJS_TEMPLATE_ID || '',
  publicKey: process.env.EMAILJS_PUBLIC_KEY || '',
  privateKey: process.env.EMAILJS_PRIVATE_KEY || '',
};
export const mailEnabled = !!(EMAILJS.service && EMAILJS.template && EMAILJS.publicKey);
// EmailJS sozlanmagan va server ishlab chiqish rejimida bo'lsa, kod javobda qaytariladi (emulatorda sinash uchun).
// Production'da (NODE_ENV=production) kod hech qachon javobda qaytmaydi.
const devCodes = !mailEnabled && process.env.NODE_ENV !== 'production';
export const mailInfo = { provider: 'EmailJS', enabled: mailEnabled, devCodes, privateKey: !!EMAILJS.privateKey };

export const PURPOSES = {
  buyer: 'Hisobni tasdiqlash',
  seller: "Do'kon ochish",
  courier: "Kuryer sifatida ro'yxatdan o'tish",
  cargo: "Yuk tashuvchi sifatida ro'yxatdan o'tish",
  reset: 'Parolni tiklash',
  password: "Parolni o'zgartirish",
};

export const normEmail = (s) => {
  const e = String(s ?? '').trim().toLowerCase();
  return e.length <= 120 && /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(e) ? e : null;
};
// Kod email bilan birga aynan qaysi amal va qaysi hisob uchun olinganiga
// ham bog'lanadi. Shunda bitta emaildagi kodni boshqa login/profilga olib
// o'tib ishlatib bo'lmaydi.
const codeBinding = (value) => String(value ?? '').trim().slice(0, 180);
const hashCode = (email, purpose, binding, code) => crypto.createHash('sha256')
  .update(`${email}|${purpose}|${binding}|${code}`).digest('hex');
const CODE_TTL_MIN = 10;
const RESEND_SEC = 60;
const MAX_PER_HOUR = 6;
const MAX_ATTEMPTS = 5;

async function deliver({ email, name, code, purpose }) {
  const res = await fetch('https://api.emailjs.com/api/v1.0/email/send', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      service_id: EMAILJS.service,
      template_id: EMAILJS.template,
      user_id: EMAILJS.publicKey,
      ...(EMAILJS.privateKey ? { accessToken: EMAILJS.privateKey } : {}),
      // Shablonda {{to_email}} "To Email" maydoniga, {{code}} matnga qo'yiladi
      template_params: {
        to_email: email, email, to_name: name || 'Foydalanuvchi', name: name || 'Foydalanuvchi',
        code, passcode: code, purpose: PURPOSES[purpose] || '', time: `${CODE_TTL_MIN} daqiqa`, app_name: 'Rydex',
      },
    }),
    signal: AbortSignal.timeout(15000),
  });
  if (!res.ok) throw new Error(`EmailJS ${res.status}: ${(await res.text().catch(() => '')).slice(0, 200)}`);
}

/** 6 xonali kod yaratib emailga yuboradi. Qayta yuborish 60 soniyada bir marta, soatiga 6 martagacha */
export async function sendCode({ email, purpose, name, binding = '' }) {
  if (!PURPOSES[purpose]) throw new HttpError(400, "Noma'lum amal");
  binding = codeBinding(binding);
  const row = await one('SELECT * FROM email_codes WHERE email=$1 AND purpose=$2', [email, purpose]);
  if (row) {
    const since = (Date.now() - new Date(row.sent_at).getTime()) / 1000;
    if (since < RESEND_SEC) {
      const wait = Math.ceil(RESEND_SEC - since);
      throw new HttpError(429, `Kodni qayta yuborish uchun ${wait} soniya kuting`, { retryAfter: wait });
    }
    const fresh = Date.now() - new Date(row.window_at).getTime() < 3600e3;
    if (fresh && row.sent_count >= MAX_PER_HOUR) throw new HttpError(429, "Juda ko'p urinish. Bir soatdan keyin qayta urinib ko'ring");
  }
  const code = String(crypto.randomInt(0, 1_000_000)).padStart(6, '0');
  if (mailEnabled) {
    try {
      await deliver({ email, name, code, purpose });
    } catch (e) {
      log('EmailJS xato', e.message);
      throw new HttpError(502, "Emailga kod yuborib bo'lmadi. Manzilni tekshirib, qayta urinib ko'ring");
    }
  } else if (!devCodes) {
    throw new HttpError(503, "Email xizmati hali sozlanmagan. Keyinroq urinib ko'ring");
  } else {
    log(`[TEST] ${email} (${purpose}) tasdiqlash kodi: ${code}`);
  }
  await q(`INSERT INTO email_codes(email, purpose, binding, code_hash, attempts, sent_at, expires_at, sent_count, window_at)
    VALUES($1,$2,$3,$4,0,now(),now() + make_interval(mins => $5),1,now())
    ON CONFLICT (email, purpose) DO UPDATE SET binding=$3, code_hash=$4, attempts=0, sent_at=now(), expires_at=now() + make_interval(mins => $5),
      sent_count=CASE WHEN email_codes.window_at < now() - interval '1 hour' THEN 1 ELSE email_codes.sent_count + 1 END,
      window_at=CASE WHEN email_codes.window_at < now() - interval '1 hour' THEN now() ELSE email_codes.window_at END`,
  [email, purpose, binding, hashCode(email, purpose, binding, code), CODE_TTL_MIN]);
  q("DELETE FROM email_codes WHERE expires_at < now() - interval '1 day'").catch(() => {});
  return { codeSent: true, email, expiresIn: CODE_TTL_MIN * 60, resendIn: RESEND_SEC, ...(devCodes ? { devCode: code } : {}) };
}

/** Kodni tekshiradi. Noto'g'ri bo'lsa urinish sanaladi; to'g'ri bo'lsa consumeCode bilan o'chiriladi */
export async function checkCode({ email, purpose, code, binding = '' }) {
  const c = String(code ?? '').replace(/\D/g, '');
  binding = codeBinding(binding);
  const row = await one('SELECT * FROM email_codes WHERE email=$1 AND purpose=$2', [email, purpose]);
  if (!row) throw new HttpError(400, 'Avval tasdiqlash kodini oling', { codeInvalid: true });
  if (codeBinding(row.binding) !== binding) {
    throw new HttpError(400, "Bu kod boshqa hisob uchun olingan. Login va emailni tekshiring", { codeInvalid: true });
  }
  if (new Date(row.expires_at) < new Date()) throw new HttpError(400, 'Kodning muddati tugagan. Yangi kod oling', { codeExpired: true });
  if (row.attempts >= MAX_ATTEMPTS) throw new HttpError(429, "Kod ko'p marta xato kiritildi. Yangi kod oling", { codeExpired: true });
  const ok = c.length === 6 && crypto.timingSafeEqual(Buffer.from(hashCode(email, purpose, binding, c)), Buffer.from(row.code_hash));
  if (!ok) {
    await q('UPDATE email_codes SET attempts=attempts+1 WHERE email=$1 AND purpose=$2', [email, purpose]);
    const left = MAX_ATTEMPTS - 1 - row.attempts;
    throw new HttpError(400, left > 0 ? `Kod noto'g'ri. Yana ${left} ta urinish qoldi` : "Kod noto'g'ri. Yangi kod oling", { codeInvalid: true, codeExpired: left <= 0 });
  }
}

export const consumeCode = (email, purpose) => q('DELETE FROM email_codes WHERE email=$1 AND purpose=$2', [email, purpose]);

// ---------- ro'yxatdan o'tish maydonlarini tekshirish ----------
export const personName = (v, what) => {
  const s = str(v).trim().replace(/\s+/g, ' ').slice(0, 40);
  if (s.length < 2) throw new HttpError(400, `${what}ni kiriting`, { field: what === 'Ism' ? 'firstName' : 'lastName' });
  return s;
};
export const needPhone = (v) => { const p = normPhone(v); if (!p) throw new HttpError(400, "Telefon raqamini to'liq kiriting: +998 XX XXX XX XX", { field: 'phone' }); return p; };
export const needEmail = (v) => { const e = normEmail(v); if (!e) throw new HttpError(400, "Email manzilini to'g'ri kiriting", { field: 'email' }); return e; };

/// Email butun tizim bo'ylab bitta hisobga tegishli. account_emails jadvali
/// foydalanuvchi/sotuvchi/kuryer jadvallari orasidagi noyoblikni atomik saqlaydi.
export async function ensureEmailAvailable(email, { type, accountId = null } = {}) {
  const row = await one('SELECT account_type, account_id FROM account_emails WHERE email=$1', [email]);
  if (!row) return null;
  if (row.account_type === type && accountId != null && row.account_id === String(accountId)) return row;
  throw new HttpError(409, "Bu email bilan hisob allaqachon ochilgan. Kirish bo'limidan foydalaning", { field: 'email', accountType: row.account_type });
}

/// Tasdiqlash kodi qabul qilingandan keyin emailni o'sha hisobga biriktiradi.
/// Bir vaqtda ikkita registratsiya bo'lsa ham PRIMARY KEY bittasinigina o'tkazadi.
export async function claimEmail(email, type, accountId) {
  const row = await one(`INSERT INTO account_emails(email, account_type, account_id)
    VALUES($1,$2,$3)
    ON CONFLICT (email) DO UPDATE SET account_type=account_emails.account_type
      WHERE account_emails.account_type=$2 AND account_emails.account_id=$3
    RETURNING email`, [email, type, String(accountId)]);
  if (!row) throw new HttpError(409, "Bu email bilan hisob allaqachon ochilgan. Kirish bo'limidan foydalaning", { field: 'email' });
}

export const releaseEmail = (email, type, accountId) => q(
  'DELETE FROM account_emails WHERE email=$1 AND account_type=$2 AND account_id=$3',
  [email, type, String(accountId)],
);
export const needLogin = (v) => {
  const l = str(v).trim().toLowerCase();
  if (!/^[a-z0-9_.]{3,30}$/.test(l)) throw new HttpError(400, "Login 3–30 belgi: lotin harflari, raqam, _ yoki .", { field: 'login' });
  return l;
};
export const needPassword = (v) => {
  const p = str(v);
  if (p.length < 6) throw new HttpError(400, 'Parol kamida 6 belgi', { field: 'password' });
  if (p.length > 100) throw new HttpError(400, 'Parol juda uzun', { field: 'password' });
  return p;
};
/** @username yoki telefon raqami */
export const needTelegram = (v) => {
  const raw = str(v).trim().replace(/^https?:\/\/(www\.)?t\.me\//i, '');
  const user = raw.replace(/^@/, '');
  if (/^[A-Za-z][A-Za-z0-9_]{4,31}$/.test(user)) return `@${user}`;
  const p = normPhone(raw);
  if (p) return p;
  throw new HttpError(400, "Telegram: @username yoki telefon raqamini kiriting", { field: 'telegram' });
};
