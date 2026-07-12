import { readdirSync, readFileSync, writeFileSync, existsSync } from "fs";
import { join, dirname } from "path";

const REPO = dirname(dirname(new URL(import.meta.url).pathname));
// Apps dir; overridable for tests so --apply never mutates the tracked tree.
const APPS = process.env.CASAOS_APPS_DIR ?? join(REPO, "apps");
// Committed map path; overridable for tests so runs never clobber the reviewed file.
const MAP_PATH = process.env.CASAOS_MAP_OUT ?? join(REPO, "scripts", "casaos-category-map.json");

const VALID = ["Media","Productivity","Home","Networking","AI","Finance","Social","Developer","Others"] as const;
type Cat = (typeof VALID)[number];

const RULES: [Cat, RegExp][] = [
  ["Home",        /home assistant|smart home|\biot\b|mqtt|zigbee|octoprint|klipper|3d print|sensor/i],
  ["AI",          /\bai\b|\bllm\b|\bgpt\b|ollama|machine learning|\bml\b|neural|chatbot|stable diffusion|inference|local-ai/i],
  ["Finance",     /finance|budget|accounting|expense|ledger|banking|crypto|invoice ninja|wallet/i],
  ["Networking",  /\bvpn\b|proxy|\bdns\b|firewall|router|tunnel|wireguard|nginx|traefik|adguard|pihole|pi-hole|bandwidth|speedtest|network/i],
  ["Developer",   /\bgit\b|gitea|code|ci\/cd|pipeline|registry|\bapi\b|database|\bsql\b|\bide\b|compiler|kubernetes|terraform|docker|webassembly|wasm|filament|laravel/i],
  ["Media",       /media|stream|video|movie|music|audio|photo|plex|jellyfin|emby|podcast|audiobook|gallery|\bimage\b|transcod|minecraft|game/i],
  ["Social",      /\bchat\b|forum|social|message|mastodon|matrix|community|comment|\bblog\b|\bfeed\b/i],
  ["Productivity",/\bnote\b|wiki|document|office|\btask\b|\btodo\b|kanban|project|calendar|bookmark|\bpdf\b|spreadsheet|invoice|\bcrm\b|\berp\b|inventory|planning|reading|storytelling/i],
];

function classify(name: string, desc: string): Cat {
  const hay = `${name} ${desc}`;
  for (const [cat, rx] of RULES) if (rx.test(hay)) return cat;
  return "Others";
}

const apps = readdirSync(APPS, { withFileTypes: true }).filter(d => d.isDirectory()).map(d => d.name).sort();
const out: Record<string, Cat> = {};
for (const app of apps) {
  const p = join(APPS, app, "app.json");
  if (!existsSync(p)) continue;
  try {
    const j = JSON.parse(readFileSync(p, "utf8"));
    const id = j?.metadata?.id ?? app;
    const name = j?.metadata?.name ?? "";
    const desc = j?.metadata?.description ?? "";
    out[id] = classify(name, desc);
  } catch (e) {
    console.warn(`skip ${app}: ${e instanceof Error ? e.message : e}`);
  }
}
const APPLY = process.argv.includes("--apply");

if (!APPLY) {
  writeFileSync(MAP_PATH, JSON.stringify(out, null, 2) + "\n");
  console.log(`Wrote ${Object.keys(out).length} entries to ${MAP_PATH}`);
} else {
  if (!existsSync(MAP_PATH)) throw new Error(`Missing ${MAP_PATH}; run without --apply first, then review.`);
  const map: Record<string, string> = JSON.parse(readFileSync(MAP_PATH, "utf8"));
  const valid = new Set<string>(VALID);
  for (const [id, cat] of Object.entries(map)) {
    if (!valid.has(cat)) throw new Error(`Invalid category "${cat}" for "${id}"`);
  }
  let written = 0;
  for (const app of apps) {
    const p = join(APPS, app, "app.json");
    if (!existsSync(p)) continue;
    const j = JSON.parse(readFileSync(p, "utf8"));
    const id = j?.metadata?.id ?? app;
    const cat = map[id];
    if (!cat) throw new Error(`No mapping for "${id}"`);
    j.compatibility = j.compatibility ?? {};
    j.compatibility.casaos = j.compatibility.casaos ?? {};
    j.compatibility.casaos.category = cat;
    writeFileSync(p, JSON.stringify(j, null, 2) + "\n");
    written++;
  }
  console.log(`Applied casaos.category to ${written} apps`);
}
