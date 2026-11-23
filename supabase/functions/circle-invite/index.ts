// Where I've Been: "circle-invite" Edge Function
// A circle admin sends a list of emails. For each one this function:
//   1. checks it with circle_invite_prepare() (admin only, limits, already a member, …), as the signed-in admin
//   2. makes a one-click sign-in link: new people get an account created (they choose a password after
//      signing in); people who already have an account get a normal sign-in link
//   3. emails "<name> invited you to <circle>" through Resend
// The invitation itself waits in circle_invites until the person taps Join or Decline in the app.
//
// Secrets (Supabase → Edge Functions → Secrets): RESEND_API_KEY, INVITE_FROM, SITE_URL.
// SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY are provided by Supabase automatically.
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
const esc = (s: string) => s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Use POST" }, 405);
  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const resendKey = Deno.env.get("RESEND_API_KEY");
    const from = Deno.env.get("INVITE_FROM") ?? "Where I've Been <noreply@whereihavebeen.com>";
    const site = (Deno.env.get("SITE_URL") ?? "https://whereihavebeen.com").replace(/\/+$/, "");
    if (!resendKey) return json({ error: "Email isn't set up: add the RESEND_API_KEY secret." }, 500);

    const auth = req.headers.get("Authorization") ?? "";
    const { circle, emails } = await req.json();
    if (!circle || !Array.isArray(emails)) return json({ error: "Send { circle, emails }" }, 400);

    // Checks and bookkeeping run as the signed-in admin, so the database rules apply.
    const asUser = createClient(url, anon, { global: { headers: { Authorization: auth } }, auth: { persistSession: false } });
    const { data: prep, error } = await asUser.rpc("circle_invite_prepare", { circle, emails: emails.map(String).slice(0, 20) });
    if (error) return json({ error: error.message }, 400);

    const admin = createClient(url, service, { auth: { persistSession: false, autoRefreshToken: false } });
    const circleName = String(prep.circle_name ?? "a circle"), inviter = String(prep.inviter ?? "A traveler");
    const results: { email: string; status: string }[] = [];

    for (const r of prep.results as { email: string; status: string }[]) {
      if (r.status !== "invite") { results.push(r); continue; }
      // New person: create the account (no email from Supabase) and get its sign-in link.
      let g = await admin.auth.admin.generateLink({
        type: "invite", email: r.email, options: { redirectTo: site, data: { must_change_password: true } },
      });
      let isNew = true;
      if (g.error) {   // already has an account
        isNew = false;
        g = await admin.auth.admin.generateLink({ type: "magiclink", email: r.email, options: { redirectTo: site } });
      }
      const link = g.data?.properties?.action_link;
      if (g.error || !link) {
        await admin.from("circle_invites").delete().eq("circle_id", circle).eq("email", r.email);
        results.push({ email: r.email, status: "failed" });
        continue;
      }
      const subject = `${inviter} invited you to ${circleName} on Where I've Been`;
      const steps = isNew
        ? "Click the button to sign in. You'll choose a password, then tap Join."
        : "Click the button to sign in, then tap Join.";
      const html = `<!doctype html><html><body style="margin:0;background:#f3f5f8;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;color:#14202e">
<div style="max-width:520px;margin:0 auto;padding:32px 20px">
  <div style="background:#fff;border-radius:16px;padding:28px 26px">
    <p style="font-size:13px;letter-spacing:.08em;text-transform:uppercase;color:#1f56d6;font-weight:700;margin:0 0 10px">Where I've Been</p>
    <h1 style="font-size:22px;line-height:1.3;margin:0 0 14px">${esc(inviter)} invited you to the circle <b>${esc(circleName)}</b></h1>
    <p style="font-size:15px;line-height:1.55;margin:0 0 18px">Where I've Been is a travel map: mark the countries, US states and national parks you've visited. In a circle you compare maps, see who has been where, and can share photos with each other. Only screen names are shown; never email, trips or notes.</p>
    <p style="font-size:15px;line-height:1.55;margin:0 0 22px">${esc(steps)}</p>
    <a href="${esc(link)}" style="display:inline-block;background:#1f56d6;color:#fff;text-decoration:none;font-weight:600;font-size:16px;padding:12px 22px;border-radius:10px">Sign in &amp; see the invitation</a>
    <p style="font-size:12.5px;color:#5b6675;line-height:1.5;margin:22px 0 0">The button works once and expires after a day. If it has expired, go to <a href="${site}" style="color:#1f56d6">${esc(site.replace(/^https?:\/\//, ""))}</a>${isNew ? " and choose Forgot password? with this email address" : " and sign in"}; the invitation will be waiting. If you weren't expecting this, you can ignore it.</p>
  </div>
</div></body></html>`;
      const text = `${inviter} invited you to the circle "${circleName}" on Where I've Been.\n\n${steps}\n\n${link}\n\nThe link works once and expires after a day. If it has expired, go to ${site}${isNew ? " and choose Forgot password? with this email address" : " and sign in"}; the invitation will be waiting.`;
      const sent = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: { Authorization: `Bearer ${resendKey}`, "Content-Type": "application/json" },
        body: JSON.stringify({ from, to: [r.email], subject, html, text }),
      });
      if (!sent.ok) {
        console.error("Resend failed", r.email, sent.status, await sent.text());
        await admin.from("circle_invites").delete().eq("circle_id", circle).eq("email", r.email);
        results.push({ email: r.email, status: "failed" });
      } else {
        results.push({ email: r.email, status: "sent" });
      }
    }
    return json({ circle_name: circleName, results });
  } catch (e) {
    console.error(e);
    return json({ error: String((e as Error)?.message ?? e) }, 500);
  }
});
