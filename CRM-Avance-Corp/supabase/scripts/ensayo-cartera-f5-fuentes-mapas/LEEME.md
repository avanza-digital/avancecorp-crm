# Ensayo: `private.cartera_f5_fuentes()` con canónica y atribución calculadas UNA vez (2026-09-30)

Todos los `.sql` son bloques `DO` que terminan SIEMPRE en `raise exception`: se ejecutan en producción
con `supabase db query --linked -f <archivo>` y **no dejan nada escrito** (incluido el `create or replace`
del 04, que se deshace con el raise). El resultado viaja en el texto del error (`MEDIDA|`, `FUNCIONES|`,
`FUENTES|`, `E2E|`).

| archivo | qué mide | resultado 30/09 |
|---|---|---|
| `01-ficha-familia-tareas-descartado.sql` | ficha con la familia precalculada en el `OR` de `tareas` | idéntica 29/29 · 499 → 492 ms: **no era el coste** |
| `02-ficha-tiempo-por-funcion.sql` | `set local track_functions='all'` + `pg_stat_xact_user_functions` | `cartera_f5_fuentes` ×7 = 291 de 490 ms; `inversionista_canonica` ×13.408 = 218 ms; `analista_atribuido_cadena` ×4.795 = 123 ms |
| `03-fuentes-mapas-oraculo-y-tiempo.sql` | `pg_temp.fuentes_b()` = mismo cuerpo con `canon_map`/`atrib_map` (jsonb) | 726/726 filas, md5 igual · **42 → 11 ms** |
| `04-fuentes-mapas-punta-a-punta.sql` | reemplazo deshecho + oráculo md5 de 29 fichas, agenda, estado, cartera, postventa_estado | **33/33 iguales** · ficha 509 → 284 · agenda 164 → 97 · cartera 193 → 126 · estado 52 → 19 |
| `medir-recorridos-por-llamada.sh` | `pg_stat_xact_user_tables` de UNA llamada como un actor | ver nota del vault «CRM - auditoria de indices (2026-09-30)» |

Lección: una CTE consultada con subconsulta correlacionada por fila (`select … from canon where id = x.id`) fue MÁS lenta
(82 ms); el mapa `jsonb_object_agg` leído con `->>` desde un InitPlan es lo que baja a 11 ms.
