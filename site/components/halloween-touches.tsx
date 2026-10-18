'use client';

import { useEffect } from 'react';

const BOO = String.raw`  ,(_)
(_____)
( ^ ^ )  Boo.
 \_v_/

Looking for the source? It's MIT: github.com/morsechimwai/agent-valley`;

// Halloween, on every page: a pumpkin for the tab icon (browsers that draw no SVG icon keep
// favicon.ico), and one for whoever opens the console. The icon is a link of our own, last in the
// head, where browsers look last: React puts back any icon link of its own that is changed.
export function HalloweenTouches() {
  useEffect(() => {
    if (!document.documentElement.classList.contains('halloween')) return;
    const icon = Object.assign(document.createElement('link'), { rel: 'icon', type: 'image/svg+xml', href: '/pumpkin.svg' });
    document.head.append(icon);
    console.log(BOO);
  }, []);
  return null;
}
