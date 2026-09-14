'use client';
import { useState } from 'react';
import Link from 'next/link';
import { Eye, EyeOff, Search, Trash2 } from 'lucide-react';
import { Avatar, Badge, Card, ErrorBox, Modal, PageTitle, Pagination, Segmented, Table, Toolbar, useConfirm } from '@/components/ui';
import { useApi, useDebounced } from '@/lib/hooks';
import { api, photoUrl } from '@/lib/api';
import { date, money, num } from '@/lib/format';

export default function Products() {
  const [q, setQ] = useState('');
  const [active, setActive] = useState('');
  const [sort, setSort] = useState('createdAt');
  const [page, setPage] = useState(1);
  const [view, setView] = useState(null);
  const dq = useDebounced(q);
  const { data, loading, error, reload } = useApi('/products', { query: { q: dq, active, sort, page, limit: 30 } });
  const [confirm, confirmEl] = useConfirm();

  const toggle = async (p) => { await api(`/products/${p.id}`, { method: 'PATCH', body: { active: !p.active } }); reload(); };
  const del = async (p) => { if (await confirm({ title: "Mahsulotni o'chirish", text: `"${p.name}" butunlay o'chiriladi.`, danger: true, ok: "O'chirish" })) { await api(`/products/${p.id}`, { method: 'DELETE' }); reload(); } };

  return (
    <>
      {confirmEl}
      <PageTitle title="Mahsulotlar" sub={data && `Jami ${num(data.total)} ta`} />
      <ErrorBox error={error} retry={reload} />
      <Card pad={false}>
        <Toolbar>
          <div className="relative"><Search size={14} className="absolute left-3 top-[11px] text-muted" /><input className="input w-64 pl-9" placeholder="Mahsulot nomi…" value={q} onChange={(e) => { setQ(e.target.value); setPage(1); }} /></div>
          <Segmented value={active} onChange={(v) => { setActive(v); setPage(1); }} options={[['', 'Hammasi'], ['1', 'Faol'], ['0', 'Yashirin']]} />
          <select className="input" value={sort} onChange={(e) => setSort(e.target.value)}><option value="createdAt">Yangi avval</option><option value="views">Ko'p ko'rilgan</option><option value="price">Qimmat avval</option><option value="priceAsc">Arzon avval</option></select>
        </Toolbar>
        <Table loading={loading} rows={data?.items || []} cols={[
          { key: 'name', label: 'Mahsulot', render: (p) => (
            <button className="flex items-center gap-3 text-left" onClick={() => setView(p)}>
              <Avatar src={photoUrl(p.photos[0])} name={p.name} size={36} />
              <div className="min-w-0"><div className={`font-medium ${p.active ? '' : 'text-muted line-through'}`}>{p.name}</div><div className="line-clamp-1 max-w-xs text-xs text-muted">{p.description || '—'}</div></div>
            </button>
          ) },
          { key: 'shop', label: "Do'kon", render: (p) => <Link href={`/shops/${p.shopId}`} className="text-xs text-text-2 hover:underline">{p.shop || p.shopId}</Link> },
          { key: 'price', label: 'Narx', cls: 'text-right tabular-nums font-medium', render: (p) => money(p.price) },
          { key: 'views', label: "Ko'rish", cls: 'text-right tabular-nums', render: (p) => num(p.views) },
          { key: 'photos', label: 'Rasm', cls: 'text-center', render: (p) => <Badge>{p.photos.length}</Badge> },
          { key: 'active', label: 'Holat', render: (p) => p.active ? <Badge tone="green">Faol</Badge> : <Badge>Yashirin</Badge> },
          { key: 'createdAt', label: "Qo'shilgan", render: (p) => <span className="text-xs text-muted">{date(p.createdAt, false)}</span> },
          { key: 'act', label: '', cls: 'text-right', render: (p) => <span className="flex justify-end gap-1"><button className="btn btn-sm btn-icon" title={p.active ? 'Yashirish' : "Ko'rsatish"} onClick={() => toggle(p)}>{p.active ? <EyeOff size={13} /> : <Eye size={13} />}</button><button className="btn btn-sm btn-icon btn-danger" onClick={() => del(p)}><Trash2 size={13} /></button></span> },
        ]} />
        {data && <Pagination page={data.page} limit={data.limit} total={data.total} onPage={setPage} />}
      </Card>

      <Modal open={Boolean(view)} title={view?.name} onClose={() => setView(null)}>
        {view && <>
          <div className="mb-3 flex gap-2 overflow-x-auto">{view.photos.map((ph) => <img key={ph} src={photoUrl(ph)} alt="" className="h-32 w-32 shrink-0 rounded-xl object-cover ring-1 ring-line" />)}</div>
          <p className="text-sm text-text-2">{view.description || <span className="text-muted">Tavsif yo'q</span>}</p>
          <dl className="mt-3 grid grid-cols-2 gap-2 text-xs">
            {[['Narx', money(view.price)], ["Ko'rishlar", num(view.views)], ["Do'kon", view.shop], ['ID', <span className="mono" key="id">{view.id}</span>]].map(([k, v]) => (
              <div key={k} className="rounded-xl bg-panel-2 p-3"><dt className="kicker">{k}</dt><dd className="mt-1 font-medium">{v}</dd></div>
            ))}
          </dl>
        </>}
      </Modal>
    </>
  );
}
