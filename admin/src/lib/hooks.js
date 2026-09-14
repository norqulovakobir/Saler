'use client';
import { useCallback, useEffect, useRef, useState } from 'react';
import { api } from './api';

// So'rov holati: data / loading / error / reload. `deps` o'zgarsa qayta yuklaydi.
export function useApi(path, { query, deps = [], enabled = true, refreshMs } = {}) {
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const seq = useRef(0);
  const q = JSON.stringify(query || {});

  const load = useCallback(async (silent = false) => {
    if (!enabled) return;
    const id = ++seq.current;
    if (!silent) setLoading(true);
    setError(null);
    try {
      const r = await api(path, { query: JSON.parse(q) });
      if (id === seq.current) setData(r);
    } catch (e) {
      if (id === seq.current) setError(e);
    } finally {
      if (id === seq.current) setLoading(false);
    }
  }, [path, q, enabled]);

  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => { load(); }, [load, ...deps]);
  useEffect(() => {
    if (!refreshMs) return;
    const t = setInterval(() => load(true), refreshMs);
    return () => clearInterval(t);
  }, [refreshMs, load]);

  return { data, loading, error, reload: () => load(true) };
}

// Qidiruv maydoni uchun kechiktirilgan qiymat
export function useDebounced(value, ms = 350) {
  const [v, setV] = useState(value);
  useEffect(() => { const t = setTimeout(() => setV(value), ms); return () => clearTimeout(t); }, [value, ms]);
  return v;
}
