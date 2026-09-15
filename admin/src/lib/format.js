const nf = new Intl.NumberFormat('uz-UZ');
export const num = (n) => nf.format(Math.round(Number(n) || 0));
export const money = (n) => `${num(n)} so'm`;
// Qisqa pul: 1.2 mln, 350 ming
export const moneyShort = (n) => {
  const v = Number(n) || 0;
  if (Math.abs(v) >= 1e9) return `${+(v / 1e9).toFixed(1)} mlrd`;
  if (Math.abs(v) >= 1e6) return `${+(v / 1e6).toFixed(1)} mln`;
  if (Math.abs(v) >= 1e3) return `${Math.round(v / 1e3)} ming`;
  return num(v);
};
export const bytes = (b) => {
  const v = Number(b) || 0;
  if (v >= 1 << 30) return `${(v / (1 << 30)).toFixed(2)} GB`;
  if (v >= 1 << 20) return `${(v / (1 << 20)).toFixed(1)} MB`;
  if (v >= 1 << 10) return `${(v / (1 << 10)).toFixed(0)} KB`;
  return `${v} B`;
};
export const date = (d, withTime = true) => {
  if (!d) return '—';
  const x = new Date(d);
  if (Number.isNaN(x.getTime())) return '—';
  return x.toLocaleString('uz-UZ', { timeZone: 'Asia/Tashkent', day: '2-digit', month: '2-digit', year: 'numeric', ...(withTime ? { hour: '2-digit', minute: '2-digit' } : {}) });
};
export const ago = (d) => {
  if (!d) return '—';
  const s = Math.max(0, (Date.now() - new Date(d).getTime()) / 1000);
  if (s < 60) return 'hozir';
  if (s < 3600) return `${Math.floor(s / 60)} daq oldin`;
  if (s < 86400) return `${Math.floor(s / 3600)} soat oldin`;
  if (s < 86400 * 30) return `${Math.floor(s / 86400)} kun oldin`;
  return date(d, false);
};
export const duration = (sec) => {
  const s = Math.round(Number(sec) || 0);
  const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60);
  return d ? `${d} kun ${h} soat` : h ? `${h} soat ${m} daq` : `${m} daq`;
};
export const shortDay = (iso) => { const [, m, d] = String(iso).split('-'); return `${d}.${m}`; };
export const monthName = (ym) => {
  const names = ['Yan', 'Fev', 'Mar', 'Apr', 'May', 'Iyn', 'Iyl', 'Avg', 'Sen', 'Okt', 'Noy', 'Dek'];
  const [y, m] = String(ym).split('-');
  return `${names[Number(m) - 1] || m} ${String(y).slice(2)}`;
};
export const WEEKDAYS = ['Yak', 'Dush', 'Sesh', 'Chor', 'Pay', 'Jum', 'Shan'];
export const STATUS = {
  new: { label: 'Yangi', tone: 'amber' },
  done: { label: 'Bajarildi', tone: 'green' },
  cancelled: { label: 'Bekor', tone: 'rose' },
};
export const VEHICLE = { foot: 'Piyoda', bike: 'Velosiped', moto: 'Mototsikl', car: 'Avtomobil' };
export const VEHICLE_TYPE = { labo: 'Labo', damas: 'Damas', gazel: 'Gazel', isuzu: 'Isuzu', fura: 'Fura' };
// Rollar: ilovadagi ro'yxatdan o'tish turlari
export const ROLE = {
  buyer: { label: 'Xaridor', tone: 'blue' },
  seller: { label: 'Sotuvchi', tone: 'dark' },
  courier: { label: 'Kuryer', tone: 'green' },
  cargo: { label: 'Yuk tashuvchi', tone: 'amber' },
};
