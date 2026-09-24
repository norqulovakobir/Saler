'use client';
import { AlertTriangle, Database, HardDrive, Image, Mail, PenLine, RefreshCw, Rows3, ShieldCheck } from 'lucide-react';
import { Badge, Card, ErrorBox, PageTitle, Stat } from '@/components/ui';
import { AreaSeries, Bars, Donut, Gauge, RankList } from '@/components/charts';
import { useApi } from '@/lib/hooks';
import { API_URL } from '@/lib/api';
import { bytes, date, num, shortDay } from '@/lib/format';

/// Jadval nomlarini o'qiladigan ko'rinishga o'tkazadi.
const TABLE_LABEL = {
  users: 'Foydalanuvchilar', sessions: 'Sessiyalar', shops: "Do'konlar", products: 'Mahsulotlar',
  orders: 'Buyurtmalar', couriers: 'Kuryerlar', cargo_orders: 'Yuk buyurtmalari',
  follows: 'Obunalar', product_likes: 'Yoqtirishlar', product_views: "Ko'rishlar",
  reel_events: 'Reels hodisalari', chat_messages: 'Chat xabarlari', user_searches: 'Qidiruvlar',
  notifications: 'Bildirishnomalar', media_uploads: 'Rasm metadatasi', email_codes: 'Email kodlari',
  admin_sessions: 'Admin sessiyalari',
};
const label = (t) => TABLE_LABEL[t] || t;

/// Chegaraga yaqinlashganda nima qilish kerakligini aytadigan ogohlantirish.
function LimitWarning({ d1, r2, writes }) {
  const alerts = [];
  if (writes.percent >= 70) alerts.push(`Bugungi yozuv kunlik chegaraning ${writes.percent}% ini egalladi. Chegara tugasa baza yozishni to'xtatadi — ko'rish va reels hodisalarini to'plab yozish kerak.`);
  if (d1.percent >= 70) alerts.push(`Baza hajmi ${d1.percent}% to'lgan. 5 GB tugasa yangi yozuv va indeks yaratish bloklanadi.`);
  if (r2.percent >= 70) alerts.push(`Rasm ombori ${r2.percent}% to'lgan. 10 GB dan oshsa to'lov boshlanadi.`);
  if (!r2.enabled) alerts.push('R2 binding ulanmagan — rasm yuklash 503 qaytaradi.');
  if (!alerts.length) return null;
  return (
    <div className="mb-4 rounded-xl border border-amber-500/30 bg-amber-500/10 p-4">
      <div className="flex items-center gap-2 text-sm font-semibold text-amber-600 dark:text-amber-400">
        <AlertTriangle size={15} />E'tibor
      </div>
      <ul className="mt-2 space-y-1 text-xs text-text-2">
        {alerts.map((a, i) => <li key={i}>• {a}</li>)}
      </ul>
    </div>
  );
}

export default function SystemPage() {
  const { data: s, error, reload } = useApi('/system', { refreshMs: 30000 });
  const L = !s;
  const d1 = s?.d1;
  const r2 = s?.r2;
  const w = s?.writes;
  // Grafikda faqat qatori bor jadvallar ko'rsatiladi — bo'shlari shovqin.
  const filled = (d1?.tables || []).filter((t) => t.rows > 0);

  return (
    <>
      <PageTitle
        title="Tizim va ombor"
        sub={s ? `${s.platform} · ${date(s.time)} · ${API_URL}` : 'Yuklanmoqda…'}
        action={<button className="btn" onClick={reload}><RefreshCw size={14} />Yangilash</button>} />
      <ErrorBox error={error} retry={reload} />
      {s && <LimitWarning d1={d1} r2={r2} writes={w} />}

      <div className="grid gap-4 xl:grid-cols-3">
        <Card title="Baza hajmi" sub={s ? `D1 · ${d1.name}` : 'D1'}>
          {L ? <div className="skeleton" style={{ height: 170 }} />
            : <Gauge percent={d1.percent} value={bytes(d1.used)} limit={bytes(d1.limit)} label="D1" />}
        </Card>
        <Card title="Rasm ombori" sub={s ? `R2 · ${r2.name}` : 'R2'}>
          {L ? <div className="skeleton" style={{ height: 170 }} />
            : <Gauge percent={r2.percent} value={bytes(r2.used)} limit={bytes(r2.limit)} label="R2" />}
        </Card>
        <Card title="Bugungi yozuv" sub="Kunlik chegara — hajmdan oldin shu tugaydi">
          {L ? <div className="skeleton" style={{ height: 170 }} />
            : <Gauge percent={w.percent} value={`${num(w.today)} yozuv`} limit={num(w.limit)} label="Yozuv" />}
        </Card>
      </div>

      <div className="mt-4 grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-5">
        <Stat loading={L} label="Baza band" value={s && bytes(d1.used)} sub={s && `${bytes(d1.limit)} dan · ${d1.percent}%`} icon={Database} />
        <Stat loading={L} label="Jami qator" value={s && num(d1.rows)} sub={s && `${filled.length} ta jadvalda ma'lumot bor`} icon={Rows3} />
        <Stat loading={L} label="Rasmlar" value={s && num(r2.files)} sub={s && `${bytes(r2.used)} · ${r2.enabled ? 'R2 ulangan' : 'R2 yo\'q'}`} icon={Image} />
        <Stat loading={L} label="Bugungi yozuv" value={s && num(w.today)} sub={s && `Kunlik chegara ${num(w.limit)}`} icon={PenLine} />
        <Stat loading={L} label="Kunlik o'qish chegarasi" value={s && num(s.reads.limit)} sub="Bepul rejada" icon={HardDrive} />
      </div>

      <div className="mt-4 grid gap-4 xl:grid-cols-3">
        <Card title="Yozuv oqimi · 14 kun" sub="Bazaga qo'shilgan qatorlar" className="xl:col-span-2">
          <AreaSeries data={s?.daily || []} series={[{ key: 'writes', name: 'Yozuv', color: 'c1' }]} xFmt={shortDay} h={240} />
        </Card>
        <Card title="Qatorlar taqsimoti" sub="Qaysi jadval joy egallayapti">
          <Donut
            data={filled.slice(0, 6).map((t, i) => ({ name: label(t.name), value: t.rows, color: ['c1', 'c6', 'c3', 'c4', 'c7', 'c8'][i] }))}
            h={170} center="qator" />
        </Card>
      </div>

      <div className="mt-4 grid gap-4 xl:grid-cols-2">
        <Card title="Jadvallar" sub="Qator soni bo'yicha">
          {s && <RankList items={filled.slice(0, 10)} label={(t) => label(t.name)} sub={(t) => t.name} value={(t) => t.rows} />}
        </Card>
        <Card title="Eng ko'p yozadigan kunlar" sub="Kunlik chegarani shular yeydi">
          <Bars data={s?.daily || []} x="date" series={[{ key: 'writes', name: 'Yozuv', color: 'c6' }]} xFmt={shortDay} h={240} />
        </Card>
      </div>

      <Card title="Xizmatlar" className="mt-4">
        {s && <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
          {[
            { k: 'Baza (D1)', ok: s.services.database, on: 'Ulangan', off: 'Binding yo\'q', icon: Database },
            { k: 'Rasm ombori', ok: s.services.media === 'r2', on: 'Cloudflare R2', off: 'Ulanmagan', icon: Image },
            { k: 'Email (Brevo)', ok: s.services.email, on: 'Kodlar ketyapti', off: 'Kalit yo\'q', icon: Mail },
            { k: 'Admin paroli', ok: s.services.admin, on: 'O\'rnatilgan', off: 'Yo\'q', icon: ShieldCheck },
          ].map(({ k, ok, on, off, icon: Icon }) => (
            <div key={k} className="rounded-xl bg-panel-2 p-3">
              <div className="flex items-center gap-2 text-xs text-muted"><Icon size={13} />{k}</div>
              <div className="mt-2"><Badge tone={ok ? 'green' : 'rose'}>{ok ? on : off}</Badge></div>
            </div>
          ))}
        </div>}
      </Card>
    </>
  );
}
