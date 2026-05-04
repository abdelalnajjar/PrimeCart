import { sleep } from "k6";
import { baseUrl, mixedSession } from "./common.js";
import { handleSummary } from "./summary.js";

/**
 * Black Friday–style spike: low baseline, sharp ramp, sustained peak, cooldown.
 * Tune with env: SPIKE_TARGET_VUS, BASELINE_VUS, BASELINE_DURATION, etc.
 */
const baselineVus = Number(__ENV.BASELINE_VUS || 10);
const spikeTarget = Number(__ENV.SPIKE_TARGET_VUS || 200);
const checkoutPct = Number(__ENV.CHECKOUT_PCT || 0.25);

export const options = {
  summaryTrendStats: ["avg", "min", "med", "max", "p(90)", "p(95)", "p(99)"],
  scenarios: {
    black_friday_spike: {
      executor: "ramping-vus",
      startVUs: 0,
      stages: [
        { duration: __ENV.STAGE_BASELINE || "1m", target: baselineVus },
        { duration: __ENV.STAGE_RAMP_UP || "30s", target: spikeTarget },
        { duration: __ENV.STAGE_PEAK || "2m", target: spikeTarget },
        { duration: __ENV.STAGE_RAMP_DOWN || "1m", target: baselineVus },
        { duration: __ENV.STAGE_COOLDOWN || "30s", target: 0 },
      ],
      gracefulRampDown: "30s",
    },
  },
  thresholds: {
    http_req_failed: [__ENV.THRESHOLD_ERRORS || "rate<0.60"],
    http_req_duration: [__ENV.THRESHOLD_P99 || "p(99)<15000"],
  },
};

export default function () {
  mixedSession(baseUrl(), checkoutPct);
  sleep(0.2 + Math.random() * 0.6);
}

export { handleSummary };
