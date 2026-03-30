#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://127.0.0.1:8080/pi}"
REQUESTS="${REQUESTS:-500}"
ITERATIONS_CSV="${ITERATIONS:-10000,100000,1000000}"
CONCURRENCIES_CSV="${CONCURRENCIES:-1,10,50,100}"
TITLE="${TITLE:-Rust HTTP Benchmark Report}"
OUT_DIR=""

usage() {
  cat <<'EOF'
Usage:
  scripts/bench_report.sh [options]

Options:
  -u, --base-url URL            Base URL prefix. The script appends /<iterations>.
                                Default: http://127.0.0.1:8080/pi
  -n, --requests N             Total requests per benchmark run. Default: 500
  -i, --iterations CSV         Iteration values to test. Default: 10000,100000,1000000
  -c, --concurrency CSV        Concurrency values to test. Default: 1,10,50,100
  -o, --out-dir DIR            Output directory. Default: benchmarks/<utc-timestamp>
  -t, --title TEXT             Report title. Default: Rust HTTP Benchmark Report
  -h, --help                   Show this help

Examples:
  scripts/bench_report.sh \
    --base-url http://127.0.0.1:3030/pi \
    --iterations 100000,500000,1000000 \
    --concurrency 1,10,50,100 \
    --requests 500

  BASE_URL=http://127.0.0.1:8080/pi \
  ITERATIONS=10000,100000,1000000 \
  CONCURRENCIES=1,5,10,20,50 \
  scripts/bench_report.sh
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

json_string() {
  local escaped="${1//\\/\\\\}"
  escaped="${escaped//\"/\\\"}"
  escaped="${escaped//$'\n'/\\n}"
  printf '"%s"' "$escaped"
}

parse_csv_into_array() {
  local raw="${1// /}"
  local -n out_ref="$2"
  IFS=',' read -r -a out_ref <<<"$raw"
  if [[ ${#out_ref[@]} -eq 0 || -z "${out_ref[0]}" ]]; then
    die "received an empty list where at least one value is required"
  fi
}

ensure_numbers() {
  local label="$1"
  shift
  local value
  for value in "$@"; do
    [[ "$value" =~ ^[0-9]+$ ]] || die "$label values must be positive integers: $value"
  done
}

metric_or_zero() {
  local metric="$1"
  local source_file="$2"
  local value=""

  case "$metric" in
    complete_requests)
      value="$(awk -F: '/^Complete requests:/ {gsub(/[[:space:]]/, "", $2); print $2; exit}' "$source_file")"
      ;;
    failed_requests)
      value="$(awk -F: '/^Failed requests:/ {gsub(/[[:space:]]/, "", $2); print $2; exit}' "$source_file")"
      ;;
    requests_per_second)
      value="$(awk -F: '/^Requests per second:/ {gsub(/^[[:space:]]+/, "", $2); split($2, parts, /[[:space:]]+/); print parts[1]; exit}' "$source_file")"
      ;;
    time_per_request_ms)
      value="$(awk '/^Time per request:/ && $0 !~ /across all concurrent requests/ {print $4; exit}' "$source_file")"
      ;;
    total_mean_ms)
      value="$(awk '$1 == "Total:" {print $3; exit}' "$source_file")"
      ;;
    p50_ms)
      value="$(awk '$1 == "50%" {print $2; exit}' "$source_file")"
      ;;
    p95_ms)
      value="$(awk '$1 == "95%" {print $2; exit}' "$source_file")"
      ;;
    p99_ms)
      value="$(awk '$1 == "99%" {print $2; exit}' "$source_file")"
      ;;
    max_ms)
      value="$(awk '$1 == "100%" {print $2; exit}' "$source_file")"
      ;;
    transfer_rate_kb)
      value="$(awk '/^Transfer rate:/ {print $3; exit}' "$source_file")"
      ;;
    *)
      die "unsupported metric parser: $metric"
      ;;
  esac

  printf '%s\n' "${value:-0}"
}

join_numbers_for_js() {
  local -n values_ref="$1"
  local joined=""
  local value
  for value in "${values_ref[@]}"; do
    joined+="${value},"
  done
  printf '[%s]' "${joined%,}"
}

write_report() {
  local report_path="$1"
  local rows_js="$2"
  local generated_at="$3"
  local runs_count="$4"
  local iterations_js="$5"
  local concurrencies_js="$6"

  cat >"$report_path" <<EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${TITLE}</title>
  <style>
    :root {
      --bg: #f5f1e8;
      --paper: rgba(255, 252, 245, 0.82);
      --ink: #172033;
      --muted: #566071;
      --grid: rgba(23, 32, 51, 0.12);
      --border: rgba(23, 32, 51, 0.1);
      --accent: #c85c38;
      --accent-soft: rgba(200, 92, 56, 0.14);
      --good: #156f5b;
      --shadow: 0 24px 70px rgba(23, 32, 51, 0.12);
      --radius: 24px;
      --mono: "SFMono-Regular", Menlo, Consolas, monospace;
      --sans: "Avenir Next", "Segoe UI", sans-serif;
    }

    * {
      box-sizing: border-box;
    }

    body {
      margin: 0;
      min-height: 100vh;
      font-family: var(--sans);
      color: var(--ink);
      background:
        radial-gradient(circle at top left, rgba(200, 92, 56, 0.18), transparent 28rem),
        radial-gradient(circle at top right, rgba(21, 111, 91, 0.16), transparent 25rem),
        linear-gradient(180deg, #fbf7ef 0%, var(--bg) 100%);
    }

    main {
      width: min(1220px, calc(100% - 2rem));
      margin: 0 auto;
      padding: 2rem 0 4rem;
    }

    .hero,
    .panel {
      backdrop-filter: blur(12px);
      background: var(--paper);
      border: 1px solid var(--border);
      border-radius: var(--radius);
      box-shadow: var(--shadow);
    }

    .hero {
      overflow: hidden;
      padding: 2rem;
      position: relative;
      margin-bottom: 1rem;
    }

    .hero::after {
      content: "";
      position: absolute;
      inset: auto -10% -25% auto;
      width: 18rem;
      height: 18rem;
      border-radius: 999px;
      background: radial-gradient(circle, rgba(200, 92, 56, 0.2), transparent 72%);
      pointer-events: none;
    }

    .eyebrow {
      margin: 0 0 0.6rem;
      text-transform: uppercase;
      letter-spacing: 0.14em;
      color: var(--accent);
      font-size: 0.76rem;
      font-weight: 700;
    }

    h1 {
      margin: 0;
      font-size: clamp(2rem, 4vw, 3.8rem);
      line-height: 0.95;
      letter-spacing: -0.04em;
    }

    .lede {
      max-width: 62rem;
      margin: 1rem 0 1.4rem;
      color: var(--muted);
      font-size: 1.02rem;
      line-height: 1.6;
    }

    .meta-grid,
    .cards,
    .chart-grid,
    .heatmap-grid {
      display: grid;
      gap: 1rem;
    }

    .meta-grid {
      grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
    }

    .meta-item {
      padding: 1rem 1.1rem;
      border: 1px solid var(--border);
      border-radius: 18px;
      background: rgba(255, 255, 255, 0.45);
    }

    .meta-label,
    .card-label {
      color: var(--muted);
      font-size: 0.82rem;
      text-transform: uppercase;
      letter-spacing: 0.09em;
      margin-bottom: 0.45rem;
    }

    .meta-value,
    .card-value {
      font-size: 1rem;
      font-weight: 700;
      word-break: break-word;
    }

    .stack {
      display: grid;
      gap: 1rem;
    }

    .panel {
      padding: 1.35rem;
    }

    .panel h2 {
      margin: 0 0 0.3rem;
      font-size: 1.18rem;
      letter-spacing: -0.02em;
    }

    .panel p {
      margin: 0 0 1rem;
      color: var(--muted);
      line-height: 1.5;
    }

    .cards {
      grid-template-columns: repeat(auto-fit, minmax(190px, 1fr));
    }

    .card {
      padding: 1rem;
      border-radius: 18px;
      border: 1px solid var(--border);
      background: linear-gradient(180deg, rgba(255,255,255,0.78), rgba(255,255,255,0.52));
    }

    .card-value {
      font-size: 1.55rem;
      line-height: 1.1;
      letter-spacing: -0.03em;
    }

    .card-note {
      margin-top: 0.5rem;
      color: var(--muted);
      font-size: 0.92rem;
      line-height: 1.45;
    }

    .heatmap-grid,
    .chart-grid {
      grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
    }

    table {
      width: 100%;
      border-collapse: collapse;
      overflow: hidden;
      border-radius: 18px;
      border: 1px solid var(--border);
      background: rgba(255,255,255,0.55);
    }

    th,
    td {
      padding: 0.8rem 0.9rem;
      text-align: left;
      border-bottom: 1px solid var(--grid);
      border-right: 1px solid var(--grid);
      vertical-align: top;
    }

    th:last-child,
    td:last-child {
      border-right: 0;
    }

    tr:last-child td {
      border-bottom: 0;
    }

    th {
      font-size: 0.86rem;
      font-weight: 700;
      color: var(--muted);
      text-transform: uppercase;
      letter-spacing: 0.07em;
      background: rgba(23, 32, 51, 0.04);
    }

    .heat-cell {
      min-width: 110px;
      border-radius: 14px;
      color: #111;
      font-weight: 700;
    }

    .heat-cell small {
      display: block;
      margin-top: 0.3rem;
      font-weight: 500;
      opacity: 0.8;
    }

    .legend {
      display: flex;
      flex-wrap: wrap;
      gap: 0.7rem;
      margin: 0 0 1rem;
    }

    .legend span {
      display: inline-flex;
      align-items: center;
      gap: 0.4rem;
      color: var(--muted);
      font-size: 0.92rem;
    }

    .swatch {
      width: 0.85rem;
      height: 0.85rem;
      border-radius: 999px;
      display: inline-block;
    }

    .chart-wrap {
      padding: 0.4rem 0 0;
    }

    svg {
      width: 100%;
      height: auto;
      display: block;
      overflow: visible;
    }

    .axis-label {
      fill: var(--muted);
      font-size: 12px;
      font-family: var(--sans);
    }

    .series-label {
      fill: var(--ink);
      font-size: 12px;
      font-weight: 700;
      font-family: var(--sans);
    }

    .grid-line {
      stroke: var(--grid);
      stroke-width: 1;
    }

    .domain {
      stroke: rgba(23, 32, 51, 0.4);
      stroke-width: 1.4;
    }

    .raw-table code,
    .hero code {
      font-family: var(--mono);
      font-size: 0.95em;
      background: rgba(23, 32, 51, 0.06);
      padding: 0.15rem 0.35rem;
      border-radius: 6px;
    }

    .raw-table td {
      font-family: var(--mono);
      font-size: 0.92rem;
    }

    @media (max-width: 800px) {
      main {
        width: min(100% - 1rem, 1220px);
        padding-top: 1rem;
      }

      .hero,
      .panel {
        padding: 1rem;
      }

      th,
      td {
        padding: 0.7rem;
      }
    }
  </style>
</head>
<body>
  <main>
    <section class="hero">
      <p class="eyebrow">ApacheBench Matrix Report</p>
      <h1>${TITLE}</h1>
      <p class="lede">
        ${runs_count} benchmark runs generated against <code>${BASE_URL}/&lt;i&gt;</code>.
        Use the heatmaps to spot where throughput collapses and the charts to compare how latency shifts as concurrency increases.
      </p>
      <div class="meta-grid">
        <div class="meta-item">
          <div class="meta-label">Generated</div>
          <div class="meta-value">${generated_at}</div>
        </div>
        <div class="meta-item">
          <div class="meta-label">Requests per Run</div>
          <div class="meta-value">${REQUESTS}</div>
        </div>
        <div class="meta-item">
          <div class="meta-label">Iterations Tested</div>
          <div class="meta-value">${ITERATIONS_CSV}</div>
        </div>
        <div class="meta-item">
          <div class="meta-label">Concurrency Tested</div>
          <div class="meta-value">${CONCURRENCIES_CSV}</div>
        </div>
      </div>
    </section>

    <div class="stack">
      <section class="panel">
        <h2>Highlights</h2>
        <p>Fastest throughput and worst latency become obvious here before you dive into the full matrix.</p>
        <div class="cards" id="summary-cards"></div>
      </section>

      <section class="panel">
        <h2>Heatmaps</h2>
        <p>Rows are <code>i</code> values. Columns are concurrency levels. Darker green is better for throughput, darker orange is worse for latency.</p>
        <div class="heatmap-grid">
          <div>
            <h2>Requests per Second</h2>
            <div id="rps-heatmap"></div>
          </div>
          <div>
            <h2>P95 Latency</h2>
            <div id="p95-heatmap"></div>
          </div>
        </div>
      </section>

      <section class="panel">
        <h2>Trend Lines</h2>
        <p>Each line is one iteration count. This is the quickest view for how the server reacts when concurrency climbs.</p>
        <div class="chart-grid">
          <div>
            <div class="legend" id="legend"></div>
            <div class="chart-wrap" id="rps-chart"></div>
          </div>
          <div>
            <div class="chart-wrap" id="latency-chart"></div>
          </div>
        </div>
      </section>

      <section class="panel raw-table">
        <h2>Raw Metrics</h2>
        <p>The same data used for the visual report. You also have the original ApacheBench output under the sibling <code>raw/</code> directory.</p>
        <div id="raw-table"></div>
      </section>
    </div>
  </main>

  <script>
    const rows = [
${rows_js}
    ];

    const meta = {
      title: $(json_string "$TITLE"),
      baseUrl: $(json_string "$BASE_URL"),
      requests: ${REQUESTS},
      generatedAt: $(json_string "$generated_at"),
      iterations: ${iterations_js},
      concurrencies: ${concurrencies_js},
    };

    const palette = ["#0f6c5c", "#c85c38", "#245fa6", "#91631a", "#7b3ea8", "#aa2a45"];

    function byKey(iterations, concurrency) {
      return rows.find((row) => row.iterations === iterations && row.concurrency === concurrency);
    }

    function number(value, digits = 2) {
      return new Intl.NumberFormat("en-US", {
        maximumFractionDigits: digits,
        minimumFractionDigits: digits === 0 ? 0 : 0,
      }).format(value);
    }

    function heatColor(value, min, max, reverse) {
      if (max === min) {
        return "hsla(158, 60%, 42%, 0.28)";
      }
      let ratio = (value - min) / (max - min);
      if (reverse) ratio = 1 - ratio;
      const hue = reverse ? 26 : 156;
      const sat = reverse ? 74 : 52;
      const light = 88 - ratio * 42;
      const alpha = 0.26 + ratio * 0.5;
      return "hsla(" + hue + ", " + sat + "%, " + light + "%, " + alpha + ")";
    }

    function renderSummary() {
      const summary = document.getElementById("summary-cards");
      const fastest = rows.reduce((best, row) => (row.rps > best.rps ? row : best), rows[0]);
      const slowest = rows.reduce((worst, row) => (row.rps < worst.rps ? row : worst), rows[0]);
      const lowestP95 = rows.reduce((best, row) => (row.p95Ms < best.p95Ms ? row : best), rows[0]);
      const highestP95 = rows.reduce((worst, row) => (row.p95Ms > worst.p95Ms ? row : worst), rows[0]);
      const failed = rows.reduce((count, row) => count + row.failedRequests, 0);

      const cards = [
        {
          label: "Best Throughput",
          value: number(fastest.rps) + " req/s",
          note: "i=" + fastest.iterations + " at c=" + fastest.concurrency,
        },
        {
          label: "Worst Throughput",
          value: number(slowest.rps) + " req/s",
          note: "i=" + slowest.iterations + " at c=" + slowest.concurrency,
        },
        {
          label: "Best P95",
          value: number(lowestP95.p95Ms, 0) + " ms",
          note: "i=" + lowestP95.iterations + " at c=" + lowestP95.concurrency,
        },
        {
          label: "Worst P95",
          value: number(highestP95.p95Ms, 0) + " ms",
          note: "i=" + highestP95.iterations + " at c=" + highestP95.concurrency,
        },
        {
          label: "Failures",
          value: number(failed, 0),
          note: failed === 0 ? "No failed requests across the whole matrix" : "Review the raw outputs for error details",
        },
      ];

      summary.innerHTML = cards.map((card) => (
        '<article class="card">' +
          '<div class="card-label">' + card.label + '</div>' +
          '<div class="card-value">' + card.value + '</div>' +
          '<div class="card-note">' + card.note + '</div>' +
        '</article>'
      )).join("");
    }

    function renderHeatmap(targetId, metric, options) {
      const target = document.getElementById(targetId);
      const values = rows.map((row) => row[metric]);
      const min = Math.min(...values);
      const max = Math.max(...values);

      let html = '<table><thead><tr><th>Iterations</th>';
      for (const concurrency of meta.concurrencies) {
        html += '<th>c=' + concurrency + '</th>';
      }
      html += '</tr></thead><tbody>';

      for (const iterations of meta.iterations) {
        html += '<tr><th>i=' + iterations + '</th>';
        for (const concurrency of meta.concurrencies) {
          const row = byKey(iterations, concurrency);
          const value = row[metric];
          const bg = heatColor(value, min, max, options.reverse);
          html += '<td class="heat-cell" style="background:' + bg + ';">' +
            options.format(value) +
            '<small>' + row.failedRequests + ' failed</small>' +
            '</td>';
        }
        html += '</tr>';
      }

      html += '</tbody></table>';
      target.innerHTML = html;
    }

    function renderLegend() {
      const legend = document.getElementById("legend");
      legend.innerHTML = meta.iterations.map((iterations, index) => (
        '<span><i class="swatch" style="background:' + palette[index % palette.length] + ';"></i>i=' + iterations + '</span>'
      )).join("");
    }

    function renderLineChart(targetId, metric, yLabel, formatter) {
      const target = document.getElementById(targetId);
      const width = 720;
      const height = 320;
      const margin = { top: 18, right: 24, bottom: 48, left: 64 };
      const innerWidth = width - margin.left - margin.right;
      const innerHeight = height - margin.top - margin.bottom;
      const values = rows.map((row) => row[metric]);
      const min = Math.min(...values);
      const max = Math.max(...values);
      const domainMin = Math.min(0, min);
      const domainMax = max === min ? max + 1 : max * 1.08;
      const xPositions = new Map();

      meta.concurrencies.forEach((concurrency, index) => {
        const x = margin.left + (meta.concurrencies.length === 1 ? innerWidth / 2 : (index / (meta.concurrencies.length - 1)) * innerWidth);
        xPositions.set(concurrency, x);
      });

      const yFor = (value) => {
        const ratio = (value - domainMin) / (domainMax - domainMin);
        return margin.top + innerHeight - ratio * innerHeight;
      };

      const yTicks = 4;
      let svg = '<svg viewBox="0 0 ' + width + ' ' + height + '" role="img" aria-label="' + yLabel + ' chart">';

      for (let i = 0; i <= yTicks; i += 1) {
        const value = domainMin + ((domainMax - domainMin) / yTicks) * i;
        const y = yFor(value);
        svg += '<line class="grid-line" x1="' + margin.left + '" y1="' + y + '" x2="' + (width - margin.right) + '" y2="' + y + '"></line>';
        svg += '<text class="axis-label" x="' + (margin.left - 12) + '" y="' + (y + 4) + '" text-anchor="end">' + formatter(value) + '</text>';
      }

      svg += '<line class="domain" x1="' + margin.left + '" y1="' + (height - margin.bottom) + '" x2="' + (width - margin.right) + '" y2="' + (height - margin.bottom) + '"></line>';
      svg += '<line class="domain" x1="' + margin.left + '" y1="' + margin.top + '" x2="' + margin.left + '" y2="' + (height - margin.bottom) + '"></line>';

      meta.concurrencies.forEach((concurrency) => {
        const x = xPositions.get(concurrency);
        svg += '<text class="axis-label" x="' + x + '" y="' + (height - margin.bottom + 24) + '" text-anchor="middle">' + concurrency + '</text>';
      });

      svg += '<text class="axis-label" x="' + (width / 2) + '" y="' + (height - 8) + '" text-anchor="middle">Concurrency</text>';
      svg += '<text class="axis-label" x="18" y="' + (height / 2) + '" text-anchor="middle" transform="rotate(-90 18 ' + (height / 2) + ')">' + yLabel + '</text>';

      meta.iterations.forEach((iterations, index) => {
        const color = palette[index % palette.length];
        const series = rows
          .filter((row) => row.iterations === iterations)
          .sort((a, b) => a.concurrency - b.concurrency);

        const points = series.map((row) => xPositions.get(row.concurrency) + ',' + yFor(row[metric])).join(' ');
        svg += '<polyline fill="none" stroke="' + color + '" stroke-width="3" stroke-linejoin="round" stroke-linecap="round" points="' + points + '"></polyline>';

        series.forEach((row, pointIndex) => {
          const x = xPositions.get(row.concurrency);
          const y = yFor(row[metric]);
          svg += '<circle cx="' + x + '" cy="' + y + '" r="5" fill="' + color + '" stroke="white" stroke-width="2">' +
            '<title>i=' + row.iterations + ', c=' + row.concurrency + ': ' + formatter(row[metric]) + '</title>' +
            '</circle>';

          if (pointIndex === series.length - 1) {
            svg += '<text class="series-label" x="' + (x + 10) + '" y="' + (y + 4) + '">' + row.iterations + '</text>';
          }
        });
      });

      svg += '</svg>';
      target.innerHTML = svg;
    }

    function renderRawTable() {
      const target = document.getElementById("raw-table");
      const headers = [
        "iterations",
        "concurrency",
        "rps",
        "meanMs",
        "p95Ms",
        "p99Ms",
        "maxMs",
        "failedRequests",
      ];

      let html = "<table><thead><tr>";
      headers.forEach((header) => {
        html += "<th>" + header + "</th>";
      });
      html += "</tr></thead><tbody>";

      rows
        .slice()
        .sort((a, b) => a.iterations - b.iterations || a.concurrency - b.concurrency)
        .forEach((row) => {
          html += "<tr>";
          html += "<td>" + row.iterations + "</td>";
          html += "<td>" + row.concurrency + "</td>";
          html += "<td>" + number(row.rps) + "</td>";
          html += "<td>" + number(row.meanMs, 2) + "</td>";
          html += "<td>" + number(row.p95Ms, 0) + "</td>";
          html += "<td>" + number(row.p99Ms, 0) + "</td>";
          html += "<td>" + number(row.maxMs, 0) + "</td>";
          html += "<td>" + row.failedRequests + "</td>";
          html += "</tr>";
        });

      html += "</tbody></table>";
      target.innerHTML = html;
    }

    renderSummary();
    renderLegend();
    renderHeatmap("rps-heatmap", "rps", {
      reverse: false,
      format: (value) => number(value) + " req/s",
    });
    renderHeatmap("p95-heatmap", "p95Ms", {
      reverse: true,
      format: (value) => number(value, 0) + " ms",
    });
    renderLineChart("rps-chart", "rps", "Requests / sec", (value) => number(value, 0));
    renderLineChart("latency-chart", "p95Ms", "P95 latency (ms)", (value) => number(value, 0));
    renderRawTable();
  </script>
</body>
</html>
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -u|--base-url)
      [[ $# -ge 2 ]] || die "missing value for $1"
      BASE_URL="$2"
      shift 2
      ;;
    -n|--requests)
      [[ $# -ge 2 ]] || die "missing value for $1"
      REQUESTS="$2"
      shift 2
      ;;
    -i|--iterations)
      [[ $# -ge 2 ]] || die "missing value for $1"
      ITERATIONS_CSV="$2"
      shift 2
      ;;
    -c|--concurrency)
      [[ $# -ge 2 ]] || die "missing value for $1"
      CONCURRENCIES_CSV="$2"
      shift 2
      ;;
    -o|--out-dir)
      [[ $# -ge 2 ]] || die "missing value for $1"
      OUT_DIR="$2"
      shift 2
      ;;
    -t|--title)
      [[ $# -ge 2 ]] || die "missing value for $1"
      TITLE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

require_command ab
require_command awk

[[ "$REQUESTS" =~ ^[0-9]+$ ]] || die "--requests must be a positive integer"

parse_csv_into_array "$ITERATIONS_CSV" ITERATIONS_VALUES
parse_csv_into_array "$CONCURRENCIES_CSV" CONCURRENCIES_VALUES
ensure_numbers "iterations" "${ITERATIONS_VALUES[@]}"
ensure_numbers "concurrency" "${CONCURRENCIES_VALUES[@]}"

if [[ -z "$OUT_DIR" ]]; then
  OUT_DIR="benchmarks/$(date -u +%Y%m%d-%H%M%S)"
fi

mkdir -p "$OUT_DIR/raw"

STARTED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
SUMMARY_CSV="$OUT_DIR/summary.csv"
REPORT_HTML="$OUT_DIR/report.html"

printf 'iterations,concurrency,requests,complete_requests,failed_requests,requests_per_second,time_per_request_ms,total_mean_ms,p50_ms,p95_ms,p99_ms,max_ms,transfer_rate_kb_s,url\n' >"$SUMMARY_CSV"

ROWS_JS=""
RUNS_COUNT=0

for iterations in "${ITERATIONS_VALUES[@]}"; do
  for concurrency in "${CONCURRENCIES_VALUES[@]}"; do
    RUNS_COUNT=$((RUNS_COUNT + 1))
    TARGET_URL="${BASE_URL%/}/$iterations"
    OUTPUT_FILE="$OUT_DIR/raw/i-${iterations}__c-${concurrency}.txt"

    echo "[$RUNS_COUNT] ab -n $REQUESTS -c $concurrency $TARGET_URL"
    ab -n "$REQUESTS" -c "$concurrency" -q "$TARGET_URL" >"$OUTPUT_FILE"

    complete_requests="$(metric_or_zero complete_requests "$OUTPUT_FILE")"
    failed_requests="$(metric_or_zero failed_requests "$OUTPUT_FILE")"
    requests_per_second="$(metric_or_zero requests_per_second "$OUTPUT_FILE")"
    time_per_request_ms="$(metric_or_zero time_per_request_ms "$OUTPUT_FILE")"
    total_mean_ms="$(metric_or_zero total_mean_ms "$OUTPUT_FILE")"
    p50_ms="$(metric_or_zero p50_ms "$OUTPUT_FILE")"
    p95_ms="$(metric_or_zero p95_ms "$OUTPUT_FILE")"
    p99_ms="$(metric_or_zero p99_ms "$OUTPUT_FILE")"
    max_ms="$(metric_or_zero max_ms "$OUTPUT_FILE")"
    transfer_rate_kb="$(metric_or_zero transfer_rate_kb "$OUTPUT_FILE")"

    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
      "$iterations" \
      "$concurrency" \
      "$REQUESTS" \
      "$complete_requests" \
      "$failed_requests" \
      "$requests_per_second" \
      "$time_per_request_ms" \
      "$total_mean_ms" \
      "$p50_ms" \
      "$p95_ms" \
      "$p99_ms" \
      "$max_ms" \
      "$transfer_rate_kb" \
      "$TARGET_URL" >>"$SUMMARY_CSV"

    ROWS_JS+="      {
        iterations: $iterations,
        concurrency: $concurrency,
        requests: $REQUESTS,
        url: $(json_string "$TARGET_URL"),
        completeRequests: $complete_requests,
        failedRequests: $failed_requests,
        rps: $requests_per_second,
        meanMs: $time_per_request_ms,
        totalMeanMs: $total_mean_ms,
        p50Ms: $p50_ms,
        p95Ms: $p95_ms,
        p99Ms: $p99_ms,
        maxMs: $max_ms,
        transferRateKb: $transfer_rate_kb,
      },
"
  done
done

write_report \
  "$REPORT_HTML" \
  "$ROWS_JS" \
  "$STARTED_AT" \
  "$RUNS_COUNT" \
  "$(join_numbers_for_js ITERATIONS_VALUES)" \
  "$(join_numbers_for_js CONCURRENCIES_VALUES)"

cat <<EOF
Benchmark matrix finished.
Summary CSV: $SUMMARY_CSV
HTML report: $REPORT_HTML
Raw outputs: $OUT_DIR/raw
EOF
