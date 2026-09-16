'use client';
import { useState } from 'react';
import { Ban, BadgeCheck, CheckCircle2, Search, Trash2 } from 'lucide-react';
import { Avatar, Badge, Card, ErrorBox, PageTitle, Pagination, Segmented, Table, Toolbar, useConfirm } from '@/components/ui';
import { useApi, useDebounced } from '@/lib/hooks';
import { api } from '@/lib/api';
import { TRUCK, VEHICLE, ago, date, money, num } from '@/lib/format';

export default function Couriers() {
  const [q, setQ] = useState('');
  const [online, setOnline] = useState('');
  const [type, setType] = useState('');
  const [status, setStatus] = useState('');
  const [page, setPage] = useState(1);
  const dq = useDebounced(q);
  const { data, loading, error, reload } = useApi('/couriers', { query: { q: dq, online, type, status, page, limit: 30 }, refreshMs: 30000 });
  const [confirm, confirmEl] = useConfirm();
  const reset = (fn) => (v) => { fn(v); setPage(1); };

  const del = async (c) => {
    if (await confirm({ title: "Hisobni o'chirish", text: `${c.name} o'chiriladi, faol buyurtmalari bo'shatiladi.`, danger: true, ok: "O'chirish" })) {
      await api(`/couriers/${c.id}`, { method: 'DELETE' });
      reload();
    }
  };
  const toggle = async (c) => {
    const block = c.active;
    const ok = await confirm({
      title: block ? 'Bloklash' : 'Blokdan chiqarish',
      text: block ? `${c.name} tizimga kira olmaydi va buyurtma ololmaydi.` : `${c.name} qayta faollashtiriladi.`,
      danger: block,
      ok: block ? 'Bloklash' : 'Faollashtirish',
    });
    if (!ok) return;
    await api(`/couriers/${c.id}`, { method: 'PATCH', body: { active: !c.active } });
    reload();
  };

  return (
    <>
      {confirmEl}
      <PageTitle title="Kuryer va yuk tashuvchilar" sub={data && `Jami ${num(data.total)} ta · Onlayn ${data.online}`} />
      <ErrorBox error={error} retry={reload} />
      <Card pad={false}>
        <Toolbar>
          <div className="relative">
            <Search size={14} className="absolute left-3 top-[11px] text-muted" />
            <input className="input w-64 pl-9" placeholder="Ism, telefon, email, raqam…" value={q} onChange={(e) => reset(setQ)(e.target.value)} />
          </div>
          <Segmented value={type} onChange={reset(setType)} options={[['', 'Barchasi'], ['courier', 'Kuryerlar'], ['cargo', 'Yuk tashuvchilar']]} />
          <Segmented value={status} onChange={reset(setStatus)} options={[['', 'Holat: barchasi'], ['active', 'Faol'], ['blocked', 'Bloklangan']]} />
          <button className={`btn btn-sm ${online === '1' ? 'btn-primary' : ''}`} onClick={() => reset(setOnline)(online === '1' ? '' : '1')}>Faqat onlayn</button>
        </Toolbar>
        <Table loading={loading} rows={data?.items || []} cols={[
          { key: 'name', label: 'Hisob', render: (c) => (
            <div className="flex items-center gap-2.5">
              <span className="relative">
                <Avatar name={c.name} size={30} rounded="rounded-full" />
                <i className={`absolute -bottom-0.5 -right-0.5 h-2.5 w-2.5 rounded-full ring-2 ring-panel ${c.online ? 'bg-emerald-500' : 'bg-zinc-400'}`} />
              </span>
              <div className="min-w-0">
                <div className="font-medium">{c.name}</div>
                <div className="truncate text-xs text-muted">@{c.login} · {c.phone}</div>
              </div>
            </div>
          ) },
          { key: 'type', label: 'Tur', render: (c) => c.type === 'cargo' ? <Badge tone="amber">Yuk tashuvchi</Badge> : <Badge tone="green">Kuryer</Badge> },
          { key: 'vehicle', label: 'Transport', render: (c) => (
            <div className="min-w-0">
              <Badge>{c.type === 'cargo' ? `${TRUCK[c.vehicleType] || c.vehicleType} · ${num(c.capacityKg)} kg` : VEHICLE[c.vehicle] || c.vehicle}</Badge>
              {c.plate && <div className="mt-0.5 text-xs text-muted">{c.plate}</div>}
            </div>
          ) },
          { key: 'region', label: 'Hudud', render: (c) => (
            <span className="text-xs text-text-2">{c.type === 'cargo' ? (c.regions || []).join(', ') || '—' : c.region || '—'}</span>
          ) },
          { key: 'email', label: 'Email', render: (c) => (
            <span className="flex items-center gap-1 text-xs text-muted">{c.email || '—'}{c.emailVerified && <BadgeCheck size={12} className="text-emerald-500" />}</span>
          ) },
          { key: 'tariff', label: 'Tarif', cls: 'text-right', render: (c) => (
            <span className="text-xs text-text-2">{c.basePrice || c.pricePerKm ? `${money(c.basePrice)} + ${num(c.pricePerKm)}/km` : '—'}</span>
          ) },
          { key: 'deliveries', label: 'Yetkazgan', cls: 'text-right tabular-nums', render: (c) => num(c.deliveries) },
          { key: 'activeOrders', label: 'Faol', cls: 'text-center', render: (c) => c.activeOrders ? <Badge tone="amber">{c.activeOrders}</Badge> : <span className="text-muted">0</span> },
          { key: 'status', label: 'Holat', render: (c) => c.active ? <Badge tone="green">Faol</Badge> : <Badge tone="rose">Bloklangan</Badge> },
          { key: 'location', label: 'Joylashuv', render: (c) => (
            <span className="text-xs text-muted">{c.location?.lat ? `${c.location.lat.toFixed(4)}, ${c.location.lon.toFixed(4)} · ${ago(c.location.updatedAt)}` : '—'}</span>
          ) },
          { key: 'createdAt', label: "Ro'yxatdan", render: (c) => <span className="text-xs text-muted">{date(c.createdAt, false)}</span> },
          { key: 'act', label: '', cls: 'text-right', render: (c) => (
            <span className="flex justify-end gap-1">
              <button className={`btn btn-sm btn-icon ${c.active ? '' : 'btn-primary'}`} title={c.active ? 'Bloklash' : 'Blokdan chiqarish'} onClick={() => toggle(c)}>
                {c.active ? <Ban size={13} /> : <CheckCircle2 size={13} />}
              </button>
              <button className="btn btn-sm btn-icon btn-danger" title="O'chirish" onClick={() => del(c)}><Trash2 size={13} /></button>
            </span>
          ) },
        ]} />
        {data && <Pagination page={data.page} limit={data.limit} total={data.total} onPage={setPage} />}
      </Card>
    </>
  );
}
