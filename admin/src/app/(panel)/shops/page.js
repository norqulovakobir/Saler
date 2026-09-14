'use client';
import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { MapPin, Search } from 'lucide-react';
import { Avatar, Badge, Card, ErrorBox, PageTitle, Pagination, Table, Toolbar } from '@/components/ui';
import { useApi, useDebounced } from '@/lib/hooks';
import { photoUrl } from '@/lib/api';
import { ago, date, moneyShort, num } from '@/lib/format';

export default function Shops() {
  const router = useRouter();
  const [q, setQ] = useState('');
  const [sort, setSort] = useState('createdAt');
  const [page, setPage] = useState(1);
  const dq = useDebounced(q);
  const { data, loading, error, reload } = useApi('/shops', { query: { q: dq, sort, page, limit: 25 } });

  return (
    <>
      <PageTitle title="Do'konlar" sub={data && `Jami ${num(data.total)} ta do'kon`} />
      <ErrorBox error={error} retry={reload} />
      <Card pad={false}>
        <Toolbar>
          <div className="relative"><Search size={14} className="absolute left-3 top-[11px] text-muted" /><input className="input w-72 pl-9" placeholder="Nomi, login, telefon, egasi…" value={q} onChange={(e) => { setQ(e.target.value); setPage(1); }} /></div>
          <select className="input" value={sort} onChange={(e) => setSort(e.target.value)}><option value="createdAt">Yangi avval</option><option value="name">Nomi bo'yicha</option></select>
        </Toolbar>
        <Table loading={loading} rows={data?.items || []} onRow={(r) => router.push(`/shops/${r.id}`)} cols={[
          { key: 'name', label: "Do'kon", render: (r) => (
            <div className="flex items-center gap-3">
              <Avatar src={photoUrl(r.logo)} name={r.name} />
              <div className="min-w-0"><div className="flex items-center gap-1.5 font-medium">{r.name}{r.hasLocation && <MapPin size={12} className="text-muted" />}</div><div className="text-xs text-muted">@{r.login} · {r.ownerName}</div></div>
            </div>
          ) },
          { key: 'phone', label: 'Telefon', render: (r) => <span className="text-xs text-text-2">{r.phone}</span> },
          { key: 'products', label: 'Mahsulot', cls: 'text-right tabular-nums', render: (r) => num(r.products) },
          { key: 'views', label: "Ko'rish", cls: 'text-right tabular-nums', render: (r) => num(r.views) },
          { key: 'orders', label: 'Buyurtma', cls: 'text-right tabular-nums', render: (r) => <>{num(r.orders)}<span className="text-xs text-muted"> / {r.done}</span></> },
          { key: 'revenue', label: 'Tushum', cls: 'text-right tabular-nums font-medium', render: (r) => moneyShort(r.revenue) },
          { key: 'sellers', label: 'Sotuvchi', cls: 'text-center', render: (r) => <Badge>{r.sellers}</Badge> },
          { key: 'lastOrderAt', label: 'Oxirgi buyurtma', render: (r) => <span className="text-xs text-muted">{r.lastOrderAt ? ago(r.lastOrderAt) : '—'}</span> },
          { key: 'createdAt', label: 'Ochilgan', render: (r) => <span className="text-xs text-muted">{date(r.createdAt, false)}</span> },
        ]} />
        {data && <Pagination page={data.page} limit={data.limit} total={data.total} onPage={setPage} />}
      </Card>
    </>
  );
}
