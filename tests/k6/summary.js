/**
 * Prints a concise report: latency (avg, P95, P99), throughput (req/s), error rate (%).
 * k6 also prints its default end-of-test summary; this adds a single copy-paste friendly block.
 */
export function handleSummary(data) {
  const dur = data.metrics.http_req_duration?.values;
  const reqs = data.metrics.http_reqs?.values;
  const failed = data.metrics.http_req_failed?.values;
  const runMs = data.state?.testRunDurationMs || 1;
  const runSec = runMs / 1000;
  const totalReqs = reqs?.count ?? 0;
  const rps = totalReqs / runSec;
  const errPct = failed?.rate != null ? (failed.rate * 100).toFixed(2) : "n/a";

  const line = (label, val) =>
    `${label.padEnd(22)} ${val === undefined || val === null ? "n/a" : typeof val === "number" ? val.toFixed(2) : val}`;

  const block = [
    "",
    "========== PrimeCart k6 summary ==========",
    line("Duration (s)", runSec),
    line("Total HTTP requests", totalReqs),
    line("Throughput (req/s)", rps),
    line("Error rate (%)", errPct),
    line("Latency avg (ms)", dur?.avg),
    line("Latency med (ms)", dur?.med),
    line("Latency P95 (ms)", dur?.["p(95)"]),
    line("Latency P99 (ms)", dur?.["p(99)"]),
    line("Latency max (ms)", dur?.max),
    "==========================================",
    "",
  ].join("\n");

  return { stdout: block };
}
