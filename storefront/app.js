// The storefront is static: CloudFront serves these files from S3, and the
// browser calls /api/* on the same CloudFront domain, which forwards to the ALB.
const grid = document.getElementById("grid");
const status = document.getElementById("status");
const chips = document.getElementById("categories");
const qInput = document.getElementById("q");
const state = { q: "", category: "" };

const money = (cents) => new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" }).format(cents / 100);

async function getJSON(path) {
  const res = await fetch(path, { headers: { Accept: "application/json" } });
  if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
  return res.json();
}

function card(p) {
  const el = document.createElement("article");
  el.className = "card";
  const stock = p.stock > 0 ? `${p.stock} in stock` : "Out of stock";
  el.innerHTML = `
    <div class="img" aria-hidden="true"></div>
    <h2></h2>
    <p></p>
    <div class="row"><span class="price"></span><span class="stock ${p.stock > 0 ? "" : "out"}"></span></div>`;
  // textContent, never innerHTML, for data from the API.
  el.querySelector(".img").textContent = p.image;
  el.querySelector("h2").textContent = p.name;
  el.querySelector("p").textContent = p.description;
  el.querySelector(".price").textContent = money(p.price_cents);
  el.querySelector(".stock").textContent = stock;
  return el;
}

async function loadProducts() {
  const params = new URLSearchParams();
  if (state.q) params.set("q", state.q);
  if (state.category) params.set("category", state.category);
  status.textContent = "Loading products…";
  try {
    const products = await getJSON(`/api/products?${params}`);
    grid.replaceChildren(...products.map(card));
    status.textContent = products.length ? `${products.length} products` : "No products match.";
  } catch (err) {
    grid.replaceChildren();
    status.textContent = `The catalog isn't reachable right now (${err.message}). Is a lab running?`;
  }
  showServedBy();
}

async function loadCategories() {
  try {
    const cats = ["", ...(await getJSON("/api/categories"))];
    chips.replaceChildren(...cats.map((c) => {
      const b = document.createElement("button");
      b.type = "button";
      b.className = "chip";
      b.textContent = c || "All";
      b.setAttribute("aria-pressed", String(c === state.category));
      b.addEventListener("click", () => {
        state.category = c;
        chips.querySelectorAll(".chip").forEach((x) => x.setAttribute("aria-pressed", String(x === b)));
        loadProducts();
      });
      return b;
    }));
  } catch { /* the product call reports the error */ }
}

// Shows which pod answered; refresh to watch the ALB alternate between pods.
async function showServedBy() {
  try {
    const info = await getJSON("/api/info");
    document.getElementById("served-by").textContent = `Served by pod ${info.pod} on ${info.node}`;
  } catch { /* optional */ }
}

document.getElementById("search").addEventListener("submit", (e) => {
  e.preventDefault();
  state.q = qInput.value.trim();
  loadProducts();
});

loadCategories();
loadProducts();
