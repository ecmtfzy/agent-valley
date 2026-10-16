'use client';

import { useEffect } from 'react';

// The loops rest while their section is off the screen.
export function IdleSections() {
  useEffect(() => {
    if (!('IntersectionObserver' in window)) return;
    const rest = new IntersectionObserver((entries) => {
      for (const entry of entries) entry.target.classList.toggle('idle', !entry.isIntersecting);
    });
    for (const section of document.querySelectorAll('.hero, .section, .foot')) rest.observe(section);
    return () => rest.disconnect();
  }, []);
  return null;
}
