# Migraciones

Las migraciones Alembic son incrementales y se ejecutan mediante el contenedor `migrate` antes de iniciar API y worker.

La revisión inicial es intencionalmente vacía: establece una línea base verificable sin crear tablas de negocio antes de diseñar el módulo de trabajos.
