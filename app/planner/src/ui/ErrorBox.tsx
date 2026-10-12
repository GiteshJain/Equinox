// A failed read shows its message on the screen, never a blank page (spec §3).
export function ErrorBox({ error }: { error: unknown }) {
  const message = error instanceof Error ? error.message : String(error);
  return <div className="error" role="alert" data-error>{message}</div>;
}
