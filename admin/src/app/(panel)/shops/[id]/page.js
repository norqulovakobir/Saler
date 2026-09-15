'use client';
import { useState } from 'react';
import Link from 'next/link';
import { useParams, useRouter } from 'next/navigation';
import { ArrowLeft, Ban, CheckCircle2, Eye, EyeOff, Mail, MapPin, Package, Phone, ShoppingCart, Trash2, Users, Wallet } from 'lucide-react';
import { Avatar, Badge, Card, ErrorBox, PageTitle, Stat, StatusBadge, Table, useConfirm } from '@/components/ui';
import { AreaSeries } from '@/components/charts';
import { useApi } from '@/lib/hooks';
import { api, photoUrl } from '@/lib/api';
import { ago, date, money, moneyShort, num, shortDay } from '@/lib/format';

export default function ShopDetail() {
  const { id } = useParams();
  const router = useRouter();
  const { data, loading, error, reload } = useApi(`/shops/${id}`);
  const [confirm, confirmEl] = useConfirm();
  const [busy, setBusy] = useState(false);
  const s = data?.shop;

  const toggleProduct = async (p) => { await api(`/products/${p.id}`, { method: 'PATCH', body: { active: !p.active } }); reload(); };
  const delProduct = async (p) => { if (await confirm({ title: "Mahsulotni o'chirish", text: `"${p.name}" butunlay o'chiriladi.`, danger: true, ok: "O'chirish" })) { await api(`/products/${p.id}`, { method: 'DELETE' }); reload(); } };
  const setStatus = async (o, status) => { await api(`/orders/${o.id}`, { method: 'PATCH', body: { status } }); reload(); };
  const toggleActive = async () => {
    const block = s.active;
    const ok = await confirm({
      title: block ? "Do'konni bloklash" : 'Blokdan chiqarish',
      text: block ? `"${s.name}" bloklanadi: sotuvchi hisobiga kira olmaydi, ochiq sessiyalari yopiladi. Mahsulotlar o'chirilmaydi.` : `"${s.name}" sotuvchisi yana kirishi mumkin.`,
      danger: block,
      ok: block ? 'Bloklash' : 'Ochish',
    });
    if (!ok) return;
    setBusy(true);
    try { await api(`/shops/${id}`, { method: 'PATCH', body: { active: !s.active } }); reload(); } finally { setBusy(false); }
  };
  const delShop = async () => {
    if (!(await confirm({ title: "Do'konni o'chirish", text: `"${s.name}" do'koni, uning ${data.products.length} ta mahsuloti va ${data.stats.totalOrders} ta buyurtmasi butunlay o'chiriladi. Qaytarib bo'lmaydi.`, danger: true, ok: "Ha, o'chirish" }))) return;
    setBusy(true);
    try { await api(`/shops/${id}`, { method: 'DELETE' }); router.replace('/shops'); } finally { setBusy(false); }
  };

  if (error) return <ErrorBox error={error} retry={reload} />;
  if (loading || !data) return <div className="space-y-4"><div className="skeleton h-12 w-1/2" /><div className="skeleton h-28" /><div className="skeleton h-64" /></div>;
  const st = data.stats;

  return (
    <>
      {confirmEl}
      <Link href="/shops" className="mb-3 inline-flex items-center gap-1 text-xs text-muted hover:text-text"><ArrowLeft size={12} />Do'konlar</Link>
      <PageTitle
        title={<span className="flex items-center gap-3"><Avatar src={photoUrl(s.logo)} name={s.name} size={40} rounded="rounded-xl" />{s.name}<span className="text-sm font-normal text-muted">@{s.login}</span>{s.active ? <Badge tone="green">Faol</Badge> : <Badge tone="rose">Bloklangan</Badge>}</span>}
        sub={`Egasi: ${s.ownerName || '—'} · AI sotuvchi: ${s.sellerName || 'Madina'} · Viloyat: ${s.region || '—'} · Ochilgan: ${date(s.createdAt)}${s.lastLoginAt ? ` · Oxirgi kirish: ${ago(s.lastLoginAt)}` : ''}`}
        action={<>
          <button className={`btn ${s.active ? 'btn-danger' : 'btn-primary'}`} disabled={busy} onClick={toggleActive}>{s.active ? <><Ban size={14} />Bloklash</> : <><CheckCircle2 size={14} />Blokdan chiqarish</>}</button>
          <button className="btn btn-danger" disabled={busy} onClick={delShop}><Trash2 size={14} />O'chirish</button>
        </>} />

      <div className="grid grid-cols-2 gap-3 md:grid-cols-4 xl:grid-cols-8">
        <Stat label="Tushum" value={moneyShort(st.revenue)} icon={Wallet} />
        <Stat label="Buyurtmalar" value={num(st.totalOrders)} sub={`Yangi ${st.newOrders} · Bajarildi ${st.doneOrders}`} icon={ShoppingCart} />
        <Stat label="Mahsulotlar" value={num(st.productCount)} sub={`Yashirin ${st.hiddenCount}`} icon={Package} />
        <Stat label="Ko'rishlar" value={num(st.views)} icon={Eye} />
        <Stat label="Obunachilar" value={num(st.followers)} icon={Users} />
        <Stat label="Telefon" value={<span className="text-base">{s.phone || '—'}</span>} icon={Phone} />
        <Stat label="Email" value={<span className="text-sm">{s.email || '—'}</span>} sub={s.email ? (s.emailVerified ? 'Tasdiqlangan' : 'Tasdiqlanmagan') : null} icon={Mail} />
        <Stat label="Joylashuv" value={<span className="text-sm">{s.location?.lat ? (s.location.address || `${s.location.lat.toFixed(4)}, ${s.location.lon.toFixed(4)}`) : "Yo'q"}</span>} sub={s.location?.lat ? <a className="hover:underline" target="_blank" rel="noreferrer" href={`https://www.google.com/maps?q=${s.location.lat},${s.location.lon}`}>Xaritada ochish</a> : null} icon={MapPin} />
      </div>

      <div className="mt-4 grid gap-4 xl:grid-cols-3">
        <Card title="Buyurtmalar · 30 kun" className="xl:col-span-2">
          <AreaSeries data={data.byDay} series={[{ key: 'n', name: 'Buyurtma', color: 'c1' }]} xFmt={shortDay} h={200} />
        </Card>
        <Card title="Sotuvchi" sub="Do'kon egasi va AI sotuvchi">
          <ul className="space-y-2.5 text-sm">
            {data.sellers.map((u) => (
              <li key={u.id} className="flex items-center justify-between gap-2">
                <span className="flex min-w-0 items-center gap-2"><Avatar name={u.name} size={26} rounded="rounded-full" /><span className="truncate">{u.name || '—'}{u.username && <span className="text-xs text-muted"> @{u.username}</span>}</span></span>
                <span className="flex gap-1">{u.owner && <Badge tone="dark">Egasi</Badge>}</span>
              </li>
            ))}
            <li className="flex items-center justify-between gap-2">
              <span className="flex min-w-0 items-center gap-2"><Avatar name={s.sellerName || 'M'} size={26} rounded="rounded-full" /><span className="truncate">{s.sellerName || 'Madina'}</span></span>
              <Badge tone="blue">AI sotuvchi</Badge>
            </li>
          </ul>
          {s.description && <p className="mt-3 border-t border-line pt-3 text-xs text-text-2">{s.description}</p>}
        </Card>
      </div>

      <Card title={`Mahsulotlar · ${data.products.length}`} className="mt-4" pad={false}>
        <Table rows={data.products} cols={[
          { key: 'name', label: 'Mahsulot', render: (p) => <div className="flex items-center gap-2.5"><Avatar src={photoUrl(p.photos[0])} name={p.name} /><span className={p.active ? 'font-medium' : 'text-muted line-through'}>{p.name}</span></div> },
          { key: 'price', label: 'Narx', cls: 'text-right tabular-nums', render: (p) => money(p.price) },
          { key: 'views', label: "Ko'rish", cls: 'text-right tabular-nums', render: (p) => num(p.views) },
          { key: 'active', label: 'Holat', render: (p) => p.active ? <Badge tone="green">Faol</Badge> : <Badge>Yashirin</Badge> },
          { key: 'createdAt', label: "Qo'shilgan", render: (p) => <span className="text-xs text-muted">{date(p.createdAt, false)}</span> },
          { key: 'act', label: '', cls: 'text-right', render: (p) => <span className="flex justify-end gap-1"><button className="btn btn-sm btn-icon" onClick={() => toggleProduct(p)}>{p.active ? <EyeOff size={13} /> : <Eye size={13} />}</button><button className="btn btn-sm btn-icon btn-danger" onClick={() => delProduct(p)}><Trash2 size={13} /></button></span> },
        ]} />
      </Card>

      <Card title="Oxirgi buyurtmalar" className="mt-4" pad={false}>
        <Table rows={data.orders} cols={[
          { key: 'id', label: 'ID', render: (o) => <span className="mono text-xs text-muted">{o.id}</span> },
          { key: 'items', label: 'Mahsulot', render: (o) => <span className="line-clamp-1">{(o.items || [{ name: o.productName, qty: 1 }]).map((i) => `${i.name}${i.qty > 1 ? ` ×${i.qty}` : ''}`).join(', ')}</span> },
          { key: 'customerName', label: 'Xaridor', render: (o) => <>{o.customerName}<div className="text-xs text-muted">{o.phone}</div></> },
          { key: 'price', label: 'Summa', cls: 'text-right tabular-nums font-medium', render: (o) => money(o.price) },
          { key: 'status', label: 'Holat', render: (o) => <StatusBadge status={o.status} /> },
          { key: 'createdAt', label: 'Vaqt', render: (o) => <span className="text-xs text-muted">{ago(o.createdAt)}</span> },
          { key: 'act', label: '', cls: 'text-right', render: (o) => <select className="input h-8 text-xs" value={o.status} onChange={(e) => setStatus(o, e.target.value)}><option value="new">Yangi</option><option value="done">Bajarildi</option><option value="cancelled">Bekor</option></select> },
        ]} />
      </Card>
    </>
  );
}
