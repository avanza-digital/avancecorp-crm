# Procedencia del lead en Leads (sistema o manual)

Estado: **ensayado en el banco el 19/09/2026; pendiente de instalar en
producción** (acta en `../../migrations/MIGRACIONES.md`, entrada `20260919170500`).

Pedido de Miguel (19/09/2026): «que en el sistema se pueda diferenciar un lead
que viene del sistema de los que los mismos analistas cargan», con algo
«amigable» que «a simple vista distinga el lead», además del filtro.

## Qué distingue

- **Sistema**: entró solo por el puente (`crm-importar-leads` / puerta SQL del
  importador). Sin `alta_manual` y sin autor.
- **Manual**: lo registró una persona por la RPC de alta. `alta_manual = true`
  (columna sellada e inmutable desde el 01/09) **o**, para los leads anteriores a
  esa columna, tener `creado_por`. El puente nunca escribe autor, así que la
  regla no puede confundir un lead del sistema con uno manual.
- Cifras de producción al 19/09: 1 864 del sistema (landing 837, formulario
  1 027); 82 manuales con marca (desde el 01/09); 36 manuales de agosto sin
  marca pero con autor. Los 36 salen bien por la regla del autor, sin tocar datos
  sellados (un backfill de `alta_manual` sería decisión aparte: la columna es
  inmutable y movería «manual propio» en Citas de agosto, mes que sigue reabierto).

## Contrato

- `crm.cartera_filtrada_fn` recibe `p_procedencia text default null` con dominio
  `sistema` | `manual`; otro valor → `22023`, nunca un «cero resultados»
  silencioso. Sin él la respuesta es idéntica a la del 16/09 salvo la clave
  `procedencia` (nula) y, por fila, `procedencia` y `cargado_por` (uuid del autor
  o null).
- Acota la **misma base** que etapa, analista, búsqueda, recepción y origen:
  filas, totales, capital y embudo salen del mismo conjunto antes de paginar.
- Cambia la firma (11 argumentos). La de 10 se retira en la misma migración
  (una sola candidata para PostgREST); su declaración analítica se **mueve** a la
  firma nueva conservando `declarado_en` y se re-sella.
- Ámbito, RLS, invoker, `search_path` vacío, permisos (`authenticated` sí;
  `anon`/`service_role` no) y el adaptador `resumen_cartera_fn()` (solo usa
  `->'resumen'`) no cambian. `alta_manual` y `creado_por` ya tenían GRANT SELECT
  para `authenticated`; el preflight lo comprueba porque la RPC es invoker.
- Front: «Sistema y manual» no viaja (un servidor previo sigue respondiendo); con
  una procedencia elegida el cliente exige el eco y filas coherentes o rechaza la
  respuesta (`ROW_CONTRACT`). El nombre del autor se resuelve en pantalla con el
  equipo visible; si no se conoce, el chip dice solo «Manual». El drawer y la
  tarjeta flotante leen el ámbito (select directo): el mapper deriva la misma
  regla desde `alta_manual` + `creado_por`.

## Ensayo local

Copia propia `cartera_procedencia_20260919` en el contenedor del banco, creada
desde `cartera_origen_20260916` (que terminó su ensayo con la función del 16/09
instalada, md5 `be330214…` = producción al 19/09). Las copias nacen como
`supabase_admin`; los ensayos corren como `postgres` (owner/ACL como prod).

```bash
node supabase/scripts/cartera-procedencia/ensayar.mjs
```

Pasos: gate analítico verde antes → equivalencia sin filtro para los 11 actores
(función anterior en `pg_temp` vs. nueva, quitando las claves nuevas y
validándolas por fila; y `resumen_cartera_fn()` antes vs. después; misma
transacción, deshecha) → instalación con un contador ajeno en rojo (deshecha:
conserva el rojo y declara la firma nueva) → instalación real + gate + oráculo
propio + partición «sistema + manual = todo» por actor sobre los datos de la
copia → **genera** `reversa.sql` y `../registrar-20260919170500.sql` con las
huellas medidas → guardas de la reversa (sello alterado y función corregida se
rechazan; rojo ajeno se conserva) → reversa + gate + oráculo del 16/09 →
reinstalación + gate + oráculo. Escribe `verificacion.json`.

## Publicación y reversa

1. Instalar `20260919170500_crm_cartera_filtro_procedencia.sql` en producción por
   la vía autorizada (Miguel con `!`, `db query --linked --file`), luego el
   registrador `../registrar-20260919170500.sql`, y anotar el acta en
   `MIGRACIONES.md`.
2. Comprobar que PostgREST ya sirve la firma nueva, sin credenciales de persona:
   un POST anónimo a `/rest/v1/rpc/cartera_filtrada_fn` con
   `{"p_procedencia":"manual"}` debe responder `42501`; `{"p_nope":1}` → `PGRST202`.
3. Publicar el front construido del commit fusionado (release + preflight).
4. Reversa: primero retirar el front; luego `reversa.sql` restaura la firma de 10
   byte a byte y su declaración analítica. No toca datos.

## Estado del gate analítico en producción (19/09)

35 contadores y `crm.contrato_eliminar_auditado(uuid,uuid)` sin declarar (desde
el 16/09, otra sesión): el assert global sigue en rojo por esa causa. Esta
migración no lo tapa ni lo agrava: su postflight exige que el conjunto en rojo
quede exactamente igual y que la firma nueva quede declarada y vigente.
