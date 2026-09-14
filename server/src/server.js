import express from 'express';
import cors from 'cors';
import { migrate, one } from './db.js';
import { HttpError, ah, log } from './util.js';
import adminRouter from './admin.js';
import apiRouter, { reportHandler } from './api.js';

const app = express();
app.disable('x-powered-by');
app.set('trust proxy', 1);
app.use(cors());
app.use(express.json({ limit: '60mb' }));

app.get('/', (_req, res) => res.json({ ok: true, name: 'Saler AI server', time: new Date().toISOString() }));
app.get('/health', (_req, res) => res.json({ ok: true }));

// Rasmlar: photos jadvalidan
app.get('/api/photo/:ref', ah(async (req, res) => {
  const p = await one('SELECT mime, data FROM photos WHERE ref=$1', [req.params.ref]);
  if (!p) throw new HttpError(404, 'Rasm topilmadi');
  res.set('Content-Type', p.mime);
  res.set('Cache-Control', 'public, max-age=31536000, immutable');
  res.send(p.data);
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
migrate()
  .then(() => app.listen(port, '0.0.0.0', () => log(`Saler server ${port}-portda ishlayapti`)))
  .catch((e) => { console.error('DB migratsiya xatosi:', e); process.exit(1); });
