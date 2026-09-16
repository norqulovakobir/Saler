import express from 'express';
import cors from 'cors';
import { closeDb, migrate, one } from './db.js';
import { storageEnabled, publicUrl, ensureBucket, BUCKET } from './storage.js';
import { HttpError, ah, log } from './util.js';
import adminRouter from './admin.js';
import apiRouter, { reportHandler } from './api.js';

const app = express();
app.disable('x-powered-by');
app.set('trust proxy', 1);
app.use(cors());
// Sekin so'rovlarni logga yozadi: ilova qotib qolsa, sababini darhol ko'rish uchun
app.use((req, res, next) => {
  const t0 = process.hrtime.bigint();
  res.on('finish', () => {
    const ms = Number(process.hrtime.bigint() - t0) / 1e6;
    if (ms > 500) log('SEKIN', `${req.method} ${req.originalUrl.split('?')[0]} ${Math.round(ms)} ms`);
  });
  next();
});
app.use(express.json({ limit: '60mb' }));

app.get('/', (_req, res) => res.json({ ok: true, name: 'Rydex server', time: new Date().toISOString() }));
app.get('/health', (_req, res) => res.json({ ok: true }));
// Bazaga haqiqiy so'rov yuboradi. Supabase bepul loyihasi 7 kun so'rovsiz qolib to'xtab qolmasligi uchun kuniga bir marta chaqirish mumkin.
app.get('/health/db', ah(async (_req, res) => {
  await one('SELECT 1');
  res.json({ ok: true, db: true });
}));

// Rasmlar: eskilari photos jadvalidan beriladi, qolganlari Supabase Storage'ga yo'naltiriladi
app.get('/api/photo/:ref', ah(async (req, res) => {
  const p = await one('SELECT mime, data FROM photos WHERE ref=$1', [req.params.ref]);
  res.set('Cache-Control', 'public, max-age=31536000, immutable');
  if (p) {
    res.set('Content-Type', p.mime);
    return res.send(p.data);
  }
  if (storageEnabled) return res.redirect(301, publicUrl(req.params.ref));
  res.set('Cache-Control', 'no-store');
  throw new HttpError(404, 'Rasm topilmadi');
}));

app.get('/api/report/:key', reportHandler);
app.use('/api/admin', adminRouter);
app.use('/api', apiRouter);

app.use((_req, res) => res.status(404).json({ error: 'Topilmadi' }));
// eslint-disable-next-line no-unused-vars
app.use((err, _req, res, _next) => {
  if (err instanceof HttpError) return res.status(err.status).json({ error: err.message, ...err.extra });
  if (err?.type === 'entity.too.large') return res.status(413).json({ error: 'Yuborilgan maʼlumot juda katta' });
  log('ERROR', err?.stack || String(err));
  res.status(500).json({ error: 'Server xatosi' });
});

const port = Number(process.env.PORT) || 3000;
let httpServer;
let shuttingDown = false;

async function setupStorage() {
  if (!storageEnabled) {
    log("Rasmlar Postgres'da saqlanadi (SUPABASE_URL berilmagan)");
    return;
  }
  try {
    const status = await ensureBucket();
    log(`Rasmlar Supabase Storage'da: "${BUCKET}" bucket ${status}`);
  } catch (error) {
    log('ERROR', `Supabase Storage: ${error.message}`);
  }
}

async function shutdown(signal) {
  if (shuttingDown) return;
  shuttingDown = true;
  log(`Saler server ${signal} signalini oldi, so'rovlar yakunlanmoqda`);
  const forceTimer = setTimeout(() => process.exit(1), 15_000);
  forceTimer.unref();
  try {
    await Promise.all([
      new Promise((resolve) => httpServer ? httpServer.close(resolve) : resolve()),
      closeDb(),
    ]);
    clearTimeout(forceTimer);
    process.exit(0);
  } catch (error) {
    console.error('Serverni toza to‘xtatib bo‘lmadi:', error);
    process.exit(1);
  }
}

process.once('SIGTERM', () => { void shutdown('SIGTERM'); });
process.once('SIGINT', () => { void shutdown('SIGINT'); });

async function start() {
  await migrate();
  await setupStorage();
  httpServer = app.listen(port, '0.0.0.0', () => log(`Saler server ${port}-portda ishlayapti`));
}

start().catch((error) => {
  console.error('DB migratsiya xatosi:', error);
  process.exit(1);
});
