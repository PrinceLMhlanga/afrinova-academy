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

        -- Drop old policies to ensure they are updated
    DROP POLICY IF EXISTS "Users can view own devices" ON public.user_devices;
    DROP POLICY IF EXISTS "Users can insert own devices" ON public.user_devices;
    DROP POLICY IF EXISTS "Users can update own devices" ON public.user_devices;
    DROP POLICY IF EXISTS "Users can delete own devices" ON public.user_devices;

    -- SELECT: Users can see their own devices or any anonymous device
    -- (This allows claiming anonymous devices during login)
    CREATE POLICY "Users can view own devices"
    ON public.user_devices
    FOR SELECT
    USING (auth.uid() = user_id OR user_id IS NULL);

    -- INSERT: 
    -- 1. Authenticated users can insert for themselves
    -- 2. Anonymous users can insert anonymous records
    CREATE POLICY "Users can insert own devices"
    ON public.user_devices
    FOR INSERT
    WITH CHECK (
      (auth.role() = 'authenticated' AND auth.uid() = user_id) OR
      (auth.role() = 'anon' AND user_id IS NULL)
    );

    -- UPDATE:
    -- 1. Users can update their own records
    -- 2. Authenticated users can update anonymous records (to claim them)
    -- 3. Anonymous users can update anonymous records
    CREATE POLICY "Users can update own devices"
    ON public.user_devices
    FOR UPDATE
    USING (auth.uid() = user_id OR user_id IS NULL)
    WITH CHECK (
      (auth.role() = 'authenticated' AND (auth.uid() = user_id OR user_id IS NULL)) OR
      (auth.role() = 'anon' AND user_id IS NULL)
    );

    -- DELETE: Users can only delete their own records
    CREATE POLICY "Users can delete own devices"
    ON public.user_devices
    FOR DELETE
    USING (auth.uid() = user_id);

  END IF;
END $$;

COMMIT;
