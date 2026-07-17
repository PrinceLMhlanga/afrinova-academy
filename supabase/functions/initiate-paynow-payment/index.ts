// supabase/functions/initiate-paynow-payment/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// Simple SHA512 using Web Crypto API
async function sha512Hash(message: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(message);
  const hashBuffer = await crypto.subtle.digest("SHA-512", data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map(b => b.toString(16).padStart(2, '0')).join('').toUpperCase();
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const { reference, amount, mobileNumber, email } = await req.json();

    const PROJECT_URL = Deno.env.get("PROJECT_URL")!;
    const SERVICE_ROLE_KEY = Deno.env.get("SERVICE_ROLE_KEY")!;
    const supabase = createClient(PROJECT_URL, SERVICE_ROLE_KEY);

    // Get PayNow credentials
    // Get PayNow credentials
const { data: settings, error: settingsError } = await supabase
  .from("platform_settings")
  .select("key, value")
  .or("key.eq.paynow_integration_id,key.eq.paynow_integration_key");

if (settingsError) {
  console.error("Settings error:", settingsError);
}

let integrationId = "", integrationKey = "";
for (const row of (settings || [])) {
  if (row.key === "paynow_integration_id") integrationId = row.value;
  if (row.key === "paynow_integration_key") integrationKey = row.value;
}

    if (!integrationId || !integrationKey) {
      return new Response(JSON.stringify({ success: false, error: "PayNow not configured" }), {
        status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const amountStr = Number(amount).toFixed(2);
    const autoEmail = email?.trim() || `${mobileNumber}@mobile.paynow.co.zw`;

    const items: Record<string, string> = {
      id: integrationId,
      reference: reference,
      amount: amountStr,
      authemail: autoEmail,
      additionalinfo: "",
      returnurl: "https://afrinova.academy/payment/complete",
      resulturl: `${PROJECT_URL}/functions/v1/paynow-webhook`,
      status: "Message",
      phone: mobileNumber,
      method: "ecocash",
    };

    // Generate hash
    const concat = Object.entries(items)
      .filter(([k]) => k !== "hash")
      .map(([_, v]) => v)
      .join("");
    items["hash"] = await sha512Hash(concat + integrationKey);

    // Send to PayNow
    const formBody = new URLSearchParams(items).toString();
    
    const paynowResponse = await fetch("https://www.paynow.co.zw/interface/remotetransaction", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: formBody,
    });

    const responseText = await paynowResponse.text();
    console.log("PayNow Response:", responseText);

    // Parse response
    let pollUrl = "", success = false, error = "";
    const lines = responseText.split(/[\r\n&]+/);
    for (const line of lines) {
      if (!line.includes("=")) continue;
      const equalIndex = line.indexOf("=");
      const key = line.substring(0, equalIndex).toLowerCase();
      const value = decodeURIComponent(line.substring(equalIndex + 1));
      if (key === "pollurl") pollUrl = value;
      if (key === "status") success = value.toLowerCase() === "ok";
      if (key === "error") error = value;
    }

    return new Response(JSON.stringify({
      success,
      pollUrl,
      error,
      reference,
    }), { headers: { ...corsHeaders, "Content-Type": "application/json" } });

  } catch (e) {
    return new Response(JSON.stringify({ success: false, error: e.message || "Unknown error" }), {
      status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});