# Filtro de origen en Leads

Solicitud de Miguel (16/09/2026): que la pantalla **Leads** tenga un filtro de
origen y que todos sus componentes lo obedezcan a la vez. Es un filtro más en el
módulo que ya tiene etapa, analista, búsqueda y recepción (13/09).

## Contrato

- `crm.cartera_filtrada_fn` recibe `p_origen text default null`. Sin él la
  respuesta es idéntica a la vigente salvo la clave nueva `origen` (nula).
- El origen acota la **misma base** que el resto de filtros: filas, total,
  capital, activos, convertidos y distribución por etapa salen del mismo conjunto
  antes de paginar. Compone con etapa, analista, búsqueda y recepción.
- Dominio: los 8 valores del CHECK de `crm.leads.origen` (5 vigentes y 3
  históricos: `web`, `campania`, `whatsapp`). Otro valor → `22023`, nunca un
  «cero resultados» silencioso.
- Cambia la firma (10 argumentos). La de 9 se retira en la misma migración para
  que PostgREST no vea dos candidatas; su declaración analítica se **mueve** a la
  firma nueva (la lista de exenciones no admite borrados) y se re-sella.
- Ámbito, RLS, permisos (`authenticated` sí; `anon`/`service_role` no), invoker,
  `search_path` vacío y el adaptador `resumen_cartera_fn()` no cambian.
- Front: `«Todos los orígenes»` no viaja (un servidor previo sigue respondiendo);
  con un origen elegido el cliente exige el eco `origen` y filas coherentes, o
  rechaza la respuesta (`ROW_CONTRACT`). Por eso el orden es **servidor primero**.

## Ensayo local

Copia sintética propia en el contenedor local (`banco.mjs` fija base y
contenedor; nunca acepta destinos externos). La copia se preparó a paridad con
producción: funciones con el md5 vivo de `cartera_filtrada_fn` (9 args) y del
resumen, gobernanza analítica sembrada con las filas de producción y gate verde.

```bash
node supabase/scripts/cartera-origen/ensayar.mjs
```

Pasos: gate analítico verde antes → equivalencia sin filtro para todos los
actores (función anterior en `pg_temp` vs. nueva, misma transacción, deshecha) →
instalación real + gate + `test-cartera-origen.sql` → `reversa.sql` + gate +
oráculo del 13/09 → reinstalación + gate + oráculo. Escribe `verificacion.json`.

## Publicación y reversa

1. Instalar `20260916220124_crm_cartera_filtro_origen.sql` en producción por la
   vía autorizada (Miguel con `!`, `db query --linked --file`), registrar la
   versión y anotar el acta en `MIGRACIONES.md`.
2. Publicar el front construido del commit verificado (release + preflight).
3. Reversa: primero retirar el front; luego `reversa.sql` restaura la firma de 9
   argumentos byte a byte (definición tomada de producción el 16/09) y su
   declaración analítica. No toca datos.

## Estado del gate analítico en producción (16/09)

Al preparar esta migración el censo de producción tenía **35** contadores y
`crm.contrato_eliminar_auditado(uuid,uuid)` (migración `20260916160000`, otra
sesión) **sin declarar**: `private.assert_analitica_leads_citas()` está en rojo
por esa causa. Esta migración no lo tapa ni lo agrava: su postflight exige que el
conjunto en rojo quede exactamente igual que antes y que la firma nueva quede
declarada y vigente. Declarar esa función es tarea de quien la publicó.
