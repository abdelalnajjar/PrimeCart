import http from "k6/http";
import { check, sleep } from "k6";

const products = JSON.parse(open("../../data/products.json"));

export function baseUrl() {
  return __ENV.BASE_URL || "http://localhost:3000";
}

export function randomProduct() {
  return products[Math.floor(Math.random() * products.length)];
}

function toUrlEncoded(obj) {
  return Object.keys(obj)
    .map((k) => `${encodeURIComponent(k)}=${encodeURIComponent(String(obj[k]))}`)
    .join("&");
}

export function browseHome(base) {
  const res = http.get(`${base}/`);
  check(res, { "home 200": (r) => r.status === 200 });
  return res;
}

export function browseCheckoutPage(base, productId) {
  const res = http.get(`${base}/checkout/${productId}`);
  check(res, { "checkout page 200": (r) => r.status === 200 });
  return res;
}

export function browseStatic(base) {
  const res = http.get(`${base}/styles.css`);
  check(res, { "styles 200": (r) => r.status === 200 });
  return res;
}

export function browseFlow(base) {
  browseHome(base);
  sleep(0.2 + Math.random() * 0.5);
  const p = randomProduct();
  browseCheckoutPage(base, p.id);
  sleep(0.1 + Math.random() * 0.3);
  browseStatic(base);
  sleep(0.1 + Math.random() * 0.2);
  return p;
}

export function submitOrder(base, product) {
  const body = toUrlEncoded({
    firstName: "Load",
    lastName: "Test",
    email: `k6_${__VU}_${__ITER}_${Date.now()}@example.com`,
    street: "1 Washington Sq",
    city: "San Jose",
    state: "CA",
    zip: "95112",
    country: "USA",
    productId: product.id,
    quantity: "1",
  });

  const res = http.post(`${base}/orders`, body, {
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
  });

  check(res, {
    "order 201": (r) => r.status === 201,
    "order confirmation html": (r) =>
      r.status === 201 && String(r.body).includes("Order"),
  });
  return res;
}

export function mixedSession(base, checkoutProbability) {
  const p = browseFlow(base);
  if (Math.random() < checkoutProbability) {
    sleep(0.2 + Math.random() * 0.4);
    submitOrder(base, p);
  }
}
