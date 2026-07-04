import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const PROJECT_URL = Deno.env.get("PROJECT_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SERVICE_ROLE_KEY")!;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Content-Type": "application/json",
};

Deno.serve(async (req) => {
  try {
    const supabase = createClient(PROJECT_URL, SERVICE_ROLE_KEY);

    // ✅ Get minimum settlement threshold from platform_settings
    const { data: thresholdData } = await supabase
      .from("platform_settings")
      .select("value")
      .eq("key", "settlement_threshold")
      .maybeSingle();

    const minimumThreshold = parseFloat(thresholdData?.value || "20");
    
    console.log(`💰 Settlement threshold: $${minimumThreshold}`);
    console.log(`🔍 Checking teacher wallets...`);

    // Get all teacher wallets with pending balance above threshold
    const { data: wallets } = await supabase
      .from("teacher_wallets")
      .select("*")
      .gte("pending_balance", minimumThreshold);  // ✅ Only get wallets above threshold

    if (!wallets || wallets.length === 0) {
      console.log(`❌ No teachers have reached the $${minimumThreshold} threshold yet`);
      return new Response(JSON.stringify({ 
        success: true, 
        released: 0,
        threshold: minimumThreshold,
        message: "No teachers above threshold"
      }), { headers: corsHeaders });
    }

    let totalReleased = 0;
    let teachersSettled = 0;

    for (const wallet of wallets) {
      const teacherId = wallet.teacher_id;
      const currentPending = Number(wallet.pending_balance || 0);
      const currentAvailable = Number(wallet.available_balance || 0);
      const currentLifetime = Number(wallet.lifetime_earnings || 0);
      
      if (currentPending < minimumThreshold) continue;

      // ✅ Move ALL pending to available
      const releaseAmount = currentPending;
      const newAvailable = currentAvailable + releaseAmount;

      const { error: updateError } = await supabase
        .from("teacher_wallets")
        .upsert({
          teacher_id: teacherId,
          pending_balance: 0,  // Reset pending
          available_balance: newAvailable,  // Add to available
          lifetime_earnings: currentLifetime,
          last_updated: new Date().toISOString(),
        }, { onConflict: "teacher_id" });

      if (updateError) {
        console.error(`❌ Failed to settle teacher ${teacherId}:`, updateError);
        continue;
      }

      // ✅ Log the settlement as a transaction
      await supabase.from("financial_transactions").insert({
        owner_type: "teacher",
        owner_id: teacherId,
        amount: releaseAmount,
        type: "settlement",
        description: `Weekly settlement - $${releaseAmount.toFixed(2)} moved to available`,
      });

      console.log(`✅ Settled $${releaseAmount.toFixed(2)} for teacher ${teacherId}`);
      totalReleased += releaseAmount;
      teachersSettled++;
    }

    console.log(`🎉 Settled ${teachersSettled} teachers. Total released: $${totalReleased.toFixed(2)}`);

    return new Response(JSON.stringify({ 
      success: true, 
      released: totalReleased,
      teachersSettled: teachersSettled,
      threshold: minimumThreshold,
    }), { headers: corsHeaders });

  } catch (error) {
    console.error("❌ Auto-settle error:", error);
    return new Response(JSON.stringify({ 
      success: false, 
      error: error instanceof Error ? error.message : "Unknown error" 
    }), { 
      status: 500, 
      headers: corsHeaders 
    });
  }
});