'use client';
import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { BarChart3, Bike, LayoutDashboard, LogOut, Menu, Package, Server, ShoppingCart, Store, Users, X } from 'lucide-react';
import { useState } from 'react';
import { setToken } from '@/lib/api';
import { ThemeToggle } from '@/components/theme';

const NAV = [
  { href: '/dashboard', label: 'Bosh sahifa', icon: LayoutDashboard },
  { href: '/analytics', label: 'Analitika', icon: BarChart3 },
  { href: '/shops', label: "Do'konlar", icon: Store },
  { href: '/products', label: 'Mahsulotlar', icon: Package },
  { href: '/orders', label: 'Buyurtmalar', icon: ShoppingCart },
  { href: '/users', label: 'Foydalanuvchilar', icon: Users },
  { href: '/couriers', label: 'Kuryerlar', icon: Bike },
  { href: '/system', label: 'Tizim', icon: Server },
];

export default function Sidebar() {
  const path = usePathname();
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const logout = () => { setToken(null); router.replace('/login'); };

  const nav = (
    <nav className="flex flex-1 flex-col gap-0.5">
      {NAV.map(({ href, label, icon: Icon }) => (
        <Link key={href} href={href} onClick={() => setOpen(false)} className={`nav-link ${path.startsWith(href) ? 'active' : ''}`}>
          <Icon size={16} strokeWidth={2} /><span>{label}</span>
        </Link>
      ))}
    </nav>
  );
  const footer = (
    <div className="mt-3 flex items-center justify-between gap-2 border-t border-line pt-3">
      <ThemeToggle />
      <button className="btn btn-sm btn-ghost text-muted" onClick={logout} title="Chiqish"><LogOut size={14} />Chiqish</button>
    </div>
  );

  return (
    <>
      <aside className="sticky top-0 hidden h-screen w-[232px] shrink-0 flex-col border-r border-line bg-panel px-3 py-4 lg:flex">
        <Brand />
        {nav}
        {footer}
      </aside>

      {/* mobil sarlavha */}
      <div className="sticky top-0 z-30 flex items-center justify-between border-b border-line bg-panel px-3 py-2 lg:hidden">
        <Brand compact />
        <div className="flex items-center gap-2"><ThemeToggle /><button className="btn btn-sm btn-icon" onClick={() => setOpen(true)}><Menu size={16} /></button></div>
      </div>
      {open && (
        <div className="fixed inset-0 z-40 bg-black/50 lg:hidden" onClick={() => setOpen(false)}>
          <aside className="flex h-full w-[260px] flex-col bg-panel px-3 py-4" onClick={(e) => e.stopPropagation()}>
            <div className="mb-2 flex items-center justify-between"><Brand /><button className="btn btn-sm btn-icon btn-ghost" onClick={() => setOpen(false)}><X size={16} /></button></div>
            {nav}
            {footer}
          </aside>
        </div>
      )}
    </>
  );
}

function Brand({ compact }) {
  return (
    <div className={`flex items-center gap-2.5 ${compact ? '' : 'mb-5 px-1'}`}>
      <div className="grid h-8 w-8 place-items-center rounded-[9px] bg-accent text-[13px] font-bold text-accent-fg">S</div>
      <div className="leading-tight"><div className="text-[14px] font-semibold tracking-tight">Rydex</div><div className="kicker text-[10px]">Admin panel</div></div>
    </div>
  );
}
