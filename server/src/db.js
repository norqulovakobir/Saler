import pg from 'pg';

const { Pool } = pg;

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) throw new Error("DATABASE_URL o'rnatilmagan. PostgreSQL manzilini bering.");

const envInt = (key, fallback, { min = 0, max = Number.MAX_SAFE_INTEGER } = {}) => {
  const value = Number(process.env[key]);
  return Number.isInteger(value) && value >= min && value <= max ? value : fallback;
};

const localDatabase = /(?:localhost|127\.0\.0\.1|::1)/.test(databaseUrl);
const useSsl = process.env.DATABASE_SSL == null
  ? !localDatabase
  : process.env.DATABASE_SSL.toLowerCase() === 'true';
const ssl = useSsl ? { rejectUnauthorized: process.env.DATABASE_SSL_REJECT_UNAUTHORIZED === 'true' } : false;

// Bitta Node process uchun kichik pool kifoya. PgBouncer ulangan bo'lsa ham,
// bu limit databasega cheksiz yangi connection ochilishining oldini oladi.
const poolMax = envInt('DB_POOL_MAX', 8, { min: 1, max: 30 });
export const pool = new Pool({
  connectionString: databaseUrl,
  ssl,
  max: poolMax,
  min: 0,
  idleTimeoutMillis: envInt('DB_POOL_IDLE_MS', 30_000, { min: 1_000, max: 300_000 }),
  connectionTimeoutMillis: envInt('DB_CONNECT_TIMEOUT_MS', 5_000, { min: 500, max: 30_000 }),
  query_timeout: envInt('DB_QUERY_TIMEOUT_MS', 25_000, { min: 1_000, max: 120_000 }),
  statement_timeout: envInt('DB_STATEMENT_TIMEOUT_MS', 20_000, { min: 1_000, max: 120_000 }),
  maxUses: envInt('DB_POOL_MAX_USES', 7_500, { min: 0, max: 100_000 }),
  application_name: process.env.DB_APPLICATION_NAME || 'saler-api',
});

pool.on('error', (error) => {
  // Idle connection xatosi so'rovni yiqitmasligi uchun pg pool yangisini ochadi.
  console.error('PostgreSQL pool xatosi:', error.message);
});

export const q = (text, params = []) => pool.query(text, params);
export const one = async (text, params = []) => (await pool.query(text, params)).rows[0] ?? null;
export const all = async (text, params = []) => (await pool.query(text, params)).rows;

export const dbPoolStats = () => ({
  total: pool.totalCount,
  idle: pool.idleCount,
  waiting: pool.waitingCount,
  max: poolMax,
});

let closePromise;
export function closeDb() {
  closePromise ??= pool.end();
  return closePromise;
}

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

  -- Yetkazish va yuk: vaqtlar, masofa, haq (eski bazalarga ham qo'shiladi)
  ALTER TABLE orders ADD COLUMN IF NOT EXISTS picked_at TIMESTAMPTZ;
  ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivered_at TIMESTAMPTZ;
  ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivery_fee BIGINT;
  ALTER TABLE orders ADD COLUMN IF NOT EXISTS route_km DOUBLE PRECISION;
  ALTER TABLE cargo_orders ADD COLUMN IF NOT EXISTS price BIGINT;
  ALTER TABLE cargo_orders ADD COLUMN IF NOT EXISTS accepted_at TIMESTAMPTZ;
  ALTER TABLE cargo_orders ADD COLUMN IF NOT EXISTS done_at TIMESTAMPTZ;
  CREATE INDEX IF NOT EXISTS idx_orders_courier ON orders(courier_id);
  CREATE INDEX IF NOT EXISTS idx_cargo_carrier ON cargo_orders(carrier_id);
  -- AI natijalari keshi
  CREATE TABLE IF NOT EXISTS courier_advice (
    courier_id TEXT PRIMARY KEY REFERENCES couriers(id) ON DELETE CASCADE,
    tips JSONB NOT NULL DEFAULT '[]',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
  );
  -- Xaridor hisobi (majburiy ro'yxatdan o'tish), qiziqishlar profili
  ALTER TABLE users ADD COLUMN IF NOT EXISTS phone TEXT;
  ALTER TABLE users ADD COLUMN IF NOT EXISTS pass_hash TEXT;
  ALTER TABLE users ADD COLUMN IF NOT EXISTS registered_at TIMESTAMPTZ;
  ALTER TABLE users ADD COLUMN IF NOT EXISTS interests JSONB;
  ALTER TABLE users ADD COLUMN IF NOT EXISTS interests_at TIMESTAMPTZ;
  CREATE UNIQUE INDEX IF NOT EXISTS idx_users_phone ON users(phone) WHERE phone IS NOT NULL;
  -- Obunalar, layklar, Reels ko'rishlari, qidiruvlar
  CREATE TABLE IF NOT EXISTS follows (
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    shop_id TEXT NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, shop_id)
  );
  CREATE INDEX IF NOT EXISTS idx_follows_shop ON follows(shop_id);
  CREATE TABLE IF NOT EXISTS product_likes (
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    product_id TEXT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, product_id)
  );
  CREATE INDEX IF NOT EXISTS idx_likes_product ON product_likes(product_id);
  CREATE TABLE IF NOT EXISTS reel_events (
    id SERIAL PRIMARY KEY,
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    product_id TEXT NOT NULL,
    dwell_ms INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
  );
  CREATE INDEX IF NOT EXISTS idx_reel_events_user ON reel_events(user_id, created_at);
  CREATE TABLE IF NOT EXISTS user_searches (
    id SERIAL PRIMARY KEY,
    user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    q TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
  );
  CREATE INDEX IF NOT EXISTS idx_user_searches_user ON user_searches(user_id, created_at);
  CREATE INDEX IF NOT EXISTS idx_views_user ON product_views(user_id, created_at);
  CREATE INDEX IF NOT EXISTS idx_likes_user ON product_likes(user_id, created_at);
  -- Takroriy mahsulotni aniqlash: normallashtirilgan nom va rasm xeshlari
  ALTER TABLE products ADD COLUMN IF NOT EXISTS name_key TEXT;
  ALTER TABLE products ADD COLUMN IF NOT EXISTS photo_hashes JSONB NOT NULL DEFAULT '{}';
  CREATE INDEX IF NOT EXISTS idx_products_namekey ON products(shop_id, name_key);

  CREATE TABLE IF NOT EXISTS shop_ai_summary (
    shop_id TEXT PRIMARY KEY REFERENCES shops(id) ON DELETE CASCADE,
    data JSONB NOT NULL DEFAULT '{}',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
  );

  -- Ro'yxatdan o'tish: email orqali tasdiqlash kodlari (kodning o'zi emas, xeshi saqlanadi)
  CREATE TABLE IF NOT EXISTS email_codes (
    email TEXT NOT NULL,
    purpose TEXT NOT NULL,
    code_hash TEXT NOT NULL,
    attempts INT NOT NULL DEFAULT 0,
    sent_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL,
    sent_count INT NOT NULL DEFAULT 1,
    window_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (email, purpose)
  );
  -- Tasdiqlash kodi bitta emailning o'zida ham faqat bitta login/profilga tegishli.
  ALTER TABLE email_codes ADD COLUMN IF NOT EXISTS binding TEXT NOT NULL DEFAULT '';
  -- Xaridor: ism, familiya, telegram, tasdiqlangan email; admin bloklashi
  ALTER TABLE users ADD COLUMN IF NOT EXISTS first_name TEXT;
  ALTER TABLE users ADD COLUMN IF NOT EXISTS last_name TEXT;
  ALTER TABLE users ADD COLUMN IF NOT EXISTS email TEXT;
  ALTER TABLE users ADD COLUMN IF NOT EXISTS telegram TEXT;
  ALTER TABLE users ADD COLUMN IF NOT EXISTS email_verified_at TIMESTAMPTZ;
  ALTER TABLE users ADD COLUMN IF NOT EXISTS blocked BOOLEAN NOT NULL DEFAULT false;
  CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email ON users(lower(email)) WHERE email IS NOT NULL;
  -- Sotuvchi: egasi, email, viloyat (AI sotuvchi ismi seller_name ustunida, bo'sh bo'lsa Madina)
  ALTER TABLE shops ADD COLUMN IF NOT EXISTS first_name TEXT NOT NULL DEFAULT '';
  ALTER TABLE shops ADD COLUMN IF NOT EXISTS last_name TEXT NOT NULL DEFAULT '';
  ALTER TABLE shops ADD COLUMN IF NOT EXISTS email TEXT NOT NULL DEFAULT '';
  ALTER TABLE shops ADD COLUMN IF NOT EXISTS email_verified_at TIMESTAMPTZ;
  ALTER TABLE shops ADD COLUMN IF NOT EXISTS region TEXT NOT NULL DEFAULT '';
  -- Kuryer va yuk tashuvchi: ism, familiya, ish viloyati, davlat raqami
  ALTER TABLE couriers ADD COLUMN IF NOT EXISTS first_name TEXT NOT NULL DEFAULT '';
  ALTER TABLE couriers ADD COLUMN IF NOT EXISTS last_name TEXT NOT NULL DEFAULT '';
  ALTER TABLE couriers ADD COLUMN IF NOT EXISTS email_verified_at TIMESTAMPTZ;
  ALTER TABLE couriers ADD COLUMN IF NOT EXISTS region TEXT NOT NULL DEFAULT '';
  ALTER TABLE couriers ADD COLUMN IF NOT EXISTS plate TEXT NOT NULL DEFAULT '';
  ALTER TABLE couriers ADD COLUMN IF NOT EXISTS last_login_at TIMESTAMPTZ;
  ALTER TABLE shops ADD COLUMN IF NOT EXISTS last_login_at TIMESTAMPTZ;

  -- Bitta email butun Saler AI tizimida faqat bitta rol/hisobga tegishli.
  -- Alohida users, shops va couriers jadvallarida buni UNIQUE bilan saqlab
  -- bo'lmaydi, shu sabab markaziy reyestr ishlatiladi.
  CREATE TABLE IF NOT EXISTS account_emails (
    email TEXT PRIMARY KEY,
    account_type TEXT NOT NULL,
    account_id TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
  );
  INSERT INTO account_emails(email, account_type, account_id)
    SELECT lower(email), 'buyer', id::text FROM users
    WHERE email IS NOT NULL AND email <> '' AND email_verified_at IS NOT NULL
    ON CONFLICT (email) DO NOTHING;
  INSERT INTO account_emails(email, account_type, account_id)
    SELECT lower(email), 'seller', id FROM shops
    WHERE email <> '' AND email_verified_at IS NOT NULL
    ON CONFLICT (email) DO NOTHING;
  INSERT INTO account_emails(email, account_type, account_id)
    SELECT lower(email), type, id FROM couriers
    WHERE email <> '' AND email_verified_at IS NOT NULL
    ON CONFLICT (email) DO NOTHING;
  `);
  // Supabase public jadvallarni Data API orqali tashqariga ochadi. RLS yoqilsa, u yerdan hech narsa o'qib bo'lmaydi.
  // Server jadval egasi sifatida ulanadi, shuning uchun uning o'z so'rovlariga ta'sir qilmaydi.
  await q(`DO $$ DECLARE t text; BEGIN
    FOREACH t IN ARRAY ARRAY['users','sessions','shops','products','photos','orders','couriers','cargo_orders',
      'notifications','chat_messages','shop_advice','product_views','logs','courier_advice','shop_ai_summary','follows','product_likes','reel_events','user_searches','email_codes','account_emails'] LOOP
      EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    END LOOP;
  END $$;`);
}
