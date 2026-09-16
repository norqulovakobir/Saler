import { Router } from 'express';
import { q, one, all } from './db.js';
import { ah, HttpError, newId, newToken, hashPassword, checkPassword, storeDataUri, distanceKm, shopLevel, shopRating, num, str, log, nameKey, dataUriHash, normPhone, REGIONS } from './util.js';
import { sendCode, checkCode, consumeCode, personName, needPhone, needEmail, needLogin, needPassword, needTelegram, ensureEmailAvailable, claimEmail, releaseEmail } from './verify.js';
import { assistantReply, shopChatReply, sellerAdvice, sellerAiSummary, userInterests } from './ai.js';
import { emit, notifyShop, sseHandler, clientInfo, placeName } from './events.js';
import courierRouter, { serializeCourier, assignCourier, routeKmOf } from './courier.js';

const r = Router();

// ---------- serializers ----------
export function serializeShop(s, extra = {}) {
  const sales = num(s.sales);
  return {
    id: s.id, name: s.name, sellerName: s.seller_name || 'Madina', ownerName: s.owner_name, phone: s.phone, logo: s.logo,
    description: s.description, login: s.login, firstName: s.first_name || '', lastName: s.last_name || '', email: s.email || '',
    emailVerified: !!s.email_verified_at, region: s.region || '',
    location: s.lat != null ? { lat: s.lat, lon: s.lon, address: s.address } : null,
    productCount: num(s.product_count), sales, rating: shopRating(sales), level: shopLevel(sales), followers: num(s.followers),
    createdAt: s.created_at, ...extra,
  };
}
export const serializeProduct = (p) => ({
  id: p.id, shopId: p.shop_id, name: p.name, category: p.category, price: Number(p.price),
  description: p.description, photos: p.photos || [], active: p.active, views: p.views, createdAt: p.created_at,
});
export const serializeOrder = (o) => ({
  id: o.id, status: o.status, createdAt: o.created_at, productName: o.product_name, price: Number(o.price),
  customerName: o.customer_name, phone: o.phone, address: o.address, buyerLink: o.customer_name || 'Ilova',
  items: o.items || [], shopId: o.shop_id, shopName: o.shop_name || '', shopPhone: o.shop_phone || '',
  courierId: o.courier_id, deliveryStatus: o.delivery_status,
  shopLocation: o.shop_lat != null ? { lat: o.shop_lat, lon: o.shop_lon, address: o.shop_address } : null,
  location: o.lat != null ? { lat: o.lat, lon: o.lon } : null,
  courierName: o.courier_name || '', courierPhone: o.courier_phone || '',
  deliveryFee: o.delivery_fee != null ? Number(o.delivery_fee) : null, routeKm: o.route_km ?? routeKmOf(o),
  pickedAt: o.picked_at, deliveredAt: o.delivered_at,
});

const SHOP_SQL = `
  SELECT s.*,
    (SELECT count(*) FROM products p WHERE p.shop_id=s.id AND p.active)::int AS product_count,
    (SELECT count(*) FROM orders o WHERE o.shop_id=s.id AND o.status='done' AND NOT o.archived)::int AS sales,
    (SELECT count(*) FROM follows f WHERE f.shop_id=s.id)::int AS followers
  FROM shops s`;
const ORDER_SQL = `
  SELECT o.*, s.name AS shop_name, s.phone AS shop_phone, s.lat AS shop_lat, s.lon AS shop_lon, s.address AS shop_address,
    c.name AS courier_name, c.phone AS courier_phone
  FROM orders o JOIN shops s ON s.id=o.shop_id LEFT JOIN couriers c ON c.id=o.courier_id`;
export const getShop = (id) => one(`${SHOP_SQL} WHERE s.id=$1`, [id]);

// ---------- auth ----------
r.post('/auth/guest', ah(async (req, res) => {
  const name = str(req.body?.name, 'Xaridor').slice(0, 80) || 'Xaridor';
  const u = await one('INSERT INTO users(name) VALUES($1) RETURNING *', [name]);
  const token = newToken();
  await q('INSERT INTO sessions(token, user_id) VALUES($1,$2)', [token, u.id]);
  res.json({ token, user: { id: u.id, name: u.name } });
}));

// Token -> req.user / req.shop / req.courier
r.use(ah(async (req, _res, next) => {
  const m = (req.headers.authorization || '').match(/^Bearer (.+)$/);
  if (!m) throw new HttpError(401, 'Token yo\'q');
  const s = await one('SELECT * FROM sessions WHERE token=$1 AND user_id IS NOT NULL', [m[1]]);
  if (!s) throw new HttpError(401, 'Token eskirgan');
  req.session = s;
  req.user = await one('SELECT * FROM users WHERE id=$1', [s.user_id]);
  if (!req.user) throw new HttpError(401, 'Foydalanuvchi topilmadi');
  q('UPDATE users SET last_seen=now() WHERE id=$1 AND last_seen < now() - interval \'10 minute\'', [s.user_id]).catch(() => {});
  req.shop = s.shop_id ? await getShop(s.shop_id) : null;
  req.courier = s.courier_id ? await one('SELECT * FROM couriers WHERE id=$1', [s.courier_id]) : null;
  // Mehmon hamma narsani ko'ra oladi. Buyurtma, Reels, obuna va layk uchun tasdiqlangan xaridor hisobi kerak
  if (needsBuyer(req)) {
    if (!req.user.registered_at) throw new HttpError(403, "Davom etish uchun ismingiz, telefon va emailingizni tasdiqlang", { needAuth: true });
    if (req.user.blocked) throw new HttpError(403, "Hisobingiz bloklangan. Qo'llab-quvvatlash xizmatiga murojaat qiling");
  }
  next();
}));
const BUYER_ONLY = [
  [/^\/orders$/, 'POST'], [/^\/reels(\/|$)/], [/^\/me\/interests$/], [/^\/products\/[^/]+\/like$/], [/^\/shops\/[^/]+\/follow$/],
  [/^\/cargo\/orders$/, 'POST'], [/^\/courier-requests$/, 'POST'],
];
const needsBuyer = (req) => BUYER_ONLY.some(([re, method]) => re.test(req.path) && (!method || method === req.method));
const publicUser = (u) => ({
  id: u.id, name: u.name, firstName: u.first_name || '', lastName: u.last_name || '', phone: u.phone || null,
  email: u.email || null, telegram: u.telegram || null, emailVerified: !!u.email_verified_at, registered: !!u.registered_at,
});

r.get('/me', ah(async (req, res) => {
  res.json({
    user: publicUser(req.user),
    shop: req.shop ? serializeShop(req.shop) : null,
    courier: req.courier ? serializeCourier(req.courier) : null,
  });
}));


// ---------- xaridor: email kod bilan tasdiqlanadigan hisob ----------
// 1-qadam (code yo'q): ma'lumotlar tekshiriladi va emailga 6 xonali kod yuboriladi.
// 2-qadam (code bor): kod to'g'ri bo'lsa hisob tasdiqlanadi va sessiya shu hisobga bog'lanadi.
r.post('/auth/buyer', ah(async (req, res) => {
  const b = req.body || {};
  const firstName = personName(b.firstName, 'Ism');
  const lastName = personName(b.lastName, 'Familiya');
  const phone = needPhone(b.phone);
  const telegram = needTelegram(b.telegram);
  const email = needEmail(b.email);
  // Shu email bilan hisob bo'lsa (boshqa qurilma), sessiya o'sha hisobga o'tadi
  const existing = await one('SELECT * FROM users WHERE lower(email)=$1', [email]);
  await ensureEmailAvailable(email, { type: 'buyer', accountId: existing?.id });
  if (existing?.blocked) throw new HttpError(403, "Bu hisob bloklangan. Qo'llab-quvvatlash xizmatiga murojaat qiling");
  const targetId = existing ? existing.id : !req.user.registered_at ? req.user.id : null;
  const phoneOwner = await one('SELECT id, email_verified_at FROM users WHERE phone=$1 AND ($2::int IS NULL OR id<>$2)', [phone, targetId]);
  if (phoneOwner?.email_verified_at) throw new HttpError(409, "Bu telefon raqami boshqa email bilan tasdiqlangan. O'sha emailni kiriting", { field: 'phone' });

  const binding = `buyer:${phone}`;
  if (!str(b.code).trim()) return res.json(await sendCode({ email, purpose: 'buyer', name: firstName, binding }));

  await checkCode({ email, purpose: 'buyer', code: b.code, binding });
  // Eski tasdiqlanmagan hisobdagi raqam bo'shatiladi
  if (phoneOwner) await q('UPDATE users SET phone=NULL WHERE id=$1', [phoneOwner.id]);
  const target = targetId != null ? { id: targetId } : await one('INSERT INTO users(name) VALUES($1) RETURNING id', [firstName]);
  await claimEmail(email, 'buyer', target.id);
  const u = await one(`UPDATE users SET name=$2, first_name=$3, last_name=$4, phone=$5, email=$6, telegram=$7,
      email_verified_at=now(), registered_at=coalesce(registered_at, now()) WHERE id=$1 RETURNING *`,
  [target.id, `${firstName} ${lastName}`, firstName, lastName, phone, email, telegram]);
  if (u.id !== req.user.id) await q('UPDATE sessions SET user_id=$2 WHERE token=$1', [req.session.token, u.id]);
  await consumeCode(email, 'buyer');
  log('Xaridor tasdiqlandi', u.id);
  res.json({ user: publicUser(u) });
}));

r.post('/auth/logout', ah(async (req, res) => {
  if (req.courier) await q('UPDATE couriers SET online=false WHERE id=$1', [req.courier.id]);
  await q('DELETE FROM sessions WHERE token=$1', [req.session.token]);
  res.json({ ok: true });
}));

// ---------- parolni tiklash (sotuvchi, kuryer, yuk tashuvchi): email kod bilan ----------
r.post('/auth/reset', ah(async (req, res) => {
  const b = req.body || {};
  const role = ['seller', 'courier', 'cargo'].includes(b.role) ? b.role : null;
  if (!role) throw new HttpError(400, "Rolni tanlang");
  const login = needLogin(b.login);
  const email = needEmail(b.email);
  const table = role === 'seller' ? 'shops' : 'couriers';
  const acc = role === 'seller'
    ? await one('SELECT id, login, first_name, name, active FROM shops WHERE login=$1 AND lower(email)=$2 AND email_verified_at IS NOT NULL', [login, email])
    : await one('SELECT id, login, first_name, name, active FROM couriers WHERE login=$1 AND lower(email)=$2 AND type=$3 AND email_verified_at IS NOT NULL', [login, email, role]);
  const binding = `reset:${role}:${acc?.id ?? login}`;
  if (!str(b.code).trim()) {
    // Hisob bor-yo'qligini oshkor qilmaslik uchun javob bir xil
    if (!acc) return res.json({ codeSent: true, email, expiresIn: 600, resendIn: 60 });
    return res.json(await sendCode({ email, purpose: 'reset', name: acc.first_name || acc.name, binding }));
  }
  const password = needPassword(b.password);
  if (!acc) throw new HttpError(400, "Kod noto'g'ri", { codeInvalid: true });
  await checkCode({ email, purpose: 'reset', code: b.code, binding });
  await q(`UPDATE ${table} SET pass_hash=$2 WHERE id=$1`, [acc.id, hashPassword(password)]);
  // Boshqa qurilmalardagi sessiyalar yopiladi
  await q(`UPDATE sessions SET ${role === 'seller' ? 'shop_id' : 'courier_id'}=NULL WHERE ${role === 'seller' ? 'shop_id' : 'courier_id'}=$1 AND token<>$2`, [acc.id, req.session.token]);
  await consumeCode(email, 'reset');
  if (role === 'seller') notifyShop(acc.id, 'security', 'Parol tiklandi', 'Hisobingiz paroli email orqali tiklandi. Bu siz bo\'lmasangiz, darhol qo\'llab-quvvatlashga yozing.').catch(() => {});
  res.json({ ok: true, login: acc.login });
}));

// Jonli hodisalar oqimi (SSE): ilova ulanib turadi, buyurtma, pul, bildirishnoma darhol keladi
r.get('/events', sseHandler);

// ---------- seller auth ----------
const loginNotice = (req, shopId) => {
  // Xavfsizlik xabarnomasi: qaysi qurilma va ilovadan, qayerdan kirilgani (javobni kechiktirmaslik uchun fonda)
  const who = clientInfo(req);
  (async () => {
    const place = await placeName(who.lat, who.lon);
    const when = new Date().toLocaleString('ru-RU', { timeZone: 'Asia/Tashkent' });
    const lines = [
      `Qurilma: ${who.device}`,
      `Ilova: ${who.app}`,
      place ? `Joylashuv: ${place}` : who.lat != null ? `Joylashuv: ${who.lat.toFixed(4)}, ${who.lon.toFixed(4)}` : 'Joylashuv: aniqlanmadi (qurilmada joylashuvga ruxsat berilmagan)',
      who.ip ? `IP: ${who.ip}` : null,
      `Vaqt: ${when}`,
    ].filter(Boolean);
    await notifyShop(shopId, 'security', 'Hisobingizga kirildi', lines.join('\n'), {
      device: who.device, app: who.app, ip: who.ip, place, lat: who.lat, lon: who.lon,
      mapUrl: who.lat != null ? `https://www.google.com/maps?q=${who.lat},${who.lon}` : null,
    });
  })().catch((e) => log('Kirish xabari xato', e.message));
};

/** Do'kon ochish ma'lumotlarini tekshiradi (kod yuborishdan oldin ham, keyin ham) */
async function sellerSignup(b) {
  const d = {
    firstName: personName(b.firstName, 'Ism'),
    lastName: personName(b.lastName, 'Familiya'),
    phone: needPhone(b.phone),
    email: needEmail(b.email),
    shopName: str(b.shopName ?? b.name).trim().replace(/\s+/g, ' ').slice(0, 60),
    aiName: str(b.aiName ?? b.sellerName).trim().replace(/\s+/g, ' ').slice(0, 30) || 'Madina',
    region: str(b.region).trim(),
    login: needLogin(b.login),
    password: needPassword(b.password),
  };
  if (d.shopName.length < 2) throw new HttpError(400, "Do'kon nomini kiriting", { field: 'shopName' });
  if (b.logo && !/^data:image\//.test(String(b.logo))) throw new HttpError(400, 'Logo rasm bo\'lishi kerak', { field: 'logo' });
  if (!REGIONS.includes(d.region)) throw new HttpError(400, 'Viloyatni tanlang', { field: 'region' });
  const l = b.location || {};
  const lat = Number(l.lat), lon = Number(l.lon);
  if (!Number.isFinite(lat) || !Number.isFinite(lon) || Math.abs(lat) > 90 || Math.abs(lon) > 180) throw new HttpError(400, "Do'kon joylashuvini xaritada belgilang", { field: 'location' });
  d.location = { lat, lon, address: str(l.address).trim().slice(0, 200) };
  if (!d.location.address) throw new HttpError(400, "Do'kon manzilini kiriting", { field: 'address' });
  if (await one('SELECT 1 FROM shops WHERE login=$1', [d.login])) throw new HttpError(409, 'Bu login band. Boshqasini tanlang', { field: 'login' });
  await ensureEmailAvailable(d.email, { type: 'seller' });
  return d;
}

// 1-qadam: tekshiruv va emailga kod. 2-qadam (code bilan): do'kon yaratiladi
r.post('/seller/register', ah(async (req, res) => {
  const b = req.body || {};
  const d = await sellerSignup(b);
  const binding = `seller:${d.login}`;
  if (!str(b.code).trim()) return res.json(await sendCode({ email: d.email, purpose: 'seller', name: d.firstName, binding }));
  await checkCode({ email: d.email, purpose: 'seller', code: b.code, binding });
  const logo = b.logo ? await storeDataUri(b.logo) : null;
  const id = newId('s_');
  let emailClaimed = false;
  try {
    await claimEmail(d.email, 'seller', id);
    emailClaimed = true;
    await q(`INSERT INTO shops(id, name, seller_name, owner_name, first_name, last_name, phone, email, email_verified_at, region, login, pass_hash, logo, lat, lon, address, last_login_at)
      VALUES($1,$2,$3,$4,$5,$6,$7,$8,now(),$9,$10,$11,$12,$13,$14,$15,now())`,
    [id, d.shopName, d.aiName, `${d.firstName} ${d.lastName}`, d.firstName, d.lastName, d.phone, d.email, d.region, d.login, hashPassword(d.password), logo, d.location.lat, d.location.lon, d.location.address]);
  } catch (e) {
    if (emailClaimed) await releaseEmail(d.email, 'seller', id).catch(() => {});
    if (e.code === '23505') throw new HttpError(409, 'Bu login band. Boshqasini tanlang', { field: 'login' });
    throw e;
  }
  await consumeCode(d.email, 'seller');
  await q('UPDATE sessions SET shop_id=$2, courier_id=NULL WHERE token=$1', [req.session.token, id]);
  await notifyShop(id, 'system', "Do'koningiz ochildi", `${d.aiName} — do'koningizning AI sotuvchisi ishga tushdi. Birinchi mahsulotingizni qo'shing, xaridorlar va obunachilar uni darhol ko'radi.`).catch(() => {});
  log("Yangi do'kon", id, d.shopName);
  res.json({ shop: serializeShop(await getShop(id)) });
}));

r.post('/seller/login', ah(async (req, res) => {
  const login = needLogin(req.body?.login);
  const email = needEmail(req.body?.email);
  const s = await one('SELECT * FROM shops WHERE login=$1 AND lower(email)=$2', [login, email]);
  if (!s || !checkPassword(str(req.body?.password), s.pass_hash)) throw new HttpError(403, "Login, email yoki parol noto'g'ri");
  if (!s.active) throw new HttpError(403, "Do'koningiz bloklangan. Qo'llab-quvvatlash xizmatiga murojaat qiling");
  await q('UPDATE sessions SET shop_id=$2, courier_id=NULL WHERE token=$1', [req.session.token, s.id]);
  await q('UPDATE shops SET last_login_at=now() WHERE id=$1', [s.id]);
  loginNotice(req, s.id);
  res.json({ shop: serializeShop(await getShop(s.id)) });
}));

r.post('/seller/logout', ah(async (req, res) => {
  await q('UPDATE sessions SET shop_id=NULL WHERE token=$1', [req.session.token]);
  res.json({ ok: true });
}));

const needShop = (req) => { if (!req.shop) throw new HttpError(403, 'Sotuvchi sifatida kiring'); return req.shop; };

r.post('/seller/password', ah(async (req, res) => {
  const shop = needShop(req);
  const { oldPassword, newPassword, code } = req.body || {};
  if (!checkPassword(str(oldPassword), shop.pass_hash)) throw new HttpError(400, "Joriy parol noto'g'ri");
  const password = needPassword(newPassword);
  const email = needEmail(shop.email);
  // Ikki bosqich: avval joriy parol tekshiriladi va emailga kod jo'natiladi,
  // keyin kod bilan tasdiqlangandagina yangi parol saqlanadi.
  if (!str(code).trim()) {
    return res.json(await sendCode({ email, purpose: 'password', name: shop.first_name || shop.owner_name || shop.name, binding: `password:seller:${shop.id}` }));
  }
  await checkCode({ email, purpose: 'password', code, binding: `password:seller:${shop.id}` });
  await q('UPDATE shops SET pass_hash=$2 WHERE id=$1', [shop.id, hashPassword(password)]);
  await consumeCode(email, 'password');
  const who = clientInfo(req);
  await notifyShop(shop.id, 'security', "Parol o'zgartirildi", `Do'kon paroli email kodi bilan yangilandi.\nQurilma: ${who.device}\nIlova: ${who.app}${who.ip ? `\nIP: ${who.ip}` : ''}`, { device: who.device, app: who.app, ip: who.ip });
  res.json({ ok: true });
}));

r.post('/seller/reset', ah(async (req, res) => {
  const shop = needShop(req);
  if (!checkPassword(str(req.body?.password), shop.pass_hash)) throw new HttpError(400, "Parol noto'g'ri");
  const n = (await q('UPDATE orders SET archived=true WHERE shop_id=$1 AND NOT archived', [shop.id])).rowCount;
  await q('UPDATE products SET views=0 WHERE shop_id=$1', [shop.id]);
  await q('DELETE FROM product_views WHERE shop_id=$1', [shop.id]);
  await q('DELETE FROM notifications WHERE shop_id=$1', [shop.id]);
  await q('DELETE FROM shop_advice WHERE shop_id=$1', [shop.id]);
  res.json({ orders: n });
}));

// ---------- catalog ----------
// Do'kon ko'rsatkichlari bitta so'rovda (har do'kon uchun alohida subquery o'rniga guruhlab hisoblanadi)
const SHOP_STATS_SQL = `
  WITH pc AS (SELECT shop_id, count(*)::int AS n, coalesce(sum(views),0)::int AS views FROM products WHERE active GROUP BY shop_id),
       oc AS (SELECT shop_id, count(*)::int AS n FROM orders WHERE status='done' AND NOT archived GROUP BY shop_id)
  SELECT s.*, coalesce(pc.n,0) AS product_count, coalesce(oc.n,0) AS sales, coalesce(pc.views,0) AS product_views,
    (SELECT count(*) FROM follows f WHERE f.shop_id=s.id)::int AS followers
  FROM shops s LEFT JOIN pc ON pc.shop_id=s.id LEFT JOIN oc ON oc.shop_id=s.id`;

/**
 * Bosh sahifadagi do'konlar.
 * - `limit` berilsa sahifalab ishlaydi va { items, hasMore, seed } qaytaradi. Berilmasa eski ilovalar uchun massiv (200 tagacha).
 * - Qidiruvsiz: yaxshi do'konlar vaznli tasodifiy tartibda. Sotuv, mahsulot, ko'rishlar, logo va joylashuv vaznni oshiradi,
 *   mahsulotsiz do'konlar oxirida. Tartib `seed` ga bog'liq: bir seed bilan keyingi sahifalarda do'kon takrorlanmaydi.
 * - Qidiruvda: nomi mos kelganlar oldin, keyin sotuvlar bo'yicha.
 */
r.get('/shops', ah(async (req, res) => {
  const text = str(req.query.q).trim();
  const paged = req.query.limit != null;
  const limit = paged ? Math.min(50, Math.max(1, Math.floor(num(req.query.limit, 20)))) : 200;
  const offset = paged ? Math.max(0, Math.floor(num(req.query.offset, 0))) : 0;
  if (text.length >= 2 && offset === 0) q('INSERT INTO user_searches(user_id, q) VALUES($1,$2)', [req.user.id, text.slice(0, 80)]).catch(() => {});
  const seed = str(req.query.seed).slice(0, 64) || newToken().slice(0, 12);
  let where = 'WHERE s.active';
  let order;
  const params = [];
  if (text) {
    params.push(`%${text}%`);
    where += ' AND (s.name ILIKE $1 OR s.description ILIKE $1 OR EXISTS (SELECT 1 FROM products p WHERE p.shop_id=s.id AND p.active AND p.name ILIKE $1))';
    order = '(t.name ILIKE $1) DESC, t.sales DESC, t.product_count DESC, t.created_at DESC, t.id';
  } else {
    params.push(seed);
    // Efraimidis–Spirakis vaznli tasodifiy tartib: kalit = ln(u) / vazn, u esa seed va do'kon id'sidan olingan (0;1) son
    order = `(t.product_count > 0) DESC,
      ln((hashtext(t.id || $1)::bigint + 2147483649)::float8 / 4294967297)
        / (1 + 3 * ln(1 + t.sales::float8) + ln(1 + t.product_count::float8) + 0.5 * ln(1 + t.product_views::float8)
           + CASE WHEN t.logo IS NOT NULL THEN 0.5 ELSE 0 END + CASE WHEN t.lat IS NOT NULL THEN 0.5 ELSE 0 END) DESC,
      t.id`;
  }
  params.push(limit + 1, offset);
  const rows = await all(`SELECT * FROM (${SHOP_STATS_SQL} ${where}) t ORDER BY ${order} LIMIT $${params.length - 1} OFFSET $${params.length}`, params);
  const items = rows.slice(0, limit).map((s) => serializeShop(s));
  if (!paged) return res.json(items);
  res.json({ items, hasMore: rows.length > limit, seed: text ? null : seed });
}));

r.get('/shops-map', ah(async (_req, res) => {
  const rows = await all(`${SHOP_SQL} WHERE s.active AND s.lat IS NOT NULL ORDER BY sales DESC`);
  res.json(rows.map((s) => serializeShop(s)));
}));

r.get('/shops-rating', ah(async (_req, res) => {
  const rows = await all(`${SHOP_SQL} WHERE s.active ORDER BY sales DESC, product_count DESC, s.created_at ASC LIMIT 100`);
  res.json(rows.map((s, i) => serializeShop(s, { rank: i + 1 })));
}));

r.get('/shops/:id', ah(async (req, res) => {
  const s = await getShop(req.params.id);
  if (!s) throw new HttpError(404, "Do'kon topilmadi");
  const products = await all('SELECT * FROM products WHERE shop_id=$1 AND active ORDER BY created_at DESC', [s.id]);
  res.json({ shop: serializeShop(s, await followInfo(s.id, req.user.id)), products: products.map(serializeProduct) });
}));

r.get('/categories/:slug/products', ah(async (req, res) => {
  const rows = await all(`SELECT p.* FROM products p JOIN shops s ON s.id=p.shop_id WHERE p.category=$1 AND p.active AND s.active ORDER BY p.views DESC, p.created_at DESC LIMIT 300`, [req.params.slug]);
  const shopIds = [...new Set(rows.map((p) => p.shop_id))];
  const shops = shopIds.length ? await all(`${SHOP_SQL} WHERE s.id = ANY($1)`, [shopIds]) : [];
  const byId = Object.fromEntries(shops.map((s) => [s.id, serializeShop(s)]));
  res.json(rows.map((p) => ({ ...serializeProduct(p), shop: byId[p.shop_id] || null })));
}));

r.get('/products/:id', ah(async (req, res) => {
  const p = await one('SELECT * FROM products WHERE id=$1', [req.params.id]);
  if (!p) throw new HttpError(404, 'Mahsulot topilmadi');
  const s = await getShop(p.shop_id);
  res.json({ product: serializeProduct(p), shop: s ? serializeShop(s) : null });
}));

/** Nomdagi mazmunli so'zlar (o'xshash mahsulotlarni topish uchun) */
const STOP_WORDS = new Set(['va', 'uchun', 'bilan', 'yangi', 'sotiladi', 'arzon', 'для', 'и', 'с', 'на', 'new', 'the', 'and', 'for', 'with']);
const nameWords = (name) => [...new Set(String(name || '').toLowerCase().split(/[^\p{L}\p{N}]+/u).filter((w) => w.length >= 3 && !STOP_WORDS.has(w)))].slice(0, 8);

/** Mahsulot sahifasi ostidagi o'xshash mahsulotlar: bir xil kategoriya, nomdagi umumiy so'zlar, yaqin narx, shu do'kon */
r.get('/products/:id/related', ah(async (req, res) => {
  const limit = Math.min(20, Math.max(1, Math.floor(num(req.query.limit, 10))));
  const p = await one('SELECT * FROM products WHERE id=$1', [req.params.id]);
  if (!p) throw new HttpError(404, 'Mahsulot topilmadi');
  const words = nameWords(p.name);
  const rows = await all(`SELECT p.* FROM products p JOIN shops s ON s.id=p.shop_id
    WHERE p.active AND s.active AND p.id<>$1 AND (p.category=$2 OR p.shop_id=$3 OR p.name ILIKE ANY($4::text[]))
    ORDER BY p.views DESC, p.created_at DESC LIMIT 300`, [p.id, p.category, p.shop_id, words.map((w) => `%${w}%`)]);
  const price = Number(p.price) || 0;
  const ranked = rows
    .map((c) => {
      const cw = nameWords(c.name);
      const common = words.filter((w) => cw.some((x) => x.startsWith(w) || w.startsWith(x))).length;
      const cp = Number(c.price) || 0;
      const priceNear = price > 0 && cp > 0 ? 1 / (1 + Math.abs(Math.log(cp / price))) : 0;
      const score = (p.category && c.category === p.category ? 3 : 0) + common * 2.5 + (c.shop_id === p.shop_id ? 1 : 0)
        + priceNear * 1.5 + Math.log10(1 + (c.views || 0)) * 0.3;
      return { c, score };
    })
    .sort((a, b) => b.score - a.score);
  // Xilma-xillik: bir xil nomli mahsulot 2 tadan, bitta do'kondan 3 tadan oshmasin; joy qolsa qolganlari bilan to'ldiriladi
  const picked = [], rest = [], byName = {}, byShop = {};
  for (const { c } of ranked) {
    const nameKey = c.name.trim().toLowerCase();
    if (picked.length < limit && (byName[nameKey] || 0) < 2 && (byShop[c.shop_id] || 0) < 3) {
      picked.push(c);
      byName[nameKey] = (byName[nameKey] || 0) + 1;
      byShop[c.shop_id] = (byShop[c.shop_id] || 0) + 1;
    } else rest.push(c);
  }
  const related = [...picked, ...rest].slice(0, limit);
  const shopIds = [...new Set(related.map((x) => x.shop_id))];
  const shops = shopIds.length ? await all(`${SHOP_SQL} WHERE s.id = ANY($1)`, [shopIds]) : [];
  const byId = Object.fromEntries(shops.map((s) => [s.id, serializeShop(s)]));
  res.json({ items: related.map((x) => ({ ...serializeProduct(x), shop: byId[x.shop_id] || null })) });
}));

r.post('/products/:id/view', ah(async (req, res) => {
  const p = await one('SELECT id, shop_id, views FROM products WHERE id=$1', [req.params.id]);
  if (!p) throw new HttpError(404, 'Mahsulot topilmadi');
  const ins = await one('INSERT INTO product_views(product_id, user_id, shop_id) VALUES($1,$2,$3) ON CONFLICT DO NOTHING RETURNING id', [p.id, req.user.id, p.shop_id]);
  let views = p.views;
  if (ins) views = (await one('UPDATE products SET views=views+1 WHERE id=$1 RETURNING views', [p.id])).views;
  res.json({ views });
}));

// ---------- obunalar, layklar, Reels, qiziqishlar ----------
const followInfo = (shopId, userId) => one(`SELECT (SELECT count(*) FROM follows WHERE shop_id=$1)::int AS followers,
  EXISTS(SELECT 1 FROM follows WHERE shop_id=$1 AND user_id=$2) AS following`, [shopId, userId]);
const likeInfo = (productId, userId) => one(`SELECT (SELECT count(*) FROM product_likes WHERE product_id=$1)::int AS likes,
  EXISTS(SELECT 1 FROM product_likes WHERE product_id=$1 AND user_id=$2) AS liked`, [productId, userId]);

r.post('/shops/:id/follow', ah(async (req, res) => {
  const s = await one('SELECT id, name FROM shops WHERE id=$1 AND active', [req.params.id]);
  if (!s) throw new HttpError(404, "Do'kon topilmadi");
  const ins = await one('INSERT INTO follows(user_id, shop_id) VALUES($1,$2) ON CONFLICT DO NOTHING RETURNING shop_id', [req.user.id, s.id]);
  const f = await followInfo(s.id, req.user.id);
  if (ins) {
    await notifyShop(s.id, 'follow', 'Yangi obunachi', `${req.user.name || 'Xaridor'} do'koningizga obuna bo'ldi. Obunachilar: ${f.followers}`, { followers: f.followers });
    dropAffinity(req.user.id);
    maybeRefreshInterests(req.user.id);
  }
  res.json(f);
}));

r.delete('/shops/:id/follow', ah(async (req, res) => {
  await q('DELETE FROM follows WHERE user_id=$1 AND shop_id=$2', [req.user.id, req.params.id]);
  res.json(await followInfo(req.params.id, req.user.id));
}));

r.post('/products/:id/like', ah(async (req, res) => {
  const p = await one('SELECT id FROM products WHERE id=$1', [req.params.id]);
  if (!p) throw new HttpError(404, 'Mahsulot topilmadi');
  await q('INSERT INTO product_likes(user_id, product_id) VALUES($1,$2) ON CONFLICT DO NOTHING', [req.user.id, p.id]);
  dropAffinity(req.user.id);
  maybeRefreshInterests(req.user.id);
  res.json(await likeInfo(p.id, req.user.id));
}));

r.delete('/products/:id/like', ah(async (req, res) => {
  await q('DELETE FROM product_likes WHERE user_id=$1 AND product_id=$2', [req.user.id, req.params.id]);
  res.json(await likeInfo(req.params.id, req.user.id));
}));

/** Qiziqishlarni aniqlash uchun foydalanuvchi harakatlari */
async function collectSignals(uid) {
  const [reels, likes, views, orders, searches, chats, follows] = await Promise.all([
    all(`SELECT p.name, p.category, max(e.dwell_ms)::int AS ms FROM reel_events e JOIN products p ON p.id=e.product_id
      WHERE e.user_id=$1 AND e.created_at > now() - interval '30 days' GROUP BY p.id ORDER BY ms DESC LIMIT 25`, [uid]),
    all('SELECT p.name, p.category FROM product_likes l JOIN products p ON p.id=l.product_id WHERE l.user_id=$1 ORDER BY l.created_at DESC LIMIT 20', [uid]),
    all('SELECT p.name, p.category FROM product_views v JOIN products p ON p.id=v.product_id WHERE v.user_id=$1 ORDER BY v.created_at DESC LIMIT 20', [uid]),
    all(`SELECT i->>'name' AS name, p.category FROM orders o CROSS JOIN LATERAL jsonb_array_elements(o.items) i
      LEFT JOIN products p ON p.id = i->>'productId' WHERE o.user_id=$1 ORDER BY o.created_at DESC LIMIT 20`, [uid]),
    all('SELECT q FROM user_searches WHERE user_id=$1 ORDER BY created_at DESC LIMIT 15', [uid]),
    all("SELECT text FROM chat_messages WHERE user_id=$1 AND role='user' ORDER BY id DESC LIMIT 10", [uid]),
    all('SELECT s.name FROM follows f JOIN shops s ON s.id=f.shop_id WHERE f.user_id=$1 LIMIT 20', [uid]),
  ]);
  return { reels, likes, views, orders, searches: searches.map((x) => x.q), chats: chats.map((x) => x.text.slice(0, 160)), follows: follows.map((x) => x.name) };
}

const interestJobs = new Set();
// Har bir surishda bazaga so'rov yubormaslik uchun: bitta foydalanuvchi uchun 60 soniyada bir marta tekshiriladi
const interestSeen = new Map();
/** Qiziqishlar profilini fonda Gemini bilan yangilaydi: ko'pi bilan 20 daqiqada bir marta (force bo'lmasa) */
function maybeRefreshInterests(userId, { force = false } = {}) {
  if (interestJobs.has(userId)) return;
  if (!force) {
    const last = interestSeen.get(userId) || 0;
    if (Date.now() - last < 60e3) return;
    interestSeen.set(userId, Date.now());
    if (interestSeen.size > 5000) interestSeen.delete(interestSeen.keys().next().value);
  }
  interestJobs.add(userId);
  (async () => {
    const u = await one('SELECT interests, interests_at FROM users WHERE id=$1', [userId]);
    // Profil bo'sh bo'lsa (harakatlar hali kam edi) 30 soniyadan keyin qayta urinadi, to'lgan bo'lsa 20 daqiqada bir marta
    const empty = !(u?.interests?.categories?.length || u?.interests?.keywords?.length);
    const gap = empty ? 30e3 : 20 * 60e3;
    if (!force && u?.interests_at && Date.now() - new Date(u.interests_at).getTime() < gap) return;
    const interests = await userInterests({ signals: await collectSignals(userId) });
    await q('UPDATE users SET interests=$2, interests_at=now() WHERE id=$1', [userId, JSON.stringify(interests)]);
  })().catch((e) => log('Qiziqishlar xato', e.message)).finally(() => interestJobs.delete(userId));
}

r.get('/me/interests', ah(async (req, res) => {
  const u = await one('SELECT interests, interests_at FROM users WHERE id=$1', [req.user.id]);
  const empty = !(u?.interests?.categories?.length || u?.interests?.keywords?.length);
  if (empty) maybeRefreshInterests(req.user.id, { force: true });
  const i = u?.interests || {};
  res.json({ categories: i.categories || [], keywords: i.keywords || [], summary: i.summary || null, source: i.source || null, updatedAt: u?.interests_at || null });
}));

// ---------- Reels: qiziqishga asoslangan tartib ----------
// Nomzodlar ro'yxati hamma uchun umumiy keshda turadi: har bir foydalanuvchi uchun bazaga og'ir so'rov ketmaydi.
const POOL_TTL = 120e3;
let poolCache = { at: 0, rows: [] };
// Har bir foydalanuvchi/sessiya uchun faqat ko'rib bo'lingan kichik bo'laklar.
// To'liq katalog bu yerda hech qachon RAM'ga olinmaydi.
const reelLists = new Map();
async function candidatePool() {
  if (poolCache.rows.length && Date.now() - poolCache.at < POOL_TTL) return poolCache.rows;
  const rows = await all(`
    WITH likes AS (SELECT product_id, count(*)::int AS n FROM product_likes GROUP BY product_id),
      sold AS (SELECT i->>'productId' AS pid, sum((i->>'qty')::int)::int AS n
        FROM orders o CROSS JOIN LATERAL jsonb_array_elements(o.items) i
        WHERE o.status='done' AND o.created_at > now() - interval '60 days' GROUP BY 1),
      base AS (
        SELECT p.id, p.shop_id, p.name, p.category, left(coalesce(p.description,''), 160) AS description,
          p.views, p.created_at, coalesce(l.n, 0) AS likes, coalesce(s2.n, 0) AS sold
        FROM products p
        JOIN shops s ON s.id = p.shop_id
        LEFT JOIN likes l ON l.product_id = p.id
        LEFT JOIN sold s2 ON s2.pid = p.id
        WHERE p.active AND s.active AND jsonb_array_length(p.photos) > 0
      ),
      fresh AS (SELECT * FROM base ORDER BY created_at DESC LIMIT 400),
      top AS (SELECT * FROM base ORDER BY (views + likes * 5 + sold * 10) DESC LIMIT 200)
    SELECT * FROM fresh UNION SELECT * FROM top`);
  poolCache = { at: Date.now(), rows };
  return rows;
}
/** Yangi mahsulot qo'shilsa yoki o'chirilsa nomzodlar keshi yangilanadi */
export const dropReelPool = () => {
  poolCache = { at: 0, rows: [] };
  reelLists.clear();
};

const tokens = (s) => String(s || '').toLowerCase().normalize('NFKC').split(/[^\p{L}\p{N}]+/u).filter((w) => w.length > 2 && !STOP_WORDS.has(w));

// Foydalanuvchi yaqinligi (kategoriya va kalit so'zlar) 5 daqiqa keshlanadi
const affinityCache = new Map();
const AFFINITY_TTL = 5 * 60e3;
/**
 * Harakatlardan qiziqish profili: layk, buyurtma, Reels'da uzoq ko'rish, mahsulot ko'rish.
 * Har bir signal vaqt o'tishi bilan so'nadi (yarim umr ~14 kun), shuning uchun qiziqish o'zgarsa tartib ham o'zgaradi.
 */
async function userAffinity(uid) {
  const c = affinityCache.get(uid);
  if (c && c.exp > Date.now()) return c.data;
  const decay = "exp(-extract(epoch from now() - %s) / 1209600.0)";
  const [cats, names, follows, me] = await Promise.all([
    all(`SELECT category, sum(w)::float8 AS score FROM (
        SELECT p.category, 5.0 * ${decay.replace('%s', 'l.created_at')} AS w
          FROM product_likes l JOIN products p ON p.id=l.product_id WHERE l.user_id=$1
        UNION ALL
        SELECT p.category, least(6.0, e.dwell_ms / 1500.0) * ${decay.replace('%s', 'e.created_at')}
          FROM reel_events e JOIN products p ON p.id=e.product_id
          WHERE e.user_id=$1 AND e.created_at > now() - interval '45 days'
        UNION ALL
        SELECT p.category, 8.0 * ${decay.replace('%s', 'o.created_at')}
          FROM orders o CROSS JOIN LATERAL jsonb_array_elements(o.items) i JOIN products p ON p.id = i->>'productId'
          WHERE o.user_id=$1
        UNION ALL
        SELECT p.category, 1.5 * ${decay.replace('%s', 'v.created_at')}
          FROM product_views v JOIN products p ON p.id=v.product_id WHERE v.user_id=$1
      ) t WHERE t.category IS NOT NULL AND t.category <> '' GROUP BY 1 ORDER BY 2 DESC LIMIT 12`, [uid]),
    all(`(SELECT p.name FROM product_likes l JOIN products p ON p.id=l.product_id WHERE l.user_id=$1 ORDER BY l.created_at DESC LIMIT 15)
      UNION ALL
      (SELECT p.name FROM reel_events e JOIN products p ON p.id=e.product_id
        WHERE e.user_id=$1 AND e.dwell_ms > 4000 ORDER BY e.created_at DESC LIMIT 15)`, [uid]),
    all('SELECT shop_id FROM follows WHERE user_id=$1', [uid]),
    one('SELECT interests FROM users WHERE id=$1', [uid]),
  ]);
  // Kalit so'zlar: layk qilingan va uzoq ko'rilgan mahsulot nomlaridan + AI profilidan
  const freq = new Map();
  for (const r2 of names) for (const w of tokens(r2.name)) freq.set(w, (freq.get(w) || 0) + 1);
  for (const w of (me?.interests?.keywords || [])) freq.set(String(w).toLowerCase(), (freq.get(String(w).toLowerCase()) || 0) + 2);
  const keywords = [...freq.entries()].filter(([, n]) => n >= 1).sort((a, b) => b[1] - a[1]).slice(0, 15).map(([w]) => w);
  // AI aniqlagan kategoriyalar ham qo'shiladi (harakat kam bo'lgan yangi foydalanuvchi uchun)
  const score = new Map(cats.map((x) => [x.category, Number(x.score)]));
  (me?.interests?.categories || []).forEach((cat, i) => score.set(cat, (score.get(cat) || 0) + (4 - Math.min(i, 3))));
  const max = Math.max(1, ...score.values());
  const data = {
    cats: Object.fromEntries([...score.entries()].map(([k, v]) => [k, v / max])), // 0..1
    keywords,
    follows: new Set(follows.map((f) => f.shop_id)),
    strength: Math.min(1, max / 12), // profil qanchalik to'lgani: yangi foydalanuvchida 0 ga yaqin
  };
  affinityCache.set(uid, { data, exp: Date.now() + AFFINITY_TTL });
  if (affinityCache.size > 2000) affinityCache.delete(affinityCache.keys().next().value);
  return data;
}
export const dropAffinity = (uid) => affinityCache.delete(uid);

/**
 * Bitta kichik Reel bo'lagini tanlaydi. Avvalgi yechim 400–800 mahsulotni
 * olib, Node xotirasida saralardi. Bu so'rov esa aynan kerak bo'lgan 5 yoki
 * 2 ta ID'ni SQL ichida qiziqish bo'yicha saralaydi.
 */
async function fetchReelBatch(req, seed, excluded, take) {
  const uid = req.user.id;
  const affinity = await userAffinity(uid);
  const categories = Object.entries(affinity.cats)
    .filter(([, score]) => Number(score) >= .12)
    .sort((a, b) => Number(b[1]) - Number(a[1]))
    .map(([category]) => category)
    .slice(0, 8);
  const patterns = affinity.keywords
    .map((word) => String(word).trim().toLowerCase())
    .filter((word) => word.length >= 3)
    .slice(0, 12)
    .map((word) => `%${word}%`);
  const hasInterest = categories.length > 0 || patterns.length > 0;
  const count = Math.max(1, Math.min(5, take));

  const find = async (strictInterest) => all(`
    SELECT p.id,
      CASE
        WHEN $5::boolean THEN 'interest'
        WHEN EXISTS(SELECT 1 FROM follows f WHERE f.user_id=$1 AND f.shop_id=p.shop_id)
          AND p.created_at > now() - interval '48 hours' THEN 'following'
        WHEN p.created_at > now() - interval '48 hours' THEN 'new'
        ELSE 'popular'
      END AS reason
    FROM products p
    JOIN shops s ON s.id=p.shop_id
    WHERE p.active AND s.active AND jsonb_array_length(p.photos) > 0
      AND (cardinality($2::text[]) = 0 OR p.id <> ALL($2::text[]))
      AND (
        NOT $5::boolean
        OR p.category = ANY($3::text[])
        OR lower(concat_ws(' ', p.name, coalesce(p.description, ''))) LIKE ANY($4::text[])
      )
    ORDER BY
      (
        CASE WHEN p.category = ANY($3::text[])
          THEN greatest(4, 22 - 3 * coalesce(array_position($3::text[], p.category), 7))
          ELSE 0 END
        + CASE WHEN lower(concat_ws(' ', p.name, coalesce(p.description, ''))) LIKE ANY($4::text[]) THEN 9 ELSE 0 END
        + CASE WHEN EXISTS(SELECT 1 FROM follows f WHERE f.user_id=$1 AND f.shop_id=p.shop_id) THEN 4 ELSE 0 END
        + least(6, ln(1 + greatest(0, p.views)::float8))
        + CASE WHEN p.created_at > now() - interval '72 hours' THEN 2 ELSE 0 END
        - CASE WHEN EXISTS(
          SELECT 1 FROM reel_events e
          WHERE e.user_id=$1 AND e.product_id=p.id AND e.created_at > now() - interval '24 hours'
        ) THEN 30 ELSE 0 END
      ) DESC,
      md5($6::text || p.id) ASC
    LIMIT $7`, [uid, excluded, categories, patterns, strictInterest, seed, count]);

  // Yangi foydalanuvchi qiziqishi hali aniqlanmagan bo'lsa, faqat boshlang'ich
  // 5 ta mashhur mahsulot ko'rsatiladi. Birinchi qarash/layklardan keyin
  // keyingi so'rovlar faqat qiziqishga mos mahsulotlardan tuziladi.
  let rows = await find(hasInterest);
  if (hasInterest && rows.length === 0) rows = await find(false);
  return rows.map((row) => ({ id: row.id, reason: row.reason }));
}

async function reelPage(req, seed, offset, limit) {
  const key = `${req.user.id}:${seed}`;
  let list = reelLists.get(key);
  if (!list || list.exp < Date.now()) {
    list = { ranked: [], pages: new Map(), exhausted: false, exp: Date.now() + 30 * 60e3 };
    reelLists.set(key, list);
  }
  list.exp = Date.now() + 30 * 60e3;
  const pageKey = `${offset}:${limit}`;
  if (!list.pages.has(pageKey)) {
    const wanted = offset + limit;
    while (!list.exhausted && list.ranked.length < wanted) {
      const missing = wanted - list.ranked.length;
      const batch = await fetchReelBatch(req, seed, list.ranked.map((x) => x.id), missing);
      if (!batch.length) {
        list.exhausted = true;
        break;
      }
      list.ranked.push(...batch);
      if (batch.length < missing) list.exhausted = true;
    }
    list.pages.set(pageKey, list.ranked.slice(offset, offset + limit));
  }
  const page = list.pages.get(pageKey) || [];
  return { page, hasMore: !list.exhausted || offset + page.length < list.ranked.length };
}

r.get('/reels', ah(async (req, res) => {
  const uid = req.user.id;
  // Ilova 5 ta bilan boshlaydi, keyin 2 tadan so'raydi. Limitni kichik
  // ushlab turish birinchi kadr va keyingi swipe'larni silliq qiladi.
  const limit = Math.min(5, Math.max(1, Math.floor(num(req.query.limit, 5))));
  const offset = Math.max(0, Math.floor(num(req.query.offset, 0)));
  const seed = str(req.query.seed).slice(0, 64) || newToken().slice(0, 12);
  for (const [k, value] of reelLists) if (value.exp < Date.now()) reelLists.delete(k);
  if (reelLists.size > 1000) reelLists.delete(reelLists.keys().next().value);
  if (offset === 0) maybeRefreshInterests(uid);
  const { page, hasMore } = await reelPage(req, seed, offset, limit);
  const ids = page.map((x) => x.id);
  // Layk va obuna holati har sahifada yangidan olinadi
  const prods = ids.length ? await all(`SELECT p.*, (SELECT count(*) FROM product_likes l WHERE l.product_id=p.id)::int AS likes,
      EXISTS(SELECT 1 FROM product_likes l WHERE l.product_id=p.id AND l.user_id=$2) AS liked
    FROM products p WHERE p.id = ANY($1) AND p.active`, [ids, uid]) : [];
  const shopIds = [...new Set(prods.map((p) => p.shop_id))];
  const shops = shopIds.length ? await all(`${SHOP_SQL} WHERE s.id = ANY($1)`, [shopIds]) : [];
  const followed = new Set((shopIds.length ? await all('SELECT shop_id FROM follows WHERE user_id=$1 AND shop_id = ANY($2)', [uid, shopIds]) : []).map((x) => x.shop_id));
  const byP = Object.fromEntries(prods.map((p) => [p.id, p])), byS = Object.fromEntries(shops.map((x) => [x.id, x]));
  const items = page.filter((x) => byP[x.id] && byS[byP[x.id].shop_id]).map((x) => {
    const p = byP[x.id], shop = byS[p.shop_id];
    return {
      product: serializeProduct(p), shop: serializeShop(shop, { following: followed.has(shop.id) }),
      likes: p.likes, liked: p.liked, isNew: Date.now() - new Date(p.created_at).getTime() < 48 * 3600e3, reason: x.reason,
    };
  });
  res.json({ items, hasMore, seed });
}));

r.post('/reels/:id/view', ah(async (req, res) => {
  const ms = Math.max(0, Math.min(600000, Math.round(num(req.body?.ms))));
  const p = await one('SELECT id, shop_id FROM products WHERE id=$1', [req.params.id]);
  if (!p) throw new HttpError(404, 'Mahsulot topilmadi');
  await q('INSERT INTO reel_events(user_id, product_id, dwell_ms) VALUES($1,$2,$3)', [req.user.id, p.id, ms]);
  // 2 soniyadan ko'p ko'rilgan bo'lsa, mahsulot ko'rishlariga ham qo'shiladi (har foydalanuvchi uchun bir marta)
  if (ms >= 2000) {
    const ins = await one('INSERT INTO product_views(product_id, user_id, shop_id) VALUES($1,$2,$3) ON CONFLICT DO NOTHING RETURNING id', [p.id, req.user.id, p.shop_id]);
    if (ins) await q('UPDATE products SET views=views+1 WHERE id=$1', [p.id]);
  }
  // Keyingi kichik bo'lak aynan hozirgi ko'rish signalini hisobga olsin;
  // 5 daqiqalik affinity keshi eski qiziqishni ushlab qolmaydi.
  dropAffinity(req.user.id);
  maybeRefreshInterests(req.user.id);
  res.json({ ok: true });
}));

// ---------- orders ----------
r.post('/orders', ah(async (req, res) => {
  const b = req.body || {};
  const items = Array.isArray(b.items) ? b.items : [];
  if (!items.length) throw new HttpError(400, 'Savat bo\'sh');
  const ids = items.map((i) => str(i.productId));
  const products = await all('SELECT * FROM products WHERE id = ANY($1)', [ids]);
  if (!products.length) throw new HttpError(400, 'Mahsulot topilmadi');
  const shopId = products[0].shop_id;
  if (products.some((p) => p.shop_id !== shopId)) throw new HttpError(400, "Bitta buyurtmada faqat bitta do'kon mahsulotlari bo'lishi mumkin");
  const lines = items.map((i) => {
    const p = products.find((x) => x.id === str(i.productId));
    if (!p) return null;
    return { productId: p.id, name: p.name, price: Number(p.price), qty: Math.max(1, num(i.qty, 1)) };
  }).filter(Boolean);
  const price = lines.reduce((s, l) => s + l.price * l.qty, 0);
  const productName = lines.length === 1 ? lines[0].name : `${lines[0].name} va yana ${lines.length - 1} ta`;
  const id = newId('o_');
  const customer = str(b.customerName).trim() || req.user.name;
  await q(`INSERT INTO orders(id, shop_id, user_id, product_name, price, customer_name, phone, address, lat, lon, items) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)`,
    [id, shopId, req.user.id, productName, price, customer, str(b.phone).trim(), str(b.address).trim(), b.lat ?? null, b.lon ?? null, JSON.stringify(lines)]);
  if (customer && customer !== req.user.name) await q('UPDATE users SET name=$2 WHERE id=$1', [req.user.id, customer.slice(0, 80)]);
  const mapUrl = b.lat != null && b.lon != null ? `https://www.google.com/maps?q=${b.lat},${b.lon}` : null;
  await notifyShop(shopId, 'order', 'Yangi buyurtma', `${customer}: ${productName} — ${price.toLocaleString('ru-RU')} so'm. Tel: ${str(b.phone)}`, { orderId: id, mapUrl, amount: price });
  emit([`shop:${shopId}`], 'order:new', { orderId: id, amount: price });
  dropAffinity(req.user.id);
  maybeRefreshInterests(req.user.id);
  log('Yangi buyurtma', id, shopId, price);
  await assignCourier(id).catch((e) => log('assign xato', e.message));
  const o = await one(`${ORDER_SQL} WHERE o.id=$1`, [id]);
  res.json({ ok: true, order: serializeOrder(o) });
}));

r.get('/my-orders', ah(async (req, res) => {
  const rows = await all(`${ORDER_SQL} WHERE o.user_id=$1 ORDER BY o.created_at DESC LIMIT 100`, [req.user.id]);
  res.json(rows.map(serializeOrder));
}));

// ---------- AI: assistant ----------
const getHistory = (userId, scope, limit = 30) => all('SELECT role, text FROM chat_messages WHERE user_id=$1 AND scope=$2 ORDER BY id DESC LIMIT $3', [userId, scope, limit]).then((rows) => rows.reverse());
const saveMsg = (userId, scope, role, text) => q('INSERT INTO chat_messages(user_id, scope, role, text) VALUES($1,$2,$3,$4)', [userId, scope, role, text]);
const histOut = (rows) => rows.map((m) => ({ role: m.role, content: m.text }));

r.get('/assistant/history', ah(async (req, res) => res.json({ history: histOut(await getHistory(req.user.id, 'assistant', 100)) })));
r.delete('/assistant/history', ah(async (req, res) => { await q("DELETE FROM chat_messages WHERE user_id=$1 AND scope='assistant'", [req.user.id]); res.json({ ok: true }); }));

/** AI javobidan "SHOPS: id1,id2" / "PRODUCTS: ..." qatorini ajratib oladi */
function extractIds(text, key) {
  const re = new RegExp(`^\\s*${key}:\\s*(.*)$`, 'im');
  const m = text.match(re);
  const ids = m ? m[1].split(/[,\s]+/).map((x) => x.replace(/[\[\]]/g, '').trim()).filter(Boolean) : [];
  return { ids, text: text.replace(re, '').replace(/\[(s_|p_)[a-f0-9]+\]/g, '').trim() };
}

r.post('/assistant', ah(async (req, res) => {
  const message = str(req.body?.message).trim();
  if (!message) throw new HttpError(400, 'Xabar bo\'sh');
  const lat = req.body?.lat != null ? Number(req.body.lat) : null, lon = req.body?.lon != null ? Number(req.body.lon) : null;
  const history = await getHistory(req.user.id, 'assistant');
  const shopsRaw = await all(`${SHOP_SQL} WHERE s.active ORDER BY sales DESC LIMIT 60`);
  const shops = shopsRaw.map((s) => serializeShop(s, { distanceKm: lat != null ? distanceKm(lat, lon, s.lat, s.lon) : undefined }));
  const products = (await all(`SELECT p.* FROM products p JOIN shops s ON s.id=p.shop_id WHERE p.active AND s.active ORDER BY p.views DESC LIMIT 400`)).map(serializeProduct);
  const wantCourier = /kuryer|kurer|yetkaz|dostavka|курьер|достав|courier|deliver/i.test(message);
  const wantCargo = /yuk|viloyat|fura|gazel|damas|labo|груз|cargo|shahardan|shaharga/i.test(message);
  const shopsForAi = lat != null ? [...shops].sort((a, b) => (a.distanceKm ?? 1e9) - (b.distanceKm ?? 1e9)) : shops;
  const raw = await assistantReply({
    message: `${message}\n\n(Javob oxirida alohida qatorda tavsiya qilgan do'konlar ID larini "SHOPS: id1, id2" ko'rinishida yoz; tavsiya bo'lmasa "SHOPS: -" yoz. Matn ichida ID larni yozma.)`,
    history, shops: shopsForAi, products, userLoc: lat != null ? { lat, lon } : null,
  });
  const { ids, text } = extractIds(raw, 'SHOPS');
  const picked = ids.map((id) => shops.find((s) => s.id === id)).filter(Boolean).slice(0, 6);
  let couriers = [];
  if (wantCourier) {
    const rows = await all(`SELECT * FROM couriers WHERE active AND type='courier' AND online ORDER BY location_at DESC NULLS LAST LIMIT 20`);
    couriers = rows.map((c) => serializeCourier(c, lat != null ? { distanceKm: distanceKm(lat, lon, c.lat, c.lon) } : {}));
    if (lat != null) couriers.sort((a, b) => (a.distanceKm ?? 1e9) - (b.distanceKm ?? 1e9));
    couriers = couriers.slice(0, 5);
  }
  await saveMsg(req.user.id, 'assistant', 'user', message);
  await saveMsg(req.user.id, 'assistant', 'assistant', text);
  res.json({ text, shops: picked, showMap: picked.filter((s) => s.location).length > 1, couriers, showCouriers: wantCourier, showCargo: wantCargo });
}));

// ---------- AI: shop chat ----------
r.get('/chat/history', ah(async (req, res) => res.json({ history: histOut(await getHistory(req.user.id, `shop:${str(req.query.shopId)}`, 100)) })));
r.delete('/chat/history', ah(async (req, res) => { await q('DELETE FROM chat_messages WHERE user_id=$1 AND scope=$2', [req.user.id, `shop:${str(req.query.shopId)}`]); res.json({ ok: true }); }));

r.post('/chat', ah(async (req, res) => {
  const shopId = str(req.body?.shopId), message = str(req.body?.message).trim(), mode = str(req.body?.mode);
  const shopRow = await getShop(shopId);
  if (!shopRow) throw new HttpError(404, "Do'kon topilmadi");
  const shop = serializeShop(shopRow);
  const products = (await all('SELECT * FROM products WHERE shop_id=$1 AND active ORDER BY views DESC LIMIT 100', [shopId])).map(serializeProduct);
  const scope = `shop:${shopId}`;
  if (mode === 'catalog') {
    const text = products.length ? `Mana bizning mahsulotlarimiz (${products.length} ta):` : "Hozircha mahsulotlar qo'shilmagan.";
    await saveMsg(req.user.id, scope, 'assistant', text);
    return res.json({ text, products: products.slice(0, 20) });
  }
  if (!message) throw new HttpError(400, 'Xabar bo\'sh');
  const history = await getHistory(req.user.id, scope);
  const raw = await shopChatReply({ message: `${message}\n\n(Javob oxirida alohida qatorda tilga olgan mahsulotlar ID larini "PRODUCTS: id1, id2" ko'rinishida yoz; bo'lmasa "PRODUCTS: -". Matn ichida ID yozma.)`, history, shop, products });
  const { ids, text } = extractIds(raw, 'PRODUCTS');
  const picked = ids.map((id) => products.find((p) => p.id === id)).filter(Boolean).slice(0, 6);
  await saveMsg(req.user.id, scope, 'user', message);
  await saveMsg(req.user.id, scope, 'assistant', text);
  res.json({ text, products: picked });
}));

// ---------- seller: products ----------
const positivePrice = (v) => { const n = parsePrice(v); if (n <= 0) throw new HttpError(400, 'Narxni kiriting'); return n; };
const parsePrice = (v) => { const n = Math.round(Number(String(v ?? '').replace(/[^\d.]/g, ''))); if (!Number.isFinite(n) || n < 0) throw new HttpError(400, "Narx noto'g'ri"); return n; };
/** Rasmlarni saqlaydi va har bir yangi rasmning xeshini qaytaradi: { refs, hashes: {ref: sha256} } */
async function storePhotosHashed(list) {
  if (!Array.isArray(list)) return { refs: [], hashes: {} };
  const refs = [], hashes = {};
  for (const p of list.slice(0, 10)) {
    const h = dataUriHash(p);
    const ref = await storeDataUri(p);
    if (ref) { refs.push(ref); if (h) hashes[ref] = h; }
  }
  return { refs, hashes };
}

/** Bitta do'konda bir mahsulot (nomi yoki rasmi bir xil) ikki marta yuklanmasin */
async function assertNotDuplicate(shopId, key, hashes, exceptId = null) {
  // Eski mahsulotlarning nom kalitlari birinchi tekshiruvda to'ldiriladi
  for (const x of await all('SELECT id, name FROM products WHERE shop_id=$1 AND name_key IS NULL', [shopId])) await q('UPDATE products SET name_key=$2 WHERE id=$1', [x.id, nameKey(x.name)]);
  if (key) {
    const d = await one('SELECT name FROM products WHERE shop_id=$1 AND name_key=$2 AND ($3::text IS NULL OR id<>$3) LIMIT 1', [shopId, key, exceptId]);
    if (d) throw new HttpError(409, `Bu mahsulot allaqachon yuklangan: "${d.name}". Uni tahrirlang yoki boshqa nom bering`);
  }
  if (hashes.length) {
    const d = await one(`SELECT name FROM products WHERE shop_id=$1 AND ($3::text IS NULL OR id<>$3)
      AND EXISTS (SELECT 1 FROM jsonb_each_text(photo_hashes) h WHERE h.value = ANY($2::text[])) LIMIT 1`, [shopId, hashes, exceptId]);
    if (d) throw new HttpError(409, `Bu rasm "${d.name}" mahsulotida allaqachon ishlatilgan. Bir mahsulotni ikki marta yuklab bo'lmaydi`);
  }
}

async function storePhotos(list) {
  if (!Array.isArray(list)) return [];
  const out = [];
  for (const p of list.slice(0, 10)) { const ref = await storeDataUri(p); if (ref) out.push(ref); }
  return out;
}

r.get('/seller/products', ah(async (req, res) => {
  const shop = needShop(req);
  res.json((await all('SELECT * FROM products WHERE shop_id=$1 ORDER BY created_at DESC', [shop.id])).map(serializeProduct));
}));

r.post('/seller/products', ah(async (req, res) => {
  const shop = needShop(req);
  const b = req.body || {};
  const name = str(b.name).trim();
  if (!name) throw new HttpError(400, 'Mahsulot nomini kiriting');
  const price = positivePrice(b.price);
  const key = nameKey(name);
  await assertNotDuplicate(shop.id, key, (Array.isArray(b.photos) ? b.photos : []).map(dataUriHash).filter(Boolean));
  const { refs: photos, hashes } = await storePhotosHashed(b.photos);
  if (!photos.length) throw new HttpError(400, 'Kamida 1 ta rasm yuklang');
  const id = newId('p_');
  await q('INSERT INTO products(id, shop_id, name, category, price, description, photos, name_key, photo_hashes) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)',
    [id, shop.id, name, str(b.category) || null, price, str(b.description).trim(), JSON.stringify(photos), key, JSON.stringify(hashes)]);
  dropReelPool();
  // Yangi mahsulot birinchi bo'lib obunachilarga: jonli hodisa va Reels'da oldinga chiqadi
  const fans = await all('SELECT user_id FROM follows WHERE shop_id=$1', [shop.id]);
  if (fans.length) emit(fans.map((f) => `user:${f.user_id}`), 'product:new', { productId: id, shopId: shop.id, shopName: shop.name, name });
  res.json({ product: serializeProduct(await one('SELECT * FROM products WHERE id=$1', [id])) });
}));

r.put('/seller/products/:id', ah(async (req, res) => {
  const shop = needShop(req);
  const p = await one('SELECT * FROM products WHERE id=$1 AND shop_id=$2', [req.params.id, shop.id]);
  if (!p) throw new HttpError(404, 'Mahsulot topilmadi');
  const b = req.body || {};
  const sets = [], vals = [p.id];
  const set = (col, v) => { vals.push(v); sets.push(`${col}=$${vals.length}`); };
  const newName = b.name != null ? str(b.name).trim() : null;
  const incoming = Array.isArray(b.photos) ? b.photos.map(dataUriHash).filter(Boolean) : [];
  const nameChanged = newName && nameKey(newName) !== (p.name_key || nameKey(p.name));
  if (nameChanged || incoming.length) await assertNotDuplicate(shop.id, nameChanged ? nameKey(newName) : null, incoming, p.id);
  if (typeof b.active === 'boolean') set('active', b.active);
  if (b.name != null) { if (!newName) throw new HttpError(400, 'Nom bo\'sh'); set('name', newName); set('name_key', nameKey(newName)); }
  if (b.price != null) set('price', positivePrice(b.price));
  if (b.description != null) set('description', str(b.description).trim());
  if (b.category != null) set('category', str(b.category) || null);
  if (b.photos != null) {
    const { refs, hashes } = await storePhotosHashed(b.photos);
    if (!refs.length) throw new HttpError(400, 'Kamida 1 ta rasm yuklang');
    const old = p.photo_hashes || {};
    const kept = Object.fromEntries(refs.filter((ref) => old[ref]).map((ref) => [ref, old[ref]]));
    set('photos', JSON.stringify(refs));
    set('photo_hashes', JSON.stringify({ ...kept, ...hashes }));
  }
  if (sets.length) await q(`UPDATE products SET ${sets.join(', ')} WHERE id=$1`, vals);
  dropReelPool();
  res.json({ product: serializeProduct(await one('SELECT * FROM products WHERE id=$1', [p.id])) });
}));

r.delete('/seller/products/:id', ah(async (req, res) => {
  const shop = needShop(req);
  await q('DELETE FROM products WHERE id=$1 AND shop_id=$2', [req.params.id, shop.id]);
  dropReelPool();
  res.json({ ok: true });
}));

// ---------- seller: orders / badges / notifications ----------
r.get('/seller/orders', ah(async (req, res) => {
  const shop = needShop(req);
  res.json((await all(`${ORDER_SQL} WHERE o.shop_id=$1 AND NOT o.archived ORDER BY o.created_at DESC LIMIT 300`, [shop.id])).map(serializeOrder));
}));

r.patch('/seller/orders/:id', ah(async (req, res) => {
  const shop = needShop(req);
  const status = str(req.body?.status);
  if (!['done', 'cancelled'].includes(status)) throw new HttpError(400, "Status noto'g'ri");
  const cur = await one('SELECT * FROM orders WHERE id=$1 AND shop_id=$2', [req.params.id, shop.id]);
  if (!cur) throw new HttpError(404, 'Buyurtma topilmadi');
  if (cur.status !== 'new') throw new HttpError(409, cur.status === 'done' ? 'Buyurtma allaqachon bajarilgan' : 'Buyurtma allaqachon bekor qilingan');
  // Bekor qilinsa, hali yetkazilmagan buyurtmadan kuryer ozod qilinadi
  const o = await one(`UPDATE orders SET status=$3::text,
      courier_id = CASE WHEN $3::text='cancelled' AND coalesce(delivery_status,'')<>'delivered' THEN NULL ELSE courier_id END,
      delivery_status = CASE WHEN $3::text='cancelled' AND coalesce(delivery_status,'')<>'delivered' THEN NULL ELSE delivery_status END
    WHERE id=$1 AND shop_id=$2 AND status='new' RETURNING *`, [cur.id, shop.id, status]);
  if (!o) throw new HttpError(409, "Buyurtma holati o'zgargan, ro'yxatni yangilang");
  emit([`shop:${shop.id}`, o.user_id ? `user:${o.user_id}` : null, cur.courier_id ? `courier:${cur.courier_id}` : null], 'order:update', { orderId: o.id, status });
  if (status === 'done') emit([`shop:${shop.id}`], 'money', { orderId: o.id, amount: Number(o.price) });
  res.json({ ok: true });
}));

r.get('/seller/badges', ah(async (req, res) => {
  const shop = needShop(req);
  const a = await one(`SELECT (SELECT count(*) FROM orders WHERE shop_id=$1 AND status='new' AND NOT archived)::int AS "newOrders", (SELECT count(*) FROM notifications WHERE shop_id=$1 AND NOT read)::int AS unread`, [shop.id]);
  res.json(a);
}));

r.get('/seller/notifications', ah(async (req, res) => {
  const shop = needShop(req);
  const rows = await all('SELECT * FROM notifications WHERE shop_id=$1 ORDER BY created_at DESC LIMIT 100', [shop.id]);
  if (req.query.read === '1') await q('UPDATE notifications SET read=true WHERE shop_id=$1 AND NOT read', [shop.id]);
  res.json(rows.map((n) => ({ id: n.id, type: n.type, title: n.title, text: n.text, read: n.read, createdAt: n.created_at, meta: n.meta })));
}));
r.delete('/seller/notifications', ah(async (req, res) => {
  const shop = needShop(req);
  await q('DELETE FROM notifications WHERE shop_id=$1', [shop.id]);
  res.json({ ok: true });
}));

// ---------- seller: shop profile ----------
r.put('/seller/shop', ah(async (req, res) => {
  const shop = needShop(req);
  const b = req.body || {};
  const sets = [], vals = [shop.id];
  const set = (col, v) => { vals.push(v); sets.push(`${col}=$${vals.length}`); };
  if (b.logo != null) set('logo', await storeDataUri(b.logo));
  if (b.name != null) { const n = str(b.name).trim(); if (!n) throw new HttpError(400, "Do'kon nomi bo'sh"); set('name', n); }
  if (b.sellerName != null) set('seller_name', str(b.sellerName).trim());
  if (b.ownerName != null) set('owner_name', str(b.ownerName).trim());
  if (b.phone != null) set('phone', str(b.phone).trim());
  if (b.description != null) set('description', str(b.description).trim());
  if ('location' in b) {
    const l = b.location;
    if (l && l.lat != null && l.lon != null) { set('lat', Number(l.lat)); set('lon', Number(l.lon)); set('address', str(l.address).trim() || null); }
    else { set('lat', null); set('lon', null); set('address', null); }
  }
  if (sets.length) await q(`UPDATE shops SET ${sets.join(', ')} WHERE id=$1`, vals);
  res.json({ shop: serializeShop(await getShop(shop.id)) });
}));

// ---------- seller: analytics ----------
const WD = ['Yak', 'Dush', 'Sesh', 'Chor', 'Pay', 'Jum', 'Shan'];
const HOUR_BLOCKS = [['Tong (6–10)', 6, 10], ['Kunduz (10–14)', 10, 14], ['Tushdan keyin (14–18)', 14, 18], ['Kechqurun (18–22)', 18, 22], ['Tun (22–6)', 22, 30]];

async function buildAnalytics(shop) {
  const sid = shop.id;
  const base = `FROM orders WHERE shop_id=$1 AND NOT archived`;
  const st = await one(`SELECT count(*)::int AS "totalOrders", count(*) FILTER (WHERE status='new')::int AS "newOrders",
    coalesce(sum(price) FILTER (WHERE status='done'),0)::bigint AS revenue, count(DISTINCT coalesce(nullif(phone,''), nullif(customer_name,''), id))::int AS customers,
    coalesce(avg(price) FILTER (WHERE status='done'),0)::bigint AS "avgCheck",
    count(*) FILTER (WHERE status='done')::int AS done, count(*) FILTER (WHERE status='cancelled')::int AS cancelled,
    count(*) FILTER (WHERE created_at >= now() - interval '7 day')::int AS week,
    count(*) FILTER (WHERE created_at >= now() - interval '14 day' AND created_at < now() - interval '7 day')::int AS prev ${base}`, [sid]);
  const units = await one(`SELECT coalesce(sum((i->>'qty')::int),0)::int AS n FROM orders o, jsonb_array_elements(o.items) i WHERE o.shop_id=$1 AND NOT o.archived AND o.status='done'`, [sid]);
  const views = (await one('SELECT coalesce(sum(views),0)::int AS v FROM products WHERE shop_id=$1', [sid])).v;
  const months = await all(`SELECT to_char(date_trunc('month', created_at),'YYYY-MM') AS month, count(*)::int AS total, count(*) FILTER (WHERE status='done')::int AS done,
    count(*) FILTER (WHERE status='cancelled')::int AS cancelled, count(*) FILTER (WHERE status='new')::int AS new, coalesce(sum(price) FILTER (WHERE status='done'),0)::bigint AS "sumDone"
    ${base} GROUP BY 1 ORDER BY 1 DESC LIMIT 2`, [sid]);
  const thisKey = new Date().toISOString().slice(0, 7);
  const tm = months.find((m) => m.month === thisKey) || { month: thisKey, total: 0, done: 0, cancelled: 0, new: 0, sumDone: 0 };
  const pm = months.find((m) => m.month !== thisKey) || null;
  const byDayN = (days) => all(`WITH d AS (SELECT generate_series((now() - ($2::int - 1) * interval '1 day')::date, now()::date, interval '1 day')::date AS dt)
    SELECT to_char(d.dt,'YYYY-MM-DD') AS date, (SELECT count(*) FROM orders WHERE shop_id=$1 AND NOT archived AND created_at::date=d.dt)::int AS n,
    (SELECT coalesce(sum(price),0) FROM orders WHERE shop_id=$1 AND NOT archived AND status='done' AND created_at::date=d.dt)::bigint AS sum FROM d ORDER BY d.dt`, [sid, days])
    .then((rows) => rows.map((x) => ({ ...x, sum: Number(x.sum) })));
  const topSold = (await all(`SELECT i->>'name' AS name, sum((i->>'qty')::int)::int AS qty, count(DISTINCT o.id)::int AS orders, sum((i->>'qty')::int * (i->>'price')::bigint)::bigint AS sum
    FROM orders o, jsonb_array_elements(o.items) i WHERE o.shop_id=$1 AND NOT o.archived AND o.status='done' GROUP BY 1 ORDER BY qty DESC LIMIT 5`, [sid])).map((x) => ({ ...x, sum: Number(x.sum) }));
  const customers = (await all(`SELECT customer_name AS name, phone, count(*)::int AS orders, coalesce(sum(price) FILTER (WHERE status='done'),0)::bigint AS sum, max(created_at) AS last ${base} GROUP BY 1,2 ORDER BY orders DESC, sum DESC LIMIT 5`, [sid])).map((x) => ({ ...x, sum: Number(x.sum) }));
  const recent = (await all(`SELECT product_name AS "productName", customer_name AS "customerName", created_at AS "createdAt", price::bigint AS price, status ${base} ORDER BY created_at DESC LIMIT 5`, [sid])).map((x) => ({ ...x, price: Number(x.price) }));
  const hours = new Array(24).fill(0);
  for (const x of await all(`SELECT extract(hour from created_at AT TIME ZONE 'Asia/Tashkent')::int AS h, count(*)::int AS n ${base} GROUP BY 1`, [sid])) hours[x.h] = x.n;
  const hourBlocks = HOUR_BLOCKS.map(([label, a, b]) => ({ label, n: hours.reduce((s, n, h) => (h >= a && h < b) || (b > 24 && h < b - 24) ? s + n : s, 0) }));
  const wd = new Array(7).fill(0);
  for (const x of await all(`SELECT extract(dow from created_at AT TIME ZONE 'Asia/Tashkent')::int AS d, count(*)::int AS n ${base} GROUP BY 1`, [sid])) wd[x.d] = x.n;
  const byWeekday = [1, 2, 3, 4, 5, 6, 0].map((d) => ({ label: WD[d], n: wd[d] }));
  const peakN = Math.max(...hours), bestWd = byWeekday.reduce((a, b) => (b.n > a.n ? b : a), byWeekday[0]);
  const prods = await all('SELECT * FROM products WHERE shop_id=$1', [sid]);
  const soldNames = new Set(topSold.map((t) => t.name));
  const soldAll = new Set((await all(`SELECT DISTINCT i->>'name' AS name FROM orders o, jsonb_array_elements(o.items) i WHERE o.shop_id=$1 AND NOT o.archived`, [sid])).map((x) => x.name));
  const top = prods.filter((p) => p.views > 0).sort((a, b) => b.views - a.views).slice(0, 5).map(serializeProduct);
  const unsold = prods.filter((p) => !soldAll.has(p.name) && !soldNames.has(p.name)).slice(0, 5).map(serializeProduct);
  const tips = [];
  if (st.newOrders > 0) tips.push({ type: 'warning', title: `${st.newOrders} ta yangi buyurtma`, text: 'Yangi buyurtmalarni tezroq tasdiqlang yoki bekor qiling.' });
  if (prods.length < 5) tips.push({ type: 'idea', title: 'Katalogni to\'ldiring', text: "Kamida 5–10 ta mahsulot qo'shing, xaridorlar tanlovi ko'proq bo'lsin." });
  if (!shop.lat) tips.push({ type: 'idea', title: 'Joylashuv yo\'q', text: "Do'kon joylashuvini belgilang — AI yordamchi yaqin xaridorlarga sizni tavsiya qiladi." });
  if (unsold.length) tips.push({ type: 'idea', title: 'Sotilmagan mahsulotlar', text: `${unsold.length} ta mahsulot hali sotilmagan. Narx yoki rasmni yangilab ko'ring.` });
  if (st.done > 0 && st.cancelled / Math.max(1, st.done + st.cancelled) > 0.3) tips.push({ type: 'warning', title: 'Bekor qilishlar ko\'p', text: 'Bekor qilingan buyurtmalar ulushi 30% dan oshdi. Mavjudlik va narxni tekshiring.' });
  if (st.done >= 10) tips.push({ type: 'success', title: 'Yaxshi ketyapsiz', text: `${st.done} ta buyurtma bajarildi. Davom eting!` });
  return {
    stats: { totalOrders: st.totalOrders, newOrders: st.newOrders, revenue: Number(st.revenue), customers: st.customers, unitsSold: units.n, avgCheck: Number(st.avgCheck), views, conversion: views > 0 ? Math.round((st.totalOrders / views) * 1000) / 10 : 0 },
    week: { n: st.week }, prev: { n: st.prev },
    thisMonth: { ...tm, sumDone: Number(tm.sumDone) }, prevMonth: pm ? { ...pm, sumDone: Number(pm.sumDone) } : null,
    byDay: await byDayN(7), byDay30: await byDayN(30),
    topSold, customers, recent,
    status: { done: st.done, new: st.newOrders, cancelled: st.cancelled, sums: { done: Number(st.revenue) } },
    hourBlocks, byWeekday, peakHour: peakN > 0 ? { h: hours.indexOf(peakN) } : null, bestWeekday: bestWd.n > 0 ? { label: bestWd.label } : null,
    top, unsold, tips,
  };
}

r.get('/seller/analytics', ah(async (req, res) => res.json(await buildAnalytics(needShop(req)))));

// Instagram-uslubidagi sotuvchi profili uchun auditoriya va post statistikasi.
// Email/telefon kabi shaxsiy ma'lumotlar qaytarilmaydi — faqat obunachining
// profil nomi va shu do'kondagi faolligi ko'rinadi.
r.get('/seller/audience', ah(async (req, res) => {
  const shop = needShop(req);
  const sid = shop.id;
  const limit = Math.min(100, Math.max(1, Math.floor(num(req.query.limit, 50))));
  const [summary, followers, products] = await Promise.all([
    one(`SELECT
      (SELECT count(*) FROM follows WHERE shop_id=$1)::int AS followers,
      (SELECT count(DISTINCT user_id) FROM product_views WHERE shop_id=$1)::int AS reach,
      (SELECT count(*) FROM product_likes l JOIN products p ON p.id=l.product_id WHERE p.shop_id=$1)::int AS likes,
      (SELECT count(*) FROM orders WHERE shop_id=$1 AND NOT archived)::int AS orders,
      (SELECT coalesce(sum(price) FILTER (WHERE status='done'),0)::bigint FROM orders WHERE shop_id=$1 AND NOT archived) AS revenue,
      (SELECT count(*) FROM follows f
        WHERE f.shop_id=$1 AND (
          EXISTS(SELECT 1 FROM product_views v WHERE v.user_id=f.user_id AND v.shop_id=$1)
          OR EXISTS(SELECT 1 FROM product_likes l JOIN products p ON p.id=l.product_id WHERE l.user_id=f.user_id AND p.shop_id=$1)
        ))::int AS "engagedFollowers"`, [sid]),
    all(`SELECT u.id,
        coalesce(nullif(trim(concat_ws(' ', u.first_name, u.last_name)), ''), nullif(u.name, ''), 'Xaridor') AS name,
        f.created_at AS "joinedAt",
        (SELECT count(*) FROM product_views v WHERE v.user_id=u.id AND v.shop_id=$1)::int AS views,
        (SELECT count(*) FROM product_likes l JOIN products p ON p.id=l.product_id WHERE l.user_id=u.id AND p.shop_id=$1)::int AS likes,
        (SELECT count(*) FROM orders o WHERE o.user_id=u.id AND o.shop_id=$1 AND NOT o.archived)::int AS orders,
        (SELECT p.name FROM product_views v JOIN products p ON p.id=v.product_id
          WHERE v.user_id=u.id AND v.shop_id=$1 ORDER BY v.created_at DESC LIMIT 1) AS "lastProduct"
      FROM follows f JOIN users u ON u.id=f.user_id
      WHERE f.shop_id=$1 ORDER BY f.created_at DESC LIMIT $2`, [sid, limit]),
    all(`SELECT p.id, p.name, p.photos, p.active, p.created_at AS "createdAt",
        (SELECT count(*) FROM product_views v WHERE v.product_id=p.id)::int AS views,
        (SELECT count(*) FROM product_views v JOIN follows f ON f.user_id=v.user_id
          WHERE v.product_id=p.id AND f.shop_id=$1)::int AS "followerViews",
        (SELECT count(*) FROM product_likes l WHERE l.product_id=p.id)::int AS likes,
        (SELECT coalesce(sum((i->>'qty')::int),0)::int
          FROM orders o CROSS JOIN LATERAL jsonb_array_elements(o.items) i
          WHERE o.shop_id=$1 AND NOT o.archived AND o.status='done' AND i->>'productId'=p.id) AS sold,
        (SELECT coalesce(sum((i->>'qty')::bigint * (i->>'price')::bigint),0)::bigint
          FROM orders o CROSS JOIN LATERAL jsonb_array_elements(o.items) i
          WHERE o.shop_id=$1 AND NOT o.archived AND o.status='done' AND i->>'productId'=p.id) AS revenue
      FROM products p WHERE p.shop_id=$1
      ORDER BY views DESC, likes DESC, p.created_at DESC LIMIT 60`, [sid]),
  ]);
  res.json({
    summary: { ...summary, revenue: Number(summary.revenue || 0) },
    followers,
    products: products.map((p) => ({ ...p, photo: p.photos?.[0] || null, revenue: Number(p.revenue || 0) })),
  });
}));

/** Analitika bo'yicha AI xulosa (6 soat keshlanadi, ?refresh=1 yangilaydi) */
r.get('/seller/analytics/ai-summary', ah(async (req, res) => {
  const shop = needShop(req);
  const cached = await one('SELECT * FROM shop_ai_summary WHERE shop_id=$1', [shop.id]);
  if (cached && req.query.refresh !== '1' && Date.now() - new Date(cached.updated_at).getTime() < 6 * 3600e3) return res.json({ ...cached.data, generatedAt: cached.updated_at });
  const data = await sellerAiSummary({ shop, analytics: await buildAnalytics(shop) });
  const row = await one(`INSERT INTO shop_ai_summary(shop_id, data, updated_at) VALUES($1,$2,now())
    ON CONFLICT (shop_id) DO UPDATE SET data=$2, updated_at=now() RETURNING updated_at`, [shop.id, JSON.stringify(data)]);
  res.json({ ...data, generatedAt: row.updated_at });
}));

r.get('/seller/advice', ah(async (req, res) => {
  const shop = needShop(req);
  const cached = await one('SELECT * FROM shop_advice WHERE shop_id=$1', [shop.id]);
  if (cached && req.query.refresh !== '1' && Date.now() - new Date(cached.updated_at).getTime() < 24 * 3600e3) return res.json({ tips: cached.tips });
  const a = await buildAnalytics(shop);
  const tips = await sellerAdvice({ shop: serializeShop(shop), stats: { ...a.stats, thisMonth: a.thisMonth, status: a.status, topSold: a.topSold, unsoldCount: a.unsold.length, productCount: shop.product_count, hasLocation: shop.lat != null } });
  await q('INSERT INTO shop_advice(shop_id, tips, updated_at) VALUES($1,$2,now()) ON CONFLICT (shop_id) DO UPDATE SET tips=$2, updated_at=now()', [shop.id, JSON.stringify(tips)]);
  res.json({ tips });
}));

// ---------- seller: report (HTML) ----------
const reports = new Map();
r.post('/seller/report', ah(async (req, res) => {
  const shop = needShop(req);
  const key = newToken();
  reports.set(key, { shopId: shop.id, exp: Date.now() + 3600e3 });
  for (const [k, v] of reports) if (v.exp < Date.now()) reports.delete(k);
  res.json({ sent: false, url: `/api/report/${key}` });
}));

r.use('/courier', courierRouter);
r.use(courierRouter.publicRoutes);

export default r;

/** Hisobot sahifasi (token bilan, auth talab qilmaydi) — server.js dan ulanadi */
export const reportHandler = ah(async (req, res) => {
  const rep = reports.get(req.params.key);
  if (!rep || rep.exp < Date.now()) throw new HttpError(404, 'Hisobot muddati tugagan');
  const shop = await getShop(rep.shopId);
  const a = await buildAnalytics(shop);
  const cached = await one('SELECT data FROM shop_ai_summary WHERE shop_id=$1', [shop.id]);
  const ai = cached?.data?.summary ? cached.data : await sellerAiSummary({ shop, analytics: a });
  const f = (n) => Number(n || 0).toLocaleString('ru-RU').replace(/,/g, ' ');
  const esc = (v) => String(v ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const table = (head, list, cols) => (list?.length
    ? `<table><tr>${head.map((h) => `<th>${esc(h)}</th>`).join('')}</tr>${list.map((x) => `<tr>${cols.map((c) => `<td>${esc(typeof c === 'function' ? c(x) : x[c])}</td>`).join('')}</tr>`).join('')}</table>`
    : `<p class="empty">Ma'lumot yo'q</p>`);
  const days = a.byDay30 || [];
  const maxN = Math.max(1, ...days.map((d) => d.n));
  const W = 720, H = 190, bw = W / Math.max(1, days.length);
  const bars = days.map((d, i) => {
    const h = Math.round((d.n / maxN) * (H - 40));
    const x = (i * bw + 2).toFixed(1);
    return `<rect x="${x}" y="${H - 22 - h}" width="${(bw - 4).toFixed(1)}" height="${Math.max(h, 1)}" rx="3" fill="${d.n ? '#F5B301' : '#EEE'}"><title>${d.date}: ${d.n} ta, ${f(d.sum)} so'm</title></rect>`
      + (d.n ? `<text x="${(i * bw + bw / 2).toFixed(1)}" y="${H - 26 - h}" font-size="10" text-anchor="middle" fill="#555">${d.n}</text>` : '')
      + (i % 5 === 0 || i === days.length - 1 ? `<text x="${(i * bw + bw / 2).toFixed(1)}" y="${H - 6}" font-size="10" text-anchor="middle" fill="#888">${d.date.slice(8)}.${d.date.slice(5, 7)}</text>` : '');
  }).join('');
  const st = a.status || {};
  const totalSt = Math.max(1, (st.done || 0) + (st.new || 0) + (st.cancelled || 0));
  const pct = (n) => Math.round(((n || 0) / totalSt) * 100);
  const hl = { good: ['#E7F7EE', '#1E8E4E', '✓'], warn: ['#FFF4DE', '#A86F00', '!'], idea: ['#EFEAFF', '#6B4FD8', '★'] };
  const month30 = days.reduce((acc, d) => ({ n: acc.n + d.n, sum: acc.sum + d.sum }), { n: 0, sum: 0 });
  res.set('Content-Type', 'text/html; charset=utf-8').send(`<!doctype html><html lang="uz"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(shop.name)} — savdo hisoboti</title>
<style>
*{box-sizing:border-box}body{font-family:-apple-system,system-ui,"Segoe UI",Roboto,sans-serif;margin:0;background:#F4F3EF;color:#15171A}
.wrap{max-width:860px;margin:0 auto;padding:24px 18px 48px}
.top{display:flex;justify-content:space-between;gap:12px;align-items:flex-start;flex-wrap:wrap}
h1{margin:0;font-size:26px;letter-spacing:-.4px}.muted{color:#6B6F76;font-size:13px}
.btn{background:#15171A;color:#fff;border:0;border-radius:12px;padding:11px 16px;font-weight:700;font-size:14px;cursor:pointer}
.card{background:#fff;border-radius:18px;padding:16px 18px;margin-top:14px;box-shadow:0 8px 24px rgba(20,22,26,.05)}
h2{font-size:16px;margin:0 0 10px}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:10px;margin-top:14px}
.kpi{background:#fff;border-radius:16px;padding:14px;box-shadow:0 8px 24px rgba(20,22,26,.05)}.kpi span{font-size:12px;color:#6B6F76}.kpi b{display:block;font-size:21px;margin-top:4px;letter-spacing:-.3px}
.ai{background:#15171A;color:#fff}.ai p{margin:0 0 10px;line-height:1.55;color:#E8E9EB}.tag{font-size:11px;font-weight:700;letter-spacing:.6px;color:#F5B301}
.hl{display:flex;gap:10px;align-items:flex-start;padding:8px 10px;border-radius:12px;margin-top:6px;font-size:14px;line-height:1.45}.hl i{font-style:normal;font-weight:800;width:18px;text-align:center}
.bar{height:10px;border-radius:6px;background:#EEE;overflow:hidden;display:flex}.bar div{height:100%}
.legend{display:flex;gap:14px;flex-wrap:wrap;font-size:13px;margin-top:8px}.dot{display:inline-block;width:9px;height:9px;border-radius:50%;margin-right:5px}
table{border-collapse:collapse;width:100%}td,th{border-bottom:1px solid #EFEFEF;padding:8px 6px;text-align:left;font-size:13.5px}th{color:#6B6F76;font-weight:600;font-size:12px}
.empty{color:#9A9DA3;font-size:13px;margin:4px 0}.cols{display:grid;grid-template-columns:1fr 1fr;gap:14px}@media(max-width:640px){.cols{grid-template-columns:1fr}}
@media print{body{background:#fff}.btn{display:none}.card,.kpi{box-shadow:none;border:1px solid #E6E6E6}.ai{background:#fff;color:#15171A}.ai p{color:#15171A}}
</style></head><body><div class="wrap">
<div class="top"><div><h1>${esc(shop.name)}</h1><div class="muted">Savdo hisoboti · ${new Date().toLocaleString('ru-RU', { timeZone: 'Asia/Tashkent' })} · Daraja: ${esc(shopLevel(shop.sales))}</div></div>
<button class="btn" onclick="print()">PDF sifatida saqlash</button></div>
<div class="grid">
<div class="kpi"><span>Daromad</span><b>${f(a.stats.revenue)} so'm</b></div>
<div class="kpi"><span>Jami buyurtma</span><b>${a.stats.totalOrders}</b></div>
<div class="kpi"><span>30 kunda</span><b>${month30.n} ta · ${f(month30.sum)}</b></div>
<div class="kpi"><span>O'rtacha chek</span><b>${f(a.stats.avgCheck)} so'm</b></div>
<div class="kpi"><span>Mijozlar</span><b>${a.stats.customers}</b></div>
<div class="kpi"><span>Ko'rishlar · konversiya</span><b>${f(a.stats.views)} · ${a.stats.conversion}%</b></div>
</div>
<div class="card ai"><div class="tag">AI XULOSA</div><p style="margin-top:8px">${esc(ai.summary)}</p>
${(ai.highlights || []).map((h) => { const [bg, fg, ic] = hl[h.type] || hl.idea; return `<div class="hl" style="background:${bg};color:${fg}"><i>${ic}</i><span>${esc(h.text)}</span></div>`; }).join('')}</div>
<div class="card"><h2>Oxirgi 30 kun: buyurtmalar</h2><svg viewBox="0 0 ${W} ${H}" width="100%" role="img" aria-label="30 kunlik buyurtmalar">${bars}</svg></div>
<div class="card"><h2>Buyurtma holatlari</h2>
<div class="bar"><div style="width:${pct(st.done)}%;background:#1E8E4E"></div><div style="width:${pct(st.new)}%;background:#F5B301"></div><div style="width:${pct(st.cancelled)}%;background:#D64545"></div></div>
<div class="legend"><span><i class="dot" style="background:#1E8E4E"></i>Bajarildi: ${st.done || 0}</span><span><i class="dot" style="background:#F5B301"></i>Yangi: ${st.new || 0}</span><span><i class="dot" style="background:#D64545"></i>Bekor: ${st.cancelled || 0}</span>
${a.peakHour ? `<span>Eng faol soat: ${esc(a.peakHour.h)}:00</span>` : ''}${a.bestWeekday ? `<span>Eng yaxshi kun: ${esc(a.bestWeekday.label)}</span>` : ''}</div></div>
<div class="cols">
<div class="card"><h2>Eng ko'p sotilgan</h2>${table(['Mahsulot', 'Dona', 'Summa'], a.topSold, ['name', 'qty', (x) => `${f(x.sum)} so'm`])}</div>
<div class="card"><h2>Faol mijozlar</h2>${table(['Mijoz', 'Buyurtma', 'Summa'], a.customers, [(x) => x.name || x.phone || '—', 'orders', (x) => `${f(x.sum)} so'm`])}</div>
<div class="card"><h2>Eng ko'p ko'rilgan</h2>${table(['Mahsulot', "Ko'rish", 'Narx'], a.top, ['name', 'views', (x) => `${f(x.price)} so'm`])}</div>
<div class="card"><h2>Hali sotilmagan</h2>${table(['Mahsulot', "Ko'rish", 'Narx'], a.unsold, ['name', 'views', (x) => `${f(x.price)} so'm`])}</div>
</div>
<div class="card"><h2>Oxirgi buyurtmalar</h2>${table(['Sana', 'Mijoz', 'Mahsulot', 'Summa', 'Holat'], a.recent, [(x) => new Date(x.createdAt || x.created_at).toLocaleDateString('ru-RU'), (x) => x.customerName || x.customer_name || '—', (x) => x.productName || x.product_name || '—', (x) => `${f(x.price)} so'm`, (x) => ({ new: 'Yangi', done: 'Bajarildi', cancelled: 'Bekor' }[x.status] || x.status)])}</div>
<div class="card"><h2>Tavsiyalar</h2>${(a.tips || []).length ? `<ul style="margin:0;padding-left:18px;line-height:1.6">${a.tips.map((t) => `<li><b>${esc(t.title)}</b>: ${esc(t.text)}</li>`).join('')}</ul>` : `<p class="empty">Tavsiya yo'q</p>`}</div>
<p class="muted" style="margin-top:18px">Rydex tomonidan tayyorlandi.</p>
</div></body></html>`);
});
