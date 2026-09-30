## Base de datos
el objetivo es diseñar y mantener la estructura de datos que soportará el sistema y garantizar la integridad, consistencia y concurrencia de la información.
## Responsabilidades
- Diseñar el modelo de datos.
- Elaborar el diagrama ER.
- Definir tablas y relaciones.
- Definir claves primarias y foráneas.
- Definir índices.
- Definir restricciones de integridad.
- Analizar las reglas de concurrencia.
- Diseñar mecanismos para evitar doble reserva.
- Implementar restricciones relacionadas con capacidad.
- Definir estados de reservas y pagos.
- Analizar expiración de reservas temporales.
- Optimizar consultas cuando sea necesario.
- Definir estrategia de migraciones.
## Información que deberá contemplar
Entre otras entidades:
- Usuarios.
- Roles.
- Categorías.
- Servicios.
- Horarios.
- Disponibilidad.
- Reservas.
- Pagos.
- QR / accesos.
- Empleados.
El modelo definitivo se determinará después del análisis completo de los requerimientos.
## Punto crítico
La concurrencia, capacidad e integridad de las reservas deberán estar respaldadas por mecanismos de la base de datos y no únicamente por validaciones realizadas desde el código.