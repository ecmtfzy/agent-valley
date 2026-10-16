// A word explained in Words on this page. A screen reader hears that the link is to its meaning.
export function Word({ id, children }: { id: string; children: React.ReactNode }) {
  return (
    <a className="w" href={`#w-${id}`}>
      {children}
      <span className="sr"> (meaning)</span>
    </a>
  );
}
