BEGIN;

-- Generic trigger function to create notifications for core events
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
      RETURN NEW; -- only notify on completion
    END IF;
    v_user := NEW.student_id;
    v_type := 'exam_result';
    v_title := 'Exam results ready';
    v_body := 'Your attempt for exam ' || COALESCE(NEW.exam_id::text, '') || ' is complete.';
    v_data := to_jsonb(NEW);

  -- Chat messages: notify session student when a new message arrives from someone else
  ELSIF TG_TABLE_NAME = 'chat_messages' THEN
    -- Try to find session owner (student)
    SELECT student_id INTO v_user FROM public.chat_sessions WHERE id = NEW.session_id LIMIT 1;
    IF v_user IS NULL THEN
      RETURN NEW;
    END IF;
    -- Avoid notifying the sender themselves
    IF NEW.sender = v_user::text OR NEW.sender_id = v_user THEN
      RETURN NEW;
    END IF;
    v_type := 'chat_message';
    v_title := 'New message';
    v_body := substring(coalesce(NEW.message, '') for 200);
    v_data := jsonb_build_object('session_id', NEW.session_id, 'message_id', NEW.id);

  -- Live lessons: notify student when a lesson is scheduled
  ELSIF TG_TABLE_NAME = 'live_lessons' THEN
    -- Prefer notifying students via enrollments if there's a student list; fallback to teacher's students
    v_type := 'live_lesson';
    v_title := 'Live lesson scheduled';
    v_body := 'Live lesson by teacher ' || COALESCE(NEW.teacher_id::text, '') || '\nStarts: ' || COALESCE(NEW.starts_at::text, '');
    v_data := to_jsonb(NEW);

    -- Create notifications for all enrolled students (best-effort)
    PERFORM (
      SELECT public.create_notification(en.student_id, v_type, v_title, v_body, v_data, ARRAY['in_app'])
      FROM public.enrollments en
      WHERE en.subject_id = NEW.subject_id
    );
    RETURN NEW;

  ELSE
    RETURN NEW;
  END IF;

  -- Fallback: create notification for a single user
  IF v_user IS NOT NULL THEN
    PERFORM public.create_notification(v_user, v_type, v_title, v_body, v_data, ARRAY['in_app']);
  END IF;

  RETURN NEW;
END;
$$;

-- Attach triggers
DROP TRIGGER IF EXISTS payments_notify_insert ON public.payments;
CREATE TRIGGER payments_notify_insert AFTER INSERT ON public.payments
  FOR EACH ROW EXECUTE FUNCTION public.notify_on_event();

DROP TRIGGER IF EXISTS enrollments_notify_insert ON public.enrollments;
CREATE TRIGGER enrollments_notify_insert AFTER INSERT ON public.enrollments
  FOR EACH ROW EXECUTE FUNCTION public.notify_on_event();

DROP TRIGGER IF EXISTS exam_attempts_notify_insert ON public.exam_attempts;
CREATE TRIGGER exam_attempts_notify_insert AFTER INSERT ON public.exam_attempts
  FOR EACH ROW EXECUTE FUNCTION public.notify_on_event();

DROP TRIGGER IF EXISTS chat_messages_notify_insert ON public.chat_messages;
CREATE TRIGGER chat_messages_notify_insert AFTER INSERT ON public.chat_messages
  FOR EACH ROW EXECUTE FUNCTION public.notify_on_event();

DROP TRIGGER IF EXISTS live_lessons_notify_insert ON public.live_lessons;
CREATE TRIGGER live_lessons_notify_insert AFTER INSERT ON public.live_lessons
  FOR EACH ROW EXECUTE FUNCTION public.notify_on_event();

COMMIT;
