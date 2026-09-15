// Postgres'dagi photos jadvalidagi rasmlarni Supabase Storage'ga ko'chiradi.
// Rasm manzili o'zgarmaydi: /api/photo/<ref> uni Storage'ga yo'naltiradi.
//
//   SOURCE_DATABASE_URL=... SUPABASE_URL=... SUPABASE_SECRET_KEY=... node scripts/move-photos.js [--delete]
//
// SOURCE_DATABASE_URL: rasmlar olinadigan baza (masalan eski Render bazasi). Berilmasa DATABASE_URL olinadi.
// --delete: ko'chirilgan rasmni manba bazadan o'chiradi (joy bo'shatish uchun).
import pg from 'pg';
import { storageEnabled, uploadPhoto, ensureBucket, BUCKET } from '../src/storage.js';

const src = process.env.SOURCE_DATABASE_URL || process.env.DATABASE_URL;
const del = process.argv.includes('--delete');
if (!src) { console.error('SOURCE_DATABASE_URL yoki DATABASE_URL bering'); process.exit(1); }
if (!storageEnabled) { console.error('SUPABASE_URL va SUPABASE_SECRET_KEY bering'); process.exit(1); }

const ssl = /localhost|127\.0\.0\.1/.test(src) ? false : { rejectUnauthorized: false };
const db = new pg.Client({ connectionString: src, ssl });
await db.connect();
console.log(`Bucket "${BUCKET}": ${await ensureBucket()}`);

const { rows } = await db.query('SELECT ref FROM photos ORDER BY created_at');
console.log(`Ko'chiriladigan rasmlar: ${rows.length}`);
let done = 0, bytes = 0;
for (const { ref } of rows) {
  const { rows: [p] } = await db.query('SELECT mime, data FROM photos WHERE ref=$1', [ref]);
  await uploadPhoto(ref, p.data, p.mime);
  if (del) await db.query('DELETE FROM photos WHERE ref=$1', [ref]);
  done++;
  bytes += p.data.length;
  if (done % 25 === 0 || done === rows.length) console.log(`  ${done}/${rows.length}  (${(bytes / 1048576).toFixed(1)} MB)`);
}
await db.end();
console.log('Rasmlar ko\'chirildi.');
