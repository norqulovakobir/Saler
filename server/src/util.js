import crypto from 'node:crypto';
import { q } from './db.js';
import { storageEnabled, uploadPhoto } from './storage.js';

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

/** data:image/...;base64,... -> Supabase Storage'ga (sozlangan bo'lsa) yoki photos jadvaliga saqlab, ref qaytaradi. Oddiy ref bo'lsa o'zini qaytaradi. */
export async function storeDataUri(s) {
  if (typeof s !== 'string' || !s) return null;
  const m = s.match(/^data:([\w/+.-]+);base64,(.+)$/s);
  if (!m) return s;
  if (!m[1].startsWith('image/')) throw new HttpError(400, 'Faqat rasm yuklash mumkin');
  const buf = Buffer.from(m[2], 'base64');
  if (buf.length > 6 * 1024 * 1024) throw new HttpError(400, 'Rasm juda katta (maks 6MB)');
  const ref = newId('ph_');
  if (storageEnabled) await uploadPhoto(ref, buf, m[1]);
  else await q('INSERT INTO photos(ref, mime, data) VALUES($1,$2,$3)', [ref, m[1], buf]);
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

/** Mahsulot nomini solishtirish uchun normallashtirish (katta-kichik harf, tinish belgilari, bo'shliqlar) */
export const nameKey = (s) => String(s || '').normalize('NFKC').toLowerCase().replace(/[^\p{L}\p{N}]+/gu, ' ').trim();

/** data URI rasmining SHA-256 xeshi: bir xil rasmni qayta yuklashni aniqlash uchun */
export function dataUriHash(s) {
  const m = typeof s === 'string' ? s.match(/^data:[\w/+.-]+;base64,(.+)$/s) : null;
  return m ? crypto.createHash('sha256').update(Buffer.from(m[1], 'base64')).digest('hex') : null;
}

/** Telefon raqamini +998XXXXXXXXX ko'rinishiga keltiradi, noto'g'ri bo'lsa null */
export function normPhone(v) {
  const d = String(v || '').replace(/\D/g, '');
  if (d.length === 9) return `+998${d}`;
  if (d.length === 12 && d.startsWith('998')) return `+${d}`;
  return null;
}

/** Ilovadagi mahsulot kategoriyalari (flutter_app/lib/categories.dart bilan bir xil) */
export const CATEGORY_SLUGS = ['school', 'women', 'shoes', 'kids', 'men', 'home', 'beauty', 'accessories', 'electronics', 'toys', 'furniture',
  'adult-products', 'groceries', 'flowers', 'appliances', 'pet-supplies', 'sports', 'car-accessories', 'books', 'jewelry', 'tools', 'garden',
  'health', 'adaptive-products', 'stationery'];

/** Viloyat markazlari (yo'nalish masofasini taxminlash uchun) */
export const REGION_COORDS = {
  'Toshkent shahri': [41.311, 69.240], 'Toshkent viloyati': [41.040, 69.357], Andijon: [40.783, 72.344], "Farg'ona": [40.389, 71.787],
  Namangan: [40.998, 71.673], Samarqand: [39.655, 66.960], Buxoro: [39.768, 64.421], Navoiy: [40.103, 65.374],
  Qashqadaryo: [38.861, 65.790], Surxondaryo: [37.224, 67.278], Jizzax: [40.116, 67.842], Sirdaryo: [40.490, 68.784],
  Xorazm: [41.550, 60.631], "Qoraqalpog'iston": [42.460, 59.603],
};
/** Ikki viloyat orasidagi taxminiy yo'l (km): to'g'ri chiziq × 1.25; bitta viloyat ichida 40 km */
export function regionRouteKm(from, to) {
  const a = REGION_COORDS[from], b = REGION_COORDS[to];
  if (!a || !b) return null;
  if (from === to) return 40;
  return Math.round(distanceKm(a[0], a[1], b[0], b[1]) * 1.25);
}
/** Tarif bo'yicha narx, 1000 so'mga yuvarlanadi */
export const tariffPrice = (base, perKm, km) => (km == null || (!base && !perKm) ? null : Math.round((num(base) + num(perKm) * km) / 1000) * 1000);
export const median = (arr) => { const a = arr.filter((x) => Number.isFinite(x) && x > 0).sort((x, y) => x - y); if (!a.length) return null; const m = Math.floor(a.length / 2); return a.length % 2 ? a[m] : Math.round((a[m - 1] + a[m]) / 2); };

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
