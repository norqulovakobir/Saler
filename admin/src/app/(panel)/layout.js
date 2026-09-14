'use client';
import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import Sidebar from '@/components/sidebar';
import { api, getToken } from '@/lib/api';

export default function PanelLayout({ children }) {
  const router = useRouter();
  const [ok, setOk] = useState(false);

  useEffect(() => {
    if (!getToken()) { router.replace('/login'); return; }
    api('/me').then(() => setOk(true)).catch(() => router.replace('/login'));
  }, [router]);

  if (!ok) return <div className="grid min-h-screen place-items-center text-sm text-muted">Yuklanmoqda…</div>;
  return (
    <div className="flex min-h-screen flex-col lg:flex-row">
      <Sidebar />
      <main className="min-w-0 flex-1"><div className="mx-auto w-full max-w-[1440px] p-4 lg:p-7">{children}</div></main>
    </div>
  );
}
