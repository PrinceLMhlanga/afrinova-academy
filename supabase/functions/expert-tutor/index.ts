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
  const { sessionId, message, currentObjectiveId, studentId } = body;
  console.log(`🔵 Expert chat stream request for session: ${sessionId}`);

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

  // ✅ Get conversation history (last 15 messages)
  const { data: chatHistory } = await supabase
    .from('expert_tutor_messages')
    .select('*')
    .eq('session_id', sessionId)
    .order('created_at', { ascending: false })
    .limit(15);

  // Reverse to chronological order
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

  // Build progress summary
  const { data: objectivesProgress } = await supabase
    .from('expert_tutor_progress')
    .select('*')
    .eq('student_id', studentId)
    .eq('topic_id', session.topic_id);

  const masteredObjectives = (objectivesProgress || []).filter((p: any) => p.is_mastered).length;
  const totalObjectives = (allObjectives || []).length;

  const systemPrompt = `You are the AfriNova Expert Tutor, a warm and practical ZIMSEC/Cambridge teacher.

CURRENT CONTEXT:
- Subject: ${session.subjects?.name || 'Unknown'}
- Level: ${session.levels?.name || 'Unknown'}
- Topic: ${session.topics?.name || 'Unknown'}
- Current Objective: ${objective?.objective_text || 'General learning'}
- Command Word: ${objective?.command_word || 'understand'}
- SubTopic: ${objective?.subtopic_name || 'General'}

OVERALL PROGRESS:
- Objectives Mastered: ${masteredObjectives}/${totalObjectives}
- Current Difficulty: ${progress?.difficulty_reached || 'easy'}
- Easy: ${progress?.correct_easy || 0}/${progress?.attempts_easy || 0} correct
- Medium: ${progress?.correct_medium || 0}/${progress?.attempts_medium || 0} correct
- Hard: ${progress?.correct_hard || 0}/${progress?.attempts_hard || 0} correct
- Exam: ${progress?.correct_exam || 0}/${progress?.attempts_exam || 0} correct

ALL OBJECTIVES IN THIS TOPIC:
${(allObjectives || []).map((obj: any, i: number) => `${i + 1}. ${obj.objective_text}`).join('\n')}

HOW TO RESPOND TO STUDENT ANSWERS:

✅ CORRECT ANSWER:
"Very good! You got it right!"
Then INCREASE difficulty and ask a HARDER question.

👍 CLOSE ANSWER (80% correct):
"Good job! You got [what they got right]. Also add [missing point(s)]."
Provide the complete answer briefly.
Then ask a SIMILAR difficulty question.

🤔 PARTIALLY CORRECT (50% correct):
"Good start! You mentioned [correct part]. Let me add [missing key points]."
Explain clearly.
Ask ONE more question at the SAME difficulty.

❌ WRONG (First attempt):
"Not quite. Here's a hint: [specific hint]."
Let them try once more.

❌ WRONG AGAIN (Second attempt):
"No worries! Here's the answer: [clear explanation]."
Ask a similar question at the SAME difficulty.

❌ WRONG THIRD TIME:
"Let's move on. You can revise this objective later."
Move to the next objective WITHOUT marking as mastered.
Do NOT use [OBJECTIVE_MASTERED].

DIFFICULTY PROGRESSION:
- Start with EASY questions
- After 2 correct EASY → Move to MEDIUM
- After 2 correct MEDIUM → Move to HARD
- After 1-2 correct HARD → Generate EXAM-STYLE questions
- After 2 EXAM-STYLE questions correct → Congratulate student, give next objective question and end with [OBJECTIVE_MASTERED]
- For objectives that need student to use a formula, provide detailed questions involving real world calculations using that formula, starting with 2 easy, then 2 medium, 1 hard and 2 very challenging exam questions with mark allocations. 

EXAM-STYLE QUESTIONS:
Generate 2 challenging ZIMSEC past paper style questions with mark allocations per objective.
For objectives that need student to use a formula, provide detailed questions involving real world calculations using that formula, starting with 2 easy, then 2 medium, 1 hard and 2 very challenging exam questions with mark allocations. 


⚠️ CRITICAL MARKER INSTRUCTIONS:

WHEN OBJECTIVE IS MASTERED - DO THIS IN ONE MESSAGE:

1. Congratulate the student
2. Tell them the objective is mastered
3. Introduce the next objective
4. Ask the FIRST question for the next objective
5. END with [OBJECTIVE_MASTERED]

⚠️ CRITICAL - Never write [OBJECTIVE_MASTERED] without including question for the next objective. WE WANT THE LESSON TO KEEP THE LESSON GOING.

EXAMPLE OF A COMPLETE MASTERED MESSAGE:
"Very good! You've mastered this objective!

Let's move to our next objective: calculate the field strength using E = V/d.

Here's your first question:
Two parallel plates are separated by 2.0 cm and connected to a 100V supply. Calculate the electric field strength between the plates.

[OBJECTIVE_MASTERED]"

This way the student sees:
- Confirmation of mastery
- Introduction to next objective
- First question ready to answer
- All in ONE message

When ALL objectives are complete:
END WITH: [TOPIC_COMPLETE]

RESPOND AS PLAIN TEXT`;

  // ✅ Build contents with PROPER conversation structure
  const contents: any[] = [];
  
  // Add system prompt
  contents.push({
    role: "user",
    parts: [{ text: systemPrompt }],
  });
  
  contents.push({
    role: "model",
    parts: [{ text: "I understand. I'll track progress, use the conversation history, and always end with the correct marker when an objective is mastered." }],
  });

  // ✅ Add conversation history (last 10 messages in chronological order)
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

  // Add current student message
  contents.push({
    role: "user",
    parts: [{ text: `Student's answer: ${message}` }],
  });

  // Model chain
  const modelChain = ["gemini-2.5-flash", "gemini-3.5-flash-lite", "gemini-3.6-flash"];
  let responseStream: any = null;
  let activeModelUsed = "";

  for (const modelName of modelChain) {
    try {
      console.log(`Connecting Expert Tutor to: ${modelName}...`);
      responseStream = await ai.models.generateContentStream({
        model: modelName,
        contents: contents,
        config: { temperature: 0.5, maxOutputTokens: 4000 },
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
  const { sessionId, objectivesText, topicName, subjectName, levelName } = body;
  console.log('🔵 Teaching mode for session:', sessionId);

  const systemPrompt = `You are the AfriNova Expert Tutor, an experienced and encouraging ZIMSEC/Cambridge teacher.

YOU ARE IN TEACHING MODE. The student has NOT been assessed yet. Your job is to TEACH, not test.

TEACH THE FOLLOWING OBJECTIVES:
${objectivesText}

CONTEXT:
- Topic: ${topicName || 'Unknown'}
- Subject: ${subjectName || 'Unknown'}
- Level: ${levelName || 'Unknown'}

TEACHING GUIDELINES:
1. Start with a warm welcome and brief overview of what they'll learn
2. Explain each objective clearly with real-world examples
3. Use simple language first, then introduce technical terms
4. Include relevant formulas where applicable (use LaTeX)
5. Use ZIMSEC-relevant examples and contexts
6. Break down complex concepts into steps
7. Include a mini-summary after each objective
8. End with: "You're ready! Click START SESSION when you've understood these concepts."

FORMAT:
Use markdown with:
- ## for each objective
- **Bold** for key terms
- Lists for steps
- $$...$$ for formulas
- Examples in blockquotes
- Keep it student-friendly

DO NOT:
- Do NOT ask questions
- Do NOT test the student
- Do NOT use [EXERCISE:difficulty]
- Do NOT use [OBJECTIVE_MASTERED]
- Do NOT assess

JUST TEACH the concepts clearly.

RESPOND AS PLAIN TEXT`;

  const contents: any[] = [];
  contents.push({
    role: "user",
    parts: [{ text: systemPrompt }],
  });
  contents.push({
    role: "model",
    parts: [{ text: "I understand. I'll teach these objectives clearly without testing." }],
  });

  // Model chain
  const modelChain = ["gemini-2.5-flash", "gemini-2.5-flash-lite", "gemini-3.1-flash-lite"];
  let responseStream: any = null;
  let activeModelUsed = "";

  for (const modelName of modelChain) {
    try {
      console.log(`Connecting Teacher mode to: ${modelName}...`);
      
      responseStream = await ai.models.generateContentStream({
        model: modelName,
        contents: contents,
        config: { 
          temperature: 0.4, 
          maxOutputTokens: 8000 
        },
      });

      activeModelUsed = modelName;
      console.log(`✅ Teacher stream connected: ${activeModelUsed}`);
      break;
    } catch (error: any) {
      console.warn(`⚠️ Model ${modelName} failed:`, error.message || error);
      if (modelName === modelChain[modelChain.length - 1]) {
        return new Response(JSON.stringify({ error: "All models exhausted" }), {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
      continue;
    }
  }

  // Create readable stream
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
        console.error('🔴 Teacher stream error:', streamError);
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