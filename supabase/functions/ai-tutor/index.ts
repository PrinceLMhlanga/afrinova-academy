import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY")!;
const GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent";

import { GoogleGenAI } from "npm:@google/genai";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, accept, cache-control",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};


const ai = new GoogleGenAI({ apiKey: GEMINI_API_KEY });

// ✅ THE SINGLE MASTER ENTRY ROUTER
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const body = await req.json(); 
    const { action } = body;

    // Route to the appropriate feature handler function
    if (action === "chat_stream") {
      return await handleChatStream(body, corsHeaders); 
    }

    if (action === "analyze_exam") {
      return await handleExamAnalysis(body, corsHeaders);
    }

    if (action === "generate_flashcards") {
      return await handleFlashcardGeneration(body, corsHeaders);
    }

    if (action === "generate_summary") {
      return await handleSummaryGeneration(body, corsHeaders);
    }

    return new Response(JSON.stringify({ error: "Invalid action" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  } catch (err) {
    console.error("🔴 Server routing error:", err);
    return new Response(JSON.stringify({ error: "Internal Server Error" }), {
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
  
    const prompt = `You are an expert exam tutor for AfriNova Academy. Analyze these student mistakes concisely.
  
TOTAL QUESTIONS TO PROCESS: ${failedQuestions.length}
CRITICAL RULE: Keep explanations highly concise and punchy so that ALL questions fit into this single response window.

For EACH question, provide your analysis in this exact compressed format (start each question with ###QUESTION_START and end with ###QUESTION_END):

###QUESTION_START
**Concept**: [1 brief sentence on what core topic this question tests]
**Why Correct**: [1 direct sentence or short calculation proof explaining the logic of the correct choice. in case you find the correct option wrong also, be transparent and tell the student that there might be an error or typo. The correct answer should actually be : ...]
**Key Distractor Error**: [1 sentence explaining the primary misconception behind the incorrect choices, especially the student's selected answer]
**💡 Quick Tip**: [1 short exam strategy tip under 15 words]
###QUESTION_END

Failed Questions Data Dataset:
${failedQuestions.map((q: any, i: number) => `
[Q ${i + 1}] Text: ${q.question_text}
Options -> A: ${q.option_a} | B: ${q.option_b} | C: ${q.option_c} | D: ${q.option_d}
Correct: ${q.correct_answer} | Student Chose: ${q.student_answer}
`).join('\n')}`;


  // 1. Declare the universal free-tier fallback prioritization model chain
  const modelChain = [
    "gemini-3.6-flash",
    "gemini-3.5-flash",
    "gemini-3.5-flash-lite",
    "gemini-2.5-flash"
  ];

  let responseData = null;
  let activeModelUsed = "";

  // 2. Cascade down the models if a free-tier rate limit occurs
  for (const modelName of modelChain) {
    try {
      console.log(`Connecting Exam Analysis to model node: ${modelName}...`);
      
      // Use the official client's .models.generateContent method for standard static JSON responses
      responseData = await ai.models.generateContent({
        model: modelName,
        contents: [{ role: "user", parts: [{ text: prompt }] }],
        config: {
          temperature: 0.3,
          maxOutputTokens: 8000,
        },
      });

      activeModelUsed = modelName;
      console.log(`✅ Exam Analysis success link: ${activeModelUsed}`);
      break; 

    } catch (error: any) {
      console.warn(`⚠️ Model node ${modelName} rejected exam payload:`, error.message || error);
      if (modelName === modelChain[modelChain.length - 1]) {
        return new Response(JSON.stringify({ error: "All fallback models exhausted" }), {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
      continue; 
    }
  }

  // Extract text safely using the official SDK object structure
  const fullText = responseData?.text || '';
  
  // 3. Parse per-question blocks using your existing regex logic
  const perQuestion: string[] = [];
  const regex = /###QUESTION_START([\s\S]*?)###QUESTION_END/g;
  let match;
  while ((match = regex.exec(fullText)) !== null) {
    perQuestion.push(match[1].trim());
  }
  
  console.log(`Parsed ${perQuestion.length} question explanations using ${activeModelUsed}`);

  return new Response(JSON.stringify({ 
    feedback: fullText,
    perQuestion: perQuestion,
    meta: { model: activeModelUsed } // Send model info back for logging if needed
  }), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}



async function handleFlashcardGeneration(body: any, corsHeaders: Record<string, string>) {
  const { topic, subject, level, count } = body;
  console.log(`🔵 Flashcard generation request received for topic: ${topic}`);
  
  // ✅ PRESERVED EXACTLY: Your original system prompt text completely untouched
  const prompt = `You are an expert educator. Generate ${count || 10} flashcards for ${subject} - ${topic} at ${level} level.

For each flashcard, output in this exact format:
###CARD_START
Q: [question]
A: [answer]
###CARD_END

Rules:
- Mix simple recall and conceptual understanding questions.
- Keep answers concise (1–3 sentences).
- Cover key definitions, formulas, and concepts.
- Include at least 2 calculation-based cards where appropriate.

Formatting Rules:
- Use Markdown for all text.
- Use inline LaTeX ($...$) ONLY for short symbols, variables, or very short expressions (e.g. $F$, $a$, $\Delta v$, $E=mc^2$).
- Use display LaTeX ($$...$$) for any formula, derivation, or calculation longer than a short expression.
- If a calculation requires multiple steps, place each step on its own display equation.
- Never place long equations or derivations inside a sentence.
- Keep each display equation on its own line.`;

  // Define your free-tier model prioritization degradation cascade
  const modelChain = [
    "gemini-2.5-flash",        // Stable base tier matching your entry endpoint parameters
    "gemini-3.5-flash",       
    "gemini-3.5-flash-lite",  
    "gemini-2.5-pro"           // Advanced emergency safety net
  ];

  let responseData = null;
  let activeModelUsed = "";

  // Loop through models if a free-tier rate limit occurs
  for (const modelName of modelChain) {
    try {
      console.log(`Connecting Flashcards to model node: ${modelName}...`);
      
      // Call standard content generation using the official SDK client
      responseData = await ai.models.generateContent({
        model: modelName,
        contents: [{ role: "user", parts: [{ text: prompt }] }],
        config: {
          temperature: 0.7,
          maxOutputTokens: 8000, // Raised to ensure full card datasets never clip mid-generation
        },
      });

      activeModelUsed = modelName;
      console.log(`✅ Flashcard success link confirmed on: ${activeModelUsed}`);
      break; 

    } catch (error: any) {
      console.warn(`⚠️ Model node ${modelName} rejected flashcard payload:`, error.message || error);
      
      if (modelName === modelChain[modelChain.length - 1]) {
        return new Response(JSON.stringify({ error: "All fallback models in the chain have been exhausted." }), {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
      continue; 
    }
  }

  // Extract raw text response from SDK data structure safely
  const text = responseData?.text || '';
  
  // Parse cards using your exact original index bounds matches
  const cards: { question: string; answer: string }[] = [];
  const regex = /###CARD_START\s*Q:\s*([\s\S]*?)\s*A:\s*([\s\S]*?)###CARD_END/g;
  let match;
  
  while ((match = regex.exec(text)) !== null) {
    cards.push({
      question: match[1].trim(),
      answer: match[2].trim(),
    });
  }

  console.log(`Successfully compiled ${cards.length} cards using engine: ${activeModelUsed}`);

  return new Response(JSON.stringify({ cards }), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}




async function handleSummaryGeneration(body: any, corsHeaders: Record<string, string>) {
  const { topic, subject, level, syllabusOutline } = body;
  console.log(`🔵 Summary generation request received for subject: ${subject} - ${topic}`);
  
  // ✅ PRESERVED EXACTLY: Build your original prompt logic completely untouched
  let prompt = `You are an expert ZIMSEC educator. Create a comprehensive study summary for ${subject} - ${topic} at ${level} level.`;

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
- Use inline LaTeX ($...$) ONLY for short symbols, variables, or very short expressions (e.g. $F$, $a$, $\Delta v$, $E=mc^2$).
- Use display LaTeX ($$...$$) for any formula, derivation, or calculation longer than a short expression.
- If a calculation requires multiple steps, place each step on its own display equation.
- Never place long equations or derivations inside a sentence.
- Keep each display equation on its own line.

Keep it clear and student-friendly. Use LaTeX for ALL formulas.`;

  // 1. Declare the universal free-tier fallback prioritization model chain
  const modelChain = [
    "gemini-2.5-flash",        // Matches your standard default entry endpoint engine configuration
    "gemini-3.5-flash",       
    "gemini-3.5-flash-lite",  
    "gemini-2.5-pro"           // Advanced emergency safety net for large data summaries
  ];

  let responseData = null;
  let activeModelUsed = "";

  // 2. Cascade down the models if a free-tier rate limit occurs
  for (const modelName of modelChain) {
    try {
      console.log(`Connecting Summary Engine to model node: ${modelName}...`);
      
      // Use the official client's .models.generateContent method for standard static responses
      responseData = await ai.models.generateContent({
        model: modelName,
        contents: [{ role: "user", parts: [{ text: prompt }] }],
        config: {
          temperature: 0.5,
          maxOutputTokens: 8000,
        },
      });

      activeModelUsed = modelName;
      console.log(`✅ Summary success link confirmed on: ${activeModelUsed}`);
      break; 

    } catch (error: any) {
      console.warn(`⚠️ Model node ${modelName} rejected summary payload:`, error.message || error);
      
      if (modelName === modelChain[modelChain.length - 1]) {
        return new Response(JSON.stringify({ error: "All fallback models in the chain have been exhausted." }), {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
      continue; 
    }
  }

  // 3. Extract raw text response from SDK data structure safely
  const summary = responseData?.text || '';

  console.log(`Successfully compiled study summary block using engine: ${activeModelUsed}`);

  return new Response(JSON.stringify({ summary }), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}








// ✅ Preserved system rules, AfriNova branding, historical matching, and LaTeX formatting guidelines
function buildContents(message: string, subject: string, history: any[] | undefined): any[] {
  const contents: any[] = [];

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
- Use inline LaTeX ($...$) ONLY for short symbols, variables, or very short expressions (e.g. $F$, $a$, $\Delta v$, $E=mc^2$).
- Use display LaTeX ($$...$$) for any formula, derivation, or calculation longer than a short expression.
- If a calculation requires multiple steps, place each step on its own display equation.
- Never place long equations or derivations inside a sentence.
- Keep each display equation on its own line.

RULES:
- Always be kind, patient, and supportive
- If a student seems confused, say "No worries, let me explain it differently"
- If they get something wrong, gently correct them: "You're on the right track! Actually..."
- NEVER make a student feel bad for asking a question
- USE THE CONVERSATION HISTORY to give contextual answers
- If the student says "explain that again" or "what about the second part", REFER BACK to previous messages`,
    }],
  });

  contents.push({
    role: "model",
    parts: [{ text: "I understand. I'll be a warm, encouraging tutor who remembers our conversation." }],
  });

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

  contents.push({
    role: "user",
    parts: [{ text: `Subject context: ${subject || 'General Educational Development'}. Current input request: ${message}` }],
  });

  return contents;
}

async function handleChatStream(body: any, corsHeaders: Record<string, string>) {
  const { message, subject, history } = body;
  const contents = buildContents(message, subject, history);

  // 1. Define your free-tier model prioritization degradation cascade
  const modelChain = [
    "gemini-3.6-flash",       
    "gemini-3.5-flash",       
    "gemini-3.5-flash-lite",
    "gemini-2.5-flash",      
    "gemini-2.5-flash-lite" 
  ];

  let responseStream = null;
  let activeModelUsed = "";

  // 2. Attempt model connections one by one
  for (const modelName of modelChain) {
    try {
      console.log(`Trying to connect stream to Gemini model: ${modelName}...`);
      
      responseStream = await ai.models.generateContentStream({
        model: modelName,
        contents: contents,
        config: { 
          temperature: 0.7, 
          maxOutputTokens: 8000 
        },
      });

      // If execution reaches here without throwing an error, the model accepted the request!
      activeModelUsed = modelName;
      console.log(`✅ Success! Stream connected using: ${activeModelUsed}`);
      break; 

    } catch (error: any) {
      console.warn(`⚠️ Model ${modelName} failed or tier exhausted. Error details:`, error.message || error);
      
      // If we are at the end of our model fallback options list, throw the error out to the main handler
      if (modelName === modelChain[modelChain.length - 1]) {
        throw new Error("All fallback models in the free tier chain have been exhausted or returned errors.");
      }
      
      console.log("🔄 Degrading gracefully to the next available tier fallback model...");
      continue; // Jump to the next model configuration item in the array loop
    }
  }

  // 3. Create and return the readable response stream
  const stream = new ReadableStream({
    async start(controller) {
      try {
        // Track the model name behind the scenes inside the stream envelope if tracking is needed
        controller.enqueue(`data: ${JSON.stringify({ meta: { model: activeModelUsed } })}\n\n`);

        for await (const chunk of responseStream) {
          const text = chunk.text;
          if (text) {
            controller.enqueue(`data: ${JSON.stringify({ text })}\n\n`);
          }
        }
      } catch (streamError) {
        console.error('🔴 Token collection stream runtime error:', streamError);
      } finally {
        controller.enqueue('data: [DONE]\n\n');
        controller.close();
        console.log(`🔵 Stream closed successfully for model: ${activeModelUsed}`);
      }
    }
  });

  const encodedStream = stream.pipeThrough(new TextEncoderStream());

  return new Response(encodedStream, {
    headers: {
      ...corsHeaders,
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache, no-transform",
      "Connection": "keep-alive",
      "X-Accel-Buffering": "no"
    },
  });
}
