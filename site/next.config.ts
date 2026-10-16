import type { NextConfig } from 'next';

// Every page is plain HTML written at build time; nothing runs on a server.
const nextConfig: NextConfig = {
  output: 'export',
  images: { unoptimized: true },
  // Keeps the address as the old page gave it, https://agentvalley.app/ with its slash.
  trailingSlash: true,
  reactStrictMode: true,
};

export default nextConfig;
