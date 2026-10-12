// Messages shown at the foot of the screen: what clashed on a save, why a save didn't get through. Each goes after a
// while, or when closed.
import { useSyncExternalStore } from "react";

export type Message = { id: number; text: string };

let messages: Message[] = [];
let next = 1;
const listeners = new Set<() => void>();
const emit = () => listeners.forEach((l) => l());

export const MESSAGE_MS = 12_000;

export function showMessage(text: string): void {
  const id = next++;
  messages = [...messages, { id, text }];
  emit();
  setTimeout(() => closeMessage(id), MESSAGE_MS);
}

export function closeMessage(id: number): void {
  if (!messages.some((m) => m.id === id)) return;
  messages = messages.filter((m) => m.id !== id);
  emit();
}

export function useMessages(): Message[] {
  return useSyncExternalStore(
    (l) => {
      listeners.add(l);
      return () => listeners.delete(l);
    },
    () => messages,
  );
}
