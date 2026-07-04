import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const PAYNOW_INTEGRATION_KEY = Deno.env.get("PAYNOW_INTEGRATION_KEY");
const PROJECT_URL = Deno.env.get("PROJECT_URL");
const SERVICE_ROLE_KEY = Deno.env.get("SERVICE_ROLE_KEY");

if (!PAYNOW_INTEGRATION_KEY || !PROJECT_URL || !SERVICE_ROLE_KEY) {
  console.error("Missing required PayNow environment variables");
}

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }

  const body = await req.text();
  const params = new URLSearchParams(body);

  const status = params.get("status")?.trim();
  const paynowReference = params.get("paynowreference")?.trim();
  const reference = params.get("reference")?.trim();
  const amount = parseFloat(params.get("amount") || "0");
  const hash = params.get("hash")?.trim();

  if (!reference || !paynowReference || !status || !hash) {
    return new Response("Missing required payment fields", { status: 400 });
  }

  if (!PAYNOW_INTEGRATION_KEY || !PROJECT_URL || !SERVICE_ROLE_KEY) {
    return new Response("Server misconfiguration", { status: 500 });
  }

  const hashString = `${PAYNOW_INTEGRATION_KEY}${paynowReference}${params.get("amount") || "0"}${status}`;
  const computedHash = await sha256(hashString);
  const durationDays = amount >= 25 ? 90 : 30;

  if (computedHash !== hash) {
    console.error("Hash mismatch - possible tampering");
    return new Response("Invalid hash", { status: 400 });
  }

  const supabase = createClient(PROJECT_URL, SERVICE_ROLE_KEY);

  if (status === "Paid" || status === "Awaiting Delivery") {
    // ✅ CHECK IF ALREADY PROCESSED FIRST
    const { data: alreadyProcessed } = await supabase
      .from("payments")
      .select("id, status")
      .eq("gateway_reference", reference)
      .eq("status", "completed")
      .maybeSingle();

    if (alreadyProcessed) {
      console.log("⚠️ Payment already processed:", reference);
      return new Response("Already processed", { status: 200 });
    }

    const { data: payment, error: findError } = await supabase
      .from("payments")
      .select("*")
      .eq("gateway_reference", reference)
      .eq("status", "pending")
      .maybeSingle();

    if (findError || !payment) {
      console.error("Payment not found:", reference, findError);
      return new Response("Payment not found", { status: 404 });
    }

    const expiresAt = new Date(Date.now() + durationDays * 24 * 60 * 60 * 1000).toISOString();

    // Update payment status
    const { error: updateError } = await supabase
      .from("payments")
      .update({
        status: "completed",
        paynow_reference: paynowReference,
        updated_at: new Date().toISOString(),
      })
      .eq("id", payment.id)
      .eq("status", "pending");

    if (updateError) {
      console.error("Failed to update payment:", updateError);
      return new Response("Update failed", { status: 500 });
    }

    

    // Commission logic
    const { data: commissionData } = await supabase
      .from("platform_settings")
      .select("value")
      .eq("key", "default_commission")
      .maybeSingle();

    let platformPct = 20;
    let teacherPct = 80;

    if (commissionData?.value) {
      const parts = String(commissionData.value).split(":");
      platformPct = parseInt(parts[0], 10) || 20;
      teacherPct = parseInt(parts[1], 10) || 80;
    }

    const { data: teacherCommission } = await supabase
      .from("commission_rules")
      .select("platform_percentage, teacher_percentage")
      .eq("teacher_id", payment.teacher_id)
      .eq("is_active", true)
      .maybeSingle();

    if (teacherCommission) {
      platformPct = teacherCommission.platform_percentage;
      teacherPct = teacherCommission.teacher_percentage;
    }

    const teacherAmount = amount * (teacherPct / 100);
    const platformAmount = amount * (platformPct / 100);

    // Financial transactions
    const { data: existingTxns } = await supabase
      .from("financial_transactions")
      .select("id")
      .eq("payment_id", payment.id);

    if (!existingTxns || existingTxns.length === 0) {
      await supabase.from("financial_transactions").insert([
        {
          payment_id: payment.id,
          owner_type: "teacher",
          owner_id: payment.teacher_id,
          amount: teacherAmount,
          type: "credit",
          description: `Payment from student ${payment.student_id}`,
        },
        {
          payment_id: payment.id,
          owner_type: "platform",
          owner_id: payment.student_id,
          amount: platformAmount,
          type: "credit",
          description: "Platform fee",
        },
      ]);
    }

    // Teacher wallet
    const { data: wallet } = await supabase
      .from("teacher_wallets")
      .select("pending_balance, lifetime_earnings")
      .eq("teacher_id", payment.teacher_id)
      .maybeSingle();

    const currentPending = wallet?.pending_balance || 0;
    const currentLifetime = wallet?.lifetime_earnings || 0;

    await supabase.from("teacher_wallets").upsert({
      teacher_id: payment.teacher_id,
      pending_balance: currentPending + teacherAmount,
      lifetime_earnings: currentLifetime + teacherAmount,
      last_updated: new Date().toISOString(),
    }, { onConflict: "teacher_id" });

    // Update student profile
    await supabase.from("profiles").update({
      is_subscribed: true,
      subscription_expires_at: expiresAt,
      subscription_plan: "paid",
    }).eq("id", payment.student_id);

    console.log("✅ Payment processed successfully:", reference);
  } else {
    console.log(`ℹ️ Payment status: ${status} - no action needed`);
  }

  return new Response("OK", { status: 200 });
});

// SHA256 hash function
async function sha256(message: string): Promise<string> {
  const msgBuffer = new TextEncoder().encode(message);
  const hashBuffer = await crypto.subtle.digest("SHA-256", msgBuffer);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
}