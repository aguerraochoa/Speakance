import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !supabaseServiceRoleKey) {
    return json({ error: "Missing Supabase env vars" }, 500);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const bearerToken = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!bearerToken) {
    return json({ error: "Unauthorized" }, 401);
  }

  const adminClient = createClient(supabaseUrl, supabaseServiceRoleKey);
  const { data: authData, error: authError } = await adminClient.auth.getUser(bearerToken);
  if (authError || !authData.user) {
    return json({ error: authError?.message || "Unauthorized" }, 401);
  }

  const { error: deleteError } = await adminClient.auth.admin.deleteUser(authData.user.id);
  if (deleteError) {
    return json({ error: deleteError.message }, 500);
  }

  return json({ status: "deleted" }, 200);
});

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}
