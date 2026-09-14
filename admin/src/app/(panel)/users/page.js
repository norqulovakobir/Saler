'use client';
import { useState } from 'react';
import Link from 'next/link';
import { Search } from 'lucide-react';
import { Avatar, Badge, Card, ErrorBox, PageTitle, Pagination, Segmented, Table, Toolbar } from '@/components/ui';
import { useApi, useDebounced } from '@/lib/hooks';
import { ago, moneyShort, num } from '@/lib/format';

export default function UsersPage() {
  const [q, setQ] = useState('');
  const [role, setRole] = useState('');
  const [source, setSource] = useState('');
  const [page, setPage] = useState(1);
  const dq = useDebounced(q);
  const { data, loading, error, reload } = useApi('/users', { query: { q: dq, role, source, page, limit: 30 } });

  return (
    <>
      <PageTitle title="Foydalanuvchilar" sub={data && `Jami ${num(data.total)} ta`} />
      <ErrorBox error={error} retry={reload} />
      <Card pad={false}>
        <Toolbar>
          <div className="relative"><Search size={14} className="absolute left-3 top-[11px] text-muted" /><input className="input w-64 pl-9" placeholder="Ism, username yoki ID…" value={q} onChange={(e) => { setQ(e.target.value); setPage(1); }} /></div>
          <Segmented value={role} onChange={(v) => { setRole(v); setPage(1); }} options={[['', 'Barcha'], ['buyer', 'Xaridor'], ['seller', 'Sotuvchi']]} />
          <Segmented value={source} onChange={(v) => { setSource(v); setPage(1); }} options={[['', 'Barcha manba'], ['telegram', 'Telegram'], ['app', 'Ilova']]} />
        </Toolbar>
        <Table loading={loading} rows={data?.items || []} cols={[
          { key: 'name', label: 'Foydalanuvchi', render: (u) => <div className="flex items-center gap-2.5"><Avatar name={u.name} size={30} rounded="rounded-full" /><div><div className="font-medium">{u.name || '—'}</div><div className="text-xs text-muted">{u.username ? `@${u.username}` : <span className="mono">{u.id}</span>}</div></div></div> },
          { key: 'role', label: 'Rol', render: (u) => u.role === 'seller' ? <Badge tone="dark">Sotuvchi</Badge> : <Badge tone="blue">Xaridor</Badge> },
          { key: 'source', label: 'Manba', render: (u) => <Badge>{u.source === 'app' ? 'Ilova' : 'Telegram'}</Badge> },
          { key: 'lang', label: 'Til', render: (u) => <span className="text-xs uppercase text-text-2">{u.lang}</span> },
          { key: 'shop', label: "Do'kon", render: (u) => u.shopId ? <Link href={`/shops/${u.shopId}`} className="text-xs hover:underline">{u.shop || u.shopId}</Link> : <span className="text-xs text-muted">—</span> },
          { key: 'orders', label: 'Buyurtma', cls: 'text-right tabular-nums', render: (u) => num(u.orders) },
          { key: 'spent', label: 'Xarid', cls: 'text-right tabular-nums font-medium', render: (u) => moneyShort(u.spent) },
          { key: 'lastActivity', label: 'Oxirgi faollik', render: (u) => <span className="text-xs text-muted">{u.lastActivity ? ago(u.lastActivity) : '—'}</span> },
        ]} />
        {data && <Pagination page={data.page} limit={data.limit} total={data.total} onPage={setPage} />}
      </Card>
    </>
  );
}
