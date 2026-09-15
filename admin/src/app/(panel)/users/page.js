'use client';
import { useState } from 'react';
import Link from 'next/link';
import { Ban, CheckCircle2, MailCheck, Search } from 'lucide-react';
import { Avatar, Badge, Card, ErrorBox, PageTitle, Pagination, Segmented, Table, Toolbar, useConfirm } from '@/components/ui';
import { useApi, useDebounced } from '@/lib/hooks';
import { api } from '@/lib/api';
import { ROLE, ago, moneyShort, num } from '@/lib/format';

/** Barcha rollar bitta ro'yxatda: xaridor (tasdiqlangan yoki mehmon), sotuvchi, kuryer, yuk tashuvchi. Bloklash shu yerdan. */
export default function UsersPage() {
  const [q, setQ] = useState('');
  const [role, setRole] = useState('');
  const [status, setStatus] = useState('');
  const [page, setPage] = useState(1);
  const dq = useDebounced(q);
  const { data, loading, error, reload } = useApi('/users', { query: { q: dq, role, status, page, limit: 30 } });
  const [confirm, confirmEl] = useConfirm();

  const toggleBlock = async (u) => {
    const block = !u.blocked;
    const who = u.name || u.id;
    const ok = await confirm({
      title: block ? 'Bloklash' : 'Blokdan chiqarish',
      text: block
        ? `${who} bloklanadi: xaridor buyurtma bera olmaydi, sotuvchi yoki kuryer hisobiga kira olmaydi (ochiq sessiyalari yopiladi).`
        : `${who} yana ilovadan to'liq foydalana oladi.`,
      danger: block,
      ok: block ? 'Bloklash' : 'Ochish',
    });
    if (!ok) return;
    await api(`/users/${u.id}`, { method: 'PATCH', body: { blocked: block } });
    reload();
  };

  const roleBadge = (u) => { const r = ROLE[u.role] || { label: u.role, tone: 'neutral' }; return <Badge tone={r.tone}>{r.label}</Badge>; };
  const statusBadge = (u) => (u.blocked ? <Badge tone="rose">Bloklangan</Badge> : !u.registered ? <Badge>Mehmon</Badge> : <Badge tone="green">Faol</Badge>);

  return (
    <>
      {confirmEl}
      <PageTitle title="Foydalanuvchilar" sub={data && `Jami ${num(data.total)} ta`} />
      <ErrorBox error={error} retry={reload} />
      <Card pad={false}>
        <Toolbar>
          <div className="relative"><Search size={14} className="absolute left-3 top-[11px] text-muted" /><input className="input w-64 pl-9" placeholder="Ism, login, telefon, email, telegram…" value={q} onChange={(e) => { setQ(e.target.value); setPage(1); }} /></div>
          <Segmented value={role} onChange={(v) => { setRole(v); setPage(1); }} options={[['', 'Barcha'], ['buyer', 'Xaridor'], ['seller', 'Sotuvchi'], ['courier', 'Kuryer'], ['cargo', 'Yuk tashuvchi']]} />
          <Segmented value={status} onChange={(v) => { setStatus(v); setPage(1); }} options={[['', 'Barcha holat'], ['registered', 'Tasdiqlangan'], ['guest', 'Mehmon'], ['blocked', 'Bloklangan']]} />
        </Toolbar>
        <Table loading={loading} rows={data?.items || []} cols={[
          { key: 'name', label: 'Foydalanuvchi', render: (u) => (
            <div className="flex items-center gap-2.5">
              <Avatar name={u.name} size={30} rounded="rounded-full" />
              <div><div className="font-medium">{u.name || '—'}</div><div className="text-xs text-muted">{u.username ? `@${u.username}` : <span className="mono">{u.id}</span>}</div></div>
            </div>
          ) },
          { key: 'role', label: 'Rol', render: roleBadge },
          { key: 'phone', label: 'Telefon', render: (u) => <span className="text-xs text-text-2">{u.phone || '—'}</span> },
          { key: 'email', label: 'Email', render: (u) => u.email ? <span className="flex items-center gap-1 text-xs text-text-2">{u.email}{u.verified && <MailCheck size={12} className="text-emerald-500" title="Email tasdiqlangan" />}</span> : <span className="text-xs text-muted">—</span> },
          { key: 'telegram', label: 'Telegram', render: (u) => <span className="text-xs text-text-2">{u.telegram || '—'}</span> },
          { key: 'shop', label: "Do'kon / Viloyat", render: (u) => u.shopId
            ? <Link href={`/shops/${u.shopId}`} className="text-xs hover:underline">{u.shop || u.shopId}</Link>
            : <span className="text-xs text-muted">{u.region || '—'}</span> },
          { key: 'orders', label: 'Buyurtma', cls: 'text-right tabular-nums', render: (u) => num(u.orders) },
          { key: 'spent', label: 'Xarid / Daromad', cls: 'text-right tabular-nums font-medium', render: (u) => moneyShort(u.spent) },
          { key: 'lastActivity', label: 'Oxirgi faollik', render: (u) => <span className="text-xs text-muted">{u.lastActivity ? ago(u.lastActivity) : '—'}</span> },
          { key: 'status', label: 'Holat', render: statusBadge },
          { key: 'act', label: '', cls: 'text-right', render: (u) => (
            <button className={`btn btn-sm btn-icon ${u.blocked ? '' : 'btn-danger'}`} title={u.blocked ? 'Blokdan chiqarish' : 'Bloklash'} onClick={() => toggleBlock(u)}>
              {u.blocked ? <CheckCircle2 size={13} /> : <Ban size={13} />}
            </button>
          ) },
        ]} />
        {data && <Pagination page={data.page} limit={data.limit} total={data.total} onPage={setPage} />}
      </Card>
    </>
  );
}
