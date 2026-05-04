import { sleep } from "k6";
import { baseUrl, mixedSession } from "./common.js";
import { handleSummary } from "./summary.js";

const vus = Number(__ENV.VUS || 50);
const duration = __ENV.DURATION || "2m";
const checkoutPct = Number(__ENV.CHECKOUT_PCT || 0.2);

export const options = {
  summaryTrendStats: ["avg", "min", "med", "max", "p(90)", "p(95)", "p(99)"],
  scenarios: {
    browse_checkout: {
      executor: "constant-vus",
      vus,
      duration,
    },
  },
  thresholds: {
    http_req_failed: [__ENV.THRESHOLD_ERRORS || "rate<0.50"],
    http_req_duration: [__ENV.THRESHOLD_P95 || "p(95)<8000"],
  },
};

export default function () {
  mixedSession(baseUrl(), checkoutPct);
  sleep(0.3 + Math.random() * 0.7);
}

export { handleSummary };
