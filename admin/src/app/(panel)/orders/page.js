'use client';
import { useState } from 'react';
import Link from 'next/link';
import { Search } from 'lucide-react';
import { Badge, Card, ErrorBox, PageTitle, Pagination, Segmented, StatusBadge, Table, Toolbar } from '@/components/ui';
import { useApi, useDebounced } from '@/lib/hooks';
import { api } from '@/lib/api';
import { date, money, num } from '@/lib/format';

export default function Orders() {
  const [q, setQ] = useState('');
  const [status, setStatus] = useState('');
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const [page, setPage] = useState(1);
  const dq = useDebounced(q);
  const { data, loading, error, reload } = useApi('/orders', { query: { q: dq, status, from, to, page, limit: 30 }, refreshMs: 30000 });

  const setSt = async (o, st) => { await api(`/orders/${o.id}`, { method: 'PATCH', body: { status: st } }); reload(); };
  const reset = () => { setQ(''); setStatus(''); setFrom(''); setTo(''); setPage(1); };

  return (
    <>
      <PageTitle title="Buyurtmalar" sub={data && `Topildi ${num(data.total)} ta · Summa ${money(data.sum)}`} />
      <ErrorBox error={error} retry={reload} />
      <Card pad={false}>
        <Toolbar>
          <div className="relative"><Search size={14} className="absolute left-3 top-[11px] text-muted" /><input className="input w-64 pl-9" placeholder="Xaridor, telefon, mahsulot, ID…" value={q} onChange={(e) => { setQ(e.target.value); setPage(1); }} /></div>
          <Segmented value={status} onChange={(v) => { setStatus(v); setPage(1); }} options={[['', 'Hammasi'], ['new', 'Yangi'], ['done', 'Bajarildi'], ['cancelled', 'Bekor']]} />
          <div className="flex items-center gap-1.5">
            <input type="date" className="input" value={from} onChange={(e) => { setFrom(e.target.value); setPage(1); }} />
            <span className="text-xs text-muted">—</span>
            <input type="date" className="input" value={to} onChange={(e) => { setTo(e.target.value); setPage(1); }} />
          </div>
          {(q || status || from || to) && <button className="btn btn-sm btn-ghost" onClick={reset}>Tozalash</button>}
        </Toolbar>
        <Table loading={loading} rows={data?.items || []} cols={[
          { key: 'id', label: 'ID', render: (o) => <span className="mono text-xs text-muted">{o.id}</span> },
          { key: 'createdAt', label: 'Vaqt', render: (o) => <span className="text-xs text-text-2">{date(o.createdAt)}</span> },
          { key: 'shop', label: "Do'kon", render: (o) => <Link href={`/shops/${o.shopId}`} className="font-medium hover:underline">{o.shop || o.shopId}</Link> },
          { key: 'items', label: 'Mahsulotlar', render: (o) => (
            <ul className="text-xs text-text-2">{o.items.map((i, k) => <li key={k}>{i.name} {i.qty > 1 && <span className="text-muted">×{i.qty}</span>}</li>)}{!o.items.length && '—'}</ul>
          ) },
          { key: 'customerName', label: 'Xaridor', render: (o) => <>{o.customerName || '—'}<div className="text-xs text-muted">{o.phone}</div></> },
          { key: 'source', label: 'Manba', render: (o) => <Badge>{o.buyerId != null && o.buyerId < 0 ? 'Ilova' : 'Telegram'}</Badge> },
          { key: 'price', label: 'Summa', cls: 'text-right tabular-nums font-semibold', render: (o) => money(o.price) },
          { key: 'status', label: 'Holat', render: (o) => <StatusBadge status={o.status} /> },
          { key: 'act', label: '', cls: 'text-right', render: (o) => <select className="input h-8 text-xs" value={o.status} onChange={(e) => setSt(o, e.target.value)}><option value="new">Yangi</option><option value="done">Bajarildi</option><option value="cancelled">Bekor</option></select> },
        ]} />
        {data && <Pagination page={data.page} limit={data.limit} total={data.total} onPage={setPage} />}
      </Card>
    </>
  );
}
