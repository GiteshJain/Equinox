// Review's charts, drawn as the old Review draws them (web/planner/index.html: barChart, spark, forecastBoard's chart,
// rpScatter, rpCost, rpTailChart and groupOverviewHtml's chart), from the layouts in model.ts. A tip follows the pointer
// over anything with a data-tip, as the old .maptip does.
import { useRef, type MouseEvent as RMouseEvent, type ReactNode } from "react";
import {
  barLayout, costParts, forecastLayout, groupLayout, scatterLayout, sparkBars, tailBars, type AircraftRow, type AverageFlight, type Forecast, type GroupRow,
  type ProfitDay, type RouteRow,
} from "./model";

/** A chart with the old planner's pointer tip. */
function ChartWrap({ children, className = "chartwrap" }: { children: ReactNode; className?: string }) {
  const wrap = useRef<HTMLDivElement>(null), tip = useRef<HTMLDivElement>(null);
  const move = (e: RMouseEvent<HTMLDivElement>) => {
    const t = tip.current, w = wrap.current;
    if (!t || !w) return;
    const el = (e.target as Element).closest?.("[data-tip]");
    if (!el) { t.style.display = "none"; return; }
    const r = w.getBoundingClientRect();
    t.textContent = el.getAttribute("data-tip");
    t.style.display = "block";
    const x = e.clientX - r.left, y = e.clientY - r.top;
    t.style.left = Math.max(0, Math.min(x + 14, r.width - t.offsetWidth - 6)) + "px";
    t.style.top = (y + 16 + t.offsetHeight > r.height ? y - t.offsetHeight - 10 : y + 16) + "px";
  };
  return (
    <div className={className} ref={wrap} onMouseMove={move} onMouseLeave={() => { if (tip.current) tip.current.style.display = "none"; }}>
      {children}
      <div className="maptip" ref={tip} />
    </div>
  );
}

/** The profit chart: a bar per interval, the zero line, the average. */
export function BarChart({ pts, avg, figure }: { pts: readonly { x: string; y: number; tip: string }[]; avg: number | null; figure?: string }) {
  if (!pts.length) return <div className="empty">Needs two nights of cash to show a day's profit.</div>;
  const g = barLayout(pts, avg);
  return (
    <ChartWrap>
      <svg className="lchart" viewBox={`0 0 ${g.W} ${g.H}`} role="img" data-figure={figure} data-bars={g.bars.length}>
        {g.grid.map((l, i) => (
          <g key={i}>
            <line x1={g.L} x2={g.W - g.R} y1={l.y.toFixed(1)} y2={l.y.toFixed(1)} className={l.zero ? "zero" : "grid"} />
            <text x={g.L - 6} y={(l.y + 4).toFixed(1)} textAnchor="end">{l.label}</text>
          </g>
        ))}
        {g.bars.map((b, i) => (
          <g key={"b" + i}>
            <rect x={b.x.toFixed(1)} y={b.y.toFixed(1)} width={b.w.toFixed(1)} height={b.h.toFixed(1)} rx="3" className={b.neg ? "bneg" : "bpos"} />
            <rect x={b.hitX.toFixed(1)} y={g.T} width={b.hitW.toFixed(1)} height={g.H - g.T - g.B} className="hitc" data-tip={b.tip} />
            <text x={(b.x + b.w / 2).toFixed(1)} y={g.H - 9} textAnchor="middle">{b.label}</text>
          </g>
        ))}
        {g.avg ? (
          <>
            <line x1={g.L} x2={g.W - g.R} y1={g.avg.y.toFixed(1)} y2={g.avg.y.toFixed(1)} className="avgl" />
            <text x={g.W - g.R} y={(g.avg.y - 5).toFixed(1)} textAnchor="end" className="avgt">{g.avg.text}</text>
          </>
        ) : null}
      </svg>
    </ChartWrap>
  );
}

/** A card's sparkline. */
export function Spark({ days }: { days: readonly ProfitDay[] }) {
  if (!days.length) return null;
  return (
    <svg className="spark" viewBox="0 0 120 30" aria-hidden="true">
      <line x1="0" x2="120" y1="15" y2="15" className="zero" />
      {sparkBars(days).map((b, i) => <rect key={i} x={b.x.toFixed(1)} y={b.y.toFixed(1)} width={b.w.toFixed(1)} height={b.h.toFixed(1)} rx="1.5" className={b.neg ? "bneg" : "bpos"} />)}
    </svg>
  );
}

/** Cash, next 14 days. */
export function ForecastChart({ fc, cushion, airline }: { fc: Forecast; cushion: number; airline: string }) {
  const g = forecastLayout(fc, cushion);
  if (!g) return null;
  return (
    <svg className="fcchart" viewBox={`0 0 ${g.W} ${g.H}`} role="img" aria-label={`Cash forecast for ${airline}`}>
      {g.days.map((d, i) => (
        <g key={i}>
          <line x1={d.x} x2={d.x} y1="12" y2={g.H - 22} stroke="#E4E8F2" />
          {d.label ? <text x={d.x} y={g.H - 6} fontSize="10.5" textAnchor="middle" fill="#8B96A8">{d.label}</text> : null}
        </g>
      ))}
      <line x1={g.pad} x2={g.W - g.pad} y1={g.cushionY} y2={g.cushionY} stroke="#F6B44B" strokeDasharray="4 4" />
      <text x={g.W - g.pad} y={g.cushionY - 4} fontSize="10.5" textAnchor="end" fill="#C98A1E">{cushion.toFixed(1)}M cushion</text>
      {g.zeroY != null ? <line x1={g.pad} x2={g.W - g.pad} y1={g.zeroY} y2={g.zeroY} stroke="#B4234B" /> : null}
      <path d={g.path} fill="none" stroke="#3B3FD8" strokeWidth="2.2" strokeLinejoin="round" />
      {g.pays.map((p, i) => (
        <line key={"p" + i} x1={p.x} x2={p.x} y1={g.H - 22} y2={p.y2} stroke={p.repeat ? "#C3C9D9" : "#8B96A8"} strokeWidth="2"><title>{p.title}</title></line>
      ))}
      <circle cx={g.low.x} cy={g.low.y} r="4.5" fill={g.low.bad ? "#B4234B" : "#3B3FD8"} />
      <text x={g.low.textX} y={g.low.y + 15} fontSize="11" fill="#0A1230">{g.low.text}</text>
      <text x={g.start.x} y={g.start.y} fontSize="11" fill="#0A1230">{g.start.text}</text>
    </svg>
  );
}

/** Load against profit: economy load against profit a flight, bubble size flights a week, colour the mark. */
export function Scatter({ routes }: { routes: readonly RouteRow[] }) {
  const g = scatterLayout(routes);
  if (!g) return <div className="dim">No loads matched yet.</div>;
  return (
    <svg className="rpsvg" viewBox={`0 0 ${g.W} ${g.H}`} role="img" aria-label="Economy load against profit a flight">
      {g.yTicks.map((t, i) => (
        <g key={i}>
          <line x1={g.pl} x2={g.W - g.pr} y1={t.y} y2={t.y} stroke="#EEF1F7" />
          <text x={g.pl - 6} y={t.y + 4} fontSize="10" textAnchor="end" fill="#8B96A8">{t.label}</text>
        </g>
      ))}
      {g.xTicks.map((t, i) => <text key={"x" + i} x={t.x} y={g.H - 12} fontSize="10" textAnchor="middle" fill="#8B96A8">{t.label}</text>)}
      {g.zeroY != null ? <line x1={g.pl} x2={g.W - g.pr} y1={g.zeroY} y2={g.zeroY} stroke="#B4234B" strokeDasharray="3 3" /> : null}
      <text x={g.W - g.pr} y={g.H - 1} fontSize="10" textAnchor="end" fill="#8B96A8">economy load →</text>
      {g.dots.map((d, i) => (
        <circle key={"d" + i} cx={d.x.toFixed(1)} cy={d.y.toFixed(1)} r={d.r.toFixed(1)} fill={d.color} fillOpacity=".55" stroke={d.color}><title>{d.title}</title></circle>
      ))}
      {g.labels.map((l, i) => <text key={"l" + i} x={l.x.toFixed(1)} y={l.y.toFixed(1)} fontSize="10" textAnchor="end" fill="#0A1230">{l.text}</text>)}
    </svg>
  );
}

/** An average flight: income and where it goes, in thousands. */
export function CostChart({ avg }: { avg: AverageFlight | null }) {
  const c = costParts(avg);
  if (!c) return <div className="dim">No flights yet.</div>;
  const R = c.income.reduce((a, x) => a + x.k, 0);
  const W = 460, x0 = 70, bw = W - x0 - 10;
  const bar = (label: string, parts: typeof c.income, y: number) => {
    let x = x0;
    return (
      <g>
        <text x="0" y={y + 15} fontSize="11.5" fill="#0A1230">{label}</text>
        {parts.map((p) => {
          const w = Math.max(0, p.k / R * bw), at = x;
          x += w;
          return <rect key={p.name} x={at.toFixed(1)} y={y} width={w.toFixed(1)} height="22" fill={p.color}><title>{p.name}: {p.k.toFixed(1)}k</title></rect>;
        })}
      </g>
    );
  };
  return (
    <svg className="rpsvg" viewBox={`0 0 ${W} 140`} role="img" aria-label="Income and costs of an average flight" data-figure="review: an average flight">
      {bar("Income", c.income, 8)}
      {bar("Costs", c.costs, 38)}
      <text x={x0} y="80" fontSize="12" fill="#0A1230" fontWeight="700">Profit {c.profitK.toFixed(1)}k a flight · {c.marginPct}% margin</text>
      {[...c.income, ...c.costs].map((p, i) => (
        <g key={p.name} transform={`translate(${(i % 4) * 115},${96 + Math.floor(i / 4) * 18})`}>
          <rect width="10" height="10" fill={p.color} />
          <text x="14" y="9" fontSize="10.5" fill="#3B4566">{p.name} {p.k.toFixed(1)}k</text>
        </g>
      ))}
    </svg>
  );
}

/** Each aircraft's profit a day after its lease. */
export function TailChart({ rows }: { rows: readonly AircraftRow[] }) {
  const g = tailBars(rows);
  return (
    <svg className="rpsvg" viewBox={`0 0 ${g.W} ${g.H}`} role="img" aria-label="Profit a day after lease, by aircraft">
      {g.bars.map((b, i) => (
        <g key={i}>
          <text x="0" y={b.y + 15} fontSize="11" fill="#0A1230">{b.reg}</text>
          <rect x={b.x.toFixed(1)} y={b.y + 4} width={b.w.toFixed(1)} height="14" rx="3" fill={b.pos ? "#1E9E6A" : "#B4234B"}><title>{b.title}</title></rect>
          <text x={b.labelX.toFixed(1)} y={b.y + 15} fontSize="10.5" textAnchor={b.pos ? "start" : "end"} fill="#3B4566">{b.label}</text>
        </g>
      ))}
      {g.mid != null ? <line x1={g.mid} x2={g.mid} y1="0" y2={g.H - 2} stroke="#C3C9D9" /> : null}
    </svg>
  );
}

/** The group today: one row per airline, flight profit against leases and the week-end closing, net at the end. */
export function GroupChart({ rows }: { rows: readonly GroupRow[] }) {
  const g = groupLayout(rows);
  return (
    <svg className="rpsvg" viewBox={`0 0 ${g.W} ${g.H}`} role="img" aria-label="Flight profit against leases, by airline" data-figure="review: the group today">
      {g.rows.map((x) => (
        <g key={x.r.airline_id} data-group-row={x.r.code ?? x.r.name}>
          <text x="0" y={x.y + 16} fontSize="11.5" fill="#0A1230">{x.r.name}</text>
          <rect x={g.c} y={x.y + 3} width={x.profitW.toFixed(1)} height="16" rx="3" fill="#1E9E6A"><title>{x.profitTitle}</title></rect>
          <rect x={(g.c - x.leaseW).toFixed(1)} y={x.y + 3} width={x.leaseW.toFixed(1)} height="16" rx="3" fill="#E0557A"><title>{x.leaseTitle}</title></rect>
          <text x={g.W - 4} y={x.y + 16} fontSize="11.5" textAnchor="end" fill={x.neg ? "#B4234B" : "#0A1230"} fontWeight="700">{x.net}</text>
        </g>
      ))}
      <line x1={g.c} x2={g.c} y1="0" y2={g.axisY} stroke="#C3C9D9" />
      <text x={g.c - 6} y={g.labelY} fontSize="10" textAnchor="end" fill="#8B96A8">← leases and closing</text>
      <text x={g.c + 6} y={g.labelY} fontSize="10" fill="#8B96A8">flight profit →</text>
      <text x={g.W - 4} y={g.labelY} fontSize="10" textAnchor="end" fill="#8B96A8">net a day</text>
    </svg>
  );
}
