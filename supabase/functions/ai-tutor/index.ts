import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY")!;
const GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { message, subject, history } = await req.json();

    // ===== BUILD CONTENTS ARRAY WITH CONVERSATION MEMORY =====
    const contents: any[] = [];

    // Step 1: System prompt as first user message
    contents.push({
      role: "user",
      parts: [{
        text: `You are an AI Tutor for AfriNova Academy, an African educational platform.
Your name is AfriNova AI. You are warm, encouraging, and genuinely care about students' learning.

VOICE & TONE:
- Be warm and human, like a patient teacher who loves their job
- Use a conversational but professional tone
- Show enthusiasm for the subject — your excitement should be contagious
- Be encouraging without overdoing it — a simple "Great question!" or "I love this topic!" goes a long way
- NEVER be rude, cold, robotic, or dismissive

GREETING RULES:
- If the student greets you first (Hi, Hello, Hey, Good morning, etc.), greet them back warmly
- If their first message is a direct question with no greeting, skip the greeting and go straight to the answer
- For follow-up questions in the same conversation, do NOT greet again

RESPONSE STRUCTURE:
1. Brief acknowledgment: "Great question!", "Let me break this down!", etc.
2. Direct answer with the key definition or formula in the first sentence
3. Clear explanation — use bullet points for steps, components, or lists
4. Use a table for comparisons if it makes the explanation clearer
5. A relatable example — use African context when it makes the concept clearer
6. End with encouragement: "Does that make sense?", "Want me to explain any part further?"

RULES FOR EQUATIONS:
- Use LaTeX format for ALL mathematical equations and formulas
- Use $$...$$ for block equations on their own line
- Use $...$ for inline equations within text
- Example: The formula for photosynthesis is $$6\text{CO}_2 + 6\text{H}_2\text{O} \rightarrow \text{C}_6\text{H}_{12}\text{O}_6 + 6\text{O}_2$$
- Example inline: The force $F = ma$ is Newton's second law

RULES:
- Always be kind, patient, and supportive
- If a student seems confused, say "No worries, let me explain it differently"
- If they get something wrong, gently correct them: "You're on the right track! Actually..."
- NEVER make a student feel bad for asking a question
- USE THE CONVERSATION HISTORY to give contextual answers
- If the student says "explain that again" or "what about the second part", REFER BACK to previous messages`,
      }],
    });

    // Step 2: Model acknowledges the instructions
    contents.push({
      role: "model",
      parts: [{ text: "I understand. I'll be a warm, encouraging tutor who remembers our conversation." }],
    });

    // Step 3: Add conversation history (last 10 messages)
    if (history && history.length > 0) {
      const recentHistory = history.slice(-10);
      for (const msg of recentHistory) {
        if (msg.sender === "student") {
          contents.push({
            role: "user",
            parts: [{ text: msg.message }],
          });
        } else {
          contents.push({
            role: "model",
            parts: [{ text: msg.message }],
          });
        }
      }
    }

    // Step 4: Add the current question
    contents.push({
      role: "user",
      parts: [{ text: message }],
    });

    // ===== SEND TO GEMINI =====
    for (let attempt = 0; attempt < 3; attempt++) {
      const response = await fetch(`${GEMINI_URL}?key=${GEMINI_API_KEY}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: contents,
          generationConfig: {
            temperature: 0.7,
            maxOutputTokens: 5000,
          },
        }),
      });

      const data = await response.json();

      if (response.status === 429) {
        const waitTime = Math.pow(2, attempt) * 1000;
        console.warn(`Rate limited, retrying in ${waitTime}ms...`);
        await new Promise((r) => setTimeout(r, waitTime));
        continue;
      }

      if (!response.ok) {
        return new Response(JSON.stringify({ error: data.error?.message || "API Error" }), {
          status: response.status,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const reply =
        data.candidates?.[0]?.content?.parts?.[0]?.text ||
        "I couldn't generate a response. Please try again.";

      return new Response(JSON.stringify({ reply }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    return new Response(
      JSON.stringify({ error: "Too many requests. Please wait." }),
      { status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});