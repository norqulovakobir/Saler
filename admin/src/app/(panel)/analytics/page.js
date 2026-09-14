'use client';
import { useState } from 'react';
import Link from 'next/link';
import { Card, ErrorBox, PageTitle } from '@/components/ui';
import { Bars, Lines, RankList } from '@/components/charts';
import { useApi } from '@/lib/hooks';
import { WEEKDAYS, moneyShort, monthName, num } from '@/lib/format';

export default function Analytics() {
  const [months, setMonths] = useState(6);
  const { data: a, error, reload } = useApi('/analytics', { query: { months } });
  const hours = a ? a.hours.map((n, h) => ({ h: String(h).padStart(2, '0'), n })) : [];
  const weekdays = a ? a.weekdays.map((n, i) => ({ d: WEEKDAYS[i], n })) : [];
  const monthly = a ? a.monthly.map((m) => ({ ...m, label: monthName(m.month) })) : [];

  return (
    <>
      <PageTitle title="Analitika" sub="Butun platforma bo'yicha chuqur ko'rsatkichlar" action={
        <select className="input" value={months} onChange={(e) => setMonths(Number(e.target.value))}>
          {[3, 6, 12, 24].map((m) => <option key={m} value={m}>{m} oy</option>)}
        </select>
      } />
      <ErrorBox error={error} retry={reload} />

      <div className="grid gap-4 xl:grid-cols-2">
        <Card title="Oylik buyurtmalar" sub="Holatlar bo'yicha">
          <Bars data={monthly} x="label" series={[{ key: 'done', name: 'Bajarildi', color: 'c1' }, { key: 'new', name: 'Yangi', color: 'c4' }, { key: 'cancelled', name: 'Bekor', color: 'c5' }]} stacked h={240} />
        </Card>
        <Card title="Oylik tushum" sub="Bajarilgan va umumiy summa">
          <Lines data={monthly} x="label" series={[{ key: 'sumDone', name: 'Bajarilgan', color: 'c1' }, { key: 'sumTotal', name: 'Jami', color: 'c2', dashed: true }]} money h={240} />
        </Card>
        <Card title="Kun soatlari bo'yicha" sub="Buyurtma qaysi soatda ko'p tushadi">
          <Bars data={hours} x="h" series={[{ key: 'n', name: 'Buyurtma', color: 'c1' }]} h={200} />
        </Card>
        <Card title="Hafta kunlari bo'yicha">
          <Bars data={weekdays} x="d" series={[{ key: 'n', name: 'Buyurtma', color: 'c1' }]} h={200} />
        </Card>
      </div>

      <div className="mt-4 grid gap-4 md:grid-cols-2 xl:grid-cols-3">
        <Card title="Top do'konlar" sub="Tushum bo'yicha">
          <RankList items={a?.topShops || []} label={(s) => <Link href={`/shops/${s.id}`} className="hover:underline">{s.name}</Link>} sub={(s) => `${s.done}/${s.orders} buyurtma`} value={(s) => s.revenue} fmt={moneyShort} />
        </Card>
        <Card title="Eng ko'p sotilgan" sub="Mahsulotlar, dona">
          <RankList items={a?.topProducts || []} label={(p) => p.name} sub={(p) => p.shop} value={(p) => p.qty} fmt={(v) => `${num(v)} dona`} />
        </Card>
        <Card title="Eng ko'p ko'rilgan" sub="Mahsulotlar">
          <RankList items={a?.topViewed || []} label={(p) => p.name} sub={(p) => p.shop} value={(p) => p.views} fmt={(v) => `${num(v)} ko'rish`} color="c6" />
        </Card>
        <Card title="Top xaridorlar" sub="Xarid summasi">
          <RankList items={a?.topCustomers || []} label={(c) => c.name} sub={(c) => c.phone} value={(c) => c.sum} fmt={moneyShort} color="c3" />
        </Card>
        <Card title="Narx taqsimoti" sub="Mahsulotlar soni">
          <Bars data={a?.priceBuckets || []} x="label" series={[{ key: 'n', name: 'Mahsulot', color: 'c1' }]} h={220} layout="vertical" />
        </Card>
        <Card title="Do'kon hajmi" sub="Mahsulot soni bo'yicha do'konlar">
          <Bars data={a?.shopSizes || []} x="label" series={[{ key: 'n', name: "Do'kon", color: 'c6' }]} h={220} layout="vertical" />
        </Card>
      </div>
    </>
  );
}
