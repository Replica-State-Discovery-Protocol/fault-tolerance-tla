#!/usr/bin/env python3
"""Chart the `(N ds/min)` throughput values from a TLC progress log.

Reads a TLC run log (e.g. n5.log), extracts every "distinct states / minute"
sample and its timestamp, and writes a self-contained HTML file with an
interactive SVG line chart. The input log is only ever read, never modified.

Usage:
    python3 plot_ds_rate.py [LOG] [-o OUT.html] [--window N]

Defaults: LOG = n5.log beside this script, OUT = <log-stem>-ds-rate.html.
No third-party dependencies.
"""

from __future__ import annotations

import argparse
import datetime as dt
import html
import json
import re
from pathlib import Path

# Progress(20) at 2026-07-25 21:58:40: 519,745,360 states generated
# (3,376,328 s/min), 107,069,468 distinct states found (752,352 ds/min), ...
PROGRESS_RE = re.compile(
    r"Progress\((?P<depth>\d+)\)\s+at\s+(?P<ts>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}):\s+"
    r"(?P<generated>[\d,]+) states generated \((?P<s_rate>[\d,]+) s/min\),\s+"
    r"(?P<distinct>[\d,]+) distinct states found \((?P<ds_rate>[\d,]+) ds/min\)"
)

# Palette — dataviz reference instance (validated light & dark, 2 slots).
LIGHT = {
    "surface": "#fcfcfb",
    "plane": "#f9f9f7",
    "primary": "#0b0b0b",
    "secondary": "#52514e",
    "muted": "#898781",
    "grid": "#e1e0d9",
    "axis": "#c3c2b7",
    "border": "rgba(11,11,11,0.10)",
    "s1": "#2a78d6",
    "s2": "#eb6834",
}
DARK = {
    "surface": "#1a1a19",
    "plane": "#0d0d0d",
    "primary": "#ffffff",
    "secondary": "#c3c2b7",
    "muted": "#898781",
    "grid": "#2c2c2a",
    "axis": "#383835",
    "border": "rgba(255,255,255,0.10)",
    "s1": "#3987e5",
    "s2": "#d95926",
}

# Chart geometry.
W, H = 960, 440
M_TOP, M_RIGHT, M_BOTTOM, M_LEFT = 24, 104, 52, 78
PLOT_W = W - M_LEFT - M_RIGHT
PLOT_H = H - M_TOP - M_BOTTOM


class Sample:
    __slots__ = ("time", "elapsed", "depth", "ds_rate", "distinct", "s_rate", "generated", "x", "y")

    def __init__(self, time, depth, ds_rate, distinct, s_rate, generated):
        self.time = time
        self.depth = depth
        self.ds_rate = ds_rate
        self.distinct = distinct
        self.s_rate = s_rate
        self.generated = generated
        self.elapsed = 0.0
        self.x = 0.0
        self.y = 0.0


def parse_log(path: Path) -> list[Sample]:
    samples: list[Sample] = []
    with path.open(encoding="utf-8", errors="replace") as fh:
        for line in fh:
            m = PROGRESS_RE.search(line)
            if not m:
                continue
            num = lambda key: int(m.group(key).replace(",", ""))  # noqa: E731
            samples.append(
                Sample(
                    time=dt.datetime.strptime(m.group("ts"), "%Y-%m-%d %H:%M:%S"),
                    depth=int(m.group("depth")),
                    ds_rate=num("ds_rate"),
                    distinct=num("distinct"),
                    s_rate=num("s_rate"),
                    generated=num("generated"),
                )
            )
    samples.sort(key=lambda s: s.time)
    if samples:
        t0 = samples[0].time
        for s in samples:
            s.elapsed = (s.time - t0).total_seconds()
    return samples


def moving_average(values: list[int], window: int) -> list[float]:
    """Trailing mean over up to `window` samples, defined from the first point."""
    out, total = [], 0.0
    for i, v in enumerate(values):
        total += v
        if i >= window:
            total -= values[i - window]
        out.append(total / min(i + 1, window))
    return out


def nice_ceiling(value: float) -> tuple[float, float]:
    """Round `value` up to a clean axis maximum; return (max, tick step)."""
    if value <= 0:
        return 1.0, 0.25
    magnitude = 10 ** (len(str(int(value))) - 1)
    for step_mult in (0.1, 0.2, 0.25, 0.5, 1.0, 2.0):
        step = magnitude * step_mult
        top = step * (int(value / step) + 1)
        if 4 <= top / step <= 8:
            return top, step
    step = magnitude
    return step * (int(value / step) + 1), step


def fmt(n: float) -> str:
    return f"{round(n):,}"


def path_d(points: list[tuple[float, float]]) -> str:
    return " ".join(
        ("M" if i == 0 else "L") + f"{x:.2f} {y:.2f}" for i, (x, y) in enumerate(points)
    )


def css_vars(pal: dict, indent: str) -> str:
    return "\n".join(f"{indent}--{k}: {v};" for k, v in pal.items())


def build_html(samples: list[Sample], window: int, source: Path) -> str:
    rates = [s.ds_rate for s in samples]
    avg = moving_average(rates, window)

    y_max, y_step = nice_ceiling(max(rates))
    x_span = max(samples[-1].elapsed, 1.0)

    def sx(elapsed: float) -> float:
        return M_LEFT + PLOT_W * (elapsed / x_span)

    def sy(value: float) -> float:
        return M_TOP + PLOT_H * (1 - value / y_max)

    for s in samples:
        s.x, s.y = sx(s.elapsed), sy(s.ds_rate)

    raw_pts = [(s.x, s.y) for s in samples]
    avg_pts = [(s.x, sy(a)) for s, a in zip(samples, avg)]

    # Y gridlines + ticks.
    y_ticks = []
    v = 0.0
    while v <= y_max + 1e-6:
        y_ticks.append((v, sy(v)))
        v += y_step

    # X ticks: whole clock times on a ~30-minute cadence.
    tick_every = 1800 if x_span > 5400 else 600 if x_span > 1200 else 120
    x_ticks, marker = [], 0.0
    while marker <= x_span + 1e-6:
        label = (samples[0].time + dt.timedelta(seconds=marker)).strftime("%H:%M")
        x_ticks.append((sx(marker), label))
        marker += tick_every

    peak = max(samples, key=lambda s: s.ds_rate)
    last = samples[-1]

    grid = "\n".join(
        f'      <line class="grid" x1="{M_LEFT}" y1="{y:.2f}" x2="{M_LEFT + PLOT_W}" y2="{y:.2f}"/>'
        for _, y in y_ticks
    )
    y_labels = "\n".join(
        f'      <text class="tick num" x="{M_LEFT - 12}" y="{y + 4:.2f}" text-anchor="end">{fmt(v)}</text>'
        for v, y in y_ticks
    )
    x_labels = "\n".join(
        f'      <text class="tick num" x="{x:.2f}" y="{M_TOP + PLOT_H + 24}" text-anchor="middle">{lbl}</text>'
        for x, lbl in x_ticks
    )

    total_distinct = last.distinct
    duration = dt.timedelta(seconds=int(last.elapsed))
    hours, remainder = divmod(int(duration.total_seconds()), 3600)
    minutes = remainder // 60
    span_text = (
        f'{samples[0].time.strftime("%Y-%m-%d %H:%M")}'
        f' – {last.time.strftime("%H:%M")} · {hours}h {minutes}m'
        f" · {len(samples)} samples"
    )

    rows = "\n".join(
        "        <tr>"
        f'<td class="num">{s.time.strftime("%H:%M:%S")}</td>'
        f'<td class="num">{s.depth}</td>'
        f'<td class="num">{fmt(s.ds_rate)}</td>'
        f'<td class="num">{fmt(a)}</td>'
        f'<td class="num">{fmt(s.distinct)}</td>'
        f'<td class="num">{fmt(s.s_rate)}</td>'
        "</tr>"
        for s, a in zip(samples, avg)
    )

    payload = json.dumps(
        {
            "window": window,
            "plot": {"left": M_LEFT, "top": M_TOP, "width": PLOT_W, "height": PLOT_H},
            "points": [
                {
                    "x": round(s.x, 2),
                    "y": round(s.y, 2),
                    "ya": round(sy(a), 2),
                    "t": s.time.strftime("%H:%M:%S"),
                    "raw": s.ds_rate,
                    "avg": round(a),
                    "depth": s.depth,
                }
                for s, a in zip(samples, avg)
            ],
        },
        separators=(",", ":"),
    ).replace("</", "<\\/")

    title = f"Distinct states found per minute — {html.escape(source.name)}"

    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<style>
  .viz-root {{
    color-scheme: light;
{css_vars(LIGHT, "    ")}
  }}
  @media (prefers-color-scheme: dark) {{
    :root:where(:not([data-theme="light"])) .viz-root {{
      color-scheme: dark;
{css_vars(DARK, "      ")}
    }}
  }}
  :root[data-theme="dark"] .viz-root {{
    color-scheme: dark;
{css_vars(DARK, "    ")}
  }}

  html, body {{ margin: 0; }}
  body {{
    background: {LIGHT["plane"]};
    font-family: system-ui, -apple-system, "Segoe UI", sans-serif;
  }}
  @media (prefers-color-scheme: dark) {{
    :root:where(:not([data-theme="light"])) body {{ background: {DARK["plane"]}; }}
  }}
  :root[data-theme="dark"] body {{ background: {DARK["plane"]}; }}
  .viz-root {{
    background: var(--plane);
    color: var(--primary);
    padding: 24px 16px 48px;
    min-height: 100vh;
    box-sizing: border-box;
  }}
  .card {{
    max-width: 1000px;
    margin: 0 auto;
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 12px;
    padding: 20px 20px 8px;
  }}
  h1 {{ font-size: 17px; font-weight: 600; color: var(--primary); margin: 0 0 4px; }}
  .sub {{ font-size: 13px; color: var(--secondary); margin: 0 0 2px; }}
  .note {{ font-size: 12px; color: var(--muted); margin: 4px 0 12px; }}
  .legend {{ display: flex; gap: 18px; align-items: center; margin: 0 0 6px; }}
  .legend span {{ display: inline-flex; align-items: center; gap: 7px; font-size: 12.5px; color: var(--secondary); }}
  .key {{ width: 16px; height: 2px; border-radius: 1px; }}
  .figure {{ position: relative; }}
  svg {{ display: block; width: 100%; height: auto; touch-action: none; }}
  .grid {{ stroke: var(--grid); stroke-width: 1; }}
  .axis {{ stroke: var(--axis); stroke-width: 1; }}
  .tick {{ fill: var(--muted); font-size: 11px; }}
  .num {{ font-variant-numeric: tabular-nums; }}
  .series {{ fill: none; stroke-width: 2; stroke-linejoin: round; stroke-linecap: round; }}
  .s-raw {{ stroke: var(--s1); }}
  .s-avg {{ stroke: var(--s2); }}
  .dot {{ stroke: var(--surface); stroke-width: 2; }}
  .callout {{ fill: var(--secondary); font-size: 11.5px; }}
  .callout-strong {{ fill: var(--primary); font-size: 12px; font-weight: 600; }}
  .crosshair {{ stroke: var(--axis); stroke-width: 1; opacity: 0; }}
  .focus-dot {{ opacity: 0; stroke: var(--surface); stroke-width: 2; }}
  .tip {{
    position: absolute; pointer-events: none; opacity: 0;
    transform: translate(-50%, -100%);
    background: var(--surface); border: 1px solid var(--border);
    border-radius: 8px; padding: 8px 10px; min-width: 150px;
    box-shadow: 0 4px 14px rgba(0,0,0,0.14);
    transition: opacity .08s linear;
  }}
  .tip-t {{ font-size: 11px; color: var(--muted); margin-bottom: 5px; font-variant-numeric: tabular-nums; }}
  .tip-row {{ display: flex; align-items: baseline; gap: 8px; margin-top: 3px; }}
  .tip-val {{ font-size: 13px; font-weight: 600; color: var(--primary); font-variant-numeric: tabular-nums; }}
  .tip-name {{ font-size: 11.5px; color: var(--secondary); }}
  details {{ max-width: 1000px; margin: 14px auto 0; font-size: 13px; color: var(--secondary); }}
  summary {{ cursor: pointer; padding: 6px 0; }}
  .scroll {{ max-height: 340px; overflow: auto; border: 1px solid var(--border); border-radius: 8px; }}
  table {{ border-collapse: collapse; width: 100%; background: var(--surface); }}
  th, td {{ text-align: right; padding: 5px 12px; font-size: 12px; white-space: nowrap; }}
  th {{ position: sticky; top: 0; background: var(--surface); color: var(--muted);
        font-weight: 500; border-bottom: 1px solid var(--border); }}
  td {{ color: var(--secondary); }}
</style>
</head>
<body>
<div class="viz-root">
  <div class="card">
    <h1>Distinct states found per minute</h1>
    <p class="sub">{html.escape(source.name)} · {span_text}</p>
    <div class="legend">
      <span><i class="key" style="background:var(--s1)"></i>Per-minute rate</span>
      <span><i class="key" style="background:var(--s2)"></i>{window}-sample moving average</span>
    </div>
    <div class="figure">
      <svg viewBox="0 0 {W} {H}" role="img" aria-label="Line chart of distinct states found per minute over the run, with a {window}-sample moving average.">
{grid}
        <line class="axis" x1="{M_LEFT}" y1="{M_TOP + PLOT_H}" x2="{M_LEFT + PLOT_W}" y2="{M_TOP + PLOT_H}"/>
{y_labels}
{x_labels}
        <text class="tick" x="{M_LEFT - 12}" y="{M_TOP - 8}" text-anchor="end">ds/min</text>
        <path class="series s-raw" d="{path_d(raw_pts)}"/>
        <path class="series s-avg" d="{path_d(avg_pts)}"/>
        <circle class="dot" cx="{peak.x:.2f}" cy="{peak.y:.2f}" r="4" fill="var(--s1)"/>
        <text class="callout" x="{peak.x + 10:.2f}" y="{peak.y - 8:.2f}">peak {fmt(peak.ds_rate)}</text>
        <circle class="dot" cx="{last.x:.2f}" cy="{last.y:.2f}" r="4" fill="var(--s1)"/>
        <text class="callout-strong num" x="{last.x + 10:.2f}" y="{last.y + 4:.2f}">{fmt(last.ds_rate)}</text>
        <circle class="dot" cx="{avg_pts[-1][0]:.2f}" cy="{avg_pts[-1][1]:.2f}" r="4" fill="var(--s2)"/>
        <line class="crosshair" id="xhair" y1="{M_TOP}" y2="{M_TOP + PLOT_H}"/>
        <circle class="focus-dot" id="fdot-raw" r="4.5" fill="var(--s1)"/>
        <circle class="focus-dot" id="fdot-avg" r="4.5" fill="var(--s2)"/>
        <rect id="hit" x="{M_LEFT}" y="{M_TOP}" width="{PLOT_W}" height="{PLOT_H}" fill="transparent" tabindex="0"/>
      </svg>
      <div class="tip" id="tip">
        <div class="tip-t" id="tip-t"></div>
        <div class="tip-row"><svg width="14" height="4"><line x1="1" y1="2" x2="13" y2="2" stroke="var(--s1)" stroke-width="2" stroke-linecap="round"/></svg><span class="tip-val" id="tip-raw"></span><span class="tip-name">ds/min</span></div>
        <div class="tip-row"><svg width="14" height="4"><line x1="1" y1="2" x2="13" y2="2" stroke="var(--s2)" stroke-width="2" stroke-linecap="round"/></svg><span class="tip-val" id="tip-avg"></span><span class="tip-name">avg</span></div>
        <div class="tip-t" id="tip-d" style="margin:5px 0 0"></div>
      </div>
    </div>
    <p class="note">Each point is one TLC progress line. Total distinct states at the end of the
       window: {fmt(total_distinct)}. The first sample covers only the seconds between
       start-up and the first progress report, so it under-reports.</p>
  </div>
  <details>
    <summary>Table view — all {len(samples)} samples</summary>
    <div class="scroll">
      <table>
        <thead><tr><th>Time</th><th>Depth</th><th>ds/min</th><th>Avg ({window})</th><th>Distinct total</th><th>s/min</th></tr></thead>
        <tbody>
{rows}
        </tbody>
      </table>
    </div>
  </details>
</div>
<script type="application/json" id="data">{payload}</script>
<script>
(function () {{
  var D = JSON.parse(document.getElementById('data').textContent);
  var svg = document.querySelector('svg');
  var hit = document.getElementById('hit');
  var xhair = document.getElementById('xhair');
  var fRaw = document.getElementById('fdot-raw');
  var fAvg = document.getElementById('fdot-avg');
  var tip = document.getElementById('tip');
  var tipT = document.getElementById('tip-t');
  var tipRaw = document.getElementById('tip-raw');
  var tipAvg = document.getElementById('tip-avg');
  var tipD = document.getElementById('tip-d');
  var idx = -1;

  function nearest(vx) {{
    var lo = 0, hi = D.points.length - 1;
    while (lo < hi) {{
      var mid = (lo + hi) >> 1;
      if (D.points[mid].x < vx) lo = mid + 1; else hi = mid;
    }}
    if (lo > 0 && Math.abs(D.points[lo - 1].x - vx) <= Math.abs(D.points[lo].x - vx)) lo--;
    return lo;
  }}

  function show(i) {{
    if (i === idx) return;
    idx = i;
    var p = D.points[i];
    xhair.setAttribute('x1', p.x); xhair.setAttribute('x2', p.x);
    xhair.style.opacity = 1;
    fRaw.setAttribute('cx', p.x); fRaw.setAttribute('cy', p.y); fRaw.style.opacity = 1;
    fAvg.setAttribute('cx', p.x); fAvg.setAttribute('cy', p.ya); fAvg.style.opacity = 1;
    tipT.textContent = p.t;
    tipRaw.textContent = p.raw.toLocaleString();
    tipAvg.textContent = p.avg.toLocaleString();
    tipD.textContent = 'depth ' + p.depth;
    var box = svg.getBoundingClientRect();
    var k = box.width / {W};
    tip.style.left = (p.x * k) + 'px';
    tip.style.top = Math.max(0, (Math.min(p.y, p.ya) * k) - 12) + 'px';
    tip.style.opacity = 1;
  }}

  function hide() {{
    idx = -1;
    xhair.style.opacity = 0;
    fRaw.style.opacity = 0;
    fAvg.style.opacity = 0;
    tip.style.opacity = 0;
  }}

  function toViewX(clientX) {{
    var box = svg.getBoundingClientRect();
    return (clientX - box.left) * ({W} / box.width);
  }}

  hit.addEventListener('pointermove', function (e) {{ show(nearest(toViewX(e.clientX))); }});
  hit.addEventListener('pointerleave', hide);
  hit.addEventListener('focus', function () {{ show(D.points.length - 1); }});
  hit.addEventListener('blur', hide);
  hit.addEventListener('keydown', function (e) {{
    var step = e.key === 'ArrowLeft' ? -1 : e.key === 'ArrowRight' ? 1 : 0;
    if (!step) return;
    e.preventDefault();
    var next = Math.min(D.points.length - 1, Math.max(0, (idx < 0 ? D.points.length - 1 : idx) + step));
    show(next);
  }});
}})();
</script>
</body>
</html>
"""


def main() -> int:
    here = Path(__file__).resolve().parent
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("log", nargs="?", default=here / "n5.log", type=Path, help="TLC log to read")
    ap.add_argument("-o", "--out", type=Path, help="output HTML path")
    ap.add_argument("-w", "--window", type=int, default=10, help="moving-average window in samples")
    args = ap.parse_args()

    log = args.log.resolve()
    samples = parse_log(log)
    if not samples:
        print(f"No 'ds/min' progress samples found in {log}")
        return 1

    out = (args.out or log.with_name(log.stem + "-ds-rate.html")).resolve()
    out.write_text(build_html(samples, max(1, args.window), log), encoding="utf-8")

    rates = [s.ds_rate for s in samples]
    print(f"{len(samples)} samples  min {min(rates):,}  max {max(rates):,}  mean {sum(rates) // len(rates):,} ds/min")
    print(f"wrote {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
