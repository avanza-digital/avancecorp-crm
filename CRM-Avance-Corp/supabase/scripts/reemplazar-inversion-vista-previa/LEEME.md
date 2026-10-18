# Reemplazar inversión · vista previa del mes — pruebas, aplicación y reversa

- Migración: `../../migrations/20261017211313_crm_reemplazar_inversion_vista_previa.sql`. Va DESPUÉS de la Fase 1
  (`20261017162053`, kit en `../reemplazar-inversion/`): su preflight la exige con sus huellas.
- Qué es: `crm.reemplazar_inversion_vista_previa_fn` (solo lectura) dice en qué mes queda la venta antes de confirmar el
  reemplazo y si el contrato tiene cuotas pagadas (el reemplazo se negaría), y el núcleo del reemplazo usa las MISMAS reglas
  (`private.reemplazo_dia_registro_venta`, `private.reemplazo_fecha_comercial`, `private.contrato_tiene_cuotas_pagadas`).
  Decisión de Miguel del 17/10/2026: consulta exacta en el servidor, una sola regla. Gate de realidad (producción, 17/10):
  de 514 inversiones Avance «nuevo» vigentes, 294 tienen cuotas pagadas: la pantalla lo avisa antes de llenar nada.
- `probar.sh`: corridas en el banco Docker (cada una en ROLLBACK): la batería ENTERA de la Fase 1 (45 bloques, con el
  núcleo que ahora usa los ayudantes), `test-vista-previa.sql` sobre la misma siembra (12 bloques: paridad en cada forma de
  calcular el mes, cuotas pagadas, roles y validaciones, que no escribe nada, catálogo) y el candado «nadie más los usa» de
  `reversa.sql` (se niega ante una función PL/pgSQL que llama a un ayudante en MAYÚSCULAS o con comillas; sin ella no
  estorba). Salida 0 = todo PASS (psql en 0 y el marcador final), 1 = una aserción FALLA, 3 = ERROR DE ENSAYO (no se llegó
  a probar). Última corrida (17/10 19:28): todo PASS.
- `mutantes.py`: una corrida BASE sin mutante tiene que pasar (si no, «ENSAYO INVÁLIDO», salida 2); luego 16 mutantes de
  los ayudantes y de la puerta. MUERTO solo si una aserción lo detecta (salida 1 de `probar.sh`); un error de ensayo cuenta
  en contra. Última corrida (17/10 19:28): base PASS, 16/16 muertos.
- Carreras de la Fase 1 con el núcleo parcheado (`../reemplazar-inversion/carrera.sh` y `carrera-pago.sh`, 17/10 19:30):
  E1–E3 3/3 PASS, E4 P0409 y su mutante sin bloqueo sigue perdiendo el pago (la carrera lo ve). E5 (reversa de la Fase 1)
  no aplica con esta migración puesta: su preflight se niega a propósito.
- `reversa.sql`: devuelve el núcleo a su huella de la Fase 1 (541ce30f…) y retira la vista previa (se niega si otra función
  la usa; busca el nombre sin mayúsculas ni comillas. Una llamada armada con EXECUTE y texto concatenado NO se ve: antes de
  revertir, revisar a mano si alguna función arma SQL dinámico con estos nombres). Probada en el banco: deja la Fase 1 en APTA y la batería de la Fase 1 en 45/45. **Revertir primero el front**
  (la pantalla llama a esta puerta). Como en la Fase 1, la reversa no borra la fila de `schema_migrations`.
- La puerta es VOLATILE a propósito y se llama por POST (supabase-js `rpc` lo hace por defecto): toma FOR SHARE del perfil y
  la membresía, que fallaría en una transacción de solo lectura. El postflight y la comprobación lo exigen.
- `generar-registrador.mjs` → `registrar.sql`; `comprobar-tras-aplicar.sql` (solo lectura, `APTA` / `NO APTA`). Desde esta
  migración, la comprobación de la Fase 1 da NO APTA en «huellas» a propósito (el núcleo cambió): vale la de aquí.

## Orden para publicar (lo hace Miguel con `!`; nunca `db push` ni `apply_migration` directo)

1. La Fase 1 entera, en el orden de su LEEME (migración → registrar → comprobar).
2. `supabase db query --linked --file supabase/migrations/20261017211313_crm_reemplazar_inversion_vista_previa.sql`.
3. `supabase db query --linked --file supabase/scripts/reemplazar-inversion-vista-previa/registrar.sql`.
4. `supabase db query --linked --file supabase/scripts/reemplazar-inversion-vista-previa/comprobar-tras-aplicar.sql` → `APTA`.
5. Después, el front con `/release-crm` (la pantalla llama a esta puerta y a las dos de la Fase 1).
