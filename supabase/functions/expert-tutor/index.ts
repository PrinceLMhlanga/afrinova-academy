import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { GoogleGenAI } from "npm:@google/genai";

const supabaseUrl = Deno.env.get("PROJECT_URL")!;
const supabaseKey = Deno.env.get("SERVICE_ROLE_KEY")!;
const supabase = createClient(supabaseUrl, supabaseKey);

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY")!;
const ai = new GoogleGenAI({ apiKey: GEMINI_API_KEY });

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, accept, cache-control",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

interface ExpertMessage {
  id: string;
  session_id: string;
  role: string;
  content: string;
  message_type: string;
  objective_id: string | null;
  question_id: string | null;
  created_at: string;
}

interface ExpertObjective {
  id: string;
  topic_id: string;
  subject_id: string | null;
  level_id: string | null;
  subtopic_name: string | null;
  objective_text: string;
  command_word: string | null;
  display_order: number;
  is_active: boolean;
  created_at: string;
}

interface ExpertProgress {
  id: string;
  student_id: string;
  subject_id: string | null;
  topic_id: string | null;
  objective_id: string;
  mastery_level: number;
  difficulty_reached: string;
  attempts_easy: number;
  correct_easy: number;
  attempts_medium: number;
  correct_medium: number;
  attempts_hard: number;
  correct_hard: number;
  attempts_exam: number;
  correct_exam: number;
  is_mastered: boolean;
  mastered_at: string | null;
  last_attempted_at: string | null;
  created_at: string;
  updated_at: string;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const body = await req.json();
    const { action } = body;

    if (action === "expert_chat") {
      return await handleExpertChat(body, corsHeaders);
    }
    if (action === "expert_teach") {
  return await handleExpertTeach(body, corsHeaders);
}


    if (action === "grade_answer") {
      return await handleGradeAnswer(body, corsHeaders);
    }

    if (action === "grade_handwritten") {
      return await handleGradeHandwritten(body, corsHeaders);
    }

    if (action === "load_questions") {
      return await handleLoadQuestions(body, corsHeaders);
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

// ==========================================
// 1. EXPERT CHAT
// ==========================================
async function handleExpertChat(body: any, corsHeaders: Record<string, string>) {
  const { sessionId, message, currentObjectiveId, studentId, image_url, has_image } = body;
  console.log(`🔵 Expert chat stream request for session: ${sessionId}, has_image: ${has_image}`);

  // Get session details
  const { data: session } = await supabase
    .from('expert_tutor_sessions')
    .select('*, topics(name, syllabus_outline), subjects(name), levels(name)')
    .eq('id', sessionId)
    .single();

  if (!session) {
    return new Response(JSON.stringify({ error: "Session not found" }), {
      status: 404,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  // Get conversation history (last 15 messages)
  const { data: chatHistory } = await supabase
    .from('expert_tutor_messages')
    .select('*')
    .eq('session_id', sessionId)
    .order('created_at', { ascending: false })
    .limit(15);

  const orderedHistory = (chatHistory || []).reverse();

  // Get current objective
  const { data: objective } = await supabase
    .from('expert_tutor_objectives')
    .select('*')
    .eq('id', currentObjectiveId)
    .maybeSingle();

  // Get student progress
  const { data: progress } = await supabase
    .from('expert_tutor_progress')
    .select('*')
    .eq('student_id', studentId)
    .eq('objective_id', currentObjectiveId)
    .maybeSingle();

  // Get all objectives
  const { data: allObjectives } = await supabase
    .from('expert_tutor_objectives')
    .select('*')
    .eq('topic_id', session.topic_id)
    .eq('is_active', true)
    .order('display_order', { ascending: true });

  // Get all progress
  const { data: objectivesProgress } = await supabase
    .from('expert_tutor_progress')
    .select('*')
    .eq('student_id', studentId)
    .eq('topic_id', session.topic_id);

  const masteredIds = (objectivesProgress || [])
    .filter((p: any) => p.is_mastered)
    .map((p: any) => p.objective_id);

  const masteredObjectives = masteredIds.length;
  const totalObjectives = (allObjectives || []).length;

  // ✅ Compute batch position
  const currentIdx = (allObjectives || []).findIndex(
    (o: any) => o.id === currentObjectiveId
  );
  
  // Will this objective be the last in batch if mastered?
  const willBeMasteredCount = masteredObjectives + 1;
  const isLastInBatch = willBeMasteredCount % 5 === 0;
  const isLastOverall = currentIdx === (allObjectives || []).length - 1;

  // Find next non-mastered objective
  let nextObj = null;
  for (let i = currentIdx + 1; i < (allObjectives || []).length; i++) {
    if (!masteredIds.includes(allObjectives[i].id)) {
      nextObj = allObjectives[i];
      break;
    }
  }

  // Find current batch objectives
  const batchNumber = Math.floor(masteredObjectives / 5) + 1;
  const currentBatchObjectives = (allObjectives || []).slice(
    Math.floor((currentIdx) / 5) * 5,
    Math.floor((currentIdx) / 5) * 5 + 5
  );

  // ✅ Pre-fetch image and convert to base64
let base64Image = "";
if (has_image && image_url) {
  try {
    console.log('📸 Fetching image from Supabase Storage:', image_url);
    const imageResponse = await fetch(image_url);
    
    if (!imageResponse.ok) {
      throw new Error(`HTTP ${imageResponse.status}: Could not download image`);
    }
    
    const arrayBuffer = await imageResponse.arrayBuffer();
    const imageBytes = new Uint8Array(arrayBuffer);
    console.log('📸 Image downloaded. Size:', imageBytes.length, 'bytes');
    
    // Convert to base64 (chunked to avoid stack overflow on large images)
    let binary = '';
    const chunkSize = 8192;
    for (let i = 0; i < imageBytes.length; i += chunkSize) {
      const chunk = imageBytes.subarray(i, i + chunkSize);
      binary += String.fromCharCode.apply(null, Array.from(chunk));
    }
    base64Image = btoa(binary);
    
    console.log('📸 Base64 encoded. Length:', base64Image.length);
  } catch (fetchErr: any) {
    console.error("🔴 Error fetching image for Gemini:", fetchErr.message);
    return new Response(
      JSON.stringify({ error: `Image processing failed: ${fetchErr.message}` }),
      {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
}

  const systemPrompt = `You are the AfriNova Expert Tutor, a warm and practical ZIMSEC/Cambridge teacher.

You are currently in ASSESSMENT MODE for the topic "${session.topics?.name}".

${has_image ? `⚠️ IMAGE SUBMITTED: The student has uploaded a photo of their handwritten answer. You MUST:
1. Carefully read the handwriting in the image
2. Transcribe what they wrote (mentally, for your grading)
3. Grade the answer against the question requirements
4. Give specific feedback referencing what they actually wrote
5. Identify mistakes, missing steps, or incorrect working
6. If the answer is correct, follow the standard mastery flow
7. If incorrect, give a specific hint about what went wrong

DO NOT IGNORE THE IMAGE. Grade based on what is actually shown.` : ''}

CURRENT CONTEXT:
- Subject: ${session.subjects?.name || 'Unknown'}
- Level: ${session.levels?.name || 'Unknown'}
- Topic: ${session.topics?.name || 'Unknown'}
- Current Objective: ${objective?.objective_text || 'General learning'}
- Command Word: ${objective?.command_word || 'understand'}
- SubTopic: ${objective?.subtopic_name || 'General'}

PROGRESS:
- Objectives Mastered: ${masteredObjectives}/${totalObjectives}
- Current Difficulty: ${progress?.difficulty_reached || 'easy'}
- Easy: ${progress?.correct_easy || 0}/${progress?.attempts_easy || 0} correct
- Medium: ${progress?.correct_medium || 0}/${progress?.attempts_medium || 0} correct
- Hard: ${progress?.correct_hard || 0}/${progress?.attempts_hard || 0} correct
- Exam: ${progress?.correct_exam || 0}/${progress?.attempts_exam || 0} correct

BATCH POSITION:
- This is batch #${batchNumber}
- Remaining in this batch: ${5 - (masteredObjectives % 5)} objectives
- If current objective is mastered, it will be the LAST in this batch: ${isLastInBatch ? 'YES' : 'NO'}
- If current objective is mastered, it will be the LAST overall: ${isLastOverall ? 'YES' : 'NO'}

ALL OBJECTIVES IN THIS TOPIC:
${(allObjectives || []).map((obj: any, i: number) => `${i + 1}. ${obj.objective_text}${masteredIds.includes(obj.id) ? ' ✅' : ''}`).join('\n')}

${nextObj ? `NEXT OBJECTIVE (after current one is mastered): ${nextObj.objective_text}` : 'NEXT OBJECTIVE: None (this is the last one)'}

HOW TO RESPOND TO STUDENT ANSWERS:

✅ CORRECT ANSWER (Not last in batch):
"Very good! You got it right!"
Then INCREASE difficulty and ask a HARDER question on the SAME objective.

👍 CLOSE ANSWER (80% correct):
"Good job! You got [what they got right]. Also add [missing point(s)]."
Then ask a SIMILAR difficulty question.

🤔 PARTIALLY CORRECT (50% correct):
"Good start! You mentioned [correct part]. Let me add [missing key points]."
Ask ONE more question at the SAME difficulty.

❌ WRONG (First attempt):
"Not quite. Here's a hint: [specific hint]."

❌ WRONG AGAIN (Second attempt):
"No worries! Here's the answer: [clear explanation]."
Ask a similar question at the SAME difficulty.

❌ WRONG THIRD TIME:
"Let's move on. You can revise this objective later."
Move to next objective WITHOUT marking mastered.

DIFFICULTY PROGRESSION:
- Start with EASY questions (simple recall or direct application)
- After 1 correct EASY → Move to MEDIUM
- After 1 correct MEDIUM → Move to HARD
- After 1 correct HARD → Generate EXAM-STYLE questions
- After 1 - 2 EXAM-STYLE questions correct → Objective MASTERED

FOR FORMULA-BASED OBJECTIVES:
Provide detailed questions involving real-world calculations using the formula:
- 1 easy, 1 medium, 1 hard, 2 challenging exam questions with mark allocations.

EXAM-STYLE QUESTIONS:
Generate 1-2 challenging ZIMSEC past paper style questions with mark allocations.

⚠️ CRITICAL: WHEN OBJECTIVE IS MASTERED - DO THIS IN ONE MESSAGE:

${isLastOverall
  ? `[TOPIC_COMPLETE] at the START of your response.
     
     Congratulate the student warmly.
     Tell them they have mastered ALL objectives in this topic!
     Do NOT ask another question.`
  : isLastInBatch
    ? `[OBJECTIVE_MASTERED][BATCH_COMPLETE] at the START of your response.
       
       Example (follow this exactly):
       [OBJECTIVE_MASTERED][BATCH_COMPLETE]
       Excellent! You've mastered this objective!
       
       That completes this batch of objectives. Great progress!
       Draw a line under the completed batch and then STOP. DO NOT MOVE TO THE NEXT OBJECTIVE. DO NOT ASK ANOTHER QUESTION. YOU HAVE COMPLETED ASSESSING THIS BATCH OF OBJECTIVES SO YOU ARE DONE FOR NOW. THE SYSTEM WILL HANDLE THE TEACHING OF NEXT OBJECTIVES. 
      `
    : `[OBJECTIVE_MASTERED] at the START of your response.
       
       Then IN ONE MESSAGE:
       1. Congratulate the student
       2. Tell them the objective is mastered
       3. Introduce the NEXT OBJECTIVE
       4. Ask the FIRST QUESTION for the next objective
       
       Example:
       [OBJECTIVE_MASTERED]
       Very good! You've mastered this objective!
       
       Let's move to our next objective: ${nextObj?.objective_text || '[next objective]'}.
       
       Here's your first question:
       [question for next objective]`}

⚠️ CRITICAL - When moving to the next objective NEVER end your message without including the question for that objective. KEEP THE LESSON GOING.

ASSESSMENT FORMATTING RULES (CRITICAL):

1. ALWAYS bold the objective when mentioning it:
   - "Let's move to our next objective: **${objective?.objective_text}**"
   
2. ALWAYS number and label every question with difficulty:
   - Format: **Question N (Difficulty)**
   - Difficulty must match: (Easy), (Medium), (Hard), (Exam-Style), (ZIMSEC Past Paper)
   - N is a continuous counter within the current objective, resetting to 1 on a new objective

3. Question template:
   **Question 1 (Easy)**
   
   [Question text]
   
   [Formula if needed]
   
   [Marks if exam-style: (X marks)]

4. Feedback format:
   - Start with: ✅ **Correct!** or ❌ **Not quite.** or 🤔 **Close!**
   - Brief explanation with **bold** on key terms
   - Then next question with number and difficulty

5. When introducing next objective:
   - Bold it: "Let's move to our next objective: **[objective text]**"
   - Then **Question 1 (Easy)** — reset counter

EXAMPLE:

✅ **Correct!** Your calculation is spot on.

Let's try a slightly harder one:

**Question 3 (Medium)**

A satellite orbits at 400 km above Earth. Given Earth's radius $6400\\text{ km}$ and mass $6 \\times 10^{24}\\text{ kg}$, calculate $g$ at the satellite's position.

$(G = 6.67 \\times 10^{-11}\\text{ N m}^2\\text{kg}^{-2})$

---

LATEX RULES:
- Inline: $symbol$ for short expressions
- Display: $$formula$$ for longer equations on own line
- Units in math: wrap in \\text{}: $4200\\text{ J kg}^{-1}\\text{K}^{-1}$
- Temperature: $20^\\circ\\text{C}$
- No commas in numbers: 30000 not 30,000
- No spaces in multipliers: $10000\\times$

MARKDOWN RULES:
- **Bold** key terms and question labels
- ## for objective headings
- Bullet lists for multi-point feedback
- Horizontal rules (---) to separate questions

RESPOND AS PLAIN TEXT (markdown expected).`;

  const contents: any[] = [];

// System prompt
contents.push({
  role: "user",
  parts: [{ text: systemPrompt }],
});

contents.push({
  role: "model",
  parts: [{ text: "I understand." }],
});

// Conversation history
if (orderedHistory.length > 0) {
  for (const msg of orderedHistory.slice(-10)) {
    if (msg.role === 'student') {
      contents.push({
        role: "user",
        parts: [{ text: msg.content }],
      });
    } else if (msg.role === 'expert' && msg.content) {
      contents.push({
        role: "model",
        parts: [{ text: msg.content }],
      });
    }
  }
}

// ✅ Current message — with image if present
// ✅ Current message — with image if present
if (has_image && base64Image) {
  contents.push({
    role: "user",
    parts: [
      { text: "Here is my handwritten answer. Please read the handwriting carefully and grade it." },
      { 
        inlineData: { 
          data: base64Image,
          mimeType: 'image/jpeg',
        } 
      },
    ],
  });
} else {
  contents.push({
    role: "user",
    parts: [{ text: `Student's answer: ${message}` }],
  });
}

  // Model chain
 // ✅ When image present, prioritize vision-strong models
const modelChain = has_image 
  ? ["gemini-3.6-flash", "gemini-2.5-flash", "gemini-3.5-flash"]
  : ["gemini-2.5-flash", "gemini-3.5-flash-lite", "gemini-3.6-flash"];
  let responseStream: any = null;
  let activeModelUsed = "";

  for (const modelName of modelChain) {
    try {
      console.log(`Connecting Expert Tutor to: ${modelName}...`);
      responseStream = await ai.models.generateContentStream({
        model: modelName,
        contents: contents,
        config: { temperature: 0.5, maxOutputTokens: 8000 },
      });
      activeModelUsed = modelName;
      console.log(`✅ Connected: ${activeModelUsed}`);
      break;
    } catch (error: any) {
      console.warn(`⚠️ ${modelName} failed:`, error.message || error);
      if (modelName === modelChain[modelChain.length - 1]) {
        return new Response(JSON.stringify({ error: "All models exhausted" }), {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
      continue;
    }
  }

  const stream = new ReadableStream({
    async start(controller) {
      try {
        controller.enqueue(`data: ${JSON.stringify({ meta: { model: activeModelUsed } })}\n\n`);
        for await (const chunk of responseStream) {
          const text = chunk.text;
          if (text) {
            controller.enqueue(`data: ${JSON.stringify({ text })}\n\n`);
          }
        }
      } catch (streamError) {
        console.error('🔴 Expert stream error:', streamError);
      } finally {
        controller.enqueue('data: [DONE]\n\n');
        controller.close();
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

async function handleExpertTeach(body: any, corsHeaders: Record<string, string>) {
  const {
    sessionId,
    objectivesText,
    topicName,
    subjectName,
    levelName,
    isFirstBatch,
    masteredText,
  } = body;

  console.log('🔵 Teaching mode - isFirstBatch:', isFirstBatch);

  // Get chat history for continuity
  const { data: chatHistory } = await supabase
    .from('expert_tutor_messages')
    .select('*')
    .eq('session_id', sessionId)
    .order('created_at', { ascending: true })
    .limit(20);

  const orderedHistory = (chatHistory || []).filter(
    (m: any) => m.role === 'expert' || m.role === 'student'
  );

  const historySummary = orderedHistory
    .map((m: any) => `${m.role === 'expert' ? 'Tutor' : 'Student'}: ${(m.content || '').substring(0, 150)}`)
    .join('\n');

  const greetingRule = isFirstBatch
    ? `1. GREET the student warmly and introduce yourself as their AfriNova Expert Tutor. This is the start of a new topic.`
    : `1. DO NOT greet or re-introduce yourself. The student just finished the previous batch.
       Transition naturally like: "Great work on the last batch! Let's continue with the next set of concepts."
       This is the SAME teacher who just finished assessing them.`;

  const masteredSection = (masteredText && masteredText.trim().length > 0)
    ? `\nOBJECTIVES ALREADY MASTERED (do NOT teach these again):\n${masteredText}\n`
    : '';

  const systemInstruction = `You are the AfriNova Expert Tutor — the SAME tutor the student has been working with. 

You are now in TEACHING MODE. Your role has shifted from assessing to teaching, but YOU ARE THE SAME TEACHER.

${isFirstBatch
  ? 'This is the FIRST batch of objectives for this topic.'
  : 'You just finished assessing the previous batch and the student mastered them. Now you are teaching the NEXT batch.'}

CONTEXT:
- Topic: ${topicName}
- Subject: ${subjectName}
- Level: ${levelName}
${masteredSection}
RECENT CONVERSATION (you are continuing from here):
${historySummary || 'No previous conversation'}

TEACH THESE NEW OBJECTIVES:
${objectivesText}

TEACHING GUIDELINES:
${greetingRule}
2. Explain each objective clearly with real-world examples
3. Use simple language first, then introduce technical terms
4. Include relevant formulas where applicable (use LaTeX)
5. Use ZIMSEC-relevant examples and contexts
6. Break down complex concepts into steps
7. Include a mini-summary after each objective
8. End with: "Click START SESSION when you're ready, and I'll assess your understanding."

FORMAT RULES (CRITICAL):
- Use markdown with **## for each objective heading**
- Use **bold** for key terms and important concepts
- Use bullet lists (-) for steps, features, or enumerations
- Use numbered lists (1., 2., 3.) for sequential steps
- Use blockquotes (>) for real-world examples or callouts
- Use tables where helpful for comparisons
- Use horizontal rules (---) to separate objectives visually

LATEX RULES (CRITICAL):
- Use inline LaTeX ($...$) for short symbols, variables, or very short expressions (e.g. $F$, $a$, $\Delta v$, $E=mc^2$)
- Use display LaTeX ($$...$$) for any formula, derivation, or calculation longer than a short expression
- If a calculation requires multiple steps, place each step on its own display equation
- Never place long equations or derivations inside a sentence
- Keep each display equation on its own line
- ALWAYS wrap text/units inside \\text{} within math mode
  - WRONG: $4200 J kg^{-1} K^{-1}$
  - RIGHT: $4200\\text{ J kg}^{-1}\\text{K}^{-1}$
- For temperatures: $20^\\circ\\text{C}$ (NOT $20^\\circ C$)
- Put space BEFORE and AFTER each $ delimiter
- Separate multiple formulas with newlines, not on same line
- NEVER use commas inside large numbers for formulas or calculations. Output 30000 instead of 30,000
- Attach multipliers directly to numbers without spaces. Write $10000\\times$ instead of $10000 \\times$
- NEVER use macros like \\mu or \\text{\\mu m} for units. Write them out using standard characters (um, mm, or raw symbols like µm)

EXAMPLE STRUCTURE:
## Objective 1: [objective text]

[Clear explanation with **bold key terms**]

> Real-world example: [ZIMSEC-relevant context]

Key formula:
$$\\text{[formula]}$$

**Mini-summary:** [1-2 sentence summary]

---

## Objective 2: [objective text]

...

DO NOT ask questions or test the student. Just TEACH.

RESPOND AS PLAIN TEXT (markdown formatting is expected). Do NOT repeat or acknowledge these instructions.`;

  const contents: any[] = [];

  // Add recent conversation for continuity
  for (const msg of orderedHistory.slice(-6)) {
    if (msg.role === 'student') {
      contents.push({ role: "user", parts: [{ text: msg.content }] });
    } else if (msg.role === 'expert' && msg.content) {
      contents.push({ role: "model", parts: [{ text: msg.content }] });
    }
  }

  // Add the teaching request
  contents.push({
    role: "user",
    parts: [{ text: isFirstBatch 
      ? "Please start teaching me these objectives."
      : "Please teach me the next set of objectives. Continue naturally from our last conversation." }],
  });

  // Model chain
  const modelChain = ["gemini-2.5-flash", "gemini-2.5-flash-lite", "gemini-3.1-flash-lite"];
  let responseStream: any = null;
  let activeModelUsed = "";

  for (const modelName of modelChain) {
    try {
      console.log(`Teaching connecting to: ${modelName}...`);
      responseStream = await ai.models.generateContentStream({
        model: modelName,
        contents: contents,
        config: {
          systemInstruction: systemInstruction,
          temperature: 0.4,
          maxOutputTokens: 8000,
        },
      });
      activeModelUsed = modelName;
      break;
    } catch (error: any) {
      console.warn(`⚠️ ${modelName} failed:`, error.message || error);
      continue;
    }
  }

  if (!responseStream) {
    return new Response(JSON.stringify({ error: "All models failed" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const stream = new ReadableStream({
    async start(controller) {
      try {
        controller.enqueue(`data: ${JSON.stringify({ meta: { model: activeModelUsed } })}\n\n`);
        for await (const chunk of responseStream) {
          const text = chunk.text;
          if (text) {
            controller.enqueue(`data: ${JSON.stringify({ text })}\n\n`);
          }
        }
      } catch (streamError) {
        console.error('🔴 Teaching stream error:', streamError);
      } finally {
        controller.enqueue('data: [DONE]\n\n');
        controller.close();
      }
    }
  });

  const encodedStream = stream.pipeThrough(new TextEncoderStream());

  return new Response(encodedStream, {
    headers: {
      ...corsHeaders,
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      "Connection": "keep-alive",
      "X-Accel-Buffering": "no"
    },
  });
}
// ==========================================
// 2. GRADE ANSWER
// ==========================================
async function handleGradeAnswer(body: any, corsHeaders: Record<string, string>) {
  const { questionText, studentAnswer, correctAnswer, markingScheme, objectiveText, questionType, commandWord } = body;
  console.log(`🔵 Grading ${questionType || 'text'} answer`);

  if (questionType === 'mcq') {
    const isCorrect = studentAnswer.trim().toUpperCase() === correctAnswer.trim().toUpperCase();
    return new Response(JSON.stringify({
      is_correct: isCorrect,
      marks_awarded: isCorrect ? 1 : 0,
      marks_total: 1,
      feedback: isCorrect ? '✅ Correct! Well done!' : `❌ Incorrect. The correct answer is ${correctAnswer}.`,
      hint: isCorrect ? '' : `Think about why ${correctAnswer} is correct.`,
    }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const prompt = `You are grading a ZIMSEC ${questionType || 'structured'} question.

QUESTION: ${questionText}

STUDENT'S ANSWER: ${studentAnswer}

COMMAND WORD: ${commandWord || 'explain'}

${correctAnswer ? `MODEL ANSWER: ${correctAnswer}` : ''}

${markingScheme ? `MARKING SCHEME: ${markingScheme}` : 'No formal marking scheme provided.'}

OBJECTIVE: ${objectiveText || 'General learning'}

Return JSON:
{
  "is_correct": true/false,
  "marks_awarded": X,
  "marks_total": Y,
  "feedback": "Specific feedback",
  "hint": "A hint to help",
  "key_points_covered": ["point1"],
  "key_points_missed": ["point1"]
}`;

  const modelChain = ["gemini-2.5-flash", "gemini-3.5-flash"];
  let responseData: any = null;
  let activeModelUsed = "";

  for (const modelName of modelChain) {
    try {
      responseData = await ai.models.generateContent({
        model: modelName,
        contents: [{ role: "user", parts: [{ text: prompt }] }],
        config: { temperature: 0.3, maxOutputTokens: 2000 },
      });
      activeModelUsed = modelName;
      break;
    } catch (error: any) {
      console.warn(`⚠️ Model ${modelName} failed:`, error.message || error);
      continue;
    }
  }

  const fullText = responseData?.text || '';
  let parsedResponse: any;

  try {
    const jsonMatch = fullText.match(/```json\s*([\s\S]*?)\s*```/);
    const jsonStr = jsonMatch ? jsonMatch[1] : fullText;
    parsedResponse = JSON.parse(jsonStr);
  } catch {
    parsedResponse = {
      is_correct: false,
      marks_awarded: 0,
      marks_total: 5,
      feedback: fullText || 'Could not grade answer',
      hint: '',
      key_points_covered: [],
      key_points_missed: [],
    };
  }

  return new Response(JSON.stringify({ ...parsedResponse, meta: { model: activeModelUsed } }), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// ==========================================
// 3. GRADE HANDWRITTEN
// ==========================================
async function handleGradeHandwritten(body: any, corsHeaders: Record<string, string>) {
  const { imageUrl, questionText, correctAnswer, markingScheme, commandWord, objectiveText } = body;
  console.log('🔵 Grading handwritten answer');

  const prompt = `You are grading a handwritten ZIMSEC answer.

QUESTION: ${questionText}

COMMAND WORD: ${commandWord || 'explain'}

${correctAnswer ? `MODEL ANSWER: ${correctAnswer}` : ''}

${markingScheme ? `MARKING SCHEME: ${markingScheme}` : 'No formal marking scheme.'}

OBJECTIVE: ${objectiveText || 'General learning'}

Return JSON:
{
  "transcribed_answer": "...",
  "is_correct": true/false,
  "marks_awarded": X,
  "marks_total": Y,
  "correct_steps": ["step1"],
  "mistakes": ["mistake1"],
  "feedback": "Feedback",
  "hint": "Hint"
}`;

  const modelChain = ["gemini-2.5-flash", "gemini-3.5-flash"];
  let responseData: any = null;
  let activeModelUsed = "";

  for (const modelName of modelChain) {
    try {
      responseData = await ai.models.generateContent({
        model: modelName,
        contents: [
          {
            role: "user",
            parts: [
              { text: prompt },
              { fileData: { fileUri: imageUrl, mimeType: "image/jpeg" } },
            ],
          },
        ],
        config: { temperature: 0.3, maxOutputTokens: 2000 },
      });
      activeModelUsed = modelName;
      break;
    } catch (error: any) {
      console.warn(`⚠️ Model ${modelName} failed:`, error.message || error);
      continue;
    }
  }

  const fullText = responseData?.text || '';
  let parsedResponse: any;

  try {
    const jsonMatch = fullText.match(/```json\s*([\s\S]*?)\s*```/);
    const jsonStr = jsonMatch ? jsonMatch[1] : fullText;
    parsedResponse = JSON.parse(jsonStr);
  } catch {
    parsedResponse = {
      transcribed_answer: '',
      is_correct: false,
      marks_awarded: 0,
      marks_total: 5,
      correct_steps: [],
      mistakes: ['Could not parse answer'],
      feedback: fullText || 'Could not grade answer',
      hint: '',
    };
  }

  return new Response(JSON.stringify({ ...parsedResponse, meta: { model: activeModelUsed } }), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// ==========================================
// 4. LOAD QUESTIONS
// ==========================================
async function handleLoadQuestions(body: any, corsHeaders: Record<string, string>) {
  const { topicId, difficulty, count = 1 } = body;
  console.log(`🔵 Loading ${difficulty} questions for topic: ${topicId}`);

  const { data: questions, error } = await supabase
    .from('question_bank')
    .select('*')
    .eq('topic_id', topicId)
    .eq('difficulty', difficulty)
    .eq('is_approved', true)
    .limit(count);

  if (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  if (!questions || questions.length === 0) {
    const { data: fallbackQuestions } = await supabase
      .from('question_bank')
      .select('*')
      .eq('topic_id', topicId)
      .eq('is_approved', true)
      .limit(count);
    
    return new Response(JSON.stringify({ 
      questions: fallbackQuestions || [],
      note: 'Fallback: no questions found for specified difficulty'
    }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  return new Response(JSON.stringify({ questions }), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}