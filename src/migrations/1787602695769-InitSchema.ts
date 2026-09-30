import { MigrationInterface, QueryRunner } from 'typeorm';
import * as bcrypt from 'bcrypt';

const ADMIN_EMAIL = 'admin@examen.com';
const ADMIN_PASSWORD = 'Admin123!';
const ADMIN_NAME = 'Administrador';

export class InitSchema1787602695769 implements MigrationInterface {
  name = 'InitSchema1787602695769';

  public async up(queryRunner: QueryRunner): Promise<void> {
    // TypeORM usa uuid_generate_v4() para las columnas UUID generadas.
    await queryRunner.query(`CREATE EXTENSION IF NOT EXISTS "uuid-ossp"`);
    await queryRunner.query(
      `CREATE TYPE "public"."users_role_enum" AS ENUM('admin', 'user')`,
    );

    // Crear las tablas y restricciones esperadas por las entidades del API.
    await queryRunner.query(
      `CREATE TABLE "users" ("id" uuid NOT NULL DEFAULT uuid_generate_v4(), "name" character varying(100) NOT NULL, "email" character varying(150) NOT NULL, "password" character varying(255) NOT NULL, "role" "public"."users_role_enum" NOT NULL DEFAULT 'user', "created_at" TIMESTAMP NOT NULL DEFAULT now(), "updated_at" TIMESTAMP NOT NULL DEFAULT now(), CONSTRAINT "UQ_users_email" UNIQUE ("email"), CONSTRAINT "PK_users" PRIMARY KEY ("id"))`,
    );

    await queryRunner.query(
      `CREATE TABLE "categories" ("id" uuid NOT NULL DEFAULT uuid_generate_v4(), "name" character varying(100) NOT NULL, "description" character varying(255), "created_at" TIMESTAMP NOT NULL DEFAULT now(), "updated_at" TIMESTAMP NOT NULL DEFAULT now(), CONSTRAINT "UQ_categories_name" UNIQUE ("name"), CONSTRAINT "PK_categories" PRIMARY KEY ("id"))`,
    );

    await queryRunner.query(
      `CREATE TABLE "events" ("id" uuid NOT NULL DEFAULT uuid_generate_v4(), "name" character varying(150) NOT NULL, "description" text, "date" TIMESTAMP NOT NULL, "location" character varying(200) NOT NULL, "price" numeric(10,2) NOT NULL, "capacity" integer NOT NULL DEFAULT '0', "category_id" uuid NOT NULL, "created_at" TIMESTAMP NOT NULL DEFAULT now(), "updated_at" TIMESTAMP NOT NULL DEFAULT now(), CONSTRAINT "UQ_events_name" UNIQUE ("name"), CONSTRAINT "PK_events" PRIMARY KEY ("id"))`,
    );

    await queryRunner.query(
      `CREATE TABLE "event_images" ("id" uuid NOT NULL DEFAULT uuid_generate_v4(), "url" character varying(500) NOT NULL, "order" integer NOT NULL DEFAULT '0', "event_id" uuid NOT NULL, "created_at" TIMESTAMP NOT NULL DEFAULT now(), CONSTRAINT "PK_event_images" PRIMARY KEY ("id"))`,
    );

    await queryRunner.query(
      `CREATE TABLE "favorites" ("id" uuid NOT NULL DEFAULT uuid_generate_v4(), "user_id" uuid NOT NULL, "event_id" uuid NOT NULL, "created_at" TIMESTAMP NOT NULL DEFAULT now(), CONSTRAINT "UQ_favorites_user_event" UNIQUE ("user_id", "event_id"), CONSTRAINT "PK_favorites" PRIMARY KEY ("id"))`,
    );

    await queryRunner.query(
      `ALTER TABLE "events" ADD CONSTRAINT "FK_events_category" FOREIGN KEY ("category_id") REFERENCES "categories"("id") ON DELETE RESTRICT ON UPDATE NO ACTION`,
    );
    await queryRunner.query(
      `ALTER TABLE "event_images" ADD CONSTRAINT "FK_event_images_event" FOREIGN KEY ("event_id") REFERENCES "events"("id") ON DELETE CASCADE ON UPDATE NO ACTION`,
    );
    await queryRunner.query(
      `ALTER TABLE "favorites" ADD CONSTRAINT "FK_favorites_user" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE NO ACTION`,
    );
    await queryRunner.query(
      `ALTER TABLE "favorites" ADD CONSTRAINT "FK_favorites_event" FOREIGN KEY ("event_id") REFERENCES "events"("id") ON DELETE CASCADE ON UPDATE NO ACTION`,
    );

    // Limitar el acceso REST de Supabase al backend con service_role.
    const tables = ['users', 'categories', 'events', 'event_images', 'favorites'];

    for (const table of tables) {
      await queryRunner.query(`ALTER TABLE public.${table} ENABLE ROW LEVEL SECURITY;`);
      await queryRunner.query(
        `CREATE POLICY "backend_full_access" ON public.${table} FOR ALL TO service_role USING (true) WITH CHECK (true);`,
      );
      await queryRunner.query(
        `REVOKE ALL ON TABLE public.${table} FROM anon, authenticated;`,
      );
      await queryRunner.query(
        `GRANT ALL ON TABLE public.${table} TO service_role;`,
      );
    }

    // Cuenta inicial de desarrollo; cambiar la contraseña antes de producción.
    const hashedPassword = await bcrypt.hash(ADMIN_PASSWORD, 10);
    await queryRunner.query(
      `INSERT INTO "users" ("name", "email", "password", "role") VALUES ($1, $2, $3, 'admin')`,
      [ADMIN_NAME, ADMIN_EMAIL, hashedPassword],
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    // El rollback elimina los datos de estas tablas junto con el esquema.
    await queryRunner.query(`DROP TABLE "favorites"`);
    await queryRunner.query(`DROP TABLE "event_images"`);
    await queryRunner.query(`DROP TABLE "events"`);
    await queryRunner.query(`DROP TABLE "categories"`);
    await queryRunner.query(`DROP TABLE "users"`);
    await queryRunner.query(`DROP TYPE "public"."users_role_enum"`);
  }
}