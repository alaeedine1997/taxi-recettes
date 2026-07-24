// Edge Function : gestion des comptes (create / delete / password)
// Déployée côté Supabase sous le slug "rapid-function".
// Sécurité :
//  - superadmin : crée/supprime/réinitialise n'importe quel compte, dans n'importe quelle flotte.
//  - patron     : crée/supprime/réinitialise uniquement des CHAUFFEURS de SA flotte.
// La clé service_role reste côté serveur.

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
  const jwt = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  if (!jwt) return json({ error: "auth" }, 401);

  const admin = createClient(URL, SERVICE, { auth: { persistSession: false } });

  // Appelant
  const { data: caller, error: cErr } = await admin.auth.getUser(jwt);
  if (cErr || !caller?.user) return json({ error: "auth" }, 401);
  const { data: me } = await admin.from("profiles").select("role, fleet_id, active").eq("id", caller.user.id).single();
  if (!me || !me.active) return json({ error: "forbidden" }, 403);

  let body: any;
  try { body = await req.json(); } catch { return json({ error: "json" }, 400); }
  const action = String(body.action || "create");

  // ---------- CREATE ----------
  if (action === "create") {
    const username = String(body.username || "").trim().toLowerCase();
    const password = String(body.password || "");
    const role = String(body.role || "chauffeur");
    let fleet_id: string | null = body.fleet_id ?? null;

    if (!okUsername(username)) return json({ error: "username_invalide" }, 400);
    if (password.length < 6) return json({ error: "mdp_court" }, 400);
    if (!["patron", "chauffeur"].includes(role)) return json({ error: "role" }, 400);

    if (me.role === "superadmin") { /* peut tout */ }
    else if (me.role === "patron") {
      if (role !== "chauffeur") return json({ error: "patron_role" }, 403);
      fleet_id = me.fleet_id;
      if (!fleet_id) return json({ error: "patron_sans_flotte" }, 403);
    } else return json({ error: "forbidden" }, 403);

    const email = `${username}@${DOMAIN}`;
    const { data: created, error: uErr } = await admin.auth.admin.createUser({ email, password, email_confirm: true });
    if (uErr || !created?.user) {
      if (/already/i.test(String(uErr?.message || ""))) return json({ error: "identifiant_pris" }, 409);
      return json({ error: "create_failed", detail: String(uErr?.message || "") }, 400);
    }
    const display_name = (String(body.display_name || username).replace(/[<>]/g, "").trim().slice(0, 60)) || username;
    const { error: pErr } = await admin.from("profiles").insert({ id: created.user.id, username, display_name, role, fleet_id });
    if (pErr) {
      await admin.auth.admin.deleteUser(created.user.id);
      if (/duplicate|unique/i.test(pErr.message)) return json({ error: "identifiant_pris" }, 409);
      return json({ error: "profile_failed", detail: pErr.message }, 400);
    }
    return json({ ok: true, username, role, fleet_id, login: email });
  }

  // ---------- DELETE / PASSWORD (sur une cible) ----------
  if (action === "delete" || action === "password") {
    const targetId = String(body.id || "");
    if (!targetId) return json({ error: "id" }, 400);

    const { data: target } = await admin.from("profiles").select("id, role, fleet_id").eq("id", targetId).single();
    if (!target) return json({ error: "introuvable" }, 404);

    // Autorisation
    if (me.role === "superadmin") {
      /* peut agir sur tout le monde */
    } else if (me.role === "patron") {
      if (target.role !== "chauffeur" || target.fleet_id !== me.fleet_id) return json({ error: "forbidden" }, 403);
    } else return json({ error: "forbidden" }, 403);

    if (action === "delete") {
      if (targetId === caller.user.id) return json({ error: "self_delete" }, 400); // ne pas se supprimer soi-même
      await admin.from("profiles").delete().eq("id", targetId);
      const { error } = await admin.auth.admin.deleteUser(targetId);
      if (error) return json({ error: "delete_failed", detail: error.message }, 400);
      return json({ ok: true });
    }

    // password
    const pw = String(body.password || "");
    if (pw.length < 6) return json({ error: "mdp_court" }, 400);
    const { error } = await admin.auth.admin.updateUserById(targetId, { password: pw });
    if (error) return json({ error: "password_failed", detail: error.message }, 400);
    return json({ ok: true });
  }

  return json({ error: "action" }, 400);
});
