'use client';
import { createContext, useContext, useEffect, useState } from 'react';
import { Moon, Sun } from 'lucide-react';

const KEY = 'rydex_admin_theme';
const Ctx = createContext({ theme: 'light', setTheme: () => {} });

// <html data-theme> ni brauzer chizishidan oldin o'rnatadi (miltillashsiz)
export const THEME_SCRIPT = `(function(){try{var t=localStorage.getItem('${KEY}');if(!t)t=matchMedia('(prefers-color-scheme: dark)').matches?'dark':'light';document.documentElement.setAttribute('data-theme',t);}catch(e){}})();`;

export function ThemeProvider({ children }) {
  const [theme, setThemeState] = useState('light');
  useEffect(() => { setThemeState(document.documentElement.getAttribute('data-theme') || 'light'); }, []);
  const setTheme = (t) => {
    setThemeState(t);
    document.documentElement.setAttribute('data-theme', t);
    try { localStorage.setItem(KEY, t); } catch {}
  };
  return <Ctx.Provider value={{ theme, setTheme }}>{children}</Ctx.Provider>;
}

export const useTheme = () => useContext(Ctx);

export function ThemeToggle({ className = '' }) {
  const { theme, setTheme } = useTheme();
  const dark = theme === 'dark';
  return (
    <button className={`btn btn-sm ${className}`} onClick={() => setTheme(dark ? 'light' : 'dark')} title={dark ? "Oq mavzu" : "Qora mavzu"}>
      {dark ? <Sun size={14} /> : <Moon size={14} />}
      <span>{dark ? 'Oq' : 'Qora'}</span>
    </button>
  );
}

// Grafiklar uchun joriy mavzu ranglari (CSS o'zgaruvchilaridan)
export function useChartTheme() {
  const { theme } = useTheme();
  const [vars, setVars] = useState(null);
  useEffect(() => {
    const cs = getComputedStyle(document.documentElement);
    const v = (n) => cs.getPropertyValue(n).trim();
    setVars({ grid: v('--chart-grid'), axis: v('--chart-axis'), tipBg: v('--tip-bg'), tipFg: v('--tip-fg'), tipMuted: v('--tip-muted'), c1: v('--c1'), c2: v('--c2'), c3: v('--c3'), c4: v('--c4'), c5: v('--c5'), c6: v('--c6'), c7: v('--c7'), c8: v('--c8'), panel2: v('--panel-2') });
  }, [theme]);
  return vars;
}
