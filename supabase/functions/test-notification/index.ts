import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

serve(async (req) => {
  try {
    const { userId } = await req.json();
    
    // Check secrets
    const hasServiceAccount = !!Deno.env.get("FCM_SERVICE_ACCOUNT");
    const hasProjectId = !!Deno.env.get("FCM_PROJECT_ID");
    
    // Check devices for user
    const supabaseUrl = Deno.env.get("PROJECT_URL");
    const serviceKey = Deno.env.get("SERVICE_ROLE_KEY");
    
    if (!supabaseUrl || !serviceKey) {
      return new Response(JSON.stringify({ 
        error: "Missing Supabase env vars",
        hasServiceAccount,
        hasProjectId
      }), { status: 500 });
    }
    
    // Fetch user devices
    const { data: devices, error } = await fetch(
      `${supabaseUrl}/rest/v1/user_devices?user_id=eq.${userId}&select=token,platform`,
      {
        headers: {
          'apikey': serviceKey,
          'Authorization': `Bearer ${serviceKey}`
        }
      }
    ).then(r => r.json());
    
    return new Response(JSON.stringify({
      secrets: {
        FCM_SERVICE_ACCOUNT: hasServiceAccount ? "SET" : "MISSING",
        FCM_PROJECT_ID: hasProjectId ? "SET" : "MISSING",
      },
      devices: devices || [],
      error: error || null
    }), { 
      headers: { "Content-Type": "application/json" } 
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" }
    });
  }
});