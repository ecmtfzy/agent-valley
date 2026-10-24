// Nothing on the page comes from another site, and forms post only here; the policy says so to the
// browser. The page carries it in a tag (app/layout.tsx), and Vercel sends it as a header too (vercel.json).
export const CSP =
  "default-src 'self'; img-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; base-uri 'none'; form-action 'self'";
