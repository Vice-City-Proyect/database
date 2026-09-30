-- ==============================================================================
-- DATOS DE PRUEBA (SEED DATA)
-- Basado en el esquema relacional real
-- ==============================================================================

-- 1. INSERTAR ROLES (Si no existen por el esquema)
INSERT INTO public.roles (id, name, description, permissions) VALUES
  ('11111111-1111-1111-1111-111111111111', 'admin', 'Administrador con acceso total', '{"all": true}'::jsonb),
  ('22222222-2222-2222-2222-222222222222', 'staff', 'Personal de soporte y validación', '{"bookings": true, "tickets": true}'::jsonb),
  ('33333333-3333-3333-3333-333333333333', 'customer', 'Cliente final', '{}'::jsonb)
ON CONFLICT (name) DO NOTHING;


-- 2. INSERTAR USUARIOS
INSERT INTO public.users (id, role_id, email, password_hash, full_name, phone, document_id, is_active) VALUES
  (
    'a1111111-1111-1111-1111-111111111111',
    '11111111-1111-1111-1111-111111111111', -- admin
    'admin@sistema.com',
    '$2b$10$EixZaYVK1fsbw1ZfbX3OXePaWxn96p36WQoeG6Lruj3vjPGga31lW',
    'Carlos Administrador',
    '+573001234567',
    '1010203040',
    true
  ),
  (
    'a2222222-2222-2222-2222-222222222222',
    '22222222-2222-2222-2222-222222222222', -- staff
    'staff@sistema.com',
    '$2b$10$EixZaYVK1fsbw1ZfbX3OXePaWxn96p36WQoeG6Lruj3vjPGga31lW',
    'Laura Validadora',
    '+573009876543',
    '5060708090',
    true
  ),
  (
    'a3333333-3333-3333-3333-333333333333',
    '33333333-3333-3333-3333-333333333333', -- customer
    'cliente@sistema.com',
    '$2b$10$EixZaYVK1fsbw1ZfbX3OXePaWxn96p36WQoeG6Lruj3vjPGga31lW',
    'Juan Pérez',
    '+573115551234',
    '1122334455',
    true
  )
ON CONFLICT (id) DO NOTHING;


-- 3. INSERTAR CATEGORÍAS
INSERT INTO public.categories (id, name, slug, description, sort_order, is_active) VALUES
  (
    'c1111111-1111-1111-1111-111111111111',
    'Consultoría y Asesorías',
    'consultoria-y-asesorias',
    'Servicios profesionales de consultoría técnica y de negocio.',
    1,
    true
  ),
  (
    'c2222222-2222-2222-2222-222222222222',
    'Eventos y Talleres',
    'eventos-y-talleres',
    'Sesiones de capacitación presenciales y virtuales.',
    2,
    true
  )
ON CONFLICT (id) DO NOTHING;


-- 4. INSERTAR SERVICIOS
INSERT INTO public.services (id, category_id, name, slug, description, price, currency, duration_minutes, capacity, is_active) VALUES
  (
    's1111111-1111-1111-1111-111111111111',
    'c1111111-1111-1111-1111-111111111111', -- Consultoría
    'Asesoría Técnica Individual',
    'asesoria-tecnica-individual',
    'Sesión privada uno a uno para arquitectura de software.',
    150000.00,
    'COP',
    60,
    1,
    true
  ),
  (
    's2222222-2222-2222-2222-222222222222',
    'c2222222-2222-2222-2222-222222222222', -- Eventos
    'Taller de Desarrollo Web',
    'taller-desarrollo-web',
    'Curso intensivo en vivo sobre frameworks modernos.',
    85000.00,
    'COP',
    120,
    20,
    true
  )
ON CONFLICT (id) DO NOTHING;


-- 5. INSERTAR HORARIOS DE SERVICIO (SERVICE SCHEDULES)
-- day_of_week: 1 = Lunes, 3 = Miércoles
INSERT INTO public.service_schedules (id, service_id, day_of_week, start_time, end_time, is_active) VALUES
  (
    'h1111111-1111-1111-1111-111111111111',
    's1111111-1111-1111-1111-111111111111',
    1, -- Lunes
    '09:00:00',
    '10:00:00',
    true
  ),
  (
    'h2222222-2222-2222-2222-222222222222',
    's2222222-2222-2222-2222-222222222222',
    3, -- Miércoles
    14:00:00',
    '16:00:00',
    true
  )
ON CONFLICT (id) DO NOTHING;


-- 6. INSERTAR RESERVAS (BOOKINGS)
INSERT INTO public.bookings (id, user_id, service_id, schedule_id, start_at, end_at, quantity, total_amount, status, notes) VALUES
  (
    'b1111111-1111-1111-1111-111111111111',
    'a3333333-3333-3333-3333-333333333333', -- Cliente Juan
    's1111111-1111-1111-1111-111111111111', -- Asesoría
    'h1111111-1111-1111-1111-111111111111',
    '22026-10-05 09:00:00+00',
    '2026-10-05 10:00:00+00',
    1,
    150000.00,
    'confirmed',
    'Reserva confirmada y pagada'
  )
ON CONFLICT (id) DO NOTHING;


-- 7. INSERTAR PAGOS (PAYMENTS)
INSERT INTO public.payments (id, booking_id, amount, currency, method, status, provider, provider_reference, paid_at) VALUES
  (
    'p1111111-1111-1111-1111-111111111111',
    'b1111111-1111-1111-1111-111111111111',
    150000.00,
    'COP',
    'card',
    'approved',
    'wompi',
    'TRANSACTION-REF-001',
    '2026-09-28 15:30:00+00'
  )
ON CONFLICT (id) DO NOTHING;


-- 8. INSERTAR TICKET (TICKETS)
INSERT INTO public.tickets (id, booking_id, code, holder_name, status, valid_from, valid_until) VALUES
  (
    't1111111-1111-1111-1111-111111111111',
    'b1111111-1111-1111-1111-111111111111',
    'TCK-2026-0001',
    'Juan Pérez',
    'valid',
    '2026-10-05 08:30:00+00',
    '2026-10-05 10:30:00+00'
  )
ON CONFLICT (id) DO NOTHING;


-- 9. INSERTAR REGISTRO DE ACCESO (ACCESS_LOGS)
INSERT INTO public.access_logs (id, ticket_id, scanned_by, result, reason, access_point) VALUES
  (
    'l1111111-1111-1111-1111-111111111111',
    't1111111-1111-1111-1111-111111111111',
    'a2222222-2222-2222-2222-222222222222', -- Escaneado por Staff Laura
    'granted',
    'Ingreso autorizado',
    'Torniquete Principal'
  )
ON CONFLICT (id) DO NOTHING;