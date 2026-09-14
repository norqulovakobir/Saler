'use client';
import { useState } from 'react';
import Link from 'next/link';
import { ArrowUpRight, Bike, Eye, Package, Receipt, RefreshCw, ShoppingCart, Store, Users, Wallet } from 'lucide-react';
import { Card, ErrorBox, PageTitle, Stat, StatusBadge, Table } from '@/components/ui';
import { AreaSeries, Bars, Donut } from '@/components/charts';
import { useApi } from '@/lib/hooks';
import { ago, money, moneyShort, num, shortDay } from '@/lib/format';

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

      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        <Stat loading={L} label="Tushum" value={o && moneyShort(o.revenue.total)} sub={o && `Hafta: ${moneyShort(o.revenue.week)}`} growth={o?.revenue.growth} icon={Wallet} />
        <Stat loading={L} label="Buyurtmalar" value={o && num(o.orders.total)} sub={o && `Bugun ${o.orders.today} · Hafta ${o.orders.week}`} growth={o?.orders.growth} icon={ShoppingCart} />
        <Stat loading={L} label="Do'konlar" value={o && num(o.shops.total)} sub={o && `Hafta +${o.shops.week} · Xaritada ${o.shops.withLocation}`} growth={o?.shops.growth} icon={Store} />
        <Stat loading={L} label="Mahsulotlar" value={o && num(o.products.total)} sub={o && `Faol ${num(o.products.active)} · Yashirin ${o.products.hidden}`} icon={Package} />
        <Stat loading={L} label="Foydalanuvchilar" value={o && num(o.users.total)} sub={o && `Xaridor ${num(o.users.buyers)} · Sotuvchi ${o.users.sellers}`} icon={Users} />
        <Stat loading={L} label="Ko'rishlar" value={o && num(o.products.views)} sub={o && `Konversiya ${o.conversion}%`} icon={Eye} />
        <Stat loading={L} label="O'rtacha chek" value={o && moneyShort(o.revenue.avgOrder)} sub={o && `Bugun ${moneyShort(o.revenue.today)}`} icon={Receipt} />
        <Stat loading={L} label="Kuryerlar" value={o && num(o.couriers.total)} sub={o && `Onlayn ${o.couriers.online}`} icon={Bike} />
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
        <Card title="Yangi do'konlar va mahsulotlar">
          <AreaSeries data={ts.data || []} series={[{ key: 'shops', name: "Do'konlar", color: 'c1' }, { key: 'products', name: 'Mahsulotlar', color: 'c6' }]} xFmt={shortDay} h={200} />
        </Card>
        <Card title="Foydalanuvchi manbalari">
          <Donut data={o ? [
            { name: 'Telegram', value: o.users.telegram, color: 'c1' },
            { name: 'Mobil ilova', value: o.users.app, color: 'c6' },
          ] : []} h={130} center="jami" />
          {o && <p className="mt-4 text-xs text-muted">Oxirgi 7 kunda faol suhbat: <b className="font-semibold text-text">{num(o.users.activeWeek)}</b></p>}
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
