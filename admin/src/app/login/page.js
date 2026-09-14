'use client';
import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { ArrowRight } from 'lucide-react';
import { API_URL, api, getToken, setToken } from '@/lib/api';
import { ThemeToggle } from '@/components/theme';

export default function Login() {
  const router = useRouter();
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  useEffect(() => { if (getToken()) router.replace('/dashboard'); }, [router]);

  const submit = async (e) => {
    e.preventDefault();
    setBusy(true); setError('');
    try {
      const r = await api('/login', { method: 'POST', body: { password } });
      setToken(r.token);
      router.replace('/dashboard');
    } catch (err) {
      setError(/fetch|network/i.test(err.message) ? `Server bilan aloqa yo'q (${API_URL})` : err.message);
    } finally { setBusy(false); }
  };

  return (
    <div className="grid min-h-screen place-items-center p-4">
      <div className="absolute right-4 top-4"><ThemeToggle /></div>
      <form onSubmit={submit} className="card w-full max-w-[360px] p-7">
        <div className="mb-6 flex items-center gap-3">
          <div className="grid h-10 w-10 place-items-center rounded-xl bg-accent text-[15px] font-bold text-accent-fg">S</div>
          <div><h1 className="text-[15px] font-semibold tracking-tight">Saler AI Admin</h1><p className="text-xs text-muted">Boshqaruv paneliga kirish</p></div>
        </div>
        <label className="kicker mb-1.5 block">Admin parol</label>
        <input className="input w-full" type="password" autoFocus value={password} onChange={(e) => setPassword(e.target.value)} placeholder="••••••••" />
        {error && <p className="mt-2 text-xs text-rose-600 dark:text-rose-300">{error}</p>}
        <button className="btn btn-primary mt-4 w-full justify-center" disabled={busy || !password}>{busy ? 'Tekshirilmoqda…' : <>Kirish <ArrowRight size={14} /></>}</button>
        <p className="mt-5 text-center text-[11px] text-muted">API: {API_URL}</p>
      </form>
    </div>
  );
}
