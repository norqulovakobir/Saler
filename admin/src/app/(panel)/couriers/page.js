'use client';
import { useState } from 'react';
import { Ban, CheckCircle2, Search, Trash2 } from 'lucide-react';
import { Avatar, Badge, Card, ErrorBox, PageTitle, Pagination, Segmented, Table, Toolbar, useConfirm } from '@/components/ui';
import { useApi, useDebounced } from '@/lib/hooks';
import { api } from '@/lib/api';
import { VEHICLE, VEHICLE_TYPE, ago, date, moneyShort, num } from '@/lib/format';

/** Kuryerlar (shahar ichi) va yuk tashuvchilar (viloyatlararo): onlayn holati, transport, viloyat, daromad, bloklash */
export default function Couriers() {
  const [q, setQ] = useState('');
  const [type, setType] = useState('');
  const [online, setOnline] = useState('');
  const [page, setPage] = useState(1);
  const dq = useDebounced(q);
  const { data, loading, error, reload } = useApi('/couriers', { query: { q: dq, type, online, page, limit: 30 }, refreshMs: 30000 });
  const [confirm, confirmEl] = useConfirm();

  const del = async (c) => {
    if (await confirm({ title: "Hisobni o'chirish", text: `${c.name} o'chiriladi, faol buyurtmalari bo'shatiladi.`, danger: true, ok: "O'chirish" })) {
      await api(`/couriers/${c.id}`, { method: 'DELETE' });
      reload();
    }
  };
  const toggleActive = async (c) => {
    const block = c.active;
    const ok = await confirm({
      title: block ? 'Bloklash' : 'Blokdan chiqarish',
      text: block ? `${c.name} bloklanadi: oflayn qilinadi, hisobiga kira olmaydi, boshlanmagan buyurtmalari boshqa kuryerga beriladi.` : `${c.name} yana kirishi va buyurtma olishi mumkin.`,
      danger: block,
      ok: block ? 'Bloklash' : 'Ochish',
    });
    if (!ok) return;
    await api(`/couriers/${c.id}`, { method: 'PATCH', body: { active: !c.active } });
    reload();
  };

  const transport = (c) => c.type === 'cargo'
    ? <><Badge tone="amber">{VEHICLE_TYPE[c.vehicleType] || c.vehicleType || '—'}</Badge>{c.capacityKg ? <span className="ml-1 text-xs text-muted">{num(c.capacityKg)} kg</span> : null}</>
    : <Badge>{VEHICLE[c.vehicle] || c.vehicle}</Badge>;
  const regionOf = (c) => (c.type === 'cargo' && Array.isArray(c.regions) && c.regions.length ? c.regions.join(', ') : c.region || '—');
  const tariff = (c) => (c.basePrice || c.pricePerKm ? `${c.basePrice ? moneyShort(c.basePrice) : ''}${c.basePrice && c.pricePerKm ? ' + ' : ''}${c.pricePerKm ? `${num(c.pricePerKm)}/km` : ''}` : '—');

  return (
    <>
      {confirmEl}
      <PageTitle title="Kuryerlar va yuk tashuvchilar" sub={data && `Kuryer ${num(data.couriers)} · Yuk tashuvchi ${num(data.cargo)} · Onlayn ${data.online} · Bloklangan ${data.blocked}`} />
      <ErrorBox error={error} retry={reload} />
      <Card pad={false}>
        <Toolbar>
          <div className="relative"><Search size={14} className="absolute left-3 top-[11px] text-muted" /><input className="input w-64 pl-9" placeholder="Ism, telefon, login, email, raqam…" value={q} onChange={(e) => { setQ(e.target.value); setPage(1); }} /></div>
          <Segmented value={type} onChange={(v) => { setType(v); setPage(1); }} options={[['', 'Barcha'], ['courier', 'Kuryer'], ['cargo', 'Yuk tashuvchi']]} />
          <button className={`btn btn-sm ${online === '1' ? 'btn-primary' : ''}`} onClick={() => { setOnline(online === '1' ? '' : '1'); setPage(1); }}>Faqat onlayn</button>
        </Toolbar>
        <Table loading={loading} rows={data?.items || []} cols={[
          { key: 'name', label: 'Kuryer', render: (c) => (
            <div className="flex items-center gap-2.5">
              <span className="relative"><Avatar name={c.name} size={30} rounded="rounded-full" /><i className={`absolute -bottom-0.5 -right-0.5 h-2.5 w-2.5 rounded-full ring-2 ring-panel ${c.online ? 'bg-emerald-500' : 'bg-zinc-400'}`} /></span>
              <div><div className={`font-medium ${c.active ? '' : 'text-muted line-through'}`}>{c.name}</div><div className="text-xs text-muted">@{c.login} · {c.phone}{c.email ? ` · ${c.email}` : ''}</div></div>
            </div>
          ) },
          { key: 'type', label: 'Tur', render: (c) => c.type === 'cargo' ? <Badge tone="amber">Yuk tashuvchi</Badge> : <Badge tone="green">Kuryer</Badge> },
          { key: 'vehicle', label: 'Transport', render: transport },
          { key: 'plate', label: 'Raqam', render: (c) => <span className="mono text-xs text-text-2">{c.plate || '—'}</span> },
          { key: 'region', label: 'Viloyat', render: (c) => <span className="line-clamp-1 max-w-[180px] text-xs text-text-2">{regionOf(c)}</span> },
          { key: 'tariff', label: 'Tarif', render: (c) => <span className="text-xs text-text-2">{tariff(c)}</span> },
          { key: 'deliveries', label: 'Yetkazgan', cls: 'text-right tabular-nums', render: (c) => num(c.type === 'cargo' ? c.cargoDone : c.deliveries) },
          { key: 'activeOrders', label: 'Faol', cls: 'text-center', render: (c) => { const n = (c.activeOrders || 0) + (c.cargoActive || 0); return n ? <Badge tone="amber">{n}</Badge> : <span className="text-muted">0</span>; } },
          { key: 'earnings', label: 'Daromad', cls: 'text-right tabular-nums font-medium', render: (c) => moneyShort(c.earnings) },
          { key: 'rating', label: 'Reyting', cls: 'text-right tabular-nums', render: (c) => `${Number(c.rating).toFixed(1)} ★` },
          { key: 'location', label: 'Joylashuv', render: (c) => <span className="text-xs text-muted">{c.location?.lat ? `${c.location.lat.toFixed(4)}, ${c.location.lon.toFixed(4)} · ${ago(c.location.updatedAt)}` : '—'}</span> },
          { key: 'createdAt', label: "Ro'yxatdan", render: (c) => <span className="text-xs text-muted">{date(c.createdAt, false)}{c.lastLoginAt ? <><br />kirdi: {ago(c.lastLoginAt)}</> : null}</span> },
          { key: 'status', label: 'Holat', render: (c) => c.active ? (c.online ? <Badge tone="green">Onlayn</Badge> : <Badge>Oflayn</Badge>) : <Badge tone="rose">Bloklangan</Badge> },
          { key: 'act', label: '', cls: 'text-right', render: (c) => (
            <span className="flex justify-end gap-1">
              <button className={`btn btn-sm btn-icon ${c.active ? 'btn-danger' : ''}`} title={c.active ? 'Bloklash' : 'Blokdan chiqarish'} onClick={() => toggleActive(c)}>{c.active ? <Ban size={13} /> : <CheckCircle2 size={13} />}</button>
              <button className="btn btn-sm btn-icon btn-danger" title="O'chirish" onClick={() => del(c)}><Trash2 size={13} /></button>
            </span>
          ) },
        ]} />
        {data && <Pagination page={data.page} limit={data.limit} total={data.total} onPage={setPage} />}
      </Card>
    </>
  );
}
