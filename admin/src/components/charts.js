'use client';
import { Area, AreaChart, Bar, BarChart, CartesianGrid, Cell, Legend, Line, LineChart, Pie, PieChart, PolarAngleAxis, RadialBar, RadialBarChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import { useChartTheme } from '@/components/theme';
import { num } from '@/lib/format';

// Seriya ranglari: nomlar mavzuga qarab CSS o'zgaruvchilaridan olinadi (useChartTheme)
export const K = { primary: 'c1', gray: 'c2', green: 'c3', amber: 'c4', red: 'c5', blue: 'c6', violet: 'c7', cyan: 'c8' };

// O'q belgilari: pul uchun "1.5 ming / 2.3 mln", son uchun butun
const tickMoney = (v) => {
  const a = Math.abs(v);
  if (a >= 1e9) return `${+(v / 1e9).toFixed(1)} mlrd`;
  if (a >= 1e6) return `${+(v / 1e6).toFixed(1)} mln`;
  if (a >= 1e3) return `${+(v / 1e3).toFixed(1)} ming`;
  return num(v);
};
const fmtVal = (money) => (v, n) => [money ? `${num(v)} so'm` : num(v), n];

function useParts(money) {
  const t = useChartTheme();
  if (!t) return null;
  const axis = { stroke: t.grid, tick: { fill: t.axis, fontSize: 11 }, tickLine: false, axisLine: false };
  return {
    t,
    axis,
    grid: { stroke: t.grid, strokeDasharray: '3 3', vertical: false },
    tip: {
      contentStyle: { background: t.tipBg, border: 'none', borderRadius: 10, fontSize: 12, padding: '8px 10px', boxShadow: '0 6px 24px rgba(0,0,0,.18)' },
      labelStyle: { color: t.tipMuted, marginBottom: 4 },
      itemStyle: { color: t.tipFg, padding: 0 },
      cursor: { fill: t.panel2, opacity: 0.6 },
    },
    yProps: { ...axis, width: 64, tickFormatter: money ? tickMoney : num, allowDecimals: false, tickMargin: 4 },
    color: (s) => t[s.color] || s.color,
  };
}

function Wrap({ h = 240, children }) {
  return <div style={{ height: h, width: '100%' }}><ResponsiveContainer>{children}</ResponsiveContainer></div>;
}
const Skel = ({ h }) => <div className="skeleton" style={{ height: h }} />;

export function AreaSeries({ data, x = 'date', series, h = 240, money = false, xFmt }) {
  const p = useParts(money);
  if (!p) return <Skel h={h} />;
  return (
    <Wrap h={h}>
      <AreaChart data={data} margin={{ top: 8, right: 8, left: 0, bottom: 0 }}>
        <defs>
          {series.map((s) => (
            <linearGradient key={s.key} id={`g-${s.key}`} x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor={p.color(s)} stopOpacity={0.22} /><stop offset="100%" stopColor={p.color(s)} stopOpacity={0} />
            </linearGradient>
          ))}
        </defs>
        <CartesianGrid {...p.grid} />
        <XAxis dataKey={x} {...p.axis} tickFormatter={xFmt} minTickGap={28} />
        <YAxis {...p.yProps} />
        <Tooltip {...p.tip} formatter={fmtVal(money)} />
        {series.length > 1 && <Legend iconType="circle" iconSize={8} wrapperStyle={{ fontSize: 12 }} />}
        {series.map((s) => <Area key={s.key} type="monotone" dataKey={s.key} name={s.name} stroke={p.color(s)} fill={`url(#g-${s.key})`} strokeWidth={2} dot={false} activeDot={{ r: 4, strokeWidth: 0 }} />)}
      </AreaChart>
    </Wrap>
  );
}

export function Bars({ data, x, series, h = 240, money = false, stacked = false, xFmt, layout }) {
  const p = useParts(money);
  if (!p) return <Skel h={h} />;
  const vertical = layout === 'vertical';
  return (
    <Wrap h={h}>
      <BarChart data={data} margin={{ top: 8, right: 8, left: 0, bottom: 0 }} layout={layout} barCategoryGap="28%">
        <CartesianGrid {...p.grid} vertical={vertical} horizontal={!vertical} />
        {/* Recharts o'qlarni Fragment ichidan topmaydi — alohida shartli elementlar */}
        {vertical && <XAxis type="number" {...p.axis} tickFormatter={money ? tickMoney : num} allowDecimals={false} />}
        {vertical && <YAxis type="category" dataKey={x} {...p.axis} width={120} />}
        {!vertical && <XAxis dataKey={x} {...p.axis} tickFormatter={xFmt} minTickGap={16} />}
        {!vertical && <YAxis {...p.yProps} />}
        <Tooltip {...p.tip} formatter={fmtVal(money)} />
        {series.length > 1 && <Legend iconType="circle" iconSize={8} wrapperStyle={{ fontSize: 12 }} />}
        {series.map((s, i) => <Bar key={s.key} dataKey={s.key} name={s.name} fill={p.color(s)} stackId={stacked ? 'a' : undefined} radius={stacked && i < series.length - 1 ? 0 : vertical ? [0, 6, 6, 0] : [6, 6, 0, 0]} maxBarSize={vertical ? 18 : 34} />)}
      </BarChart>
    </Wrap>
  );
}

export function Lines({ data, x, series, h = 240, money = false, xFmt }) {
  const p = useParts(money);
  if (!p) return <Skel h={h} />;
  return (
    <Wrap h={h}>
      <LineChart data={data} margin={{ top: 8, right: 8, left: 0, bottom: 0 }}>
        <CartesianGrid {...p.grid} />
        <XAxis dataKey={x} {...p.axis} tickFormatter={xFmt} minTickGap={28} />
        <YAxis {...p.yProps} />
        <Tooltip {...p.tip} formatter={fmtVal(money)} />
        <Legend iconType="circle" iconSize={8} wrapperStyle={{ fontSize: 12 }} />
        {series.map((s) => <Line key={s.key} type="monotone" dataKey={s.key} name={s.name} stroke={p.color(s)} strokeWidth={2} dot={false} strokeDasharray={s.dashed ? '5 4' : undefined} />)}
      </LineChart>
    </Wrap>
  );
}

export function Donut({ data, h = 200, nameKey = 'name', valueKey = 'value', center }) {
  const p = useParts(false);
  if (!p) return <Skel h={h} />;
  const total = data.reduce((s, d) => s + (d[valueKey] || 0), 0);
  const rows = data.map((d) => ({ ...d, fill: p.t[d.color] || d.color }));
  return (
    <div className="flex items-center gap-5">
      <div style={{ width: h, height: h }} className="relative shrink-0">
        <ResponsiveContainer>
          <PieChart>
            <Pie data={total ? rows : [{ [nameKey]: '—', [valueKey]: 1, fill: p.t.panel2 }]} dataKey={valueKey} nameKey={nameKey} innerRadius="68%" outerRadius="92%" paddingAngle={total ? 3 : 0} stroke="none" cornerRadius={3}>
              {(total ? rows : [{ fill: p.t.panel2 }]).map((d, i) => <Cell key={i} fill={d.fill} />)}
            </Pie>
            {total > 0 && <Tooltip {...p.tip} formatter={(v) => num(v)} />}
          </PieChart>
        </ResponsiveContainer>
        <div className="pointer-events-none absolute inset-0 grid place-items-center text-center">
          <div><div className="text-lg font-semibold tabular-nums leading-none">{num(total)}</div><div className="mt-1 text-[10px] uppercase tracking-wide text-muted">{center || 'jami'}</div></div>
        </div>
      </div>
      <ul className="flex-1 space-y-2 text-xs">
        {rows.map((d, i) => (
          <li key={i} className="flex items-center justify-between gap-2">
            <span className="flex items-center gap-2 text-text-2"><i className="inline-block h-2.5 w-2.5 rounded-full" style={{ background: d.fill }} />{d[nameKey]}</span>
            <span className="tabular-nums"><b className="font-semibold">{num(d[valueKey])}</b><span className="text-muted"> · {total ? Math.round((d[valueKey] / total) * 100) : 0}%</span></span>
          </li>
        ))}
      </ul>
    </div>
  );
}

/// Ombor to'lganligi: yarim doira gauge. Chegaraga yaqinlashgan sari rang
/// yashildan sariqqa, keyin qizilga o'tadi — foizni o'qimasdan ham ko'rinadi.
export function Gauge({ percent, h = 170, label, value, limit }) {
  const p = useParts(false);
  if (!p) return <Skel h={h} />;
  const pct = Math.max(0, Math.min(100, Number(percent) || 0));
  const tone = pct >= 90 ? 'c5' : pct >= 70 ? 'c4' : 'c3';
  const fill = p.t[tone] || tone;
  const rows = [{ name: label, value: pct, fill }];
  return (
    <div className="relative" style={{ height: h }}>
      <ResponsiveContainer>
        <RadialBarChart data={rows} startAngle={210} endAngle={-30} innerRadius="66%" outerRadius="100%" barSize={16}>
          <PolarAngleAxis type="number" domain={[0, 100]} tick={false} />
          <RadialBar dataKey="value" background={{ fill: p.t.panel2 }} cornerRadius={8} />
        </RadialBarChart>
      </ResponsiveContainer>
      <div className="pointer-events-none absolute inset-0 grid place-items-center text-center">
        <div>
          <div className="text-2xl font-semibold tabular-nums leading-none" style={{ color: fill }}>
            {pct < 0.01 && pct > 0 ? '<0.01' : pct}%
          </div>
          <div className="mt-1.5 text-[13px] font-medium tabular-nums">{value}</div>
          {limit && <div className="mt-0.5 text-[10px] uppercase tracking-wide text-muted">{limit} dan</div>}
        </div>
      </div>
    </div>
  );
}

// Reyting ro'yxati: nom + gorizontal chiziq
export function RankList({ items, label, value, sub, fmt = num, color = 'c1' }) {
  const p = useParts(false);
  if (!p) return <Skel h={180} />;
  const max = Math.max(1, ...items.map((i) => Number(value(i)) || 0));
  if (!items.length) return <div className="py-8 text-center text-xs text-muted">Ma'lumot yo'q</div>;
  const fill = p.t[color] || color;
  return (
    <ul className="space-y-2.5">
      {items.map((it, i) => (
        <li key={i} className="text-xs">
          <div className="mb-1 flex items-center justify-between gap-2">
            <span className="flex min-w-0 items-center gap-2"><span className="w-4 shrink-0 tabular-nums text-muted">{i + 1}</span><span className="truncate font-medium">{label(it)}</span>{sub && <span className="truncate text-muted">{sub(it)}</span>}</span>
            <span className="shrink-0 tabular-nums font-semibold">{fmt(value(it))}</span>
          </div>
          <div className="h-1.5 w-full overflow-hidden rounded-full bg-panel-2"><div className="h-full rounded-full" style={{ width: `${((Number(value(it)) || 0) / max) * 100}%`, background: fill }} /></div>
        </li>
      ))}
    </ul>
  );
}
