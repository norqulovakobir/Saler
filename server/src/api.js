import { Router } from 'express';
import { q, one, all } from './db.js';
import { ah, HttpError, newId, newToken, hashPassword, checkPassword, storeDataUri, distanceKm, shopLevel, shopRating, num, str, log } from './util.js';
import { assistantReply, shopChatReply, sellerAdvice } from './ai.js';
import courierRouter, { serializeCourier, assignCourier } from './courier.js';

const r = Router();

// ---------- serializers ----------
export function serializeShop(s, extra = {}) {
  const sales = num(s.sales);
  return {
    id: s.id, name: s.name, sellerName: s.seller_name, ownerName: s.owner_name, phone: s.phone, logo: s.logo,
    description: s.description, login: s.login,
    location: s.lat != null ? { lat: s.lat, lon: s.lon, address: s.address } : null,
    productCount: num(s.product_count), sales, rating: shopRating(sales), level: shopLevel(sales),
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
});

const SHOP_SQL = `
  SELECT s.*,
    (SELECT count(*) FROM products p WHERE p.shop_id=s.id AND p.active)::int AS product_count,
    (SELECT count(*) FROM orders o WHERE o.shop_id=s.id AND o.status='done' AND NOT o.archived)::int AS sales
  FROM shops s`;
const ORDER_SQL = `
  SELECT o.*, s.name AS shop_name, s.phone AS shop_phone, s.lat AS shop_lat, s.lon AS shop_lon, s.address AS shop_address
  FROM orders o JOIN shops s ON s.id=o.shop_id`;
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
  next();
}));

r.get('/me', ah(async (req, res) => {
  res.json({
    user: { id: req.user.id, name: req.user.name },
    shop: req.shop ? serializeShop(req.shop) : null,
    courier: req.courier ? serializeCourier(req.courier) : null,
  });
}));

// ---------- seller auth ----------
r.post('/seller/register', ah(async (req, res) => {
  const b = req.body || {};
  const login = str(b.login).trim().toLowerCase();
  const password = str(b.password);
  if (!str(b.name).trim()) throw new HttpError(400, "Do'kon nomini kiriting");
  if (login.length < 3) throw new HttpError(400, 'Login kamida 3 belgi');
  if (password.length < 6) throw new HttpError(400, 'Parol kamida 6 belgi');
  if (await one('SELECT 1 FROM shops WHERE login=$1', [login])) throw new HttpError(400, 'Bu login band');
  const id = newId('s_');
  await q(`INSERT INTO shops(id, name, seller_name, owner_name, phone, login, pass_hash) VALUES($1,$2,$3,$4,$5,$6,$7)`,
    [id, str(b.name).trim(), str(b.sellerName).trim(), str(b.ownerName).trim(), str(b.phone).trim(), login, hashPassword(password)]);
  await q('UPDATE sessions SET shop_id=$2, courier_id=NULL WHERE token=$1', [req.session.token, id]);
  res.json({ shop: serializeShop(await getShop(id)) });
}));

r.post('/seller/login', ah(async (req, res) => {
  const login = str(req.body?.login).trim().toLowerCase();
  const s = await one('SELECT * FROM shops WHERE login=$1', [login]);
  if (!s || !checkPassword(str(req.body?.password), s.pass_hash)) throw new HttpError(403, "Login yoki parol noto'g'ri");
  await q('UPDATE sessions SET shop_id=$2, courier_id=NULL WHERE token=$1', [req.session.token, s.id]);
  await q(`INSERT INTO notifications(id, shop_id, type, title, text) VALUES($1,$2,'security','Yangi kirish','Hisobingizga ilova orqali kirildi')`, [newId('n_'), s.id]);
  res.json({ shop: serializeShop(await getShop(s.id)) });
}));

r.post('/seller/logout', ah(async (req, res) => {
  await q('UPDATE sessions SET shop_id=NULL WHERE token=$1', [req.session.token]);
  res.json({ ok: true });
}));

const needShop = (req) => { if (!req.shop) throw new HttpError(403, 'Sotuvchi sifatida kiring'); return req.shop; };

r.post('/seller/password', ah(async (req, res) => {
  const shop = needShop(req);
  const { oldPassword, newPassword } = req.body || {};
  if (!checkPassword(str(oldPassword), shop.pass_hash)) throw new HttpError(400, "Joriy parol noto'g'ri");
  if (str(newPassword).length < 6) throw new HttpError(400, 'Yangi parol kamida 6 belgi');
  await q('UPDATE shops SET pass_hash=$2 WHERE id=$1', [shop.id, hashPassword(newPassword)]);
  await q(`INSERT INTO notifications(id, shop_id, type, title, text) VALUES($1,$2,'security','Parol o''zgartirildi','Do''kon paroli yangilandi')`, [newId('n_'), shop.id]);
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
r.get('/shops', ah(async (req, res) => {
  const qs = `%${str(req.query.q).trim()}%`;
  const rows = await all(`${SHOP_SQL} WHERE s.active AND (s.name ILIKE $1 OR s.description ILIKE $1 OR EXISTS (SELECT 1 FROM products p WHERE p.shop_id=s.id AND p.active AND p.name ILIKE $1)) ORDER BY sales DESC, s.created_at DESC LIMIT 200`, [qs]);
  res.json(rows.map((s) => serializeShop(s)));
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
  res.json({ shop: serializeShop(s), products: products.map(serializeProduct) });
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

r.post('/products/:id/view', ah(async (req, res) => {
  const p = await one('SELECT id, shop_id, views FROM products WHERE id=$1', [req.params.id]);
  if (!p) throw new HttpError(404, 'Mahsulot topilmadi');
  const ins = await one('INSERT INTO product_views(product_id, user_id, shop_id) VALUES($1,$2,$3) ON CONFLICT DO NOTHING RETURNING id', [p.id, req.user.id, p.shop_id]);
  let views = p.views;
  if (ins) views = (await one('UPDATE products SET views=views+1 WHERE id=$1 RETURNING views', [p.id])).views;
  res.json({ views });
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
  await q(`INSERT INTO notifications(id, shop_id, type, title, text, meta) VALUES($1,$2,'order','Yangi buyurtma',$3,$4)`,
    [newId('n_'), shopId, `${customer}: ${productName} — ${price.toLocaleString('ru-RU')} so'm. Tel: ${str(b.phone)}`, JSON.stringify({ orderId: id, mapUrl })]);
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
const parsePrice = (v) => { const n = Math.round(Number(String(v ?? '').replace(/[^\d.]/g, ''))); if (!Number.isFinite(n) || n < 0) throw new HttpError(400, "Narx noto'g'ri"); return n; };
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
  const price = parsePrice(b.price);
  const photos = await storePhotos(b.photos);
  if (!photos.length) throw new HttpError(400, 'Kamida 1 ta rasm yuklang');
  const id = newId('p_');
  await q('INSERT INTO products(id, shop_id, name, category, price, description, photos) VALUES($1,$2,$3,$4,$5,$6,$7)',
    [id, shop.id, name, str(b.category) || null, price, str(b.description).trim(), JSON.stringify(photos)]);
  res.json({ product: serializeProduct(await one('SELECT * FROM products WHERE id=$1', [id])) });
}));

r.put('/seller/products/:id', ah(async (req, res) => {
  const shop = needShop(req);
  const p = await one('SELECT * FROM products WHERE id=$1 AND shop_id=$2', [req.params.id, shop.id]);
  if (!p) throw new HttpError(404, 'Mahsulot topilmadi');
  const b = req.body || {};
  const sets = [], vals = [p.id];
  const set = (col, v) => { vals.push(v); sets.push(`${col}=$${vals.length}`); };
  if (typeof b.active === 'boolean') set('active', b.active);
  if (b.name != null) { const n = str(b.name).trim(); if (!n) throw new HttpError(400, 'Nom bo\'sh'); set('name', n); }
  if (b.price != null) set('price', parsePrice(b.price));
  if (b.description != null) set('description', str(b.description).trim());
  if (b.category != null) set('category', str(b.category) || null);
  if (b.photos != null) { const ph = await storePhotos(b.photos); if (!ph.length) throw new HttpError(400, 'Kamida 1 ta rasm yuklang'); set('photos', JSON.stringify(ph)); }
  if (sets.length) await q(`UPDATE products SET ${sets.join(', ')} WHERE id=$1`, vals);
  res.json({ product: serializeProduct(await one('SELECT * FROM products WHERE id=$1', [p.id])) });
}));

r.delete('/seller/products/:id', ah(async (req, res) => {
  const shop = needShop(req);
  await q('DELETE FROM products WHERE id=$1 AND shop_id=$2', [req.params.id, shop.id]);
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
  if (!['new', 'done', 'cancelled'].includes(status)) throw new HttpError(400, "Status noto'g'ri");
  const o = await one('UPDATE orders SET status=$3 WHERE id=$1 AND shop_id=$2 RETURNING *', [req.params.id, shop.id, status]);
  if (!o) throw new HttpError(404, 'Buyurtma topilmadi');
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
    coalesce(sum(price) FILTER (WHERE status='done'),0)::bigint AS revenue, count(DISTINCT coalesce(phone, customer_name))::int AS customers,
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
  const f = (n) => Number(n).toLocaleString('ru-RU');
  const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const rows = (list, cols) => list.map((x) => `<tr>${cols.map((c) => `<td>${esc(typeof c === 'function' ? c(x) : x[c])}</td>`).join('')}</tr>`).join('');
  res.set('Content-Type', 'text/html; charset=utf-8').send(`<!doctype html><html lang="uz"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${esc(shop.name)} — hisobot</title>
<style>body{font-family:system-ui,sans-serif;margin:24px;color:#111}h1{margin:0 0 4px}small{color:#666}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:12px;margin:20px 0}.card{border:1px solid #ddd;border-radius:10px;padding:12px}.card b{display:block;font-size:22px}table{border-collapse:collapse;width:100%;margin:8px 0 20px}td,th{border-bottom:1px solid #eee;padding:6px 8px;text-align:left;font-size:14px}h2{font-size:17px;margin:20px 0 6px}@media print{button{display:none}}</style></head><body>
<button onclick="print()">PDF sifatida saqlash</button>
<h1>${esc(shop.name)}</h1><small>Hisobot: ${new Date().toLocaleString('ru-RU')} · Daraja: ${shopLevel(shop.sales)} · Sotuvlar: ${shop.sales}</small>
<div class="grid"><div class="card">Jami buyurtma<b>${a.stats.totalOrders}</b></div><div class="card">Daromad (so'm)<b>${f(a.stats.revenue)}</b></div><div class="card">Mijozlar<b>${a.stats.customers}</b></div><div class="card">Sotilgan dona<b>${a.stats.unitsSold}</b></div><div class="card">O'rtacha chek<b>${f(a.stats.avgCheck)}</b></div><div class="card">Ko'rishlar<b>${f(a.stats.views)}</b></div></div>
<h2>Oxirgi 30 kun</h2><table><tr><th>Sana</th><th>Buyurtma</th><th>Daromad</th></tr>${rows(a.byDay30, ['date', 'n', (x) => f(x.sum)])}</table>
<h2>Eng ko'p sotilgan</h2><table><tr><th>Mahsulot</th><th>Dona</th><th>Buyurtma</th><th>Summa</th></tr>${rows(a.topSold, ['name', 'qty', 'orders', (x) => f(x.sum)])}</table>
<h2>Faol mijozlar</h2><table><tr><th>Mijoz</th><th>Telefon</th><th>Buyurtma</th><th>Summa</th></tr>${rows(a.customers, ['name', 'phone', 'orders', (x) => f(x.sum)])}</table>
<h2>Maslahatlar</h2><ul>${a.tips.map((t) => `<li><b>${esc(t.title)}</b> — ${esc(t.text)}</li>`).join('')}</ul>
</body></html>`);
});
