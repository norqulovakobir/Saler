import { Router } from 'express';
import { q, one, all } from './db.js';
import { ah, HttpError, newId, hashPassword, checkPassword, storeDataUri, distanceKm, num, str, REGIONS, log } from './util.js';

const r = Router();
const pub = Router();

export const serializeCourier = (c, extra = {}) => ({
  id: c.id, type: c.type, name: c.name, phone: c.phone, email: c.email, login: c.login, photo: c.photo,
  vehicle: c.vehicle, vehicleType: c.vehicle_type, capacityKg: c.capacity_kg, regions: c.regions || [],
  pricePerKm: c.price_per_km, basePrice: c.base_price, about: c.about, online: c.online,
  location: c.lat != null ? { lat: c.lat, lon: c.lon, updatedAt: c.location_at } : null,
  deliveries: c.deliveries, rating: c.rating, createdAt: c.created_at, ...extra,
});
const serializeCargo = (x) => ({
  id: x.id, status: x.status, kind: x.kind, fromRegion: x.from_region, toRegion: x.to_region, date: x.date, cargo: x.cargo,
  weightKg: x.weight_kg, customerName: x.customer_name, phone: x.phone, address: x.address,
  carrierName: x.carrier_name || '', carrierPhone: x.carrier_phone || '', carrierId: x.carrier_id, createdAt: x.created_at,
});
const CARGO_SQL = `SELECT x.*, c.name AS carrier_name, c.phone AS carrier_phone FROM cargo_orders x LEFT JOIN couriers c ON c.id=x.carrier_id`;
const ORDER_SQL = `SELECT o.*, s.name AS shop_name, s.phone AS shop_phone, s.lat AS shop_lat, s.lon AS shop_lon, s.address AS shop_address FROM orders o JOIN shops s ON s.id=o.shop_id`;
const serializeOrder = (o) => ({
  id: o.id, status: o.status, createdAt: o.created_at, productName: o.product_name, price: Number(o.price),
  customerName: o.customer_name, phone: o.phone, address: o.address, buyerLink: o.customer_name || 'Ilova', items: o.items || [],
  shopId: o.shop_id, shopName: o.shop_name || '', shopPhone: o.shop_phone || '', courierId: o.courier_id, deliveryStatus: o.delivery_status,
  shopLocation: o.shop_lat != null ? { lat: o.shop_lat, lon: o.shop_lon, address: o.shop_address } : null,
});

const VEHICLES = ['foot', 'bike', 'moto', 'car'];
const VEHICLE_TYPES = ['labo', 'damas', 'gazel', 'isuzu', 'fura'];
const needCourier = (req) => { if (!req.courier) throw new HttpError(403, 'Kuryer sifatida kiring'); return req.courier; };
const reload = (id) => one('SELECT * FROM couriers WHERE id=$1', [id]);

/** Yangi do'kon buyurtmasiga eng yaqin onlayn kuryerni biriktiradi */
export async function assignCourier(orderId) {
  const o = await one(`${ORDER_SQL} WHERE o.id=$1`, [orderId]);
  if (!o || o.courier_id) return null;
  const rejected = o.rejected_by || [];
  const cs = await all(`SELECT * FROM couriers WHERE active AND online AND type='courier' AND NOT (id = ANY($1))`, [rejected]);
  if (!cs.length) return null;
  const ranked = cs.map((c) => ({ c, d: distanceKm(o.shop_lat, o.shop_lon, c.lat, c.lon) ?? 1e9 })).sort((a, b) => a.d - b.d);
  const pick = ranked[0].c;
  await q("UPDATE orders SET courier_id=$2, delivery_status='assigned' WHERE id=$1", [orderId, pick.id]);
  log('Kuryer biriktirildi', orderId, pick.id);
  return pick.id;
}

// ---------- auth ----------
r.post('/register', ah(async (req, res) => {
  const b = req.body || {};
  const login = str(b.login).trim().toLowerCase(), password = str(b.password);
  if (!str(b.name).trim()) throw new HttpError(400, 'Ismingizni kiriting');
  if (login.length < 3) throw new HttpError(400, 'Login kamida 3 belgi');
  if (password.length < 6) throw new HttpError(400, 'Parol kamida 6 belgi');
  if (await one('SELECT 1 FROM couriers WHERE login=$1', [login])) throw new HttpError(400, 'Bu login band');
  const type = b.type === 'cargo' ? 'cargo' : 'courier';
  const regions = Array.isArray(b.regions) ? b.regions.map(String).filter(Boolean) : [];
  if (type === 'cargo' && !regions.length) throw new HttpError(400, 'Kamida bitta viloyat tanlang');
  const id = newId('c_');
  await q(`INSERT INTO couriers(id, type, name, phone, email, login, pass_hash, vehicle, vehicle_type, capacity_kg, regions, price_per_km, base_price)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)`,
    [id, type, str(b.name).trim(), str(b.phone).trim(), str(b.email).trim(), login, hashPassword(password),
      VEHICLES.includes(b.vehicle) ? b.vehicle : 'moto', type === 'cargo' ? (VEHICLE_TYPES.includes(b.vehicleType) ? b.vehicleType : 'labo') : '',
      num(b.capacityKg), JSON.stringify(regions), num(b.pricePerKm), num(b.basePrice)]);
  await q('UPDATE sessions SET courier_id=$2, shop_id=NULL WHERE token=$1', [req.session.token, id]);
  res.json({ courier: serializeCourier(await reload(id)) });
}));

r.post('/login', ah(async (req, res) => {
  const login = str(req.body?.login).trim().toLowerCase();
  const c = await one('SELECT * FROM couriers WHERE login=$1', [login]);
  if (!c || !checkPassword(str(req.body?.password), c.pass_hash)) throw new HttpError(403, "Login yoki parol noto'g'ri");
  await q('UPDATE sessions SET courier_id=$2, shop_id=NULL WHERE token=$1', [req.session.token, c.id]);
  res.json({ courier: serializeCourier(c) });
}));

r.post('/logout', ah(async (req, res) => {
  if (req.courier) await q('UPDATE couriers SET online=false WHERE id=$1', [req.courier.id]);
  await q('UPDATE sessions SET courier_id=NULL WHERE token=$1', [req.session.token]);
  res.json({ ok: true });
}));

// ---------- location / profile ----------
r.post('/location', ah(async (req, res) => {
  const c = needCourier(req);
  const b = req.body || {};
  const online = b.online !== false;
  if (online && b.lat != null && b.lon != null) {
    await q('UPDATE couriers SET online=true, lat=$2, lon=$3, location_at=now() WHERE id=$1', [c.id, Number(b.lat), Number(b.lon)]);
    // Onlayn bo'lganda kuryersiz yangi buyurtmalarni biriktirish
    for (const o of await all("SELECT id FROM orders WHERE courier_id IS NULL AND status='new' AND NOT archived AND created_at > now() - interval '1 day'")) await assignCourier(o.id);
  } else {
    await q('UPDATE couriers SET online=$2 WHERE id=$1', [c.id, online]);
  }
  res.json({ ok: true, online });
}));

r.put('/profile', ah(async (req, res) => {
  const c = needCourier(req);
  const b = req.body || {};
  const sets = [], vals = [c.id];
  const set = (col, v) => { vals.push(v); sets.push(`${col}=$${vals.length}`); };
  if (b.photo != null) set('photo', await storeDataUri(b.photo));
  if (b.name != null) { const n = str(b.name).trim(); if (!n) throw new HttpError(400, 'Ism bo\'sh'); set('name', n); }
  if (b.phone != null) set('phone', str(b.phone).trim());
  if (b.email != null) set('email', str(b.email).trim());
  if (b.about != null) set('about', str(b.about).trim());
  if (b.vehicle != null && VEHICLES.includes(b.vehicle)) set('vehicle', b.vehicle);
  if (c.type === 'cargo') {
    if (b.vehicleType != null && VEHICLE_TYPES.includes(b.vehicleType)) set('vehicle_type', b.vehicleType);
    if (b.capacityKg != null) set('capacity_kg', num(b.capacityKg));
    if (b.basePrice != null) set('base_price', num(b.basePrice));
    if (b.pricePerKm != null) set('price_per_km', num(b.pricePerKm));
    if (Array.isArray(b.regions)) set('regions', JSON.stringify(b.regions.map(String).filter(Boolean)));
  }
  if (sets.length) await q(`UPDATE couriers SET ${sets.join(', ')} WHERE id=$1`, vals);
  res.json({ courier: serializeCourier(await reload(c.id)) });
}));

// ---------- delivery orders ----------
r.get('/orders', ah(async (req, res) => {
  const c = needCourier(req);
  const rows = await all(`${ORDER_SQL} WHERE o.courier_id=$1 AND o.delivery_status IN ('assigned','picked','delivered') AND o.status<>'cancelled' ORDER BY (o.delivery_status='delivered'), o.created_at DESC LIMIT 100`, [c.id]);
  res.json(rows.map(serializeOrder));
}));

r.patch('/orders/:id', ah(async (req, res) => {
  const c = needCourier(req);
  const status = str(req.body?.status);
  if (!['picked', 'delivered', 'rejected'].includes(status)) throw new HttpError(400, "Status noto'g'ri");
  const o = await one('SELECT * FROM orders WHERE id=$1 AND courier_id=$2', [req.params.id, c.id]);
  if (!o) throw new HttpError(404, 'Buyurtma topilmadi');
  if (status === 'rejected') {
    await q(`UPDATE orders SET courier_id=NULL, delivery_status=NULL, rejected_by = rejected_by || to_jsonb($2::text) WHERE id=$1`, [o.id, c.id]);
    await assignCourier(o.id);
  } else {
    await q('UPDATE orders SET delivery_status=$2 WHERE id=$1', [o.id, status]);
    if (status === 'delivered') {
      await q('UPDATE couriers SET deliveries=deliveries+1 WHERE id=$1', [c.id]);
      await q(`INSERT INTO notifications(id, shop_id, type, title, text) VALUES($1,$2,'order','Yetkazildi',$3)`, [newId('n_'), o.shop_id, `${o.product_name} — ${o.customer_name} ga yetkazildi (kuryer: ${c.name})`]);
    }
  }
  res.json({ ok: true });
}));

// ---------- cargo / direct requests for this courier ----------
r.get('/cargo', ah(async (req, res) => {
  const c = needCourier(req);
  res.json((await all(`${CARGO_SQL} WHERE x.carrier_id=$1 ORDER BY (x.status='new') DESC, x.created_at DESC LIMIT 100`, [c.id])).map(serializeCargo));
}));

r.patch('/cargo/:id', ah(async (req, res) => {
  const c = needCourier(req);
  const status = str(req.body?.status);
  if (!['accepted', 'rejected', 'done'].includes(status)) throw new HttpError(400, "Status noto'g'ri");
  const x = await one('UPDATE cargo_orders SET status=$3 WHERE id=$1 AND carrier_id=$2 RETURNING *', [req.params.id, c.id, status]);
  if (!x) throw new HttpError(404, 'Buyurtma topilmadi');
  if (status === 'done') await q('UPDATE couriers SET deliveries=deliveries+1 WHERE id=$1', [c.id]);
  res.json({ ok: true });
}));

// ---------- public (buyer-facing) ----------
pub.get('/couriers/nearby', ah(async (req, res) => {
  const lat = req.query.lat != null ? Number(req.query.lat) : null, lon = req.query.lon != null ? Number(req.query.lon) : null;
  const rows = await all(`SELECT * FROM couriers WHERE active AND online AND type='courier' AND (location_at IS NULL OR location_at > now() - interval '1 hour') ORDER BY location_at DESC NULLS LAST LIMIT 100`);
  let out = rows.map((c) => serializeCourier(c, { distanceKm: lat != null ? distanceKm(lat, lon, c.lat, c.lon) : null }));
  if (lat != null) out = out.filter((c) => c.distanceKm == null || c.distanceKm <= 50).sort((a, b) => (a.distanceKm ?? 1e9) - (b.distanceKm ?? 1e9));
  res.json(out);
}));

pub.post('/courier-requests', ah(async (req, res) => {
  const b = req.body || {};
  const c = await one("SELECT * FROM couriers WHERE id=$1 AND active", [str(b.courierId)]);
  if (!c) throw new HttpError(404, 'Kuryer topilmadi');
  const id = newId('g_');
  await q(`INSERT INTO cargo_orders(id, user_id, carrier_id, kind, from_region, to_region, cargo, customer_name, phone, address)
    VALUES($1,$2,$3,'direct',$4,$5,$6,$7,$8,$9)`,
    [id, req.user.id, c.id, str(b.from).trim(), str(b.to).trim(), str(b.note).trim(), str(b.name).trim() || req.user.name, str(b.phone).trim(), str(b.from).trim()]);
  res.json({ ok: true, id });
}));

pub.get('/cargo/regions', (_req, res) => res.json(REGIONS));

pub.get('/cargo/carriers', ah(async (req, res) => {
  const from = str(req.query.from).trim(), to = str(req.query.to).trim();
  const rows = await all(`SELECT * FROM couriers WHERE active AND type='cargo' ORDER BY online DESC, deliveries DESC LIMIT 200`);
  const norm = (s) => s.toLowerCase().replace(/[^a-zа-яё']/gi, '').slice(0, 5);
  const serves = (c, region) => !region || (c.regions || []).some((x) => norm(x) === norm(region));
  res.json(rows.filter((c) => serves(c, from) && serves(c, to)).map((c) => serializeCourier(c)));
}));

pub.get('/cargo/my', ah(async (req, res) => {
  res.json((await all(`${CARGO_SQL} WHERE x.user_id=$1 ORDER BY x.created_at DESC LIMIT 100`, [req.user.id])).map(serializeCargo));
}));

pub.post('/cargo/orders', ah(async (req, res) => {
  const b = req.body || {};
  const c = await one("SELECT * FROM couriers WHERE id=$1 AND type='cargo' AND active", [str(b.carrierId)]);
  if (!c) throw new HttpError(404, 'Yuk tashuvchi topilmadi');
  if (!str(b.fromRegion) || !str(b.toRegion)) throw new HttpError(400, 'Qayerdan va qayerga ekanini tanlang');
  const id = newId('g_');
  await q(`INSERT INTO cargo_orders(id, user_id, carrier_id, kind, from_region, to_region, date, cargo, weight_kg, customer_name, phone, address)
    VALUES($1,$2,$3,'cargo',$4,$5,$6,$7,$8,$9,$10,$11)`,
    [id, req.user.id, c.id, str(b.fromRegion), str(b.toRegion), str(b.date).trim(), str(b.cargo).trim(), num(b.weightKg), str(b.name).trim() || req.user.name, str(b.phone).trim(), str(b.address).trim()]);
  res.json({ ok: true, id });
}));

// ---------- route proxy (OSRM) with memory cache ----------
const routeCache = new Map();
pub.get('/route', ah(async (req, res) => {
  const parse = (s) => { const m = str(s).match(/^(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)$/); return m ? [Number(m[1]), Number(m[2])] : null; };
  const from = parse(req.query.from), to = parse(req.query.to);
  if (!from || !to) throw new HttpError(400, "from/to noto'g'ri");
  const profile = req.query.profile === 'foot' ? 'foot' : 'driving';
  const key = `${profile}|${from.map((v) => v.toFixed(4))}|${to.map((v) => v.toFixed(4))}`;
  const hit = routeCache.get(key);
  if (hit && hit.exp > Date.now()) return res.json(hit.data);
  const url = `https://router.project-osrm.org/route/v1/${profile}/${from[1]},${from[0]};${to[1]},${to[0]}?overview=full&geometries=geojson&steps=true`;
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), 12000);
  let j;
  try {
    const resp = await fetch(url, { signal: ctrl.signal, headers: { 'User-Agent': 'saler-ai/1.0' } });
    j = await resp.json();
  } catch { throw new HttpError(502, 'Marshrut xizmati javob bermadi'); } finally { clearTimeout(t); }
  const route = j?.routes?.[0];
  if (!route) throw new HttpError(404, 'Marshrut topilmadi');
  const steps = (route.legs?.[0]?.steps || []).map((s) => ({ location: s.maneuver?.location || null, type: s.maneuver?.type, modifier: s.maneuver?.modifier, exit: s.maneuver?.exit, name: s.name, distance: s.distance }));
  const data = { geometry: route.geometry?.coordinates || [], distance: route.distance, duration: route.duration, steps };
  routeCache.set(key, { data, exp: Date.now() + 6 * 3600e3 });
  if (routeCache.size > 2000) routeCache.delete(routeCache.keys().next().value);
  res.json(data);
}));

r.publicRoutes = pub;
export default r;
