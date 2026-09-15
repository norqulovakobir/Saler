'use client';
import { useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { ArrowUpRight, Bike, Eye, MapPin, Package, Receipt, RefreshCw, Search, ShoppingCart, Store, Users, Wallet, X } from 'lucide-react';
import { Avatar, Badge, Card, ErrorBox, PageTitle, Stat, StatusBadge, Table } from '@/components/ui';
import { AreaSeries, Bars, Donut } from '@/components/charts';
import { useApi, useDebounced } from '@/lib/hooks';
import { photoUrl } from '@/lib/api';
import { ago, money, moneyShort, num, shortDay } from '@/lib/format';

/** Bosh sahifadagi do'kon qidiruvi: nomi, login, telefon yoki egasi bo'yicha */
function ShopSearch() {
  const router = useRouter();
  const [q, setQ] = useState('');
  const dq = useDebounced(q.trim());
  const { data, loading, error } = useApi('/shops', { query: { q: dq, limit: 6 } });
  const sub = !data ? 'Yuklanmoqda…' : dq ? `"${dq}" bo'yicha ${num(data.total)} ta natija` : `Jami ${num(data.total)} ta do'kon · oxirgi qo'shilganlar`;

  return (
    <Card title="Do'kon qidiruvi" sub={sub} className="mb-4" pad={false}
      action={<Link href={dq ? `/shops?q=${encodeURIComponent(dq)}` : '/shops'} className="btn btn-sm btn-ghost">Hammasi <ArrowUpRight size={13} /></Link>}>
      <div className="px-4 pb-3">
        <div className="relative">
          <Search size={15} className="absolute left-3 top-[11px] text-muted" />
          <input className="input w-full pl-9 pr-9" placeholder="Do'kon nomi, login, telefon yoki egasi…" value={q} onChange={(e) => setQ(e.target.value)} />
          {q && <button type="button" aria-label="Tozalash" className="absolute right-2 top-[7px] rounded-md p-1 text-muted hover:text-text" onClick={() => setQ('')}><X size={14} /></button>}
        </div>
      </div>
      <ErrorBox error={error} />
      <Table loading={loading} rows={data?.items || []} onRow={(r) => router.push(`/shops/${r.id}`)}
        empty={dq ? `"${dq}" bo'yicha do'kon topilmadi` : "Hozircha do'konlar yo'q. Sotuvchilar ilovada ro'yxatdan o'tganda shu yerda ko'rinadi."}
        cols={[
          { key: 'name', label: "Do'kon", render: (r) => (
            <div className="flex items-center gap-3">
              <Avatar src={photoUrl(r.logo)} name={r.name} />
              <div className="min-w-0"><div className="flex items-center gap-1.5 font-medium">{r.name}{r.hasLocation && <MapPin size={12} className="text-muted" />}{!r.active && <Badge tone="rose">Bloklangan</Badge>}</div><div className="text-xs text-muted">@{r.login}{r.ownerName ? ` · ${r.ownerName}` : ''}{r.region ? ` · ${r.region}` : ''}</div></div>
            </div>
          ) },
          { key: 'phone', label: 'Telefon', render: (r) => <span className="text-xs text-text-2">{r.phone || '—'}</span> },
          { key: 'products', label: 'Mahsulot', cls: 'text-right tabular-nums', render: (r) => num(r.products) },
          { key: 'orders', label: 'Buyurtma', cls: 'text-right tabular-nums', render: (r) => <>{num(r.orders)}<span className="text-xs text-muted"> / {r.done}</span></> },
          { key: 'revenue', label: 'Tushum', cls: 'text-right tabular-nums font-medium', render: (r) => moneyShort(r.revenue) },
          { key: 'createdAt', label: 'Ochilgan', render: (r) => <span className="text-xs text-muted">{ago(r.createdAt)}</span> },
        ]} />
    </Card>
  );
}

export default function Dashboard() {
  const [days, setDays] = useState(30);
  const ov = useApi('/overview', { refreshMs: 60000 });
  const ts = useApi('/timeseries', { query: { days }, refreshMs: 60000 });
  const orders = useApi('/orders', { query: { limit: 8 }, refreshMs: 60000 });
  const o = ov.data;
  const L = !o;

  return (
    <>
      <PageTitle title="Bosh sahifa" sub={o ? `Yangilandi: ${ago(o.generatedAt)}` : 'Yuklanmoqda…'} action={<>
        <select className="input" value={days} onChange={(e) => setDays(Number(e.target.value))}>
          {[7, 14, 30, 60, 90, 180, 365].map((d) => <option key={d} value={d}>{d} kun</option>)}
        </select>
        <button className="btn" onClick={() => { ov.reload(); ts.reload(); orders.reload(); }}><RefreshCw size={14} />Yangilash</button>
      </>} />
      <ErrorBox error={ov.error} retry={ov.reload} />

      {o && o.mail && !o.mail.enabled && (
        <div className="card mb-4 flex flex-wrap items-center justify-between gap-3 border-amber-500/40 px-4 py-3 text-sm">
          <span className="text-text-2">
            <b className="font-semibold text-text">Email tasdiqlash {o.mail.devCodes ? 'test rejimida' : "o'chiq"}.</b>{' '}
            {o.mail.devCodes ? "Kodlar emailga bormaydi, ilovada ko'rinadi." : "Ro'yxatdan o'tish va buyurtma ishlamaydi."} Serverda EMAILJS_PUBLIC_KEY va EMAILJS_PRIVATE_KEY kiriting.
          </span>
          <Link href="/system" className="btn btn-sm">Tizim <ArrowUpRight size={13} /></Link>
        </div>
      )}

      <ShopSearch />

      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        <Stat loading={L} label="Tushum" value={o && moneyShort(o.revenue.total)} sub={o && `Hafta: ${moneyShort(o.revenue.week)}`} growth={o?.revenue.growth} icon={Wallet} />
        <Stat loading={L} label="Buyurtmalar" value={o && num(o.orders.total)} sub={o && `Bugun ${o.orders.today} · Hafta ${o.orders.week}`} growth={o?.orders.growth} icon={ShoppingCart} />
        <Stat loading={L} label="Do'konlar" value={o && num(o.shops.total)} sub={o && `Hafta +${o.shops.week} · Xaritada ${o.shops.withLocation}${o.shops.blocked ? ` · Bloklangan ${o.shops.blocked}` : ''}`} growth={o?.shops.growth} icon={Store} />
        <Stat loading={L} label="Mahsulotlar" value={o && num(o.products.total)} sub={o && `Faol ${num(o.products.active)} · Yashirin ${o.products.hidden}`} icon={Package} />
        <Stat loading={L} label="Xaridorlar" value={o && num(o.users.buyers)} sub={o && `Tasdiqlangan · Mehmon ${num(o.users.guests)} · Haftada +${o.users.regWeek}`} icon={Users} />
        <Stat loading={L} label="Ko'rishlar" value={o && num(o.products.views)} sub={o && `Konversiya ${o.conversion}%`} icon={Eye} />
        <Stat loading={L} label="O'rtacha chek" value={o && moneyShort(o.revenue.avgOrder)} sub={o && `Bugun ${moneyShort(o.revenue.today)}`} icon={Receipt} />
        <Stat loading={L} label="Kuryerlar" value={o && num(o.couriers.total)} sub={o && `Onlayn ${o.couriers.online} · Kuryer ${o.couriers.couriers} · Yuk ${o.couriers.cargo}`} icon={Bike} />
      </div>

      <div className="mt-4 grid gap-4 xl:grid-cols-3">
        <Card title={`Tushum · ${days} kun`} sub="Bajarilgan buyurtmalar summasi" className="xl:col-span-2">
          <AreaSeries data={ts.data || []} series={[{ key: 'revenue', name: 'Tushum', color: 'c1' }]} money xFmt={shortDay} h={250} />
        </Card>
        <Card title="Buyurtma holatlari">
          <Donut data={o ? [
            { name: 'Yangi', value: o.orders.status.new, color: 'c4' },
            { name: 'Bajarildi', value: o.orders.status.done, color: 'c3' },
            { name: 'Bekor', value: o.orders.status.cancelled, color: 'c5' },
          ] : []} h={150} center="buyurtma" />
          {o && <div className="mt-4 grid grid-cols-2 gap-2">
            <div className="rounded-xl bg-panel-2 p-3"><div className="kicker">Bajarilish</div><div className="mt-1 text-lg font-semibold tabular-nums">{o.doneRate}%</div></div>
            <div className="rounded-xl bg-panel-2 p-3"><div className="kicker">Bekor qilish</div><div className="mt-1 text-lg font-semibold tabular-nums">{o.cancelRate}%</div></div>
          </div>}
        </Card>
      </div>

      <div className="mt-4 grid gap-4 md:grid-cols-2 xl:grid-cols-3">
        <Card title="Buyurtmalar kunlar bo'yicha">
          <Bars data={ts.data || []} x="date" series={[{ key: 'done', name: 'Bajarildi', color: 'c1' }, { key: 'cancelled', name: 'Bekor', color: 'c5' }]} stacked xFmt={shortDay} h={200} />
        </Card>
        <Card title="Ro'yxatdan o'tishlar" sub="Tasdiqlangan xaridorlar, yangi do'konlar va kuryerlar">
          <AreaSeries data={ts.data || []} series={[{ key: 'buyers', name: 'Xaridorlar', color: 'c6' }, { key: 'shops', name: "Do'konlar", color: 'c1' }, { key: 'couriers', name: 'Kuryerlar', color: 'c3' }]} xFmt={shortDay} h={200} />
        </Card>
        <Card title="Rollar" sub="Tasdiqlangan hisoblar">
          <Donut data={o ? [
            { name: 'Xaridor', value: o.users.buyers, color: 'c6' },
            { name: 'Sotuvchi', value: o.users.sellers, color: 'c1' },
            { name: 'Kuryer', value: o.users.couriers, color: 'c3' },
            { name: 'Yuk tashuvchi', value: o.users.cargo, color: 'c4' },
          ] : []} h={130} center="hisob" />
          {o && <p className="mt-4 text-xs text-muted">7 kunda faol xaridor: <b className="font-semibold text-text">{num(o.users.activeWeek)}</b> · Bloklangan: <b className="font-semibold text-text">{num(o.users.blocked)}</b></p>}
        </Card>
      </div>

      <Card title="Oxirgi buyurtmalar" className="mt-4" pad={false} action={<Link href="/orders" className="btn btn-sm btn-ghost">Hammasi <ArrowUpRight size={13} /></Link>}>
        <Table loading={orders.loading} rows={orders.data?.items || []} cols={[
          { key: 'id', label: 'ID', render: (r) => <span className="mono text-xs text-muted">{r.id}</span> },
          { key: 'shop', label: "Do'kon", render: (r) => <Link className="font-medium hover:underline" href={`/shops/${r.shopId}`}>{r.shop || r.shopId}</Link> },
          { key: 'items', label: 'Mahsulot', render: (r) => <span className="line-clamp-1 text-text-2">{r.items.map((i) => `${i.name}${i.qty > 1 ? ` ×${i.qty}` : ''}`).join(', ') || '—'}</span> },
          { key: 'customerName', label: 'Xaridor', render: (r) => <>{r.customerName}<div className="text-xs text-muted">{r.phone}</div></> },
          { key: 'price', label: 'Summa', cls: 'text-right tabular-nums font-medium', render: (r) => money(r.price) },
          { key: 'status', label: 'Holat', render: (r) => <StatusBadge status={r.status} /> },
          { key: 'createdAt', label: 'Vaqt', render: (r) => <span className="text-xs text-muted">{ago(r.createdAt)}</span> },
        ]} />
      </Card>
    </>
  );
}
