# Migraciones de base de datos

Esta rama contiene la migración inicial de PlanCity API para PostgreSQL/Supabase. La fuente de verdad del esquema de la API son sus entidades TypeORM y las migraciones versionadas, no `synchronize`.

## Alcance

`src/migrations/1787602695769-InitSchema.ts` crea:

- `users`, con roles `admin` y `user`.
- `categories`.
- `events`, relacionados con una categoría.
- `event_images`, relacionados con eventos.
- `favorites`, con una restricción única por usuario y evento.
- La extensión `uuid-ossp`, necesaria para generar UUID.

También habilita RLS en las cinco tablas. El rol `service_role` recibe acceso completo; `anon` y `authenticated` no reciben permisos de tabla. La política no convierte el rol de la aplicación `admin` en un rol de Supabase: son conceptos distintos.

La migración crea además la cuenta administrativa inicial definida en el código de la migración. Su contraseña se guarda con bcrypt. Es una credencial de desarrollo: cámbiala antes de exponer la API y no reutilices esa contraseña en producción.

## Requisitos

- Node.js 20 o superior.
- El repositorio de la API NestJS, que contiene `package.json`, `src/data-source.ts` y las entidades TypeORM.
- Un proyecto PostgreSQL/Supabase vacío o preparado para recibir estas tablas.
- `DATABASE_URL` configurada en el `.env` de la API con una conexión PostgreSQL autorizada a crear extensiones, tipos, tablas, políticas y permisos. No uses una clave `anon` o `service_role` de la API REST como cadena de conexión PostgreSQL.

Este repositorio de base de datos no incluye el runtime de NestJS. Los comandos siguientes se ejecutan desde la raíz del repositorio de la API, una vez integrada esta migración en `src/migrations/`.

## Aplicar

Instala las dependencias del backend y configura su entorno:

```powershell
npm install
Copy-Item .env.example .env
```

Edita `.env` localmente y asigna `DATABASE_URL`; no subas ese archivo ni compartas sus credenciales. Después ejecuta:

```powershell
npm run typeorm -- migration:show
npm run migration:run
npm run typeorm -- migration:show
```

El `data-source.ts` del backend debe seguir usando `synchronize: false` y cargar `src/migrations/*{.ts,.js}`. TypeORM registra las migraciones ejecutadas en su tabla de historial; no ejecutes esta migración manualmente desde el SQL Editor y luego vuelvas a correrla con TypeORM.

## Supabase y despliegue

- Ejecuta la migración con una conexión de base de datos con permisos DDL, normalmente la conexión PostgreSQL del proyecto. La extensión y los roles `service_role`, `anon` y `authenticated` deben estar disponibles en Supabase.
- La migración está pensada para inicializar un esquema limpio. No la apliques sobre tablas existentes con nombres iguales sin comparar primero sus columnas y restricciones.
- Las políticas permiten acceso a `service_role`; verifica que el backend use el mecanismo de conexión previsto por el proyecto. Los clientes `anon` y `authenticated` no podrán acceder directamente a estas tablas.
- Prueba primero en un proyecto Supabase de desarrollo y toma un respaldo antes de producción.
- `uuid-ossp` no se elimina al revertir porque puede ser compartida con otros esquemas u objetos.

## Revertir

Desde la raíz de la API:

```powershell
npm run migration:revert
```

El `down` elimina las tablas, sus datos y el tipo `users_role_enum`. Es una operación destructiva; no la uses en una base con datos que deban conservarse.

## Crear migraciones futuras

Actualiza primero las entidades TypeORM y genera una migración con el script existente:

```powershell
npm run migration:generate -- src/migrations/DescribeYourChange
```

Revisa el SQL generado, especialmente cambios destructivos, permisos y políticas RLS. Ejecuta la migración en desarrollo, prueba la API y versiona el archivo junto con los cambios de esquema relacionados. No edites una migración que ya se haya aplicado en un entorno compartido; crea una nueva.