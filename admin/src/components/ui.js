'use client';
import { useEffect, useState } from 'react';
import { ChevronLeft, ChevronRight, TrendingDown, TrendingUp, X } from 'lucide-react';
import { STATUS, num } from '@/lib/format';

export function Card({ title, sub, action, children, className = '', pad = true }) {
  return (
    <section className={`card overflow-hidden ${className}`}>
      {(title || action) && (
        <header className="flex items-center justify-between gap-3 px-4 pt-3.5 pb-2">
          <div><h3 className="text-[13.5px] font-semibold tracking-tight">{title}</h3>{sub && <p className="text-xs text-muted">{sub}</p>}</div>
          {action}
        </header>
      )}
      <div className={pad ? `px-4 pb-4 ${title ? 'pt-1' : 'pt-4'}` : ''}>{children}</div>
    </section>
  );
}

// Ko'rsatkich kartasi
export function Stat({ label, value, sub, growth, icon: Icon, loading }) {
  return (
    <div className="card p-4">
      <div className="flex items-center justify-between gap-2">
        <span className="kicker truncate">{label}</span>
        {Icon && <Icon size={15} className="shrink-0 text-muted" />}
      </div>
      {loading ? <div className="skeleton mt-2 h-7 w-24" /> : <div className="stat-value mt-1.5 truncate">{value}</div>}
      <div className="mt-1.5 flex items-center gap-2 text-xs text-muted">
        {growth !== undefined && growth !== null && !loading && (
          <span className={`badge ${growth >= 0 ? 'badge-green' : 'badge-rose'}`}>
            {growth >= 0 ? <TrendingUp size={11} /> : <TrendingDown size={11} />}{Math.abs(growth)}%
          </span>
        )}
        {sub && !loading && <span className="truncate">{sub}</span>}
        {loading && <div className="skeleton h-3 w-32" />}
      </div>
    </div>
  );
}

export function Badge({ children, tone = 'neutral' }) {
  return <span className={`badge badge-${tone}`}>{children}</span>;
}
export function StatusBadge({ status }) {
  const s = STATUS[status] || { label: status || '—', tone: 'neutral' };
  return <Badge tone={s.tone}>{s.label}</Badge>;
}

export function Table({ cols, rows, empty = "Ma'lumot yo'q", loading, rowKey = (r) => r.id, onRow }) {
  return (
    <div className="overflow-x-auto">
      <table className="w-full min-w-[640px] border-collapse text-[13px]">
        <thead><tr>{cols.map((c) => <th key={c.key} className={`th ${c.cls || ''}`}>{c.label}</th>)}</tr></thead>
        <tbody>
          {loading && Array.from({ length: 6 }).map((_, i) => (
            <tr key={i} className="tr">{cols.map((c) => <td key={c.key} className="td"><div className="skeleton h-4 w-3/4" /></td>)}</tr>
          ))}
          {!loading && rows.length === 0 && <tr className="tr"><td className="td py-12 text-center text-muted" colSpan={cols.length}>{empty}</td></tr>}
          {!loading && rows.map((r) => (
            <tr key={rowKey(r)} className={`tr ${onRow ? 'cursor-pointer' : ''}`} onClick={onRow ? () => onRow(r) : undefined}>
              {cols.map((c) => <td key={c.key} className={`td ${c.cls || ''}`}>{c.render ? c.render(r) : r[c.key]}</td>)}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export function Pagination({ page, limit, total, onPage }) {
  const pages = Math.max(1, Math.ceil(total / limit));
  return (
    <div className="flex items-center justify-between gap-3 border-t border-line px-4 py-2.5 text-xs text-muted">
      <span>Jami <b className="font-semibold text-text">{num(total)}</b> ta · {page}/{pages} sahifa</span>
      <div className="flex gap-1">
        <button className="btn btn-sm btn-icon" disabled={page <= 1} onClick={() => onPage(page - 1)}><ChevronLeft size={14} /></button>
        <button className="btn btn-sm btn-icon" disabled={page >= pages} onClick={() => onPage(page + 1)}><ChevronRight size={14} /></button>
      </div>
    </div>
  );
}

export function Modal({ open, title, onClose, children, footer }) {
  useEffect(() => {
    if (!open) return;
    const h = (e) => e.key === 'Escape' && onClose();
    window.addEventListener('keydown', h);
    return () => window.removeEventListener('keydown', h);
  }, [open, onClose]);
  if (!open) return null;
  return (
    <div className="fixed inset-0 z-50 grid place-items-center bg-black/50 p-4 backdrop-blur-[2px]" onClick={onClose}>
      <div className="card w-full max-w-lg" onClick={(e) => e.stopPropagation()}>
        <header className="flex items-center justify-between border-b border-line px-4 py-3">
          <h3 className="font-semibold">{title}</h3>
          <button className="btn btn-sm btn-icon btn-ghost" onClick={onClose}><X size={16} /></button>
        </header>
        <div className="p-4">{children}</div>
        {footer && <footer className="flex justify-end gap-2 border-t border-line px-4 py-3">{footer}</footer>}
      </div>
    </div>
  );
}

// Tasdiqlash oynasi (confirm() o'rniga)
export function useConfirm() {
  const [state, setState] = useState(null);
  const confirm = (opts) => new Promise((resolve) => setState({ ...opts, resolve }));
  const el = (
    <Modal open={Boolean(state)} title={state?.title || 'Tasdiqlang'} onClose={() => { state?.resolve(false); setState(null); }}
      footer={<>
        <button className="btn" onClick={() => { state.resolve(false); setState(null); }}>Bekor</button>
        <button className={`btn ${state?.danger ? 'btn-danger' : 'btn-primary'}`} onClick={() => { state.resolve(true); setState(null); }}>{state?.ok || 'Ha'}</button>
      </>}>
      <p className="text-sm text-text-2">{state?.text}</p>
    </Modal>
  );
  return [confirm, el];
}

export function Toolbar({ children }) {
  return <div className="flex flex-wrap items-center gap-2 border-b border-line px-4 py-3">{children}</div>;
}

// Segment tugmalar (filtr)
export function Segmented({ value, onChange, options }) {
  return (
    <div className="seg">
      {options.map(([v, l]) => <button key={v} className={value === v ? 'on' : ''} onClick={() => onChange(v)}>{l}</button>)}
    </div>
  );
}

export function PageTitle({ title, sub, action }) {
  return (
    <div className="mb-5 flex flex-wrap items-end justify-between gap-3">
      <div><h1 className="text-[20px] font-semibold tracking-tight">{title}</h1>{sub && <p className="mt-0.5 text-xs text-muted">{sub}</p>}</div>
      {action && <div className="flex flex-wrap items-center gap-2">{action}</div>}
    </div>
  );
}

export function ErrorBox({ error, retry }) {
  if (!error) return null;
  return (
    <div className="card mb-4 flex items-center justify-between gap-3 border-rose-500/40 px-4 py-3 text-sm text-rose-600 dark:text-rose-300">
      <span>{String(error.message || error)}</span>
      {retry && <button className="btn btn-sm" onClick={retry}>Qayta</button>}
    </div>
  );
}

export function Avatar({ src, name, size = 32, rounded = 'rounded-lg' }) {
  return src
    ? <img src={src} alt="" style={{ width: size, height: size }} className={`${rounded} shrink-0 object-cover ring-1 ring-line`} />
    : <div style={{ width: size, height: size }} className={`${rounded} grid shrink-0 place-items-center bg-panel-2 text-xs font-semibold text-muted ring-1 ring-line`}>{(name || '?').slice(0, 1).toUpperCase()}</div>;
}
