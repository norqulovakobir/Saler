-- media_uploads.storage ustuni endi 'sb' (Supabase Storage) qiymatini ham
-- qabul qilishi kerak. SQLite'da CHECK ni o'zgartirib bo'lmaydi, shuning uchun
-- jadval qayta quriladi. Ma'lumot ko'chiriladi, indekslar tiklanadi.
-- Bir necha marta ishga tushirilsa ham zarar qilmaydi.
CREATE TABLE IF NOT EXISTS media_uploads_v2 (
  ref TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  mime TEXT NOT NULL,
  bytes INTEGER NOT NULL,
  storage TEXT NOT NULL CHECK(storage IN ('r2', 'sb', 'd1')),
  created_at TEXT NOT NULL
);

INSERT OR IGNORE INTO media_uploads_v2 (ref, user_id, mime, bytes, storage, created_at)
  SELECT ref, user_id, mime, bytes, storage, created_at FROM media_uploads;

DROP TABLE media_uploads;
ALTER TABLE media_uploads_v2 RENAME TO media_uploads;

CREATE INDEX IF NOT EXISTS media_uploads_user_created_idx ON media_uploads(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS media_uploads_created_idx ON media_uploads(created_at);
