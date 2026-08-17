BEGIN;

CREATE TABLE IF NOT EXISTS public.user_devices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
  token text NOT NULL,
  device_id text,
  platform text NOT NULL,
  is_web boolean NOT NULL DEFAULT false,
  last_seen_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT user_devices_token_key UNIQUE (token)
);

ALTER TABLE public.user_devices
  ADD COLUMN IF NOT EXISTS device_id text;

ALTER TABLE public.user_devices
  ADD COLUMN IF NOT EXISTS last_seen_at timestamptz;

ALTER TABLE public.user_devices
  ADD COLUMN IF NOT EXISTS is_web boolean NOT NULL DEFAULT false;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'user_devices_token_key'
      AND conrelid = 'public.user_devices'::regclass
  ) THEN
    ALTER TABLE public.user_devices
      ADD CONSTRAINT user_devices_token_key UNIQUE (token);
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'user_devices_device_id_key'
      AND conrelid = 'public.user_devices'::regclass
  ) THEN
    ALTER TABLE public.user_devices
      ADD CONSTRAINT user_devices_device_id_key UNIQUE (device_id);
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_user_devices_token ON public.user_devices (token);
CREATE UNIQUE INDEX IF NOT EXISTS idx_user_devices_device_id ON public.user_devices (device_id) WHERE device_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_user_devices_user_token ON public.user_devices (user_id, token);

CREATE OR REPLACE FUNCTION public.user_devices_updated_at_trigger()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS user_devices_updated_at ON public.user_devices;
CREATE TRIGGER user_devices_updated_at
BEFORE UPDATE ON public.user_devices
FOR EACH ROW EXECUTE FUNCTION public.user_devices_updated_at_trigger();

COMMIT;
