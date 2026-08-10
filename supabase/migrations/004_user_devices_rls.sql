BEGIN;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = 'user_devices' AND c.relkind = 'r'
  ) THEN
    ALTER TABLE public.user_devices ENABLE ROW LEVEL SECURITY;

    IF NOT EXISTS (
      SELECT 1
      FROM pg_policies
      WHERE schemaname = 'public'
        AND tablename = 'user_devices'
        AND policyname = 'Users can view own devices'
    ) THEN
      CREATE POLICY "Users can view own devices"
      ON public.user_devices
      FOR SELECT
      USING (auth.uid() = user_id OR auth.uid() IS NULL);
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM pg_policies
      WHERE schemaname = 'public'
        AND tablename = 'user_devices'
        AND policyname = 'Users can insert own devices'
    ) THEN
      CREATE POLICY "Users can insert own devices"
      ON public.user_devices
      FOR INSERT
      WITH CHECK (auth.uid() = user_id OR auth.uid() IS NULL);
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM pg_policies
      WHERE schemaname = 'public'
        AND tablename = 'user_devices'
        AND policyname = 'Users can update own devices'
    ) THEN
      CREATE POLICY "Users can update own devices"
      ON public.user_devices
      FOR UPDATE
      USING (auth.uid() = user_id OR auth.uid() IS NULL)
      WITH CHECK (auth.uid() = user_id OR auth.uid() IS NULL);
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM pg_policies
      WHERE schemaname = 'public'
        AND tablename = 'user_devices'
        AND policyname = 'Users can delete own devices'
    ) THEN
      CREATE POLICY "Users can delete own devices"
      ON public.user_devices
      FOR DELETE
      USING (auth.uid() = user_id OR auth.uid() IS NULL);
    END IF;
  END IF;
END $$;

COMMIT;
