// Edge Function : create-user
// Crée un compte (auth user + profil) de façon SÉCURISÉE.
// - Seul un superadmin peut créer n'importe quel rôle et assigner n'importe quelle flotte.
// - Un patron ne peut créer que des chauffeurs, et seulement dans SA flotte.
// La clé service_role reste côté serveur (jamais exposée au navigateur).
//
// Déploiement : voir site/supabase/DEPLOY.md

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

const DOMAIN = "taxi.local";
const okUsername = (u: string) => /^[a-z0-9._-]{2,32}$/.test(u);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method" }, 405);

  const URL = Deno.env.get("SUPABASE_URL")!;
  const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const authHeader = req.headers.get("Authorization") || "";
  const jwt = authHeader.replace(/^Bearer\s+/i, "");
  if (!jwt) return json({ error: "auth" }, 401);

  // Client admin (service_role) — côté serveur uniquement
  const admin = createClient(URL, SERVICE, { auth: { persistSession: false } });

  // 1) Identifier l'appelant via son JWT
  const { data: caller, error: cErr } = await admin.auth.getUser(jwt);
  if (cErr || !caller?.user) return json({ error: "auth" }, 401);
  const { data: me } = await admin
    .from("profiles").select("role, fleet_id, active").eq("id", caller.user.id).single();
  if (!me || !me.active) return json({ error: "forbidden" }, 403);

  // 2) Entrée
  let body: any;
  try { body = await req.json(); } catch { return json({ error: "json" }, 400); }
  const username = String(body.username || "").trim().toLowerCase();
  const password = String(body.password || "");
  const role = String(body.role || "chauffeur");
  let fleet_id: string | null = body.fleet_id ?? null;

  if (!okUsername(username)) return json({ error: "username_invalide" }, 400);
  if (password.length < 6) return json({ error: "mdp_court" }, 400);
  if (!["patron", "chauffeur"].includes(role)) return json({ error: "role" }, 400);

  // 3) Autorisations
  if (me.role === "superadmin") {
    // ok, peut tout
  } else if (me.role === "patron") {
    if (role !== "chauffeur") return json({ error: "patron_role" }, 403);
    fleet_id = me.fleet_id; // force sa propre flotte
    if (!fleet_id) return json({ error: "patron_sans_flotte" }, 403);
  } else {
    return json({ error: "forbidden" }, 403);
  }

  const email = `${username}@${DOMAIN}`;

  // 4) Créer l'utilisateur auth (email confirmé, pas d'email réel)
  const { data: created, error: uErr } = await admin.auth.admin.createUser({
    email, password, email_confirm: true,
  });
  if (uErr || !created?.user) {
    const msg = String(uErr?.message || "");
    if (/already/i.test(msg)) return json({ error: "identifiant_pris" }, 409);
    return json({ error: "create_failed", detail: msg }, 400);
  }

  // display_name : champ libre → on le nettoie (pas de < >, longueur bornée)
  const display_name = (String(body.display_name || username).replace(/[<>]/g, "").trim().slice(0, 60)) || username;

  // 5) Créer le profil (rollback de l'auth user si échec)
  const { error: pErr } = await admin.from("profiles").insert({
    id: created.user.id, username, display_name, role, fleet_id,
  });
  if (pErr) {
    const { error: dErr } = await admin.auth.admin.deleteUser(created.user.id);
    if (dErr) console.error("rollback deleteUser a échoué (utilisateur auth orphelin):", created.user.id, dErr.message);
    if (/duplicate|unique/i.test(pErr.message)) return json({ error: "identifiant_pris" }, 409);
    return json({ error: "profile_failed", detail: pErr.message }, 400);
  }

  return json({ ok: true, username, role, fleet_id, login: email });
});
