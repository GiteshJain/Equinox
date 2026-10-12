import { closeMessage, useMessages } from "./messages";

export function Messages() {
  const messages = useMessages();
  if (messages.length === 0) return null;
  return (
    <div className="messages" role="status" aria-live="polite">
      {messages.map((m) => (
        <div className="message" key={m.id} data-message>
          <span>{m.text}</span>
          <button type="button" aria-label="Close" onClick={() => closeMessage(m.id)}>×</button>
        </div>
      ))}
    </div>
  );
}
