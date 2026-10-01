# Contrato Swagger y guia de consumo del frontend

Este documento describe el contrato REST de PlanCity API para que el equipo de frontend pueda integrar autenticacion, perfil, categorias, eventos y favoritos. Los ejemplos corresponden a los controladores, DTO y servicios del backend compartido en `plancity-api-main.zip`.

> Esta rama agrega documentacion al repositorio de base de datos. El codigo ejecutable de NestJS y la UI de Swagger viven en el repositorio de la API. La documentacion interactiva se sirve en `/api/docs` cuando ese backend esta levantado.

## 1. Datos de conexion

| Entorno | URL base |
|---|---|
| Desarrollo local | `http://localhost:3000` |
| Produccion | Sustituir por el dominio publicado del API |

La URL de Swagger local es `http://localhost:3000/api/docs`. Las rutas REST no llevan prefijo `/api`; por ejemplo, el registro es `POST /auth/register`.

Todas las respuestas usan JSON salvo las respuestas `204 No Content`, que no tienen body. La API no envuelve las respuestas en una propiedad comun como `data`: cada endpoint devuelve el objeto o arreglo descrito mas abajo.

## 2. Autenticacion y formato

Para endpoints protegidos, el frontend envia el JWT recibido en el login o registro:

```http
Authorization: Bearer <accessToken>
Content-Type: application/json
```

Los roles del API son `admin` y `user` (minusculas). Las rutas publicas no requieren `Authorization`; las operaciones marcadas como admin requieren un token valido cuyo rol sea `admin`.

El login y el registro devuelven:

```json
{
  "accessToken": "<jwt>",
  "user": {
    "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "name": "Santiago Botero",
    "email": "santiago@example.com",
    "role": "user",
    "createdAt": "2026-09-30T12:00:00.000Z"
  }
}
```

No se devuelve la contrasena ni su hash. El token contiene el identificador en `sub`, ademas de `email` y `role`. El frontend debe tratar el token como credencial, no incluirlo en logs y eliminarlo al cerrar sesion. El logout es stateless: confirma la accion, pero no revoca el token en el servidor.

## 3. Validacion y errores

El backend valida los DTO con `whitelist`, `forbidNonWhitelisted` y `transform`. En la practica:

- Los campos desconocidos producen `400 Bad Request`; no enviar propiedades extra.
- Los UUID de rutas y filtros deben tener formato UUID.
- Los cuerpos deben ser JSON y respetar los tipos/limites documentados.
- `PATCH` recibe solo los campos que se desean cambiar.

Los errores siguen el formato NestJS:

```json
{
  "statusCode": 400,
  "message": ["La contraseña debe tener al menos 6 caracteres"],
  "error": "Bad Request"
}
```

`message` puede ser texto o una lista de mensajes de validacion.

| HTTP | Cuando ocurre |
|---|---|
| `400` | DTO invalido, UUID invalido o nueva contrasena igual a la actual. |
| `401` | Credenciales invalidas, JWT ausente/invalido o contrasena actual incorrecta. |
| `403` | Usuario autenticado sin rol `admin` en una operacion administrativa. |
| `404` | Usuario, categoria, evento o favorito solicitado no existe. |
| `409` | Email/categoria/evento duplicado o evento ya agregado a favoritos. |
| `500` | Error inesperado del servidor o de la base de datos. |

Ejemplo de credenciales invalidas:

```json
{
  "statusCode": 401,
  "message": "Credenciales inválidas",
  "error": "Unauthorized"
}
```

## 4. Resumen de endpoints

| Metodo | Ruta | Acceso | Resultado exitoso |
|---|---|---|---|
| `POST` | `/auth/register` | Publico | `201`, token y usuario |
| `POST` | `/auth/login` | Publico | `200`, token y usuario |
| `POST` | `/auth/logout` | JWT | `200`, mensaje |
| `GET` | `/users/me` | JWT | `200`, perfil |
| `PATCH` | `/users/me/password` | JWT | `200`, mensaje |
| `GET` | `/categories` | Publico | `200`, categorias |
| `GET` | `/categories/{id}` | Publico | `200`, categoria |
| `POST` | `/categories` | JWT admin | `201`, categoria creada |
| `PATCH` | `/categories/{id}` | JWT admin | `200`, categoria actualizada |
| `DELETE` | `/categories/{id}` | JWT admin | `204`, sin body |
| `GET` | `/events` | Publico | `200`, eventos; admite filtros |
| `GET` | `/events/{id}` | Publico | `200`, detalle del evento |
| `POST` | `/events` | JWT admin | `201`, evento creado |
| `PATCH` | `/events/{id}` | JWT admin | `200`, evento actualizado |
| `DELETE` | `/events/{id}` | JWT admin | `204`, sin body |
| `GET` | `/favorites` | JWT | `200`, eventos favoritos del usuario |
| `POST` | `/favorites/{eventId}` | JWT | `201`, favorito creado |
| `DELETE` | `/favorites/{eventId}` | JWT | `204`, sin body |

Los codigos anteriores son los que devuelve NestJS en runtime: un `POST` sin `@HttpCode` devuelve `201`; login, logout y cambio de contrasena establecen `200` explicitamente. En particular, el decorador Swagger actual del registro declara `200`, aunque runtime responde `201`; conviene corregirlo a `@ApiCreatedResponse` en el repositorio del backend.

## 5. Autenticacion

### Registrar usuario

`POST /auth/register` es publico y crea la cuenta con rol `user`. Tras el alta, la respuesta incluye un JWT para iniciar sesion automaticamente.

Solicitud:

```json
{
  "name": "Santiago Botero",
  "email": "santiago@example.com",
  "password": "miPassword123"
}
```

Reglas: `name` es texto de al menos 2 caracteres; `email` debe ser valido; `password` es texto con minimo 6 caracteres.

Respuesta `201 Created`: objeto de autenticacion de la seccion 2. El email existente responde `409`.

### Iniciar sesion

`POST /auth/login` es publico.

Solicitud:

```json
{
  "email": "santiago@example.com",
  "password": "miPassword123"
}
```

Respuesta `200 OK`: el mismo objeto de autenticacion del registro. Un email o contrasena incorrectos responden `401` con el mismo mensaje generico.

### Cerrar sesion

`POST /auth/logout` requiere JWT. No recibe body.

Respuesta `200 OK`:

```json
{ "message": "Sesión cerrada correctamente" }
```

Al recibir el `200`, el frontend debe eliminar localmente el token y limpiar el estado autenticado. La ruta no invalida JWT ya emitidos.

## 6. Perfil

### Consultar perfil

`GET /users/me` requiere JWT. No recibe body. Devuelve solo datos publicos del usuario autenticado:

```json
{
  "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
  "name": "Santiago Botero",
  "email": "santiago@example.com",
  "role": "user",
  "createdAt": "2026-09-30T12:00:00.000Z"
}
```

Respuesta `200 OK`. `password` nunca forma parte de este DTO.

### Cambiar contrasena

`PATCH /users/me/password` requiere JWT.

Solicitud:

```json
{
  "currentPassword": "miPasswordActual123",
  "newPassword": "miPasswordNuevo456"
}
```

`currentPassword` no puede estar vacia; `newPassword` requiere al menos 6 caracteres y debe ser diferente de la actual.

Respuesta `200 OK`:

```json
{ "message": "Contraseña actualizada correctamente" }
```

Una contrasena actual incorrecta responde `401`; una nueva igual a la actual responde `400`.

## 7. Categorias

Un objeto categoria tiene este formato:

```json
{
  "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
  "name": "Conciertos",
  "description": "Presentaciones musicales en vivo",
  "createdAt": "2026-09-30T12:00:00.000Z",
  "updatedAt": "2026-09-30T12:00:00.000Z"
}
```

### Listar categorias

`GET /categories` es publico, no recibe parametros y devuelve `200 OK` con un arreglo ordenado por nombre ascendente. Si no hay categorias, devuelve `[]`.

### Obtener categoria

`GET /categories/{id}` es publico. `id` debe ser UUID. Devuelve `200 OK` y el objeto categoria; si no existe, `404`.

### Crear categoria

`POST /categories` requiere JWT con rol `admin`.

```json
{
  "name": "Conciertos",
  "description": "Presentaciones musicales en vivo"
}
```

`name` requiere entre 2 y 100 caracteres. `description` es opcional y permite hasta 255 caracteres.

Respuesta `201 Created`: objeto categoria creado. Nombre duplicado responde `409`.

### Actualizar categoria

`PATCH /categories/{id}` requiere JWT con rol `admin`. El body acepta cualquiera de los campos de creacion, todos opcionales:

```json
{ "description": "Musica en vivo y festivales" }
```

Respuesta `200 OK`: categoria actualizada. ID inexistente responde `404`; nombre duplicado responde `409`.

### Eliminar categoria

`DELETE /categories/{id}` requiere JWT con rol `admin`. Respuesta `204 No Content`, sin body. La base de datos restringe eliminar categorias que todavia esten asociadas a eventos; el frontend debe informar que primero hay que reasignar o eliminar esos eventos.

## 8. Eventos

Un evento incluye categoria e imagenes. Ejemplo de respuesta:

```json
{
  "id": "8fa85f64-5717-4562-b3fc-2c963f66afa6",
  "name": "Festival de Jazz en el Parque",
  "description": "Una noche de jazz en vivo con bandas locales",
  "date": "2026-11-15T19:00:00.000Z",
  "location": "Parque de la 93, Bogota",
  "price": 45000,
  "capacity": 200,
  "categoryId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
  "createdAt": "2026-09-30T12:00:00.000Z",
  "updatedAt": "2026-09-30T12:00:00.000Z",
  "category": {
    "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "name": "Conciertos",
    "description": "Presentaciones musicales en vivo",
    "createdAt": "2026-09-30T12:00:00.000Z",
    "updatedAt": "2026-09-30T12:00:00.000Z"
  },
  "images": [
    {
      "id": "4fa85f64-5717-4562-b3fc-2c963f66afa6",
      "url": "https://example.com/imagenes/festival.jpg",
      "order": 0,
      "eventId": "8fa85f64-5717-4562-b3fc-2c963f66afa6",
      "createdAt": "2026-09-30T12:00:00.000Z"
    }
  ]
}
```

### Listar y filtrar eventos

`GET /events` es publico. Devuelve un arreglo ordenado por fecha ascendente; no implementa paginacion.

| Query param | Tipo | Uso |
|---|---|---|
| `search` | string | Coincidencia parcial, sin distinguir mayusculas, en nombre o descripcion. |
| `categoryId` | UUID | Limita resultados a una categoria. |

Los filtros se pueden combinar:

```http
GET /events?search=jazz&categoryId=3fa85f64-5717-4562-b3fc-2c963f66afa6
```

Respuesta `200 OK`: `Event[]`; sin coincidencias devuelve `[]`.

### Obtener detalle de evento

`GET /events/{id}` es publico y requiere UUID. Respuesta `200 OK`: objeto evento con su categoria e imagenes. Evento inexistente responde `404`.

### Crear evento

`POST /events` requiere JWT con rol `admin`.

```json
{
  "name": "Festival de Jazz en el Parque",
  "description": "Una noche de jazz en vivo con bandas locales",
  "date": "2026-11-15T19:00:00.000Z",
  "location": "Parque de la 93, Bogota",
  "price": 45000,
  "capacity": 200,
  "categoryId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
  "images": [
    "https://example.com/imagenes/festival.jpg",
    "https://example.com/imagenes/escenario.jpg"
  ]
}
```

Campos requeridos: `name` (minimo 2 caracteres), `date` (fecha ISO), `location` (minimo 2 caracteres), `price` (numero >= 0 y maximo 2 decimales), `capacity` (entero positivo) y `categoryId` (UUID existente). `description` e `images` son opcionales. `images` acepta hasta 10 URLs validas; su posicion define el campo `order`.

Respuesta `201 Created`: objeto evento completo. Categoria inexistente responde `404`; nombre duplicado responde `409`.

### Actualizar evento

`PATCH /events/{id}` requiere JWT con rol `admin`; recibe cualquier subconjunto de los campos aceptados al crear.

```json
{
  "price": 50000,
  "images": ["https://example.com/imagenes/festival-actualizado.jpg"]
}
```

Respuesta `200 OK`: objeto evento actualizado. Si se omite `images`, las imagenes no cambian; si se envia, se reemplaza la lista completa. Enviar `"images": []` elimina todas las imagenes. ID/categoria inexistente responde `404`; nombre duplicado responde `409`.

### Eliminar evento

`DELETE /events/{id}` requiere JWT con rol `admin`. Respuesta `204 No Content`, sin body. La eliminacion en cascada tambien elimina imagenes y favoritos asociados.

## 9. Favoritos

Los favoritos siempre pertenecen al usuario del JWT; el frontend no debe enviar `userId` ni puede consultar favoritos de otra cuenta.

### Listar favoritos

`GET /favorites` requiere JWT. No recibe body. Devuelve `200 OK` con un arreglo de eventos favoritos del usuario, ordenados por fecha de favorito descendente; sin favoritos devuelve `[]`.

### Agregar favorito

`POST /favorites/{eventId}` requiere JWT. El ID debe corresponder a un evento existente. No recibe body.

Respuesta `201 Created`:

```json
{
  "id": "5fa85f64-5717-4562-b3fc-2c963f66afa6",
  "userId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
  "eventId": "8fa85f64-5717-4562-b3fc-2c963f66afa6",
  "createdAt": "2026-09-30T12:00:00.000Z"
}
```

Evento inexistente responde `404`; favorito repetido responde `409`.

### Quitar favorito

`DELETE /favorites/{eventId}` requiere JWT y no recibe body. Respuesta `204 No Content`; si ese evento no es favorito del usuario actual, devuelve `404`.

## 10. Integracion desde el frontend

Ejemplo de cliente `fetch` que conserva el status y parsea errores JSON:

```javascript
const API_URL = import.meta.env.VITE_API_URL ?? 'http://localhost:3000';

async function apiRequest(path, { token, ...options } = {}) {
  const response = await fetch(`${API_URL}${path}`, {
    ...options,
    headers: {
      ...(options.body ? { 'Content-Type': 'application/json' } : {}),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...options.headers,
    },
  });

  if (response.status === 204) return null;

  const payload = await response.json().catch(() => null);
  if (!response.ok) {
    const error = new Error(
      Array.isArray(payload?.message)
        ? payload.message.join(', ')
        : payload?.message ?? 'Error inesperado',
    );
    error.status = response.status;
    error.payload = payload;
    throw error;
  }

  return payload;
}
```

Ejemplos de uso:

```javascript
const auth = await apiRequest('/auth/login', {
  method: 'POST',
  body: JSON.stringify({ email, password }),
});
// Guardar auth.accessToken usando la estrategia de sesion del producto.

const events = await apiRequest('/events?search=jazz', { token: auth.accessToken });

await apiRequest('/favorites/8fa85f64-5717-4562-b3fc-2c963f66afa6', {
  method: 'POST',
  token: auth.accessToken,
});
```

Para `204`, no intentar ejecutar `response.json()`. En `401`, solicitar autenticacion de nuevo y limpiar el token invalido. En `403`, mostrar que la accion requiere permisos administrativos; no confundirlo con una sesion expirada.

## 11. Criterios para mantener Swagger actualizado

La UI `/api/docs` se genera en el backend. Para que coincida con este contrato, los cambios en controladores/DTO deben actualizar sus decoradores Swagger:

- `@ApiTags` para agrupar por Autenticacion, Perfil, Categorias, Eventos y Favoritos.
- `@ApiOperation` con una descripcion util para el consumidor.
- `@ApiBearerAuth('access-token')` en endpoints protegidos; el decorador `@Auth()` actual ya lo agrega.
- `@ApiBody`, `@ApiParam` y `@ApiQuery` para solicitudes, UUID y filtros.
- `@ApiCreatedResponse` para los `POST` que responden `201`; `@ApiOkResponse` para `200`; `@ApiNoContentResponse` para `204`.
- `@ApiBadRequestResponse`, `@ApiUnauthorizedResponse`, `@ApiForbiddenResponse`, `@ApiNotFoundResponse` y `@ApiConflictResponse` para errores posibles.
- DTO de respuesta explicitos para perfil, categoria, evento, favorito y error. No documentar `password` ni hashes en respuestas.

Verificar cada cambio en Swagger UI y probar ejemplos con una cuenta `user` y otra `admin`. El frontend debe integrarse contra la respuesta efectiva del API y no asumir que todos los endpoints devuelven el mismo status o envoltorio.