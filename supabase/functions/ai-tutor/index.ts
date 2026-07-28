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
    const body = await req.json(); // ✅ Parse once
    const { message, subject, history, action } = body;

  if (action === "analyze_exam") {
      return await handleExamAnalysis(body, corsHeaders);
    }

    if (action === "generate_flashcards") {
  return await handleFlashcardGeneration(body, corsHeaders);
}

if (action === "generate_summary") {
  return await handleSummaryGeneration(body, corsHeaders);
}

if (action === "chat_stream") {
  return await handleChatStream(body, corsHeaders);  // ✅ Pass body, not req
}

    

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
async function handleExamAnalysis(body: any, corsHeaders: Record<string, string>) {
  const { failedQuestions } = body;
  
  if (!failedQuestions || failedQuestions.length === 0) {
    return new Response(JSON.stringify({ feedback: '', perQuestion: [] }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
  
  const prompt = `You are an exam tutor for AfriNova Academy. Analyze these questions.

For EACH question, provide your analysis in this exact format (start each question with ###QUESTION_START and end with ###QUESTION_END):

###QUESTION_START
**What it means**: [interpretation]
**Why correct**: [explanation]
**Why wrong**: [explanation for each wrong option]
**💡 Tip**: [short tip]
###QUESTION_END

${failedQuestions.map((q: any, i: number) => `
Question ${i}:
${q.question_text}
A: ${q.option_a}
B: ${q.option_b}
C: ${q.option_c}
D: ${q.option_d}
Correct Answer: ${q.correct_answer}
Student Answered: ${q.student_answer}
`).join('\n')}`;

  const response = await fetch(`${GEMINI_URL}?key=${GEMINI_API_KEY}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: {
        temperature: 0.5,
        maxOutputTokens: 4000,
      },
    }),
  });

  const data = await response.json();
  const fullText = data.candidates?.[0]?.content?.parts?.[0]?.text || '';
  
  // ✅ Parse per-question responses
  const perQuestion: string[] = [];
  const regex = /###QUESTION_START([\s\S]*?)###QUESTION_END/g;
  let match;
  while ((match = regex.exec(fullText)) !== null) {
    perQuestion.push(match[1].trim());
  }
  
  console.log(`Parsed ${perQuestion.length} question explanations`);

  return new Response(JSON.stringify({ 
    feedback: fullText,
    perQuestion: perQuestion 
  }), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}


async function handleFlashcardGeneration(body: any, corsHeaders: Record<string, string>) {
  const { topic, subject, level, count } = body;
  
  const prompt = `You are an expert educator. Generate ${count || 10} flashcards for ${subject} - ${topic} at ${level} level.

For each flashcard, output in this exact format:
###CARD_START
Q: [question]
A: [answer]
###CARD_END

Rules:
- Mix simple recall and conceptual understanding questions
- Keep answers concise (1-3 sentences)
- Cover key definitions, formulas, and concepts
- Include at least 2 calculation-based cards if applicable
- Use LaTeX for formulas: $formula$`;

  const response = await fetch(`${GEMINI_URL}?key=${GEMINI_API_KEY}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: { temperature: 0.7, maxOutputTokens: 3000 },
    }),
  });

  const data = await response.json();
  const text = data.candidates?.[0]?.content?.parts?.[0]?.text || '';
  
  // Parse cards
  const cards: { question: string; answer: string }[] = [];
  const regex = /###CARD_START\s*Q:\s*([\s\S]*?)\s*A:\s*([\s\S]*?)###CARD_END/g;
  let match;
  while ((match = regex.exec(text)) !== null) {
    cards.push({
      question: match[1].trim(),
      answer: match[2].trim(),
    });
  }

  return new Response(JSON.stringify({ cards }), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}



async function handleSummaryGeneration(body: any, corsHeaders: Record<string, string>) {
  const { topic, subject, level, syllabusOutline } = body;
  
  let prompt = `You are an expert ZIMSEC educator. Create a comprehensive study summary for ${subject} - ${topic} at ${level} level.`;

  // ✅ Include syllabus outline if available
  if (syllabusOutline && syllabusOutline.trim().length > 0) {
    prompt += `\n\nFollow this syllabus outline:\n${syllabusOutline}`;
  } else {
    prompt += `\n\nCover the key topics, concepts, formulas, and exam tips for this subject.`;
  }

  prompt += `

Structure your response with:
## Key Concepts
- Bullet points of main ideas

## Important Formulas
- Use LaTeX: $formula$

## Detailed Notes
- Organized by subtopic
- Clear explanations
- Examples where helpful

## Exam Tips
- Common mistakes to avoid
- What examiners look for

## Quick Review
- 5 key points to remember

CRITICAL LaTeX RULES:
- ALWAYS wrap text/units inside \text{} within math mode
- Example WRONG: $4200 J kg^{-1} K^{-1}$
- Example RIGHT: $4200\text{ J kg}^{-1}\text{K}^{-1}$
- For temperatures: $20^\circ\text{C}$ (NOT $20^\circ C$)
- Put space BEFORE and AFTER each $ delimiter
- Separate multiple formulas with newlines, not on same line

Keep it clear and student-friendly. Use LaTeX for ALL formulas.`;

  const response = await fetch(`${GEMINI_URL}?key=${GEMINI_API_KEY}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: { temperature: 0.5, maxOutputTokens: 4000 },
    }),
  });

  const data = await response.json();
  const summary = data.candidates?.[0]?.content?.parts?.[0]?.text || '';

  return new Response(JSON.stringify({ summary }), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// For streaming chat, use SSE

function buildContents(message: string, subject: string, history: any[] | undefined): any[] {
  const contents: any[] = [];

  // System prompt
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

  return contents;
}

const GEMINI_STREAM_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:streamGenerateContent";

async function handleChatStream(body: any, corsHeaders: Record<string, string>) {
  const { message, subject, history } = body;
  console.log('🔵 Chat stream request received');
  
  const contents = buildContents(message, subject, history);
  
  console.log('🔵 Calling Gemini stream API...');
  
  const response = await fetch(`${GEMINI_STREAM_URL}?key=${GEMINI_API_KEY}&alt=sse`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: contents,
      generationConfig: { temperature: 0.7, maxOutputTokens: 2000 },
    }),
  });

  console.log('🔵 Gemini response status:', response.status);
  
  if (!response.ok) {
    const errorText = await response.text();
    console.error('🔴 Gemini error:', errorText);
    return new Response(JSON.stringify({ error: 'Stream failed' }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  // Create SSE stream
  const stream = new ReadableStream({
    async start(controller) {
      const reader = response.body?.getReader();
      if (!reader) {
        console.error('🔴 No reader available');
        controller.close();
        return;
      }

      const decoder = new TextDecoder();
      let buffer = '';

      try {
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;

          buffer += decoder.decode(value, { stream: true });
          const lines = buffer.split('\n');
          buffer = lines.pop() || '';

          for (const line of lines) {
            if (line.startsWith('data: ')) {
              const data = line.substring(6).trim();
              if (!data || data === '[DONE]') continue;
              try {
                const parsed = JSON.parse(data);
                const text = parsed.candidates?.[0]?.content?.parts?.[0]?.text || '';
                if (text) {
                  controller.enqueue(`data: ${JSON.stringify({ text })}\n\n`);
                }
              } catch (e) {
                console.log('🔶 Parse skip for line:', data.substring(0, 50));
              }
            }
          }
        }
      } finally {
        reader.releaseLock();
        controller.enqueue('data: [DONE]\n\n');
        controller.close();
        console.log('🔵 Stream closed');
      }
    }
  });

  return new Response(stream, {
    headers: {
      ...corsHeaders,
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      "Connection": "keep-alive",
    },
  });
}