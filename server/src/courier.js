import { Router } from 'express';
import { q, one, all } from './db.js';
import { ah, HttpError, newId, hashPassword, checkPassword, storeDataUri, distanceKm, num, str, REGIONS, log, regionRouteKm, tariffPrice, median } from './util.js';
import { emit, notifyShop } from './events.js';
import { sendCode, checkCode, consumeCode, personName, needPhone, needEmail, needLogin, needPassword } from './verify.js';
import { courierInsights } from './ai.js';

const r = Router();
const pub = Router();
const TZ = "'Asia/Tashkent'";
const ROAD = 1.3; // shahar ichida to'g'ri chiziq masofasini yo'lga aylantirish koeffitsiyenti

export const serializeCourier = (c, extra = {}) => ({
  id: c.id, type: c.type, name: c.name, phone: c.phone, email: c.email, login: c.login, photo: c.photo,
  firstName: c.first_name || '', lastName: c.last_name || '', region: c.region || '', plate: c.plate || '',
  emailVerified: !!c.email_verified_at, active: c.active !== false,
  vehicle: c.vehicle, vehicleType: c.vehicle_type, capacityKg: c.capacity_kg, regions: c.regions || [],
  pricePerKm: c.price_per_km, basePrice: c.base_price, about: c.about, online: c.online,
  location: c.lat != null ? { lat: c.lat, lon: c.lon, updatedAt: c.location_at } : null,
  deliveries: c.deliveries, rating: c.rating, createdAt: c.created_at, ...extra,
});

const CARGO_SQL = `SELECT x.*, c.name AS carrier_name, c.phone AS carrier_phone, c.base_price AS carrier_base, c.price_per_km AS carrier_per_km
  FROM cargo_orders x LEFT JOIN couriers c ON c.id=x.carrier_id`;
const serializeCargo = (x) => {
  const km = x.kind === 'cargo' ? regionRouteKm(x.from_region, x.to_region) : null;
  return {
    id: x.id, status: x.status, kind: x.kind, fromRegion: x.from_region, toRegion: x.to_region, date: x.date, cargo: x.cargo,
    weightKg: x.weight_kg, customerName: x.customer_name, phone: x.phone, address: x.address,
    carrierName: x.carrier_name || '', carrierPhone: x.carrier_phone || '', carrierId: x.carrier_id, createdAt: x.created_at,
    price: x.price != null ? Number(x.price) : null, distanceKm: km, suggestedPrice: tariffPrice(x.carrier_base, x.carrier_per_km, km),
    acceptedAt: x.accepted_at, doneAt: x.done_at,
  };
};

const ORDER_SQL = `SELECT o.*, s.name AS shop_name, s.phone AS shop_phone, s.lat AS shop_lat, s.lon AS shop_lon, s.address AS shop_address FROM orders o JOIN shops s ON s.id=o.shop_id`;
/** Do'kondan xaridorgacha taxminiy yo'l, km */
export const routeKmOf = (o) => {
  const d = distanceKm(o.shop_lat, o.shop_lon, o.lat, o.lon);
  return d == null ? null : Math.round(d * ROAD * 10) / 10;
};
const courierFee = (c, km) => tariffPrice(c.base_price, c.price_per_km, km);
const serializeOrder = (o, c) => {
  const km = o.route_km ?? routeKmOf(o);
  return {
    id: o.id, status: o.status, createdAt: o.created_at, productName: o.product_name, price: Number(o.price),
    customerName: o.customer_name, phone: o.phone, address: o.address, buyerLink: o.customer_name || 'Ilova', items: o.items || [],
    shopId: o.shop_id, shopName: o.shop_name || '', shopPhone: o.shop_phone || '', courierId: o.courier_id, deliveryStatus: o.delivery_status,
    shopLocation: o.shop_lat != null ? { lat: o.shop_lat, lon: o.shop_lon, address: o.shop_address } : null,
    location: o.lat != null ? { lat: o.lat, lon: o.lon } : null,
    routeKm: km, deliveryFee: o.delivery_fee != null ? Number(o.delivery_fee) : c ? courierFee(c, km) : null,
    pickedAt: o.picked_at, deliveredAt: o.delivered_at,
  };
};

const VEHICLES = ['foot', 'bike', 'moto', 'car'];
const VEHICLE_TYPES = ['labo', 'damas', 'gazel', 'isuzu', 'fura'];
const needCourier = (req) => {
  if (!req.courier) throw new HttpError(403, 'Kuryer sifatida kiring');
  if (req.courier.active === false) throw new HttpError(403, "Hisobingiz bloklangan. Qo'llab-quvvatlash xizmatiga murojaat qiling");
  return req.courier;
};
const reload = (id) => one('SELECT * FROM couriers WHERE id=$1', [id]);
const tariffOf = (c) => ({ basePrice: num(c.base_price), pricePerKm: num(c.price_per_km), isSet: num(c.base_price) > 0 || num(c.price_per_km) > 0 });
const fmt = (n) => Number(n).toLocaleString('ru-RU').replace(/,/g, ' ');

/** Yangi do'kon buyurtmasiga eng yaqin, bo'sh va joylashuvi yangi onlayn kuryerni biriktiradi */
export async function assignCourier(orderId) {
  const o = await one(`${ORDER_SQL} WHERE o.id=$1`, [orderId]);
  if (!o || o.courier_id || o.status !== 'new') return null;
  const rejected = o.rejected_by || [];
  const cs = await all(`SELECT c.*, (SELECT count(*) FROM orders x WHERE x.courier_id=c.id AND x.delivery_status IN ('assigned','picked'))::int AS active
    FROM couriers c WHERE c.active AND c.online AND c.type='courier' AND c.lat IS NOT NULL
      AND c.location_at > now() - interval '30 minutes' AND NOT (c.id = ANY($1))`, [rejected]);
  const ranked = cs
    .filter((c) => c.active < 3) // bitta kuryerda bir vaqtda 3 tadan ortiq yetkazish bo'lmaydi
    .map((c) => ({ c, d: distanceKm(o.shop_lat, o.shop_lon, c.lat, c.lon) ?? 1e9 }))
    .sort((a, b) => a.d - b.d);
  if (!ranked.length) return null;
  const pick = ranked[0].c;
  // Poyga holatidan himoya: faqat hali hech kimga biriktirilmagan bo'lsa
  const upd = await one("UPDATE orders SET courier_id=$2, delivery_status='assigned' WHERE id=$1 AND courier_id IS NULL AND status='new' RETURNING id", [orderId, pick.id]);
  if (!upd) return null;
  log('Kuryer biriktirildi', orderId, pick.id);
  emit([`courier:${pick.id}`], 'order:assigned', { orderId });
  emit([`shop:${o.shop_id}`, o.user_id ? `user:${o.user_id}` : null], 'order:update', { orderId, deliveryStatus: 'assigned' });
  return pick.id;
}

// ---------- auth ----------
/** Kuryer yoki yuk tashuvchi ma'lumotlarini tekshiradi (kod yuborishdan oldin ham, keyin ham) */
async function courierSignup(b) {
  const type = b.type === 'cargo' ? 'cargo' : 'courier';
  const d = {
    type,
    firstName: personName(b.firstName, 'Ism'),
    lastName: personName(b.lastName, 'Familiya'),
    phone: needPhone(b.phone),
    email: needEmail(b.email),
    login: needLogin(b.login),
    password: needPassword(b.password),
    region: str(b.region).trim(),
    vehicle: 'car', vehicleType: '', plate: '', capacityKg: 0, basePrice: num(b.basePrice), pricePerKm: num(b.pricePerKm), regions: [],
  };
  if (type === 'courier') {
    if (!REGIONS.includes(d.region)) throw new HttpError(400, 'Ishlaydigan viloyatingizni tanlang', { field: 'region' });
    if (!VEHICLES.includes(b.vehicle)) throw new HttpError(400, 'Transportingizni tanlang', { field: 'vehicle' });
    d.vehicle = b.vehicle;
    d.regions = [d.region];
    if (['moto', 'car'].includes(d.vehicle)) d.plate = str(b.plate).trim().toUpperCase().replace(/\s+/g, ' ').slice(0, 12);
  } else {
    if (!VEHICLE_TYPES.includes(b.vehicleType)) throw new HttpError(400, 'Mashina turini tanlang', { field: 'vehicleType' });
    d.vehicleType = b.vehicleType;
    d.plate = str(b.plate).trim().toUpperCase().replace(/\s+/g, ' ').slice(0, 12);
    if (d.plate.replace(/\s/g, '').length < 5) throw new HttpError(400, 'Mashina davlat raqamini kiriting', { field: 'plate' });
    d.capacityKg = num(b.capacityKg);
    if (d.capacityKg < 50) throw new HttpError(400, "Yuk sig'imini kiriting (kg)", { field: 'capacityKg' });
    if (d.basePrice <= 0 && d.pricePerKm <= 0) throw new HttpError(400, "Narxni kiriting: boshlang'ich narx yoki 1 km narxi", { field: 'basePrice' });
    d.regions = [...new Set((Array.isArray(b.regions) ? b.regions : []).map(String).filter((x) => REGIONS.includes(x)))];
    if (!d.regions.length) throw new HttpError(400, 'Kamida bitta viloyatni tanlang', { field: 'regions' });
    d.region = REGIONS.includes(d.region) ? d.region : d.regions[0];
  }
  if (b.photo && !/^data:image\//.test(String(b.photo))) throw new HttpError(400, "Rasm bo'lishi kerak", { field: 'photo' });
  if (await one('SELECT 1 FROM couriers WHERE login=$1', [d.login])) throw new HttpError(409, 'Bu login band. Boshqasini tanlang', { field: 'login' });
  if (await one('SELECT 1 FROM couriers WHERE lower(email)=$1 AND type=$2', [d.email, type])) {
    throw new HttpError(409, "Bu email bilan hisob ochilgan. Kirish bo'limidan foydalaning", { field: 'email' });
  }
  return d;
}

// 1-qadam: tekshiruv va emailga kod. 2-qadam (code bilan): hisob yaratiladi
r.post('/register', ah(async (req, res) => {
  const b = req.body || {};
  const d = await courierSignup(b);
  if (!str(b.code).trim()) return res.json(await sendCode({ email: d.email, purpose: d.type, name: d.firstName }));
  await checkCode({ email: d.email, purpose: d.type, code: b.code });
  const photo = b.photo ? await storeDataUri(b.photo) : null;
  const id = newId('c_');
  try {
    await q(`INSERT INTO couriers(id, type, name, first_name, last_name, phone, email, email_verified_at, login, pass_hash, photo, vehicle, vehicle_type,
        plate, capacity_kg, regions, region, price_per_km, base_price, last_login_at)
      VALUES($1,$2,$3,$4,$5,$6,$7,now(),$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,now())`,
    [id, d.type, `${d.firstName} ${d.lastName}`, d.firstName, d.lastName, d.phone, d.email, d.login, hashPassword(d.password), photo,
      d.vehicle, d.vehicleType, d.plate, d.capacityKg, JSON.stringify(d.regions), d.region, d.pricePerKm, d.basePrice]);
  } catch (e) {
    if (e.code === '23505') throw new HttpError(409, 'Bu login band. Boshqasini tanlang', { field: 'login' });
    throw e;
  }
  await consumeCode(d.email, d.type);
  await q('UPDATE sessions SET courier_id=$2, shop_id=NULL WHERE token=$1', [req.session.token, id]);
  log(d.type === 'cargo' ? 'Yangi yuk tashuvchi' : 'Yangi kuryer', id);
  res.json({ courier: serializeCourier(await reload(id)) });
}));

r.post('/login', ah(async (req, res) => {
  const who = str(req.body?.login).trim().toLowerCase();
  const type = ['courier', 'cargo'].includes(req.body?.type) ? req.body.type : null;
  const c = who.includes('@')
    ? await one('SELECT * FROM couriers WHERE lower(email)=$1 AND ($2::text IS NULL OR type=$2) ORDER BY created_at DESC LIMIT 1', [who, type])
    : await one('SELECT * FROM couriers WHERE login=$1', [who]);
  if (!c || !checkPassword(str(req.body?.password), c.pass_hash)) throw new HttpError(403, "Login yoki parol noto'g'ri");
  if (type && c.type !== type) {
    throw new HttpError(403, c.type === 'cargo' ? "Bu yuk tashuvchi hisobi. \"Yuk tashuvchi\" bo'limidan kiring" : "Bu kuryer hisobi. \"Kuryer\" bo'limidan kiring");
  }
  if (!c.active) throw new HttpError(403, "Hisobingiz bloklangan. Qo'llab-quvvatlash xizmatiga murojaat qiling");
  await q('UPDATE sessions SET courier_id=$2, shop_id=NULL WHERE token=$1', [req.session.token, c.id]);
  await q('UPDATE couriers SET last_login_at=now() WHERE id=$1', [c.id]);
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
    // Kuryersiz qolgan yangi buyurtmalarni biriktirish (cheklangan miqdorda, har pingda og'ir bo'lmasligi uchun)
    const pending = await all("SELECT id FROM orders WHERE courier_id IS NULL AND status='new' AND NOT archived AND created_at > now() - interval '1 day' ORDER BY created_at LIMIT 20");
    for (const o of pending) await assignCourier(o.id);
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
  // Tarif: kuryer uchun ham, yuk tashuvchi uchun ham
  if (b.basePrice != null) set('base_price', Math.max(0, num(b.basePrice)));
  if (b.pricePerKm != null) set('price_per_km', Math.max(0, num(b.pricePerKm)));
  if (c.type === 'cargo') {
    if (b.vehicleType != null && VEHICLE_TYPES.includes(b.vehicleType)) set('vehicle_type', b.vehicleType);
    if (b.capacityKg != null) set('capacity_kg', num(b.capacityKg));
    if (Array.isArray(b.regions)) {
      const regions = b.regions.map(String).filter(Boolean);
      if (!regions.length) throw new HttpError(400, 'Kamida bitta viloyat tanlang');
      set('regions', JSON.stringify(regions));
    }
  }
  if (sets.length) await q(`UPDATE couriers SET ${sets.join(', ')} WHERE id=$1`, vals);
  res.json({ courier: serializeCourier(await reload(c.id)) });
}));

// ---------- delivery orders ----------
r.get('/orders', ah(async (req, res) => {
  const c = needCourier(req);
  const rows = await all(`${ORDER_SQL} WHERE o.courier_id=$1 AND o.delivery_status IN ('assigned','picked','delivered') AND o.status<>'cancelled'
    ORDER BY (o.delivery_status='delivered'), o.created_at DESC LIMIT 100`, [c.id]);
  res.json(rows.map((o) => serializeOrder(o, c)));
}));

const DELIVERY_FROM = { picked: 'assigned', delivered: 'picked', rejected: 'assigned' };
const DELIVERY_LABEL = { assigned: 'biriktirilgan', picked: "yo'lda", delivered: 'yetkazilgan' };
r.patch('/orders/:id', ah(async (req, res) => {
  const c = needCourier(req);
  const status = str(req.body?.status);
  const from = DELIVERY_FROM[status];
  if (!from) throw new HttpError(400, "Status noto'g'ri");
  const o = await one(`${ORDER_SQL} WHERE o.id=$1 AND o.courier_id=$2`, [req.params.id, c.id]);
  if (!o) throw new HttpError(404, 'Buyurtma topilmadi');
  const conflict = () => new HttpError(409, o.status === 'cancelled' ? 'Buyurtma bekor qilingan' : `Buyurtma hozir "${DELIVERY_LABEL[o.delivery_status] || o.delivery_status}" holatida, bu amalni bajarib bo'lmaydi`);
  if (o.status === 'cancelled' || o.delivery_status !== from) throw conflict();
  const people = [`shop:${o.shop_id}`, o.user_id ? `user:${o.user_id}` : null];

  if (status === 'rejected') {
    const u = await one(`UPDATE orders SET courier_id=NULL, delivery_status=NULL, rejected_by = rejected_by || to_jsonb($2::text)
      WHERE id=$1 AND courier_id=$2 AND delivery_status='assigned' RETURNING id`, [o.id, c.id]);
    if (!u) throw conflict();
    emit(people, 'order:update', { orderId: o.id, deliveryStatus: null });
    await assignCourier(o.id);
    return res.json({ ok: true });
  }
  if (status === 'picked') {
    const u = await one(`UPDATE orders SET delivery_status='picked', picked_at=now() WHERE id=$1 AND courier_id=$2 AND delivery_status='assigned' RETURNING id`, [o.id, c.id]);
    if (!u) throw conflict();
    emit(people, 'order:update', { orderId: o.id, deliveryStatus: 'picked' });
    return res.json({ ok: true });
  }
  // Yetkazildi: masofa va yetkazish haqi qayd etiladi, buyurtma bajarilgan (sotuv) hisoblanadi
  const km = routeKmOf(o);
  const fee = courierFee(c, km);
  const u = await one(`UPDATE orders SET delivery_status='delivered', delivered_at=now(), route_km=$3, delivery_fee=$4,
      status = CASE WHEN status='new' THEN 'done' ELSE status END
    WHERE id=$1 AND courier_id=$2 AND delivery_status='picked' RETURNING *`, [o.id, c.id, km, fee]);
  if (!u) throw conflict();
  await q('UPDATE couriers SET deliveries=deliveries+1 WHERE id=$1', [c.id]);
  await notifyShop(o.shop_id, 'order', 'Yetkazildi, sotuv yakunlandi', `${o.product_name} — ${o.customer_name}ga yetkazildi. Kuryer: ${c.name}. Sotuv: +${fmt(o.price)} so'm`, { orderId: o.id, amount: Number(o.price) });
  if (o.status === 'new') emit([`shop:${o.shop_id}`], 'money', { orderId: o.id, amount: Number(o.price) });
  emit(people, 'order:update', { orderId: o.id, status: u.status, deliveryStatus: 'delivered' });
  emit([`courier:${c.id}`], 'stats', { earnings: fee });
  res.json({ ok: true });
}));

// ---------- statistika ----------
async function courierStats(c) {
  const period = async (cond) => {
    const x = await one(`SELECT count(*)::int AS deliveries, coalesce(sum(delivery_fee),0)::bigint AS earnings, coalesce(sum(route_km),0)::float8 AS km
      FROM orders WHERE courier_id=$1 AND delivery_status='delivered' ${cond}`, [c.id]);
    return { deliveries: x.deliveries, earnings: Number(x.earnings), km: Math.round(x.km * 10) / 10 };
  };
  const today = await period(`AND (delivered_at AT TIME ZONE ${TZ})::date = (now() AT TIME ZONE ${TZ})::date`);
  const week = await period("AND delivered_at > now() - interval '7 days'");
  const month = await period("AND delivered_at > now() - interval '30 days'");
  const total = await period('');
  const active = (await one("SELECT count(*)::int AS n FROM orders WHERE courier_id=$1 AND delivery_status IN ('assigned','picked')", [c.id])).n;
  const rejected = (await one("SELECT count(*)::int AS n FROM orders WHERE rejected_by ? $1 AND created_at > now() - interval '30 days'", [c.id])).n;
  const acceptRate = month.deliveries + rejected > 0 ? Math.round((month.deliveries / (month.deliveries + rejected)) * 100) : null;
  const byDay = (await all(`WITH d AS (SELECT generate_series((now() AT TIME ZONE ${TZ})::date - 13, (now() AT TIME ZONE ${TZ})::date, interval '1 day')::date AS dt)
    SELECT to_char(d.dt,'YYYY-MM-DD') AS date, count(o.id)::int AS deliveries, coalesce(sum(o.delivery_fee),0)::bigint AS earnings
    FROM d LEFT JOIN orders o ON o.courier_id=$1 AND o.delivery_status='delivered' AND (o.delivered_at AT TIME ZONE ${TZ})::date = d.dt
    GROUP BY d.dt ORDER BY d.dt`, [c.id])).map((x) => ({ ...x, earnings: Number(x.earnings) }));
  // Bozor talabi: oxirgi 30 kundagi barcha buyurtmalar soatlar bo'yicha
  const hours = await all(`SELECT extract(hour from created_at AT TIME ZONE ${TZ})::int AS h, count(*)::int AS n FROM orders WHERE created_at > now() - interval '30 days' GROUP BY 1`);
  const peakHours = [[6, 9], [9, 12], [12, 15], [15, 18], [18, 21], [21, 24]]
    .map(([a, b]) => ({ label: `${String(a).padStart(2, '0')}:00–${String(b % 24).padStart(2, '0')}:00`, orders: hours.filter((x) => x.h >= a && x.h < b).reduce((s, x) => s + x.n, 0) }))
    .filter((x) => x.orders > 0).sort((a, b) => b.orders - a.orders).slice(0, 3);
  // Buyurtma ko'p chiqadigan do'konlar (kuryerga 30 km radiusda)
  const zones = await all(`SELECT s.id, s.name, s.address, s.lat, s.lon, count(o.id)::int AS orders FROM orders o JOIN shops s ON s.id=o.shop_id
    WHERE o.created_at > now() - interval '14 days' AND s.lat IS NOT NULL GROUP BY s.id ORDER BY orders DESC LIMIT 30`);
  const hotZones = zones
    .map((z) => ({ shopId: z.id, name: z.name, address: z.address || '', lat: z.lat, lon: z.lon, orders: z.orders, distanceKm: c.lat != null ? distanceKm(c.lat, c.lon, z.lat, z.lon) : null }))
    .filter((z) => z.distanceKm == null || z.distanceKm <= 30)
    .sort((a, b) => b.orders - a.orders || (a.distanceKm ?? 0) - (b.distanceKm ?? 0))
    .slice(0, 5);
  const waitingOrders = (await one("SELECT count(*)::int AS n FROM orders WHERE courier_id IS NULL AND status='new' AND NOT archived AND created_at > now() - interval '1 day'")).n;
  return { type: 'courier', tariff: tariffOf(c), today, week, month, total, active, acceptRate, byDay, peakHours, hotZones, waitingOrders };
}

async function cargoStats(c) {
  const cnt = await one(`SELECT count(*) FILTER (WHERE status='new')::int AS new, count(*) FILTER (WHERE status='accepted')::int AS accepted,
      count(*) FILTER (WHERE status='done')::int AS done, count(*) FILTER (WHERE status='rejected')::int AS rejected,
      coalesce(sum(price) FILTER (WHERE status='done' AND done_at > now() - interval '30 days'),0)::bigint AS rev_month,
      coalesce(sum(price) FILTER (WHERE status='done'),0)::bigint AS rev_total
    FROM cargo_orders WHERE carrier_id=$1`, [c.id]);
  const decided = cnt.accepted + cnt.done + cnt.rejected;
  const acceptRate = decided > 0 ? Math.round(((cnt.accepted + cnt.done) / decided) * 100) : null;
  const byDay = (await all(`WITH d AS (SELECT generate_series((now() AT TIME ZONE ${TZ})::date - 13, (now() AT TIME ZONE ${TZ})::date, interval '1 day')::date AS dt),
      a AS (SELECT (created_at AT TIME ZONE ${TZ})::date AS dt, count(*)::int AS n FROM cargo_orders WHERE carrier_id=$1 GROUP BY 1),
      b AS (SELECT (done_at AT TIME ZONE ${TZ})::date AS dt, coalesce(sum(price),0)::bigint AS s FROM cargo_orders WHERE carrier_id=$1 AND status='done' AND done_at IS NOT NULL GROUP BY 1)
    SELECT to_char(d.dt,'YYYY-MM-DD') AS date, coalesce(a.n,0)::int AS orders, coalesce(b.s,0)::bigint AS revenue
    FROM d LEFT JOIN a ON a.dt=d.dt LEFT JOIN b ON b.dt=d.dt ORDER BY d.dt`, [c.id])).map((x) => ({ ...x, revenue: Number(x.revenue) }));
  const carriers = await all("SELECT base_price, price_per_km FROM couriers WHERE active AND type='cargo'");
  const medianBase = median(carriers.map((x) => num(x.base_price))), medianPerKm = median(carriers.map((x) => num(x.price_per_km)));
  const priceFor = (base, perKm, km) => tariffPrice(base, perKm, km);
  const routes = await all(`SELECT from_region AS "from", to_region AS "to", count(*)::int AS orders, array_agg(price) FILTER (WHERE price > 0) AS prices
    FROM cargo_orders WHERE kind='cargo' AND created_at > now() - interval '60 days' GROUP BY 1,2 ORDER BY orders DESC LIMIT 40`);
  const mine = c.regions || [];
  const topRoutes = routes.filter((x) => !mine.length || mine.includes(x.from) || mine.includes(x.to)).slice(0, 5);
  // Talab ma'lumoti kam bo'lsa, xizmat viloyatlari orasidagi yo'nalishlar bilan to'ldiriladi
  for (let i = 0; i < mine.length && topRoutes.length < 5; i++) {
    for (let j = 0; j < mine.length && topRoutes.length < 5; j++) {
      if (i !== j && !topRoutes.some((x) => x.from === mine[i] && x.to === mine[j])) topRoutes.push({ from: mine[i], to: mine[j], orders: 0, prices: null });
    }
  }
  return {
    type: 'cargo', tariff: tariffOf(c),
    counts: { new: cnt.new, accepted: cnt.accepted, done: cnt.done, rejected: cnt.rejected }, acceptRate,
    revenue: { month: Number(cnt.rev_month), total: Number(cnt.rev_total) }, byDay,
    topRoutes: topRoutes.map((x) => {
      const km = regionRouteKm(x.from, x.to);
      const agreed = median((x.prices || []).map(Number));
      return { from: x.from, to: x.to, orders: x.orders, distanceKm: km, yourPrice: priceFor(c.base_price, c.price_per_km, km), marketPrice: agreed ?? priceFor(medianBase, medianPerKm, km) };
    }),
    market: { carriers: carriers.length, medianBasePrice: medianBase, medianPricePerKm: medianPerKm },
  };
}

r.get('/stats', ah(async (req, res) => {
  const c = needCourier(req);
  res.json(c.type === 'cargo' ? await cargoStats(c) : await courierStats(c));
}));

/** AI maslahatlar (6 soat keshlanadi, ?refresh=1 yangilaydi) */
r.get('/ai-insights', ah(async (req, res) => {
  const c = needCourier(req);
  const cached = await one('SELECT * FROM courier_advice WHERE courier_id=$1', [c.id]);
  if (cached && req.query.refresh !== '1' && Date.now() - new Date(cached.updated_at).getTime() < 6 * 3600e3) return res.json({ tips: cached.tips, generatedAt: cached.updated_at });
  const stats = c.type === 'cargo' ? await cargoStats(c) : await courierStats(c);
  const tips = await courierInsights({ courier: serializeCourier(c), stats });
  const row = await one(`INSERT INTO courier_advice(courier_id, tips, updated_at) VALUES($1,$2,now())
    ON CONFLICT (courier_id) DO UPDATE SET tips=$2, updated_at=now() RETURNING updated_at`, [c.id, JSON.stringify(tips)]);
  res.json({ tips, generatedAt: row.updated_at });
}));

/** Faol yetkazishlar uchun optimal tartib: har buyurtmada avval do'kon, keyin xaridor; eng yaqin keyingi nuqta tanlanadi */
r.get('/route-plan', ah(async (req, res) => {
  const c = needCourier(req);
  const qLat = req.query.lat != null ? Number(req.query.lat) : null, qLon = req.query.lon != null ? Number(req.query.lon) : null;
  const lat = Number.isFinite(qLat) ? qLat : c.lat, lon = Number.isFinite(qLon) ? qLon : c.lon;
  const rows = await all(`${ORDER_SQL} WHERE o.courier_id=$1 AND o.delivery_status IN ('assigned','picked') AND o.status<>'cancelled' ORDER BY o.created_at`, [c.id]);
  const open = rows.map((o) => {
    const drop = { orderId: o.id, kind: 'dropoff', title: o.customer_name || 'Xaridor', address: o.address || '', lat: o.lat, lon: o.lon };
    return o.delivery_status === 'assigned'
      ? { orderId: o.id, kind: 'pickup', title: o.shop_name, address: o.shop_address || '', lat: o.shop_lat, lon: o.shop_lon, next: drop }
      : drop;
  });
  const stops = [];
  let cur = lat != null && lon != null ? [lat, lon] : null;
  let total = 0;
  while (open.length) {
    let bi = 0, best = Infinity;
    open.forEach((s, i) => {
      const d = cur && s.lat != null ? distanceKm(cur[0], cur[1], s.lat, s.lon) : null;
      const v = d ?? 1e6 + i;
      if (v < best) { best = v; bi = i; }
    });
    const { next, ...stop } = open.splice(bi, 1)[0];
    const leg = cur && stop.lat != null ? Math.round(distanceKm(cur[0], cur[1], stop.lat, stop.lon) * ROAD * 10) / 10 : null;
    if (leg != null) total += leg;
    stops.push({ ...stop, legKm: leg });
    if (stop.lat != null) cur = [stop.lat, stop.lon];
    if (next) open.push(next);
  }
  res.json({ stops, totalKm: Math.round(total * 10) / 10 });
}));

// ---------- cargo / direct requests for this courier ----------
r.get('/cargo', ah(async (req, res) => {
  const c = needCourier(req);
  res.json((await all(`${CARGO_SQL} WHERE x.carrier_id=$1 ORDER BY (x.status='new') DESC, x.created_at DESC LIMIT 100`, [c.id])).map(serializeCargo));
}));

const CARGO_FROM = { accepted: 'new', rejected: 'new', done: 'accepted' };
const CARGO_LABEL = { new: 'yangi', accepted: 'qabul qilingan', done: 'bajarilgan', rejected: 'rad etilgan' };
r.patch('/cargo/:id', ah(async (req, res) => {
  const c = needCourier(req);
  const status = str(req.body?.status);
  const from = CARGO_FROM[status];
  if (!from) throw new HttpError(400, "Status noto'g'ri");
  const x = await one('SELECT * FROM cargo_orders WHERE id=$1 AND carrier_id=$2', [req.params.id, c.id]);
  if (!x) throw new HttpError(404, 'Buyurtma topilmadi');
  const conflict = () => new HttpError(409, `Buyurtma hozir "${CARGO_LABEL[x.status] || x.status}" holatida, bu amalni bajarib bo'lmaydi`);
  if (x.status !== from) throw conflict();
  const raw = req.body?.price;
  const price = raw != null && raw !== '' ? Math.round(num(raw, -1)) : null;
  if (price != null && price < 0) throw new HttpError(400, "Narx noto'g'ri");
  const u = await one(`UPDATE cargo_orders SET status=$3::text,
      price = CASE WHEN $3::text='accepted' AND $4::bigint IS NOT NULL THEN $4::bigint ELSE price END,
      accepted_at = CASE WHEN $3::text='accepted' THEN now() ELSE accepted_at END,
      done_at = CASE WHEN $3::text='done' THEN now() ELSE done_at END
    WHERE id=$1 AND carrier_id=$2 AND status=$5::text RETURNING *`, [x.id, c.id, status, price, from]);
  if (!u) throw conflict();
  if (status === 'done') await q('UPDATE couriers SET deliveries=deliveries+1 WHERE id=$1', [c.id]);
  emit([u.user_id ? `user:${u.user_id}` : null], 'cargo:update', { id: u.id, status });
  emit([`courier:${c.id}`], 'stats', {});
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
  const c = await one("SELECT * FROM couriers WHERE id=$1 AND active AND type='courier'", [str(b.courierId)]);
  if (!c) throw new HttpError(404, 'Kuryer topilmadi');
  const id = newId('g_');
  await q(`INSERT INTO cargo_orders(id, user_id, carrier_id, kind, from_region, to_region, cargo, customer_name, phone, address)
    VALUES($1,$2,$3,'direct',$4,$5,$6,$7,$8,$9)`,
    [id, req.user.id, c.id, str(b.from).trim(), str(b.to).trim(), str(b.note).trim(), str(b.name).trim() || req.user.name, str(b.phone).trim(), str(b.from).trim()]);
  emit([`courier:${c.id}`], 'cargo:new', { id });
  res.json({ ok: true, id });
}));

pub.get('/cargo/regions', (_req, res) => res.json(REGIONS));

pub.get('/cargo/carriers', ah(async (req, res) => {
  const from = str(req.query.from).trim(), to = str(req.query.to).trim();
  const rows = await all(`SELECT * FROM couriers WHERE active AND type='cargo' ORDER BY online DESC, deliveries DESC LIMIT 200`);
  // Viloyat nomi to'liq solishtiriladi ("Toshkent shahri" va "Toshkent viloyati" farqlanadi)
  const norm = (s) => String(s).toLowerCase().replace(/[^a-zа-яё]/gi, '');
  const serves = (c, region) => !region || (c.regions || []).some((x) => norm(x) === norm(region));
  const km = from && to ? regionRouteKm(from, to) : null;
  res.json(rows.filter((c) => serves(c, from) && serves(c, to)).map((c) => serializeCourier(c, { routeKm: km, estimatedPrice: km != null ? tariffPrice(c.base_price, c.price_per_km, km) : null })));
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
  emit([`courier:${c.id}`], 'cargo:new', { id });
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
