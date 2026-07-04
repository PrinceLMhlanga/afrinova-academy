import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const PROJECT_URL = Deno.env.get("PROJECT_URL");
const SERVICE_ROLE_KEY = Deno.env.get("SERVICE_ROLE_KEY");

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (!PROJECT_URL || !SERVICE_ROLE_KEY) {
      return new Response(
        JSON.stringify({ success: false, error: "Server misconfiguration" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const { email, amount, reference, ecocashNumber, teacherId, studentId } = await req.json();

    if (!reference || !teacherId || !studentId || !amount) {
      return new Response(
        JSON.stringify({ success: false, error: "Missing required payment fields" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const supabase = createClient(PROJECT_URL, SERVICE_ROLE_KEY);

    // Get PayNow keys from platform_settings
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

    await supabase.from("payments").insert({
      student_id: studentId,
      teacher_id: teacherId,
      amount: amount,
      gateway_reference: reference,
      status: "pending",
    });

    // Call PayNow API
    const formBody = new URLSearchParams({
      id: integrationId,
      key: integrationKey,
      resulturl: `${PROJECT_URL}/functions/v1/paynow-webhook`,
      returnurl: "https://afrinova.academy/payment/complete",
      reference: reference,
      amount: Number(amount).toFixed(2),
      email: String(email || ""),
      ecocashnumber: String(ecocashNumber || ""),
      authemail: String(email || ""),
    });

    const paynowResponse = await fetch(
      "https://www.paynow.co.zw/interface/remotetransaction",
      {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: formBody.toString(),
      }
    );

    const responseBody = await paynowResponse.text();

    const data: Record<string, string> = {};
    for (const line of responseBody.split("&")) {
      const parts = line.split("=");
      if (parts.length === 2) {
        data[decodeURIComponent(parts[0])] = decodeURIComponent(parts[1]);
      }
    }

    if (data.status === "Ok") {
      return new Response(
        JSON.stringify({
          success: true,
          pollUrl: data.pollurl,
          instructions: data.instructions,
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    return new Response(
      JSON.stringify({ success: false, error: data.error || "Payment failed" }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : "Payment initiation failed";
    return new Response(
      JSON.stringify({ success: false, error: message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});