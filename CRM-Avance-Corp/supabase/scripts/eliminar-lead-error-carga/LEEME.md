# Eliminar lead por error de carga — pruebas y reversa

- Migración: `../../migrations/20261015044917_crm_eliminar_lead_error_carga.sql`.
- `candados-produccion/`: cuerpo de producción (14/10/2026) de los 8 candados que la migración amplía.
- `test-eliminar-lead.sql`: pruebas en un banco Docker con el esquema de producción (una transacción, ROLLBACK).
  `PGTZ=America/Lima psql "<banco> user=supabase_admin" -v ON_ERROR_STOP=1 -f test-eliminar-lead.sql`
  (superusuario: usa `session_replication_role` para sembrar). Última corrida: 69/69 PASS.
- `reversa.sql`: retira las puertas y la llave y devuelve los candados a su huella de producción; se niega si un
  candado cambió después de la migración; conserva `crm.leads_eliminados` si tiene filas.
- Carreras de dos conexiones (INSERT y UPDATE concurrentes de una fila hija) y mutantes de la llave: ver la entrada
  del ledger `MIGRACIONES.md` (20261015044917).
- r2 (`20261015150731`): fichas de inversionista sin dinero, solicitudes canceladas y de tasa sin usar. Reversa:
  `reversa-r2.sql` (devuelve la puerta r1 —copia en `candados-produccion/crm.eliminar_lead_error_carga.r1.sql`— y el
  candado de tasa). Pruebas: el mismo `test-eliminar-lead.sql`, 100/100 PASS con r2.
