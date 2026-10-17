# Reemplazar inversión — pruebas, aplicación y reversa

- Migración: `../../migrations/20261017162053_crm_reemplazar_inversion.sql`. Plan y decisiones: vault
  «Reemplazar inversion - plan por fases (2026-10-17)».
- `candados-produccion/trg_contratos_observar_rentabilidad.sql`: cuerpo de producción (17/10/2026, md5 9a0c0411…) del
  observador de tasa que la migración cambia por anclas (queda en 1606e0a6…). Lo usa `reversa.sql`.
- `test-reemplazar-inversion.sql`: batería en un banco Docker con el esquema de producción (una transacción, ROLLBACK).
  Como superusuario: `docker exec -i -e PGPASSWORD=<local> <contenedor> psql -U supabase_admin -h 127.0.0.1 -d postgres
  -v ON_ERROR_STOP=1 -f - < test-reemplazar-inversion.sql`. Última corrida: 45 bloques PASS.
- `mutantes.py`: por cada defensa, un mutante que la neutraliza dentro de la transacción de la batería
  (`python3 -I mutantes.py`). Última corrida: 43/43 muertos.
- `carrera.sh`: tres carreras con dos conexiones reales (cierre de mes en curso, alta del mismo cliente, mes de destino
  ocupado). Última corrida: 3/3 PASS.
- `carrera-pago.sh`: E4, un pago en curso contra el reemplazo, en una base desechable copiada del banco (se borra al
  terminar). Esperado P0409 «cuotas pagadas»; con `MUTANTE=1` (sin el candado del cronograma) termina OK: el pago se
  perdería. Última corrida: los dos PASS.
- `carrera-reversa.sh`: E5, la reversa mientras un reemplazo está por confirmarse (misma base desechable). Esperado:
  columna, CHECK y copia conservados; con `MUTANTE=1` (sin el candado inicial de la reversa) la columna se pierde.
  Última corrida: los dos PASS.
- `banco/`: montaje del banco (`montar.sh`) y del stack local propio para el gate entero (`gate-rls-stack.sh <etiqueta>`,
  con `CRM_RLS_EXIGE_REEMPLAZAR_INVERSION=1`). El gate deja 15 fallos ajenos en el banco, iguales antes y después.
- `reversa.sql`: retira las dos puertas y el núcleo y devuelve el observador a 9a0c0411…; se niega si el observador cambió
  después de la migración; conserva la columna `reemplazada_por` si alguna copia la usa.
- `generar-registrador.mjs` → `registrar.sql`: registra la versión en `supabase_migrations.schema_migrations`
  (`db query --linked --file` no lo hace). Regenerarlo tras CADA edición de la migración.
- `comprobar-tras-aplicar.sql`: solo lectura, termina en ROLLBACK; veredicto `APTA` / `NO APTA` en una fila.

## Orden para publicar (lo hace Miguel con `!`; nunca `db push` ni `apply_migration` directo)

1. Branch de Supabase o banco al día con producción: aplicar, batería, `test-rls.mjs` y advisors.
2. Producción: `supabase db query --linked --file supabase/migrations/20261017162053_crm_reemplazar_inversion.sql`
   (el preflight se niega si alguna huella cambió: entonces se recalcula, no se fuerza).
3. `supabase db query --linked --file supabase/scripts/reemplazar-inversion/registrar.sql`.
4. `supabase db query --linked --file supabase/scripts/reemplazar-inversion/comprobar-tras-aplicar.sql` → `APTA`
   (`vigia_sin_pendientes` es informativo).
5. Sin pantalla todavía (Fase 2): las puertas solo se llaman con sesión de un admin del portal; no con `service_role`.
