-- =====================================================================
-- ESQUEMA COMPLETO - Next.js + Supabase (PostgreSQL)
-- Ejecutar completo en el SQL Editor de Supabase.
-- Idempotente: puede ejecutarse más de una vez sin errores.
-- =====================================================================


-- =====================================================================
-- 1. EXTENSIONES
-- btree_gist permite combinar igualdad (uuid) + rangos en una
-- EXCLUDE constraint (evita reservas solapadas).
-- =====================================================================
CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA extensions;


-- =====================================================================
-- 2. FUNCIONES (todas con search_path vacío)
-- =====================================================================

-- 2.1 Mantiene updated_at al día
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

-- 2.2 Libera reservas "pending" cuya retención (expires_at) ya venció.
--     Devuelve la cantidad de reservas liberadas.
--     Llamar desde el backend (RPC con service role) o programar con pg_cron.
CREATE OR REPLACE FUNCTION public.release_expired_bookings()
RETURNS integer
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  released integer;
BEGIN
  UPDATE public.bookings
     SET status = 'expired',
         updated_at = now()
   WHERE status = 'pending'
     AND expires_at IS NOT NULL
     AND expires_at < now();

  GET DIAGNOSTICS released = ROW_COUNT;
  RETURN released;
END;
$$;

-- Solo el backend (service_role) puede ejecutar la función vía RPC
REVOKE EXECUTE ON FUNCTION public.release_expired_bookings() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.release_expired_bookings() TO service_role;


-- =====================================================================
-- 3. TABLAS
-- =====================================================================

-- 3.1 ROLES -----------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.roles (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  name        text        NOT NULL UNIQUE,
  description text,
  permissions jsonb       NOT NULL DEFAULT '{}'::jsonb,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT roles_name_not_blank CHECK (length(trim(name)) > 0)
);

-- 3.2 USERS -----------------------------------------------------------
-- RESTRICT en role_id: borrar un rol no debe borrar usuarios en masa.
CREATE TABLE IF NOT EXISTS public.users (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  role_id       uuid        NOT NULL REFERENCES public.roles(id) ON DELETE RESTRICT,
  email         text        NOT NULL,
  password_hash text,
  full_name     text        NOT NULL,
  phone         text,
  document_id   text,
  is_active     boolean     NOT NULL DEFAULT true,
  last_login_at timestamptz,
  metadata      jsonb       NOT NULL DEFAULT '{}'::jsonb,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT users_email_format CHECK (position('@' in email) > 1),
  CONSTRAINT users_full_name_not_blank CHECK (length(trim(full_name)) > 0)
);
CREATE UNIQUE INDEX IF NOT EXISTS users_email_lower_uidx ON public.users (lower(email));
CREATE INDEX IF NOT EXISTS users_role_id_idx ON public.users (role_id);

-- 3.3 CATEGORIES ------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.categories (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  name        text        NOT NULL,
  slug        text        NOT NULL UNIQUE,
  description text,
  sort_order  integer     NOT NULL DEFAULT 0,
  is_active   boolean     NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT categories_name_not_blank CHECK (length(trim(name)) > 0)
);

-- 3.4 SERVICES --------------------------------------------------------
-- RESTRICT en category_id: no se borra una categoría que tenga servicios.
CREATE TABLE IF NOT EXISTS public.services (
  id               uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  category_id      uuid          NOT NULL REFERENCES public.categories(id) ON DELETE RESTRICT,
  name             text          NOT NULL,
  slug             text          NOT NULL UNIQUE,
  description      text,
  price            numeric(12,2) NOT NULL,
  currency         char(3)       NOT NULL DEFAULT 'COP',
  duration_minutes integer       NOT NULL DEFAULT 60,
  capacity         integer       NOT NULL DEFAULT 1,
  image_url        text,
  is_active        boolean       NOT NULL DEFAULT true,
  metadata         jsonb         NOT NULL DEFAULT '{}'::jsonb,
  created_at       timestamptz   NOT NULL DEFAULT now(),
  updated_at       timestamptz   NOT NULL DEFAULT now(),
  CONSTRAINT services_price_positive    CHECK (price > 0),
  CONSTRAINT services_duration_positive CHECK (duration_minutes > 0),
  CONSTRAINT services_capacity_positive CHECK (capacity > 0),
  CONSTRAINT services_name_not_blank    CHECK (length(trim(name)) > 0)
);
CREATE INDEX IF NOT EXISTS services_category_id_idx ON public.services (category_id);
CREATE INDEX IF NOT EXISTS services_active_idx      ON public.services (is_active) WHERE is_active;

-- 3.5 SERVICE_SCHEDULES -----------------------------------------------
-- day_of_week: 0 = domingo ... 6 = sábado
CREATE TABLE IF NOT EXISTS public.service_schedules (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  service_id  uuid        NOT NULL REFERENCES public.services(id) ON DELETE CASCADE,
  day_of_week smallint    NOT NULL,
  start_time  time        NOT NULL,
  end_time    time        NOT NULL,
  valid_from  date,
  valid_until date,
  is_active   boolean     NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT schedules_day_range   CHECK (day_of_week BETWEEN 0 AND 6),
  CONSTRAINT schedules_time_range  CHECK (end_time > start_time),
  CONSTRAINT schedules_date_range  CHECK (valid_until IS NULL OR valid_from IS NULL OR valid_until >= valid_from),
  CONSTRAINT schedules_unique_slot UNIQUE (service_id, day_of_week, start_time)
);
CREATE INDEX IF NOT EXISTS service_schedules_service_id_idx ON public.service_schedules (service_id);

-- 3.6 BOOKINGS --------------------------------------------------------
-- RESTRICT en user_id y service_id: se conserva el historial de reservas.
-- La EXCLUDE constraint impide que dos reservas activas (pending/confirmed)
-- del mismo servicio se solapen en el tiempo (modelo de cupo exclusivo).
-- Si necesitas varios cupos simultáneos por servicio (capacity > 1),
-- elimina la constraint bookings_no_overlap y valida el cupo en el backend.
CREATE TABLE IF NOT EXISTS public.bookings (
  id                  uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             uuid          NOT NULL REFERENCES public.users(id)    ON DELETE RESTRICT,
  service_id          uuid          NOT NULL REFERENCES public.services(id) ON DELETE RESTRICT,
  schedule_id         uuid                   REFERENCES public.service_schedules(id) ON DELETE SET NULL,
  start_at            timestamptz   NOT NULL,
  end_at              timestamptz   NOT NULL,
  quantity            integer       NOT NULL DEFAULT 1,
  total_amount        numeric(12,2) NOT NULL,
  status              text          NOT NULL DEFAULT 'pending',
  expires_at          timestamptz,
  notes               text,
  cancelled_at        timestamptz,
  cancellation_reason text,
  metadata            jsonb         NOT NULL DEFAULT '{}'::jsonb,
  created_at          timestamptz   NOT NULL DEFAULT now(),
  updated_at          timestamptz   NOT NULL DEFAULT now(),
  CONSTRAINT bookings_date_range      CHECK (end_at > start_at),
  CONSTRAINT bookings_quantity_pos    CHECK (quantity > 0),
  CONSTRAINT bookings_amount_nonneg   CHECK (total_amount >= 0),
  CONSTRAINT bookings_status_valid    CHECK (status IN ('pending','confirmed','cancelled','completed','expired','no_show')),
  CONSTRAINT bookings_no_overlap EXCLUDE USING gist (
    service_id WITH =,
    tstzrange(start_at, end_at, '[)') WITH &&
  ) WHERE (status IN ('pending','confirmed'))
);
CREATE INDEX IF NOT EXISTS bookings_user_id_idx     ON public.bookings (user_id);
CREATE INDEX IF NOT EXISTS bookings_service_id_idx  ON public.bookings (service_id);
CREATE INDEX IF NOT EXISTS bookings_schedule_id_idx ON public.bookings (schedule_id);
CREATE INDEX IF NOT EXISTS bookings_status_idx      ON public.bookings (status);
CREATE INDEX IF NOT EXISTS bookings_start_at_idx    ON public.bookings (start_at);
CREATE INDEX IF NOT EXISTS bookings_pending_expiry_idx
  ON public.bookings (expires_at) WHERE status = 'pending';

-- 3.7 PAYMENTS --------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.payments (
  id                 uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id         uuid          NOT NULL REFERENCES public.bookings(id) ON DELETE CASCADE,
  amount             numeric(12,2) NOT NULL,
  currency           char(3)       NOT NULL DEFAULT 'COP',
  method             text          NOT NULL,
  status             text          NOT NULL DEFAULT 'pending',
  provider           text,
  provider_reference text,
  paid_at            timestamptz,
  raw_response       jsonb         NOT NULL DEFAULT '{}'::jsonb,
  created_at         timestamptz   NOT NULL DEFAULT now(),
  updated_at         timestamptz   NOT NULL DEFAULT now(),
  CONSTRAINT payments_amount_positive CHECK (amount > 0),
  CONSTRAINT payments_method_valid    CHECK (method IN ('card','pse','cash','transfer','wallet','other')),
  CONSTRAINT payments_status_valid    CHECK (status IN ('pending','processing','approved','rejected','failed','cancelled','refunded'))
);
CREATE INDEX IF NOT EXISTS payments_booking_id_idx ON public.payments (booking_id);
CREATE INDEX IF NOT EXISTS payments_status_idx     ON public.payments (status);
-- Evita registrar dos veces la misma transacción de una pasarela
CREATE UNIQUE INDEX IF NOT EXISTS payments_provider_ref_uidx
  ON public.payments (provider, provider_reference)
  WHERE provider IS NOT NULL AND provider_reference IS NOT NULL;

-- 3.8 TICKETS ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.tickets (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id   uuid        NOT NULL REFERENCES public.bookings(id) ON DELETE CASCADE,
  code         text        NOT NULL UNIQUE DEFAULT replace(gen_random_uuid()::text, '-', ''),
  holder_name  text,
  status       text        NOT NULL DEFAULT 'valid',
  valid_from   timestamptz,
  valid_until  timestamptz,
  used_at      timestamptz,
  metadata     jsonb       NOT NULL DEFAULT '{}'::jsonb,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT tickets_status_valid CHECK (status IN ('valid','used','cancelled','expired')),
  CONSTRAINT tickets_date_range   CHECK (valid_until IS NULL OR valid_from IS NULL OR valid_until > valid_from)
);
CREATE INDEX IF NOT EXISTS tickets_booking_id_idx ON public.tickets (booking_id);
CREATE INDEX IF NOT EXISTS tickets_status_idx     ON public.tickets (status);

-- 3.9 ACCESS_LOGS -----------------------------------------------------
-- Bitácora de validaciones/escaneos. Si se borra un usuario se conserva el log.
CREATE TABLE IF NOT EXISTS public.access_logs (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id    uuid        NOT NULL REFERENCES public.tickets(id) ON DELETE CASCADE,
  scanned_by   uuid                 REFERENCES public.users(id)   ON DELETE SET NULL,
  result       text        NOT NULL,
  reason       text,
  access_point text,
  ip_address   inet,
  metadata     jsonb       NOT NULL DEFAULT '{}'::jsonb,
  created_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT access_logs_result_valid CHECK (result IN ('granted','denied'))
);
CREATE INDEX IF NOT EXISTS access_logs_ticket_id_idx  ON public.access_logs (ticket_id);
CREATE INDEX IF NOT EXISTS access_logs_scanned_by_idx ON public.access_logs (scanned_by);
CREATE INDEX IF NOT EXISTS access_logs_created_at_idx ON public.access_logs (created_at DESC);


-- =====================================================================
-- 4. TRIGGERS updated_at
-- =====================================================================
DROP TRIGGER IF EXISTS trg_roles_updated_at     ON public.roles;
CREATE TRIGGER trg_roles_updated_at     BEFORE UPDATE ON public.roles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_users_updated_at     ON public.users;
CREATE TRIGGER trg_users_updated_at     BEFORE UPDATE ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_categories_updated_at ON public.categories;
CREATE TRIGGER trg_categories_updated_at BEFORE UPDATE ON public.categories
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_services_updated_at  ON public.services;
CREATE TRIGGER trg_services_updated_at  BEFORE UPDATE ON public.services
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_service_schedules_updated_at ON public.service_schedules;
CREATE TRIGGER trg_service_schedules_updated_at BEFORE UPDATE ON public.service_schedules
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_bookings_updated_at  ON public.bookings;
CREATE TRIGGER trg_bookings_updated_at  BEFORE UPDATE ON public.bookings
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_payments_updated_at  ON public.payments;
CREATE TRIGGER trg_payments_updated_at  BEFORE UPDATE ON public.payments
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_tickets_updated_at   ON public.tickets;
CREATE TRIGGER trg_tickets_updated_at   BEFORE UPDATE ON public.tickets
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


-- =====================================================================
-- 5. ROW LEVEL SECURITY
-- 5.1 Habilitar RLS en todas las tablas (Linter: "RLS Disabled in Public")
-- =====================================================================
ALTER TABLE public.roles             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.services          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.service_schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bookings          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tickets           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.access_logs       ENABLE ROW LEVEL SECURITY;

-- 5.2 Política totalmente permisiva (USING true / WITH CHECK true) por tabla
--     (Linter: "RLS Enabled No Policy").
--     Se asigna TO service_role: es el rol que usa tu backend, así la
--     política es 100% permisiva para él y NO se abren los datos a la
--     anon key pública de Supabase.
DROP POLICY IF EXISTS "backend_full_access" ON public.roles;
CREATE POLICY "backend_full_access" ON public.roles
  FOR ALL TO service_role USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "backend_full_access" ON public.users;
CREATE POLICY "backend_full_access" ON public.users
  FOR ALL TO service_role USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "backend_full_access" ON public.categories;
CREATE POLICY "backend_full_access" ON public.categories
  FOR ALL TO service_role USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "backend_full_access" ON public.services;
CREATE POLICY "backend_full_access" ON public.services
  FOR ALL TO service_role USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "backend_full_access" ON public.service_schedules;
CREATE POLICY "backend_full_access" ON public.service_schedules
  FOR ALL TO service_role USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "backend_full_access" ON public.bookings;
CREATE POLICY "backend_full_access" ON public.bookings
  FOR ALL TO service_role USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "backend_full_access" ON public.payments;
CREATE POLICY "backend_full_access" ON public.payments
  FOR ALL TO service_role USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "backend_full_access" ON public.tickets;
CREATE POLICY "backend_full_access" ON public.tickets
  FOR ALL TO service_role USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "backend_full_access" ON public.access_logs;
CREATE POLICY "backend_full_access" ON public.access_logs
  FOR ALL TO service_role USING (true) WITH CHECK (true);

-- 5.3 Defensa en profundidad: los roles públicos de la API no tocan las tablas
REVOKE ALL ON TABLE
  public.roles, public.users, public.categories, public.services,
  public.service_schedules, public.bookings, public.payments,
  public.tickets, public.access_logs
FROM anon, authenticated;


-- =====================================================================
-- 6. DATOS INICIALES (roles base)
-- =====================================================================
INSERT INTO public.roles (name, description, permissions) VALUES
  ('admin',    'Administrador con acceso total',            '{"all": true}'::jsonb),
  ('staff',    'Personal que valida accesos y gestiona reservas', '{"bookings": true, "tickets": true}'::jsonb),
  ('customer', 'Cliente final',                             '{}'::jsonb)
ON CONFLICT (name) DO NOTHING;

-- =====================================================================
-- FIN DEL SCRIPT
-- Opcional: programar la liberación de bloqueos expirados con pg_cron:
--   SELECT cron.schedule('release-expired-bookings', '* * * * *',
--                        $$SELECT public.release_expired_bookings();$$);
-- =====================================================================
