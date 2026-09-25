BEGIN;

CREATE OR REPLACE FUNCTION public.notify_on_event() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_user uuid;
  v_type text;
  v_title text;
  v_body text;
  v_data jsonb;
BEGIN
  -- Payments: notify student about payment status
  IF TG_TABLE_NAME = 'payments' THEN
    v_user := NEW.student_id;
    v_type := 'payment';
    v_title := 'Payment ' || COALESCE(NEW.status, 'updated');
    v_body := 'Payment of ' || COALESCE(NEW.amount::text,'') || ' (ref: ' || COALESCE(NEW.gateway_reference, '') || ')';
    v_data := to_jsonb(NEW);

  -- Enrollments: notify student when enrolled/approved/paid
  ELSIF TG_TABLE_NAME = 'enrollments' THEN
    v_user := NEW.student_id;
    v_type := 'enrollment';
    v_title := 'Enrollment ' || COALESCE(NEW.status, 'created');
    v_body := 'Enrollment for subject ' || COALESCE(NEW.subject_id::text, '') || ' status: ' || COALESCE(NEW.status, '');
    v_data := to_jsonb(NEW);

  -- Exam attempts: notify student when attempt completed
  ELSIF TG_TABLE_NAME = 'exam_attempts' THEN
    IF NEW.completed_at IS NULL THEN
      RETURN NEW;
    END IF;
    v_user := NEW.student_id;
    v_type := 'exam_result';
    v_title := 'Exam results ready';
    v_body := 'Your attempt for exam ' || COALESCE(NEW.exam_id::text, '') || ' is complete.';
    v_data := to_jsonb(NEW);

  -- Live lessons: notify student when a lesson is scheduled
  ELSIF TG_TABLE_NAME = 'live_lessons' THEN
    v_type := 'live_lesson';
    v_title := 'Live lesson scheduled';
    v_body := 'Live lesson by teacher ' || COALESCE(NEW.teacher_id::text, '') || '\nStarts: ' || COALESCE(NEW.starts_at::text, '');
    v_data := to_jsonb(NEW);

    PERFORM (
      SELECT public.create_notification(en.student_id, v_type, v_title, v_body, v_data, ARRAY['in_app'])
      FROM public.enrollments en
      WHERE en.subject_id = NEW.subject_id
    );
    RETURN NEW;

  ELSE
    RETURN NEW;
  END IF;

  IF v_user IS NOT NULL THEN
    PERFORM public.create_notification(v_user, v_type, v_title, v_body, v_data, ARRAY['in_app']);
  END IF;

  RETURN NEW;
END;
$$;

-- Drop the chat trigger to make sure it stops executing completely
DROP TRIGGER IF EXISTS chat_messages_notify_insert ON public.chat_messages;

COMMIT;