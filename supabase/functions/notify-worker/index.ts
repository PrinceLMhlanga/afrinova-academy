import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const PROJECT_URL = Deno.env.get("PROJECT_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SERVICE_ROLE_KEY")!;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Content-Type": "application/json",
};

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const supabase = createClient(PROJECT_URL, SERVICE_ROLE_KEY);

    // Fetch undelivered notifications
    const { data: pending, error: fetchError } = await supabase
      .from('notifications')
      .select('id')
      .is('delivered_at', null)
      .order('created_at', { ascending: true })
      .limit(100);

    if (fetchError) throw fetchError;
    if (!pending || pending.length === 0) {
      return new Response(JSON.stringify({ success: true, processed: 0 }), { headers: corsHeaders });
    }

    const results: Array<any> = [];

    for (const n of pending) {
      try {
        const resp = await fetch(`${PROJECT_URL}/functions/v1/notify-dispatch`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'apikey': SERVICE_ROLE_KEY,
            'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
          },
          body: JSON.stringify({ notificationId: n.id }),
        });

        if (resp.ok) {
          await supabase.from('notifications').update({ delivered_at: new Date().toISOString() }).eq('id', n.id);
          results.push({ id: n.id, status: resp.status });
        } else {
          const text = await resp.text();
          results.push({ id: n.id, status: resp.status, body: text });
        }
      } catch (e) {
        results.push({ id: n.id, error: String(e) });
      }
    }

    return new Response(JSON.stringify({ success: true, processed: results.length, results }), { headers: corsHeaders });
  } catch (error) {
    return new Response(JSON.stringify({ success: false, error: (error as Error).message }), { status: 500, headers: corsHeaders });
  }
});
