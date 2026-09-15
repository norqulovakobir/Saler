import { Router } from 'express';
import os from 'node:os';
import { q, one, all } from './db.js';
import { ah, HttpError, newToken, pageArgs, str, num, logTail } from './util.js';
import { storageEnabled } from './storage.js';
import { aiInfo } from './ai.js';
import { mailInfo } from './verify.js';

const r = Router();
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || 'admin';

// ---- auth ----
r.post('/login', ah(async (req, res) => {
  const { password } = req.body || {};
  if (!password || password !== ADMIN_PASSWORD) throw new HttpError(401, "Parol noto'g'ri");
  const token = newToken();
  await q("INSERT INTO sessions(token, shop_id) VALUES($1,'__admin__')", [token]);
  res.json({ token });
}));

r.use(ah(async (req, _res, next) => {
  const m = (req.headers.authorization || '').match(/^Bearer (.+)$/);
  const s = m ? await one("SELECT token FROM sessions WHERE token=$1 AND shop_id='__admin__'", [m[1]]) : null;
  if (!s) throw new HttpError(401, 'Kirish talab qilinadi');
  next();
}));

r.get('/me', (_req, res) => res.json({ ok: true, role: 'admin' }));

// ---- helpers ----
const growth = (cur, prev) => (prev > 0 ? Math.round(((cur - prev) / prev) * 1000) / 10 : cur > 0 ? 100 : 0);
const orderRow = (o) => ({
  id: o.id, shopId: o.shop_id, shop: o.shop_name, items: o.items, productName: o.product_name,
  customerName: o.customer_name, phone: o.phone, buyerId: o.user_id == null ? null : -o.user_id,
  price: Number(o.price), status: o.status, deliveryStatus: o.delivery_status, courierId: o.courier_id, createdAt: o.created_at,
});
const bool = (v) => (v === '1' || v === 'true' ? true : v === '0' || v === 'false' ? false : null);

/** Do'konni bloklash/ochish. Bloklanganda sotuvchi sessiyalari yopiladi (login qayta ishlamaydi) */
async function setShopActive(id, active) {
  const s = await one('UPDATE shops SET active=$2 WHERE id=$1 RETURNING id', [id, active]);
  if (!s) throw new HttpError(404, "Do'kon topilmadi");
  if (!active) await q('UPDATE sessions SET shop_id=NULL WHERE shop_id=$1', [id]);
}
/** Kuryer/yuk tashuvchini bloklash/ochish. Bloklanganda oflayn qilinadi, sessiyalar yopiladi, boshlanmagan buyurtmalar bo'shatiladi */
async function setCourierActive(id, active) {
  const c = await one('UPDATE couriers SET active=$2, online = CASE WHEN $2 THEN online ELSE false END WHERE id=$1 RETURNING id', [id, active]);
  if (!c) throw new HttpError(404, 'Kuryer topilmadi');
  if (!active) {
    await q('UPDATE sessions SET courier_id=NULL WHERE courier_id=$1', [id]);
    await q("UPDATE orders SET courier_id=NULL, delivery_status=NULL WHERE courier_id=$1 AND delivery_status='assigned'", [id]);
  }
}

// ---- dashboard ----
r.get('/overview', ah(async (_req, res) => {
  const o = await one(`
    SELECT count(*)::int AS total,
      count(*) FILTER (WHERE created_at >= now() - interval '1 day')::int AS today,
      count(*) FILTER (WHERE created_at >= now() - interval '7 day')::int AS week,
      count(*) FILTER (WHERE created_at >= now() - interval '14 day' AND created_at < now() - interval '7 day')::int AS prev_week,
      count(*) FILTER (WHERE status='new')::int AS s_new,
      count(*) FILTER (WHERE status='done')::int AS s_done,
      count(*) FILTER (WHERE status='cancelled')::int AS s_cancelled,
      coalesce(sum(price) FILTER (WHERE status='done'),0)::bigint AS rev_total,
      coalesce(sum(price) FILTER (WHERE status='done' AND created_at >= now() - interval '7 day'),0)::bigint AS rev_week,
      coalesce(sum(price) FILTER (WHERE status='done' AND created_at >= now() - interval '14 day' AND created_at < now() - interval '7 day'),0)::bigint AS rev_prev_week,
      coalesce(sum(price) FILTER (WHERE status='done' AND created_at >= now() - interval '1 day'),0)::bigint AS rev_today,
      coalesce(avg(price) FILTER (WHERE status='done'),0)::bigint AS avg_order
    FROM orders`);
  const s = await one(`
    SELECT count(*)::int AS total,
      count(*) FILTER (WHERE created_at >= now() - interval '7 day')::int AS week,
      count(*) FILTER (WHERE created_at >= now() - interval '14 day' AND created_at < now() - interval '7 day')::int AS prev_week,
      count(*) FILTER (WHERE lat IS NOT NULL)::int AS with_location,
      count(*) FILTER (WHERE NOT active)::int AS blocked
    FROM shops`);
  const p = await one(`SELECT count(*)::int AS total, count(*) FILTER (WHERE active)::int AS active, coalesce(sum(views),0)::int AS views FROM products`);
  const u = await one(`
    SELECT count(*)::int AS total,
      count(*) FILTER (WHERE registered_at IS NOT NULL)::int AS registered,
      count(*) FILTER (WHERE registered_at >= now() - interval '7 day')::int AS reg_week,
      count(*) FILTER (WHERE blocked)::int AS blocked,
      count(*) FILTER (WHERE last_seen >= now() - interval '7 day')::int AS active_week
    FROM users`);
  const c = await one(`
    SELECT count(*)::int AS total, count(*) FILTER (WHERE online)::int AS online,
      count(*) FILTER (WHERE type='courier')::int AS couriers, count(*) FILTER (WHERE type='cargo')::int AS cargo,
      count(*) FILTER (WHERE NOT active)::int AS blocked, count(*) FILTER (WHERE created_at >= now() - interval '7 day')::int AS week
    FROM couriers`);
  const closed = o.s_done + o.s_cancelled;
  res.json({
    generatedAt: new Date().toISOString(),
    revenue: { total: Number(o.rev_total), week: Number(o.rev_week), growth: growth(Number(o.rev_week), Number(o.rev_prev_week)), avgOrder: Number(o.avg_order), today: Number(o.rev_today) },
    orders: { total: o.total, today: o.today, week: o.week, growth: growth(o.week, o.prev_week), status: { new: o.s_new, done: o.s_done, cancelled: o.s_cancelled } },
    shops: { total: s.total, week: s.week, withLocation: s.with_location, blocked: s.blocked, growth: growth(s.week, s.prev_week) },
    products: { total: p.total, active: p.active, hidden: p.total - p.active, views: p.views },
    // Rollar: tasdiqlangan xaridorlar, mehmonlar (hisobsiz ko'rayotganlar), sotuvchilar, kuryerlar, yuk tashuvchilar
    users: {
      total: u.registered + s.total + c.total, buyers: u.registered, guests: u.total - u.registered, sellers: s.total, couriers: c.couriers, cargo: c.cargo,
      blocked: u.blocked + s.blocked + c.blocked, regWeek: u.reg_week + s.week + c.week, activeWeek: u.active_week,
      telegram: 0, app: u.registered + s.total + c.total,
    },
    conversion: p.views > 0 ? Math.round((o.total / p.views) * 1000) / 10 : 0,
    couriers: { total: c.total, online: c.online, couriers: c.couriers, cargo: c.cargo },
    doneRate: closed > 0 ? Math.round((o.s_done / closed) * 100) : 0,
    cancelRate: closed > 0 ? Math.round((o.s_cancelled / closed) * 100) : 0,
    mail: mailInfo,
  });
}));

r.get('/timeseries', ah(async (req, res) => {
  const days = Math.min(365, Math.max(1, num(req.query.days, 30)));
  const rows = await all(`
    WITH d AS (SELECT generate_series((now() - ($1::int - 1) * interval '1 day')::date, now()::date, interval '1 day')::date AS dt)
    SELECT to_char(d.dt,'YYYY-MM-DD') AS date,
      coalesce((SELECT sum(price) FROM orders WHERE status='done' AND created_at::date=d.dt),0)::bigint AS revenue,
      (SELECT count(*) FROM orders WHERE status='done' AND created_at::date=d.dt)::int AS done,
      (SELECT count(*) FROM orders WHERE status='cancelled' AND created_at::date=d.dt)::int AS cancelled,
      (SELECT count(*) FROM shops WHERE created_at::date=d.dt)::int AS shops,
      (SELECT count(*) FROM products WHERE created_at::date=d.dt)::int AS products,
      (SELECT count(*) FROM users WHERE registered_at::date=d.dt)::int AS buyers,
      (SELECT count(*) FROM couriers WHERE created_at::date=d.dt)::int AS couriers
    FROM d ORDER BY d.dt`, [days]);
  res.json(rows.map((x) => ({ ...x, revenue: Number(x.revenue) })));
}));

// ---- analytics ----
r.get('/analytics', ah(async (req, res) => {
  const months = Math.min(24, Math.max(1, num(req.query.months, 6)));
  const since = `now() - interval '${months} month'`;
  const hours = new Array(24).fill(0), weekdays = new Array(7).fill(0);
  for (const x of await all(`SELECT extract(hour from created_at AT TIME ZONE 'Asia/Tashkent')::int AS h, count(*)::int AS n FROM orders WHERE created_at >= ${since} GROUP BY 1`)) hours[x.h] = x.n;
  for (const x of await all(`SELECT extract(dow from created_at AT TIME ZONE 'Asia/Tashkent')::int AS d, count(*)::int AS n FROM orders WHERE created_at >= ${since} GROUP BY 1`)) weekdays[x.d] = x.n;
  const monthly = (await all(`
    SELECT to_char(date_trunc('month', created_at),'YYYY-MM') AS month,
      count(*) FILTER (WHERE status='done')::int AS done, count(*) FILTER (WHERE status='new')::int AS new,
      count(*) FILTER (WHERE status='cancelled')::int AS cancelled,
      coalesce(sum(price) FILTER (WHERE status='done'),0)::bigint AS "sumDone", coalesce(sum(price),0)::bigint AS "sumTotal"
    FROM orders WHERE created_at >= ${since} GROUP BY 1 ORDER BY 1`)).map((m) => ({ ...m, sumDone: Number(m.sumDone), sumTotal: Number(m.sumTotal) }));
  const topShops = (await all(`
    SELECT s.id, s.name, count(o.id) FILTER (WHERE o.status='done')::int AS done, count(o.id)::int AS orders,
      coalesce(sum(o.price) FILTER (WHERE o.status='done'),0)::bigint AS revenue
    FROM shops s JOIN orders o ON o.shop_id=s.id WHERE o.created_at >= ${since} GROUP BY s.id ORDER BY revenue DESC LIMIT 10`)).map((x) => ({ ...x, revenue: Number(x.revenue) }));
  const topProducts = await all(`
    SELECT i->>'name' AS name, s.name AS shop, sum((i->>'qty')::int)::int AS qty
    FROM orders o JOIN shops s ON s.id=o.shop_id, jsonb_array_elements(o.items) i
    WHERE o.created_at >= ${since} GROUP BY 1,2 ORDER BY qty DESC LIMIT 10`);
  const topViewed = await all(`SELECT p.name, s.name AS shop, p.views FROM products p JOIN shops s ON s.id=p.shop_id ORDER BY p.views DESC LIMIT 10`);
  const topCustomers = (await all(`
    SELECT customer_name AS name, phone, sum(price)::bigint AS sum FROM orders WHERE status='done' AND created_at >= ${since}
    GROUP BY 1,2 ORDER BY sum DESC LIMIT 10`)).map((x) => ({ ...x, sum: Number(x.sum) }));
  const buckets = [[0, 50000, '< 50 ming'], [50000, 200000, '50–200 ming'], [200000, 500000, '200–500 ming'], [500000, 1000000, '500 ming – 1 mln'], [1000000, 5000000, '1–5 mln'], [5000000, null, '> 5 mln']];
  const priceBuckets = [];
  for (const [lo, hi, label] of buckets) {
    const x = await one(`SELECT count(*)::int AS n FROM products WHERE price >= $1 AND ($2::bigint IS NULL OR price < $2)`, [lo, hi]);
    priceBuckets.push({ label, n: x.n });
  }
  const sizes = [[0, 1, '0'], [1, 5, '1–4'], [5, 20, '5–19'], [20, 50, '20–49'], [50, null, '50+']];
  const shopSizes = [];
  for (const [lo, hi, label] of sizes) {
    const x = await one(`SELECT count(*)::int AS n FROM (SELECT s.id, count(p.id) AS c FROM shops s LEFT JOIN products p ON p.shop_id=s.id GROUP BY s.id) t WHERE c >= $1 AND ($2::int IS NULL OR c < $2)`, [lo, hi]);
    shopSizes.push({ label, n: x.n });
  }
  // Viloyatlar bo'yicha do'konlar va kuryerlar
  const regions = await all(`
    SELECT r.region, coalesce(s.n,0)::int AS shops, coalesce(c.n,0)::int AS couriers, coalesce(c.cargo,0)::int AS cargo FROM (
      SELECT region FROM shops WHERE region<>'' UNION SELECT region FROM couriers WHERE region<>'') r
    LEFT JOIN (SELECT region, count(*) AS n FROM shops WHERE region<>'' GROUP BY 1) s ON s.region=r.region
    LEFT JOIN (SELECT region, count(*) FILTER (WHERE type='courier') AS n, count(*) FILTER (WHERE type='cargo') AS cargo FROM couriers WHERE region<>'' GROUP BY 1) c ON c.region=r.region
    ORDER BY shops DESC, couriers DESC`);
  res.json({ hours, weekdays, monthly, topShops, topProducts, topViewed, topCustomers, priceBuckets, shopSizes, regions });
}));

// ---- shops ----
r.get('/shops', ah(async (req, res) => {
  const { page, limit, offset } = pageArgs(req.query, 25);
  const qs = `%${str(req.query.q)}%`;
  const active = bool(req.query.active);
  const order = req.query.sort === 'name' ? 's.name ASC' : 's.created_at DESC';
  const where = `WHERE (s.name ILIKE $1 OR s.login ILIKE $1 OR s.phone ILIKE $1 OR s.owner_name ILIKE $1 OR s.email ILIKE $1 OR s.region ILIKE $1) AND ($2::boolean IS NULL OR s.active=$2)`;
  const total = (await one(`SELECT count(*)::int AS n FROM shops s ${where}`, [qs, active])).n;
  const items = (await all(`
    SELECT s.id, s.name, s.logo, (s.lat IS NOT NULL) AS "hasLocation", s.login, s.owner_name AS "ownerName", s.phone, s.email, s.region, s.active,
      s.seller_name AS "aiName", s.created_at AS "createdAt", s.last_login_at AS "lastLoginAt",
      (SELECT count(*) FROM products p WHERE p.shop_id=s.id)::int AS products,
      (SELECT coalesce(sum(views),0) FROM products p WHERE p.shop_id=s.id)::int AS views,
      (SELECT count(*) FROM orders o WHERE o.shop_id=s.id)::int AS orders,
      (SELECT count(*) FROM orders o WHERE o.shop_id=s.id AND o.status='done')::int AS done,
      (SELECT coalesce(sum(price),0) FROM orders o WHERE o.shop_id=s.id AND o.status='done')::bigint AS revenue,
      (SELECT count(*) FROM follows f WHERE f.shop_id=s.id)::int AS followers,
      1 AS sellers,
      (SELECT max(created_at) FROM orders o WHERE o.shop_id=s.id) AS "lastOrderAt"
    FROM shops s ${where} ORDER BY ${order} LIMIT $3 OFFSET $4`, [qs, active, limit, offset])).map((x) => ({ ...x, revenue: Number(x.revenue) }));
  res.json({ total, page, limit, items });
}));

r.get('/shops/:id', ah(async (req, res) => {
  const s = await one('SELECT * FROM shops WHERE id=$1', [req.params.id]);
  if (!s) throw new HttpError(404, "Do'kon topilmadi");
  const st = await one(`
    SELECT coalesce(sum(price) FILTER (WHERE status='done'),0)::bigint AS revenue, count(*)::int AS "totalOrders",
      count(*) FILTER (WHERE status='new')::int AS "newOrders", count(*) FILTER (WHERE status='done')::int AS "doneOrders"
    FROM orders WHERE shop_id=$1`, [s.id]);
  const pc = await one(`SELECT count(*)::int AS c, count(*) FILTER (WHERE NOT active)::int AS h, coalesce(sum(views),0)::int AS v FROM products WHERE shop_id=$1`, [s.id]);
  const followers = (await one('SELECT count(*)::int AS n FROM follows WHERE shop_id=$1', [s.id])).n;
  const byDay = await all(`
    WITH d AS (SELECT generate_series((now() - interval '29 day')::date, now()::date, interval '1 day')::date AS dt)
    SELECT to_char(d.dt,'YYYY-MM-DD') AS date, (SELECT count(*) FROM orders WHERE shop_id=$1 AND created_at::date=d.dt)::int AS n FROM d ORDER BY d.dt`, [s.id]);
  const products = await all(`SELECT id, name, photos, active, price::bigint AS price, views, created_at AS "createdAt" FROM products WHERE shop_id=$1 ORDER BY created_at DESC`, [s.id]);
  const orders = (await all(`SELECT o.*, s.name AS shop_name FROM orders o JOIN shops s ON s.id=o.shop_id WHERE o.shop_id=$1 ORDER BY o.created_at DESC LIMIT 100`, [s.id])).map(orderRow);
  res.json({
    shop: {
      id: s.id, name: s.name, login: s.login, logo: s.logo, ownerName: s.owner_name, firstName: s.first_name, lastName: s.last_name, sellerName: s.seller_name,
      createdAt: s.created_at, lastLoginAt: s.last_login_at, phone: s.phone, email: s.email, emailVerified: !!s.email_verified_at, region: s.region, active: s.active,
      description: s.description, location: s.lat != null ? { lat: s.lat, lon: s.lon, address: s.address } : null,
    },
    stats: { revenue: Number(st.revenue), totalOrders: st.totalOrders, newOrders: st.newOrders, doneOrders: st.doneOrders, productCount: pc.c, hiddenCount: pc.h, views: pc.v, followers },
    byDay,
    sellers: [{ id: s.login, name: s.owner_name || s.name, username: s.login, owner: true, lang: 'uz' }],
    products: products.map((p) => ({ ...p, price: Number(p.price) })),
    orders,
  });
}));

r.patch('/shops/:id', ah(async (req, res) => {
  if (typeof req.body?.active !== 'boolean') throw new HttpError(400, 'active: true/false');
  await setShopActive(req.params.id, req.body.active);
  res.json({ ok: true });
}));

r.delete('/shops/:id', ah(async (req, res) => {
  await q('DELETE FROM shops WHERE id=$1', [req.params.id]);
  res.json({ ok: true });
}));

// ---- products ----
r.get('/products', ah(async (req, res) => {
  const { page, limit, offset } = pageArgs(req.query, 30);
  const qs = `%${str(req.query.q)}%`;
  const active = bool(req.query.active);
  const order = { views: 'p.views DESC', price: 'p.price DESC', priceAsc: 'p.price ASC' }[req.query.sort] || 'p.created_at DESC';
  const where = `WHERE (p.name ILIKE $1 OR s.name ILIKE $1) AND ($2::boolean IS NULL OR p.active=$2)`;
  const total = (await one(`SELECT count(*)::int AS n FROM products p JOIN shops s ON s.id=p.shop_id ${where}`, [qs, active])).n;
  const items = (await all(`
    SELECT p.id, p.name, p.description, p.photos, p.shop_id AS "shopId", s.name AS shop, p.price::bigint AS price, p.views, p.active, p.created_at AS "createdAt"
    FROM products p JOIN shops s ON s.id=p.shop_id ${where} ORDER BY ${order} LIMIT $3 OFFSET $4`, [qs, active, limit, offset])).map((x) => ({ ...x, price: Number(x.price) }));
  res.json({ total, page, limit, items });
}));

r.patch('/products/:id', ah(async (req, res) => {
  if (typeof req.body?.active === 'boolean') await q('UPDATE products SET active=$2 WHERE id=$1', [req.params.id, req.body.active]);
  res.json({ ok: true });
}));
r.delete('/products/:id', ah(async (req, res) => {
  await q('DELETE FROM products WHERE id=$1', [req.params.id]);
  res.json({ ok: true });
}));

// ---- orders ----
r.get('/orders', ah(async (req, res) => {
  const { page, limit, offset } = pageArgs(req.query, 30);
  const qs = `%${str(req.query.q)}%`;
  const status = ['new', 'done', 'cancelled'].includes(req.query.status) ? req.query.status : null;
  const from = /^\d{4}-\d{2}-\d{2}$/.test(req.query.from || '') ? req.query.from : null;
  const to = /^\d{4}-\d{2}-\d{2}$/.test(req.query.to || '') ? req.query.to : null;
  const where = `WHERE (o.customer_name ILIKE $1 OR o.phone ILIKE $1 OR s.name ILIKE $1 OR o.product_name ILIKE $1 OR o.id ILIKE $1)
    AND ($2::text IS NULL OR o.status=$2) AND ($3::date IS NULL OR o.created_at::date >= $3) AND ($4::date IS NULL OR o.created_at::date <= $4)`;
  const agg = await one(`SELECT count(*)::int AS n, coalesce(sum(o.price),0)::bigint AS sum FROM orders o JOIN shops s ON s.id=o.shop_id ${where}`, [qs, status, from, to]);
  const items = (await all(`SELECT o.*, s.name AS shop_name FROM orders o JOIN shops s ON s.id=o.shop_id ${where} ORDER BY o.created_at DESC LIMIT $5 OFFSET $6`, [qs, status, from, to, limit, offset])).map(orderRow);
  res.json({ total: agg.n, sum: Number(agg.sum), page, limit, items });
}));

r.patch('/orders/:id', ah(async (req, res) => {
  const status = req.body?.status;
  if (!['new', 'done', 'cancelled'].includes(status)) throw new HttpError(400, "Status noto'g'ri");
  await q('UPDATE orders SET status=$2 WHERE id=$1', [req.params.id, status]);
  res.json({ ok: true });
}));

// ---- couriers (kuryer va yuk tashuvchi) ----
r.get('/couriers', ah(async (req, res) => {
  const { page, limit, offset } = pageArgs(req.query, 30);
  const qs = `%${str(req.query.q)}%`;
  const online = req.query.online === '1' ? true : null;
  const type = ['courier', 'cargo'].includes(req.query.type) ? req.query.type : null;
  const active = bool(req.query.active);
  const where = `WHERE (c.name ILIKE $1 OR c.login ILIKE $1 OR c.phone ILIKE $1 OR c.email ILIKE $1 OR c.plate ILIKE $1 OR c.region ILIKE $1)
    AND ($2::boolean IS NULL OR c.online=$2) AND ($3::text IS NULL OR c.type=$3) AND ($4::boolean IS NULL OR c.active=$4)`;
  const total = (await one(`SELECT count(*)::int AS n FROM couriers c ${where}`, [qs, online, type, active])).n;
  const counts = await one(`SELECT count(*) FILTER (WHERE online)::int AS online, count(*) FILTER (WHERE type='courier')::int AS couriers, count(*) FILTER (WHERE type='cargo')::int AS cargo, count(*) FILTER (WHERE NOT active)::int AS blocked FROM couriers`);
  const items = (await all(`
    SELECT c.id, c.type, c.name, c.login, c.phone, c.email, (c.email_verified_at IS NOT NULL) AS "emailVerified", c.online, c.active,
      c.vehicle, c.vehicle_type AS "vehicleType", c.plate, c.region, c.regions, c.capacity_kg AS "capacityKg", c.base_price AS "basePrice", c.price_per_km AS "pricePerKm",
      c.deliveries, c.rating, c.lat, c.lon, c.location_at, c.created_at AS "createdAt", c.last_login_at AS "lastLoginAt",
      (SELECT count(*) FROM orders o WHERE o.courier_id=c.id AND o.delivery_status IN ('assigned','picked'))::int AS "activeOrders",
      (SELECT coalesce(sum(delivery_fee),0) FROM orders o WHERE o.courier_id=c.id AND o.delivery_status='delivered')::bigint AS earnings,
      (SELECT count(*) FROM cargo_orders x WHERE x.carrier_id=c.id AND x.status='done')::int AS "cargoDone",
      (SELECT count(*) FROM cargo_orders x WHERE x.carrier_id=c.id AND x.status NOT IN ('done','cancelled'))::int AS "cargoActive"
    FROM couriers c ${where} ORDER BY c.online DESC, c.created_at DESC LIMIT $5 OFFSET $6`, [qs, online, type, active, limit, offset]))
    .map(({ lat, lon, location_at, ...c }) => ({ ...c, earnings: Number(c.earnings), location: lat != null ? { lat, lon, updatedAt: location_at } : null }));
  res.json({ total, online: counts.online, couriers: counts.couriers, cargo: counts.cargo, blocked: counts.blocked, page, limit, items });
}));

r.patch('/couriers/:id', ah(async (req, res) => {
  if (typeof req.body?.active !== 'boolean') throw new HttpError(400, 'active: true/false');
  await setCourierActive(req.params.id, req.body.active);
  res.json({ ok: true });
}));

r.delete('/couriers/:id', ah(async (req, res) => {
  await q("UPDATE orders SET courier_id=NULL, delivery_status=NULL WHERE courier_id=$1 AND delivery_status<>'delivered'", [req.params.id]);
  await q('DELETE FROM couriers WHERE id=$1', [req.params.id]);
  res.json({ ok: true });
}));

// ---- users: barcha rollar bitta ro'yxatda ----
// buyer (users jadvali: tasdiqlangan xaridor yoki mehmon), seller (shops), courier / cargo (couriers)
const USERS_SQL = `
  SELECT * FROM (
    SELECT ('u' || u.id) AS id, coalesce(nullif(trim(coalesce(u.first_name,'') || ' ' || coalesce(u.last_name,'')), ''), u.name) AS name,
      NULL::text AS username, 'buyer' AS role, u.phone, u.email, u.telegram,
      (u.email_verified_at IS NOT NULL) AS verified, u.blocked, (u.registered_at IS NOT NULL) AS registered,
      NULL::text AS "shopId", NULL::text AS shop, NULL::text AS region,
      (SELECT count(*) FROM orders o WHERE o.user_id=u.id)::int AS orders,
      (SELECT coalesce(sum(price),0) FROM orders o WHERE o.user_id=u.id AND o.status='done')::bigint AS spent,
      u.last_seen AS "lastActivity", u.created_at
    FROM users u
    UNION ALL
    SELECT s.id, coalesce(nullif(trim(s.first_name || ' ' || s.last_name), ''), s.owner_name), s.login, 'seller', nullif(s.phone,''), nullif(s.email,''), NULL::text,
      (s.email_verified_at IS NOT NULL), NOT s.active, true, s.id, s.name, nullif(s.region,''),
      (SELECT count(*) FROM orders o WHERE o.shop_id=s.id)::int,
      (SELECT coalesce(sum(price),0) FROM orders o WHERE o.shop_id=s.id AND o.status='done')::bigint,
      coalesce(s.last_login_at, (SELECT max(created_at) FROM orders o WHERE o.shop_id=s.id)), s.created_at
    FROM shops s
    UNION ALL
    SELECT c.id, c.name, c.login, c.type, nullif(c.phone,''), nullif(c.email,''), NULL::text,
      (c.email_verified_at IS NOT NULL), NOT c.active, true, NULL::text, NULL::text, nullif(c.region,''),
      (SELECT count(*) FROM orders o WHERE o.courier_id=c.id AND o.delivery_status='delivered')::int,
      (SELECT coalesce(sum(delivery_fee),0) FROM orders o WHERE o.courier_id=c.id AND o.delivery_status='delivered')::bigint,
      coalesce(c.last_login_at, c.location_at), c.created_at
    FROM couriers c
  ) t
  WHERE (coalesce(t.name,'') ILIKE $1 OR coalesce(t.username,'') ILIKE $1 OR coalesce(t.shop,'') ILIKE $1 OR coalesce(t.phone,'') ILIKE $1 OR coalesce(t.email,'') ILIKE $1 OR coalesce(t.telegram,'') ILIKE $1)
    AND ($2::text IS NULL OR t.role=$2)
    AND ($3::text IS NULL OR ($3='blocked' AND t.blocked) OR ($3='guest' AND NOT t.registered) OR ($3='registered' AND t.registered AND NOT t.blocked))`;

r.get('/users', ah(async (req, res) => {
  const { page, limit, offset } = pageArgs(req.query, 30);
  const qs = `%${str(req.query.q)}%`;
  const role = ['buyer', 'seller', 'courier', 'cargo'].includes(req.query.role) ? req.query.role : null;
  const status = ['blocked', 'guest', 'registered'].includes(req.query.status) ? req.query.status : null;
  if (req.query.source === 'telegram') return res.json({ total: 0, page, limit, items: [] });
  const total = (await one(`SELECT count(*)::int AS n FROM (${USERS_SQL}) x`, [qs, role, status])).n;
  const items = (await all(`${USERS_SQL} ORDER BY t.created_at DESC LIMIT $4 OFFSET $5`, [qs, role, status, limit, offset]))
    .map(({ created_at, ...x }) => ({ ...x, source: 'app', lang: 'uz', spent: Number(x.spent), createdAt: created_at }));
  res.json({ total, page, limit, items });
}));

// Bloklash: xaridor (u123) → users.blocked; sotuvchi (s_...) → shops.active; kuryer (c_...) → couriers.active
r.patch('/users/:id', ah(async (req, res) => {
  const blocked = req.body?.blocked;
  if (typeof blocked !== 'boolean') throw new HttpError(400, 'blocked: true/false');
  const id = req.params.id;
  if (/^u\d+$/.test(id)) {
    const u = await one('UPDATE users SET blocked=$2 WHERE id=$1 RETURNING id', [Number(id.slice(1)), blocked]);
    if (!u) throw new HttpError(404, 'Foydalanuvchi topilmadi');
  } else if (await one('SELECT 1 FROM shops WHERE id=$1', [id])) {
    await setShopActive(id, !blocked);
  } else if (await one('SELECT 1 FROM couriers WHERE id=$1', [id])) {
    await setCourierActive(id, !blocked);
  } else {
    throw new HttpError(404, 'Foydalanuvchi topilmadi');
  }
  res.json({ ok: true });
}));

// ---- system ----
const startedAt = Date.now();
r.get('/system', ah(async (_req, res) => {
  const mem = process.memoryUsage();
  let db = null;
  try {
    const d = await one(`SELECT pg_database_size(current_database())::bigint AS size, (SELECT count(*) FROM information_schema.tables WHERE table_schema='public')::int AS tables`);
    const objects = await one(`SELECT (SELECT count(*) FROM shops)+(SELECT count(*) FROM products)+(SELECT count(*) FROM orders)+(SELECT count(*) FROM users)+(SELECT count(*) FROM couriers) AS n`);
    db = { dataSize: Number(d.size), objects: Number(objects.n), collections: d.tables };
  } catch { /* db yo'q */ }
  const up = await one(`SELECT count(*)::int AS files, coalesce(sum(length(data)),0)::bigint AS bytes FROM photos`);
  // Email kodlari: oxirgi soatda yuborilgan va hozir kutilayotganlar
  const codes = await one(`SELECT count(*)::int AS pending, count(*) FILTER (WHERE sent_at >= now() - interval '1 hour')::int AS hour FROM email_codes WHERE expires_at > now()`).catch(() => ({ pending: 0, hour: 0 }));
  res.json({
    time: new Date().toISOString(),
    uptime: Math.round((Date.now() - startedAt) / 1000),
    node: process.version,
    memory: { rss: mem.rss, heapUsed: mem.heapUsed, heapTotal: mem.heapTotal },
    db,
    uploads: { files: up.files, bytes: Number(up.bytes), storage: storageEnabled ? 'supabase' : 'postgres' },
    bot: null,
    mail: { ...mailInfo, serviceId: process.env.EMAILJS_SERVICE_ID || null, templateId: process.env.EMAILJS_TEMPLATE_ID || null, publicKey: !!process.env.EMAILJS_PUBLIC_KEY, codesPending: codes.pending, codesHour: codes.hour },
    env: { groqModel: aiInfo.model ? `${aiInfo.model} (${aiInfo.provider})` : "AI kaliti yo'q", visionModel: aiInfo.model || '—', redis: false, port: process.env.PORT || 3000, webappUrl: process.env.ADMIN_URL || null, nodeEnv: process.env.NODE_ENV || 'development' },
    platform: process.platform,
    cpuLoad: os.loadavg(),
    logTail: logTail(40),
  });
}));

export default r;
