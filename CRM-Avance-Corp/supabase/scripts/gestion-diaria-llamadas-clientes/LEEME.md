# Gestión Diaria cuenta las llamadas a CLIENTES — kit de ensayo (19/10/2026)

Migración: `supabase/migrations/20261019170422_crm_gestion_diaria_llamadas_clientes.sql`.
Decisión de Miguel (19/10/2026): las llamadas a clientes suman al mismo número «Llamadas» del analista, a la tasa de
contacto y a los cortes de jornada / mínimo de útiles.

## Qué hay aquí

| Archivo | Para qué |
| --- | --- |
| `banco.mjs` | Fija el banco PROPIO (contenedor `crm-banco-llamadas-clientes-20261019`, base `postgres`). Nunca producción. |
| `ensayar.mjs` | Ensayo completo: foto antes, huellas en dos pasadas (migración y reversa), instalación, simulación banco-only de `20261016211001`, gate, 12 mutantes nuevos + 24 viejos, oráculo, censo intacto, cadena en solo lectura con tiempos, reversa exacta, reinstalación determinista. Escribe `verificacion.json`. |
| `test-gestion-diaria-llamadas-clientes.sql` | Oráculo (termina en ROLLBACK): dos equipos, un cliente con 14 tareas/cierres y el legado, una llamada a lead por la puerta real; lecturas como analista, supervisor, otro equipo, gerencia, sin sesión y con la postventa apagada; paridad con `gestiones_resumen_fn`. |
| `reversa.sql` | Devuelve lector, agregador y los tres gates a producción (compone con otros re-sellados) y retira el ayudante y los mutantes. |
| `verificacion.json` | Huellas selladas y resultado del último ensayo. |
| `generar-registrador.mjs` | Genera `../registrar-20261019170422.sql` (fail-closed): registra la migración en `supabase_migrations.schema_migrations` SOLO si lo instalado es lo ensayado. |
| `comprobar-tras-aplicar.sql` | Solo lectura: qué sella cada gate y cómo están citas/analista tras aplicar. |
| `AVISO-GUARDIANES-1610.md` | Lo que debe saber el re-sellado de guardianes en pausa (`20261016211001`). |

## Cómo se montó el banco (≈15 min, receta §5 de `backfill-conversion-2026-09/LEEME.md`, sin el stack compartido)

```bash
docker run -d --name crm-banco-llamadas-clientes-20261019 -e POSTGRES_PASSWORD=postgres -p 127.0.0.1:55499:5432 public.ecr.aws/supabase/postgres:17.6.1.167
supabase db dump --linked --schema public,crm,private --keep-comments -f <scratch>/esquema.sql   # solo lectura de prod
# roles crm_metricas_bridge / crm_gestion_diaria_lector, extensiones btree_gist y pg_trgm en `extensions`
# auth.users de la imagen es un esqueleto: añadir email_confirmed_at, email_change_token_new… como supabase_admin
psql -f esquema.sql (5 errores esperados: alter owner) → banco/duenos-funciones.sql → siembra-banco + siembra-gerencia
# configuración de prod sin datos personales (adaptación de banco/copiar-config.sh al contenedor; `actualizado_por`
# queda huérfano: el oráculo lo pone a NULL al tocar una bandera)
```

Acreditación: 22 huellas (`md5(pg_get_functiondef)`) de Gestión Diaria/postventa iguales a producción antes de instalar
(`acreditar-funciones.sql` en el scratch de la sesión; la lista está en `ensayar.mjs` → `PROD`).

## Cómo correrlo

```bash
cd CRM-Avance-Corp/supabase/scripts/gestion-diaria-llamadas-clientes
node ensayar.mjs          # ENSAYO OK · 12 mutantes nuevos · 24 viejos · huellas
node generar-registrador.mjs   # tras el ensayo: regenera el registrador con las huellas selladas
```

Si la migración trae `_PENDIENTE_` (placeholders), la primera pasada instala sin postflight, mide las tres huellas
(ayudante, lector, agregador) y las escribe en el archivo; la segunda instala la versión sellada.

## Lo que el ensayo enseñó

- 🔴 **`crm.postventa_estado_fn()` no sirve dentro del marcador**: pasa por `private.postventa_modo()` (`for share nowait`) y
  PostgREST ejecuta las puertas STABLE en transacción de SOLO LECTURA → `cannot execute SELECT FOR SHARE in a read-only
  transaction`. El ayudante lee las banderas sin candado, como `private.postventa_visible_actor` (RLS de tareas). Probar
  SIEMPRE la cadena con `begin read only` antes de dar por bueno un lector.
- Un gate en rojo detecta cualquier mutante en vacío: los mutantes nuevos se niegan si el gate ya está rojo. Para que los
  24 viejos fueran concluyentes, el ensayo SIMULA en el banco el re-sellado ajeno pendiente (roster en el gate del analista,
  censo analítico neutralizado en el pulso) y lo deshace antes de comparar con producción.
- `assert_gestion_diaria_citas` (G4b) y `assert_gestion_diaria_pulso` también sellaban el agregador/lector: tres gates que
  re-sellar, no uno. El preflight exige cada ancla exactamente una vez para componer con otros re-sellados.
- El censo analítico caza `count(` junto a `crm.tareas` + `execute`: el mutante «contador crudo» se escribe con el
  literal partido (`cou$m$ || $m$nt(`) para no entrar en el censo él mismo.

## Aplicación en producción (la hace Miguel)

1. Comprobar que el lector y el agregador vivos siguen siendo `27d25609…` y `7c5d14e6…` y que los tres gates traen las
   anclas (el preflight lo exige y se niega si no).
2. `supabase db query --linked --file supabase/migrations/20261019170422_crm_gestion_diaria_llamadas_clientes.sql`
   (en UN mensaje). Avisos esperados del postflight: «gate de citas OK», «gate del analista sigue en rojo SOLO por
   crm.equipo_visible_fn», «gate del pulso sigue en rojo SOLO por …».
3. Verificar: `select private.assert_gestion_diaria_citas();` → OK; Vladimir en Mi día pasa de «1 llamada» a «6».
4. `supabase db query --linked --file supabase/scripts/registrar-20261019170422.sql` (se niega si lo instalado no es lo
   ensayado) y `supabase db query --linked --file supabase/scripts/gestion-diaria-llamadas-clientes/comprobar-tras-aplicar.sql`.
5. Después, `/release-crm` con el texto nuevo de Mi día (la RPC no cambia de forma: los dos órdenes son compatibles).

## Decisiones declaradas para Miguel (no bloquean)
- Directorio (lector global) sigue sin ver llamadas a clientes en Pulso/Equipo/día del analista, igual que en el Registro.
- «Llamadas por lead» (llamadas, ahora con clientes, / leads tocados) y los «con actividad» del Pulso (solo actividades
  de leads) quedan como están; corregirlos toca tres núcleos sellados más.
