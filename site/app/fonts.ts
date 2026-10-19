import { UnifrakturMaguntia } from 'next/font/google';

// The Valley Funnies' blackletter name: on its own page, on the top bar and in the section that
// points there. Next keeps a copy with the site, so nothing loads from Google.
export const masthead = UnifrakturMaguntia({ subsets: ['latin'], weight: '400', variable: '--font-masthead' });
