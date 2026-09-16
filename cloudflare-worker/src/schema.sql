-- Saler AI Cloudflare D1 (SQLite) schema.
-- Bu fayl qayta ishga tushirilsa mavjud jadval va ma'lumotlar o'chmaydi.
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL DEFAULT 'Xaridor',
  first_name TEXT NOT NULL DEFAULT '',
  last_name TEXT NOT NULL DEFAULT '',
  phone TEXT UNIQUE,
  email TEXT COLLATE NOCASE UNIQUE,
  telegram TEXT,
  email_verified_at TEXT,
  registered_at TEXT,
  blocked INTEGER NOT NULL DEFAULT 0,
  interests TEXT NOT NULL DEFAULT '{}',
  interests_at TEXT,
  last_seen TEXT,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS sessions (
  token TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  shop_id TEXT,
  courier_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS sessions_user_idx ON sessions(user_id);
CREATE INDEX IF NOT EXISTS sessions_shop_idx ON sessions(shop_id);
CREATE INDEX IF NOT EXISTS sessions_courier_idx ON sessions(courier_id);

CREATE TABLE IF NOT EXISTS admin_sessions (
  token TEXT PRIMARY KEY,
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS email_codes (
  email TEXT COLLATE NOCASE NOT NULL,
  purpose TEXT NOT NULL,
  code_hash TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  sent_at TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  sent_count INTEGER NOT NULL DEFAULT 1,
  window_at TEXT NOT NULL,
  PRIMARY KEY (email, purpose)
);

-- Eski rasmlar uchun D1 fallback. MEDIA R2 binding ulanganidan keyin yangi
-- rasmlar R2 ga ketadi; bu jadval faqat oldingi/fallback BLOB'lar uchun qoladi.
CREATE TABLE IF NOT EXISTS media (
  ref TEXT PRIMARY KEY,
  mime TEXT NOT NULL,
  data BLOB NOT NULL,
  bytes INTEGER NOT NULL,
  created_at TEXT NOT NULL
);

-- Rasmning o'zi emas, uning hajmi va egasi haqidagi kichik metadata.
-- Guest upload limitini va R2 oqimini nazorat qilish uchun ishlatiladi.
CREATE TABLE IF NOT EXISTS media_uploads (
  ref TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  mime TEXT NOT NULL,
  bytes INTEGER NOT NULL,
  storage TEXT NOT NULL CHECK(storage IN ('r2', 'd1')),
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS media_uploads_user_created_idx ON media_uploads(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS media_uploads_created_idx ON media_uploads(created_at);
CREATE INDEX IF NOT EXISTS users_guest_seen_idx ON users(registered_at, last_seen);

CREATE TABLE IF NOT EXISTS shops (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  seller_name TEXT NOT NULL DEFAULT 'Madina',
  owner_name TEXT NOT NULL DEFAULT '',
  first_name TEXT NOT NULL DEFAULT '',
  last_name TEXT NOT NULL DEFAULT '',
  phone TEXT NOT NULL DEFAULT '',
  email TEXT COLLATE NOCASE NOT NULL UNIQUE,
  email_verified_at TEXT,
  region TEXT NOT NULL DEFAULT '',
  login TEXT COLLATE NOCASE NOT NULL UNIQUE,
  pass_hash TEXT NOT NULL,
  logo TEXT,
  description TEXT NOT NULL DEFAULT '',
  lat REAL,
  lon REAL,
  address TEXT,
  active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL,
  last_login_at TEXT
);
CREATE INDEX IF NOT EXISTS shops_active_created_idx ON shops(active, created_at DESC);

CREATE TABLE IF NOT EXISTS products (
  id TEXT PRIMARY KEY,
  shop_id TEXT NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  category TEXT,
  price INTEGER NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  photos TEXT NOT NULL DEFAULT '[]',
  active INTEGER NOT NULL DEFAULT 1,
  views INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS products_shop_idx ON products(shop_id, created_at DESC);
CREATE INDEX IF NOT EXISTS products_category_idx ON products(category, active, created_at DESC);

CREATE TABLE IF NOT EXISTS follows (
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  shop_id TEXT NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL,
  PRIMARY KEY (user_id, shop_id)
);
CREATE INDEX IF NOT EXISTS follows_shop_idx ON follows(shop_id);

CREATE TABLE IF NOT EXISTS product_likes (
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  product_id TEXT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  created_at TEXT NOT NULL,
  PRIMARY KEY (user_id, product_id)
);
CREATE INDEX IF NOT EXISTS product_likes_product_idx ON product_likes(product_id);

CREATE TABLE IF NOT EXISTS product_views (
  product_id TEXT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  shop_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  PRIMARY KEY (product_id, user_id)
);
CREATE INDEX IF NOT EXISTS product_views_user_idx ON product_views(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS reel_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  product_id TEXT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  dwell_ms INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS reel_events_user_idx ON reel_events(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS orders (
  id TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  shop_id TEXT NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'new',
  product_name TEXT NOT NULL,
  price INTEGER NOT NULL,
  customer_name TEXT NOT NULL DEFAULT '',
  phone TEXT NOT NULL DEFAULT '',
  address TEXT NOT NULL DEFAULT '',
  lat REAL,
  lon REAL,
  items TEXT NOT NULL DEFAULT '[]',
  courier_id TEXT,
  delivery_status TEXT,
  rejected_by TEXT NOT NULL DEFAULT '[]',
  route_km REAL,
  delivery_fee INTEGER,
  picked_at TEXT,
  delivered_at TEXT,
  archived INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS orders_shop_idx ON orders(shop_id, created_at DESC);
CREATE INDEX IF NOT EXISTS orders_user_idx ON orders(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS orders_courier_idx ON orders(courier_id, created_at DESC);

CREATE TABLE IF NOT EXISTS couriers (
  id TEXT PRIMARY KEY,
  type TEXT NOT NULL CHECK(type IN ('courier', 'cargo')),
  name TEXT NOT NULL,
  first_name TEXT NOT NULL DEFAULT '',
  last_name TEXT NOT NULL DEFAULT '',
  phone TEXT NOT NULL DEFAULT '',
  email TEXT COLLATE NOCASE NOT NULL,
  email_verified_at TEXT,
  login TEXT COLLATE NOCASE NOT NULL UNIQUE,
  pass_hash TEXT NOT NULL,
  photo TEXT,
  region TEXT NOT NULL DEFAULT '',
  vehicle TEXT NOT NULL DEFAULT 'car',
  vehicle_type TEXT NOT NULL DEFAULT '',
  plate TEXT NOT NULL DEFAULT '',
  capacity_kg INTEGER NOT NULL DEFAULT 0,
  regions TEXT NOT NULL DEFAULT '[]',
  price_per_km INTEGER NOT NULL DEFAULT 0,
  base_price INTEGER NOT NULL DEFAULT 0,
  about TEXT NOT NULL DEFAULT '',
  online INTEGER NOT NULL DEFAULT 0,
  lat REAL,
  lon REAL,
  location_at TEXT,
  deliveries INTEGER NOT NULL DEFAULT 0,
  rating REAL NOT NULL DEFAULT 5,
  active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL,
  last_login_at TEXT,
  UNIQUE(email, type)
);
CREATE INDEX IF NOT EXISTS couriers_nearby_idx ON couriers(type, active, online, location_at DESC);

CREATE TABLE IF NOT EXISTS cargo_orders (
  id TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  carrier_id TEXT NOT NULL REFERENCES couriers(id) ON DELETE CASCADE,
  kind TEXT NOT NULL DEFAULT 'cargo',
  status TEXT NOT NULL DEFAULT 'new',
  from_region TEXT NOT NULL DEFAULT '',
  to_region TEXT NOT NULL DEFAULT '',
  date TEXT NOT NULL DEFAULT '',
  cargo TEXT NOT NULL DEFAULT '',
  weight_kg INTEGER NOT NULL DEFAULT 0,
  customer_name TEXT NOT NULL DEFAULT '',
  phone TEXT NOT NULL DEFAULT '',
  address TEXT NOT NULL DEFAULT '',
  price INTEGER,
  accepted_at TEXT,
  done_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS cargo_orders_carrier_idx ON cargo_orders(carrier_id, created_at DESC);
CREATE INDEX IF NOT EXISTS cargo_orders_user_idx ON cargo_orders(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS notifications (
  id TEXT PRIMARY KEY,
  shop_id TEXT NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  type TEXT NOT NULL DEFAULT 'system',
  title TEXT NOT NULL,
  text TEXT NOT NULL,
  meta TEXT NOT NULL DEFAULT '{}',
  read INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS notifications_shop_idx ON notifications(shop_id, read, created_at DESC);

CREATE TABLE IF NOT EXISTS chat_messages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  shop_id TEXT,
  scope TEXT NOT NULL DEFAULT 'assistant',
  role TEXT NOT NULL,
  text TEXT NOT NULL,
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS chat_messages_user_idx ON chat_messages(user_id, scope, created_at DESC);

CREATE TABLE IF NOT EXISTS user_searches (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  q TEXT NOT NULL,
  created_at TEXT NOT NULL
);
