'use client';
import { useState } from 'react';
import { Search, Trash2 } from 'lucide-react';
import { Avatar, Badge, Card, ErrorBox, PageTitle, Pagination, Table, Toolbar, useConfirm } from '@/components/ui';
import { useApi, useDebounced } from '@/lib/hooks';
import { api } from '@/lib/api';
import { VEHICLE, ago, date, num } from '@/lib/format';

export default function Couriers() {
  const [q, setQ] = useState('');
  const [online, setOnline] = useState('');
  const [page, setPage] = useState(1);
  const dq = useDebounced(q);
  const { data, loading, error, reload } = useApi('/couriers', { query: { q: dq, online, page, limit: 30 }, refreshMs: 30000 });
  const [confirm, confirmEl] = useConfirm();

  const del = async (c) => { if (await confirm({ title: "Kuryerni o'chirish", text: `${c.name} o'chiriladi, faol buyurtmalari bo'shatiladi.`, danger: true, ok: "O'chirish" })) { await api(`/couriers/${c.id}`, { method: 'DELETE' }); reload(); } };

  return (
    <>
      {confirmEl}
      <PageTitle title="Kuryerlar" sub={data && `Jami ${num(data.total)} ta · Onlayn ${data.online}`} />
      <ErrorBox error={error} retry={reload} />
      <Card pad={false}>
        <Toolbar>
          <div className="relative"><Search size={14} className="absolute left-3 top-[11px] text-muted" /><input className="input w-64 pl-9" placeholder="Ism, telefon, login…" value={q} onChange={(e) => { setQ(e.target.value); setPage(1); }} /></div>
          <button className={`btn btn-sm ${online === '1' ? 'btn-primary' : ''}`} onClick={() => { setOnline(online === '1' ? '' : '1'); setPage(1); }}>Faqat onlayn</button>
        </Toolbar>
        <Table loading={loading} rows={data?.items || []} cols={[
          { key: 'name', label: 'Kuryer', render: (c) => <div className="flex items-center gap-2.5"><span className="relative"><Avatar name={c.name} size={30} rounded="rounded-full" /><i className={`absolute -bottom-0.5 -right-0.5 h-2.5 w-2.5 rounded-full ring-2 ring-panel ${c.online ? 'bg-emerald-500' : 'bg-zinc-400'}`} /></span><div><div className="font-medium">{c.name}</div><div className="text-xs text-muted">@{c.login} · {c.phone}</div></div></div> },
          { key: 'vehicle', label: 'Transport', render: (c) => <Badge>{VEHICLE[c.vehicle] || c.vehicle}</Badge> },
          { key: 'deliveries', label: 'Yetkazgan', cls: 'text-right tabular-nums', render: (c) => num(c.deliveries) },
          { key: 'activeOrders', label: 'Faol', cls: 'text-center', render: (c) => c.activeOrders ? <Badge tone="amber">{c.activeOrders}</Badge> : <span className="text-muted">0</span> },
          { key: 'rating', label: 'Reyting', cls: 'text-right tabular-nums', render: (c) => `${Number(c.rating).toFixed(1)} ★` },
          { key: 'location', label: 'Joylashuv', render: (c) => <span className="text-xs text-muted">{c.location?.lat ? `${c.location.lat.toFixed(4)}, ${c.location.lon.toFixed(4)} · ${ago(c.location.updatedAt)}` : '—'}</span> },
          { key: 'createdAt', label: "Ro'yxatdan", render: (c) => <span className="text-xs text-muted">{date(c.createdAt, false)}</span> },
          { key: 'act', label: '', cls: 'text-right', render: (c) => <button className="btn btn-sm btn-icon btn-danger" onClick={() => del(c)}><Trash2 size={13} /></button> },
        ]} />
        {data && <Pagination page={data.page} limit={data.limit} total={data.total} onPage={setPage} />}
      </Card>
    </>
  );
}
