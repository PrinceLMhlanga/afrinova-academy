BEGIN;

-- Enable gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Notifications table stores per-user notifications (in-app inbox)
CREATE TABLE IF NOT EXISTS public.notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
  type text NOT NULL,
  title text NOT NULL,
  body text,
  data jsonb DEFAULT '{}'::jsonb,
  is_read boolean NOT NULL DEFAULT false,
  channels text[] NOT NULL DEFAULT ARRAY[]::text[], -- e.g. ['in_app','push','email']
  created_at timestamptz NOT NULL DEFAULT now(),
  delivered_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_notifications_user_id_created_at ON public.notifications (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_is_read ON public.notifications (is_read);

-- Helper function to create a notification from SQL/Triggers
CREATE OR REPLACE FUNCTION public.create_notification(
  p_user_id uuid,
  p_type text,
  p_title text,
  p_body text DEFAULT NULL,
  p_data jsonb DEFAULT '{}'::jsonb,
  p_channels text[] DEFAULT ARRAY['in_app']::text[]
) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO public.notifications(id, user_id, type, title, body, data, channels)
  VALUES (gen_random_uuid(), p_user_id, p_type, p_title, p_body, p_data, p_channels)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

COMMIT;
