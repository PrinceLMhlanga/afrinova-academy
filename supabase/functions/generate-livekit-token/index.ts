// supabase/functions/generate-livekit-token/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { AccessToken } from "https://esm.sh/livekit-server-sdk@2.3.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const { roomName, participantName, participantId } = await req.json();

    const API_KEY = Deno.env.get("LIVEKIT_API_KEY")!;
    const API_SECRET = Deno.env.get("LIVEKIT_API_SECRET")!;

    const token = new AccessToken(API_KEY, API_SECRET, {
      identity: participantId,
      name: participantName,
    });

    token.addGrant({
      roomJoin: true,
      room: roomName,
      canPublish: true,
      canSubscribe: true,
    });

    const jwt = await token.toJwt();

    return new Response(JSON.stringify({ token: jwt }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});