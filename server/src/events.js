import { EventEmitter } from 'node:events';
import { one } from './db.js';
import { newId } from './util.js';

/**
 * Jonli hodisalar (Server-Sent Events).
 * Ilova GET /api/events ga ulanadi va o'ziga tegishli hodisalarni darhol oladi: yangi buyurtma,
 * holat o'zgarishi, pul tushishi, bildirishnoma. Kanallar: shop:<id>, courier:<id>, user:<id>.
 */
const bus = new EventEmitter();
bus.setMaxListeners(0);

export function emit(targets, type, data = {}) {
  const payload = { type, data, at: new Date().toISOString() };
  for (const t of new Set((targets || []).filter(Boolean))) bus.emit(t, payload);
}

export function sseHandler(req, res) {
  const channels = [`user:${req.user.id}`];
  if (req.shop) channels.push(`shop:${req.shop.id}`);
  if (req.courier) channels.push(`courier:${req.courier.id}`);
  res.set({ 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache, no-transform', Connection: 'keep-alive', 'X-Accel-Buffering': 'no' });
  res.flushHeaders?.();
  const send = (p) => res.write(`event: ${p.type}\ndata: ${JSON.stringify(p)}\n\n`);
  send({ type: 'hello', data: { channels: channels.map((c) => c.split(':')[0]) }, at: new Date().toISOString() });
  channels.forEach((c) => bus.on(c, send));
  // Proksi ulanishni uzib qo'ymasligi uchun muntazam "ping"
  const ping = setInterval(() => res.write(': ping\n\n'), 25000);
  req.on('close', () => {
    clearInterval(ping);
    channels.forEach((c) => bus.off(c, send));
  });
}

/** Do'kon bildirishnomasi: bazaga yoziladi va ilovaga darhol yuboriladi */
export async function notifyShop(shopId, type, title, text, meta = {}) {
  const row = await one('INSERT INTO notifications(id, shop_id, type, title, text, meta) VALUES($1,$2,$3,$4,$5,$6) RETURNING *', [newId('n_'), shopId, type, title, text, JSON.stringify(meta)]);
  emit([`shop:${shopId}`], 'notification', { id: row.id, type, title, text, meta, read: false, createdAt: row.created_at });
  return row;
}

/** So'rov yuborgan qurilma: ilova X-Device, X-App, X-Location sarlavhalarini yuboradi */
export function clientInfo(req) {
  const clip = (s) => String(s || '').replace(/[\r\n]+/g, ' ').trim().slice(0, 120);
  const m = String(req.headers['x-location'] || '').match(/^(-?\d{1,2}(?:\.\d+)?),(-?\d{1,3}(?:\.\d+)?)$/);
  const lat = m ? Number(m[1]) : null, lon = m ? Number(m[2]) : null;
  const ok = lat != null && Math.abs(lat) <= 90 && Math.abs(lon) <= 180;
  const ua = clip(req.headers['user-agent']);
  return {
    device: clip(req.headers['x-device']) || (ua.includes('Mozilla') ? 'Brauzer' : "Noma'lum qurilma"),
    app: clip(req.headers['x-app']) || (ua.includes('Mozilla') ? 'Veb-sayt' : 'Saler AI ilovasi'),
    ip: String(req.ip || '').replace(/^::ffff:/, ''),
    lat: ok ? lat : null,
    lon: ok ? lon : null,
  };
}

/** Koordinatadan joy nomi (OpenStreetMap). Maxfiylik uchun ~1 km aniqlikka yuvarlanadi, natija keshlanadi */
const placeCache = new Map();
export async function placeName(lat, lon) {
  if (lat == null || lon == null) return null;
  const la = lat.toFixed(2), lo = lon.toFixed(2), key = `${la},${lo}`;
  if (placeCache.has(key)) return placeCache.get(key);
  try {
    const r = await fetch(`https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=10&accept-language=uz&lat=${la}&lon=${lo}`, {
      headers: { 'User-Agent': 'saler-ai/1.0 (login notifications)' },
      signal: AbortSignal.timeout(4000),
    });
    const a = (await r.json()).address || {};
    const parts = [a.city || a.town || a.village || a.county || a.state_district, a.state, a.country].filter(Boolean);
    const name = [...new Set(parts)].join(', ') || null;
    placeCache.set(key, name);
    if (placeCache.size > 1000) placeCache.delete(placeCache.keys().next().value);
    return name;
  } catch {
    return null;
  }
}
