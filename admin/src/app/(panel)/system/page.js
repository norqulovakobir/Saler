'use client';
import { Activity, Cpu, Database, HardDrive, Mail, RefreshCw } from 'lucide-react';
import { Badge, Card, ErrorBox, PageTitle, Stat } from '@/components/ui';
import { useApi } from '@/lib/hooks';
import { API_URL } from '@/lib/api';
import { bytes, date, duration, num } from '@/lib/format';

export default function SystemPage() {
  const { data: s, error, reload } = useApi('/system', { refreshMs: 15000 });
  const L = !s;
  const mail = s?.mail;
  const mailState = !mail ? '—' : mail.enabled ? 'Ulangan' : mail.devCodes ? 'Test rejimi' : "O'chiq";

  return (
    <>
      <PageTitle title="Tizim" sub={s ? `Server vaqti ${date(s.time)} · ${API_URL}` : 'Yuklanmoqda…'} action={<button className="btn" onClick={reload}><RefreshCw size={14} />Yangilash</button>} />
      <ErrorBox error={error} retry={reload} />
      <div className="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-5">
        <Stat loading={L} label="Ishlash vaqti" value={s && duration(s.uptime)} sub={s && `Node ${s.node} · ${s.env.nodeEnv}`} icon={Activity} />
        <Stat loading={L} label="Xotira (RSS)" value={s && bytes(s.memory.rss)} sub={s && `Heap ${bytes(s.memory.heapUsed)} / ${bytes(s.memory.heapTotal)}`} icon={Cpu} />
        <Stat loading={L} label="Baza hajmi" value={s && (s.db ? bytes(s.db.dataSize) : '—')} sub={s?.db && `${num(s.db.objects)} yozuv · ${s.db.collections} jadval`} icon={Database} />
        <Stat loading={L} label="Yuklangan rasmlar" value={s && num(s.uploads.files)} sub={s && `${bytes(s.uploads.bytes)} · ${s.uploads.storage === 'supabase' ? 'Supabase Storage' : 'Postgres'}`} icon={HardDrive} />
        <Stat loading={L} label="Email kodlari (EmailJS)" value={mailState} sub={mail && `Kutilmoqda ${mail.codesPending} · Soatda ${mail.codesHour}`} icon={Mail} />
      </div>

      <div className="mt-4 grid gap-4 xl:grid-cols-3">
        <Card title="Sozlamalar">
          {s && <dl className="space-y-2 text-xs">
            {[['AI model', s.env.groqModel], ['Vision model', s.env.visionModel], ['Redis kesh', s.env.redis ? 'Ulangan' : 'Xotira keshi'], ['Port', s.env.port], ['Rejim', s.env.nodeEnv], ['Platforma', s.platform], ['CPU yuklama (1/5/15)', s.cpuLoad.map((x) => x.toFixed(2)).join(' / ')]].map(([k, v]) => (
              <div key={k} className="flex justify-between gap-3 border-b border-line pb-2 last:border-0"><dt className="text-muted">{k}</dt><dd className="truncate text-right font-medium text-text-2">{v}</dd></div>
            ))}
          </dl>}
        </Card>
        <Card title="Email tasdiqlash (EmailJS)" sub="Ro'yxatdan o'tish va buyurtmada 6 xonali kod shu xizmat orqali yuboriladi">
          {mail && <dl className="space-y-2 text-xs">
            {[
              ['Holat', <Badge key="st" tone={mail.enabled ? 'green' : mail.devCodes ? 'amber' : 'rose'}>{mailState}</Badge>],
              ['Service ID', mail.serviceId || '—'],
              ['Template ID', mail.templateId || '—'],
              ['Public key', mail.publicKey ? 'Bor' : "Yo'q — EMAILJS_PUBLIC_KEY kiriting"],
              ['Private key', mail.privateKey ? 'Bor' : "Yo'q (Account > Security)"],
              ['Kutilayotgan kodlar', num(mail.codesPending)],
              ['Oxirgi soatda yuborilgan', num(mail.codesHour)],
            ].map(([k, v]) => (
              <div key={k} className="flex items-center justify-between gap-3 border-b border-line pb-2 last:border-0"><dt className="text-muted">{k}</dt><dd className="truncate text-right font-medium text-text-2">{v}</dd></div>
            ))}
          </dl>}
          {mail && !mail.enabled && (
            <p className="mt-3 rounded-lg bg-panel-2 p-3 text-xs text-text-2">
              {mail.devCodes
                ? "Test rejimi: kod emailga yuborilmaydi, server logida va ilovada ko'rinadi. Ishga tushirish uchun serverda EMAILJS_PUBLIC_KEY (Account > General) va EMAILJS_PRIVATE_KEY (Account > Security, \"Allow EmailJS API for non-browser applications\" yoqilgan) kiriting."
                : "Production rejimida email kaliti yo'q: hech kim ro'yxatdan o'ta olmaydi va buyurtma bera olmaydi. EMAILJS_PUBLIC_KEY va EMAILJS_PRIVATE_KEY ni kiriting."}
            </p>
          )}
        </Card>
        <Card title="Server logi" sub="Oxirgi 40 qator" pad={false}>
          <pre className="mono max-h-[420px] overflow-auto bg-panel-2 px-4 py-3 text-[11.5px] leading-relaxed text-text-2">{s ? (s.logTail.length ? s.logTail.join('\n') : "Log hali bo'sh") : '…'}</pre>
        </Card>
      </div>
    </>
  );
}
