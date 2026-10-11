# Facturación fase 6: la ficha del inversionista dice quién vendió y para quién cuenta

**Estado (10/10/2026):** PENDIENTE DE APLICAR. Decisión de Miguel del 10/10 («los dos nombres»).

## Qué arregla

En la ficha del inversionista, «Analista de la operación» enseñaba `analista_origen_nombre`, que es a quién CUENTA la
inversión hoy: cadena de upgrade y, desde la regla de baja (`20261009200000`), quien heredó al cliente. En producción
(10/10, solo lectura) eso no es quien vendió en 46 de 820 inversiones, todas de 2 analistas dados de baja.

La migración `20261010203951_crm_ficha_analista_venta.sql` añade a cada inversión `analista_venta_id` y
`analista_venta_nombre`: el analista de cierre del contrato (`public.contratos.analista_cierre_id`) o el vendedor de la
cooperativa (`crm.cierres_externos.vendedor_id`). La pantalla enseña «Analista de la operación» (quien vendió) y, solo si
es otra persona, «Cuenta para». Ninguna cifra cambia.

## Archivos

- `vivo/crm.inversionista_ficha_fn.sql`: el cuerpo de producción al byte (`md5(pg_get_functiondef)` `d0c6543b…`).
- `generar.py`: cuerpo nuevo = vivo + dos fragmentos (las dos claves y un `cross join lateral` sobre la misma fila).
  Escribe la migración, `reversa.sql`, `ensayo-produccion.sql` y `registrar.sql`. Con `--verificar` no escribe nada.
- `banco-prueba.py`: 29 casos contra el banco Docker; deja el banco como estaba.

## Guardas de la migración

Antes de cualquier salida comprueba permisos, dueño y modo; se niega también si la ficha no es la medida (huella) o si ya
tiene comentario. Al terminar comprueba la huella nueva (`9d981c6c…`) y, por texto, que quitar los dos fragmentos
devuelve el cuerpo anterior al byte. Repetirla dice «ya aplicada». Con `crm.ficha_analista_venta_ensayo = 'on'` acaba
siempre en error: «ENSAYO FICHA PASS … SE DESHACE TODO» o, si ya estaba aplicada, «ENSAYO FICHA: ya aplicada». La
reversa solo revierte el cuerpo y el comentario que dejó la migración; cualquier otro estado lo deja para revisar a
mano.

## Producción

1. Ensayo (no deja nada): `supabase db query --linked -f <worktree>/CRM-Avance-Corp/supabase/scripts/ficha-analista-venta/ensayo-produccion.sql`
   → el error «ENSAYO FICHA PASS … SE DESHACE TODO» es el resultado correcto.
2. Miguel con `!`, desde `CRM-Avance-Corp/`: la migración y luego `registrar.sql`.
3. Comprobación (solo lectura): huella `9d981c6c…` y comentario puesto.
4. Después, el front con `/release-crm`. El orden importa poco: el front viejo ignora las claves nuevas y el nuevo
   tolera el servidor viejo (una sola línea, como antes).

Si algo corta entre la migración y el registro: repetir la migración dice «ya aplicada» y `registrar.sql` se puede
repetir.

## Verificación (10/10/2026, PRIMARY)

- Banco Docker (stack fact0c; la ficha y `private.cartera_f5_fuentes` con las huellas de producción): 29/29 PASS.
  - La ficha de 10 actores (gerencia, 3 supervisores, 5 vendedores y Directorio) para 40 inversionistas es la de antes
    más las dos claves, con el vendedor de su fila (103 inversiones).
  - Directorio sigue viendo solo Avance.
  - En una baja simulada, 28 inversiones salen con dos nombres:
    - gerencia y el heredero ven «vendió el que se fue · cuenta para el heredero»;
    - el que se fue ya no recibe la ficha (`null`).
  - Dos mutantes mueren: «venta = a quién cuenta» y «otra clave cambia».
  - Un contrato sin analista de cierre llega con las dos claves en null.
  - Ensayo (también sobre la ficha ya aplicada), negativas de permisos, cuerpo y comentario en la migración, el
    registro y la reversa, y la reversa con su repetición.
  - La cartera multiempresa del banco está apagada. Las fotos usan un doble de `crm.cartera_inversionistas_estado_fn`
    que la da por habilitada, el mismo antes y después.
- Front: prueba nueva en `cartera-inversionistas.test.tsx`, que pasa por el esquema valibot real. Cubre cinco casos:
  servidor viejo, misma persona, otra persona, vendedor desconocido y sin nadie. Cuatro mutantes mueren.
  `npm run check` PASS (6.612 pruebas, antes de la ronda de Codex).
- Codex r1 (`docs/encargos/2026-10-10-codex-ficha-analista-venta-fase6.md` y su respuesta): CHANGES_REQUESTED sin
  P0/P1. Se aceptan sus cuatro P2:
  - un vendedor que no consta sale como «Sin información» y no como quien cuenta;
  - permisos, dueño y modo se comprueban antes de cualquier salida, también en el registro;
  - el ensayo sobre la ficha ya aplicada también acaba en error;
  - la reversa no borra un comentario ajeno.

  No se añaden casos de renovación, upgrade ni segunda página, porque el cambio no tiene ninguna rama por categoría
  ni por página. El caso «vendió una persona y cuenta para otra» ya lo cubre la baja, con 28 inversiones.
- auditor-rls: PASS, sin nada que obligue a cambiar la migración. Tres P3:
  - el comentario explica por qué la función es DEFINER y qué ve Directorio (aplicado);
  - el banco mira la baja también como heredero y como el que se fue (aplicado);
  - el ciclo completo queda anotado (abajo).
- Ciclo de `supabase/migrations/LEEME.md`:
  - Quién la envuelve: nadie. Se comprobó en producción y en el banco con `pg_proc`; ninguna Edge Function la llama.
    `InversionFuenteSchema` es `v.object` en toda la historia del repo (el único `strictObject` del módulo es
    `InversionEliminadaSchema`, de otra RPC): un bundle viejo descarta las claves nuevas sin error.
  - `test-rls.mjs`: NOT RUN. No tiene ningún caso de esta función, y la visibilidad por rol la cubre este banco.
  - Advisors: después de aplicar.
- Datos de producción (10/10, solo lectura):
  - 0 contratos o cooperativas cuyo vendedor esté fuera de `crm.equipo`;
  - 9 contratos sin analista de cierre: si alguno entra en una ficha, sale «Sin información».
- Ensayo en producción con el texto final (md5 `a163657c…`, 10/10): «ENSAYO FICHA PASS: cuerpo d0c6543b -> 9d981c6c,
  solo los dos fragmentos, permisos iguales, comentario puesto — SE DESHACE TODO». Después, la huella seguía en
  `d0c6543b…`, con la misma ACL y sin comentario.
