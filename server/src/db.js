import pg from 'pg';

const { Pool } = pg;

if (!process.env.DATABASE_URL) {
  console.error("DATABASE_URL o'rnatilmagan. Render Postgres yoki boshqa Postgres manzilini bering.");
  process.exit(1);
}

const ssl = /localhost|127\.0\.0\.1/.test(process.env.DATABASE_URL) ? false : { rejectUnauthorized: false };
export const pool = new Pool({ connectionString: process.env.DATABASE_URL, ssl, max: 5 });

export const q = (text, params = []) => pool.query(text, params);
export const one = async (text, params = []) => (await pool.query(text, params)).rows[0] ?? null;
export const all = async (text, params = []) => (await pool.query(text, params)).rows;

export async function migrate() {
  await q(`
  CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL DEFAULT 'Xaridor',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen TIMESTAMPTZ NOT NULL DEFAULT now()
  );
  CREATE TABLE IF NOT EXISTS sessions (
    token TEXT PRIMARY KEY,
    user_id INT REFERENCES users(id) ON DELETE CASCADE,
    shop_id TEXT,
    courier_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
  );
  CREATE TABLE IF NOT EXISTS shops (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    seller_name TEXT NOT NULL DEFAULT '',
    owner_name TEXT NOT NULL DEFAULT '',
    phone TEXT NOT NULL DEFAULT '',
    login TEXT UNIQUE NOT NULL,
    pass_hash TEXT NOT NULL,
    logo TEXT,
    description TEXT NOT NULL DEFAULT '',
    lat DOUBLE PRECISION,
    lon DOUBLE PRECISION,
    address TEXT,
    active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
  );
  CREATE TABLE IF NOT EXISTS products (
    id TEXT PRIMARY KEY,
    shop_id TEXT NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    category TEXT,
    price BIGINT NOT NULL DEFAULT 0,
    description TEXT NOT NULL DEFAULT '',
    photos JSONB NOT NULL DEFAULT '[]',
    active BOOLEAN NOT NULL DEFAULT true,
    views INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
  );
  CREATE TABLE IF NOT EXISTS photos (
    ref TEXT PRIMARY KEY,
    mime TEXT NOT NULL,
    data BYTEA NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
  );
  CREATE TABLE IF NOT EXISTS orders (
    id TEXT PRIMARY KEY,
    shop_id TEXT NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
    user_id INT REFERENCES users(id) ON DELETE SET NULL,
    status TEXT NOT NULL DEFAULT 'new',
    product_name TEXT NOT NULL DEFAULT '',
    price BIGINT NOT NULL DEFAULT 0,
    customer_name TEXT NOT NULL DEFAULT '',
    phone TEXT NOT NULL DEFAULT '',
    address TEXT NOT NULL DEFAULT '',
    lat DOUBLE PRECISION,
    lon DOUBLE PRECISION,
    items JSONB NOT NULL DEFAULT '[]',
    courier_id TEXT,
    delivery_status TEXT,
    rejected_by JSONB NOT NULL DEFAULT '[]',
    archived BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
  );
  CREATE TABLE IF NOT EXISTS couriers (
    id TEXT PRIMARY KEY,
    type TEXT NOT NULL DEFAULT 'courier',
    name TEXT NOT NULL,
    phone TEXT NOT NULL DEFAULT '',
    login TEXT UNIQUE NOT NULL,
    email TEXT NOT NULL DEFAULT '',
    pass_hash TEXT NOT NULL,
    photo TEXT,
    vehicle TEXT NOT NULL DEFAULT 'foot',
    vehicle_type TEXT NOT NULL DEFAULT '',
    capacity_kg INT NOT NULL DEFAULT 0,
    regions JSONB NOT NULL DEFAULT '[]',
    price_per_km INT NOT NULL DEFAULT 0,
    base_price INT NOT NULL DEFAULT 0,
    about TEXT NOT NULL DEFAULT '',
    online BOOLEAN NOT NULL DEFAULT false,
    lat DOUBLE PRECISION,
    lon DOUBLE PRECISION,
    location_at TIMESTAMPTZ,
    deliveries INT NOT NULL DEFAULT 0,
    rating DOUBLE PRECISION NOT NULL DEFAULT 5,
    active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
  );
  CREATE TABLE IF NOT EXISTS cargo_orders (
    id TEXT PRIMARY KEY,
    user_id INT REFERENCES users(id) ON DELETE SET NULL,
    carrier_id TEXT REFERENCES couriers(id) ON DELETE SET NULL,
    kind TEXT NOT NULL DEFAULT 'cargo',
    status TEXT NOT NULL DEFAULT 'new',
    from_region TEXT NOT NULL DEFAULT '',
    to_region TEXT NOT NULL DEFAULT '',
    date TEXT NOT NULL DEFAULT '',
    cargo TEXT NOT NULL DEFAULT '',
    weight_kg INT NOT NULL DEFAULT 0,
    customer_name TEXT NOT NULL DEFAULT '',
    phone TEXT NOT NULL DEFAULT '',
    address TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
  );
  CREATE TABLE IF NOT EXISTS notifications (
    id TEXT PRIMARY KEY,
    shop_id TEXT NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
    type TEXT NOT NULL DEFAULT '',
    title TEXT NOT NULL DEFAULT '',
    text TEXT NOT NULL DEFAULT '',
    meta JSONB NOT NULL DEFAULT '{}',
    read BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
  );
  CREATE TABLE IF NOT EXISTS chat_messages (
    id SERIAL PRIMARY KEY,
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    scope TEXT NOT NULL,
    role TEXT NOT NULL,
    text TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
  );
  CREATE TABLE IF NOT EXISTS shop_advice (
    shop_id TEXT PRIMARY KEY REFERENCES shops(id) ON DELETE CASCADE,
    tips JSONB NOT NULL DEFAULT '[]',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
  );
  CREATE TABLE IF NOT EXISTS product_views (
    id SERIAL PRIMARY KEY,
    product_id TEXT NOT NULL,
    user_id INT,
    shop_id TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
  );
  CREATE TABLE IF NOT EXISTS logs (
    id SERIAL PRIMARY KEY,
    line TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
  );
  CREATE INDEX IF NOT EXISTS idx_products_shop ON products(shop_id);
  CREATE INDEX IF NOT EXISTS idx_orders_shop ON orders(shop_id);
  CREATE INDEX IF NOT EXISTS idx_orders_user ON orders(user_id);
  CREATE INDEX IF NOT EXISTS idx_notif_shop ON notifications(shop_id);
  CREATE INDEX IF NOT EXISTS idx_chat_user ON chat_messages(user_id, scope);
  CREATE INDEX IF NOT EXISTS idx_views_shop ON product_views(shop_id, created_at);
  CREATE UNIQUE INDEX IF NOT EXISTS idx_views_unique ON product_views(product_id, user_id);
  `);
}
