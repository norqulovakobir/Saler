/**
 * Rasm fayllari uchun Supabase Storage (ixtiyoriy).
 * SUPABASE_URL va SUPABASE_SECRET_KEY berilsa, yangi rasmlar Storage'ga yoziladi va bazada joy tejaladi.
 * Berilmasa, rasmlar avvalgidek Postgres'dagi photos jadvalida saqlanadi.
 */
const BASE = (process.env.SUPABASE_URL || '').replace(/\/+$/, '');
const KEY = process.env.SUPABASE_SECRET_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY || '';
export const BUCKET = process.env.SUPABASE_BUCKET || 'photos';
export const storageEnabled = Boolean(BASE && KEY);

function headers(extra = {}) {
  // Yangi kalitlar (sb_secret_...) faqat apikey sarlavhasida yuboriladi, ular JWT emas.
  // Eski service_role kalit (JWT) Authorization sarlavhasida ham talab qilinadi.
  const h = { apikey: KEY, ...extra };
  if (!KEY.startsWith('sb_')) h.Authorization = `Bearer ${KEY}`;
  return h;
}

export const publicUrl = (ref) => `${BASE}/storage/v1/object/public/${BUCKET}/${encodeURIComponent(ref)}`;

export async function uploadPhoto(ref, buf, mime) {
  const r = await fetch(`${BASE}/storage/v1/object/${BUCKET}/${encodeURIComponent(ref)}`, {
    method: 'POST',
    headers: headers({ 'Content-Type': mime, 'Cache-Control': 'max-age=31536000', 'x-upsert': 'true' }),
    body: buf,
  });
  if (!r.ok) throw new Error(`Supabase Storage yuklash xatosi ${r.status}: ${(await r.text()).slice(0, 200)}`);
}

/** Ochiq (public) bucket yo'q bo'lsa yaratadi */
export async function ensureBucket() {
  const r = await fetch(`${BASE}/storage/v1/bucket`, {
    method: 'POST',
    headers: headers({ 'Content-Type': 'application/json' }),
    body: JSON.stringify({ id: BUCKET, name: BUCKET, public: true }),
  });
  if (r.ok) return 'yaratildi';
  const t = await r.text();
  if (r.status === 409 || /already exists|duplicate/i.test(t)) return 'bor';
  throw new Error(`bucket yaratib bo'lmadi ${r.status}: ${t.slice(0, 200)}`);
}
