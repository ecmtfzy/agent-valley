'use client';

import { useEffect } from 'react';

// Down the page the top bar's name folds away and the crew's mark stays; at the very top the name is back.
export function NavFold() {
  useEffect(() => {
    const nav = document.querySelector('.nav');
    if (!nav) return;
    const fold = () => nav.classList.toggle('mini', scrollY > 0);
    fold();
    addEventListener('scroll', fold, { passive: true });
    return () => removeEventListener('scroll', fold);
  }, []);
  return null;
}
