'use client';
import { useState } from 'react';
import Link from 'next/link';
import { BadgeCheck, Ban, CheckCircle2, Search, Send } from 'lucide-react';
import { Avatar, Badge, Card, ErrorBox, Modal, PageTitle, Pagination, Segmented, Table, Toolbar, useConfirm } from '@/components/ui';
import { useApi, useDebounced } from '@/lib/hooks';
import { api } from '@/lib/api';
import { ROLE, TRUCK, VEHICLE, ago, date, money, moneyShort, num } from '@/lib/format';

const RoleBadge = ({ role }) => {
  const r = ROLE[role] || { label: role, tone: 'neutral' };
  return <Badge tone={r.tone}>{r.label}</Badge>;
};

const Verified = ({ ok }) => ok
  ? <span className="inline-flex items-center gap-1 text-xs text-emerald-600 dark:text-emerald-400"><BadgeCheck size={13} />Tasdiqlangan</span>
  : <span className="text-xs text-muted">Tasdiqlanmagan</span>;

/** Hisob kartasi: barcha maydonlar, oxirgi buyurtmalar va bloklash */
function AccountModal({ acc, onClose, onChanged }) {
  const { data, loading, error, reload } = useApi(`/users/${acc.kind}/${acc.rawId}`);
  const [confirm, confirmEl] = useConfirm();
  const [busy, setBusy] = useState(false);
  const a = data?.account;

  const toggle = async () => {
    const block = a.active;
    const okText = block ? 'Bloklash' : 'Blokdan chiqarish';
    const ok = await confirm({
      title: `${okText}`,
      text: block
        ? `${a.name} hisobi bloklanadi: tizimga kira olmaydi va sessiyalari yopiladi.`
        : `${a.name} hisobi qayta faollashtiriladi.`,
      danger: block,
      ok: okText,
    });
    if (!ok) return;
    setBusy(true);
    try {
      await api(`/users/${acc.kind}/${acc.rawId}`, { method: 'PATCH', body: { active: !a.active } });
      reload();
      onChanged();
    } finally { setBusy(false); }
  };

  const rows = a ? [
    ['Rol', <RoleBadge key="r" role={a.role} />],
    ['Ism familiya', [a.firstName, a.lastName].filter(Boolean).join(' ') || '—'],
    ['Telefon', a.phone || '—'],
    ['Email', <span key="e" className="flex items-center gap-2">{a.email || '—'}<Verified ok={a.emailVerified} /></span>],
    a.telegram ? ['Telegram', a.telegram] : null,
    a.login ? ['Login', `@${a.login}`] : null,
    a.region ? ['Viloyat', a.region] : null,
    a.role === 'seller' ? ['AI sotuvchi', a.aiName] : null,
    a.role === 'seller' && a.location ? ['Manzil', a.location.address || `${a.location.lat}, ${a.location.lon}`] : null,
    a.role === 'seller' ? ['Mahsulot / tushum', `${num(a.products)} ta · ${money(a.revenue)}`] : null,
    a.role === 'courier' ? ['Transport', `${VEHICLE[a.vehicle] || a.vehicle}${a.plate ? ` · ${a.plate}` : ''}`] : null,
    a.role === 'cargo' ? ['Mashina', `${TRUCK[a.vehicleType] || a.vehicleType} · ${a.plate} · ${num(a.capacityKg)} kg`] : null,
    a.role === 'cargo' ? ['Tarif', `${money(a.basePrice)} + ${money(a.pricePerKm)}/km`] : null,
    a.role === 'cargo' ? ["Yo'nalishlar", (a.regions || []).join(', ') || '—'] : null,
    ['Holat', a.active ? <Badge key="s" tone="green">Faol</Badge> : <Badge key="s" tone="rose">Bloklangan</Badge>],
    ['Ro\'yxatdan o\'tgan', date(a.registeredAt || a.createdAt)],
    a.lastLoginAt ? ['Oxirgi kirish', date(a.lastLoginAt)] : null,
    a.lastActivity ? ['Oxirgi faollik', ago(a.lastActivity)] : null,
  ].filter(Boolean) : [];

  return (
    <>
      {confirmEl}
      <Modal open title={acc.name} onClose={onClose}
        footer={a && <>
          {a.shopId && <Link className="btn" href={`/shops/${a.shopId}`}>Do'kon sahifasi</Link>}
          <button className={`btn ${a.active ? 'btn-danger' : 'btn-primary'}`} disabled={busy} onClick={toggle}>
            {a.active ? <><Ban size={14} />Bloklash</> : <><CheckCircle2 size={14} />Blokdan chiqarish</>}
          </button>
        </>}>
        <ErrorBox error={error} retry={reload} />
        {loading && <div className="space-y-2">{Array.from({ length: 6 }).map((_, i) => <div key={i} className="skeleton h-5" />)}</div>}
        {a && (
          <>
            <dl className="space-y-2 text-xs">
              {rows.map(([k, v]) => (
                <div key={k} className="flex justify-between gap-3 border-b border-line pb-2 last:border-0">
                  <dt className="text-muted">{k}</dt>
                  <dd className="truncate text-right font-medium text-text-2">{v}</dd>
                </div>
              ))}
            </dl>
            {data.orders?.length > 0 && (
              <div className="mt-4">
                <div className="mb-1.5 text-xs font-semibold text-muted">Oxirgi buyurtmalar</div>
                <ul className="space-y-1.5 text-xs">
                  {data.orders.slice(0, 6).map((o) => (
                    <li key={o.id} className="flex items-center justify-between gap-2 border-b border-line pb-1.5 last:border-0">
                      <span className="truncate">{o.productName}</span>
                      <span className="shrink-0 text-muted">{moneyShort(o.price)} · {ago(o.createdAt)}</span>
                    </li>
                  ))}
                </ul>
              </div>
            )}
          </>
        )}
      </Modal>
    </>
  );
}

export default function UsersPage() {
  const [q, setQ] = useState('');
  const [role, setRole] = useState('');
  const [verified, setVerified] = useState('');
  const [status, setStatus] = useState('');
  const [page, setPage] = useState(1);
  const [open, setOpen] = useState(null);
  const dq = useDebounced(q);
  const { data, loading, error, reload } = useApi('/users', { query: { q: dq, role, verified, status, page, limit: 30 } });
  const c = data?.counts;
  const reset = (fn) => (v) => { fn(v); setPage(1); };

  return (
    <>
      {open && <AccountModal acc={open} onClose={() => setOpen(null)} onChanged={reload} />}
      <PageTitle title="Foydalanuvchilar" sub={data && `Jami ${num(data.total)} ta hisob${c ? ` · ${num(c.guests)} mehmon` : ''}`} />
      <ErrorBox error={error} retry={reload} />
      <Card pad={false}>
        <Toolbar>
          <div className="relative">
            <Search size={14} className="absolute left-3 top-[11px] text-muted" />
            <input className="input w-72 pl-9" placeholder="Ism, telefon, email, login…" value={q} onChange={(e) => reset(setQ)(e.target.value)} />
          </div>
          <Segmented value={role} onChange={reset(setRole)} options={[
            ['', c ? `Barchasi ${c.all}` : 'Barchasi'],
            ['buyer', c ? `Xaridor ${c.buyer}` : 'Xaridor'],
            ['seller', c ? `Sotuvchi ${c.seller}` : 'Sotuvchi'],
            ['courier', c ? `Kuryer ${c.courier}` : 'Kuryer'],
            ['cargo', c ? `Yuk tashuvchi ${c.cargo}` : 'Yuk tashuvchi'],
          ]} />
          <Segmented value={verified} onChange={reset(setVerified)} options={[['', 'Email: barchasi'], ['1', 'Tasdiqlangan'], ['0', 'Tasdiqlanmagan']]} />
          <Segmented value={status} onChange={reset(setStatus)} options={[['', 'Holat: barchasi'], ['active', 'Faol'], ['blocked', 'Bloklangan']]} />
        </Toolbar>
        <Table loading={loading} rows={data?.items || []} onRow={(u) => setOpen(u)}
          empty="Hisob topilmadi. Ilovada ro'yxatdan o'tganlar shu yerda ko'rinadi."
          cols={[
            { key: 'name', label: 'Foydalanuvchi', render: (u) => (
              <div className="flex items-center gap-2.5">
                <Avatar name={u.fullName || u.name} size={30} rounded="rounded-full" />
                <div className="min-w-0">
                  <div className="font-medium">{u.fullName || u.name || '—'}</div>
                  <div className="truncate text-xs text-muted">{u.login ? `@${u.login}` : u.telegram || <span className="mono">{u.id}</span>}</div>
                </div>
              </div>
            ) },
            { key: 'role', label: 'Rol', render: (u) => <RoleBadge role={u.role} /> },
            { key: 'contact', label: 'Aloqa', render: (u) => (
              <div className="min-w-0">
                <div className="text-xs text-text-2">{u.phone || '—'}</div>
                <div className="flex items-center gap-1 truncate text-xs text-muted">
                  {u.email || '—'}{u.emailVerified && <BadgeCheck size={12} className="shrink-0 text-emerald-500" />}
                </div>
              </div>
            ) },
            { key: 'region', label: 'Viloyat', render: (u) => <span className="text-xs text-text-2">{u.region || '—'}</span> },
            { key: 'shop', label: "Do'kon", render: (u) => u.shopId
              ? <Link href={`/shops/${u.shopId}`} className="text-xs hover:underline" onClick={(e) => e.stopPropagation()}>{u.shop || u.shopId}</Link>
              : <span className="text-xs text-muted">—</span> },
            { key: 'status', label: 'Holat', render: (u) => u.active ? <Badge tone="green">Faol</Badge> : <Badge tone="rose">Bloklangan</Badge> },
            { key: 'orders', label: 'Buyurtma', cls: 'text-right tabular-nums', render: (u) => num(u.orders) },
            { key: 'amount', label: 'Summa', cls: 'text-right tabular-nums font-medium', render: (u) => moneyShort(u.amount) },
            { key: 'lastActivity', label: 'Oxirgi faollik', render: (u) => <span className="text-xs text-muted">{u.lastActivity ? ago(u.lastActivity) : '—'}</span> },
          ]} />
        {data && <Pagination page={data.page} limit={data.limit} total={data.total} onPage={setPage} />}
      </Card>
    </>
  );
}
