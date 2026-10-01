# 📚 Documentación Técnica de Base de Datos

Esta documentación describe la arquitectura relacional, diccionario de datos, restricciones de integridad y políticas de seguridad configuradas en la base de datos PostgreSQL mediante Supabase[cite: 6].

---

## 🎯 Arquitectura General del Sistema

El sistema gestiona el flujo completo de agendamiento y servicios:
1. **Control de Acceso**: Autenticación de usuarios vinculados a roles y permisos (`roles`, `users`)[cite: 6].
2. **Catálogo de Oferta**: Categorización y parametrización de servicios con capacidad y duración (`categories`, `services`)[cite: 6].
3. **Disponibilidad**: Asignación de franjas horarias habilitadas por día de la semana (`service_schedules`)[cite: 6].
4. **Motor de Reservas**: Gestión de solicitudes de agendamiento con prevención de solapamientos mediante `EXCLUDE constraint` (`bookings`)[cite: 6].
5. **Transacciones Financieras**: Registro de pasarelas y estados de pago (`payments`)[cite: 6].
6. **Emisión y Validación**: Generación de boletos y trazabilidad de accesos (`tickets`, `access_logs`)[cite: 6].

---

## 📐 Modelo Relacional

- **`roles` (1) ── (N) `users`**: Un rol define los permisos de múltiples usuarios[cite: 6].
- **`categories` (1) ── (N) `services`**: Una categoría agrupa múltiples servicios[cite: 6].
- **`services` (1) ── (N) `service_schedules`**: Un servicio define sus horarios disponibles[cite: 6].
- **`users` (1) ── (N) `bookings` (N) ── (1) `services`**: Un usuario reserva un servicio en una fecha y hora específica[cite: 6].
- **`bookings` (1) ── (N) `payments`**: Una reserva puede registrar intentos de pago[cite: 6].
- **`bookings` (1) ── (N) `tickets`**: Una reserva confirmada genera uno o más tickets[cite: 6].
- **`tickets` (1) ── (N) `access_logs`**: Un ticket registra el historial de validación o escaneos[cite: 6].

---

## 🗃 Diccionario de Datos

### 1. `public.roles`
Definición de roles y permisos del sistema[cite: 6].

| Columna | Tipo | Restricciones | Descripción |
| :--- | :--- | :--- | :--- |
| `id` | `uuid` | `PRIMARY KEY` | Identificador único del rol[cite: 6] |
| `name` | `text` | `UNIQUE`, `NOT NULL` | Nombre del rol (`admin`, `staff`, `customer`)[cite: 6] |
| `description` | `text` | `NULLABLE` | Descripción operativa[cite: 6] |
| `permissions` | `jsonb` | `NOT NULL`, Default `'{}'` | Objeto con permisos asignados[cite: 6] |
| `created_at` / `updated_at` | `timestamptz` | `NOT NULL` | Control de auditoría[cite: 6] |

---

### 2. `public.users`
Cuentas de usuario registradas[cite: 6].

| Columna | Tipo | Restricciones | Descripción |
| :--- | :--- | :--- | :--- |
| `id` | `uuid` | `PRIMARY KEY` | Identificador único del usuario[cite: 6] |
| `role_id` | `uuid` | `FK` -> `roles.id` (`ON DELETE RESTRICT`) | Rol asignado[cite: 6] |
| `email` | `text` | `NOT NULL`, Index único en minúsculas | Correo electrónico de acceso[cite: 6] |
| `password_hash` | `text` | `NULLABLE` | Hash de la contraseña[cite: 6] |
| `full_name` | `text` | `NOT NULL` | Nombre completo del usuario[cite: 6] |
| `phone` | `text` | `NULLABLE` | Número telefónico de contacto[cite: 6] |
| `document_id` | `text` | `NULLABLE` | Documento de identidad[cite: 6] |
| `is_active` | `boolean` | Default `true` | Estado del usuario en el sistema[cite: 6] |
| `last_login_at` | `timestamptz` | `NULLABLE` | Último inicio de sesión[cite: 6] |
| `metadata` | `jsonb` | Default `'{}'` | Datos adicionales[cite: 6] |

---

### 3. `public.categories`
Categorías para clasificar los servicios[cite: 6].

| Columna | Tipo | Restricciones | Descripción |
| :--- | :--- | :--- | :--- |
| `id` | `uuid` | `PRIMARY KEY` | Identificador único[cite: 6] |
| `name` | `text` | `NOT NULL` | Nombre comercial[cite: 6] |
| `slug` | `text` | `UNIQUE`, `NOT NULL` | Identificador legible en URL[cite: 6] |
| `description` | `text` | `NULLABLE` | Detalle de la categoría[cite: 6] |
| `sort_order` | `integer` | Default `0` | Orden de visualización[cite: 6] |
| `is_active` | `boolean` | Default `true` | Visibilidad de la categoría[cite: 6] |

---

### 4. `public.services`
Oferta de servicios reservables[cite: 6].

| Columna | Tipo | Restricciones | Descripción |
| :--- | :--- | :--- | :--- |
| `id` | `uuid` | `PRIMARY KEY` | Identificador único del servicio[cite: 6] |
| `category_id` | `uuid` | `FK` -> `categories.id` (`ON DELETE RESTRICT`) | Categoría perteneciente[cite: 6] |
| `name` | `text` | `NOT NULL` | Nombre del servicio[cite: 6] |
| `slug` | `text` | `UNIQUE`, `NOT NULL` | Identificador único en URL[cite: 6] |
| `price` | `numeric(12,2)` | `CHECK (price > 0)` | Precio base del servicio[cite: 6] |
| `currency` | `char(3)` | Default `'COP'` | Moneda de cobro[cite: 6] |
| `duration_minutes` | `integer` | `CHECK (duration_minutes > 0)` | Duración estimada de la sesión[cite: 6] |
| `capacity` | `integer` | `CHECK (capacity > 0)` | Cupo máximo por sesión[cite: 6] |
| `image_url` | `text` | `NULLABLE` | Enlace de imagen representativa[cite: 6] |
| `is_active` | `boolean` | Default `true` | Disponibilidad pública[cite: 6] |

---

### 5. `public.service_schedules`
Franjas de disponibilidad recurrentes[cite: 6].

| Columna | Tipo | Restricciones | Descripción |
| :--- | :--- | :--- | :--- |
| `id` | `uuid` | `PRIMARY KEY` | Identificador del horario[cite: 6] |
| `service_id` | `uuid` | `FK` -> `services.id` (`ON DELETE CASCADE`) | Servicio vinculado[cite: 6] |
| `day_of_week` | `smallint` | `CHECK (between 0 AND 6)` | Día semanal (0=Dom, 6=Sáb)[cite: 6] |
| `start_time` / `end_time` | `time` | `CHECK (end_time > start_time)` | Rango horario de atención[cite: 6] |
| `valid_from` / `valid_until` | `date` | `NULLABLE` | Rango de vigencia opcional[cite: 6] |

---

### 6. `public.bookings`
Registro dinámico de agendamientos[cite: 6].

| Columna | Tipo | Restricciones | Descripción |
| :--- | :--- | :--- | :--- |
| `id` | `uuid` | `PRIMARY KEY` | Identificador único de la reserva[cite: 6] |
| `user_id` | `uuid` | `FK` -> `users.id` (`ON DELETE RESTRICT`) | Cliente que realiza la reserva[cite: 6] |
| `service_id` | `uuid` | `FK` -> `services.id` (`ON DELETE RESTRICT`) | Servicio reservado[cite: 6] |
| `schedule_id` | `uuid` | `FK` -> `service_schedules.id` (`ON DELETE SET NULL`) | Horario base[cite: 6] |
| `start_at` / `end_at` | `timestamptz` | `CHECK (end_at > start_at)` | Fecha y hora exacta reservada[cite: 6] |
| `quantity` | `integer` | Default `1` | Cantidad de cupos solicitados[cite: 6] |
| `total_amount` | `numeric(12,2)` | `CHECK (total_amount >= 0)` | Monto total a liquidar[cite: 6] |
| `status` | `text` | `CHECK (pending, confirmed, cancelled, completed, expired, no_show)` | Estado actual de la reserva[cite: 6] |
| `expires_at` | `timestamptz` | `NULLABLE` | Límite para pago antes de caducar[cite: 6] |

> **Nota técnica**: Cuenta con una restricción de exclusión (`bookings_no_overlap`) con `tstzrange` para bloquear automáticamente reservas duplicadas o solapadas sobre el mismo servicio cuando están en estado `pending` o `confirmed`[cite: 6].

---

### 7. `public.payments`
Gestión de transacciones y pago[cite: 6].

| Columna | Tipo | Restricciones | Descripción |
| :--- | :--- | :--- | :--- |
| `id` | `uuid` | `PRIMARY KEY` | Identificador único del pago[cite: 6] |
| `booking_id` | `uuid` | `FK` -> `bookings.id` (`ON DELETE CASCADE`) | Reserva asociada[cite: 6] |
| `amount` | `numeric(12,2)` | `CHECK (amount > 0)` | Monto procesado[cite: 6] |
| `method` | `text` | `CHECK (card, pse, cash, transfer, wallet, other)` | Medio de pago utilizado[cite: 6] |
| `status` | `text` | `CHECK (pending, processing, approved, rejected, failed, cancelled, refunded)` | Estado de la transacción[cite: 6] |
| `provider` | `text` | `NULLABLE` | Pasarela empleada (ej: Wompi, PayU)[cite: 6] |
| `provider_reference` | `text` | `NULLABLE` | ID único retornado por la pasarela[cite: 6] |

---

### 8. `public.tickets`
Tiquetes / Pases digitales generados[cite: 6].

| Columna | Tipo | Restricciones | Descripción |
| :--- | :--- | :--- | :--- |
| `id` | `uuid` | `PRIMARY KEY` | Identificador del boleto[cite: 6] |
| `booking_id` | `uuid` | `FK` -> `bookings.id` (`ON DELETE CASCADE`) | Reserva de origen[cite: 6] |
| `code` | `text` | `UNIQUE`, `NOT NULL` | Código único de validación / QR[cite: 6] |
| `holder_name` | `text` | `NULLABLE` | Nombre del titular del ticket[cite: 6] |
| `status` | `text` | `CHECK (valid, used, cancelled, expired)` | Estado del boleto[cite: 6] |
| `used_at` | `timestamptz` | `NULLABLE` | Fecha y hora en la que fue consumido[cite: 6] |

---

### 9. `public.access_logs`
Historial y auditoría de lecturas / accesos[cite: 6].

| Columna | Tipo | Restricciones | Descripción |
| :--- | :--- | :--- | :--- |
| `id` | `uuid` | `PRIMARY KEY` | Registro de lectura[cite: 6] |
| `ticket_id` | `uuid` | `FK` -> `tickets.id` (`ON DELETE CASCADE`) | Ticket validado[cite: 6] |
| `scanned_by` | `uuid` | `FK` -> `users.id` (`ON DELETE SET NULL`) | Usuario staff que escaneó[cite: 6] |
| `result` | `text` | `CHECK (granted, denied)` | Resultado de la validación[cite: 6] |
| `reason` | `text` | `NULLABLE` | Causa en caso de rechazo[cite: 6] |
| `access_point` | `text` | `NULLABLE` | Ubicación o punto de control[cite: 6] |

---

## 🔒 Políticas de Seguridad (RLS)

1. **Activación RLS**: Habilitado en las 9 tablas[cite: 6].
2. **Acceso Backend**: Control exclusivo mediante política `backend_full_access` para la clave `service_role`[cite: 6].
3. **Restricción Pública**: Bloqueo explícito de consultas directas vía PostgREST a roles `anon` y `authenticated` (`REVOKE ALL`) para procesar toda lógica mediante el servidor backend de forma segura[cite: 6].