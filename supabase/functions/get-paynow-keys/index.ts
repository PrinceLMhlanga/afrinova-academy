import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const PROJECT_URL = Deno.env.get("PROJECT_URL");
const SERVICE_ROLE_KEY = Deno.env.get("SERVICE_ROLE_KEY");

serve(async () => {
  if (!PROJECT_URL || !SERVICE_ROLE_KEY) {
    return new Response(JSON.stringify({ error: "Server misconfiguration" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  const supabase = createClient(PROJECT_URL, SERVICE_ROLE_KEY);
  
  const { data: settings } = await supabase
    .from("platform_settings")
    .select("key, value")
    .in("key", ["paynow_integration_id", "paynow_integration_key"]);

  let integrationId = "";
  let integrationKey = "";
  for (const row of settings || []) {
    if (row.key === "paynow_integration_id") integrationId = row.value;
    if (row.key === "paynow_integration_key") integrationKey = row.value;
  }

  return new Response(
    JSON.stringify({ integration_id: integrationId, integration_key: integrationKey }),
    { headers: { "Content-Type": "application/json" } }
  );
});