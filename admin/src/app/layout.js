import { Inter } from 'next/font/google';
import './globals.css';
import { THEME_SCRIPT, ThemeProvider } from '@/components/theme';

const inter = Inter({ subsets: ['latin', 'cyrillic'], variable: '--font-inter', display: 'swap' });

export const metadata = {
  title: 'Saler AI · Admin',
  description: 'Saler AI boshqaruv paneli',
};

export default function RootLayout({ children }) {
  return (
    <html lang="uz" className={inter.variable} suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: THEME_SCRIPT }} />
      </head>
      <body>
        <ThemeProvider>{children}</ThemeProvider>
      </body>
    </html>
  );
}
