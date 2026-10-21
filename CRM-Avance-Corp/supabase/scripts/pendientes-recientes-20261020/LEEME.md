# Pendientes de lo más reciente a lo más antiguo (20/10/2026)

Migración: `supabase/migrations/20261020214445_crm_gestion_diaria_pendientes_recientes_primero.sql`.
Decisión de Miguel: «el orden de los pendientes … quiero que sea al revés». Qué cambia, en una línea:
la lista de pendientes del supervisor/gerencia va por `vence_en` DESCENDENTE (puerta nueva `v3`; la
`v2` sigue ascendente para los bundles publicados) y, en la cola del analista, Vencidas, Sin primer
intento y Sin conversación van de lo más reciente a lo más antiguo («Hoy» sigue por hora).

## Archivos

- `prueba-banco.sql` — prueba sintética (actores y tareas propios, sin triggers; termina en ROLLBACK).
  Sólo corre en un banco cuyo `comment on database` sea `BANCO SINTETICO PENDIENTES RECIENTES / sin produccion`.
- `reversa.sql` — devuelve la base al byte anterior (núcleo G4a, cola 20260930190028, gate G4a; retira v3 y núcleo de 6).
- `AVISO-GUARDIANES-1610.md` — las huellas nuevas del gate H3, para la tarea de re-sellado en pausa.

## Banco (receta usada el 20/10/2026)

```bash
# desde CRM-Avance-Corp/ (solo lectura sobre producción; el volcado no lleva datos)
supabase db dump --linked --schema public,crm,private --keep-comments -f /ruta/esquema.sql
BANCO_CONTENEDOR=crm-banco-pendientes-recientes-20261020 BANCO_PUERTO=55531 \
  bash supabase/scripts/potencial-lead/banco/montar-banco.sh /ruta/esquema.sql
C=crm-banco-pendientes-recientes-20261020
docker exec -i -e PGPASSWORD=postgres $C psql -U supabase_admin -h 127.0.0.1 -d postgres -qAt \
  -c "comment on database postgres is 'BANCO SINTETICO PENDIENTES RECIENTES / sin produccion'"
# migración y reversa en UN mensaje (como `db query --file`):
docker exec -i -e PGPASSWORD=postgres $C psql -U postgres -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -qAt \
  -c "$(cat supabase/migrations/20261020214445_crm_gestion_diaria_pendientes_recientes_primero.sql)"
# prueba (sentencia a sentencia, como PostgREST):
docker cp supabase/scripts/pendientes-recientes-20261020/prueba-banco.sql $C:/tmp/p.sql
docker exec -e PGPASSWORD=postgres $C psql -U supabase_admin -h 127.0.0.1 -d postgres -v ON_ERROR_STOP=1 -f /tmp/p.sql
```

Resultado el 20/10/2026: paridad de las 9 funciones implicadas con producción; migración → repetida se
niega → reversa → repetida se niega → migración → repetida se niega; prueba `PENDIENTES_RECIENTES_OK`;
mutantes de la prueba (cola con el orden viejo, cursor hacia adelante, v3 ascendente) detectados.

## Instalación en producción (Miguel, con `!`)

```bash
supabase db query --linked --file supabase/migrations/20261020214445_crm_gestion_diaria_pendientes_recientes_primero.sql
supabase migration repair --status applied 20261020214445 --linked
# después, en app/: npm run gen:types
```

Luego el front con `/release-crm`. Para revertir: primero el front (release anterior), después `reversa.sql`,
dejando pasar el rato en que las pestañas abiertas con el bundle nuevo se recargan (el aviso de «versión
publicada» se lo pide); hasta entonces, con la v3 instalada no hay daño.
