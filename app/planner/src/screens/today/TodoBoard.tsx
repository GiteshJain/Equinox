// The to-do board, as the old planner's: open to-dos with their steps (tick when done, × to delete), a line to add one
// (with steps, one a line), and the ones done in the last 7 days folded away. Each action is one planner_save() call;
// deleting asks first, in the page.
import { useState, type FormEvent } from "react";
import { saver } from "../../data/saving";
import { Board } from "../../ui/Board";
import { Confirm } from "../../ui/Confirm";
import { dueWords } from "../../ui/dates";
import { addChanges, deleteChanges, tickChanges, todoBoard, todoClass, type TodoView } from "./todos";

function Item({ t, today, now, asking, onAsk }: { t: TodoView; today: string; now: Date; asking: boolean; onAsk: (id: number | null) => void }) {
  return (
    <li className={todoClass(t, today)} data-todo={t.key} data-done={t.done ? "yes" : "no"}>
      <label className="tchk">
        <input type="checkbox" checked={t.done} aria-label={(t.done ? "Not done: " : "Done: ") + t.title}
          onChange={(e) => void saver.save(tickChanges(t.row, e.target.checked, now))} />
      </label>
      <div className="tbody">
        <div className="ttl"><b>{t.title}</b> <span className="dim" data-when>· {dueWords(t.date, today)}</span></div>
        {t.steps.length ? <ol>{t.steps.map((s) => <li key={s.id}>{s.body}</li>)}</ol> : null}
      </div>
      {asking
        ? <Confirm question="Delete this to-do?" yes="Delete" onNo={() => onAsk(null)}
            onYes={() => { onAsk(null); void saver.save(deleteChanges(t.row, t.steps)); }} />
        : <button type="button" className="dismiss" title="Delete" aria-label={"Delete: " + t.title} onClick={() => onAsk(t.row.id)}>×</button>}
    </li>
  );
}

export function TodoBoard({ worldId, todos, today, now }: { worldId: number | undefined; todos: TodoView[] | null; today: string; now: Date }) {
  const [asking, setAsking] = useState<number | null>(null);
  const [title, setTitle] = useState("");
  const [date, setDate] = useState<string | null>(null);
  const [steps, setSteps] = useState("");
  const [adding, setAdding] = useState(false);
  const board = todos ? todoBoard(todos, today) : null;

  async function add(e: FormEvent) {
    e.preventDefault();
    if (!title.trim() || worldId === undefined || adding) return;
    setAdding(true);
    const res = await saver.save(addChanges(worldId, title, date || today, steps.split("\n"), new Date()));
    setAdding(false);
    if (res.status === "saved" || res.status === "preview") {
      setTitle("");
      setSteps("");
      setDate(null);
    }
  }

  return (
    <Board title="To-do" className="todob" id="todo"
      note={board ? `${board.open.length ? board.open.length + " open" : "nothing open"}${board.done.length ? " · " + board.done.length + " done" : ""}` : ""}>
      {!board ? <div className="loading">Loading…</div> : (
        <>
          {board.open.length ? (
            <ul className="todo" data-todo-list="open">
              {board.open.map((t) => <Item key={t.row.id} t={t} today={today} now={now} asking={asking === t.row.id} onAsk={setAsking} />)}
            </ul>
          ) : null}
          <form className="tadd" onSubmit={(e) => void add(e)} data-todo-add>
            <input id="todo-title" placeholder="Add a to-do" value={title} onChange={(e) => setTitle(e.target.value)} aria-label="New to-do" />
            <input id="todo-date" type="date" value={date ?? today} onChange={(e) => setDate(e.target.value)} aria-label="Due" />
            <button className="secondary" id="todo-add" type="submit" disabled={adding}>Add</button>
            <textarea id="todo-steps" placeholder="Steps, one a line (if any)" rows={2} value={steps} onChange={(e) => setSteps(e.target.value)} aria-label="Steps" />
          </form>
          {board.done.length || board.older ? (
            <details className="tdone">
              <summary>{board.done.length} done in the last 7 days{board.older ? ` · ${board.older} older hidden` : ""}</summary>
              <ul className="todo" data-todo-list="done">
                {board.done.map((t) => <Item key={t.row.id} t={t} today={today} now={now} asking={asking === t.row.id} onAsk={setAsking} />)}
              </ul>
            </details>
          ) : null}
        </>
      )}
    </Board>
  );
}
