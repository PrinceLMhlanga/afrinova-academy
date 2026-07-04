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
      return new Response(JSON.stringify({ success: false, error: "Server misconfiguration" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { studentId, teacherId, amount, gatewayReference } = await req.json();

    if (!studentId || !teacherId || !gatewayReference || amount == null) {
      return new Response(JSON.stringify({ success: false, error: "Missing payment processing parameters" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabase = createClient(PROJECT_URL, SERVICE_ROLE_KEY);

    // ✅ Find the EXISTING pending payment instead of creating new one
    const { data: existingPayment } = await supabase
      .from("payments")
      .select("id")
      .eq("gateway_reference", gatewayReference)
      .eq("status", "pending")
      .maybeSingle();

    let paymentId;

    if (existingPayment) {
      // Update existing pending payment to completed
      await supabase
        .from("payments")
        .update({
          status: "completed",
          updated_at: new Date().toISOString(),
        })
        .eq("id", existingPayment.id);
      
      paymentId = existingPayment.id;
    } else {
      // Check if already completed
      const { data: completedPayment } = await supabase
        .from("payments")
        .select("id")
        .eq("gateway_reference", gatewayReference)
        .eq("status", "completed")
        .maybeSingle();

      if (completedPayment) {
        paymentId = completedPayment.id;
      } else {
        // Fallback: create if doesn't exist (shouldn't happen normally)
        const { data: newPayment, error: paymentError } = await supabase
          .from("payments")
          .insert({
            student_id: studentId,
            teacher_id: teacherId,
            amount: Number(amount),
            gateway_reference: gatewayReference,
            status: "completed",
          })
          .select("id")
          .single();

        if (paymentError || !newPayment) {
          throw paymentError ?? new Error("Failed to create payment record");
        }
        paymentId = newPayment.id;
      }
    }

    // ✅ Get default commission from platform_settings FIRST
const { data: defaultCommission } = await supabase
  .from("platform_settings")
  .select("value")
  .eq("key", "default_commission")  // Fixed typo: was "default_commision"
  .maybeSingle();

// Parse default: "20:80" → platform=20, teacher=80
let platformPct = 20;  // Fallback if not set
let teacherPct = 80;   // Fallback if not set

if (defaultCommission?.value) {
  const parts = String(defaultCommission.value).split(":");
  platformPct = parseInt(parts[0], 10) || 20;
  teacherPct = parseInt(parts[1], 10) || 80;
}

// ✅ Then check for teacher-specific override
const { data: teacherCommission } = await supabase
  .from("commission_rules")
  .select("platform_percentage, teacher_percentage")
  .eq("teacher_id", teacherId)
  .eq("is_active", true)
  .order("effective_from", { ascending: false })
  .maybeSingle();

// Teacher-specific overrides the default
if (teacherCommission) {
  platformPct = teacherCommission.platform_percentage;
  teacherPct = teacherCommission.teacher_percentage;
}

const teacherAmount = Number(amount) * (Number(teacherPct) / 100);
const platformAmount = Number(amount) * (Number(platformPct) / 100);

    // Check for existing financial transactions (prevent duplicates)
    const { data: existingTxns } = await supabase
      .from("financial_transactions")
      .select("id")
      .eq("payment_id", paymentId);

    if (!existingTxns || existingTxns.length === 0) {
      await supabase.from("financial_transactions").insert([
        {
          payment_id: paymentId,
          owner_type: "teacher",
          owner_id: teacherId,
          amount: teacherAmount,
          type: "credit",
          description: "Payment from student",
        },
        {
          payment_id: paymentId,
          owner_type: "platform",
          owner_id: studentId,
          amount: platformAmount,
          type: "credit",
          description: "Platform fee",
        },
      ]);
    }

    // Update teacher wallet
    const { data: currentWallet } = await supabase
      .from("teacher_wallets")
      .select("pending_balance, lifetime_earnings")
      .eq("teacher_id", teacherId)
      .maybeSingle();

    const currentPending = Number(currentWallet?.pending_balance ?? 0);
    const currentLifetime = Number(currentWallet?.lifetime_earnings ?? 0);

    await supabase.from("teacher_wallets").upsert({
      teacher_id: teacherId,
      pending_balance: currentPending + teacherAmount,
      lifetime_earnings: currentLifetime + teacherAmount,
      last_updated: new Date().toISOString(),
    }, { onConflict: "teacher_id" });

    return new Response(JSON.stringify({ success: true }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Payment processing failed";
    return new Response(JSON.stringify({ success: false, error: message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});