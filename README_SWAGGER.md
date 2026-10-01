# API y Swagger del complejo deportivo

## Estado del contrato

Esta guía y `openapi.yaml` definen una **propuesta de contrato HTTP** para que los equipos de backend y frontend acuerden cómo exponer la base de datos deportiva. El repositorio contiene el esquema PostgreSQL/Supabase, no una aplicación HTTP: el SQL no define rutas, autenticación JWT ni códigos HTTP. Por tanto, estos endpoints deben implementarse en el backend antes de considerarlos disponibles.

La propuesta se basa en [database/schema.sql](database/schema.sql) y [database/seed.sql](database/seed.sql): roles, usuarios, categorías, servicios, horarios, reservas, pagos, tickets y bitácora de accesos. No usa el modelo de eventos de PlanCity.

`openapi.yaml` es la especificación OpenAPI 3.1 que se puede importar en Swagger Editor o usar como base para configurar Swagger UI en el backend.

## Archivos y fuente de verdad

- `database/schema.sql`: estructura y restricciones de PostgreSQL.
- `database/seed.sql`: datos iniciales/de prueba; no es un catálogo de endpoints.
- `openapi.yaml`: contrato HTTP propuesto para el API.
- Este README: reglas de integración y explicaciones para frontend/backend.

Cuando el backend implemente rutas distintas, actualicen primero el contrato acordado y mantengan el OpenAPI sincronizado con controladores, DTO y pruebas. No se deben inferir rutas definitivas del nombre de las tablas.

## Convenciones de API propuestas

- Prefijo versionado: `/api/v1`.
- JSON en solicitudes y respuestas, excepto `204 No Content`, que no lleva body.
- Fechas/instantes como ISO 8601 con zona horaria, por ejemplo `2026-10-12T14:30:00Z`.
- Horas de horario como `HH:mm:ss`; `dayOfWeek` usa `0` para domingo y `6` para sábado.
- UUID como string.
- Los importes de PostgreSQL `numeric(12,2)` se representan como strings decimales, por ejemplo `"125000.00"`, para evitar errores de precisión en JavaScript. La moneda asociada viene en `currency` (`COP` por defecto).
- Respuestas de colección como arreglos JSON; no hay paginación definida en el esquema. Se recomienda incorporar paginación antes de exponer listados grandes.
- Las lecturas públicas del catálogo solo deben devolver categorías/servicios activos. Reservas, perfil, pagos, tickets y accesos requieren autorización.

## Modelo de datos y contrato

| Tabla | Uso desde el API | Datos que nunca deben exponerse sin filtrar |
|---|---|---|
| `roles` | Asignación de permisos administrativos (`admin`, `staff`, `customer`). | No confiar en permisos enviados por el cliente. |
| `users` | Perfil, contacto y relación con un rol. | `password_hash`; excluirlo siempre de DTO, logs y Swagger. |
| `categories` | Agrupar servicios y ordenar el catálogo. | — |
| `services` | Catálogo, precio, moneda, duración, cupo y disponibilidad activa. | `metadata` solo si existe un contrato explícito. |
| `service_schedules` | Ventanas semanales de servicio, con vigencia por fecha. | No aceptar horarios inactivos para nuevas reservas. |
| `bookings` | Reserva, importe total, estado, vencimiento y cancelación. | `user_id`, `total_amount` y `status` deben ser validados/calculados por el backend. |
| `payments` | Intentos y estados del pago asociado a una reserva. | `raw_response`, referencias sensibles y secretos de pasarela. |
| `tickets` | Credencial de acceso asociada a una reserva. | El código del ticket es una credencial; no incluirlo en logs públicos. |
| `access_logs` | Resultado de escaneos, punto de acceso e instante. | `ip_address` y `metadata` no deben devolverse al cliente general. |

### Estados establecidos por el esquema

- Reserva: `pending`, `confirmed`, `cancelled`, `completed`, `expired`, `no_show`.
- Pago: `pending`, `processing`, `approved`, `rejected`, `failed`, `cancelled`, `refunded`.
- Ticket: `valid`, `used`, `cancelled`, `expired`.
- Validación de acceso: `granted`, `denied`.
- Métodos de pago: `card`, `pse`, `cash`, `transfer`, `wallet`, `other`.
- Roles sembrados: `admin`, `staff`, `customer`.

La base permite esos valores, pero las transiciones válidas de estado (por ejemplo, de `pending` a `confirmed`) deben definirse y validarse en el backend.

## Endpoints propuestos

Todos los paths completos están en `openapi.yaml`. Esta tabla resume quién los consume y qué representa cada operación.

| Método | Ruta | Acceso propuesto | Uso |
|---|---|---|---|
| `POST` | `/auth/register` | Público | Crear usuario con rol `customer`; no aceptar `role_id` del cliente. |
| `POST` | `/auth/login` | Público | Autenticar por email/contraseña y recibir token. |
| `GET` | `/me` | Usuario | Obtener el perfil del token actual, sin `password_hash`. |
| `GET`, `POST` | `/categories` | Público lectura; admin escritura | Consultar/administrar categorías. |
| `GET`, `PATCH` | `/categories/{categoryId}` | Público lectura; admin escritura | Consultar o actualizar categoría. |
| `GET`, `POST` | `/services` | Público lectura; admin escritura | Catálogo y alta de servicios. |
| `GET`, `PATCH` | `/services/{serviceId}` | Público lectura; admin escritura | Detalle/edición y activación lógica. |
| `GET`, `POST` | `/services/{serviceId}/schedules` | Público lectura; admin escritura | Horarios de un servicio. |
| `GET`, `POST` | `/bookings` | Usuario autenticado | Consultar reservas propias o solicitar una nueva. |
| `GET` | `/bookings/{bookingId}` | Propietario o admin/staff | Ver detalle autorizado de una reserva. |
| `POST` | `/bookings/{bookingId}/cancel` | Propietario o admin/staff | Solicitar cancelación con motivo opcional. |
| `POST` | `/bookings/{bookingId}/payments` | Propietario | Iniciar un intento de pago. |
| `GET` | `/payments/{paymentId}` | Propietario o admin | Consultar estado de un pago sin respuesta cruda del proveedor. |
| `GET` | `/bookings/{bookingId}/tickets` | Propietario o staff | Consultar tickets autorizados de una reserva. |
| `POST` | `/tickets/{code}/validate` | Staff/admin | Validar o registrar el uso de un ticket. |
| `GET` | `/access-logs` | Staff/admin | Consultar bitácora con filtros y paginación recomendada. |

Las rutas para roles y usuarios administrativos pueden añadirse cuando el equipo defina el flujo de administración. No se publica CRUD de `roles` para el cliente común.

## Reglas críticas de reserva

1. El cliente envía `serviceId`, `startAt`, `endAt`, `quantity`, y opcionalmente `scheduleId`/`notes`. El backend deriva el usuario del token; no recibe `userId` como dato confiable.
2. El backend carga el servicio y horario, comprueba que estén activos y vigentes, valida la zona horaria y calcula `totalAmount` usando el precio del servidor.
3. La base rechaza `end_at <= start_at`, cantidad no positiva e importes negativos.
4. `bookings_no_overlap` impide solapamientos de reservas `pending` o `confirmed` del mismo servicio. Esta restricción representa cupo exclusivo, incluso cuando `services.capacity` sea mayor que uno. Si se necesitan reservas simultáneas según capacidad, el modelo SQL debe cambiar antes de ofrecer esa regla en la UI.
5. Una violación de solapamiento o conflicto de estado debería convertirse en `409 Conflict` con un código de error estable, no exponer texto SQL.
6. `release_expired_bookings()` marca como `expired` las reservas pendientes vencidas. El backend o una tarea programada debe invocarla; no se ejecuta sola por tener la función creada.

## Solicitudes y respuestas de ejemplo

### Crear una reserva

Solicitud propuesta `POST /api/v1/bookings`:

```json
{
  "serviceId": "8d2a9224-5b7e-4f6c-95f5-194dc7c98eab",
  "scheduleId": "89c27c7e-112b-4a2b-a2d9-e2c96b04d7e2",
  "startAt": "2026-10-12T14:30:00Z",
  "endAt": "2026-10-12T15:30:00Z",
  "quantity": 1,
  "notes": "Necesito préstamo de equipo"
}
```

Respuesta `201 Created` propuesta:

```json
{
  "id": "ed2a2e60-602f-499b-9e62-82c9dabf1490",
  "serviceId": "8d2a9224-5b7e-4f6c-95f5-194dc7c98eab",
  "scheduleId": "89c27c7e-112b-4a2b-a2d9-e2c96b04d7e2",
  "startAt": "2026-10-12T14:30:00Z",
  "endAt": "2026-10-12T15:30:00Z",
  "quantity": 1,
  "totalAmount": "125000.00",
  "currency": "COP",
  "status": "pending",
  "expiresAt": "2026-10-12T14:45:00Z",
  "createdAt": "2026-09-30T15:00:00Z"
}
```

El ejemplo no afirma que estos valores/status estén implementados; ilustra el contrato propuesto. El backend debe devolver solo los campos permitidos y calcular precio/expiración.

### Error de horario ocupado

Respuesta propuesta `409 Conflict`:

```json
{
  "statusCode": 409,
  "code": "BOOKING_TIME_CONFLICT",
  "message": "El horario solicitado ya no está disponible"
}
```

Conviene mantener un formato de error consistente con `code` estable para que el frontend pueda traducir mensajes sin depender del texto del servidor.

## Autenticación y Supabase

El SQL habilita RLS y concede la política de acceso de tablas a `service_role`, mientras revoca acceso de `anon` y `authenticated`. Por ello, el navegador **no debe conectarse directamente a estas tablas** ni recibir la `service_role key`. El frontend consume el backend HTTP; el backend guarda sus credenciales en secretos del servidor.

El SQL no especifica JWT, expiración de tokens, recuperación de contraseña ni proveedor de identidad. El contrato OpenAPI propone Bearer JWT como interfaz, pero el equipo backend debe decidir e implementar emisión, expiración, revocación y autorización por `roles.permissions`.

## Códigos HTTP recomendados

| Código | Uso recomendado |
|---|---|
| `200` | Lectura, actualización o acción exitosa con body. |
| `201` | Recurso creado. |
| `204` | Borrado/desactivación exitosa sin body. |
| `400` | JSON o parámetros inválidos. |
| `401` | Token ausente/inválido o credenciales incorrectas. |
| `403` | Usuario autenticado sin permiso. |
| `404` | Recurso inexistente o no visible para el usuario. |
| `409` | Solapamiento, duplicado o transición no permitida. |
| `422` | Regla de negocio válida sintácticamente pero no satisfacible (opcional; usar de forma consistente). |

No devolver errores crudos del driver PostgreSQL, SQL, hashes de contraseña, `raw_response` de pagos ni secretos de Supabase.

## Uso de Swagger

1. Abrir `openapi.yaml` en Swagger Editor o importarlo en la configuración de Swagger UI del backend.
2. Cambiar el `server` local si el API usa otro puerto/prefijo.
3. Implementar rutas y DTO conforme al contrato, o modificar el contrato antes de liberar rutas distintas.
4. Añadir ejemplos reales anonimizados y respuestas de error a cada operación.
5. Probar los roles `customer`, `staff` y `admin`, RLS, límites de acceso entre usuarios y las respuestas `409` de reservas.
6. Generar clientes frontend solo cuando el contrato haya sido aprobado y versionado.

## Decisiones pendientes del equipo backend

- Framework/base path definitivos y estrategia de versionado.
- JWT u otro mecanismo de sesión, expiración, refresh y recuperación de acceso.
- Límites de paginación y formato de filtros para listados.
- Duración de retención de una reserva `pending` y ejecución periódica de reservas vencidas.
- Si `capacity > 1` permite solapamientos y cómo se asigna `quantity`.
- Pasarela de pago, flujo de callbacks/webhooks e idempotencia.
- Reglas de cancelación/reembolso y transiciones permitidas de estados.
- Formato del código de error y política para ocultar recursos de otros usuarios.

Hasta cerrar estas decisiones, este OpenAPI es una base revisable para implementar, no una garantía de disponibilidad de endpoints.