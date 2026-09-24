const $ = s => document.querySelector(s);
let SESSION = null;

const api = async (path, opts = {}) => {
  const res = await fetch(GS.baseURL + path, {
    ...opts,
    headers: {
      "Content-Type": "application/json",
      Authorization: "Bearer " + (SESSION ? SESSION.accessToken : GS.anonKey),
      ...(opts.headers || {}),
    },
  });
  const text = await res.text();
  let body = null;
  try { body = text ? JSON.parse(text) : null; } catch { body = text; }
  if (!res.ok) throw new Error((body && body.message) || `${res.status}`);
  return body;
};
const rows = (table, query = "") => api(`/api/database/records/${table}${query ? "?" + query : ""}`);

// Privileged mutations run through the server-side `admin` function, which re-checks
// is_admin before touching anything with the service key.
async function adminFn(payload) {
  const res = await fetch(GS.functionsURL + "/admin", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: "Bearer " + SESSION.accessToken },
    body: JSON.stringify(payload),
  });
  const d = await res.json().catch(() => ({}));
  if (!res.ok || d.error) throw new Error(d.error || `${res.status}`);
  return d;
}

// ---------- sign in ----------
async function signIn() {
  const email = $("#em").value.trim(), password = $("#pw").value;
  const err = $("#gerr");
  err.classList.add("hidden");
  $("#go").disabled = true; $("#go").textContent = "Signing in…";
  try {
    const r = await fetch(GS.baseURL + "/api/auth/sessions?client_type=web", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: "Bearer " + GS.anonKey },
      body: JSON.stringify({ method: "password", email, password }),
    });
    const d = await r.json();
    if (!r.ok) throw new Error(d.message || "Sign-in failed");
    SESSION = { accessToken: d.accessToken, userID: d.user.id, name: d.user.name || email };

    // Authorisation is the server's call, not ours: ask for this profile and
    // check the flag the RLS policies key off.
    const me = await rows("profiles", `id=eq.${SESSION.userID}&select=display_name,is_admin,admin_role&limit=1`);
    if (!me.length || !me[0].is_admin) throw new Error("That account is not an admin.");

    SESSION.name = me[0].display_name || SESSION.name;
    // Legacy owners with no explicit role are full SUPER_ADMIN.
    SESSION.role = me[0].admin_role || "SUPER_ADMIN";
    sessionStorage.setItem("gs_admin", JSON.stringify(SESSION));
    enter();
  } catch (e) {
    err.textContent = e.message;
    err.classList.remove("hidden");
  } finally {
    $("#go").disabled = false; $("#go").textContent = "Sign in";
  }
}

function enter() {
  $("#gate").classList.add("hidden");
  $("#app").classList.remove("hidden");
  $("#whoName").textContent = SESSION.name;
  $("#avatar").textContent = (SESSION.name || "A").trim().charAt(0).toUpperCase() || "A";
  // Hide nav entries this role can't use (e.g. Security is SUPER_ADMIN only).
  document.querySelectorAll("nav button[data-min]").forEach(b => {
    b.hidden = !can(b.dataset.min);
  });
  show("overview");
  refreshSupportBadge();
  setInterval(refreshSupportBadge, 60_000);
}

// Count of conversations waiting on a person, shown next to "Support" in the nav.
async function refreshSupportBadge() {
  try {
    const waiting = await rows("support_conversations", "select=id&status=eq.needs_human&limit=100");
    const b = $("#supportBadge");
    b.textContent = waiting.length >= 100 ? "99+" : String(waiting.length);
    b.classList.toggle("hidden", waiting.length === 0);
  } catch { /* table not deployed yet */ }
}

$("#go").addEventListener("click", signIn);
$("#pw").addEventListener("keydown", e => { if (e.key === "Enter") signIn(); });
$("#out").addEventListener("click", () => { sessionStorage.removeItem("gs_admin"); location.reload(); });

// ---------- helpers ----------
// Escapes for BOTH text nodes and double/single-quoted attribute values — several data-*
// attributes are built from user-controlled text (display names, ids), so quotes must be
// encoded too or a crafted name could break out of the attribute and inject script.
const esc = s => String(s ?? "").replace(/[<>&"']/g, c =>
  ({ "<": "&lt;", ">": "&gt;", "&": "&amp;", '"': "&quot;", "'": "&#39;" }[c]));
const when = d => d ? new Date(d).toLocaleDateString(undefined, { day: "numeric", month: "short", year: "numeric" }) : "—";
const planPill = p => `<span class="pill p-${p || "free"}">${p || "free"}</span>`;

// Role tiers — the dashboard hides controls the caller can't use, but the `admin` edge
// function is the true enforcer (it re-checks the role for every write).
const ROLE_RANK = { READ_ONLY: 0, SUPPORT: 1, MODERATOR: 2, ADMIN: 3, SUPER_ADMIN: 4 };
const can = minRole => (ROLE_RANK[SESSION?.role] ?? -1) >= (ROLE_RANK[minRole] ?? 99);
const rolePill = r => `<span class="pill p-${r === "SUPER_ADMIN" || r === "ADMIN" ? "pro" : "plus"}">${(r || "—").toLowerCase().replace("_", " ")}</span>`;
const dayKey = d => d.toISOString().slice(0, 10);

// Brief inline confirmation on a table row after an action.
function flash(tr, msg) {
  const cell = tr.querySelector(".rowacts") || tr.lastElementChild;
  const tag = document.createElement("span");
  tag.className = "flash"; tag.textContent = msg;
  cell.appendChild(tag);
  setTimeout(() => tag.remove(), 1600);
}

// Last 7 calendar days (oldest → today) with a short weekday label.
function last7() {
  const out = [];
  for (let i = 6; i >= 0; i--) {
    const d = new Date(); d.setHours(0, 0, 0, 0); d.setDate(d.getDate() - i);
    out.push({ key: dayKey(d), label: d.toLocaleDateString(undefined, { weekday: "short" }) });
  }
  return out;
}

// The overview's selected window in days (7 / 30 / 90). Default 30 (spec).
let ovDays = 30;

// Buckets spanning the last `days`: daily for ≤31d, weekly (Monday-start) beyond, so bars
// never crowd. Each bucket = {key,label,start,end}.
function ovBuckets(days) {
  const now = new Date(); now.setHours(0, 0, 0, 0);
  const out = [];
  if (days <= 31) {
    for (let i = days - 1; i >= 0; i--) {
      const d = new Date(now); d.setDate(d.getDate() - i);
      out.push({ key: dayKey(d), label: days <= 7 ? d.toLocaleDateString(undefined, { weekday: "short" }) : String(d.getDate()),
        start: new Date(d), end: new Date(d.getTime() + 86400000) });
    }
  } else {
    const weeks = Math.ceil(days / 7);
    const mon = new Date(now); mon.setDate(mon.getDate() - ((mon.getDay() + 6) % 7));
    for (let i = weeks - 1; i >= 0; i--) {
      const s = new Date(mon); s.setDate(s.getDate() - i * 7);
      out.push({ key: dayKey(s), label: s.toLocaleDateString(undefined, { day: "numeric", month: "short" }),
        start: new Date(s), end: new Date(s.getTime() + 7 * 86400000) });
    }
  }
  return out;
}

// Count items into buckets by a date field.
function bucketize(items, field, buckets) {
  const counts = {}; buckets.forEach(b => counts[b.key] = 0);
  const first = buckets[0].start;
  items.forEach(it => {
    const t = new Date(it[field]); if (isNaN(t) || t < first) return;
    for (const b of buckets) { if (t >= b.start && t < b.end) { counts[b.key]++; break; } }
  });
  return counts;
}

// Bar chart from a [{key,label}] axis and a {key:count} map.
function barChart(axis, counts) {
  const max = Math.max(1, ...axis.map(a => counts[a.key] || 0));
  const today = axis[axis.length - 1].key;
  return `<div class="bars">${axis.map(a => {
    const v = counts[a.key] || 0;
    const h = Math.round((v / max) * 100);
    return `<div class="col"><div class="bar ${a.key === today ? "" : "soft"}" style="height:${Math.max(h, 3)}%" title="${v}"></div><div class="lbl">${a.label}</div></div>`;
  }).join("")}</div>`;
}

// SVG donut from [{label,value,color}].
function donut(segs, centerN, centerT) {
  const total = segs.reduce((s, x) => s + x.value, 0) || 1;
  const R = 78, C = 2 * Math.PI * R;
  let offset = 0;
  const rings = segs.filter(s => s.value > 0).map(s => {
    const len = (s.value / total) * C;
    const dash = `${len} ${C - len}`;
    const el = `<circle cx="95" cy="95" r="${R}" fill="none" stroke="${s.color}" stroke-width="26"
      stroke-dasharray="${dash}" stroke-dashoffset="${-offset}" transform="rotate(-90 95 95)"
      stroke-linecap="butt"></circle>`;
    offset += len;
    return el;
  }).join("");
  return `<div class="donut">
    <svg viewBox="0 0 190 190" width="190" height="190">
      <circle cx="95" cy="95" r="78" fill="none" stroke="var(--fill)" stroke-width="26"></circle>
      ${rings}
    </svg>
    <div class="mid"><div><div class="n num">${centerN}</div><div class="t">${centerT}</div></div></div>
  </div>`;
}

// ---------- views ----------
const TITLES = {
  overview: ["Dashboard", "Live data from your backend"],
  users:    ["Members", "Accounts, plans and quota"],
  posts:    ["Community", "Posts people have shared"],
  reports:  ["Moderation", "Reported content awaiting a decision"],
  support:  ["Support", "Customer conversations — the assistant answers, your team takes over"],
  knowledge:["Assistant", "What the support assistant knows and how it behaves"],
  catalog:  ["Catalog", "The Discover recipe collection"],
  subs:     ["Subscriptions", "Apple subscription bindings"],
  groups:   ["Groups", "Community groups"],
  audit:    ["Audit log", "Every admin action, most recent first"],
  finance:  ["Finance", "Revenue, AI/API spend and profit"],
  notifs:   ["Notifications", "Broadcast in-app announcements"],
  config:   ["Configuration", "App config documents (versioned)"],
  maint:    ["Maintenance", "Put the app into maintenance mode"],
  security: ["Security", "Administrators and their roles"],
};

// Money + time formatting shared across views.
const usd = micros => "$" + (Number(micros || 0) / 1_000_000).toFixed(2);
const ago = d => {
  if (!d) return "—";
  const s = (Date.now() - new Date(d)) / 1000;
  if (s < 60) return "just now";
  if (s < 3600) return Math.floor(s / 60) + "m ago";
  if (s < 86400) return Math.floor(s / 3600) + "h ago";
  return Math.floor(s / 86400) + "d ago";
};

document.querySelectorAll("nav button").forEach(b =>
  b.addEventListener("click", () => show(b.dataset.v)));

// Views that poll register their timer here so leaving the view stops it.
let viewTimer = null;

async function show(v) {
  clearInterval(viewTimer); viewTimer = null;
  document.querySelectorAll("nav button").forEach(b =>
    b.setAttribute("aria-current", String(b.dataset.v === v)));
  $("#title").textContent = TITLES[v][0];
  $("#subtitle").textContent = TITLES[v][1];
  $("#view").innerHTML = `<div class="spin">Loading…</div>`;
  try { await VIEWS[v](); }
  catch (e) { $("#view").innerHTML = `<div class="card panel"><div class="empty">Couldn't load: ${e.message}</div></div>`; }
}

const VIEWS = {
  async overview() {
    const days = ovDays;
    const axis = ovBuckets(days);
    const since = axis[0].start;
    const prevSince = new Date(since.getTime() - days * 86400000);
    const rangeLabel = days === 7 ? "last 7 days" : days === 30 ? "last 30 days" : "last 90 days";
    const [profiles, ents, subs, usage] = await Promise.all([
      rows("profiles", "select=id,created_at,display_name,country&order=created_at.desc"),
      rows("entitlements", "select=user_id,plan,used").catch(() => []),
      rows("app_store_transactions", "select=user_id,plan,environment,expires_at,revoked_at,created_at&order=created_at.desc").catch(() => []),
      rows("ai_usage", `select=user_id,created_at,cost_micros,refunded&created_at=gte.${prevSince.toISOString()}`).catch(() => []),
    ]);

    const PRICE = { plus: 9.99, pro: 12.99 };
    const totalMembers = profiles.length;

    // Plan mix from entitlements.
    const byPlan = { free: 0, plus: 0, pro: 0 };
    const entByUser = {};
    ents.forEach(e => { entByUser[e.user_id] = e; });
    profiles.forEach(p => { const pl = (entByUser[p.id] || {}).plan || "free"; byPlan[pl] = (byPlan[pl] || 0) + 1; });
    const paying = byPlan.plus + byPlan.pro;
    const mrr = byPlan.plus * PRICE.plus + byPlan.pro * PRICE.pro;

    // MRR trend: compare current vs previous period's paying count.
    let payNow = 0, payPrev = 0;
    subs.forEach(s => {
      if (s.revoked_at) return;
      const exp = s.expires_at ? new Date(s.expires_at) : null;
      const created = new Date(s.created_at);
      if (!exp || exp > new Date()) payNow++;
      if (created >= prevSince && created < since) payPrev++;
    });

    // New members this window vs previous.
    let newNow = 0, newPrev = 0;
    profiles.forEach(p => {
      const t = new Date(p.created_at);
      if (t >= since) newNow++;
      else if (t >= prevSince) newPrev++;
    });
    const userTrend = newPrev < 3 ? null : Math.round(((newNow - newPrev) / newPrev) * 100);

    // Active subscriptions chart: count of each plan at each bucket.
    const subsByBucket = axis.map(b => {
      const c = { free: 0, plus: 0, pro: 0 };
      profiles.forEach(p => {
        const joined = new Date(p.created_at);
        if (joined >= b.end) return;
        const e = entByUser[p.id];
        c[(e && e.plan) || "free"]++;
      });
      return c;
    });
    const stackMax = Math.max(1, ...subsByBucket.map(c => c.plus + c.pro));
    const subsChart = `<div class="stacked-bars">${axis.map((a, i) => {
      const c = subsByBucket[i];
      const plusH = Math.round((c.plus / stackMax) * 100);
      const proH = Math.round((c.pro / stackMax) * 100);
      return `<div class="scol">
        <div class="sstack" title="Plus: ${c.plus}, Pro: ${c.pro}">
          <div class="sbar pro" style="height:${Math.max(proH, c.pro ? 3 : 0)}%"></div>
          <div class="sbar plus" style="height:${Math.max(plusH, c.plus ? 3 : 0)}%"></div>
        </div>
        <div class="lbl">${a.label}</div>
      </div>`;
    }).join("")}</div>`;

    // Top countries.
    const countryCounts = {};
    profiles.forEach(p => {
      const c = (p.country || "").trim();
      if (!c) return;
      countryCounts[c] = (countryCounts[c] || 0) + 1;
    });
    const countryName = code => { try { return new Intl.DisplayNames(["en"], { type: "region" }).of(code) || code; } catch { return code; } };
    const topCountries = Object.entries(countryCounts).sort((a, b) => b[1] - a[1]).slice(0, 8);
    const countryMax = Math.max(1, ...topCountries.map(c => c[1]));

    // Usage by user: top users by AI action count.
    const usageByUser = {};
    const spendByUser = {};
    usage.filter(u => new Date(u.created_at) >= since).forEach(u => {
      usageByUser[u.user_id] = (usageByUser[u.user_id] || 0) + 1;
      if (!u.refunded) spendByUser[u.user_id] = (spendByUser[u.user_id] || 0) + Number(u.cost_micros || 0);
    });
    const profileMap = Object.fromEntries(profiles.map(p => [p.id, p]));
    const topUsers = Object.entries(usageByUser).sort((a, b) => b[1] - a[1]).slice(0, 10);

    // Totals for AI spend tile.
    const usage7 = usage.filter(u => new Date(u.created_at) >= since);
    const spend7 = usage7.reduce((s, u) => s + (u.refunded ? 0 : Number(u.cost_micros || 0)), 0);

    const planSegs = [
      { label: "Free", value: byPlan.free, color: "#3A3320" },
      { label: "Plus", value: byPlan.plus, color: "var(--yellow-soft)" },
      { label: "Pro",  value: byPlan.pro,  color: "var(--yellow)" },
    ];
    const pct = v => totalMembers ? Math.round((v / totalMembers) * 100) : 0;

    const tile = (k, v, d = "", cls = "") =>
      `<div class="card tile"><div class="k">${k}</div><div class="v num ${cls}">${v}</div><div class="d">${d}</div></div>`;

    $("#view").innerHTML = `
      <div class="toolbar">
        <div style="flex:1"></div>
        ${[7, 30, 90].map(d => `<button class="fbtn" data-range="${d}" aria-pressed="${d === days}">${d === 7 ? "1 week" : d === 30 ? "1 month" : "3 months"}</button>`).join("")}
      </div>

      <div class="row tiles">
        ${tile("Est. MRR", "$" + mrr.toFixed(2), `${paying} paying members`)}
        ${tile("Total users", totalMembers, userTrend !== null ? `${userTrend >= 0 ? "+" : ""}${userTrend}% vs prev period` : `${newNow} new · ${rangeLabel}`)}
        ${tile("Active subs", paying, `${byPlan.plus} plus · ${byPlan.pro} pro`)}
        ${tile("AI spend", usd(spend7), `${usage7.length} actions · ${rangeLabel}`)}
      </div>

      <div class="row two">
        <div class="card pad">
          <div class="cap">Active subscriptions <span class="mut">· paid plans · ${rangeLabel}</span></div>
          <div style="display:flex;gap:14px;margin:12px 0 0;font-size:12px;font-weight:800">
            <span style="display:flex;align-items:center;gap:6px"><span class="sw" style="background:var(--yellow);width:9px;height:9px;border-radius:50%;display:inline-block"></span>Pro</span>
            <span style="display:flex;align-items:center;gap:6px"><span class="sw" style="background:var(--yellow-soft);width:9px;height:9px;border-radius:50%;display:inline-block"></span>Plus</span>
          </div>
          ${subsChart}
        </div>
        <div class="card pad">
          <div class="cap">Plan distribution</div>
          <div class="donut-wrap" style="margin-top:8px">
            ${donut(planSegs, totalMembers, "Members")}
            <div class="legend">
              ${planSegs.map(s => `<div class="li"><span class="sw" style="background:${s.color}"></span>
                <span class="nm">${s.label}</span><span class="pc">${pct(s.value)}%</span></div>`).join("")}
              <div class="li"><span class="sw" style="background:var(--ok)"></span>
                <span class="nm">Paying</span><span class="pc">${pct(paying)}%</span></div>
            </div>
          </div>
        </div>
      </div>

      <div class="row two">
        <div class="card pad">
          <div class="cap" style="margin-bottom:16px">Revenue by plan</div>
          <div class="tw"><table>
            <thead><tr><th>Plan</th><th>Members</th><th>Price/mo</th><th>Subtotal/mo</th></tr></thead>
            <tbody>
              <tr><td>${planPill("plus")}</td><td class="num">${byPlan.plus}</td><td class="num">$${PRICE.plus}</td><td class="num">$${(byPlan.plus * PRICE.plus).toFixed(2)}</td></tr>
              <tr><td>${planPill("pro")}</td><td class="num">${byPlan.pro}</td><td class="num">$${PRICE.pro}</td><td class="num">$${(byPlan.pro * PRICE.pro).toFixed(2)}</td></tr>
              <tr style="border-top:2px solid var(--line)"><td style="font-weight:900">Total</td><td class="num" style="font-weight:900">${paying}</td><td></td><td class="num" style="font-weight:900">$${mrr.toFixed(2)}</td></tr>
            </tbody>
          </table></div>
          <p style="color:var(--muted);font-size:11.5px;margin:12px 0 0">Estimated from active paid plans × list price. Real billing is in App Store Connect.</p>
        </div>

        <div class="card pad">
          <div class="cap" style="margin-bottom:16px">Top user countries</div>
          <div class="alerts">
            ${topCountries.length ? topCountries.map(([code, n]) => `<div class="alert">
              <div class="top"><span>${esc(countryName(code))}</span><span class="r num">${n}</span></div>
              <div class="track"><span style="width:${Math.round((n / countryMax) * 100)}%"></span></div>
            </div>`).join("") : `<div class="empty">No country data yet — users will report their locale on next sign-in</div>`}
          </div>
        </div>
      </div>

      <div class="card panel">
        <div class="panel-h"><h2>Usage by user</h2><span class="note">AI actions · ${rangeLabel}</span></div>
        <div class="tw"><table>
          <thead><tr><th>User</th><th>Plan</th><th>Actions</th><th>Spend</th><th>Quota used</th></tr></thead>
          <tbody>${topUsers.map(([uid, count]) => {
            const p = profileMap[uid];
            const e = entByUser[uid] || {};
            const plan = e.plan || "free";
            const used = e.used ?? 0;
            return `<tr>
              <td><strong>${esc(p ? p.display_name : uid.slice(0, 8) + "…")}</strong></td>
              <td>${planPill(plan)}</td>
              <td class="num">${count}</td>
              <td class="num">${usd(spendByUser[uid] || 0)}</td>
              <td class="num">${used}</td>
            </tr>`;
          }).join("") || `<tr><td colspan="5" class="empty">No AI usage in this period</td></tr>`}
          </tbody>
        </table></div>
      </div>`;

    document.querySelectorAll("[data-range]").forEach(b =>
      b.addEventListener("click", () => { ovDays = Number(b.dataset.range); show("overview"); }));
  },

  async users() {
    const [profiles, ents] = await Promise.all([
      rows("profiles", "select=id,display_name,created_at,is_admin&order=created_at.desc"),
      rows("entitlements", "select=user_id,plan,used").catch(() => []),
    ]);
    const byUser = Object.fromEntries(ents.map(e => [e.user_id, e]));
    const me = SESSION.userID;
    $("#view").innerHTML = `<div class="toolbar"><div style="flex:1"></div><button class="btn" id="csv">Export CSV</button></div>
      <div class="card panel"><div class="panel-h"><h2>Accounts</h2>
      <span class="note">${profiles.length} total</span></div><div class="tw"><table>
      <thead><tr><th>Name</th><th>Plan</th><th>Used</th><th>Joined</th><th>Actions</th></tr></thead><tbody>
      ${profiles.map(p => {
        const e = byUser[p.id];
        const plan = (e && e.plan) || "free";
        const self = p.id === me;
        return `<tr data-uid="${p.id}" data-name="${esc(p.display_name || "this user")}">
          <td><strong>${esc(p.display_name) || "—"}</strong> ${p.is_admin ? '<span class="pill p-admin">admin</span>' : ""}${self ? ' <span class="pill p-free">you</span>' : ""}</td>
          <td><select class="sel" data-plan ${self ? "disabled" : ""}>
            ${["free", "plus", "pro"].map(o => `<option value="${o}" ${o === plan ? "selected" : ""}>${o}</option>`).join("")}
          </select></td>
          <td class="num">${e ? e.used ?? 0 : 0}</td>
          <td class="num" style="color:var(--muted)">${when(p.created_at)}</td>
          <td class="rowacts">
            <button class="link" data-detail>Detail</button>
            ${self ? "" : `<button class="link" data-admin="${p.is_admin ? "revoke" : "grant"}">${p.is_admin ? "Revoke admin" : "Make admin"}</button>
            <button class="btn danger" data-deluser>Delete</button>`}
          </td>
        </tr>`;
      }).join("") || `<tr><td colspan="5" class="empty">No accounts yet</td></tr>`}
      </tbody></table></div></div>`;

    $("#csv").addEventListener("click", () => exportCSV("members.csv",
      profiles.map(p => ({ name: p.display_name, plan: (byUser[p.id] || {}).plan || "free",
        used: (byUser[p.id] || {}).used ?? 0, admin: !!p.is_admin, joined: p.created_at })),
      [{ key: "name", label: "Name" }, { key: "plan", label: "Plan" }, { key: "used", label: "Used" },
       { key: "admin", label: "Admin" }, { key: "joined", label: "Joined" }]));

    document.querySelectorAll("[data-detail]").forEach(b =>
      b.addEventListener("click", () => { const tr = b.closest("tr"); openUserDetail(tr.dataset.uid, tr.dataset.name); }));

    // Change plan on select.
    document.querySelectorAll("select[data-plan]").forEach(sel =>
      sel.addEventListener("change", async () => {
        const tr = sel.closest("tr"), prev = sel.dataset.prev || sel.value;
        sel.disabled = true;
        try {
          await adminFn({ action: "set_plan", userId: tr.dataset.uid, plan: sel.value });
          sel.dataset.prev = sel.value;
          flash(tr, `Plan set to ${sel.value}`);
        } catch (e) { alert("Couldn't change plan: " + e.message); sel.value = prev; }
        finally { sel.disabled = false; }
      }));

    // Grant / revoke admin.
    document.querySelectorAll("[data-admin]").forEach(b =>
      b.addEventListener("click", async () => {
        const tr = b.closest("tr");
        const grant = b.dataset.admin === "grant";
        if (!confirm(`${grant ? "Grant admin to" : "Revoke admin from"} ${tr.dataset.name}?`)) return;
        b.disabled = true;
        try {
          await adminFn({ action: "set_admin", userId: tr.dataset.uid, value: grant });
          show("users");
        } catch (e) { alert("Couldn't update: " + e.message); b.disabled = false; }
      }));

    // Delete user.
    document.querySelectorAll("[data-deluser]").forEach(b =>
      b.addEventListener("click", async () => {
        const tr = b.closest("tr");
        const ok = await confirmTyped({
          title: `Delete ${tr.dataset.name}?`,
          body: "This erases their account, posts, plan and photos. This cannot be undone.",
          phrase: "DELETE", danger: "Delete account",
        });
        if (!ok) return;
        b.disabled = true; b.textContent = "Deleting…";
        try {
          await adminFn({ action: "delete_user", userId: tr.dataset.uid });
          tr.remove();
        } catch (e) { alert("Couldn't delete: " + e.message); b.disabled = false; b.textContent = "Delete"; }
      }));
  },

  async posts() {
    const all = await rows("posts", "select=id,author_name,caption,kind,like_count,comment_count,hidden_at,created_at&order=created_at.desc&limit=500");
    let filter = "all", term = "";
    const render = () => {
      const list = all.filter(p => {
        if (filter === "hidden" && !p.hidden_at) return false;
        if (filter !== "all" && filter !== "hidden" && (p.kind || "photo") !== filter) return false;
        if (term && !((p.caption || "") + " " + (p.author_name || "")).toLowerCase().includes(term)) return false;
        return true;
      });
      const kinds = ["all", "photo", "recipe", "reel", "question", "text", "hidden"];
      $("#view").innerHTML = `
        <div class="toolbar">
          <input class="search" id="ps" placeholder="Search caption or author…" value="${esc(term)}">
          ${kinds.map(k => `<button class="fbtn" data-f="${k}" aria-pressed="${k === filter}">${k}</button>`).join("")}
        </div>
        <div class="card panel"><div class="panel-h"><h2>Posts</h2><span class="note">${list.length} of ${all.length}</span></div>
        <div class="tw"><table>
        <thead><tr><th>Post</th><th>Type</th><th>♥</th><th>Replies</th><th>When</th><th>Actions</th></tr></thead><tbody>
        ${list.map(p => `<tr data-id="${p.id}">
          <td><strong>${esc(p.author_name)}</strong> ${p.hidden_at ? '<span class="pill k-photo">hidden</span>' : ""}<br><span style="color:var(--muted)">${esc((p.caption || "").slice(0, 90)) || "—"}</span></td>
          <td><span class="pill k-${esc(p.kind || "photo")}">${esc(p.kind || "post")}</span></td>
          <td class="num">${p.like_count ?? 0}</td>
          <td class="num">${p.comment_count ?? 0}</td>
          <td class="num" style="color:var(--muted)">${when(p.created_at)}</td>
          <td class="rowacts">
            <button class="link" data-hide="${p.hidden_at ? "0" : "1"}">${p.hidden_at ? "Unhide" : "Hide"}</button>
            <button class="btn danger" data-del>Delete</button>
          </td>
        </tr>`).join("") || `<tr><td colspan="6" class="empty">No posts match</td></tr>`}
        </tbody></table></div></div>`;

      const ps = $("#ps");
      ps.addEventListener("input", () => { term = ps.value.trim().toLowerCase(); const at = ps.selectionStart; render(); const n = $("#ps"); n.focus(); n.setSelectionRange(at, at); });
      document.querySelectorAll("[data-f]").forEach(b => b.addEventListener("click", () => { filter = b.dataset.f; render(); }));
      document.querySelectorAll("[data-hide]").forEach(b => b.addEventListener("click", async () => {
        const tr = b.closest("tr"); b.disabled = true;
        try { await adminFn({ action: "hide_content", targetType: "post", id: tr.dataset.id, hidden: b.dataset.hide === "1" });
          const rec = all.find(x => x.id === tr.dataset.id); if (rec) rec.hidden_at = b.dataset.hide === "1" ? new Date().toISOString() : null; render();
        } catch (e) { alert("Couldn't update: " + e.message); b.disabled = false; }
      }));
      document.querySelectorAll("[data-del]").forEach(b => b.addEventListener("click", async () => {
        const tr = b.closest("tr");
        if (!confirm("Permanently delete this post? Hiding is reversible; deleting is not.")) return;
        b.disabled = true; b.textContent = "Deleting…";
        try { await adminFn({ action: "delete_content", targetType: "post", id: tr.dataset.id });
          const i = all.findIndex(x => x.id === tr.dataset.id); if (i >= 0) all.splice(i, 1); render();
        } catch (e) { alert("Couldn't delete: " + e.message); b.disabled = false; b.textContent = "Delete"; }
      }));
    };
    render();
  },

  async reports() {
    const list = await rows("content_reports", "select=*&order=created_at.desc").catch(() => []);
    // Resolve the actual reported content so the admin can judge it, in 3 batched reads.
    const ids = t => [...new Set(list.filter(r => r[t]).map(r => r[t]))];
    const inList = a => a.length ? `id=in.(${a.join(",")})` : "id=eq.00000000-0000-0000-0000-000000000000";
    const [postRows, commentRows, reviewRows] = await Promise.all([
      ids("post_id").length ? rows("posts", `select=id,caption,author_name,hidden_at&${inList(ids("post_id"))}`).catch(() => []) : [],
      ids("comment_id").length ? rows("comments", `select=id,body,author_name,hidden_at&${inList(ids("comment_id"))}`).catch(() => []) : [],
      ids("review_id").length ? rows("recipe_reviews", `select=id,body,author_name,hidden_at&${inList(ids("review_id"))}`).catch(() => []) : [],
    ]);
    const map = rowsArr => Object.fromEntries(rowsArr.map(x => [x.id, x]));
    const P = map(postRows), C = map(commentRows), R = map(reviewRows);
    const target = r => {
      if (r.post_id) return { type: "post", id: r.post_id, obj: P[r.post_id] };
      if (r.comment_id) return { type: "comment", id: r.comment_id, obj: C[r.comment_id] };
      if (r.review_id) return { type: "review", id: r.review_id, obj: R[r.review_id] };
      return { type: r.target_type || "?", id: null, obj: null };
    };
    $("#view").innerHTML = `<div class="card panel"><div class="panel-h"><h2>Reports</h2>
      <span class="note">${list.length} total</span></div><div class="tw"><table>
      <thead><tr><th>Reported content</th><th>Reason</th><th>When</th><th>Actions</th></tr></thead><tbody>
      ${list.map(r => {
        const t = target(r);
        const body = t.obj ? (t.obj.caption ?? t.obj.body ?? "") : "(deleted)";
        const author = t.obj ? t.obj.author_name : "";
        return `<tr data-rid="${r.id}" data-tt="${t.type}" data-tid="${t.id || ""}">
          <td><span class="pill k-${t.type === "post" ? "photo" : t.type === "review" ? "recipe" : "reel"}">${t.type}</span>
            ${t.obj && t.obj.hidden_at ? '<span class="pill k-photo">hidden</span>' : ""}
            <strong>${esc(author)}</strong><br><span style="color:var(--muted)">${esc((body || "").slice(0, 90)) || "—"}</span></td>
          <td>${esc(r.reason || "—")}${r.note ? `<br><span style="color:var(--muted)">${esc(r.note.slice(0, 60))}</span>` : ""}</td>
          <td class="num" style="color:var(--muted)">${when(r.created_at)}</td>
          <td class="rowacts">
            ${t.id && t.obj ? `<button class="link" data-hide="${t.obj.hidden_at ? "0" : "1"}">${t.obj.hidden_at ? "Unhide" : "Hide"}</button>
            <button class="btn danger" data-del>Delete</button>` : ""}
            <button class="link" data-dismiss>Dismiss</button>
          </td>
        </tr>`;
      }).join("") || `<tr><td colspan="4" class="empty">Nothing has been reported</td></tr>`}
      </tbody></table></div></div>`;

    document.querySelectorAll("[data-dismiss]").forEach(b => b.addEventListener("click", async () => {
      const tr = b.closest("tr"); b.disabled = true;
      try { await adminFn({ action: "delete_report", reportId: tr.dataset.rid }); tr.remove(); }
      catch (e) { alert("Couldn't dismiss: " + e.message); b.disabled = false; }
    }));
    document.querySelectorAll("[data-hide]").forEach(b => b.addEventListener("click", async () => {
      const tr = b.closest("tr"); b.disabled = true;
      try { await adminFn({ action: "hide_content", targetType: tr.dataset.tt, id: tr.dataset.tid, hidden: b.dataset.hide === "1" }); show("reports"); }
      catch (e) { alert("Couldn't update: " + e.message); b.disabled = false; }
    }));
    document.querySelectorAll("[data-del]").forEach(b => b.addEventListener("click", async () => {
      const tr = b.closest("tr");
      if (!confirm("Permanently delete this content? Hiding is reversible; deleting is not.")) return;
      b.disabled = true; b.textContent = "Deleting…";
      try { await adminFn({ action: "delete_content", targetType: tr.dataset.tt, id: tr.dataset.tid }); show("reports"); }
      catch (e) { alert("Couldn't delete: " + e.message); b.disabled = false; b.textContent = "Delete"; }
    }));
  },

  async support() {
    const FILTERS = [["needs_human", "Needs you"], ["human", "With team"], ["ai", "Assistant"], ["closed", "Closed"], ["all", "All"]];
    const REASONS = { customer_asked: "asked for a person", sensitive_topic: "money / legal / security", low_confidence: "assistant unsure",
      ai_unavailable: "AI unavailable", rate_limited: "too many messages", assistant_disabled: "assistant off" };
    let filter = sessionStorage.getItem("gs_support_filter") || "needs_human";
    let openId = null;

    const render = async () => {
      const q = filter === "all" ? "" : `&status=eq.${filter}`;
      const convs = await rows("support_conversations",
        `select=id,app_id,user_id,status,handoff_reason,subject,last_message_at${q}&order=last_message_at.desc&limit=100`);
      const ids = [...new Set(convs.map(c => c.user_id))];
      const people = ids.length ? await rows("profiles", `select=id,display_name&id=in.(${ids.join(",")})`).catch(() => []) : [];
      const names = Object.fromEntries(people.map(p => [p.id, p.display_name]));
      if (!openId && convs.length) openId = convs[0].id;

      $("#view").innerHTML = `
        <div class="toolbar">${FILTERS.map(([k, l]) => `<button class="fbtn" data-f="${k}" aria-pressed="${k === filter}">${l}</button>`).join("")}
          <div style="flex:1"></div><span class="note" style="color:var(--muted);font-size:12.5px">Refreshes every 10s</span></div>
        <div class="inbox">
          <div class="card list">${convs.map(c => `
            <button class="conv" data-id="${c.id}" aria-current="${c.id === openId}">
              <div class="t"><span>${esc(names[c.user_id] || "Customer")}</span><span class="st st-${c.status}">${c.status.replace("_", " ")}</span>
                <span style="margin-left:auto;color:var(--muted);font-weight:600;font-size:12px">${ago(c.last_message_at)}</span></div>
              <div class="s">${esc(c.subject || "—")}</div>
              ${c.status === "needs_human" && c.handoff_reason ? `<div class="s" style="color:var(--stop)">${esc(REASONS[c.handoff_reason] || c.handoff_reason)}</div>` : ""}
            </button>`).join("") || `<div class="empty">No conversations here</div>`}
          </div>
          <div class="card" id="pane">${openId ? `<div class="spin">Loading…</div>` : `<div class="empty">Select a conversation</div>`}</div>
        </div>`;

      document.querySelectorAll("[data-f]").forEach(b => b.addEventListener("click", () => {
        filter = b.dataset.f; openId = null; sessionStorage.setItem("gs_support_filter", filter); render();
      }));
      document.querySelectorAll(".conv").forEach(b => b.addEventListener("click", () => {
        openId = b.dataset.id;
        document.querySelectorAll(".conv").forEach(x => x.setAttribute("aria-current", String(x === b)));
        renderPane(convs.find(c => c.id === openId), names);
      }));
      if (openId) renderPane(convs.find(c => c.id === openId), names);
    };

    const renderPane = async (conv, names, keepDraft = false) => {
      const pane = $("#pane");
      if (!conv) { pane.innerHTML = `<div class="empty">Select a conversation</div>`; return; }
      const draft = keepDraft ? ($("#reply")?.value || "") : "";
      const msgs = await rows("support_messages",
        `select=sender,author_name,body,created_at,model,fallback&conversation_id=eq.${conv.id}&order=created_at.asc&limit=500`);
      const who = m => m.sender === "user" ? esc(names[conv.user_id] || "Customer")
        : m.sender === "agent" ? esc(m.author_name || "Team")
        : m.sender === "ai" ? `Assistant${m.model ? ` · ${esc(m.model)}${m.fallback ? " (backup)" : ""}` : ""}` : "System";
      const canAct = can("SUPPORT");
      pane.innerHTML = `
        <div class="panel-h" style="padding:14px 16px;margin:0;border-bottom:1px solid var(--line)">
          <h2 style="font-size:15px">${esc(names[conv.user_id] || "Customer")} <span class="st st-${conv.status}">${conv.status.replace("_", " ")}</span></h2>
          <span class="note">${esc(conv.app_id)}</span>
          ${canAct ? `<div style="margin-left:auto;display:flex;gap:8px">
            ${conv.status !== "ai" && conv.status !== "closed" ? `<button class="btn ghost" data-st="ai" title="The assistant answers the next message">Hand back to assistant</button>` : ""}
            ${conv.status !== "closed" ? `<button class="btn ghost" data-st="closed">Close</button>` : ""}
          </div>` : ""}
        </div>
        <div class="thread" id="thread">${msgs.map(m => `
          <div class="bub ${m.sender === "system" ? "ai" : m.sender}"><div class="who">${who(m)} · ${ago(m.created_at)}</div>${esc(m.body)}</div>`).join("")}
        </div>
        ${canAct ? `<div class="composer">
          <textarea class="search" id="reply" placeholder="Reply to the customer — they see it in the app with your name">${esc(draft)}</textarea>
          <button class="btn" id="send">Send</button></div>` : ""}`;
      const th = $("#thread"); th.scrollTop = th.scrollHeight;

      pane.querySelectorAll("[data-st]").forEach(b => b.addEventListener("click", async () => {
        b.disabled = true;
        try { await adminFn({ action: "support_set_status", conversationId: conv.id, status: b.dataset.st }); refreshSupportBadge(); render(); }
        catch (e) { alert("Couldn't update: " + e.message); b.disabled = false; }
      }));
      $("#send")?.addEventListener("click", async () => {
        const text = $("#reply").value.trim(); if (!text) return;
        const s = $("#send"); s.disabled = true; s.textContent = "Sending…";
        try {
          await adminFn({ action: "support_reply", conversationId: conv.id, text });
          conv.status = "human"; refreshSupportBadge(); renderPane(conv, names);
        } catch (e) { alert("Couldn't send: " + e.message); s.disabled = false; s.textContent = "Send"; }
      });
    };

    await render();
    // New customer messages show up without a reload; an unsent reply is kept.
    viewTimer = setInterval(async () => {
      if (document.activeElement?.id === "reply" && $("#reply").value) return;
      try {
        const conv = openId && (await rows("support_conversations", `select=id,app_id,user_id,status,handoff_reason,subject,last_message_at&id=eq.${openId}`))[0];
        if (conv) {
          const p = await rows("profiles", `select=id,display_name&id=eq.${conv.user_id}`).catch(() => []);
          renderPane(conv, Object.fromEntries(p.map(x => [x.id, x.display_name])), true);
        }
      } catch { /* next tick */ }
    }, 10_000);
  },

  async knowledge() {
    const [apps, arts] = await Promise.all([
      rows("support_apps", "select=*&order=id.asc"),
      rows("support_articles", "select=id,app_id,title,body,active,embedding_model,updated_at&order=updated_at.desc"),
    ]);
    const app = apps[0];
    if (!app) { $("#view").innerHTML = `<div class="card panel"><div class="empty">No assistant configured yet</div></div>`; return; }
    const admin = can("ADMIN");

    $("#view").innerHTML = `
      <div class="card panel"><div class="panel-h"><h2>${esc(app.name)} assistant</h2>
        <span class="note">${app.enabled ? '<span class="pill p-pro">on</span>' : '<span class="pill p-free">off — every message goes to the team</span>'} · model ${esc(app.chat_model)}</span>
        ${admin ? `<div style="margin-left:auto"><button class="btn ghost" id="editApp">Edit behaviour</button></div>` : ""}</div>
        <div class="kv"><div class="k">When handing over</div><div class="v">${esc(app.handoff_message)}</div></div>
      </div>
      <div class="toolbar" style="margin-top:14px"><div style="flex:1"></div>${can("SUPPORT") ? `<button class="btn" id="addArt">+ New article</button>` : ""}</div>
      <div class="card panel"><div class="panel-h"><h2>Knowledge articles</h2><span class="note">${arts.length} · the assistant answers from these</span></div>
      <div class="tw"><table><thead><tr><th>Article</th><th>Status</th><th>Updated</th><th>Actions</th></tr></thead><tbody>
      ${arts.map(a => `<tr data-id="${a.id}">
        <td><strong>${esc(a.title)}</strong><br><span style="color:var(--muted)">${esc(a.body.slice(0, 110))}</span></td>
        <td>${a.active ? '<span class="pill p-pro">live</span>' : '<span class="pill p-free">off</span>'}
          ${a.active && !a.embedding_model ? '<br><span style="color:var(--muted);font-size:12px">indexes on next question</span>' : ""}</td>
        <td class="num" style="color:var(--muted)">${when(a.updated_at)}</td>
        <td class="rowacts">${can("SUPPORT") ? `<button class="link" data-edit>Edit</button>` : ""}${admin ? `<button class="btn danger" data-del>Delete</button>` : ""}</td>
      </tr>`).join("") || `<tr><td colspan="4" class="empty">No articles yet</td></tr>`}
      </tbody></table></div></div>`;

    const modal = (html, onSave) => {
      const bg = document.createElement("div"); bg.className = "modal-bg";
      bg.innerHTML = `<div class="modal">${html}<div class="foot"><button class="btn ghost" data-cancel>Cancel</button><button class="btn" data-save>Save</button></div></div>`;
      document.body.appendChild(bg);
      const close = () => bg.remove();
      bg.addEventListener("click", e => { if (e.target === bg) close(); });
      bg.querySelector("[data-cancel]").addEventListener("click", close);
      bg.querySelector("[data-save]").addEventListener("click", async () => {
        const s = bg.querySelector("[data-save]"); s.disabled = true; s.textContent = "Saving…";
        try { await onSave(bg); close(); show("knowledge"); }
        catch (e) { alert("Couldn't save: " + e.message); s.disabled = false; s.textContent = "Save"; }
      });
    };

    const editArticle = a => modal(`<h3>${a ? "Edit" : "New"} article</h3>
      <div class="fld"><label>Question or title</label><input class="search" id="at" style="width:100%" maxlength="200" value="${esc(a?.title || "")}"></div>
      <div class="fld"><label>Answer — facts and steps the assistant may use</label><textarea class="search" id="ab" style="width:100%;min-height:180px" maxlength="8000">${esc(a?.body || "")}</textarea></div>
      <label style="display:flex;gap:8px;align-items:center;text-transform:none;letter-spacing:0;font-size:13px"><input type="checkbox" id="aa" ${a?.active === false ? "" : "checked"}> Live (the assistant can use it)</label>`,
      bg => {
        const title = bg.querySelector("#at").value.trim(), body = bg.querySelector("#ab").value.trim();
        if (!title || !body) throw new Error("Title and answer are both required");
        return adminFn({ action: "support_article_upsert", id: a?.id, app_id: app.id, title, body, active: bg.querySelector("#aa").checked });
      });

    $("#addArt")?.addEventListener("click", () => editArticle(null));
    document.querySelectorAll("[data-edit]").forEach(b => b.addEventListener("click", () =>
      editArticle(arts.find(a => a.id === b.closest("tr").dataset.id))));
    document.querySelectorAll("[data-del]").forEach(b => b.addEventListener("click", async () => {
      if (!confirm("Delete this article? The assistant will stop using it.")) return;
      b.disabled = true;
      try { await adminFn({ action: "support_article_delete", id: b.closest("tr").dataset.id }); show("knowledge"); }
      catch (e) { alert("Couldn't delete: " + e.message); b.disabled = false; }
    }));
    $("#editApp")?.addEventListener("click", () => modal(`<h3>Assistant behaviour</h3>
      <div class="fld"><label>Instructions — who it is, what the app does, tone, rules</label><textarea class="search" id="ai" style="width:100%;min-height:240px">${esc(app.instructions)}</textarea></div>
      <div class="fld"><label>Message when handing over to the team</label><input class="search" id="ah" style="width:100%" maxlength="500" value="${esc(app.handoff_message)}"></div>
      <div class="fld"><label>Model on the VPS</label><input class="search" id="am" style="width:100%" value="${esc(app.chat_model)}"></div>
      <label style="display:flex;gap:8px;align-items:center;text-transform:none;letter-spacing:0;font-size:13px"><input type="checkbox" id="ae" ${app.enabled ? "checked" : ""}> Assistant on (off sends every message straight to the team)</label>`,
      bg => adminFn({ action: "support_app_update", id: app.id,
        instructions: bg.querySelector("#ai").value, handoff_message: bg.querySelector("#ah").value,
        chat_model: bg.querySelector("#am").value.trim(), enabled: bg.querySelector("#ae").checked })));
  },

  async catalog() {
    let term = "";
    const load = async () => {
      const q = term
        ? `select=id,title,cuisine,category,image_url,featured,published&title=ilike.*${encodeURIComponent(term)}*&order=title.asc&limit=100`
        : "select=id,title,cuisine,category,image_url,featured,published&order=title.asc&limit=100";
      return rows("catalog_recipes", q);
    };
    const render = async () => {
      const list = await load();
      $("#view").innerHTML = `
        <div class="toolbar">
          <input class="search" id="cs" placeholder="Search recipes by title…" value="${esc(term)}">
          <button class="btn" id="addRecipe">+ Add recipe</button>
        </div>
        <div class="card panel"><div class="panel-h"><h2>Discover catalog</h2><span class="note">${list.length}${term ? " matches" : " shown"}</span></div>
        <div class="tw"><table>
        <thead><tr><th>Recipe</th><th>Cuisine</th><th>Featured</th><th>Published</th><th>Actions</th></tr></thead><tbody>
        ${list.map(r => `<tr data-id="${r.id}">
          <td><strong>${esc(r.title)}</strong></td>
          <td style="color:var(--muted)">${esc(r.cuisine || "—")}</td>
          <td><button class="fbtn" data-flag="featured" aria-pressed="${!!r.featured}">${r.featured ? "Yes" : "No"}</button></td>
          <td><button class="fbtn" data-flag="published" aria-pressed="${r.published !== false}">${r.published !== false ? "Yes" : "No"}</button></td>
          <td class="rowacts">
            <button class="link" data-edit>Edit</button>
            <button class="btn danger" data-del>Delete</button>
          </td>
        </tr>`).join("") || `<tr><td colspan="5" class="empty">No recipes</td></tr>`}
        </tbody></table></div></div>`;

      const cs = $("#cs");
      cs.addEventListener("keydown", e => { if (e.key === "Enter") { term = cs.value.trim(); render(); } });
      $("#addRecipe").addEventListener("click", () => editRecipe(null));
      document.querySelectorAll("[data-flag]").forEach(b => b.addEventListener("click", async () => {
        const tr = b.closest("tr"), flag = b.dataset.flag, next = b.getAttribute("aria-pressed") !== "true";
        b.disabled = true;
        try { await adminFn({ action: "catalog_set_flags", id: tr.dataset.id, [flag]: next }); b.setAttribute("aria-pressed", String(next)); b.textContent = next ? "Yes" : "No"; }
        catch (e) { alert("Couldn't update: " + e.message); }
        finally { b.disabled = false; }
      }));
      document.querySelectorAll("[data-edit]").forEach(b => b.addEventListener("click", async () => {
        const id = b.closest("tr").dataset.id;
        const full = await rows("catalog_recipes", `id=eq.${id}&limit=1`).catch(() => []);
        editRecipe(full[0] || { id });
      }));
      document.querySelectorAll("[data-del]").forEach(b => b.addEventListener("click", async () => {
        const tr = b.closest("tr");
        if (!confirm("Delete this catalog recipe permanently?")) return;
        b.disabled = true; b.textContent = "Deleting…";
        try { await adminFn({ action: "catalog_delete", id: tr.dataset.id }); tr.remove(); }
        catch (e) { alert("Couldn't delete: " + e.message); b.disabled = false; b.textContent = "Delete"; }
      }));
    };
    // Recipe add/edit modal — a focused subset of the columns; jsonb fields kept as-is on edit.
    const editRecipe = (r) => {
      modalForm(r && r.id && r.title ? "Edit recipe" : "Add recipe", [
        { name: "title", label: "Title", value: r?.title || "" },
        { name: "cuisine", label: "Cuisine", value: r?.cuisine || "" },
        { name: "category", label: "Category", value: r?.category || "" },
        { name: "image_url", label: "Image URL", value: r?.image_url || "" },
        { name: "servings", label: "Servings", type: "number", value: r?.servings ?? "" },
        { name: "prep_minutes", label: "Prep (min)", type: "number", value: r?.prep_minutes ?? "" },
        { name: "cook_minutes", label: "Cook (min)", type: "number", value: r?.cook_minutes ?? "" },
        { name: "notes", label: "Notes", value: r?.notes || "" },
      ], async (vals) => {
        const recipe = { ...(r && r.id ? { id: r.id } : {}), ...vals };
        ["servings", "prep_minutes", "cook_minutes"].forEach(k => { if (recipe[k] === "") delete recipe[k]; else recipe[k] = Number(recipe[k]); });
        await adminFn({ action: "catalog_upsert", recipe });
        render();
      });
    };
    render();
  },

  async subs() {
    const list = await rows("app_store_transactions",
      "select=user_id,product_id,plan,environment,expires_at,revoked_at,created_at&order=expires_at.desc&limit=200").catch(() => []);
    $("#view").innerHTML = `<div class="card panel"><div class="panel-h"><h2>Subscriptions</h2>
      <span class="note">${list.length} total</span></div><div class="tw"><table>
      <thead><tr><th>Product</th><th>Plan</th><th>Env</th><th>Expires</th><th>Revoked</th></tr></thead><tbody>
      ${list.map(s => `<tr>
        <td><strong>${esc(s.product_id || "—")}</strong></td>
        <td>${planPill(s.plan)}</td>
        <td style="color:var(--muted)">${esc(s.environment || "—")}</td>
        <td class="num" style="color:var(--muted)">${when(s.expires_at)}</td>
        <td class="num" style="color:${s.revoked_at ? "var(--stop)" : "var(--muted)"}">${s.revoked_at ? when(s.revoked_at) : "—"}</td>
      </tr>`).join("") || `<tr><td colspan="5" class="empty">No subscriptions recorded</td></tr>`}
      </tbody></table></div></div>`;
  },

  async groups() {
    const list = await rows("groups", "select=id,name,slug,emoji,description,member_count,post_count&order=name.asc").catch(() => []);
    $("#view").innerHTML = `
      <div class="toolbar"><div style="flex:1"></div><button class="btn" id="addGroup">+ Add group</button></div>
      <div class="card panel"><div class="panel-h"><h2>Community groups</h2><span class="note">${list.length}</span></div>
      <div class="tw"><table>
      <thead><tr><th>Group</th><th>Slug</th><th>Members</th><th>Posts</th><th>Actions</th></tr></thead><tbody>
      ${list.map(g => `<tr data-id="${g.id}">
        <td>${esc(g.emoji || "")} <strong>${esc(g.name)}</strong><br><span style="color:var(--muted)">${esc((g.description || "").slice(0, 60))}</span></td>
        <td style="color:var(--muted)">${esc(g.slug || "—")}</td>
        <td class="num">${g.member_count ?? 0}</td>
        <td class="num">${g.post_count ?? 0}</td>
        <td class="rowacts"><button class="link" data-edit>Edit</button><button class="btn danger" data-del>Delete</button></td>
      </tr>`).join("") || `<tr><td colspan="5" class="empty">No groups</td></tr>`}
      </tbody></table></div></div>`;

    const edit = g => modalForm(g ? "Edit group" : "Add group", [
      { name: "name", label: "Name", value: g?.name || "" },
      { name: "slug", label: "Slug", value: g?.slug || "" },
      { name: "emoji", label: "Emoji", value: g?.emoji || "" },
      { name: "description", label: "Description", value: g?.description || "" },
    ], async vals => { await adminFn({ action: "group_upsert", ...(g ? { id: g.id } : {}), ...vals }); show("groups"); });

    $("#addGroup").addEventListener("click", () => edit(null));
    document.querySelectorAll("[data-edit]").forEach(b => b.addEventListener("click", () => {
      const g = list.find(x => x.id === b.closest("tr").dataset.id); edit(g);
    }));
    document.querySelectorAll("[data-del]").forEach(b => b.addEventListener("click", async () => {
      const tr = b.closest("tr");
      if (!confirm("Delete this group?")) return;
      b.disabled = true;
      try { await adminFn({ action: "group_delete", id: tr.dataset.id }); tr.remove(); }
      catch (e) { alert("Couldn't delete: " + e.message); b.disabled = false; }
    }));
  },

  async audit() {
    const list = await rows("admin_audit", "select=*&order=created_at.desc&limit=200").catch(() => []);
    $("#view").innerHTML = `<div class="card panel"><div class="panel-h"><h2>Admin actions</h2>
      <span class="note">${list.length} shown</span></div><div class="tw"><table>
      <thead><tr><th>Admin</th><th>Action</th><th>Target</th><th>Detail</th><th>When</th></tr></thead><tbody>
      ${list.map(a => `<tr>
        <td><strong>${esc(a.actor_name || "—")}</strong></td>
        <td><span class="pill k-recipe">${esc(a.action)}</span></td>
        <td style="color:var(--muted)">${esc(a.target_type || "")} ${esc((a.target_id || "").slice(0, 8))}</td>
        <td style="color:var(--muted)">${esc(JSON.stringify(a.detail || {}).slice(0, 60))}</td>
        <td class="num" style="color:var(--muted)">${ago(a.created_at)}</td>
      </tr>`).join("") || `<tr><td colspan="5" class="empty">No admin actions logged yet</td></tr>`}
      </tbody></table></div></div>`;
  },

  async security() {
    if (!can("SUPER_ADMIN")) { $("#view").innerHTML = `<div class="card panel"><div class="empty">Super-admins only.</div></div>`; return; }
    const list = await rows("profiles", "is_admin=eq.true&select=id,display_name,admin_role,created_at&order=created_at.asc");
    const roles = ["READ_ONLY", "SUPPORT", "MODERATOR", "ADMIN", "SUPER_ADMIN"];
    const me = SESSION.userID;
    $("#view").innerHTML = `<div class="card panel"><div class="panel-h"><h2>Administrators</h2>
      <span class="note">${list.length}</span></div><div class="tw"><table>
      <thead><tr><th>Name</th><th>Role</th><th>Since</th><th>Actions</th></tr></thead><tbody>
      ${list.map(p => {
        const role = p.admin_role || "SUPER_ADMIN";
        const self = p.id === me;
        return `<tr data-uid="${p.id}" data-name="${esc(p.display_name || "this admin")}">
          <td><strong>${esc(p.display_name) || "—"}</strong>${self ? ' <span class="pill p-free">you</span>' : ""}</td>
          <td><select class="sel" data-role ${self ? "disabled" : ""}>
            ${roles.map(r => `<option value="${r}" ${r === role ? "selected" : ""}>${r.toLowerCase().replace("_", " ")}</option>`).join("")}
          </select></td>
          <td class="num" style="color:var(--muted)">${when(p.created_at)}</td>
          <td class="rowacts">${self ? "" : `<button class="btn danger" data-revoke>Remove admin</button>`}</td>
        </tr>`;
      }).join("") || `<tr><td colspan="4" class="empty">No administrators</td></tr>`}
      </tbody></table></div></div>`;

    document.querySelectorAll("select[data-role]").forEach(sel => sel.addEventListener("change", async () => {
      const tr = sel.closest("tr"), prev = sel.dataset.prev || sel.value;
      sel.disabled = true;
      try { await adminFn({ action: "set_role", userId: tr.dataset.uid, role: sel.value }); sel.dataset.prev = sel.value; flash(tr, `Role set to ${sel.value}`); }
      catch (e) { alert("Couldn't change role: " + e.message); sel.value = prev; }
      finally { sel.disabled = false; }
    }));
    document.querySelectorAll("[data-revoke]").forEach(b => b.addEventListener("click", async () => {
      const tr = b.closest("tr");
      if (!confirm(`Remove admin access from ${tr.dataset.name}?`)) return;
      b.disabled = true;
      try { await adminFn({ action: "set_role", userId: tr.dataset.uid, role: "" }); show("security"); }
      catch (e) { alert("Couldn't remove: " + e.message); b.disabled = false; }
    }));
  },

  async finance() {
    const days = ovDays;
    const since = new Date(Date.now() - days * 86400000).toISOString();
    const rangeLabel = days === 7 ? "last 7 days" : days === 30 ? "last 30 days" : "last 90 days";
    const [ents, usage, budget, subs] = await Promise.all([
      rows("entitlements", "select=plan").catch(() => []),
      rows("ai_usage", `select=cost_micros,model,action,refunded,created_at&created_at=gte.${since}`).catch(() => []),
      rows("image_search_budget", "select=day,queries&order=day.desc&limit=30").catch(() => []),
      rows("app_store_transactions", "select=product_id,plan,environment,expires_at,revoked_at").catch(() => []),
    ]);
    // Monthly price per plan (from the app's price labels). Revenue is an ESTIMATE from active
    // paid plans — real billing lives in App Store Connect.
    const PRICE = { plus: 9.99, pro: 12.99 };
    const planCount = { plus: 0, pro: 0 };
    ents.forEach(e => { if (e.plan === "plus" || e.plan === "pro") planCount[e.plan]++; });
    const mrr = planCount.plus * PRICE.plus + planCount.pro * PRICE.pro;

    const spendMicros = usage.reduce((s, u) => s + (u.refunded ? 0 : Number(u.cost_micros || 0)), 0);
    const spend = spendMicros / 1e6;
    // Normalise AI spend to a monthly run-rate to compare against MRR.
    const monthlySpend = days ? spend * (30 / days) : spend;
    const profit = mrr - monthlySpend;

    const agg = field => {
      const m = {};
      usage.forEach(u => { if (u.refunded) return; const k = u[field] || "unknown"; m[k] = (m[k] || 0) + Number(u.cost_micros || 0); });
      return Object.entries(m).sort((a, b) => b[1] - a[1]).slice(0, 8);
    };
    const byModel = agg("model"), byAction = agg("action");
    const barBlock = (title, rows) => {
      const max = Math.max(1, ...rows.map(r => r[1]));
      return `<div class="card pad"><div class="cap" style="margin-bottom:16px">${title} <span class="mut">· ${rangeLabel}</span></div>
        <div class="alerts">${rows.map(([k, v]) => `<div class="alert"><div class="top"><span>${esc(k)}</span><span class="r num">${usd(v)}</span></div>
        <div class="track"><span style="width:${Math.round(v / max * 100)}%"></span></div></div>`).join("") || `<div class="empty">No spend in range</div>`}</div></div>`;
    };

    const activeSubs = subs.filter(s => !s.revoked_at && (!s.expires_at || new Date(s.expires_at) > new Date())).length;
    const todayQueries = budget[0]?.queries || 0;
    const tile = (k, v, d = "", cls = "") => `<div class="card tile"><div class="k">${k}</div><div class="v num ${cls}">${v}</div><div class="d">${d}</div></div>`;

    $("#view").innerHTML = `
      <div class="toolbar"><div style="flex:1"></div>
        ${[7, 30, 90].map(d => `<button class="fbtn" data-range="${d}" aria-pressed="${d === days}">${d === 7 ? "1 week" : d === 30 ? "1 month" : "3 months"}</button>`).join("")}
      </div>
      <div class="row tiles">
        ${tile("Est. MRR", "$" + mrr.toFixed(2), `${planCount.plus + planCount.pro} paying members`)}
        ${tile("AI spend", usd(spendMicros), rangeLabel)}
        ${tile("Est. profit / mo", "$" + profit.toFixed(2), "MRR − monthly AI run-rate", profit < 0 ? "delta down" : "delta up")}
        ${tile("App Store subs", activeSubs, activeSubs ? "active bindings" : "none recorded yet")}
      </div>
      <div class="row bottom">
        ${barBlock("AI spend by model", byModel)}
        ${barBlock("AI spend by action", byAction)}
      </div>
      <div class="row bottom">
        <div class="card panel"><div class="panel-h"><h2>Revenue by plan</h2><span class="note">estimate</span></div>
          <div class="tw"><table><thead><tr><th>Plan</th><th>Members</th><th>Price/mo</th><th>Subtotal/mo</th></tr></thead><tbody>
            <tr><td>${planPill("plus")}</td><td class="num">${planCount.plus}</td><td class="num">$${PRICE.plus}</td><td class="num">$${(planCount.plus * PRICE.plus).toFixed(2)}</td></tr>
            <tr><td>${planPill("pro")}</td><td class="num">${planCount.pro}</td><td class="num">$${PRICE.pro}</td><td class="num">$${(planCount.pro * PRICE.pro).toFixed(2)}</td></tr>
          </tbody></table></div>
        </div>
        <div class="card pad"><div class="cap" style="margin-bottom:16px">API / service usage</div>
          <div class="kv">
            <div><div class="k">AI actions</div><div class="v num">${usage.length}</div></div>
            <div><div class="k">Image searches today</div><div class="v num">${todayQueries}</div></div>
            <div><div class="k">Avg cost / action</div><div class="v num">${usage.length ? usd(spendMicros / usage.length) : "$0.00"}</div></div>
          </div>
          <p style="color:var(--muted);font-size:12px;margin-top:14px">Revenue is estimated from active paid plans × list price; real billing is in App Store Connect. AI spend is metered exactly from ai_usage.</p>
        </div>
      </div>`;
    document.querySelectorAll("[data-range]").forEach(b => b.addEventListener("click", () => { ovDays = Number(b.dataset.range); show("finance"); }));
  },

  async notifs() {
    const list = await rows("broadcasts", "select=title,body,kind,created_at&order=created_at.desc&limit=50").catch(() => []);
    $("#view").innerHTML = `
      <div class="card pad" style="margin-bottom:14px">
        <div class="cap" style="margin-bottom:12px">New broadcast <span class="mut">· shown in-app to signed-in users</span></div>
        <div class="fld"><label>Title</label><input class="search" id="bt" style="width:100%"></div>
        <div class="fld"><label>Body</label><input class="search" id="bb" style="width:100%"></div>
        <div class="fld"><label>Type</label><select class="sel" id="bk"><option>announcement</option><option>promo</option><option>alert</option></select></div>
        <div class="foot" style="display:flex;justify-content:flex-end"><button class="btn" id="bsend">Broadcast</button></div>
      </div>
      <div class="card panel"><div class="panel-h"><h2>Recent broadcasts</h2><span class="note">${list.length}</span></div>
      <div class="tw"><table><thead><tr><th>Title</th><th>Type</th><th>When</th></tr></thead>
      <tbody>${list.map(x => `<tr><td><strong>${esc(x.title)}</strong><br><span style="color:var(--muted)">${esc((x.body || "").slice(0, 80))}</span></td>
        <td><span class="pill k-recipe">${esc(x.kind)}</span></td><td class="num" style="color:var(--muted)">${ago(x.created_at)}</td></tr>`).join("")
        || `<tr><td colspan="3" class="empty">No broadcasts yet</td></tr>`}</tbody></table></div></div>`;
    $("#bsend").addEventListener("click", async () => {
      const title = $("#bt").value.trim(); if (!title) { alert("Title required"); return; }
      const b = $("#bsend"); b.disabled = true; b.textContent = "Sending…";
      try { await adminFn({ action: "broadcast_create", title, body: $("#bb").value, kind: $("#bk").value }); show("notifs"); }
      catch (e) { alert("Couldn't broadcast: " + e.message); b.disabled = false; b.textContent = "Broadcast"; }
    });
  },

  async config() {
    const list = await rows("app_config", "select=key,value,is_public,version,updated_at&order=key.asc").catch(() => []);
    $("#view").innerHTML = `
      <div class="toolbar"><div style="flex:1"></div><button class="btn" id="addcfg">+ New config key</button></div>
      <div class="card panel"><div class="panel-h"><h2>Config documents</h2><span class="note">${list.length}</span></div>
      <div class="tw"><table><thead><tr><th>Key</th><th>Public</th><th>Version</th><th>Updated</th><th>Actions</th></tr></thead>
      <tbody>${list.map(c => `<tr data-key="${esc(c.key)}">
        <td><strong>${esc(c.key)}</strong><br><span style="color:var(--muted)">${esc(JSON.stringify(c.value).slice(0, 70))}</span></td>
        <td>${c.is_public ? '<span class="pill p-pro">public</span>' : '<span class="pill p-free">private</span>'}</td>
        <td class="num">${c.version}</td>
        <td class="num" style="color:var(--muted)">${when(c.updated_at)}</td>
        <td class="rowacts"><button class="link" data-edit>Edit</button><button class="link" data-hist>History</button></td>
      </tr>`).join("") || `<tr><td colspan="5" class="empty">No config yet</td></tr>`}</tbody></table></div></div>`;

    const editCfg = (c) => {
      const bg = document.createElement("div"); bg.className = "modal-bg";
      bg.innerHTML = `<div class="modal"><h3>${c ? "Edit" : "New"} config</h3>
        <div class="fld"><label>Key</label><input class="search" id="ck" style="width:100%" value="${esc(c?.key || "")}" ${c ? "disabled" : ""}></div>
        <div class="fld"><label>Value (JSON)</label><textarea class="search" id="cv" style="width:100%;min-height:140px;font-family:var(--mono)">${esc(JSON.stringify(c?.value ?? {}, null, 2))}</textarea></div>
        <label style="display:flex;gap:8px;align-items:center;text-transform:none;letter-spacing:0;font-size:13px"><input type="checkbox" id="cp" ${c?.is_public ? "checked" : ""}> Public (readable by the app)</label>
        <div class="foot"><button class="btn ghost" data-cancel>Cancel</button><button class="btn" data-save>Save</button></div></div>`;
      document.body.appendChild(bg);
      const close = () => bg.remove();
      bg.addEventListener("click", e => { if (e.target === bg) close(); });
      bg.querySelector("[data-cancel]").addEventListener("click", close);
      bg.querySelector("[data-save]").addEventListener("click", async () => {
        let value; try { value = JSON.parse($("#cv").value); } catch { alert("Value must be valid JSON"); return; }
        const key = $("#ck").value.trim(); if (!key) { alert("Key required"); return; }
        const s = bg.querySelector("[data-save]"); s.disabled = true; s.textContent = "Saving…";
        try { await adminFn({ action: "config_upsert", key, value, is_public: $("#cp").checked }); close(); show("config"); }
        catch (e) { alert("Couldn't save: " + e.message); s.disabled = false; s.textContent = "Save"; }
      });
    };
    $("#addcfg").addEventListener("click", () => editCfg(null));
    document.querySelectorAll("[data-edit]").forEach(b => b.addEventListener("click", () => {
      editCfg(list.find(c => c.key === b.closest("tr").dataset.key));
    }));
    document.querySelectorAll("[data-hist]").forEach(b => b.addEventListener("click", async () => {
      const key = b.closest("tr").dataset.key;
      const hist = await rows("app_config_history", `config_key=eq.${encodeURIComponent(key)}&select=version,value,created_at&order=version.desc&limit=20`).catch(() => []);
      const bg = document.createElement("div"); bg.className = "modal-bg";
      bg.innerHTML = `<div class="modal"><h3>${esc(key)} — history</h3>
        ${hist.map(h => `<div class="fld" style="display:flex;justify-content:space-between;align-items:center;gap:10px">
          <span>v${h.version} · <span style="color:var(--muted)">${when(h.created_at)}</span></span>
          <button class="btn ghost" data-rb="${h.version}">Roll back</button></div>`).join("") || `<div class="empty">No prior versions</div>`}
        <div class="foot"><button class="btn ghost" data-cancel>Close</button></div></div>`;
      document.body.appendChild(bg);
      bg.addEventListener("click", e => { if (e.target === bg) bg.remove(); });
      bg.querySelector("[data-cancel]").addEventListener("click", () => bg.remove());
      bg.querySelectorAll("[data-rb]").forEach(r => r.addEventListener("click", async () => {
        if (!confirm(`Roll ${key} back to v${r.dataset.rb}?`)) return;
        try { await adminFn({ action: "config_rollback", key, version: Number(r.dataset.rb) }); bg.remove(); show("config"); }
        catch (e) { alert("Couldn't roll back: " + e.message); }
      }));
    }));
  },

  async maint() {
    const rowsM = await rows("maintenance_state", "select=enabled,message,min_build&limit=1").catch(() => []);
    const m = rowsM[0] || { enabled: false, message: "", min_build: 0 };
    $("#view").innerHTML = `<div class="card pad" style="max-width:560px">
      <div class="cap" style="margin-bottom:4px">Maintenance mode</div>
      <p style="color:var(--muted);font-size:13px;margin:0 0 16px">When enabled, the app's status check reports maintenance and shows your message. Admins bypass it.</p>
      <label style="display:flex;gap:10px;align-items:center;text-transform:none;letter-spacing:0;font-size:14px;font-weight:800;margin-bottom:14px">
        <input type="checkbox" id="men" ${m.enabled ? "checked" : ""}> Maintenance enabled</label>
      <div class="fld"><label>Message</label><input class="search" id="mmsg" style="width:100%" value="${esc(m.message || "")}" placeholder="We'll be back shortly…"></div>
      <div class="fld"><label>Minimum build (force update below)</label><input class="search" id="mmin" type="number" style="width:100%" value="${m.min_build || 0}"></div>
      <div class="foot" style="display:flex;justify-content:flex-end"><button class="btn" id="msave">Save</button></div>
      ${m.enabled ? '<div class="delta down" style="margin-top:10px">⚠ The app is currently in maintenance.</div>' : ""}
    </div>`;
    $("#msave").addEventListener("click", async () => {
      const b = $("#msave"); b.disabled = true; b.textContent = "Saving…";
      try { await adminFn({ action: "maintenance_set", enabled: $("#men").checked, message: $("#mmsg").value, min_build: Number($("#mmin").value) || 0 }); show("maint"); }
      catch (e) { alert("Couldn't save: " + e.message); b.disabled = false; b.textContent = "Save"; }
    });
  },
};

// A small modal form. fields: [{name,label,type?,value?}]. Calls onSave(values) then closes.
function modalForm(title, fields, onSave) {
  const bg = document.createElement("div");
  bg.className = "modal-bg";
  bg.innerHTML = `<div class="modal"><h3>${esc(title)}</h3>
    ${fields.map(f => `<div class="fld"><label>${esc(f.label)}</label>
      <input class="search" data-n="${esc(f.name)}" type="${f.type || "text"}" value="${esc(f.value ?? "")}" style="width:100%"></div>`).join("")}
    <div class="foot"><button class="btn ghost" data-cancel>Cancel</button><button class="btn" data-save>Save</button></div></div>`;
  document.body.appendChild(bg);
  const close = () => bg.remove();
  bg.addEventListener("click", e => { if (e.target === bg) close(); });
  bg.querySelector("[data-cancel]").addEventListener("click", close);
  bg.querySelector("[data-save]").addEventListener("click", async () => {
    const vals = {};
    bg.querySelectorAll("[data-n]").forEach(i => { vals[i.dataset.n] = i.value; });
    const save = bg.querySelector("[data-save]"); save.disabled = true; save.textContent = "Saving…";
    try { await onSave(vals); close(); }
    catch (e) { alert("Couldn't save: " + e.message); save.disabled = false; save.textContent = "Save"; }
  });
}

// Typed-confirmation modal for irreversible actions. The operator must type `phrase` exactly
// (mirrors the account-delete edge function's confirm token). Resolves true on confirm.
function confirmTyped({ title, body, phrase = "DELETE", danger = "Delete" }) {
  return new Promise(resolve => {
    const bg = document.createElement("div");
    bg.className = "modal-bg";
    bg.innerHTML = `<div class="modal"><h3>${esc(title)}</h3>
      <p style="color:var(--muted);font-size:13.5px;margin:0 0 12px">${esc(body || "")}</p>
      <div class="fld"><label>Type <b>${esc(phrase)}</b> to confirm</label>
        <input class="search" id="cfx" style="width:100%" autocomplete="off"></div>
      <div class="foot"><button class="btn ghost" data-cancel>Cancel</button>
        <button class="btn danger" data-ok disabled>${esc(danger)}</button></div></div>`;
    document.body.appendChild(bg);
    const inp = bg.querySelector("#cfx"), ok = bg.querySelector("[data-ok]");
    const close = v => { bg.remove(); resolve(v); };
    inp.addEventListener("input", () => { ok.disabled = inp.value !== phrase; });
    inp.focus();
    bg.addEventListener("click", e => { if (e.target === bg) close(false); });
    bg.querySelector("[data-cancel]").addEventListener("click", () => close(false));
    ok.addEventListener("click", () => close(true));
  });
}

// Build a CSV and trigger a download. columns = [{key,label}] or array of keys.
function exportCSV(filename, rows, columns) {
  const cols = columns.map(c => typeof c === "string" ? { key: c, label: c } : c);
  const cell = v => {
    const s = v == null ? "" : typeof v === "object" ? JSON.stringify(v) : String(v);
    return /[",\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
  };
  const lines = [cols.map(c => cell(c.label)).join(",")]
    .concat(rows.map(r => cols.map(c => cell(r[c.key])).join(",")));
  const blob = new Blob([lines.join("\n")], { type: "text/csv;charset=utf-8" });
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = filename;
  document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(a.href), 2000);
}

// Per-user detail: plan/quota levers, their posts, AI usage and subscription.
async function openUserDetail(uid, name) {
  $("#title").textContent = name || "Member";
  $("#subtitle").textContent = "Member detail";
  $("#view").innerHTML = `<div class="spin">Loading…</div>`;
  const [ent, posts, usage, subs, prof] = await Promise.all([
    rows("entitlements", `user_id=eq.${uid}&select=plan,used,top_up,trial_until,period&limit=1`).catch(() => []),
    rows("posts", `author_id=eq.${uid}&select=id,caption,kind,like_count,hidden_at,created_at&order=created_at.desc&limit=50`).catch(() => []),
    rows("ai_usage", `user_id=eq.${uid}&select=action,model,cost_micros,refunded,created_at&order=created_at.desc&limit=20`).catch(() => []),
    rows("app_store_transactions", `user_id=eq.${uid}&select=product_id,plan,environment,expires_at,revoked_at&order=expires_at.desc&limit=5`).catch(() => []),
    rows("profiles", `id=eq.${uid}&select=display_name,is_admin,created_at&limit=1`).catch(() => []),
  ]);
  const e = ent[0] || {}, p = prof[0] || {};
  const spend = usage.reduce((s, u) => s + (u.refunded ? 0 : Number(u.cost_micros || 0)), 0);
  const info = (k, v) => `<div><div class="k">${k}</div><div class="v">${v}</div></div>`;
  $("#view").innerHTML = `
    <button class="link" id="backUsers">← Back to members</button>
    <div class="card pad" style="margin-top:12px">
      <div class="cap">${esc(p.display_name || name)} ${p.is_admin ? '<span class="pill p-admin">admin</span>' : ""}</div>
      <div class="kv" style="margin-top:14px">
        ${info("Plan", planPill(e.plan))}
        ${info("Used this period", `<span class="num">${e.used ?? 0}</span>`)}
        ${info("Top-up", `<span class="num">${e.top_up ?? 0}</span>`)}
        ${info("Trial", e.trial_until ? when(e.trial_until) : "—")}
        ${info("Joined", when(p.created_at))}
      </div>
      <div class="rowacts" style="justify-content:flex-start;flex-wrap:wrap;margin-top:16px;gap:8px">
        <button class="btn ghost" data-act="top10">+10 actions</button>
        <button class="btn ghost" data-act="top50">+50 actions</button>
        <button class="btn ghost" data-act="reset">Reset quota</button>
        <button class="btn ghost" data-act="trial7">Trial 7d</button>
        <button class="btn ghost" data-act="trial30">Trial 30d</button>
        <button class="btn ghost" data-act="trial0">Clear trial</button>
      </div>
    </div>

    <div class="row bottom" style="margin-top:14px">
      <div class="card panel">
        <div class="panel-h"><h2>Their posts</h2><span class="note">${posts.length}</span></div>
        <div class="tw"><table><thead><tr><th>Caption</th><th>Type</th><th>♥</th><th>When</th></tr></thead>
        <tbody>${posts.map(x => `<tr>
          <td>${esc((x.caption || "").slice(0, 50)) || "—"} ${x.hidden_at ? '<span class="pill k-photo">hidden</span>' : ""}</td>
          <td><span class="pill k-${esc(x.kind || "photo")}">${esc(x.kind || "post")}</span></td>
          <td class="num">${x.like_count ?? 0}</td><td class="num" style="color:var(--muted)">${when(x.created_at)}</td>
        </tr>`).join("") || `<tr><td colspan="4" class="empty">No posts</td></tr>`}</tbody></table></div>
      </div>
      <div class="card panel">
        <div class="panel-h"><h2>AI usage</h2><span class="note">${usd(spend)} shown</span></div>
        <div class="tw"><table><thead><tr><th>Action</th><th>Model</th><th>Cost</th><th>When</th></tr></thead>
        <tbody>${usage.map(u => `<tr>
          <td>${esc(u.action || "—")}${u.refunded ? ' <span class="pill p-free">refunded</span>' : ""}</td>
          <td style="color:var(--muted)">${esc(u.model || "—")}</td>
          <td class="num">${usd(u.cost_micros)}</td><td class="num" style="color:var(--muted)">${ago(u.created_at)}</td>
        </tr>`).join("") || `<tr><td colspan="4" class="empty">No AI usage</td></tr>`}</tbody></table></div>
      </div>
    </div>

    <div class="card panel" style="margin-top:14px">
      <div class="panel-h"><h2>Subscriptions</h2><span class="note">${subs.length}</span></div>
      <div class="tw"><table><thead><tr><th>Product</th><th>Plan</th><th>Env</th><th>Expires</th><th>Revoked</th></tr></thead>
      <tbody>${subs.map(s => `<tr>
        <td>${esc(s.product_id || "—")}</td><td>${planPill(s.plan)}</td>
        <td style="color:var(--muted)">${esc(s.environment || "—")}</td>
        <td class="num" style="color:var(--muted)">${when(s.expires_at)}</td>
        <td class="num" style="color:var(--muted)">${s.revoked_at ? when(s.revoked_at) : "—"}</td>
      </tr>`).join("") || `<tr><td colspan="5" class="empty">No subscriptions</td></tr>`}</tbody></table></div>
    </div>`;

  $("#backUsers").addEventListener("click", () => show("users"));
  const run = async (payload, label) => {
    try { await adminFn(payload); openUserDetail(uid, name); }
    catch (e) { alert(`${label} failed: ` + e.message); }
  };
  const acts = {
    top10: () => run({ action: "add_top_up", userId: uid, amount: 10 }, "Top-up"),
    top50: () => run({ action: "add_top_up", userId: uid, amount: 50 }, "Top-up"),
    reset: () => run({ action: "reset_quota", userId: uid }, "Reset"),
    trial7: () => run({ action: "set_trial", userId: uid, days: 7 }, "Trial"),
    trial30: () => run({ action: "set_trial", userId: uid, days: 30 }, "Trial"),
    trial0: () => run({ action: "set_trial", userId: uid, days: 0 }, "Trial"),
  };
  document.querySelectorAll("[data-act]").forEach(b =>
    b.addEventListener("click", () => acts[b.dataset.act]()));
}

// resume a session within this tab
const saved = sessionStorage.getItem("gs_admin");
if (saved) { try { SESSION = JSON.parse(saved); enter(); } catch { sessionStorage.removeItem("gs_admin"); } }

