'use client';
import { Activity, Bot, Cpu, Database, HardDrive, RefreshCw } from 'lucide-react';
import { Card, ErrorBox, PageTitle, Stat } from '@/components/ui';
import { useApi } from '@/lib/hooks';
import { API_URL } from '@/lib/api';
import { bytes, date, duration, num } from '@/lib/format';

export default function SystemPage() {
  const { data: s, error, reload } = useApi('/system', { refreshMs: 15000 });
  const L = !s;

  return (
    <>
      <PageTitle title="Tizim" sub={s ? `Server vaqti ${date(s.time)} · ${API_URL}` : 'Yuklanmoqda…'} action={<button className="btn" onClick={reload}><RefreshCw size={14} />Yangilash</button>} />
      <ErrorBox error={error} retry={reload} />
      <div className="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-5">
        <Stat loading={L} label="Ishlash vaqti" value={s && duration(s.uptime)} sub={s && `Node ${s.node}`} icon={Activity} />
        <Stat loading={L} label="Xotira (RSS)" value={s && bytes(s.memory.rss)} sub={s && `Heap ${bytes(s.memory.heapUsed)} / ${bytes(s.memory.heapTotal)}`} icon={Cpu} />
        <Stat loading={L} label="Baza hajmi" value={s && (s.db ? bytes(s.db.dataSize) : '—')} sub={s?.db && `${num(s.db.objects)} hujjat · ${s.db.collections} kolleksiya`} icon={Database} />
        <Stat loading={L} label="Yuklangan rasmlar" value={s && num(s.uploads.files)} sub={s && bytes(s.uploads.bytes)} icon={HardDrive} />
        <Stat loading={L} label="Telegram bot" value={s && (s.bot ? `@${s.bot.username}` : '—')} sub={s?.bot && s.bot.name} icon={Bot} />
      </div>

      <div className="mt-4 grid gap-4 xl:grid-cols-3">
        <Card title="Sozlamalar">
          {s && <dl className="space-y-2 text-xs">
            {[['AI model', s.env.groqModel], ['Vision model', s.env.visionModel], ['Redis kesh', s.env.redis ? 'Ulangan' : 'Xotira keshi'], ['Port', s.env.port], ['Mini App URL', s.env.webappUrl || '—'], ['Platforma', s.platform], ['CPU yuklama (1/5/15)', s.cpuLoad.map((x) => x.toFixed(2)).join(' / ')]].map(([k, v]) => (
              <div key={k} className="flex justify-between gap-3 border-b border-line pb-2 last:border-0"><dt className="text-muted">{k}</dt><dd className="truncate text-right font-medium text-text-2">{v}</dd></div>
            ))}
          </dl>}
        </Card>
        <Card title="Server logi" sub="Oxirgi 40 qator" className="xl:col-span-2" pad={false}>
          <pre className="mono max-h-[420px] overflow-auto bg-panel-2 px-4 py-3 text-[11.5px] leading-relaxed text-text-2">{s ? (s.logTail.length ? s.logTail.join('\n') : 'Log fayli topilmadi (bot/data/bot.log)') : '…'}</pre>
        </Card>
      </div>
    </>
  );
}
