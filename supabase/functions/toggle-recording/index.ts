import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const { roomName, action, lessonId } = await req.json();
    
    const LIVEKIT_API_KEY = Deno.env.get("LIVEKIT_API_KEY")!;
    const LIVEKIT_API_SECRET = Deno.env.get("LIVEKIT_API_SECRET")!;
    const LIVEKIT_HOST = Deno.env.get("LIVEKIT_HOST")!; // e.g., https://your-livekit-server.com

    const url = `${LIVEKIT_HOST}/twirp/livekit.RoomService/${action === 'start' ? 'StartRecording' : 'StopRecording'}`;
    
    const response = await fetch(url, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${LIVEKIT_API_KEY}:${LIVEKIT_API_SECRET}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        roomName: roomName,
        ...(action === 'start' ? {} : { recordingId: lessonId }),
      }),
    });

    const data = await response.json();
    
    return new Response(JSON.stringify(data), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});