'use client';
// server/ dagi /api/admin bilan ishlash. Token brauzer xotirasida.
export const API_URL = (process.env.NEXT_PUBLIC_API_URL || 'http://localhost:3000').replace(/\/$/, '');
const KEY = 'rydex_admin_token';

export const getToken = () => { try { return localStorage.getItem(KEY); } catch { return null; } };
export const setToken = (t) => { try { t ? localStorage.setItem(KEY, t) : localStorage.removeItem(KEY); } catch {} };

export class ApiError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

export async function api(path, { method = 'GET', body, query } = {}) {
  const qs = query ? '?' + new URLSearchParams(Object.entries(query).filter(([, v]) => v !== undefined && v !== null && v !== '')).toString() : '';
  const res = await fetch(`${API_URL}/api/admin${path}${qs}`, {
    method,
    headers: { 'Content-Type': 'application/json', ...(getToken() ? { Authorization: `Bearer ${getToken()}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
    cache: 'no-store',
  });
  let data = null;
  try { data = await res.json(); } catch {}
  if (res.status === 401 && !path.startsWith('/login')) {
    setToken(null);
    if (typeof window !== 'undefined' && !location.pathname.startsWith('/login')) location.href = '/login';
  }
  if (!res.ok) throw new ApiError(res.status, data?.error || `Xato ${res.status}`);
  return data;
}

export const photoUrl = (ref) => (ref ? `${API_URL}/api/photo/${encodeURIComponent(ref)}` : null);
