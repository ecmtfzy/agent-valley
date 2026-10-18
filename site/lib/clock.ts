// A running time as the app writes it (Format.elapsed in PanelView.swift): seconds alone under a
// minute, minutes and seconds under ten, then minutes, then hours and minutes.
export function elapsed(seconds: number) {
  const two = (n: number) => String(n).padStart(2, '0');
  if (seconds < 60) return `${seconds}s`;
  if (seconds < 600) return `${Math.floor(seconds / 60)}m ${two(seconds % 60)}s`;
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m`;
  return `${Math.floor(seconds / 3600)}h ${two(Math.floor((seconds % 3600) / 60))}m`;
}
