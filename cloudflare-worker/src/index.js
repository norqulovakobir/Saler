import {
  HttpError, REGIONS, all, body, bool, checkCode, checkPassword, cleanPhotoRefs, consumeCode, cors, distanceKm, escapeHtml,
  hashPassword, json, loadContext, mediaResponse, needBuyer, needCourier, needEmail, needLogin, needPassword,
  needPhone, needShop, needTelegram, newId, newToken, notifyShop, now, num, one, parseJson, parseList, personName,
  publicUser, regionRouteKm, run, sendCode, serializeCargo, serializeCourier, serializeOrder, serializeProduct,
  isMediaRef,
  r2Enabled, serializeShop, shopWithStats, storeDataUri, storeImageBytes, str, tariffPrice,
} from './lib.js';
import { nudgeOfflineCouriers, push, pushEnabled, registerToken, unregisterToken } from './push.js';

const SHOP_STATS = `SELECT s.*,
  (SELECT COUNT(*) FROM products p WHERE p.shop_id=s.id AND p.active=1) AS product_count,
  (SELECT COUNT(*) FROM orders o WHERE o.shop_id=s.id AND o.status='done' AND o.archived=0) AS sales,
  (SELECT COUNT(*) FROM follows f WHERE f.shop_id=s.id) AS followers
  FROM shops s`;

const ORDER_SELECT = `SELECT o.*, s.name AS shop_name, s.phone AS shop_phone, s.lat AS shop_lat, s.lon AS shop_lon,
  s.address AS shop_address, c.name AS courier_name, c.phone AS courier_phone,
  c.photo AS courier_photo, c.car_photo AS courier_car_photo, c.plate AS courier_plate
  FROM orders o JOIN shops s ON s.id=o.shop_id LEFT JOIN couriers c ON c.id=o.courier_id`;

const CARGO_SELECT = `SELECT x.*, c.name AS carrier_name, c.phone AS carrier_phone,
  c.photo AS carrier_photo, c.car_photo AS carrier_car_photo, c.plate AS carrier_plate,
  c.base_price AS carrier_base, c.price_per_km AS carrier_per_km
  FROM cargo_orders x LEFT JOIN couriers c ON c.id=x.carrier_id`;

const VEHICLES = ['foot', 'bike', 'moto', 'car'];
const VEHICLE_TYPES = ['labo', 'damas', 'gazel', 'isuzu', 'fura'];

function limitOf(value, fallback, max) {
  return Math.min(max, Math.max(1, Math.floor(num(value, fallback))));
}

function escapedLike(value) {
  return '%' + str(value).trim().replace(/[\%_]/g, '\\$&') + '%';
}

function locationOf(value, { required = false } = {}) {
  const source = value && typeof value === 'object' ? value : {};
  const lat = Number(source.lat);
  const lon = Number(source.lon);
  if (!Number.isFinite(lat) || !Number.isFinite(lon) || Math.abs(lat) > 90 || Math.abs(lon) > 180) {
    if (required) throw new HttpError(400, "Do'kon joylashuvini xaritada belgilang", { field: 'location' });
    return null;
  }
  return { lat, lon, address: str(source.address).trim().slice(0, 200) };
}

function orderKm(order) {
  const direct = distanceKm(order.shop_lat, order.shop_lon, order.lat, order.lon);
  return direct == null ? null : Math.round(direct * 1.3 * 10) / 10;
}

function parsePrice(value) {
  const price = Math.round(Number(str(value).replace(/[^\d.]/g, '')));
  if (!Number.isFinite(price) || price < 0) throw new HttpError(400, "Narx noto'g'ri", { field: 'price' });
  return price;
}

function positivePrice(value) {
  const price = parsePrice(value);
  if (price <= 0) throw new HttpError(400, 'Narxni kiriting', { field: 'price' });
  return price;
}

async function getShop(env, id) {
  return one(env, SHOP_STATS + ' WHERE s.id=?', [id]);
}

async function shopFollowInfo(env, shopId, userId) {
  const row = await one(env, `SELECT
    (SELECT COUNT(*) FROM follows WHERE shop_id=?) AS followers,
    EXISTS(SELECT 1 FROM follows WHERE shop_id=? AND user_id=?) AS following`, [shopId, shopId, userId]);
  return { followers: num(row && row.followers), following: bool(row && row.following) };
}

async function productLikeInfo(env, productId, userId) {
  const row = await one(env, `SELECT
    (SELECT COUNT(*) FROM product_likes WHERE product_id=?) AS likes,
    EXISTS(SELECT 1 FROM product_likes WHERE product_id=? AND user_id=?) AS liked`, [productId, productId, userId]);
  return { likes: num(row && row.likes), liked: bool(row && row.liked) };
}

async function authGuest(env, input) {
  const name = str(input.name, 'Xaridor').trim().slice(0, 80) || 'Xaridor';
  const stamp = now();
  const user = await one(env, 'INSERT INTO users(name, last_seen, created_at) VALUES(?,?,?) RETURNING *', [name, stamp, stamp]);
  const token = newToken();
  await run(env, 'INSERT INTO sessions(token, user_id, created_at, updated_at) VALUES(?,?,?,?)', [token, user.id, stamp, stamp]);
  return { token, user: { id: user.id, name: user.name } };
}

/// Kuniga bir marta ishlaydi. Faol bo'lmagan mehmon yozuvlari cheksiz
/// ko'paymasligi uchun faqat 45 kundan eski, hech qanday buyurtmaga ega
/// bo'lmagan guest hisoblari tozalanadi. R2 obyektlari o'z lifecycle qoidasi
/// orqali boshqariladi; bu yerda faqat D1 metadata o'chadi.
async function cleanupStaleGuestData(env) {
  const guestCutoff = new Date(Date.now() - 45 * 24 * 60 * 60 * 1000).toISOString();
  const mediaCutoff = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
  const tasks = [
    run(env, 'DELETE FROM media_uploads WHERE created_at<?', [mediaCutoff]),
    run(env, `DELETE FROM users
      WHERE registered_at IS NULL
        AND COALESCE(last_seen, created_at)<?
        AND NOT EXISTS (SELECT 1 FROM orders WHERE orders.user_id=users.id)`, [guestCutoff]),
  ];
  const results = await Promise.allSettled(tasks);
  for (const result of results) {
    if (result.status === 'rejected') console.warn('Guest cleanup failed', result.reason);
  }
}

const MAX_DIRECT_IMAGE_BYTES = 4 * 1024 * 1024;

/// Hozir qaysi ombor ishlayotgani: media_uploads jadvali va /api/health uchun.
/// R2 binding yo'qolsa 'off' — yuklash storeImageBytes'da 503 bilan to'xtaydi.
const mediaStoreName = (env) => (r2Enabled(env) ? 'r2' : 'off');

async function takeMediaQuota(env, context, bytes) {
  const privileged = Boolean(context.user.registered_at || context.shop || context.courier);
  const maxFiles = privileged ? 60 : 6;
  const maxBytes = privileged ? 30 * 1024 * 1024 : 4 * 1024 * 1024;
  const cutoff = new Date(Date.now() - 60 * 60 * 1000).toISOString();
  const used = await one(env, `SELECT COUNT(*) AS files, COALESCE(SUM(bytes),0) AS bytes
    FROM media_uploads WHERE user_id=? AND created_at>=?`, [context.user.id, cutoff]);
  if (num(used && used.files) >= maxFiles || num(used && used.bytes) + bytes > maxBytes) {
    throw new HttpError(429, "Rasm yuklash limiti tugadi. Bir soatdan keyin qayta urinib ko'ring", { retryAfter: 3600 });
  }
}

async function uploadMedia(request, env, context) {
  const maxBytes = MAX_DIRECT_IMAGE_BYTES;
  const maxLabel = '4 MB';
  const mime = str(request.headers.get('content-type')).split(';')[0].trim().toLowerCase();
  const allowed = ['image/jpeg', 'image/jpg', 'image/png', 'image/webp', 'image/avif', 'image/gif'];
  if (!allowed.includes(mime)) throw new HttpError(400, 'JPEG, PNG, WebP, AVIF yoki GIF rasm yuklang', { field: 'image' });
  const declared = num(request.headers.get('content-length'), -1);
  if (declared > maxBytes) throw new HttpError(413, `Rasm ${maxLabel} dan katta bo'lmasin`, { field: 'image' });
  const bytes = await request.arrayBuffer();
  if (!bytes.byteLength || bytes.byteLength > maxBytes) {
    throw new HttpError(413, `Rasm ${maxLabel} dan katta bo'lmasin`, { field: 'image' });
  }
  await takeMediaQuota(env, context, bytes.byteLength);
  const ref = await storeImageBytes(env, bytes, mime, { maxBytes });
  // Bu yengil indeks limit va admin statistikasi uchun. Rasmning o'zi faqat
  // R2 da, D1 esa bir necha o'n bayt metadata saqlaydi.
  await run(env, 'INSERT INTO media_uploads(ref, user_id, mime, bytes, storage, created_at) VALUES(?,?,?,?,?,?)', [
    ref, context.user.id, mime, bytes.byteLength, mediaStoreName(env), now(),
  ]);
  return { ref, storage: mediaStoreName(env) };
}

async function sellerSignup(env, input) {
  const firstName = personName(input.firstName, 'Ism');
  const lastName = personName(input.lastName, 'Familiya');
  const phone = needPhone(input.phone);
  const email = needEmail(input.email);
  const shopName = str(input.shopName ?? input.name).trim().replace(/\s+/g, ' ').slice(0, 60);
  const aiName = str(input.aiName ?? input.sellerName).trim().replace(/\s+/g, ' ').slice(0, 30) || 'Madina';
  const region = str(input.region).trim();
  const login = needLogin(input.login);
  const password = needPassword(input.password);
  if (shopName.length < 2) throw new HttpError(400, "Do'kon nomini kiriting", { field: 'shopName' });
  if (!REGIONS.includes(region)) throw new HttpError(400, 'Viloyatni tanlang', { field: 'region' });
  const location = locationOf(input.location, { required: true });
  if (!location.address) throw new HttpError(400, "Do'kon manzilini kiriting", { field: 'address' });
  if (input.logo && !str(input.logo).startsWith('data:image/') && !isMediaRef(input.logo)) {
    throw new HttpError(400, "Logo rasm bo'lishi kerak", { field: 'logo' });
  }
  if (await one(env, 'SELECT id FROM shops WHERE login=?', [login])) throw new HttpError(409, 'Bu login band. Boshqasini tanlang', { field: 'login' });
  if (await one(env, 'SELECT id FROM shops WHERE email=?', [email])) {
    throw new HttpError(409, "Bu email bilan do'kon ochilgan. Kirish bo'limidan foydalaning", { field: 'email' });
  }
  return { firstName, lastName, phone, email, shopName, aiName, region, login, password, location };
}

async function courierSignup(env, input) {
  const type = input.type === 'cargo' ? 'cargo' : 'courier';
  const firstName = personName(input.firstName, 'Ism');
  const lastName = personName(input.lastName, 'Familiya');
  const phone = needPhone(input.phone);
  const email = needEmail(input.email);
  const login = needLogin(input.login);
  const password = needPassword(input.password);
  let region = str(input.region).trim();
  let vehicle = 'car';
  let vehicleType = '';
  let plate = '';
  let capacityKg = 0;
  let regions = [];
  const basePrice = Math.max(0, Math.round(num(input.basePrice)));
  const pricePerKm = Math.max(0, Math.round(num(input.pricePerKm)));
  // Xaridor buyurtmani kim olib kelayotganini ko'rishi kerak, shuning uchun
  // haydovchining rasmi majburiy; mashinali bo'lsa mashina rasmi ham.
  const okImage = (value) => str(value).startsWith('data:image/') || isMediaRef(value);
  if (!input.photo) throw new HttpError(400, "O'z rasmingizni qo'shing", { field: 'photo' });
  if (!okImage(input.photo)) throw new HttpError(400, "Rasm bo'lishi kerak", { field: 'photo' });
  if (input.carPhoto && !okImage(input.carPhoto)) throw new HttpError(400, "Mashina rasmi rasm bo'lishi kerak", { field: 'carPhoto' });
  const needsCar = type === 'cargo' || input.vehicle === 'moto' || input.vehicle === 'car';
  if (needsCar && !input.carPhoto) throw new HttpError(400, 'Mashinangiz rasmini qo\'shing', { field: 'carPhoto' });

  if (type === 'courier') {
    if (!REGIONS.includes(region)) throw new HttpError(400, 'Ishlaydigan viloyatingizni tanlang', { field: 'region' });
    if (!VEHICLES.includes(input.vehicle)) throw new HttpError(400, 'Transportingizni tanlang', { field: 'vehicle' });
    vehicle = input.vehicle;
    regions = [region];
    if (vehicle === 'moto' || vehicle === 'car') {
      plate = str(input.plate).trim().toUpperCase().replace(/\s+/g, ' ').slice(0, 12);
      if (plate.replace(/\s/g, '').length < 5) throw new HttpError(400, 'Mashina davlat raqamini kiriting', { field: 'plate' });
    }
  } else {
    if (!VEHICLE_TYPES.includes(input.vehicleType)) throw new HttpError(400, 'Mashina turini tanlang', { field: 'vehicleType' });
    vehicleType = input.vehicleType;
    plate = str(input.plate).trim().toUpperCase().replace(/\s+/g, ' ').slice(0, 12);
    if (plate.replace(/\s/g, '').length < 5) throw new HttpError(400, 'Mashina davlat raqamini kiriting', { field: 'plate' });
    capacityKg = Math.round(num(input.capacityKg));
    if (capacityKg < 50) throw new HttpError(400, "Yuk sig'imini kiriting (kg)", { field: 'capacityKg' });
    if (basePrice <= 0 && pricePerKm <= 0) throw new HttpError(400, "Narxni kiriting: boshlang'ich narx yoki 1 km narxi", { field: 'basePrice' });
    regions = [...new Set((Array.isArray(input.regions) ? input.regions : []).map(String).filter((item) => REGIONS.includes(item)))];
    if (!regions.length) throw new HttpError(400, 'Kamida bitta viloyatni tanlang', { field: 'regions' });
    if (!REGIONS.includes(region)) region = regions[0];
  }
  if (await one(env, 'SELECT id FROM couriers WHERE login=?', [login])) throw new HttpError(409, 'Bu login band. Boshqasini tanlang', { field: 'login' });
  if (await one(env, 'SELECT id FROM couriers WHERE email=? AND type=?', [email, type])) {
    throw new HttpError(409, "Bu email bilan hisob ochilgan. Kirish bo'limidan foydalaning", { field: 'email' });
  }
  return { type, firstName, lastName, phone, email, login, password, region, vehicle, vehicleType, plate, capacityKg, regions, basePrice, pricePerKm };
}

async function createOrUpdateBuyer(env, context, input) {
  const firstName = personName(input.firstName, 'Ism');
  const lastName = personName(input.lastName, 'Familiya');
  const phone = needPhone(input.phone);
  const telegram = needTelegram(input.telegram);
  const email = needEmail(input.email);
  const existing = await one(env, 'SELECT * FROM users WHERE email=?', [email]);
  if (existing && bool(existing.blocked)) throw new HttpError(403, "Bu hisob bloklangan. Qo'llab-quvvatlash xizmatiga murojaat qiling");
  let targetId = existing ? existing.id : (!context.user.registered_at ? context.user.id : null);
  const phoneOwner = await one(env, 'SELECT * FROM users WHERE phone=?', [phone]);
  if (phoneOwner && phoneOwner.id !== targetId && phoneOwner.email_verified_at) {
    throw new HttpError(409, "Bu telefon raqami boshqa email bilan tasdiqlangan. O'sha emailni kiriting", { field: 'phone' });
  }
  if (!str(input.code).trim()) return { pending: await sendCode(env, { email, purpose: 'buyer', name: firstName }) };
  await checkCode(env, { email, purpose: 'buyer', code: input.code });
  if (phoneOwner && phoneOwner.id !== targetId) await run(env, 'UPDATE users SET phone=NULL WHERE id=?', [phoneOwner.id]);
  if (targetId == null) {
    const created = await one(env, 'INSERT INTO users(name, created_at) VALUES(?,?) RETURNING id', [firstName, now()]);
    targetId = created.id;
  }
  const stamp = now();
  const user = await one(env, `UPDATE users SET name=?, first_name=?, last_name=?, phone=?, email=?, telegram=?,
    email_verified_at=?, registered_at=COALESCE(registered_at, ?) WHERE id=? RETURNING *`, [
    firstName + ' ' + lastName, firstName, lastName, phone, email, telegram, stamp, stamp, targetId,
  ]);
  if (targetId !== context.user.id) await run(env, 'UPDATE sessions SET user_id=?, updated_at=? WHERE token=?', [targetId, now(), context.token]);
  await consumeCode(env, email, 'buyer');
  return { user: publicUser(user) };
}

async function assignCourier(env, orderId) {
  const order = await one(env, ORDER_SELECT + " WHERE o.id=?", [orderId]);
  if (!order || order.courier_id || order.status !== 'new') return null;
  const cutoff = new Date(Date.now() - 30 * 60 * 1000).toISOString();
  const candidates = await all(env, `SELECT c.*, (
    SELECT COUNT(*) FROM orders x WHERE x.courier_id=c.id AND x.delivery_status IN ('assigned','picked')
  ) AS active_jobs FROM couriers c
    WHERE c.type='courier' AND c.active=1 AND c.online=1 AND c.lat IS NOT NULL AND c.location_at>?`, [cutoff]);
  const rejected = new Set(parseList(order.rejected_by));
  const pick = candidates
    .filter((candidate) => num(candidate.active_jobs) < 3 && !rejected.has(candidate.id))
    .map((candidate) => ({ candidate, distance: distanceKm(order.shop_lat, order.shop_lon, candidate.lat, candidate.lon) ?? 1e9 }))
    .sort((a, b) => a.distance - b.distance)[0];
  if (!pick) return null;
  const result = await run(env, `UPDATE orders SET courier_id=?, delivery_status='assigned', updated_at=?
    WHERE id=? AND courier_id IS NULL AND status='new'`, [pick.candidate.id, now(), orderId]);
  if (num(result.meta && result.meta.changes) <= 0) return null;
  // Kuryer ilovani yopgan bo'lsa ham xabar yetadi (ilova ichidagi 20 soniyalik
  // tekshiruvdan farqli). Push sozlanmagan bo'lsa jim o'tadi.
  await push(env, { courierId: pick.candidate.id }, {
    title: 'Sizga buyurtma bor',
    body: `${order.shop_name || "Do'kon"} → ${order.address || order.customer_name || 'manzil'}`,
    data: { type: 'order', orderId: order.id },
  }).catch((error) => console.error('push xato', error));
  return pick.candidate.id;
}

async function refreshInterests(env, userId) {
  const rows = await all(env, `SELECT p.category, COUNT(*) AS n FROM (
    SELECT product_id FROM product_likes WHERE user_id=?
    UNION ALL
    SELECT product_id FROM product_views WHERE user_id=?
    UNION ALL
    SELECT product_id FROM reel_events WHERE user_id=? AND dwell_ms>=2000
  ) a JOIN products p ON p.id=a.product_id WHERE p.category IS NOT NULL AND p.category<>'' GROUP BY p.category ORDER BY n DESC LIMIT 8`, [userId, userId, userId]);
  const categories = rows.map((row) => row.category);
  const interest = { categories, keywords: [], summary: categories.length ? "Ko'rilgan va yoqqan mahsulotlar asosida" : null, source: 'activity' };
  await run(env, 'UPDATE users SET interests=?, interests_at=? WHERE id=?', [JSON.stringify(interest), now(), userId]);
  return interest;
}

async function sellerAnalytics(env, shop) {
  const stats = await one(env, `SELECT
    COUNT(*) AS totalOrders,
    SUM(CASE WHEN status='new' THEN 1 ELSE 0 END) AS newOrders,
    COALESCE(SUM(CASE WHEN status='done' THEN price ELSE 0 END),0) AS revenue,
    COUNT(DISTINCT CASE WHEN phone<>'' THEN phone ELSE customer_name END) AS customers,
    COALESCE(AVG(CASE WHEN status='done' THEN price END),0) AS avgCheck,
    SUM(CASE WHEN status='done' THEN 1 ELSE 0 END) AS done,
    SUM(CASE WHEN status='cancelled' THEN 1 ELSE 0 END) AS cancelled
    FROM orders WHERE shop_id=? AND archived=0`, [shop.id]);
  const products = await all(env, 'SELECT * FROM products WHERE shop_id=? ORDER BY views DESC, created_at DESC', [shop.id]);
  const tips = [];
  if (num(stats.newOrders) > 0) tips.push({ type: 'warning', title: num(stats.newOrders) + ' ta yangi buyurtma', text: 'Yangi buyurtmalarni tezroq tasdiqlang yoki bekor qiling.' });
  if (products.length < 5) tips.push({ type: 'idea', title: "Katalogni to'ldiring", text: "Kamida 5–10 ta mahsulot qo'shing." });
  if (shop.lat == null) tips.push({ type: 'idea', title: "Joylashuv yo'q", text: "Do'kon joylashuvini xaritada belgilang." });
  if (!tips.length) tips.push({ type: 'success', title: 'Do‘kon ishlayapti', text: 'Mahsulot rasmlarini va narxlarini muntazam yangilang.' });
  return {
    stats: {
      totalOrders: num(stats.totalOrders), newOrders: num(stats.newOrders), revenue: num(stats.revenue), customers: num(stats.customers),
      unitsSold: 0, avgCheck: Math.round(num(stats.avgCheck)), views: products.reduce((sum, product) => sum + num(product.views), 0),
      conversion: 0,
    },
    week: { n: 0 }, prev: { n: 0 }, thisMonth: { total: 0, done: 0, cancelled: 0, new: 0, sumDone: 0 }, prevMonth: null,
    byDay: [], byDay30: [], topSold: [], customers: [], recent: [], status: { done: num(stats.done), new: num(stats.newOrders), cancelled: num(stats.cancelled), sums: { done: num(stats.revenue) } },
    hourBlocks: [], byWeekday: [], peakHour: null, bestWeekday: null, top: products.slice(0, 5).map(serializeProduct),
    unsold: products.filter((product) => num(product.views) === 0).slice(0, 5).map(serializeProduct), tips,
  };
}

async function registerSeller(env, context, input) {
  const signup = await sellerSignup(env, input);
  if (!str(input.code).trim()) return sendCode(env, { email: signup.email, purpose: 'seller', name: signup.firstName });
  await checkCode(env, { email: signup.email, purpose: 'seller', code: input.code });
  const id = newId('s_');
  const stamp = now();
  const logo = input.logo ? await storeDataUri(env, input.logo) : null;
  await run(env, `INSERT INTO shops(
    id,name,seller_name,owner_name,first_name,last_name,phone,email,email_verified_at,region,login,pass_hash,logo,lat,lon,address,created_at,last_login_at
  ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`, [
    id, signup.shopName, signup.aiName, signup.firstName + ' ' + signup.lastName, signup.firstName, signup.lastName, signup.phone,
    signup.email, stamp, signup.region, signup.login, await hashPassword(signup.password), logo,
    signup.location.lat, signup.location.lon, signup.location.address, stamp, stamp,
  ]);
  await consumeCode(env, signup.email, 'seller');
  await run(env, 'UPDATE sessions SET shop_id=?, courier_id=NULL, updated_at=? WHERE token=?', [id, now(), context.token]);
  await notifyShop(env, id, 'system', "Do'koningiz ochildi", signup.aiName + " — do'koningizning AI sotuvchisi ishga tushdi. Birinchi mahsulotingizni qo'shing.");
  return { shop: serializeShop(await getShop(env, id)) };
}

async function loginSeller(env, context, input) {
  const who = str(input.login).trim().toLowerCase();
  const shop = who.includes('@')
    ? await one(env, 'SELECT * FROM shops WHERE email=? ORDER BY created_at DESC LIMIT 1', [who])
    : await one(env, 'SELECT * FROM shops WHERE login=?', [who]);
  if (!shop || !(await checkPassword(input.password, shop.pass_hash))) throw new HttpError(403, "Login yoki parol noto'g'ri");
  if (!bool(shop.active)) throw new HttpError(403, "Do'koningiz bloklangan. Qo'llab-quvvatlash xizmatiga murojaat qiling");
  await run(env, 'UPDATE sessions SET shop_id=?, courier_id=NULL, updated_at=? WHERE token=?', [shop.id, now(), context.token]);
  await run(env, 'UPDATE shops SET last_login_at=? WHERE id=?', [now(), shop.id]);
  return { shop: serializeShop(await getShop(env, shop.id)) };
}

async function registerCourier(env, context, input) {
  const signup = await courierSignup(env, input);
  if (!str(input.code).trim()) return sendCode(env, { email: signup.email, purpose: signup.type, name: signup.firstName });
  await checkCode(env, { email: signup.email, purpose: signup.type, code: input.code });
  const id = newId('c_');
  const stamp = now();
  const photo = input.photo ? await storeDataUri(env, input.photo) : null;
  const carPhoto = input.carPhoto ? await storeDataUri(env, input.carPhoto) : null;
  await run(env, `INSERT INTO couriers(
    id,type,name,first_name,last_name,phone,email,email_verified_at,login,pass_hash,photo,car_photo,region,vehicle,vehicle_type,plate,capacity_kg,
    regions,price_per_km,base_price,created_at,last_login_at
  ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`, [
    id, signup.type, signup.firstName + ' ' + signup.lastName, signup.firstName, signup.lastName, signup.phone, signup.email, stamp,
    signup.login, await hashPassword(signup.password), photo, carPhoto, signup.region, signup.vehicle, signup.vehicleType, signup.plate,
    signup.capacityKg, JSON.stringify(signup.regions), signup.pricePerKm, signup.basePrice, stamp, stamp,
  ]);
  await consumeCode(env, signup.email, signup.type);
  await run(env, 'UPDATE sessions SET courier_id=?, shop_id=NULL, updated_at=? WHERE token=?', [id, now(), context.token]);
  return { courier: serializeCourier(await one(env, 'SELECT * FROM couriers WHERE id=?', [id])) };
}

async function loginCourier(env, context, input) {
  const who = str(input.login).trim().toLowerCase();
  const type = input.type === 'cargo' ? 'cargo' : input.type === 'courier' ? 'courier' : null;
  let courier;
  if (who.includes('@')) {
    courier = type
      ? await one(env, 'SELECT * FROM couriers WHERE email=? AND type=? ORDER BY created_at DESC LIMIT 1', [who, type])
      : await one(env, 'SELECT * FROM couriers WHERE email=? ORDER BY created_at DESC LIMIT 1', [who]);
  } else {
    courier = await one(env, 'SELECT * FROM couriers WHERE login=?', [who]);
  }
  if (!courier || !(await checkPassword(input.password, courier.pass_hash))) throw new HttpError(403, "Login yoki parol noto'g'ri");
  if (type && courier.type !== type) {
    throw new HttpError(403, courier.type === 'cargo'
      ? "Bu yuk tashuvchi hisobi. Yuk tashuvchi bo'limidan kiring"
      : "Bu kuryer hisobi. Kuryer bo'limidan kiring");
  }
  if (!bool(courier.active)) throw new HttpError(403, "Hisobingiz bloklangan. Qo'llab-quvvatlash xizmatiga murojaat qiling");
  await run(env, 'UPDATE sessions SET courier_id=?, shop_id=NULL, updated_at=? WHERE token=?', [courier.id, now(), context.token]);
  await run(env, 'UPDATE couriers SET last_login_at=? WHERE id=?', [now(), courier.id]);
  return { courier: serializeCourier(await one(env, 'SELECT * FROM couriers WHERE id=?', [courier.id])) };
}

async function resetPassword(env, context, input) {
  // 'cargo' ham couriers jadvalida yotadi. Avval u hech qaysi shoxga
  // tushmay, yuk tashuvchi parolini umuman tiklab bo'lmasdi.
  const type = input.role === 'courier' ? 'courier' : input.role === 'cargo' ? 'cargo' : null;
  const role = input.role === 'seller' ? 'seller' : type ? 'courier' : null;
  if (!role) throw new HttpError(400, 'Rolni tanlang');
  const email = needEmail(input.email);
  // Bir email bilan ham kuryer, ham yuk tashuvchi hisobi bo'lishi mumkin
  // (couriers.UNIQUE(email, type)) — shuning uchun tur bo'yicha ajratiladi.
  const account = role === 'seller'
    ? await one(env, 'SELECT * FROM shops WHERE email=? AND email_verified_at IS NOT NULL ORDER BY created_at DESC LIMIT 1', [email])
    : await one(env, 'SELECT * FROM couriers WHERE email=? AND type=? AND email_verified_at IS NOT NULL ORDER BY created_at DESC LIMIT 1', [email, type]);
  if (!str(input.code).trim()) {
    if (!account) return { codeSent: true, email, expiresIn: 600, resendIn: 60 };
    return sendCode(env, { email, purpose: 'reset', name: account.first_name || account.name });
  }
  const password = needPassword(input.password);
  if (!account) throw new HttpError(400, "Kod noto'g'ri", { codeInvalid: true });
  await checkCode(env, { email, purpose: 'reset', code: input.code });
  if (role === 'seller') {
    await run(env, 'UPDATE shops SET pass_hash=? WHERE id=?', [await hashPassword(password), account.id]);
    await run(env, 'UPDATE sessions SET shop_id=NULL, updated_at=? WHERE shop_id=? AND token<>?', [now(), account.id, context.token]);
  } else {
    await run(env, 'UPDATE couriers SET pass_hash=? WHERE id=?', [await hashPassword(password), account.id]);
    await run(env, 'UPDATE sessions SET courier_id=NULL, updated_at=? WHERE courier_id=? AND token<>?', [now(), account.id, context.token]);
  }
  await consumeCode(env, email, 'reset');
  return { ok: true, login: account.login };
}

async function logout(env, context) {
  if (context.courier) await run(env, 'UPDATE couriers SET online=0 WHERE id=?', [context.courier.id]);
  await run(env, 'DELETE FROM sessions WHERE token=?', [context.token]);
  return { ok: true };
}

async function listShops(env, context, url) {
  const q = str(url.searchParams.get('q')).trim();
  const limit = limitOf(url.searchParams.get('limit'), 20, 50);
  const offset = Math.max(0, Math.floor(num(url.searchParams.get('offset'))));
  let rows;
  if (q) {
    const like = '%' + q + '%';
    rows = await all(env, SHOP_STATS + ` WHERE s.active=1 AND (
      s.name LIKE ? COLLATE NOCASE OR s.description LIKE ? COLLATE NOCASE OR EXISTS(
        SELECT 1 FROM products p WHERE p.shop_id=s.id AND p.active=1 AND p.name LIKE ? COLLATE NOCASE
      )
    ) ORDER BY sales DESC, product_count DESC, s.created_at DESC LIMIT ? OFFSET ?`, [like, like, like, limit + 1, offset]);
  } else {
    rows = await all(env, SHOP_STATS + ' WHERE s.active=1 ORDER BY sales DESC, product_count DESC, s.created_at DESC LIMIT ? OFFSET ?', [limit + 1, offset]);
  }
  const items = rows.slice(0, limit);
  return {
    items: await withPreviews(env, items),
    hasMore: rows.length > limit,
    seed: url.searchParams.get('seed') || 'default',
  };
}

/// Do'kon kartochkasi fonida o'sha do'konning mahsulot rasmlari aylanadi.
/// Ro'yxatdagi har do'kon uchun alohida so'rov yubormaslik uchun hammasi
/// bitta so'rovda olinadi va do'kon bo'yicha guruhlanadi.
const PREVIEW_PER_SHOP = 5;

async function withPreviews(env, shops) {
  if (!shops.length) return [];
  const ids = shops.map((s) => s.id);
  const marks = ids.map(() => '?').join(',');
  const rows = await all(env, `SELECT id, shop_id, name, price, photos FROM products
    WHERE active=1 AND shop_id IN (${marks}) AND photos <> '[]'
    ORDER BY created_at DESC LIMIT ?`, [...ids, ids.length * PREVIEW_PER_SHOP * 3]);
  const byShop = new Map();
  for (const row of rows) {
    const list = byShop.get(row.shop_id) || [];
    if (list.length >= PREVIEW_PER_SHOP) continue;
    // Har mahsulotdan faqat birinchi rasm — karta bir do'konning turli
    // mahsulotlarini ko'rsatsin, bitta mahsulotning rakurslarini emas.
    const first = parseList(row.photos)[0];
    if (!first) continue;
    // Kartochka rasm bilan birga mahsulot nomi va narxini ham ko'rsatadi
    byShop.set(row.shop_id, [...list, { id: row.id, name: row.name || '', price: num(row.price), photo: first }]);
  }
  return shops.map((shop) => {
    const items = byShop.get(shop.id) || [];
    // `preview` eski ilova versiyalari uchun qoldirildi
    return serializeShop(shop, { preview: items.map((i) => i.photo), previewItems: items });
  });
}

/// "Sizga yaqin": joylashuvga ruxsat bergan xaridorga yaqin-atrofdagi
/// eng yaxshi do'kon va mahsulotlarni ko'rsatadi.
///
/// Faqat masofa bo'yicha saralash yaxshi natija bermaydi: eng yaqin do'kon
/// bo'sh yoki yangi bo'lishi mumkin. Shuning uchun ikkita omil ko'paytiriladi:
///
///   ball = yaqinlik × sifat
///   yaqinlik = 1 / (1 + km / 3)   — 0 km: 1.0, 3 km: 0.5, 9 km: 0.25
///   sifat    = 1 + log10(1 + sotuvlar×3 + obunachilar×2 + mahsulotlar)
///
/// log10 sifatning ta'sirini yumshatadi: 1000 ta sotuvli do'kon 10 ta sotuvlisidan
/// cheksiz ustun bo'lib ketmaydi, lekin baribir oldinga chiqadi. Natijada
/// yonginangizdagi kuchsiz do'kon ham, 10 km naridagi zo'r do'kon ham
/// ro'yxatga tushadi — real bozordagi tanlovga o'xshaydi.
const NEAR_SOFT_KM = 3;

function nearbyScore(km, quality) {
  const proximity = 1 / (1 + km / NEAR_SOFT_KM);
  return proximity * (1 + Math.log10(1 + Math.max(0, quality)));
}

async function nearbyFeed(env, context, url) {
  const lat = Number(url.searchParams.get('lat'));
  const lon = Number(url.searchParams.get('lon'));
  if (!Number.isFinite(lat) || !Number.isFinite(lon) || Math.abs(lat) > 90 || Math.abs(lon) > 180) {
    throw new HttpError(400, 'Joylashuv notogri', { field: 'location' });
  }
  // `num(null)` nolga aylanadi, shuning uchun bo'sh qiymat alohida tekshiriladi
  const rawRadius = url.searchParams.get('radius');
  const radiusKm = Math.min(200, Math.max(1, rawRadius ? num(rawRadius, 25) : 25));
  const shopLimit = limitOf(url.searchParams.get('shops'), 10, 30);
  const productLimit = limitOf(url.searchParams.get('products'), 20, 60);

  // Bazadan faqat kerakli kvadratni olamiz — butun jadvalni emas.
  // 1 daraja kenglik ~111 km; uzunlikda kenglikka qarab qisqaradi.
  const dLat = radiusKm / 111;
  const dLon = radiusKm / Math.max(1, 111 * Math.cos((lat * Math.PI) / 180));
  const shops = await all(env, SHOP_STATS + ` WHERE s.active=1
    AND s.lat IS NOT NULL AND s.lon IS NOT NULL
    AND s.lat BETWEEN ? AND ? AND s.lon BETWEEN ? AND ?`,
    [lat - dLat, lat + dLat, lon - dLon, lon + dLon]);

  const ranked = [];
  for (const shop of shops) {
    // Kvadrat doiradan kattaroq — chetdagilarni aniq masofa bilan chiqaramiz
    const km = distanceKm(lat, lon, num(shop.lat), num(shop.lon));
    if (km == null || km > radiusKm) continue;
    const quality = num(shop.sales) * 3 + num(shop.followers) * 2 + num(shop.product_count);
    ranked.push({ shop, km, score: nearbyScore(km, quality) });
  }
  ranked.sort((a, b) => b.score - a.score);

  const topShops = ranked.slice(0, shopLimit);
  let products = [];
  if (topShops.length) {
    const ids = topShops.map((item) => item.shop.id);
    const rows = await all(env, `SELECT p.* FROM products p
      WHERE p.active=1 AND p.shop_id IN (${ids.map(() => '?').join(',')})
      ORDER BY p.views DESC, p.created_at DESC LIMIT ?`, [...ids, productLimit * 3]);
    const byShop = new Map(topShops.map((item) => [item.shop.id, item]));
    products = rows
      .map((product) => {
        const owner = byShop.get(product.shop_id);
        // Mahsulot balli: do'konning yaqinligi + mahsulotning o'z talabi
        const score = nearbyScore(owner.km, num(product.views) * 2 + num(owner.shop.sales) * 3);
        return { product, owner, score };
      })
      .sort((a, b) => b.score - a.score)
      .slice(0, productLimit);
  }

  const round = (km) => Math.round(km * 10) / 10;
  return {
    radiusKm,
    shops: topShops.map((item) => serializeShop(item.shop, { distanceKm: round(item.km) })),
    products: products.map((item) => ({
      ...serializeProduct(item.product),
      shop: item.owner.shop.name,
      distanceKm: round(item.owner.km),
    })),
  };
}

async function shopDetail(env, context, id) {
  const shop = await getShop(env, id);
  if (!shop || !bool(shop.active)) throw new HttpError(404, "Do'kon topilmadi");
  const products = await all(env, 'SELECT * FROM products WHERE shop_id=? AND active=1 ORDER BY created_at DESC', [id]);
  return { shop: serializeShop(shop, await shopFollowInfo(env, id, context.user.id)), products: products.map(serializeProduct) };
}

async function categoryProducts(env, slug) {
  const rows = await all(env, `SELECT p.* FROM products p JOIN shops s ON s.id=p.shop_id
    WHERE p.category=? AND p.active=1 AND s.active=1 ORDER BY p.views DESC, p.created_at DESC LIMIT 300`, [slug]);
  const shopIds = [...new Set(rows.map((product) => product.shop_id))];
  const shops = {};
  for (const id of shopIds) {
    const shop = await getShop(env, id);
    if (shop) shops[id] = serializeShop(shop);
  }
  return rows.map((product) => ({ ...serializeProduct(product), shop: shops[product.shop_id] || null }));
}

async function productDetail(env, id) {
  const product = await one(env, 'SELECT * FROM products WHERE id=?', [id]);
  if (!product) throw new HttpError(404, 'Mahsulot topilmadi');
  const shop = await getShop(env, product.shop_id);
  return { product: serializeProduct(product), shop: shop ? serializeShop(shop) : null };
}

async function relatedProducts(env, id, rawLimit) {
  const product = await one(env, 'SELECT * FROM products WHERE id=?', [id]);
  if (!product) throw new HttpError(404, 'Mahsulot topilmadi');
  const limit = limitOf(rawLimit, 10, 20);
  const rows = await all(env, `SELECT p.* FROM products p JOIN shops s ON s.id=p.shop_id
    WHERE p.active=1 AND s.active=1 AND p.id<>? AND (p.category=? OR p.shop_id=?)
    ORDER BY p.views DESC, p.created_at DESC LIMIT ?`, [product.id, product.category, product.shop_id, limit]);
  const shops = {};
  for (const shopId of [...new Set(rows.map((item) => item.shop_id))]) {
    const shop = await getShop(env, shopId);
    if (shop) shops[shopId] = serializeShop(shop);
  }
  return { items: rows.map((item) => ({ ...serializeProduct(item), shop: shops[item.shop_id] || null })) };
}

async function viewProduct(env, context, id) {
  const product = await one(env, 'SELECT id, shop_id, views FROM products WHERE id=?', [id]);
  if (!product) throw new HttpError(404, 'Mahsulot topilmadi');
  const result = await run(env, 'INSERT OR IGNORE INTO product_views(product_id, user_id, shop_id, created_at) VALUES(?,?,?,?)', [product.id, context.user.id, product.shop_id, now()]);
  if (num(result.meta && result.meta.changes) > 0) {
    await run(env, 'UPDATE products SET views=views+1, updated_at=? WHERE id=?', [now(), product.id]);
    return { views: num(product.views) + 1 };
  }
  return { views: num(product.views) };
}

async function toggleFollow(env, context, shopId, follow) {
  needBuyer(context);
  const shop = await one(env, 'SELECT id FROM shops WHERE id=? AND active=1', [shopId]);
  if (!shop) throw new HttpError(404, "Do'kon topilmadi");
  if (follow) {
    const result = await run(env, 'INSERT OR IGNORE INTO follows(user_id, shop_id, created_at) VALUES(?,?,?)', [context.user.id, shopId, now()]);
    if (num(result.meta && result.meta.changes) > 0) {
      await notifyShop(env, shopId, 'follow', 'Yangi obunachi', (context.user.name || 'Xaridor') + " do'koningizga obuna bo'ldi.");
    }
  } else {
    await run(env, 'DELETE FROM follows WHERE user_id=? AND shop_id=?', [context.user.id, shopId]);
  }
  return shopFollowInfo(env, shopId, context.user.id);
}

async function toggleLike(env, context, productId, like) {
  needBuyer(context);
  const product = await one(env, 'SELECT id FROM products WHERE id=?', [productId]);
  if (!product) throw new HttpError(404, 'Mahsulot topilmadi');
  if (like) await run(env, 'INSERT OR IGNORE INTO product_likes(user_id, product_id, created_at) VALUES(?,?,?)', [context.user.id, productId, now()]);
  else await run(env, 'DELETE FROM product_likes WHERE user_id=? AND product_id=?', [context.user.id, productId]);
  return productLikeInfo(env, productId, context.user.id);
}

async function listReels(env, context, url) {
  needBuyer(context);
  const limit = limitOf(url.searchParams.get('limit'), 5, 20);
  const offset = Math.max(0, Math.floor(num(url.searchParams.get('offset'))));
  const seed = url.searchParams.get('seed') || newToken().slice(0, 12);
  const rows = await all(env, `SELECT p.*,
    (SELECT COUNT(*) FROM product_likes l WHERE l.product_id=p.id) AS likes,
    EXISTS(SELECT 1 FROM product_likes l WHERE l.product_id=p.id AND l.user_id=?) AS liked,
    EXISTS(SELECT 1 FROM follows f WHERE f.shop_id=p.shop_id AND f.user_id=?) AS following
    FROM products p JOIN shops s ON s.id=p.shop_id
    WHERE p.active=1 AND s.active=1 AND p.photos<>'[]'
    ORDER BY p.views DESC, p.created_at DESC LIMIT ? OFFSET ?`, [context.user.id, context.user.id, limit + 1, offset]);
  const out = [];
  for (const row of rows.slice(0, limit)) {
    const shop = await getShop(env, row.shop_id);
    if (!shop) continue;
    const fresh = Date.now() - new Date(row.created_at).getTime() < 48 * 60 * 60 * 1000;
    out.push({
      product: serializeProduct(row), shop: serializeShop(shop, { following: bool(row.following) }),
      likes: num(row.likes), liked: bool(row.liked), isNew: fresh, reason: fresh ? 'new' : 'popular',
    });
  }
  return { items: out, hasMore: rows.length > limit, seed };
}

async function recordReelView(env, context, productId, input) {
  needBuyer(context);
  const product = await one(env, 'SELECT id, shop_id, views FROM products WHERE id=?', [productId]);
  if (!product) throw new HttpError(404, 'Mahsulot topilmadi');
  const dwellMs = Math.max(0, Math.min(600000, Math.round(num(input.ms))));
  await run(env, 'INSERT INTO reel_events(user_id, product_id, dwell_ms, created_at) VALUES(?,?,?,?)', [context.user.id, productId, dwellMs, now()]);
  if (dwellMs >= 2000) await viewProduct(env, context, productId);
  return { ok: true };
}

async function createOrder(env, context, input) {
  needBuyer(context);
  const items = Array.isArray(input.items) ? input.items.slice(0, 20) : [];
  if (!items.length) throw new HttpError(400, "Savat bo'sh");
  const ids = [...new Set(items.map((item) => str(item.productId)).filter(Boolean))];
  if (!ids.length) throw new HttpError(400, 'Mahsulot topilmadi');
  const placeholders = ids.map(() => '?').join(',');
  const products = await all(env, 'SELECT * FROM products WHERE id IN (' + placeholders + ') AND active=1', ids);
  if (!products.length) throw new HttpError(400, 'Mahsulot topilmadi');
  const shopId = products[0].shop_id;
  if (products.some((product) => product.shop_id !== shopId)) throw new HttpError(400, "Bitta buyurtmada faqat bitta do'kon mahsulotlari bo'lishi mumkin");
  const lines = items.map((item) => {
    const product = products.find((candidate) => candidate.id === str(item.productId));
    if (!product) return null;
    return { productId: product.id, name: product.name, price: num(product.price), qty: Math.min(99, Math.max(1, Math.floor(num(item.qty, 1)))) };
  }).filter(Boolean);
  if (!lines.length) throw new HttpError(400, 'Mahsulot topilmadi');
  const price = lines.reduce((sum, line) => sum + line.price * line.qty, 0);
  const productName = lines.length === 1 ? lines[0].name : lines[0].name + ' va yana ' + (lines.length - 1) + ' ta';
  const customerName = str(input.customerName).trim().slice(0, 80) || context.user.name;
  const location = locationOf({ lat: input.lat, lon: input.lon });
  const id = newId('o_');
  const stamp = now();
  await run(env, `INSERT INTO orders(
    id,user_id,shop_id,status,product_name,price,customer_name,phone,address,lat,lon,items,created_at,updated_at
  ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)`, [
    id, context.user.id, shopId, 'new', productName, price, customerName, str(input.phone).trim(), str(input.address).trim(),
    location ? location.lat : null, location ? location.lon : null, JSON.stringify(lines), stamp, stamp,
  ]);
  if (customerName && customerName !== context.user.name) await run(env, 'UPDATE users SET name=? WHERE id=?', [customerName, context.user.id]);
  await notifyShop(env, shopId, 'order', 'Yangi buyurtma', customerName + ': ' + productName + ' — ' + price.toLocaleString('ru-RU') + " so'm.", { orderId: id, amount: price });
  try { await assignCourier(env, id); } catch (error) { console.error('Courier assignment failed', error); }
  const order = await one(env, ORDER_SELECT + ' WHERE o.id=?', [id]);
  return { ok: true, order: serializeOrder(order) };
}

async function myOrders(env, context) {
  needBuyer(context);
  const rows = await all(env, ORDER_SELECT + ' WHERE o.user_id=? ORDER BY o.created_at DESC LIMIT 100', [context.user.id]);
  return rows.map(serializeOrder);
}

async function assistantHistory(env, context, scope) {
  const rows = await all(env, 'SELECT role, text FROM chat_messages WHERE user_id=? AND scope=? ORDER BY id DESC LIMIT 100', [context.user.id, scope]);
  return { history: rows.reverse().map((row) => ({ role: row.role, content: row.text })) };
}

async function saveChat(env, userId, scope, role, text, shopId = null) {
  await run(env, 'INSERT INTO chat_messages(user_id, shop_id, scope, role, text, created_at) VALUES(?,?,?,?,?,?)', [userId, shopId, scope, role, text, now()]);
}

async function simpleAssistant(env, context, input) {
  const message = str(input.message).trim();
  if (!message) throw new HttpError(400, "Xabar bo'sh");
  const lat = Number(input.lat);
  const lon = Number(input.lon);
  const rows = await all(env, SHOP_STATS + ' WHERE s.active=1 ORDER BY sales DESC, product_count DESC LIMIT 40');
  const shops = rows.map((shop) => serializeShop(shop, Number.isFinite(lat) && Number.isFinite(lon)
    ? { distanceKm: distanceKm(lat, lon, shop.lat, shop.lon) }
    : {}));
  const word = message.toLowerCase().split(/\s+/).find((part) => part.length >= 3) || '';
  const match = word ? shops.filter((shop) => (shop.name + ' ' + shop.description).toLowerCase().includes(word)) : shops;
  const text = match.length
    ? "Sizga mos do'konlarni topdim. Mahsulotlari va manzilini ochib ko'ring."
    : "Hozircha aniq mos do'kon topilmadi. Mahsulot nomi yoki kategoriya bilan qayta yozib ko'ring.";
  await saveChat(env, context.user.id, 'assistant', 'user', message);
  await saveChat(env, context.user.id, 'assistant', 'assistant', text);
  return { text, shops: match.slice(0, 6), showMap: match.filter((shop) => shop.location).length > 1, couriers: [], showCouriers: false, showCargo: /yuk|cargo|fura|gazel/i.test(message) };
}

async function shopChat(env, context, input) {
  const shopId = str(input.shopId);
  const mode = str(input.mode);
  const message = str(input.message).trim();
  const shop = await getShop(env, shopId);
  if (!shop) throw new HttpError(404, "Do'kon topilmadi");
  const products = await all(env, 'SELECT * FROM products WHERE shop_id=? AND active=1 ORDER BY views DESC LIMIT 100', [shopId]);
  const scope = 'shop:' + shopId;
  if (mode === 'catalog') {
    const text = products.length ? 'Mana bizning mahsulotlarimiz (' + products.length + ' ta):' : "Hozircha mahsulotlar qo'shilmagan.";
    await saveChat(env, context.user.id, scope, 'assistant', text, shopId);
    return { text, products: products.slice(0, 20).map(serializeProduct) };
  }
  if (!message) throw new HttpError(400, "Xabar bo'sh");
  const lowered = message.toLowerCase();
  const picked = products.filter((product) => (product.name + ' ' + product.description).toLowerCase().includes(lowered)).slice(0, 6);
  const text = picked.length
    ? "Siz so'ragan mahsulotlar quyida. Narx va mavjudlikni do'kon bilan aniqlashtirishingiz mumkin."
    : "Bu mahsulot bo'yicha aniq javob topilmadi. Do'kondagi boshqa mahsulotlarni ham ko'rib chiqing.";
  await saveChat(env, context.user.id, scope, 'user', message, shopId);
  await saveChat(env, context.user.id, scope, 'assistant', text, shopId);
  return { text, products: picked.map(serializeProduct) };
}

async function sellerProducts(env, context) {
  const shop = needShop(context);
  const products = await all(env, 'SELECT * FROM products WHERE shop_id=? ORDER BY created_at DESC', [shop.id]);
  return products.map(serializeProduct);
}

async function createSellerProduct(env, context, input) {
  const shop = needShop(context);
  const name = str(input.name).trim().replace(/\s+/g, ' ').slice(0, 120);
  if (!name) throw new HttpError(400, 'Mahsulot nomini kiriting', { field: 'name' });
  const price = positivePrice(input.price);
  const photos = await cleanPhotoRefs(env, input.photos);
  if (!photos.length) throw new HttpError(400, 'Kamida 1 ta rasm yuklang', { field: 'photos' });
  const id = newId('p_');
  const stamp = now();
  await run(env, `INSERT INTO products(id,shop_id,name,category,price,description,photos,active,views,created_at,updated_at)
    VALUES(?,?,?,?,?,?,?,?,?,?,?)`, [
    id, shop.id, name, str(input.category).trim() || null, price, str(input.description).trim().slice(0, 3000),
    JSON.stringify(photos), 1, 0, stamp, stamp,
  ]);
  return { product: serializeProduct(await one(env, 'SELECT * FROM products WHERE id=?', [id])) };
}

async function updateSellerProduct(env, context, productId, input) {
  const shop = needShop(context);
  const product = await one(env, 'SELECT * FROM products WHERE id=? AND shop_id=?', [productId, shop.id]);
  if (!product) throw new HttpError(404, 'Mahsulot topilmadi');
  const columns = [];
  const values = [];
  const set = (column, value) => { columns.push(column + '=?'); values.push(value); };
  if (input.name != null) {
    const name = str(input.name).trim().replace(/\s+/g, ' ').slice(0, 120);
    if (!name) throw new HttpError(400, "Mahsulot nomi bo'sh", { field: 'name' });
    set('name', name);
  }
  if (input.price != null) set('price', positivePrice(input.price));
  if (input.description != null) set('description', str(input.description).trim().slice(0, 3000));
  if (input.category != null) set('category', str(input.category).trim() || null);
  if (input.active != null) set('active', input.active === false ? 0 : 1);
  if (input.photos != null) {
    const photos = await cleanPhotoRefs(env, input.photos);
    if (!photos.length) throw new HttpError(400, 'Kamida 1 ta rasm yuklang', { field: 'photos' });
    set('photos', JSON.stringify(photos));
  }
  if (columns.length) {
    set('updated_at', now());
    values.push(product.id);
    await run(env, 'UPDATE products SET ' + columns.join(', ') + ' WHERE id=?', values);
  }
  return { product: serializeProduct(await one(env, 'SELECT * FROM products WHERE id=?', [product.id])) };
}

async function deleteSellerProduct(env, context, productId) {
  const shop = needShop(context);
  await run(env, 'DELETE FROM products WHERE id=? AND shop_id=?', [productId, shop.id]);
  return { ok: true };
}

async function sellerOrders(env, context) {
  const shop = needShop(context);
  const rows = await all(env, ORDER_SELECT + ' WHERE o.shop_id=? AND o.archived=0 ORDER BY o.created_at DESC LIMIT 300', [shop.id]);
  return rows.map(serializeOrder);
}

async function updateSellerOrder(env, context, orderId, input) {
  const shop = needShop(context);
  const status = str(input.status);
  if (!['done', 'cancelled'].includes(status)) throw new HttpError(400, "Status noto'g'ri");
  const order = await one(env, 'SELECT * FROM orders WHERE id=? AND shop_id=?', [orderId, shop.id]);
  if (!order) throw new HttpError(404, 'Buyurtma topilmadi');
  if (order.status !== 'new') throw new HttpError(409, order.status === 'done' ? 'Buyurtma allaqachon bajarilgan' : 'Buyurtma allaqachon bekor qilingan');
  if (status === 'cancelled') {
    await run(env, `UPDATE orders SET status='cancelled', courier_id=CASE WHEN COALESCE(delivery_status,'')<>'delivered' THEN NULL ELSE courier_id END,
      delivery_status=CASE WHEN COALESCE(delivery_status,'')<>'delivered' THEN NULL ELSE delivery_status END, updated_at=? WHERE id=?`, [now(), orderId]);
  } else {
    await run(env, 'UPDATE orders SET status=?, updated_at=? WHERE id=?', [status, now(), orderId]);
  }
  return { ok: true };
}

async function sellerBadges(env, context) {
  const shop = needShop(context);
  const row = await one(env, `SELECT
    (SELECT COUNT(*) FROM orders WHERE shop_id=? AND status='new' AND archived=0) AS newOrders,
    (SELECT COUNT(*) FROM notifications WHERE shop_id=? AND read=0) AS unread`, [shop.id, shop.id]);
  return { newOrders: num(row.newOrders), unread: num(row.unread) };
}

async function sellerNotifications(env, context, url) {
  const shop = needShop(context);
  const rows = await all(env, 'SELECT * FROM notifications WHERE shop_id=? ORDER BY created_at DESC LIMIT 100', [shop.id]);
  if (url.searchParams.get('read') === '1') await run(env, 'UPDATE notifications SET read=1 WHERE shop_id=? AND read=0', [shop.id]);
  return rows.map((row) => ({
    id: row.id, type: row.type, title: row.title, text: row.text, read: bool(row.read), createdAt: row.created_at, meta: parseJson(row.meta, {}),
  }));
}

async function updateSellerShop(env, context, input) {
  const shop = needShop(context);
  const columns = [];
  const values = [];
  const set = (column, value) => { columns.push(column + '=?'); values.push(value); };
  if (input.logo != null) set('logo', await storeDataUri(env, input.logo));
  if (input.name != null) {
    const name = str(input.name).trim().replace(/\s+/g, ' ').slice(0, 60);
    if (!name) throw new HttpError(400, "Do'kon nomi bo'sh", { field: 'name' });
    set('name', name);
  }
  if (input.sellerName != null) set('seller_name', str(input.sellerName).trim().slice(0, 30) || 'Madina');
  if (input.ownerName != null) set('owner_name', str(input.ownerName).trim().slice(0, 80));
  if (input.phone != null) set('phone', str(input.phone).trim().slice(0, 30));
  if (input.description != null) set('description', str(input.description).trim().slice(0, 3000));
  if (Object.prototype.hasOwnProperty.call(input, 'location')) {
    if (input.location == null) {
      set('lat', null); set('lon', null); set('address', null);
    } else {
      const location = locationOf(input.location, { required: true });
      set('lat', location.lat); set('lon', location.lon); set('address', location.address || null);
    }
  }
  if (columns.length) {
    values.push(shop.id);
    await run(env, 'UPDATE shops SET ' + columns.join(', ') + ' WHERE id=?', values);
  }
  return { shop: serializeShop(await getShop(env, shop.id)) };
}

async function sellerPassword(env, context, input) {
  const shop = needShop(context);
  if (!(await checkPassword(input.oldPassword, shop.pass_hash))) throw new HttpError(400, "Joriy parol noto'g'ri");
  const password = needPassword(input.newPassword);
  await run(env, 'UPDATE shops SET pass_hash=? WHERE id=?', [await hashPassword(password), shop.id]);
  await notifyShop(env, shop.id, 'security', "Parol o'zgartirildi", "Do'kon paroli yangilandi.");
  return { ok: true };
}

async function resetSellerData(env, context, input) {
  const shop = needShop(context);
  if (!(await checkPassword(input.password, shop.pass_hash))) throw new HttpError(400, "Parol noto'g'ri");
  const result = await run(env, 'UPDATE orders SET archived=1, updated_at=? WHERE shop_id=? AND archived=0', [now(), shop.id]);
  await run(env, 'UPDATE products SET views=0, updated_at=? WHERE shop_id=?', [now(), shop.id]);
  await run(env, 'DELETE FROM product_views WHERE shop_id=?', [shop.id]);
  await run(env, 'DELETE FROM notifications WHERE shop_id=?', [shop.id]);
  return { orders: num(result.meta && result.meta.changes) };
}

async function sellerAdvice(env, context) {
  const shop = needShop(context);
  const analytics = await sellerAnalytics(env, shop);
  return { tips: analytics.tips };
}

async function sellerAiSummary(env, context) {
  const shop = needShop(context);
  const analytics = await sellerAnalytics(env, shop);
  const stats = analytics.stats;
  const summary = stats.totalOrders
    ? "Jami " + stats.totalOrders + " ta buyurtma bor. Daromad: " + stats.revenue.toLocaleString('ru-RU') + " so'm."
    : "Hozircha buyurtma yo'q. Katalogga mahsulot va sifatli rasmlar qo'shishdan boshlang.";
  return {
    summary,
    highlights: analytics.tips.slice(0, 3).map((tip) => ({ type: tip.type === 'success' ? 'good' : tip.type === 'warning' ? 'warn' : 'idea', text: tip.text })),
    generatedAt: now(),
  };
}

async function courierLocation(env, context, input) {
  const courier = needCourier(context);
  const online = input.online !== false;
  const location = locationOf({ lat: input.lat, lon: input.lon });
  if (online && location) {
    // Yo'nalish va tezlik ham saqlanadi: xaritada belgi harakat tomoniga
    // qaraydi va kelish vaqtini baholashda ishlatiladi.
    const heading = Number.isFinite(num(input.heading, NaN)) ? num(input.heading) : null;
    const speed = Number.isFinite(num(input.speed, NaN)) ? Math.max(0, num(input.speed)) : null;
    await run(env, 'UPDATE couriers SET online=1, lat=?, lon=?, heading=?, speed=?, location_at=? WHERE id=?',
      [location.lat, location.lon, heading, speed, now(), courier.id]);
    const pending = await all(env, `SELECT id FROM orders WHERE courier_id IS NULL AND status='new' AND archived=0
      AND created_at>? ORDER BY created_at LIMIT 20`, [new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString()]);
    for (const order of pending) {
      try { await assignCourier(env, order.id); } catch (error) { console.error('courier assign failed', error); }
    }
  } else {
    await run(env, 'UPDATE couriers SET online=? WHERE id=?', [online ? 1 : 0, courier.id]);
  }
  return { ok: true, online };
}

async function updateCourierProfile(env, context, input) {
  const courier = needCourier(context);
  const columns = [];
  const values = [];
  const set = (column, value) => { columns.push(column + '=?'); values.push(value); };
  if (input.photo != null) set('photo', await storeDataUri(env, input.photo));
  // Mashina rasmi va davlat raqami ham profildan o'zgartiriladi
  if (input.carPhoto != null) set('car_photo', await storeDataUri(env, input.carPhoto));
  if (input.plate != null) {
    const plate = str(input.plate).trim().toUpperCase().replace(/\s+/g, ' ').slice(0, 12);
    if (plate && plate.replace(/\s/g, '').length < 5) throw new HttpError(400, "Davlat raqami noto'g'ri", { field: 'plate' });
    set('plate', plate);
  }
  if (input.name != null) {
    const name = str(input.name).trim().slice(0, 80);
    if (!name) throw new HttpError(400, "Ism bo'sh");
    set('name', name);
  }
  if (input.phone != null) set('phone', str(input.phone).trim().slice(0, 30));
  if (input.email != null) set('email', needEmail(input.email));
  if (input.about != null) set('about', str(input.about).trim().slice(0, 1000));
  if (input.vehicle != null && VEHICLES.includes(input.vehicle)) set('vehicle', input.vehicle);
  if (input.basePrice != null) set('base_price', Math.max(0, Math.round(num(input.basePrice))));
  if (input.pricePerKm != null) set('price_per_km', Math.max(0, Math.round(num(input.pricePerKm))));
  if (courier.type === 'cargo') {
    if (input.vehicleType != null && VEHICLE_TYPES.includes(input.vehicleType)) set('vehicle_type', input.vehicleType);
    if (input.capacityKg != null) set('capacity_kg', Math.max(0, Math.round(num(input.capacityKg))));
    if (Array.isArray(input.regions)) {
      const regions = [...new Set(input.regions.map(String).filter((region) => REGIONS.includes(region)))];
      if (!regions.length) throw new HttpError(400, 'Kamida bitta viloyat tanlang');
      set('regions', JSON.stringify(regions));
    }
  }
  if (columns.length) {
    values.push(courier.id);
    await run(env, 'UPDATE couriers SET ' + columns.join(', ') + ' WHERE id=?', values);
  }
  return { courier: serializeCourier(await one(env, 'SELECT * FROM couriers WHERE id=?', [courier.id])) };
}

async function courierOrders(env, context) {
  const courier = needCourier(context);
  const rows = await all(env, ORDER_SELECT + ` WHERE o.courier_id=? AND o.delivery_status IN ('assigned','picked','delivered')
    AND o.status<>'cancelled' ORDER BY (o.delivery_status='delivered'), o.created_at DESC LIMIT 100`, [courier.id]);
  return rows.map((order) => {
    const km = order.route_km != null ? num(order.route_km) : orderKm(order);
    return serializeOrder({ ...order, route_km: km, delivery_fee: order.delivery_fee != null ? order.delivery_fee : tariffPrice(courier.base_price, courier.price_per_km, km) });
  });
}

async function updateCourierOrder(env, context, orderId, input) {
  const courier = needCourier(context);
  const status = str(input.status);
  if (!['picked', 'delivered', 'rejected'].includes(status)) throw new HttpError(400, "Status noto'g'ri");
  const order = await one(env, ORDER_SELECT + ' WHERE o.id=? AND o.courier_id=?', [orderId, courier.id]);
  if (!order) throw new HttpError(404, 'Buyurtma topilmadi');
  if (order.status === 'cancelled') throw new HttpError(409, 'Buyurtma bekor qilingan');
  if (status === 'rejected') {
    if (order.delivery_status !== 'assigned') throw new HttpError(409, "Bu buyurtmani rad etib bo'lmaydi");
    const rejected = [...new Set([...parseList(order.rejected_by), courier.id])];
    await run(env, 'UPDATE orders SET courier_id=NULL, delivery_status=NULL, rejected_by=?, updated_at=? WHERE id=?', [JSON.stringify(rejected), now(), order.id]);
    try { await assignCourier(env, order.id); } catch (error) { console.error('courier reassignment failed', error); }
    return { ok: true };
  }
  if (status === 'picked') {
    if (order.delivery_status !== 'assigned') throw new HttpError(409, "Buyurtma holati o'zgargan");
    await run(env, `UPDATE orders SET delivery_status='picked', picked_at=?, updated_at=?
      WHERE id=? AND courier_id=? AND delivery_status='assigned'`, [now(), now(), order.id, courier.id]);
    return { ok: true };
  }
  if (order.delivery_status !== 'picked') throw new HttpError(409, "Avval buyurtmani olib ketilgan deb belgilang");
  const km = orderKm(order);
  const fee = tariffPrice(courier.base_price, courier.price_per_km, km);
  await run(env, `UPDATE orders SET delivery_status='delivered', delivered_at=?, route_km=?, delivery_fee=?,
    status=CASE WHEN status='new' THEN 'done' ELSE status END, updated_at=? WHERE id=? AND courier_id=? AND delivery_status='picked'`, [
    now(), km, fee, now(), order.id, courier.id,
  ]);
  await run(env, 'UPDATE couriers SET deliveries=deliveries+1 WHERE id=?', [courier.id]);
  await notifyShop(env, order.shop_id, 'order', 'Yetkazildi, sotuv yakunlandi', order.product_name + ' — ' + (order.customer_name || 'xaridor') + 'ga yetkazildi.');
  return { ok: true };
}

async function courierStats(env, context) {
  const courier = needCourier(context);
  const tariff = { basePrice: num(courier.base_price), pricePerKm: num(courier.price_per_km), isSet: num(courier.base_price) > 0 || num(courier.price_per_km) > 0 };
  if (courier.type === 'cargo') {
    const rows = await all(env, 'SELECT * FROM cargo_orders WHERE carrier_id=?', [courier.id]);
    const count = (status) => rows.filter((row) => row.status === status).length;
    const done = rows.filter((row) => row.status === 'done');
    const total = done.reduce((sum, row) => sum + num(row.price), 0);
    const monthCutoff = Date.now() - 30 * 24 * 60 * 60 * 1000;
    const month = done.filter((row) => new Date(row.done_at || row.created_at).getTime() >= monthCutoff).reduce((sum, row) => sum + num(row.price), 0);
    const decided = count('accepted') + count('done') + count('rejected');
    return {
      type: 'cargo', tariff, counts: { new: count('new'), accepted: count('accepted'), done: count('done'), rejected: count('rejected') },
      acceptRate: decided ? Math.round((count('accepted') + count('done')) * 100 / decided) : null,
      revenue: { month, total }, byDay: [], topRoutes: [], market: { carriers: 0, medianBasePrice: 0, medianPricePerKm: 0 },
    };
  }
  const delivered = await all(env, `SELECT * FROM orders WHERE courier_id=? AND delivery_status='delivered'`, [courier.id]);
  const period = (hours) => {
    const rows = hours ? delivered.filter((row) => new Date(row.delivered_at || row.created_at).getTime() >= Date.now() - hours * 60 * 60 * 1000) : delivered;
    return {
      deliveries: rows.length,
      earnings: rows.reduce((sum, row) => sum + num(row.delivery_fee), 0),
      km: Math.round(rows.reduce((sum, row) => sum + num(row.route_km), 0) * 10) / 10,
    };
  };
  const active = await one(env, `SELECT COUNT(*) AS n FROM orders WHERE courier_id=? AND delivery_status IN ('assigned','picked')`, [courier.id]);
  return {
    type: 'courier', tariff, today: period(24), week: period(7 * 24), month: period(30 * 24), total: period(0),
    active: num(active.n), acceptRate: null, byDay: [], peakHours: [], hotZones: [], waitingOrders: 0,
  };
}

async function courierInsights(env, context) {
  const courier = needCourier(context);
  const stats = await courierStats(env, context);
  const tips = [];
  if (courier.type === 'cargo') {
    if (!stats.counts.new) tips.push({ type: 'idea', title: "Yangi so'rovlar yo'q", text: "Viloyatlar va tarifingizni profil orqali yangilang." });
    else tips.push({ type: 'warning', title: stats.counts.new + ' ta yangi so‘rov', text: "Mijozlarga tezroq javob bering." });
  } else {
    if (!bool(courier.online)) tips.push({ type: 'idea', title: 'Siz offlinesiz', text: "Buyurtma olish uchun onlayn holatni yoqing." });
    else tips.push({ type: 'success', title: 'Onlayn holat yoqilgan', text: "Joylashuvingizni yangilab turing — yaqin buyurtmalar tezroq biriktiriladi." });
  }
  return { tips, generatedAt: now() };
}

async function courierRoutePlan(env, context, url) {
  const courier = needCourier(context);
  const rows = await all(env, ORDER_SELECT + ` WHERE o.courier_id=? AND o.delivery_status IN ('assigned','picked')
    AND o.status<>'cancelled' ORDER BY o.created_at`, [courier.id]);
  const stops = [];
  for (const order of rows) {
    if (order.delivery_status === 'assigned') {
      stops.push({ orderId: order.id, kind: 'pickup', title: order.shop_name, address: order.shop_address || '', lat: order.shop_lat, lon: order.shop_lon });
    }
    stops.push({ orderId: order.id, kind: 'dropoff', title: order.customer_name || 'Xaridor', address: order.address || '', lat: order.lat, lon: order.lon });
  }
  let totalKm = 0;
  let previous = null;
  const output = stops.map((stop) => {
    const legKm = previous && stop.lat != null ? distanceKm(previous.lat, previous.lon, stop.lat, stop.lon) : null;
    if (legKm != null) totalKm += legKm;
    if (stop.lat != null) previous = stop;
    return { ...stop, legKm };
  });
  return { stops: output, totalKm: Math.round(totalKm * 10) / 10 };
}

async function courierCargo(env, context) {
  const courier = needCourier(context);
  const rows = await all(env, CARGO_SELECT + " WHERE x.carrier_id=? ORDER BY (x.status='new') DESC, x.created_at DESC LIMIT 100", [courier.id]);
  return rows.map(serializeCargo);
}

async function updateCourierCargo(env, context, cargoId, input) {
  const courier = needCourier(context);
  const status = str(input.status);
  const allowed = { accepted: 'new', rejected: 'new', done: 'accepted' };
  if (!allowed[status]) throw new HttpError(400, "Status noto'g'ri");
  const cargo = await one(env, 'SELECT * FROM cargo_orders WHERE id=? AND carrier_id=?', [cargoId, courier.id]);
  if (!cargo) throw new HttpError(404, 'Buyurtma topilmadi');
  if (cargo.status !== allowed[status]) throw new HttpError(409, "Buyurtma holati o'zgargan");
  const price = input.price != null && input.price !== '' ? Math.max(0, Math.round(num(input.price))) : cargo.price;
  await run(env, `UPDATE cargo_orders SET status=?, price=?, accepted_at=CASE WHEN ?='accepted' THEN ? ELSE accepted_at END,
    done_at=CASE WHEN ?='done' THEN ? ELSE done_at END, updated_at=? WHERE id=?`, [
    status, price, status, now(), status, now(), now(), cargo.id,
  ]);
  if (status === 'done') await run(env, 'UPDATE couriers SET deliveries=deliveries+1 WHERE id=?', [courier.id]);
  return { ok: true };
}

async function nearbyCouriers(env, url) {
  const lat = Number(url.searchParams.get('lat'));
  const lon = Number(url.searchParams.get('lon'));
  const cutoff = new Date(Date.now() - 60 * 60 * 1000).toISOString();
  const rows = await all(env, `SELECT * FROM couriers WHERE type='courier' AND active=1 AND online=1
    AND (location_at IS NULL OR location_at>?) ORDER BY location_at DESC LIMIT 100`, [cutoff]);
  let output = rows.map((courier) => serializeCourier(courier, Number.isFinite(lat) && Number.isFinite(lon)
    ? { distanceKm: distanceKm(lat, lon, courier.lat, courier.lon) }
    : {}));
  if (Number.isFinite(lat) && Number.isFinite(lon)) {
    output = output.filter((courier) => courier.distanceKm == null || courier.distanceKm <= 50)
      .sort((a, b) => (a.distanceKm ?? 1e9) - (b.distanceKm ?? 1e9));
  }
  return output;
}

async function directCourierRequest(env, context, input) {
  needBuyer(context);
  const courier = await one(env, `SELECT * FROM couriers WHERE id=? AND active=1 AND type='courier'`, [str(input.courierId)]);
  if (!courier) throw new HttpError(404, 'Kuryer topilmadi');
  const id = newId('g_');
  const stamp = now();
  await run(env, `INSERT INTO cargo_orders(
    id,user_id,carrier_id,kind,status,from_region,to_region,cargo,customer_name,phone,address,created_at,updated_at
  ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)`, [
    id, context.user.id, courier.id, 'direct', 'new', str(input.from).trim(), str(input.to).trim(), str(input.note).trim(),
    str(input.name).trim() || context.user.name, str(input.phone).trim(), str(input.from).trim(), stamp, stamp,
  ]);
  return { ok: true, id };
}

async function cargoCarriers(env, url) {
  const from = str(url.searchParams.get('from')).trim();
  const to = str(url.searchParams.get('to')).trim();
  const rows = await all(env, `SELECT * FROM couriers WHERE active=1 AND type='cargo' ORDER BY online DESC, deliveries DESC LIMIT 200`);
  const km = from && to ? regionRouteKm(from, to) : null;
  return rows.filter((courier) => {
    const regions = parseList(courier.regions);
    return (!from || regions.includes(from)) && (!to || regions.includes(to));
  }).map((courier) => serializeCourier(courier, {
    routeKm: km, estimatedPrice: km == null ? null : tariffPrice(courier.base_price, courier.price_per_km, km),
  }));
}

async function myCargo(env, context) {
  needBuyer(context);
  const rows = await all(env, CARGO_SELECT + ' WHERE x.user_id=? ORDER BY x.created_at DESC LIMIT 100', [context.user.id]);
  return rows.map(serializeCargo);
}

async function createCargoOrder(env, context, input) {
  needBuyer(context);
  const carrier = await one(env, `SELECT * FROM couriers WHERE id=? AND type='cargo' AND active=1`, [str(input.carrierId)]);
  if (!carrier) throw new HttpError(404, 'Yuk tashuvchi topilmadi');
  const from = str(input.fromRegion).trim();
  const to = str(input.toRegion).trim();
  if (!from || !to) throw new HttpError(400, 'Qayerdan va qayerga ekanini tanlang');
  const id = newId('g_');
  const stamp = now();
  await run(env, `INSERT INTO cargo_orders(
    id,user_id,carrier_id,kind,status,from_region,to_region,date,cargo,weight_kg,customer_name,phone,address,created_at,updated_at
  ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`, [
    id, context.user.id, carrier.id, 'cargo', 'new', from, to, str(input.date).trim(), str(input.cargo).trim(),
    Math.max(0, Math.round(num(input.weightKg))), str(input.name).trim() || context.user.name, str(input.phone).trim(),
    str(input.address).trim(), stamp, stamp,
  ]);
  return { ok: true, id };
}

async function routeProxy(url) {
  const parse = (value) => {
    const parts = str(value).split(',').map(Number);
    return parts.length === 2 && parts.every(Number.isFinite) ? parts : null;
  };
  const from = parse(url.searchParams.get('from'));
  const to = parse(url.searchParams.get('to'));
  if (!from || !to) throw new HttpError(400, "from/to noto'g'ri");
  const profile = url.searchParams.get('profile') === 'foot' ? 'foot' : 'driving';
  let response;
  try {
    response = await fetch('https://router.project-osrm.org/route/v1/' + profile + '/' + from[1] + ',' + from[0] + ';' + to[1] + ',' + to[0] + '?overview=full&geometries=geojson&steps=true');
  } catch {
    throw new HttpError(502, 'Marshrut xizmati javob bermadi');
  }
  const data = await response.json().catch(() => null);
  const route = data && data.routes && data.routes[0];
  if (!route) throw new HttpError(404, 'Marshrut topilmadi');
  return {
    geometry: (route.geometry && route.geometry.coordinates) || [], distance: route.distance, duration: route.duration,
    steps: ((route.legs && route.legs[0] && route.legs[0].steps) || []).map((step) => ({
      location: step.maneuver && step.maneuver.location, type: step.maneuver && step.maneuver.type,
      modifier: step.maneuver && step.maneuver.modifier, exit: step.maneuver && step.maneuver.exit, name: step.name, distance: step.distance,
    })),
  };
}

function adminPage(url, fallback = 30) {
  const page = Math.max(1, Math.floor(num(url.searchParams.get('page'), 1)));
  const limit = limitOf(url.searchParams.get('limit'), fallback, 100);
  return { page, limit, offset: (page - 1) * limit };
}

function adminOrder(row) {
  return {
    id: row.id, shopId: row.shop_id, shop: row.shop_name || '', items: parseList(row.items), productName: row.product_name,
    customerName: row.customer_name, phone: row.phone, buyerId: row.user_id == null ? null : -num(row.user_id),
    price: num(row.price), status: row.status, createdAt: row.created_at,
  };
}

async function adminLogin(env, input) {
  if (!env.ADMIN_PASSWORD) throw new HttpError(503, 'Admin paroli hali Worker Secret sifatida sozlanmagan');
  if (!str(input.password) || input.password !== env.ADMIN_PASSWORD) throw new HttpError(401, "Parol noto'g'ri");
  const token = newToken();
  await run(env, 'INSERT INTO admin_sessions(token, created_at, expires_at) VALUES(?,?,?)', [token, now(), new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString()]);
  return { token };
}

async function adminContext(request, env) {
  const match = (request.headers.get('authorization') || '').match(/^Bearer\s+(.+)$/i);
  const session = match ? await one(env, 'SELECT * FROM admin_sessions WHERE token=? AND expires_at>?', [match[1], now()]) : null;
  if (!session) throw new HttpError(401, 'Kirish talab qilinadi');
  return session;
}

async function adminOverview(env) {
  const day = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const week = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
  const prevWeek = new Date(Date.now() - 14 * 24 * 60 * 60 * 1000).toISOString();
  const orders = await one(env, `SELECT COUNT(*) AS total,
    SUM(CASE WHEN created_at>=? THEN 1 ELSE 0 END) AS today,
    SUM(CASE WHEN created_at>=? THEN 1 ELSE 0 END) AS week,
    SUM(CASE WHEN created_at>=? AND created_at<? THEN 1 ELSE 0 END) AS prev_week,
    SUM(CASE WHEN status='new' THEN 1 ELSE 0 END) AS s_new,
    SUM(CASE WHEN status='done' THEN 1 ELSE 0 END) AS s_done,
    SUM(CASE WHEN status='cancelled' THEN 1 ELSE 0 END) AS s_cancelled,
    COALESCE(SUM(CASE WHEN status='done' THEN price ELSE 0 END),0) AS rev_total,
    COALESCE(SUM(CASE WHEN status='done' AND created_at>=? THEN price ELSE 0 END),0) AS rev_week,
    COALESCE(SUM(CASE WHEN status='done' AND created_at>=? AND created_at<? THEN price ELSE 0 END),0) AS rev_prev_week,
    COALESCE(SUM(CASE WHEN status='done' AND created_at>=? THEN price ELSE 0 END),0) AS rev_today,
    COALESCE(AVG(CASE WHEN status='done' THEN price END),0) AS avg_order FROM orders`, [day, week, prevWeek, week, week, prevWeek, week, day]);
  const shops = await one(env, `SELECT COUNT(*) AS total, SUM(CASE WHEN created_at>=? THEN 1 ELSE 0 END) AS week,
    SUM(CASE WHEN created_at>=? AND created_at<? THEN 1 ELSE 0 END) AS prev_week,
    SUM(CASE WHEN lat IS NOT NULL THEN 1 ELSE 0 END) AS with_location FROM shops`, [week, prevWeek, week]);
  const products = await one(env, `SELECT COUNT(*) AS total, SUM(CASE WHEN active=1 THEN 1 ELSE 0 END) AS active,
    COALESCE(SUM(views),0) AS views FROM products`);
  const users = await one(env, `SELECT COUNT(*) AS total, SUM(CASE WHEN registered_at IS NOT NULL THEN 1 ELSE 0 END) AS buyers,
    SUM(CASE WHEN registered_at IS NULL THEN 1 ELSE 0 END) AS guests,
    SUM(CASE WHEN last_seen>=? THEN 1 ELSE 0 END) AS active_week FROM users`, [week]);
  const couriers = await one(env, `SELECT COUNT(*) AS total, SUM(CASE WHEN online=1 THEN 1 ELSE 0 END) AS online,
    SUM(CASE WHEN type='courier' THEN 1 ELSE 0 END) AS courier,
    SUM(CASE WHEN type='cargo' THEN 1 ELSE 0 END) AS cargo FROM couriers`);
  const verified = await one(env, `SELECT
    (SELECT COUNT(*) FROM users WHERE email_verified_at IS NOT NULL) +
    (SELECT COUNT(*) FROM shops WHERE email_verified_at IS NOT NULL) +
    (SELECT COUNT(*) FROM couriers WHERE email_verified_at IS NOT NULL) AS n,
    (SELECT COUNT(*) FROM email_codes WHERE expires_at>?) AS pending`, [now()]);
  const growth = (current, previous) => num(previous) > 0 ? Math.round((num(current) - num(previous)) * 1000 / num(previous)) / 10 : num(current) > 0 ? 100 : 0;
  const closed = num(orders.s_done) + num(orders.s_cancelled);
  return {
    generatedAt: now(),
    revenue: { total: num(orders.rev_total), week: num(orders.rev_week), growth: growth(orders.rev_week, orders.rev_prev_week), avgOrder: Math.round(num(orders.avg_order)), today: num(orders.rev_today) },
    orders: { total: num(orders.total), today: num(orders.today), week: num(orders.week), growth: growth(orders.week, orders.prev_week), status: { new: num(orders.s_new), done: num(orders.s_done), cancelled: num(orders.s_cancelled) } },
    shops: { total: num(shops.total), week: num(shops.week), withLocation: num(shops.with_location), growth: growth(shops.week, shops.prev_week) },
    products: { total: num(products.total), active: num(products.active), hidden: num(products.total) - num(products.active), views: num(products.views) },
    users: { total: num(users.buyers) + num(shops.total), buyers: num(users.buyers), sellers: num(shops.total), telegram: 0, app: num(users.buyers) + num(shops.total), activeWeek: num(users.active_week), guests: num(users.guests) },
    registrations: {
      buyers: num(users.buyers), guests: num(users.guests), sellers: num(shops.total), couriers: num(couriers.courier), carriers: num(couriers.cargo),
      verifiedEmails: num(verified.n), pendingCodes: num(verified.pending),
      week: { buyers: 0, sellers: num(shops.week), couriers: 0, carriers: 0 },
    },
    conversion: num(products.views) ? Math.round(num(orders.total) * 1000 / num(products.views)) / 10 : 0,
    couriers: { total: num(couriers.total), online: num(couriers.online) },
    doneRate: closed ? Math.round(num(orders.s_done) * 100 / closed) : 0,
    cancelRate: closed ? Math.round(num(orders.s_cancelled) * 100 / closed) : 0,
  };
}

async function adminTimeseries(env, url) {
  const days = Math.min(365, Math.max(1, Math.floor(num(url.searchParams.get('days'), 30))));
  const start = new Date(Date.now() - (days - 1) * 24 * 60 * 60 * 1000);
  const [orders, shops, products] = await Promise.all([
    all(env, 'SELECT status, price, created_at FROM orders WHERE created_at>=?', [start.toISOString()]),
    all(env, 'SELECT created_at FROM shops WHERE created_at>=?', [start.toISOString()]),
    all(env, 'SELECT created_at FROM products WHERE created_at>=?', [start.toISOString()]),
  ]);
  const data = new Map();
  for (let index = 0; index < days; index += 1) {
    const date = new Date(start.getTime() + index * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);
    data.set(date, { date, revenue: 0, done: 0, cancelled: 0, shops: 0, products: 0 });
  }
  for (const order of orders) {
    const row = data.get(str(order.created_at).slice(0, 10));
    if (!row) continue;
    if (order.status === 'done') { row.done += 1; row.revenue += num(order.price); }
    if (order.status === 'cancelled') row.cancelled += 1;
  }
  for (const shop of shops) { const row = data.get(str(shop.created_at).slice(0, 10)); if (row) row.shops += 1; }
  for (const product of products) { const row = data.get(str(product.created_at).slice(0, 10)); if (row) row.products += 1; }
  return [...data.values()];
}

async function adminShops(env, url) {
  const { page, limit, offset } = adminPage(url, 25);
  const q = str(url.searchParams.get('q')).trim();
  const status = url.searchParams.get('status');
  const params = [];
  let where = 'WHERE 1=1';
  if (q) {
    const like = '%' + q + '%';
    where += ' AND (s.name LIKE ? COLLATE NOCASE OR s.login LIKE ? COLLATE NOCASE OR s.phone LIKE ? OR s.owner_name LIKE ? COLLATE NOCASE OR s.email LIKE ? COLLATE NOCASE)';
    params.push(like, like, like, like, like);
  }
  if (status === 'active') where += ' AND s.active=1';
  if (status === 'blocked') where += ' AND s.active=0';
  const total = num((await one(env, 'SELECT COUNT(*) AS n FROM shops s ' + where, params)).n);
  const order = url.searchParams.get('sort') === 'name' ? 's.name COLLATE NOCASE ASC' : 's.created_at DESC';
  const rows = await all(env, `SELECT s.*,
    (SELECT COUNT(*) FROM products p WHERE p.shop_id=s.id) AS products,
    (SELECT COALESCE(SUM(views),0) FROM products p WHERE p.shop_id=s.id) AS views,
    (SELECT COUNT(*) FROM orders o WHERE o.shop_id=s.id) AS orders,
    (SELECT COUNT(*) FROM orders o WHERE o.shop_id=s.id AND o.status='done') AS done,
    (SELECT COALESCE(SUM(price),0) FROM orders o WHERE o.shop_id=s.id AND o.status='done') AS revenue,
    (SELECT MAX(created_at) FROM orders o WHERE o.shop_id=s.id) AS last_order_at
    FROM shops s ` + where + ' ORDER BY ' + order + ' LIMIT ? OFFSET ?', [...params, limit, offset]);
  return {
    total, page, limit,
    items: rows.map((row) => ({
      id: row.id, name: row.name, logo: row.logo, hasLocation: row.lat != null, login: row.login, ownerName: row.owner_name || '', phone: row.phone || '',
      createdAt: row.created_at, region: row.region || '', email: row.email || '', emailVerified: Boolean(row.email_verified_at), active: bool(row.active),
      aiName: row.seller_name || 'Madina', products: num(row.products), views: num(row.views), orders: num(row.orders), done: num(row.done),
      revenue: num(row.revenue), sellers: 1, lastOrderAt: row.last_order_at || null,
    })),
  };
}

async function adminProducts(env, url) {
  const { page, limit, offset } = adminPage(url, 30);
  const q = str(url.searchParams.get('q')).trim();
  const active = url.searchParams.get('active');
  const params = [];
  let where = 'WHERE 1=1';
  if (q) { const like = '%' + q + '%'; where += ' AND (p.name LIKE ? COLLATE NOCASE OR s.name LIKE ? COLLATE NOCASE)'; params.push(like, like); }
  if (active === '1') where += ' AND p.active=1';
  if (active === '0') where += ' AND p.active=0';
  const total = num((await one(env, 'SELECT COUNT(*) AS n FROM products p JOIN shops s ON s.id=p.shop_id ' + where, params)).n);
  const sort = { views: 'p.views DESC', price: 'p.price DESC', priceAsc: 'p.price ASC' }[url.searchParams.get('sort')] || 'p.created_at DESC';
  const rows = await all(env, `SELECT p.*, s.name AS shop FROM products p JOIN shops s ON s.id=p.shop_id ` + where + ' ORDER BY ' + sort + ' LIMIT ? OFFSET ?', [...params, limit, offset]);
  return { total, page, limit, items: rows.map((row) => ({
    id: row.id, name: row.name, description: row.description || '', photos: parseList(row.photos), shopId: row.shop_id, shop: row.shop || '',
    price: num(row.price), views: num(row.views), active: bool(row.active), createdAt: row.created_at,
  })) };
}

async function adminOrders(env, url) {
  const { page, limit, offset } = adminPage(url, 30);
  const q = str(url.searchParams.get('q')).trim();
  const status = ['new', 'done', 'cancelled'].includes(url.searchParams.get('status')) ? url.searchParams.get('status') : null;
  const from = /^\\d{4}-\\d{2}-\\d{2}$/.test(str(url.searchParams.get('from'))) ? url.searchParams.get('from') : null;
  const to = /^\\d{4}-\\d{2}-\\d{2}$/.test(str(url.searchParams.get('to'))) ? url.searchParams.get('to') : null;
  const params = [];
  let where = 'WHERE 1=1';
  if (q) { const like = '%' + q + '%'; where += ' AND (o.customer_name LIKE ? COLLATE NOCASE OR o.phone LIKE ? OR s.name LIKE ? COLLATE NOCASE OR o.product_name LIKE ? COLLATE NOCASE OR o.id LIKE ?)'; params.push(like, like, like, like, like); }
  if (status) { where += ' AND o.status=?'; params.push(status); }
  if (from) { where += ' AND substr(o.created_at,1,10)>=?'; params.push(from); }
  if (to) { where += ' AND substr(o.created_at,1,10)<=?'; params.push(to); }
  const aggregate = await one(env, 'SELECT COUNT(*) AS n, COALESCE(SUM(o.price),0) AS sum FROM orders o JOIN shops s ON s.id=o.shop_id ' + where, params);
  const rows = await all(env, 'SELECT o.*, s.name AS shop_name FROM orders o JOIN shops s ON s.id=o.shop_id ' + where + ' ORDER BY o.created_at DESC LIMIT ? OFFSET ?', [...params, limit, offset]);
  return { total: num(aggregate.n), sum: num(aggregate.sum), page, limit, items: rows.map(adminOrder) };
}

async function adminCouriers(env, url) {
  const { page, limit, offset } = adminPage(url, 30);
  const q = str(url.searchParams.get('q')).trim();
  const type = ['courier', 'cargo'].includes(url.searchParams.get('type')) ? url.searchParams.get('type') : null;
  const status = url.searchParams.get('status');
  const online = url.searchParams.get('online') === '1';
  const params = [];
  let where = 'WHERE 1=1';
  if (q) {
    const like = '%' + q + '%';
    where += ' AND (c.name LIKE ? COLLATE NOCASE OR c.login LIKE ? COLLATE NOCASE OR c.phone LIKE ? OR c.email LIKE ? COLLATE NOCASE OR c.region LIKE ? COLLATE NOCASE OR c.plate LIKE ? COLLATE NOCASE)';
    params.push(like, like, like, like, like, like);
  }
  if (type) { where += ' AND c.type=?'; params.push(type); }
  if (online) where += ' AND c.online=1';
  if (status === 'active') where += ' AND c.active=1';
  if (status === 'blocked') where += ' AND c.active=0';
  const total = num((await one(env, 'SELECT COUNT(*) AS n FROM couriers c ' + where, params)).n);
  const onlineCount = num((await one(env, 'SELECT COUNT(*) AS n FROM couriers WHERE online=1')).n);
  const rows = await all(env, `SELECT c.*,
    (SELECT COUNT(*) FROM orders o WHERE o.courier_id=c.id AND o.delivery_status IN ('assigned','picked')) AS active_orders
    FROM couriers c ` + where + ' ORDER BY c.online DESC, c.created_at DESC LIMIT ? OFFSET ?', [...params, limit, offset]);
  return {
    total, online: onlineCount, page, limit,
    items: rows.map((row) => ({
      id: row.id, name: row.name, type: row.type, login: row.login, phone: row.phone, email: row.email, emailVerified: Boolean(row.email_verified_at),
      active: bool(row.active), region: row.region, plate: row.plate, online: bool(row.online), vehicle: row.vehicle, vehicleType: row.vehicle_type,
      capacityKg: num(row.capacity_kg), regions: parseList(row.regions), basePrice: num(row.base_price), pricePerKm: num(row.price_per_km),
      deliveries: num(row.deliveries), rating: num(row.rating, 5), location: row.lat != null ? { lat: num(row.lat), lon: num(row.lon), updatedAt: row.location_at } : null,
      createdAt: row.created_at, lastLoginAt: row.last_login_at, activeOrders: num(row.active_orders),
    })),
  };
}

function accountRow(row) {
  return {
    id: row.id, kind: row.kind, rawId: row.rawId, role: row.role, name: row.name, firstName: row.firstName || '', lastName: row.lastName || '',
    fullName: [row.firstName, row.lastName].filter(Boolean).join(' ') || row.name, phone: row.phone || '', email: row.email || '',
    telegram: row.telegram || '', login: row.login || '', region: row.region || '', emailVerified: Boolean(row.emailVerified), active: row.active !== false,
    shopId: row.shopId || null, shop: row.shop || null, aiName: row.aiName || '', vehicle: row.vehicle || '',
    orders: num(row.orders), amount: num(row.amount), lastActivity: row.lastActivity || null, createdAt: row.createdAt,
  };
}

async function allAccounts(env) {
  const [users, shops, couriers] = await Promise.all([
    all(env, `SELECT u.*, (SELECT COUNT(*) FROM orders o WHERE o.user_id=u.id) AS orders,
      (SELECT COALESCE(SUM(price),0) FROM orders o WHERE o.user_id=u.id AND o.status='done') AS amount
      FROM users u WHERE u.registered_at IS NOT NULL`),
    all(env, `SELECT s.*, (SELECT COUNT(*) FROM orders o WHERE o.shop_id=s.id) AS orders,
      (SELECT COALESCE(SUM(price),0) FROM orders o WHERE o.shop_id=s.id AND o.status='done') AS amount FROM shops s`),
    all(env, `SELECT c.*, CASE WHEN c.type='cargo' THEN (SELECT COUNT(*) FROM cargo_orders x WHERE x.carrier_id=c.id)
      ELSE (SELECT COUNT(*) FROM orders o WHERE o.courier_id=c.id AND o.delivery_status='delivered') END AS orders,
      CASE WHEN c.type='cargo' THEN (SELECT COALESCE(SUM(price),0) FROM cargo_orders x WHERE x.carrier_id=c.id AND x.status='done')
      ELSE (SELECT COALESCE(SUM(delivery_fee),0) FROM orders o WHERE o.courier_id=c.id AND o.delivery_status='delivered') END AS amount FROM couriers c`),
  ]);
  return [
    ...users.map((row) => accountRow({
      id: 'u' + row.id, kind: 'user', rawId: String(row.id), role: 'buyer', name: row.name, firstName: row.first_name, lastName: row.last_name,
      phone: row.phone, email: row.email, telegram: row.telegram, emailVerified: Boolean(row.email_verified_at), active: !bool(row.blocked),
      orders: row.orders, amount: row.amount, lastActivity: row.last_seen, createdAt: row.created_at,
    })),
    ...shops.map((row) => accountRow({
      id: row.id, kind: 'shop', rawId: row.id, role: 'seller', name: row.name, firstName: row.first_name, lastName: row.last_name, phone: row.phone,
      email: row.email, login: row.login, region: row.region, emailVerified: Boolean(row.email_verified_at), active: bool(row.active),
      shopId: row.id, shop: row.name, aiName: row.seller_name || 'Madina', orders: row.orders, amount: row.amount,
      lastActivity: row.last_login_at, createdAt: row.created_at,
    })),
    ...couriers.map((row) => accountRow({
      id: row.id, kind: 'courier', rawId: row.id, role: row.type, name: row.name, firstName: row.first_name, lastName: row.last_name, phone: row.phone,
      email: row.email, login: row.login, region: row.region, emailVerified: Boolean(row.email_verified_at), active: bool(row.active),
      vehicle: row.type === 'cargo' ? row.vehicle_type : row.vehicle, orders: row.orders, amount: row.amount,
      lastActivity: row.location_at || row.last_login_at, createdAt: row.created_at,
    })),
  ];
}

async function adminUsers(env, url) {
  const { page, limit, offset } = adminPage(url, 30);
  const q = str(url.searchParams.get('q')).trim().toLowerCase();
  const role = ['buyer', 'seller', 'courier', 'cargo'].includes(url.searchParams.get('role')) ? url.searchParams.get('role') : null;
  const verified = url.searchParams.get('verified');
  const status = url.searchParams.get('status');
  const allRows = await allAccounts(env);
  const items = allRows.filter((row) => {
    const searchable = [row.name, row.firstName, row.lastName, row.phone, row.email, row.login, row.telegram, row.shop, row.region].join(' ').toLowerCase();
    return (!q || searchable.includes(q))
      && (!role || row.role === role)
      && (verified === '' || verified == null || (verified === '1') === row.emailVerified)
      && (status === '' || status == null || (status === 'active') === row.active);
  }).sort((a, b) => str(b.createdAt).localeCompare(str(a.createdAt)));
  return {
    total: items.length, page, limit, items: items.slice(offset, offset + limit),
    counts: {
      buyer: allRows.filter((row) => row.role === 'buyer').length, seller: allRows.filter((row) => row.role === 'seller').length,
      courier: allRows.filter((row) => row.role === 'courier').length, cargo: allRows.filter((row) => row.role === 'cargo').length,
      guests: num((await one(env, 'SELECT COUNT(*) AS n FROM users WHERE registered_at IS NULL')).n), all: allRows.length,
    },
  };
}

async function adminAccountDetail(env, kind, id) {
  if (kind === 'user') {
    const user = await one(env, 'SELECT * FROM users WHERE id=?', [num(id)]);
    if (!user) throw new HttpError(404, 'Foydalanuvchi topilmadi');
    const orders = await all(env, 'SELECT o.*, s.name AS shop_name FROM orders o LEFT JOIN shops s ON s.id=o.shop_id WHERE o.user_id=? ORDER BY o.created_at DESC LIMIT 20', [user.id]);
    return {
      account: {
        id: 'u' + user.id, kind, rawId: String(user.id), role: 'buyer', name: user.name, firstName: user.first_name || '', lastName: user.last_name || '',
        phone: user.phone || '', email: user.email || '', telegram: user.telegram || '', emailVerified: Boolean(user.email_verified_at), active: !bool(user.blocked),
        createdAt: user.created_at, registeredAt: user.registered_at, lastActivity: user.last_seen, interests: parseJson(user.interests, {}),
      },
      orders: orders.map(adminOrder),
    };
  }
  if (kind === 'shop') {
    const shop = await one(env, 'SELECT * FROM shops WHERE id=?', [id]);
    if (!shop) throw new HttpError(404, "Do'kon topilmadi");
    const [orders, products, revenue] = await Promise.all([
      all(env, 'SELECT o.*, s.name AS shop_name FROM orders o JOIN shops s ON s.id=o.shop_id WHERE o.shop_id=? ORDER BY o.created_at DESC LIMIT 20', [id]),
      one(env, 'SELECT COUNT(*) AS n FROM products WHERE shop_id=?', [id]),
      one(env, "SELECT COALESCE(SUM(price),0) AS n FROM orders WHERE shop_id=? AND status='done'", [id]),
    ]);
    return {
      account: {
        id: shop.id, kind, rawId: shop.id, role: 'seller', name: shop.name, firstName: shop.first_name || '', lastName: shop.last_name || '',
        phone: shop.phone, email: shop.email, login: shop.login, region: shop.region, aiName: shop.seller_name || 'Madina', logo: shop.logo,
        emailVerified: Boolean(shop.email_verified_at), active: bool(shop.active), createdAt: shop.created_at, lastLoginAt: shop.last_login_at,
        location: shop.lat != null ? { lat: num(shop.lat), lon: num(shop.lon), address: shop.address || '' } : null,
        products: num(products.n), revenue: num(revenue.n),
      },
      orders: orders.map(adminOrder),
    };
  }
  if (kind === 'courier') {
    const courier = await one(env, 'SELECT * FROM couriers WHERE id=?', [id]);
    if (!courier) throw new HttpError(404, 'Kuryer topilmadi');
    const orders = courier.type === 'cargo'
      ? (await all(env, 'SELECT * FROM cargo_orders WHERE carrier_id=? ORDER BY created_at DESC LIMIT 20', [id])).map((row) => ({
        id: row.id, status: row.status, productName: row.from_region + ' → ' + row.to_region, customerName: row.customer_name, phone: row.phone, price: num(row.price), createdAt: row.created_at,
      }))
      : (await all(env, 'SELECT o.*, s.name AS shop_name FROM orders o LEFT JOIN shops s ON s.id=o.shop_id WHERE o.courier_id=? ORDER BY o.created_at DESC LIMIT 20', [id])).map(adminOrder);
    return {
      account: {
        id: courier.id, kind, rawId: courier.id, role: courier.type, name: courier.name, firstName: courier.first_name, lastName: courier.last_name,
        phone: courier.phone, email: courier.email, login: courier.login, region: courier.region, plate: courier.plate, photo: courier.photo,
        vehicle: courier.vehicle, vehicleType: courier.vehicle_type, capacityKg: num(courier.capacity_kg), regions: parseList(courier.regions),
        basePrice: num(courier.base_price), pricePerKm: num(courier.price_per_km), online: bool(courier.online), deliveries: num(courier.deliveries),
        emailVerified: Boolean(courier.email_verified_at), active: bool(courier.active), createdAt: courier.created_at, lastLoginAt: courier.last_login_at,
        location: courier.lat != null ? { lat: num(courier.lat), lon: num(courier.lon), updatedAt: courier.location_at } : null,
      }, orders,
    };
  }
  throw new HttpError(400, "Noto'g'ri hisob turi");
}

async function adminSetActive(env, kind, id, active) {
  if (kind === 'user') {
    const result = await run(env, 'UPDATE users SET blocked=? WHERE id=?', [active ? 0 : 1, num(id)]);
    if (!num(result.meta && result.meta.changes)) throw new HttpError(404, 'Foydalanuvchi topilmadi');
    if (!active) await run(env, 'DELETE FROM sessions WHERE user_id=?', [num(id)]);
  } else if (kind === 'shop') {
    const result = await run(env, 'UPDATE shops SET active=? WHERE id=?', [active ? 1 : 0, id]);
    if (!num(result.meta && result.meta.changes)) throw new HttpError(404, "Do'kon topilmadi");
    if (!active) await run(env, 'UPDATE sessions SET shop_id=NULL, updated_at=? WHERE shop_id=?', [now(), id]);
  } else if (kind === 'courier') {
    const result = await run(env, 'UPDATE couriers SET active=?, online=CASE WHEN ?=1 THEN online ELSE 0 END WHERE id=?', [active ? 1 : 0, active ? 1 : 0, id]);
    if (!num(result.meta && result.meta.changes)) throw new HttpError(404, 'Kuryer topilmadi');
    if (!active) await run(env, 'UPDATE sessions SET courier_id=NULL, updated_at=? WHERE courier_id=?', [now(), id]);
  } else throw new HttpError(400, "Noto'g'ri hisob turi");
  return { ok: true, active };
}

/// Cloudflare bepul rejasining chegaralari. Panel "qancha to'lgan" ni shu
/// qiymatlarga nisbatan ko'rsatadi.
const D1_LIMIT_BYTES = 5 * 1024 * 1024 * 1024;
const R2_LIMIT_BYTES = 10 * 1024 * 1024 * 1024;
const D1_DAILY_WRITES = 100000;
const D1_DAILY_READS = 5000000;

/// Bazadagi barcha jadvallar — qaysi biri joyni egallayotgani ko'rinsin.
const COUNTED_TABLES = ['users', 'sessions', 'shops', 'products', 'orders', 'couriers',
  'cargo_orders', 'follows', 'product_likes', 'product_views', 'reel_events',
  'chat_messages', 'user_searches', 'notifications', 'media_uploads', 'email_codes',
  'admin_sessions'];

/// Bazaga eng ko'p yozadigan jadvallar: kunlik 100k yozish chegarasi hajmdan
/// oldin shular tufayli tugaydi, shuning uchun alohida kuzatiladi.
const WRITE_TABLES = ['product_views', 'reel_events', 'user_searches', 'chat_messages',
  'orders', 'media_uploads', 'users', 'sessions', 'follows', 'product_likes',
  'notifications'];

const percentOf = (used, limit) => (limit > 0 ? Math.round((used / limit) * 10000) / 100 : 0);

async function adminSystem(env) {
  const today = now().slice(0, 10);
  const from = new Date(Date.now() - 13 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);
  const countSql = 'SELECT ' + COUNTED_TABLES.map((t) => `(SELECT COUNT(*) FROM ${t}) AS ${t}`).join(', ');
  // Kunlik yozuv oqimi. Bitta UNION ALL bo'lib yozilmaydi: D1 birlashgan
  // SELECT terminlari soniga chek qo'yadi (SQLITE_ERROR 7500). batch() esa
  // hammasini bitta murojaatda yuboradi va natijalar JS'da qo'shiladi.
  const [counts, daily, media, probe] = await Promise.all([
    one(env, countSql),
    env.DB.batch(WRITE_TABLES.map((t) => env.DB
      .prepare(`SELECT substr(created_at,1,10) AS d, COUNT(*) AS n FROM ${t} WHERE created_at >= ? GROUP BY 1`)
      .bind(from))),
    one(env, 'SELECT COUNT(*) AS files, COALESCE(SUM(bytes),0) AS bytes FROM media_uploads'),
    // D1 har so'rov javobida bazaning joriy hajmini qaytaradi — alohida
    // hisoblash shart emas, eng arzon so'rov yetadi.
    run(env, 'SELECT 1'),
  ]);

  const tables = COUNTED_TABLES
    .map((name) => ({ name, rows: num(counts && counts[name]) }))
    .sort((a, b) => b.rows - a.rows);
  const rows = tables.reduce((sum, t) => sum + t.rows, 0);
  const d1Used = num(probe && probe.meta && probe.meta.size_after);
  const r2Used = num(media && media.bytes);

  // Bo'sh kunlar ham grafikda ko'rinsin, aks holda chiziq uziladi.
  const byDay = new Map();
  for (const part of daily || []) {
    for (const row of part.results || []) {
      const key = String(row.d);
      byDay.set(key, (byDay.get(key) || 0) + num(row.n));
    }
  }
  const series = [];
  for (let i = 13; i >= 0; i--) {
    const d = new Date(Date.now() - i * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);
    series.push({ date: d, writes: byDay.get(d) || 0 });
  }

  return {
    time: now(),
    platform: 'Cloudflare Workers',
    d1: {
      name: 'saler-db',
      used: d1Used,
      limit: D1_LIMIT_BYTES,
      percent: percentOf(d1Used, D1_LIMIT_BYTES),
      rows,
      tables,
    },
    r2: {
      name: 'saler-media',
      enabled: r2Enabled(env),
      used: r2Used,
      limit: R2_LIMIT_BYTES,
      percent: percentOf(r2Used, R2_LIMIT_BYTES),
      files: num(media && media.files),
    },
    writes: {
      today: byDay.get(today) || 0,
      limit: D1_DAILY_WRITES,
      percent: percentOf(byDay.get(today) || 0, D1_DAILY_WRITES),
    },
    reads: { limit: D1_DAILY_READS },
    daily: series,
    services: {
      database: Boolean(env.DB),
      media: r2Enabled(env) ? 'r2' : 'off',
      email: Boolean(env.BREVO_API_KEY && env.BREVO_SENDER_EMAIL),
      admin: Boolean(env.ADMIN_PASSWORD),
    },
  };
}

async function adminShopDetail(env, id) {
  const shop = await one(env, 'SELECT * FROM shops WHERE id=?', [id]);
  if (!shop) throw new HttpError(404, "Do'kon topilmadi");
  const [stats, productStats, products, orders] = await Promise.all([
    one(env, `SELECT COALESCE(SUM(CASE WHEN status='done' THEN price ELSE 0 END),0) AS revenue,
      COUNT(*) AS total_orders, SUM(CASE WHEN status='new' THEN 1 ELSE 0 END) AS new_orders,
      SUM(CASE WHEN status='done' THEN 1 ELSE 0 END) AS done_orders FROM orders WHERE shop_id=?`, [id]),
    one(env, `SELECT COUNT(*) AS n, SUM(CASE WHEN active=0 THEN 1 ELSE 0 END) AS hidden,
      COALESCE(SUM(views),0) AS views FROM products WHERE shop_id=?`, [id]),
    all(env, 'SELECT * FROM products WHERE shop_id=? ORDER BY created_at DESC', [id]),
    all(env, 'SELECT o.*, s.name AS shop_name FROM orders o JOIN shops s ON s.id=o.shop_id WHERE o.shop_id=? ORDER BY o.created_at DESC LIMIT 100', [id]),
  ]);
  const since = new Date(Date.now() - 29 * 24 * 60 * 60 * 1000);
  const byDay = new Map();
  for (let index = 0; index < 30; index += 1) {
    const date = new Date(since.getTime() + index * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);
    byDay.set(date, { date, n: 0 });
  }
  for (const order of orders) {
    const row = byDay.get(str(order.created_at).slice(0, 10));
    if (row) row.n += 1;
  }
  return {
    shop: {
      id: shop.id, name: shop.name, login: shop.login, logo: shop.logo, ownerName: shop.owner_name || '', sellerName: shop.seller_name || 'Madina',
      aiName: shop.seller_name || 'Madina', firstName: shop.first_name || '', lastName: shop.last_name || '', email: shop.email || '',
      emailVerified: Boolean(shop.email_verified_at), region: shop.region || '', active: bool(shop.active), lastLoginAt: shop.last_login_at,
      createdAt: shop.created_at, phone: shop.phone || '', description: shop.description || '',
      location: shop.lat != null ? { lat: num(shop.lat), lon: num(shop.lon), address: shop.address || '' } : null,
    },
    stats: {
      revenue: num(stats.revenue), totalOrders: num(stats.total_orders), newOrders: num(stats.new_orders), doneOrders: num(stats.done_orders),
      productCount: num(productStats.n), hiddenCount: num(productStats.hidden), views: num(productStats.views),
    },
    byDay: [...byDay.values()], sellers: [{ id: shop.login, name: shop.owner_name || shop.name, username: shop.login, owner: true, lang: 'uz' }],
    products: products.map((product) => ({ id: product.id, name: product.name, photos: parseList(product.photos), active: bool(product.active), price: num(product.price), views: num(product.views), createdAt: product.created_at })),
    orders: orders.map(adminOrder),
  };
}

async function adminAnalytics(env, url) {
  const months = Math.min(24, Math.max(1, Math.floor(num(url.searchParams.get('months'), 6))));
  const since = new Date();
  since.setMonth(since.getMonth() - months);
  const [orders, shops, products] = await Promise.all([
    all(env, 'SELECT * FROM orders WHERE created_at>=?', [since.toISOString()]),
    all(env, 'SELECT * FROM shops'),
    all(env, 'SELECT p.*, s.name AS shop FROM products p JOIN shops s ON s.id=p.shop_id'),
  ]);
  const hours = new Array(24).fill(0);
  const weekdays = new Array(7).fill(0);
  const byMonth = new Map();
  for (const order of orders) {
    const date = new Date(order.created_at);
    if (!Number.isNaN(date.getTime())) {
      hours[date.getUTCHours()] += 1;
      weekdays[date.getUTCDay()] += 1;
    }
    const month = str(order.created_at).slice(0, 7);
    const row = byMonth.get(month) || { month, done: 0, new: 0, cancelled: 0, sumDone: 0, sumTotal: 0 };
    row[order.status] = num(row[order.status]) + 1;
    row.sumTotal += num(order.price);
    if (order.status === 'done') row.sumDone += num(order.price);
    byMonth.set(month, row);
  }
  const shopMap = new Map(shops.map((shop) => [shop.id, { id: shop.id, name: shop.name, done: 0, orders: 0, revenue: 0 }]));
  const customers = new Map();
  const productSales = new Map();
  for (const order of orders) {
    const shop = shopMap.get(order.shop_id);
    if (shop) { shop.orders += 1; if (order.status === 'done') { shop.done += 1; shop.revenue += num(order.price); } }
    if (order.status === 'done') {
      const key = order.phone || order.customer_name || order.id;
      const customer = customers.get(key) || { name: order.customer_name || '—', phone: order.phone || '', sum: 0 };
      customer.sum += num(order.price); customers.set(key, customer);
      for (const item of parseList(order.items)) {
        const itemKey = item.name || item.productId;
        const product = productSales.get(itemKey) || { name: item.name || '—', shop: shop ? shop.name : '', qty: 0 };
        product.qty += num(item.qty, 1); productSales.set(itemKey, product);
      }
    }
  }
  const priceBuckets = [[0, 50000, '< 50 ming'], [50000, 200000, '50–200 ming'], [200000, 500000, '200–500 ming'], [500000, 1000000, '500 ming – 1 mln'], [1000000, 5000000, '1–5 mln'], [5000000, Infinity, '> 5 mln']]
    .map(([low, high, label]) => ({ label, n: products.filter((product) => num(product.price) >= low && num(product.price) < high).length }));
  const shopSizes = [[0, 1, '0'], [1, 5, '1–4'], [5, 20, '5–19'], [20, 50, '20–49'], [50, Infinity, '50+']]
    .map(([low, high, label]) => ({ label, n: shops.filter((shop) => products.filter((product) => product.shop_id === shop.id).length >= low && products.filter((product) => product.shop_id === shop.id).length < high).length }));
  return {
    hours, weekdays, monthly: [...byMonth.values()].sort((a, b) => a.month.localeCompare(b.month)),
    topShops: [...shopMap.values()].sort((a, b) => b.revenue - a.revenue).slice(0, 10),
    topProducts: [...productSales.values()].sort((a, b) => b.qty - a.qty).slice(0, 10),
    topViewed: products.sort((a, b) => num(b.views) - num(a.views)).slice(0, 10).map((product) => ({ name: product.name, shop: product.shop, views: num(product.views) })),
    topCustomers: [...customers.values()].sort((a, b) => b.sum - a.sum).slice(0, 10), priceBuckets, shopSizes,
  };
}



async function adminApi(request, env, url) {
  const method = request.method.toUpperCase();
  const path = url.pathname.slice('/api/admin'.length) || '/';
  const input = ['POST', 'PUT', 'PATCH'].includes(method) ? await body(request) : {};
  if (path === '/login' && method === 'POST') return json(await adminLogin(env, input));
  await adminContext(request, env);
  let match;
  if (path === '/me' && method === 'GET') return json({ ok: true, role: 'admin' });
  if (path === '/overview' && method === 'GET') return json(await adminOverview(env));
  if (path === '/timeseries' && method === 'GET') return json(await adminTimeseries(env, url));
  if (path === '/analytics' && method === 'GET') return json(await adminAnalytics(env, url));
  if (path === '/shops' && method === 'GET') return json(await adminShops(env, url));
  if ((match = path.match(/^\/shops\/([^/]+)$/)) && method === 'GET') return json(await adminShopDetail(env, decodeURIComponent(match[1])));
  if ((match = path.match(/^\/shops\/([^/]+)$/)) && method === 'PATCH') {
    const id = decodeURIComponent(match[1]);
    const active = input.active !== false;
    const result = await run(env, 'UPDATE shops SET active=? WHERE id=?', [active ? 1 : 0, id]);
    if (!num(result.meta && result.meta.changes)) throw new HttpError(404, "Do'kon topilmadi");
    if (!active) await run(env, 'UPDATE sessions SET shop_id=NULL, updated_at=? WHERE shop_id=?', [now(), id]);
    return json({ ok: true, active });
  }
  if ((match = path.match(/^\/shops\/([^/]+)$/)) && method === 'DELETE') {
    const id = decodeURIComponent(match[1]);
    await run(env, 'DELETE FROM orders WHERE shop_id=?', [id]);
    await run(env, 'DELETE FROM products WHERE shop_id=?', [id]);
    await run(env, 'DELETE FROM follows WHERE shop_id=?', [id]);
    await run(env, 'DELETE FROM notifications WHERE shop_id=?', [id]);
    await run(env, 'UPDATE sessions SET shop_id=NULL, updated_at=? WHERE shop_id=?', [now(), id]);
    await run(env, 'DELETE FROM shops WHERE id=?', [id]);
    return json({ ok: true });
  }
  if (path === '/products' && method === 'GET') return json(await adminProducts(env, url));
  if ((match = path.match(/^\/products\/([^/]+)$/)) && method === 'PATCH') {
    const id = decodeURIComponent(match[1]);
    if (typeof input.active === 'boolean') await run(env, 'UPDATE products SET active=?, updated_at=? WHERE id=?', [input.active ? 1 : 0, now(), id]);
    return json({ ok: true });
  }
  if ((match = path.match(/^\/products\/([^/]+)$/)) && method === 'DELETE') {
    await run(env, 'DELETE FROM products WHERE id=?', [decodeURIComponent(match[1])]);
    return json({ ok: true });
  }
  if (path === '/orders' && method === 'GET') return json(await adminOrders(env, url));
  if ((match = path.match(/^\/orders\/([^/]+)$/)) && method === 'PATCH') {
    const status = str(input.status);
    if (!['new', 'done', 'cancelled'].includes(status)) throw new HttpError(400, "Status noto'g'ri");
    await run(env, 'UPDATE orders SET status=?, updated_at=? WHERE id=?', [status, now(), decodeURIComponent(match[1])]);
    return json({ ok: true });
  }
  if (path === '/couriers' && method === 'GET') return json(await adminCouriers(env, url));
  if ((match = path.match(/^\/couriers\/([^/]+)$/)) && method === 'PATCH') return json(await adminSetActive(env, 'courier', decodeURIComponent(match[1]), input.active !== false));
  if ((match = path.match(/^\/couriers\/([^/]+)$/)) && method === 'DELETE') {
    const id = decodeURIComponent(match[1]);
    await run(env, `UPDATE orders SET courier_id=NULL, delivery_status=NULL, updated_at=?
      WHERE courier_id=? AND COALESCE(delivery_status,'')<>'delivered'`, [now(), id]);
    await run(env, 'DELETE FROM couriers WHERE id=?', [id]);
    return json({ ok: true });
  }
  if (path === '/users' && method === 'GET') return json(await adminUsers(env, url));
  if ((match = path.match(/^\/users\/(user|shop|courier)\/([^/]+)$/)) && method === 'GET') return json(await adminAccountDetail(env, match[1], decodeURIComponent(match[2])));
  if ((match = path.match(/^\/users\/(user|shop|courier)\/([^/]+)$/)) && method === 'PATCH') return json(await adminSetActive(env, match[1], decodeURIComponent(match[2]), input.active !== false));
  if (path === '/system' && method === 'GET') return json(await adminSystem(env));
  throw new HttpError(404, "Admin yo'li topilmadi");
}

async function api(request, env, execution, url) {
  const pathname = url.pathname;
  const method = request.method.toUpperCase();
  if (pathname === '/api/admin' || pathname.startsWith('/api/admin/')) return adminApi(request, env, url);
  if (pathname === '/api/auth/guest' && method === 'POST') return json(await authGuest(env, await body(request)));
  if (pathname.startsWith('/api/photo/') && method === 'GET') {
    return mediaResponse(env, decodeURIComponent(pathname.slice('/api/photo/'.length)), request, execution);
  }

  const context = await loadContext(request, env);
  // Har API chaqiruvida yozish o'rniga faqat 15 daqiqada bir marta yangilanadi.
  // Mehmonlar ko'p bo'lganda D1 write yuklamasi keskin kamayadi.
  if (execution && execution.waitUntil) {
    execution.waitUntil(run(env, 'UPDATE users SET last_seen=? WHERE id=? AND (last_seen IS NULL OR last_seen<?)', [
      now(), context.user.id, new Date(Date.now() - 15 * 60 * 1000).toISOString(),
    ]));
  }
  const path = pathname.slice(4);
  if (path === '/media/upload' && method === 'POST') return json(await uploadMedia(request, env, context));
  if (path === '/push/register' && method === 'POST') return json(await registerToken(env, context, await body(request)));
  if (path === '/push/unregister' && method === 'POST') return json(await unregisterToken(env, await body(request)));
  const input = ['POST', 'PUT', 'PATCH'].includes(method) ? await body(request) : {};
  let match;

  if (path === '/me' && method === 'GET') {
    return json({
      user: publicUser(context.user),
      shop: context.shop ? serializeShop(await getShop(env, context.shop.id)) : null,
      courier: context.courier ? serializeCourier(context.courier) : null,
    });
  }
  if (path === '/auth/buyer' && method === 'POST') {
    const result = await createOrUpdateBuyer(env, context, input);
    return json(result.pending || result);
  }
  if (path === '/auth/logout' && method === 'POST') return json(await logout(env, context));
  if (path === '/auth/reset' && method === 'POST') return json(await resetPassword(env, context, input));
  if (path === '/events' && method === 'GET') {
    return cors(new Response('event: hello\\ndata: {\"type\":\"hello\",\"data\":{}}\\n\\n', {
      headers: { 'Content-Type': 'text/event-stream; charset=utf-8', 'Cache-Control': 'no-cache, no-transform' },
    }));
  }

  if (path === '/seller/register' && method === 'POST') return json(await registerSeller(env, context, input));
  if (path === '/seller/login' && method === 'POST') return json(await loginSeller(env, context, input));
  if (path === '/seller/logout' && method === 'POST') {
    await run(env, 'UPDATE sessions SET shop_id=NULL, updated_at=? WHERE token=?', [now(), context.token]);
    return json({ ok: true });
  }
  if (path === '/seller/password' && method === 'POST') return json(await sellerPassword(env, context, input));
  if (path === '/seller/reset' && method === 'POST') return json(await resetSellerData(env, context, input));
  if (path === '/seller/products' && method === 'GET') return json(await sellerProducts(env, context));
  if (path === '/seller/products' && method === 'POST') return json(await createSellerProduct(env, context, input));
  if ((match = path.match(/^\/seller\/products\/([^/]+)$/)) && method === 'PUT') return json(await updateSellerProduct(env, context, decodeURIComponent(match[1]), input));
  if ((match = path.match(/^\/seller\/products\/([^/]+)$/)) && method === 'DELETE') return json(await deleteSellerProduct(env, context, decodeURIComponent(match[1])));
  if (path === '/seller/orders' && method === 'GET') return json(await sellerOrders(env, context));
  if ((match = path.match(/^\/seller\/orders\/([^/]+)$/)) && method === 'PATCH') return json(await updateSellerOrder(env, context, decodeURIComponent(match[1]), input));
  if (path === '/seller/badges' && method === 'GET') return json(await sellerBadges(env, context));
  if (path === '/seller/notifications' && method === 'GET') return json(await sellerNotifications(env, context, url));
  if (path === '/seller/notifications' && method === 'DELETE') {
    const shop = needShop(context);
    await run(env, 'DELETE FROM notifications WHERE shop_id=?', [shop.id]);
    return json({ ok: true });
  }
  if (path === '/seller/shop' && method === 'PUT') return json(await updateSellerShop(env, context, input));
  if (path === '/seller/analytics' && method === 'GET') return json(await sellerAnalytics(env, needShop(context)));
  if (path === '/seller/analytics/ai-summary' && method === 'GET') return json(await sellerAiSummary(env, context));
  if (path === '/seller/advice' && method === 'GET') return json(await sellerAdvice(env, context));
  if (path === '/seller/report' && method === 'POST') return json({ sent: false, url: null });

  if (path === '/courier/register' && method === 'POST') return json(await registerCourier(env, context, input));
  if (path === '/courier/login' && method === 'POST') return json(await loginCourier(env, context, input));
  if (path === '/courier/logout' && method === 'POST') {
    if (context.courier) await run(env, 'UPDATE couriers SET online=0 WHERE id=?', [context.courier.id]);
    await run(env, 'UPDATE sessions SET courier_id=NULL, updated_at=? WHERE token=?', [now(), context.token]);
    return json({ ok: true });
  }
  if (path === '/courier/location' && method === 'POST') return json(await courierLocation(env, context, input));
  if (path === '/courier/profile' && method === 'PUT') return json(await updateCourierProfile(env, context, input));
  if (path === '/courier/orders' && method === 'GET') return json(await courierOrders(env, context));
  if ((match = path.match(/^\/courier\/orders\/([^/]+)$/)) && method === 'PATCH') return json(await updateCourierOrder(env, context, decodeURIComponent(match[1]), input));
  if (path === '/courier/stats' && method === 'GET') return json(await courierStats(env, context));
  if (path === '/courier/ai-insights' && method === 'GET') return json(await courierInsights(env, context));
  if (path === '/courier/route-plan' && method === 'GET') return json(await courierRoutePlan(env, context, url));
  if (path === '/courier/cargo' && method === 'GET') return json(await courierCargo(env, context));
  if ((match = path.match(/^\/courier\/cargo\/([^/]+)$/)) && method === 'PATCH') return json(await updateCourierCargo(env, context, decodeURIComponent(match[1]), input));

  if (path === '/couriers/nearby' && method === 'GET') return json(await nearbyCouriers(env, url));
  if (path === '/courier-requests' && method === 'POST') return json(await directCourierRequest(env, context, input));
  if (path === '/cargo/regions' && method === 'GET') return json(REGIONS);
  if (path === '/cargo/carriers' && method === 'GET') return json(await cargoCarriers(env, url));
  if (path === '/cargo/my' && method === 'GET') return json(await myCargo(env, context));
  if (path === '/cargo/orders' && method === 'POST') return json(await createCargoOrder(env, context, input));
  if (path === '/route' && method === 'GET') return json(await routeProxy(url));

  if (path === '/nearby' && method === 'GET') return json(await nearbyFeed(env, context, url));
  if (path === '/shops' && method === 'GET') return json(await listShops(env, context, url));
  if (path === '/shops-map' && method === 'GET') {
    const rows = await all(env, SHOP_STATS + ' WHERE s.active=1 AND s.lat IS NOT NULL ORDER BY sales DESC');
    return json(rows.map(serializeShop));
  }
  if (path === '/shops-rating' && method === 'GET') {
    const rows = await all(env, SHOP_STATS + ' WHERE s.active=1 ORDER BY sales DESC, product_count DESC, s.created_at ASC LIMIT 100');
    return json(rows.map((shop, index) => serializeShop(shop, { rank: index + 1 })));
  }
  if ((match = path.match(/^\/shops\/([^/]+)\/follow$/)) && method === 'POST') return json(await toggleFollow(env, context, decodeURIComponent(match[1]), true));
  if ((match = path.match(/^\/shops\/([^/]+)\/follow$/)) && method === 'DELETE') return json(await toggleFollow(env, context, decodeURIComponent(match[1]), false));
  if ((match = path.match(/^\/shops\/([^/]+)$/)) && method === 'GET') return json(await shopDetail(env, context, decodeURIComponent(match[1])));
  if ((match = path.match(/^\/categories\/([^/]+)\/products$/)) && method === 'GET') return json(await categoryProducts(env, decodeURIComponent(match[1])));
  if ((match = path.match(/^\/products\/([^/]+)\/related$/)) && method === 'GET') return json(await relatedProducts(env, decodeURIComponent(match[1]), url.searchParams.get('limit')));
  if ((match = path.match(/^\/products\/([^/]+)\/view$/)) && method === 'POST') return json(await viewProduct(env, context, decodeURIComponent(match[1])));
  if ((match = path.match(/^\/products\/([^/]+)\/like$/)) && method === 'POST') return json(await toggleLike(env, context, decodeURIComponent(match[1]), true));
  if ((match = path.match(/^\/products\/([^/]+)\/like$/)) && method === 'DELETE') return json(await toggleLike(env, context, decodeURIComponent(match[1]), false));
  if ((match = path.match(/^\/products\/([^/]+)$/)) && method === 'GET') return json(await productDetail(env, decodeURIComponent(match[1])));

  if (path === '/reels' && method === 'GET') return json(await listReels(env, context, url));
  if ((match = path.match(/^\/reels\/([^/]+)\/view$/)) && method === 'POST') return json(await recordReelView(env, context, decodeURIComponent(match[1]), input));
  if (path === '/me/interests' && method === 'GET') {
    needBuyer(context);
    const interest = await refreshInterests(env, context.user.id);
    return json({ ...interest, updatedAt: now() });
  }
  if (path === '/orders' && method === 'POST') return json(await createOrder(env, context, input));
  if (path === '/my-orders' && method === 'GET') return json(await myOrders(env, context));

  if (path === '/assistant/history' && method === 'GET') return json(await assistantHistory(env, context, 'assistant'));
  if (path === '/assistant/history' && method === 'DELETE') {
    await run(env, "DELETE FROM chat_messages WHERE user_id=? AND scope='assistant'", [context.user.id]);
    return json({ ok: true });
  }
  if (path === '/assistant' && method === 'POST') return json(await simpleAssistant(env, context, input));
  if (path === '/chat/history' && method === 'GET') return json(await assistantHistory(env, context, 'shop:' + str(url.searchParams.get('shopId'))));
  if (path === '/chat/history' && method === 'DELETE') {
    await run(env, 'DELETE FROM chat_messages WHERE user_id=? AND scope=?', [context.user.id, 'shop:' + str(url.searchParams.get('shopId'))]);
    return json({ ok: true });
  }
  if (path === '/chat' && method === 'POST') return json(await shopChat(env, context, input));

  throw new HttpError(404, "Yo'l topilmadi");
}

/// Ulashish havolasi ochilganda ko'rsatiladigan sahifa.
///
/// Telegram, WhatsApp va ijtimoiy tarmoqlar havolani ochmasdan turib uning
/// og: teglarini o'qiydi — shuning uchun mahsulot nomi, narxi va rasmi
/// serverda, HTML ichida beriladi: havola suhbatda kartochka bo'lib chiqadi.
/// Odam bosganda esa ilovaning web versiyasiga o'tkaziladi va u yerdan
/// to'g'ridan to'g'ri buyurtma bera oladi.
function shareLanding(env, url, { title, description, image, target }) {
  const webBase = str(env.WEB_BASE || 'https://saler-web.onrender.com').replace(/\/+$/, '');
  const link = webBase + target;
  const photo = image ? `${url.origin}/api/photo/${encodeURIComponent(image)}` : `${webBase}/icons/Icon-512.png`;
  const html = `<!doctype html>
<html lang="uz">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(title)}</title>
<meta name="description" content="${escapeHtml(description)}">
<meta property="og:type" content="product">
<meta property="og:site_name" content="Rydex">
<meta property="og:title" content="${escapeHtml(title)}">
<meta property="og:description" content="${escapeHtml(description)}">
<meta property="og:image" content="${escapeHtml(photo)}">
<meta property="og:url" content="${escapeHtml(link)}">
<meta name="twitter:card" content="summary_large_image">
<link rel="canonical" href="${escapeHtml(link)}">
<style>
  :root{color-scheme:light}
  body{margin:0;background:#FFFDF5;font-family:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;color:#14161A;
       display:flex;min-height:100vh;align-items:center;justify-content:center;padding:24px}
  .card{max-width:420px;width:100%;background:#fff;border:1px solid #F0E6C0;border-radius:24px;padding:22px;
        box-shadow:0 14px 40px rgba(20,22,26,.07);text-align:center}
  img{width:100%;max-height:300px;object-fit:contain;border-radius:16px;background:#F7F8FA}
  h1{font-size:20px;margin:16px 0 6px;letter-spacing:-.4px}
  p{margin:0;color:#6B7280;font-size:14px}
  a{display:block;margin-top:18px;background:#FEDD06;color:#111;text-decoration:none;font-weight:800;
    padding:16px;border-radius:16px}
</style>
</head>
<body>
  <div class="card">
    <img src="${escapeHtml(photo)}" alt="${escapeHtml(title)}">
    <h1>${escapeHtml(title)}</h1>
    <p>${escapeHtml(description)}</p>
    <a href="${escapeHtml(link)}">Ochish va buyurtma berish</a>
  </div>
  <script>location.replace(${JSON.stringify(link)});</script>
</body>
</html>`;
  return new Response(html, {
    headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'public, max-age=300' },
  });
}

async function shareRoute(env, url, path) {
  let match;
  if ((match = path.match(/^\/p\/([^/]+)$/))) {
    const id = decodeURIComponent(match[1]);
    const product = await one(env, 'SELECT * FROM products WHERE id=?', [id]);
    if (!product) throw new HttpError(404, 'Mahsulot topilmadi');
    const shop = await getShop(env, product.shop_id);
    const photos = parseList(product.photos);
    return shareLanding(env, url, {
      title: str(product.name),
      description: `${num(product.price).toLocaleString('ru-RU')} so'm${shop ? ' · ' + str(shop.name) : ''}`,
      image: photos[0] || null,
      target: `/p/${encodeURIComponent(id)}`,
    });
  }
  if ((match = path.match(/^\/s\/([^/]+)$/))) {
    const id = decodeURIComponent(match[1]);
    const shop = await getShop(env, id);
    if (!shop) throw new HttpError(404, "Do'kon topilmadi");
    return shareLanding(env, url, {
      title: str(shop.name),
      description: str(shop.description) || 'Rydex do\'koni',
      image: shop.photo || shop.logo || null,
      target: `/s/${encodeURIComponent(id)}`,
    });
  }
  return null;
}

export default {
  async fetch(request, env, execution) {
    // HTTP 204 responses are not allowed to contain a body. Returning JSON here
    // makes Cloudflare throw a 1101 error during browser CORS preflight.
    if (request.method === 'OPTIONS') return cors(new Response(null, { status: 204 }));
    const url = new URL(request.url);
    try {
      if (url.pathname === '/' || url.pathname === '/health' || url.pathname === '/api/health') {
        // Production tekshiruvi: nimasi sozlanmaganini bitta so'rovda ko'rish uchun.
        const media = { store: mediaStoreName(env) };
        return json({
          ok: true,
          service: 'Rydex API',
          database: Boolean(env.DB),
          email: Boolean(env.BREVO_API_KEY && env.BREVO_SENDER_EMAIL),
          emailSender: Boolean(env.BREVO_SENDER_EMAIL),
          admin: Boolean(env.ADMIN_PASSWORD),
          push: pushEnabled(env),
          media,
        });
      }
      // Ulashish havolalari: /p/<mahsulot> va /s/<do'kon>
      if (request.method === 'GET' && !url.pathname.startsWith('/api/')) {
        const shared = await shareRoute(env, url, url.pathname);
        if (shared) return shared;
      }
      if (!url.pathname.startsWith('/api/')) throw new HttpError(404, "Yo'l topilmadi");
      return await api(request, env, execution, url);
    } catch (error) {
      const rawError = str(error && error.message);
      const schemaProblem = /no such (?:table|column)|has no column named/i.test(rawError);
      const status = error instanceof HttpError ? error.status : /UNIQUE constraint failed/i.test(rawError) ? 409 : schemaProblem ? 503 : 500;
      const message = error instanceof HttpError
        ? error.message
        : status === 409 ? "Bu ma'lumot allaqachon mavjud"
        : schemaProblem ? "Server bazasi yangilanmoqda. Bir necha daqiqadan keyin qayta urinib ko'ring"
        : "Serverda kutilmagan xato yuz berdi";
      if (!(error instanceof HttpError)) console.error('Unhandled Worker error', error);
      return json({ error: message, ...(schemaProblem ? { needsMigration: true } : {}), ...(error instanceof HttpError ? error.extra : {}) }, { status });
    }
  },
  scheduled(_event, env, execution) {
    execution.waitUntil(cleanupStaleGuestData(env));
    // Kunlik turtki: buyurtma bor, kuryer offline bo'lsa xabar beriladi
    execution.waitUntil(nudgeOfflineCouriers(env).catch((e) => console.error('nudge xato', e)));
  },
};
