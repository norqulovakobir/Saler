'use client';
import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { BadgeCheck, MapPin, Search } from 'lucide-react';
import { Avatar, Badge, Card, ErrorBox, PageTitle, Pagination, Segmented, Table, Toolbar } from '@/components/ui';
import { useApi, useDebounced } from '@/lib/hooks';
import { photoUrl } from '@/lib/api';
import { ago, date, moneyShort, num } from '@/lib/format';

export default function Shops() {
  const router = useRouter();
  const [q, setQ] = useState('');
  const [sort, setSort] = useState('createdAt');
  const [status, setStatus] = useState('');
  const [page, setPage] = useState(1);
  const dq = useDebounced(q);
  const { data, loading, error, reload } = useApi('/shops', { query: { q: dq, sort, status, page, limit: 25 } });
  // Bosh sahifadagi qidiruvdan "Hammasi" bosilganda so'rov shu yerda davom etadi
  useEffect(() => { const fromUrl = new URLSearchParams(window.location.search).get('q'); if (fromUrl) setQ(fromUrl); }, []);

  return (
    <>
      <PageTitle title="Do'konlar" sub={data && `Jami ${num(data.total)} ta do'kon`} />
      <ErrorBox error={error} retry={reload} />
      <Card pad={false}>
        <Toolbar>
          <div className="relative"><Search size={14} className="absolute left-3 top-[11px] text-muted" /><input className="input w-72 pl-9" placeholder="Nomi, login, telefon, egasi…" value={q} onChange={(e) => { setQ(e.target.value); setPage(1); }} /></div>
          <Segmented value={status} onChange={(v) => { setStatus(v); setPage(1); }} options={[['', 'Barchasi'], ['active', 'Faol'], ['blocked', 'Bloklangan']]} />
          <select className="input" value={sort} onChange={(e) => setSort(e.target.value)}><option value="createdAt">Yangi avval</option><option value="name">Nomi bo'yicha</option></select>
        </Toolbar>
        <Table loading={loading} rows={data?.items || []} onRow={(r) => router.push(`/shops/${r.id}`)} cols={[
          { key: 'name', label: "Do'kon", render: (r) => (
            <div className="flex items-center gap-3">
              <Avatar src={photoUrl(r.logo)} name={r.name} />
              <div className="min-w-0"><div className="flex items-center gap-1.5 font-medium">{r.name}{r.hasLocation && <MapPin size={12} className="text-muted" />}</div><div className="text-xs text-muted">@{r.login} · {r.ownerName}</div></div>
            </div>
          ) },
          { key: 'phone', label: 'Aloqa', render: (r) => (
            <div className="min-w-0">
              <div className="text-xs text-text-2">{r.phone || '—'}</div>
              <div className="flex items-center gap-1 truncate text-xs text-muted">{r.email || '—'}{r.emailVerified && <BadgeCheck size={12} className="shrink-0 text-emerald-500" />}</div>
            </div>
          ) },
          { key: 'region', label: 'Viloyat', render: (r) => <span className="text-xs text-text-2">{r.region || '—'}</span> },
          { key: 'aiName', label: 'AI sotuvchi', render: (r) => <span className="text-xs text-text-2">{r.aiName || 'Madina'}</span> },
          { key: 'products', label: 'Mahsulot', cls: 'text-right tabular-nums', render: (r) => num(r.products) },
          { key: 'views', label: "Ko'rish", cls: 'text-right tabular-nums', render: (r) => num(r.views) },
          { key: 'orders', label: 'Buyurtma', cls: 'text-right tabular-nums', render: (r) => <>{num(r.orders)}<span className="text-xs text-muted"> / {r.done}</span></> },
          { key: 'revenue', label: 'Tushum', cls: 'text-right tabular-nums font-medium', render: (r) => moneyShort(r.revenue) },
          { key: 'status', label: 'Holat', render: (r) => r.active === false ? <Badge tone="rose">Bloklangan</Badge> : <Badge tone="green">Faol</Badge> },
          { key: 'lastOrderAt', label: 'Oxirgi buyurtma', render: (r) => <span className="text-xs text-muted">{r.lastOrderAt ? ago(r.lastOrderAt) : '—'}</span> },
          { key: 'createdAt', label: 'Ochilgan', render: (r) => <span className="text-xs text-muted">{date(r.createdAt, false)}</span> },
        ]} />
        {data && <Pagination page={data.page} limit={data.limit} total={data.total} onPage={setPage} />}
      </Card>
    </>
  );
}
