#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://127.0.0.1:8080/pi}"
REQUESTS="${REQUESTS:-500}"
ITERATIONS_CSV="${ITERATIONS:-10000,100000,1000000}"
CONCURRENCIES_CSV="${CONCURRENCIES:-1,10,50}"
CHECK_ITERATIONS="${CHECK_ITERATIONS:-1000}"
TITLE="${TITLE:-TP2 - Analisis de ApacheBench}"
CHART_FILE_NAME="ft-vs-concurrency.svg"
OUT_DIR=""

RESULT_ROWS=()
DERIVED_ROWS=()
ANALYSIS_LINES=()
CONCLUSION_LINES=()
NON_BASE_CONCURRENCIES=()

# Keep the raw matrix in memory so derived tables and conclusions read from one source.
declare -A RPS_BY_KEY
declare -A MEAN_BY_KEY
declare -A P95_BY_KEY
declare -A FAILED_BY_KEY

usage() {
  cat <<'EOF'
Usage:
  scripts/bench_report.sh [options]

Options:
  -u, --base-url URL            Base URL prefix. The script appends /<iterations>.
                                Default: http://127.0.0.1:8080/pi
  -n, --requests N              Total requests per benchmark run. Default: 500
  -i, --iterations CSV          Iteration values to test. Default: 10000,100000,1000000
  -c, --concurrency CSV         Concurrency values to test. Default: 1,10,50
  --check-iterations N          Iterations used by the health check. Default: 1000
  -o, --out-dir DIR             Output directory. Default: benchmarks/<utc-timestamp>
  -t, --title TEXT              Report title. Default: TP2 - Analisis de ApacheBench
  -h, --help                    Show this help

Examples:
  scripts/bench_report.sh

  scripts/bench_report.sh \
    --iterations 10000,100000,1000000 \
    --concurrency 1,10,50 \
    --requests 500

  scripts/bench_report.sh \
    --base-url http://127.0.0.1:3030/pi \
    --concurrency 1,5,20 \
    --iterations 500000
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

parse_csv_into_array() {
  local raw="${1// /}"
  local -n out_ref="$2"
  IFS=',' read -r -a out_ref <<<"$raw"
  if [[ ${#out_ref[@]} -eq 0 || -z "${out_ref[0]}" ]]; then
    die "received an empty CSV list"
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

contains_value() {
  local needle="$1"
  shift
  local value
  for value in "$@"; do
    if [[ "$value" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}

format_number() {
  local value="$1"
  local digits="${2:-2}"
  if [[ "$value" == "inf" ]]; then
    printf 'inf'
    return 0
  fi
  awk -v v="$value" -v p="$digits" 'BEGIN { printf "%.*f", p, v }'
}

ratio_value() {
  local numerator="$1"
  local denominator="$2"
  awk -v n="$numerator" -v d="$denominator" '
    BEGIN {
      if (d == 0) {
        if (n == 0) {
          print "1.00"
        } else {
          print "inf"
        }
      } else {
        printf "%.2f", n / d
      }
    }
  '
}

scale_linear() {
  local value="$1"
  local domain_start="$2"
  local domain_end="$3"
  local range_start="$4"
  local range_end="$5"
  awk -v v="$value" -v d0="$domain_start" -v d1="$domain_end" -v r0="$range_start" -v r1="$range_end" '
    BEGIN {
      if (d1 == d0) {
        printf "%.2f", (r0 + r1) / 2
      } else {
        printf "%.2f", r0 + ((v - d0) / (d1 - d0)) * (r1 - r0)
      }
    }
  '
}

float_gt() {
  local left="$1"
  local right="$2"
  if [[ "$left" == "inf" ]]; then
    return 0
  fi
  awk -v a="$left" -v b="$right" 'BEGIN { exit !(a > b) }'
}

float_lt() {
  local left="$1"
  local right="$2"
  if [[ "$left" == "inf" ]]; then
    return 1
  fi
  awk -v a="$left" -v b="$right" 'BEGIN { exit !(a < b) }'
}

run_ab() {
  local url="$1"
  local concurrency="$2"
  local output

  # Execute one ab run and return its plain-text output for later parsing.
  if ! output="$(ab -n "$REQUESTS" -c "$concurrency" -q "$url" 2>&1)"; then
    echo "$output" >&2
    die "ab failed for $url with concurrency $concurrency"
  fi

  printf '%s\n' "$output"
}

parse_ab_output() {
  local output="$1"
  local rps mean_ms p95_ms failed_requests

  rps="$(awk -F: '/^Requests per second:/ {gsub(/^[[:space:]]+/, "", $2); split($2, parts, /[[:space:]]+/); print parts[1]; exit}' <<<"$output")"
  mean_ms="$(awk '/^Time per request:/ && $0 !~ /across all concurrent requests/ {print $4; exit}' <<<"$output")"
  p95_ms="$(awk '$1 == "95%" {print $2; exit}' <<<"$output")"
  failed_requests="$(awk -F: '/^Failed requests:/ {gsub(/[[:space:]]/, "", $2); print $2; exit}' <<<"$output")"

  printf '%s|%s|%s|%s\n' "${rps:-0}" "${mean_ms:-0}" "${p95_ms:-0}" "${failed_requests:-0}"
}

record_result() {
  local iterations="$1"
  local concurrency="$2"
  local rps="$3"
  local mean_ms="$4"
  local p95_ms="$5"
  local failed_requests="$6"
  local key="${iterations}|${concurrency}"

  RESULT_ROWS+=("${iterations}|${concurrency}|${rps}|${mean_ms}|${p95_ms}|${failed_requests}")
  RPS_BY_KEY["$key"]="$rps"
  MEAN_BY_KEY["$key"]="$mean_ms"
  P95_BY_KEY["$key"]="$p95_ms"
  FAILED_BY_KEY["$key"]="$failed_requests"
}

analyze_iteration() {
  local iterations="$1"
  local base_key="${iterations}|1"
  local first_concurrency="${NON_BASE_CONCURRENCIES[0]}"
  local last_concurrency="${NON_BASE_CONCURRENCIES[${#NON_BASE_CONCURRENCIES[@]}-1]}"
  local base_rps="${RPS_BY_KEY[$base_key]}"
  local base_p95="${P95_BY_KEY[$base_key]}"
  local first_key="${iterations}|${first_concurrency}"
  local last_key="${iterations}|${last_concurrency}"
  local speedup_first penalty_first speedup_last penalty_last line

  speedup_first="$(ratio_value "${RPS_BY_KEY[$first_key]}" "$base_rps")"
  penalty_first="$(ratio_value "${P95_BY_KEY[$first_key]}" "$base_p95")"
  speedup_last="$(ratio_value "${RPS_BY_KEY[$last_key]}" "$base_rps")"
  penalty_last="$(ratio_value "${P95_BY_KEY[$last_key]}" "$base_p95")"

  line="i=${iterations}: "

  if float_gt "$speedup_first" "1.50" && ! float_gt "$penalty_first" "2.50"; then
    line+="mejora clara hasta c=${first_concurrency} (speedup ${speedup_first}x)"
  elif float_gt "$speedup_first" "1.15"; then
    line+="mejora moderada hasta c=${first_concurrency} (speedup ${speedup_first}x)"
  else
    line+="no muestra una mejora significativa al pasar de c=1 a c=${first_concurrency}"
  fi

  if [[ "$first_concurrency" != "$last_concurrency" ]]; then
    local gain_after_first penalty_after_first
    gain_after_first="$(ratio_value "${RPS_BY_KEY[$last_key]}" "${RPS_BY_KEY[$first_key]}")"
    penalty_after_first="$(ratio_value "${P95_BY_KEY[$last_key]}" "${P95_BY_KEY[$first_key]}")"

    if float_lt "$gain_after_first" "1.15" && float_gt "$penalty_after_first" "1.50"; then
      line+=", pero a c=${last_concurrency} el throughput casi no mejora frente a c=${first_concurrency} y la latencia aumenta, indicando saturacion"
    elif float_gt "$penalty_last" "3.00"; then
      line+=", y a c=${last_concurrency} la latencia empeora fuerte (p95 x${penalty_last})"
    elif float_gt "$speedup_last" "$speedup_first" && ! float_gt "$penalty_last" "2.50"; then
      line+=", y todavia mantiene una ganancia util hasta c=${last_concurrency}"
    else
      line+=", con un tradeoff visible entre throughput y latencia en c=${last_concurrency}"
    fi
  else
    if float_gt "$penalty_first" "3.00"; then
      line+=", pero con un deterioro fuerte de latencia (p95 x${penalty_first})"
    elif float_gt "$penalty_first" "2.00"; then
      line+=", con costo de latencia apreciable (p95 x${penalty_first})"
    fi
  fi

  printf '%s\n' "$line"
}

compute_metrics() {
  local iterations
  local concurrency
  local baseline_key base_rps base_p95 row speedup penalty speedup_values penalty_values
  local total_failed=0
  local scales_well=0
  local saturates=0
  local latency_tradeoff=0

  NON_BASE_CONCURRENCIES=()
  for concurrency in "${CONCURRENCIES_VALUES[@]}"; do
    if [[ "$concurrency" != "1" ]]; then
      NON_BASE_CONCURRENCIES+=("$concurrency")
    fi
  done

  [[ ${#NON_BASE_CONCURRENCIES[@]} -gt 0 ]] || die "concurrency list must include at least one value greater than 1"

  DERIVED_ROWS=()
  ANALYSIS_LINES=()
  CONCLUSION_LINES=()

  # Build speedups, latency penalties and short narrative conclusions from the base matrix.
  for iterations in "${ITERATIONS_VALUES[@]}"; do
    baseline_key="${iterations}|1"
    base_rps="${RPS_BY_KEY[$baseline_key]}"
    base_p95="${P95_BY_KEY[$baseline_key]}"
    row="$iterations"
    speedup_values=()
    penalty_values=()

    for concurrency in "${NON_BASE_CONCURRENCIES[@]}"; do
      speedup="$(ratio_value "${RPS_BY_KEY[${iterations}|${concurrency}]}" "$base_rps")"
      penalty="$(ratio_value "${P95_BY_KEY[${iterations}|${concurrency}]}" "$base_p95")"
      speedup_values+=("$speedup")
      penalty_values+=("$penalty")
    done

    for speedup in "${speedup_values[@]}"; do
      row+="|${speedup}"
    done

    for penalty in "${penalty_values[@]}"; do
      row+="|${penalty}"
    done

    DERIVED_ROWS+=("$row")
    ANALYSIS_LINES+=("$(analyze_iteration "$iterations")")

    if float_gt "$(ratio_value "${RPS_BY_KEY[${iterations}|${NON_BASE_CONCURRENCIES[0]}]}" "$base_rps")" "1.50"; then
      scales_well=$((scales_well + 1))
    fi

    if float_gt "$(ratio_value "${P95_BY_KEY[${iterations}|${NON_BASE_CONCURRENCIES[${#NON_BASE_CONCURRENCIES[@]}-1]}]}" "$base_p95")" "2.00"; then
      latency_tradeoff=$((latency_tradeoff + 1))
    fi

    if [[ ${#NON_BASE_CONCURRENCIES[@]} -ge 2 ]]; then
      local first_concurrency="${NON_BASE_CONCURRENCIES[0]}"
      local last_concurrency="${NON_BASE_CONCURRENCIES[${#NON_BASE_CONCURRENCIES[@]}-1]}"
      local high_gain high_penalty
      high_gain="$(ratio_value "${RPS_BY_KEY[${iterations}|${last_concurrency}]}" "${RPS_BY_KEY[${iterations}|${first_concurrency}]}")"
      high_penalty="$(ratio_value "${P95_BY_KEY[${iterations}|${last_concurrency}]}" "${P95_BY_KEY[${iterations}|${first_concurrency}]}")"
      if float_lt "$high_gain" "1.15" && float_gt "$high_penalty" "1.50"; then
        saturates=$((saturates + 1))
      fi
    fi
  done

  for iterations in "${ITERATIONS_VALUES[@]}"; do
    for concurrency in "${CONCURRENCIES_VALUES[@]}"; do
      total_failed=$((total_failed + FAILED_BY_KEY[${iterations}|${concurrency}]))
    done
  done

  if [[ "$total_failed" -eq 0 ]]; then
    CONCLUSION_LINES+=("No se observaron failed requests: el servidor fue robusto en el rango probado.")
  else
    CONCLUSION_LINES+=("Se observaron ${total_failed} failed requests en total, por lo que la robustez bajo carga no fue completa.")
  fi

  if [[ "$scales_well" -eq "${#ITERATIONS_VALUES[@]}" ]]; then
    CONCLUSION_LINES+=("En general el servidor escala bien al menos hasta la primera concurrencia evaluada por encima de c=1.")
  elif [[ "$scales_well" -gt 0 ]]; then
    CONCLUSION_LINES+=("El escalado es parcial: algunos valores de i aprovechan la concurrencia y otros no.")
  else
    CONCLUSION_LINES+=("En el rango probado no se observa una mejora clara de throughput al aumentar la concurrencia.")
  fi

  if [[ "$saturates" -gt 0 ]]; then
    CONCLUSION_LINES+=("A concurrencias altas aparece saturacion: el throughput deja de crecer en proporcion y la latencia aumenta.")
  fi

  if [[ "$latency_tradeoff" -gt 0 ]]; then
    CONCLUSION_LINES+=("Hay un tradeoff visible entre throughput y latencia: aun cuando mejora el req/s, el p95 crece de forma apreciable.")
  fi
}

generate_mean_chart_svg() {
  local chart_path="$1"
  local chart_rel
  local width=920
  local height=440
  local margin_left=78
  local margin_right=32
  local margin_top=58
  local margin_bottom=76
  local inner_width=$((width - margin_left - margin_right))
  local inner_height=$((height - margin_top - margin_bottom))
  local tick_count=4
  local max_mean="0"
  local domain_max
  local iterations
  local concurrency
  local value
  local tick
  local tick_value
  local tick_y
  local label_x
  local label_y
  local x
  local y
  local points
  local legend_x="$margin_left"
  local legend_y=28
  local legend_step=132
  local point_index
  local series_index=0
  local concurrency_count="${#CONCURRENCIES_VALUES[@]}"
  local -a palette=("#0f6c5c" "#c85c38" "#245fa6" "#91631a" "#7b3ea8" "#aa2a45")

  chart_rel="$(realpath --relative-to="$PWD" "$chart_path" 2>/dev/null || printf '%s' "$chart_path")"

  for iterations in "${ITERATIONS_VALUES[@]}"; do
    for concurrency in "${CONCURRENCIES_VALUES[@]}"; do
      value="${MEAN_BY_KEY[${iterations}|${concurrency}]}"
      if float_gt "$value" "$max_mean"; then
        max_mean="$value"
      fi
    done
  done

  domain_max="$(awk -v m="$max_mean" 'BEGIN {
    if (m <= 0) {
      printf "1.00"
    } else {
      printf "%.2f", m * 1.10
    }
  }')"

  {
    printf '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %s %s" role="img" aria-label="f(t) segun concurrencia">\n' "$width" "$height"
    printf '  <rect width="100%%" height="100%%" fill="#fbf7ef"/>\n'
    printf '  <text x="%s" y="26" fill="#172033" font-family="Avenir Next, Segoe UI, sans-serif" font-size="22" font-weight="700">f(t) segun concurrencia</text>\n' "$margin_left"
    printf '  <text x="%s" y="46" fill="#566071" font-family="Avenir Next, Segoe UI, sans-serif" font-size="12">f(t) = tiempo medio por request (mean ms). Cada linea corresponde a un valor de i.</text>\n' "$margin_left"

    for iterations in "${ITERATIONS_VALUES[@]}"; do
      local color="${palette[$((series_index % ${#palette[@]}))]}"
      printf '  <circle cx="%s" cy="%s" r="5" fill="%s"/>\n' "$legend_x" "$legend_y" "$color"
      printf '  <text x="%s" y="%s" fill="#566071" font-family="Avenir Next, Segoe UI, sans-serif" font-size="12">i=%s</text>\n' \
        "$((legend_x + 12))" \
        "$((legend_y + 4))" \
        "$iterations"
      legend_x=$((legend_x + legend_step))
      series_index=$((series_index + 1))
    done

    for ((tick = 0; tick <= tick_count; tick += 1)); do
      tick_value="$(awk -v i="$tick" -v ticks="$tick_count" -v max="$domain_max" 'BEGIN { printf "%.2f", (i / ticks) * max }')"
      tick_y="$(scale_linear "$tick_value" "0" "$domain_max" "$((height - margin_bottom))" "$margin_top")"
      printf '  <line x1="%s" y1="%s" x2="%s" y2="%s" stroke="rgba(23,32,51,0.12)" stroke-width="1"/>\n' \
        "$margin_left" \
        "$tick_y" \
        "$((width - margin_right))" \
        "$tick_y"
      printf '  <text x="%s" y="%s" fill="#566071" font-family="Avenir Next, Segoe UI, sans-serif" font-size="12" text-anchor="end">%s</text>\n' \
        "$((margin_left - 12))" \
        "$(awk -v y="$tick_y" 'BEGIN { printf "%.2f", y + 4 }')" \
        "$(format_number "$tick_value" 2)"
    done

    printf '  <line x1="%s" y1="%s" x2="%s" y2="%s" stroke="rgba(23,32,51,0.40)" stroke-width="1.4"/>\n' \
      "$margin_left" \
      "$((height - margin_bottom))" \
      "$((width - margin_right))" \
      "$((height - margin_bottom))"
    printf '  <line x1="%s" y1="%s" x2="%s" y2="%s" stroke="rgba(23,32,51,0.40)" stroke-width="1.4"/>\n' \
      "$margin_left" \
      "$margin_top" \
      "$margin_left" \
      "$((height - margin_bottom))"

    point_index=0
    for concurrency in "${CONCURRENCIES_VALUES[@]}"; do
      if (( concurrency_count == 1 )); then
        x="$(awk -v left="$margin_left" -v plot="$inner_width" 'BEGIN { printf "%.2f", left + plot / 2 }')"
      else
        x="$(scale_linear "$point_index" "0" "$((concurrency_count - 1))" "$margin_left" "$((width - margin_right))")"
      fi
      printf '  <text x="%s" y="%s" fill="#566071" font-family="Avenir Next, Segoe UI, sans-serif" font-size="12" text-anchor="middle">%s</text>\n' \
        "$x" \
        "$((height - margin_bottom + 26))" \
        "$concurrency"
      point_index=$((point_index + 1))
    done

    printf '  <text x="%s" y="%s" fill="#566071" font-family="Avenir Next, Segoe UI, sans-serif" font-size="12" text-anchor="middle">Concurrencia</text>\n' \
      "$((width / 2))" \
      "$((height - 18))"
    printf '  <text x="22" y="%s" fill="#566071" font-family="Avenir Next, Segoe UI, sans-serif" font-size="12" text-anchor="middle" transform="rotate(-90 22 %s)">Tiempo medio por request (ms)</text>\n' \
      "$((height / 2))" \
      "$((height / 2))"

    series_index=0
    for iterations in "${ITERATIONS_VALUES[@]}"; do
      local color="${palette[$((series_index % ${#palette[@]}))]}"
      points=""
      point_index=0
      label_x=""
      label_y=""

      for concurrency in "${CONCURRENCIES_VALUES[@]}"; do
        if (( concurrency_count == 1 )); then
          x="$(awk -v left="$margin_left" -v plot="$inner_width" 'BEGIN { printf "%.2f", left + plot / 2 }')"
        else
          x="$(scale_linear "$point_index" "0" "$((concurrency_count - 1))" "$margin_left" "$((width - margin_right))")"
        fi
        value="${MEAN_BY_KEY[${iterations}|${concurrency}]}"
        y="$(scale_linear "$value" "0" "$domain_max" "$((height - margin_bottom))" "$margin_top")"
        points+="${x},${y} "
        label_x="$x"
        label_y="$y"
        point_index=$((point_index + 1))
      done

      printf '  <polyline fill="none" stroke="%s" stroke-width="3" stroke-linejoin="round" stroke-linecap="round" points="%s"/>\n' \
        "$color" \
        "$points"

      point_index=0
      for concurrency in "${CONCURRENCIES_VALUES[@]}"; do
        if (( concurrency_count == 1 )); then
          x="$(awk -v left="$margin_left" -v plot="$inner_width" 'BEGIN { printf "%.2f", left + plot / 2 }')"
        else
          x="$(scale_linear "$point_index" "0" "$((concurrency_count - 1))" "$margin_left" "$((width - margin_right))")"
        fi
        value="${MEAN_BY_KEY[${iterations}|${concurrency}]}"
        y="$(scale_linear "$value" "0" "$domain_max" "$((height - margin_bottom))" "$margin_top")"
        printf '  <circle cx="%s" cy="%s" r="5" fill="%s" stroke="white" stroke-width="2"/>\n' "$x" "$y" "$color"
        point_index=$((point_index + 1))
      done

      printf '  <text x="%s" y="%s" fill="#172033" font-family="Avenir Next, Segoe UI, sans-serif" font-size="12" font-weight="700">i=%s</text>\n' \
        "$(awk -v x="$label_x" 'BEGIN { printf "%.2f", x + 10 }')" \
        "$(awk -v y="$label_y" 'BEGIN { printf "%.2f", y + 4 }')" \
        "$iterations"

      series_index=$((series_index + 1))
    done

    printf '</svg>\n'
  } >"$chart_path"

  printf 'Chart written to %s\n' "$chart_rel"
}

generate_markdown() {
  local report_path="$1"
  local started_at="$2"
  local report_rel
  local iterations
  local concurrency
  local row
  local value_index

  report_rel="$(realpath --relative-to="$PWD" "$report_path" 2>/dev/null || printf '%s' "$report_path")"

  # The report is intentionally plain Markdown so it can be copied into the assignment as-is.
  {
    printf '# %s\n\n' "$TITLE"
    printf -- '- Generado: `%s`\n' "$started_at"
    printf -- '- Endpoint base: `%s`\n' "$BASE_URL"
    printf -- '- Requests por corrida: `%s`\n' "$REQUESTS"
    printf -- '- Iteraciones: `%s`\n' "$ITERATIONS_CSV"
    printf -- '- Concurrencias: `%s`\n\n' "$CONCURRENCIES_CSV"

    printf '## Tabla base\n\n'
    printf '| i | c | req/s | mean ms | p95 ms | failed |\n'
    printf '| --- | --- | --- | --- | --- | --- |\n'
    for row in "${RESULT_ROWS[@]}"; do
      IFS='|' read -r iterations concurrency rps mean_ms p95_ms failed_requests <<<"$row"
      printf '| %s | %s | %s | %s | %s | %s |\n' \
        "$iterations" \
        "$concurrency" \
        "$(format_number "$rps" 2)" \
        "$(format_number "$mean_ms" 2)" \
        "$(format_number "$p95_ms" 2)" \
        "$failed_requests"
    done

    printf '\n## Grafico f(t) segun concurrencia\n\n'
    printf 'Tomamos `f(t)` como el tiempo medio por request (`mean ms`) y usamos la concurrencia como eje horizontal.\n\n'
    printf '![Grafico de f(t) segun concurrencia](%s)\n' "$CHART_FILE_NAME"

    printf '\n## Tabla derivada\n\n'
    printf '| i |'
    for concurrency in "${NON_BASE_CONCURRENCIES[@]}"; do
      printf ' speedup c=%s |' "$concurrency"
    done
    for concurrency in "${NON_BASE_CONCURRENCIES[@]}"; do
      printf ' p95 penalty c=%s |' "$concurrency"
    done
    printf '\n| --- |'
    for concurrency in "${NON_BASE_CONCURRENCIES[@]}"; do
      printf ' --- |'
    done
    for concurrency in "${NON_BASE_CONCURRENCIES[@]}"; do
      printf ' --- |'
    done
    printf '\n'

    for row in "${DERIVED_ROWS[@]}"; do
      IFS='|' read -r -a parts <<<"$row"
      printf '| %s |' "${parts[0]}"
      for ((value_index = 1; value_index <= ${#NON_BASE_CONCURRENCIES[@]}; value_index += 1)); do
        printf ' %s |' "${parts[$value_index]}"
      done
      for ((value_index = 1 + ${#NON_BASE_CONCURRENCIES[@]}; value_index < ${#parts[@]}; value_index += 1)); do
        printf ' %s |' "${parts[$value_index]}"
      done
      printf '\n'
    done

    printf '\n## Analisis automatico\n\n'
    for row in "${ANALYSIS_LINES[@]}"; do
      printf -- '- %s\n' "$row"
    done

    printf '\n## Conclusion\n\n'
    for row in "${CONCLUSION_LINES[@]}"; do
      printf -- '- %s\n' "$row"
    done
  } >"$report_path"

  printf 'Report written to %s\n' "$report_rel"
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
    --check-iterations)
      [[ $# -ge 2 ]] || die "missing value for $1"
      CHECK_ITERATIONS="$2"
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
require_command curl
require_command realpath

[[ "$REQUESTS" =~ ^[0-9]+$ ]] || die "--requests must be a positive integer"
[[ "$CHECK_ITERATIONS" =~ ^[0-9]+$ ]] || die "--check-iterations must be a positive integer"

parse_csv_into_array "$ITERATIONS_CSV" ITERATIONS_VALUES
parse_csv_into_array "$CONCURRENCIES_CSV" CONCURRENCIES_VALUES
ensure_numbers "iterations" "${ITERATIONS_VALUES[@]}"
ensure_numbers "concurrency" "${CONCURRENCIES_VALUES[@]}"
contains_value "1" "${CONCURRENCIES_VALUES[@]}" || die "concurrency list must include c=1 to compute speedup and latency penalty"

max_concurrency=0
for concurrency in "${CONCURRENCIES_VALUES[@]}"; do
  if (( concurrency > max_concurrency )); then
    max_concurrency="$concurrency"
  fi
done

if (( REQUESTS < max_concurrency )); then
  die "--requests must be greater than or equal to the highest concurrency value (${max_concurrency})"
fi

if [[ -z "$OUT_DIR" ]]; then
  OUT_DIR="benchmarks/$(date -u +%Y%m%d-%H%M%S)"
fi

mkdir -p "$OUT_DIR"

STARTED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
REPORT_PATH="$OUT_DIR/report.md"
CHART_PATH="$OUT_DIR/$CHART_FILE_NAME"
HEALTH_URL="${BASE_URL%/}/$CHECK_ITERATIONS"

echo "Checking server on $HEALTH_URL"
curl --fail --silent --show-error --output /dev/null "$HEALTH_URL" || die "server check failed for $HEALTH_URL"

# Run the full benchmark matrix and keep only the metrics used in the report.
for iterations in "${ITERATIONS_VALUES[@]}"; do
  for concurrency in "${CONCURRENCIES_VALUES[@]}"; do
    target_url="${BASE_URL%/}/$iterations"
    echo "ab -n $REQUESTS -c $concurrency $target_url"
    ab_output="$(run_ab "$target_url" "$concurrency")"
    parsed_metrics="$(parse_ab_output "$ab_output")"
    IFS='|' read -r rps mean_ms p95_ms failed_requests <<<"$parsed_metrics"
    record_result "$iterations" "$concurrency" "$rps" "$mean_ms" "$p95_ms" "$failed_requests"
  done
done

compute_metrics
generate_mean_chart_svg "$CHART_PATH"
generate_markdown "$REPORT_PATH" "$STARTED_AT"

cat <<EOF
Benchmark matrix finished.
Report: $REPORT_PATH
Chart: $CHART_PATH
EOF
