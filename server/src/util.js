import crypto from 'node:crypto';
import { q } from './db.js';

export const newId = (prefix = '') => prefix + crypto.randomBytes(8).toString('hex');
export const newToken = () => crypto.randomBytes(24).toString('hex');

export function hashPassword(pw) {
  const salt = crypto.randomBytes(16).toString('hex');
  const hash = crypto.scryptSync(String(pw), salt, 32).toString('hex');
  return `${salt}:${hash}`;
}
export function checkPassword(pw, stored) {
  if (!stored) return false;
  const [salt, hash] = stored.split(':');
  const test = crypto.scryptSync(String(pw), salt, 32).toString('hex');
  return crypto.timingSafeEqual(Buffer.from(hash, 'hex'), Buffer.from(test, 'hex'));
}

export class HttpError extends Error {
  constructor(status, message, extra = {}) { super(message); this.status = status; this.extra = extra; }
}

/** Express async handler wrapper */
export const ah = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

/** Haversine masofa (km) */
export function distanceKm(lat1, lon1, lat2, lon2) {
  if ([lat1, lon1, lat2, lon2].some((v) => v == null || Number.isNaN(Number(v)))) return null;
  const R = 6371, toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1), dLon = toRad(lon2 - lon1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
  return Math.round(R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a)) * 10) / 10;
}

/** data:image/...;base64,... -> photos jadvaliga saqlab, ref qaytaradi. Oddiy ref bo'lsa o'zini qaytaradi. */
export async function storeDataUri(s) {
  if (typeof s !== 'string' || !s) return null;
  const m = s.match(/^data:([\w/+.-]+);base64,(.+)$/s);
  if (!m) return s;
  const buf = Buffer.from(m[2], 'base64');
  if (buf.length > 6 * 1024 * 1024) throw new HttpError(400, 'Rasm juda katta (maks 6MB)');
  const ref = newId('ph_');
  await q('INSERT INTO photos(ref, mime, data) VALUES($1,$2,$3)', [ref, m[1], buf]);
  return ref;
}

/** Do'kon darajasi: bajarilgan sotuvlar soniga qarab */
export function shopLevel(sales) {
  if (sales >= 30) return 'Platina';
  if (sales >= 15) return 'Oltin';
  if (sales >= 5) return 'Kumush';
  if (sales >= 1) return 'Bronza';
  return 'Yangi';
}
export function shopRating(sales) {
  return Math.min(5, Math.round((1 + Math.log10(1 + sales) * 1.6) * 10) / 10);
}

export const REGIONS = [
  'Toshkent shahri', 'Toshkent viloyati', 'Andijon', "Farg'ona", 'Namangan', 'Samarqand', 'Buxoro', 'Navoiy',
  'Qashqadaryo', 'Surxondaryo', 'Jizzax', 'Sirdaryo', 'Xorazm', "Qoraqalpog'iston",
];

export const day = (d) => new Date(d).toISOString().slice(0, 10);
export const num = (v, d = 0) => { const n = Number(v); return Number.isFinite(n) ? n : d; };
export const str = (v, d = '') => (v == null ? d : String(v));
export const pageArgs = (query, defLimit = 30) => {
  const page = Math.max(1, num(query.page, 1));
  const limit = Math.min(200, Math.max(1, num(query.limit, defLimit)));
  return { page, limit, offset: (page - 1) * limit };
};

/** Server logi (admin /system uchun) — xotirada oxirgi 200 qator */
const logLines = [];
export function log(...args) {
  const line = `${new Date().toISOString()} ${args.map((a) => (typeof a === 'string' ? a : JSON.stringify(a))).join(' ')}`;
  console.log(line);
  logLines.push(line);
  if (logLines.length > 200) logLines.shift();
}
export const logTail = (n = 40) => logLines.slice(-n);
