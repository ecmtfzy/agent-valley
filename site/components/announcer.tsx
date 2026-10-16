// One place on the page that says aloud what a button just did.
export function Announcer() {
  return <p className="sr" aria-live="polite" id="said" />;
}

export function announce(text: string) {
  const said = document.getElementById('said');
  if (said) said.textContent = text;
}
