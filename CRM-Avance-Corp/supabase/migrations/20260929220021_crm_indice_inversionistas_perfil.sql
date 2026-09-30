-- ============================================================================
-- Índice crm.inversionistas(perfil_id) — la cartera deja de recorrer la tabla
-- entera por cada contrato
-- ============================================================================
-- Aprobado por Miguel el 2026-09-29 («ok vamos con la migracion»). Medido en
-- producción el mismo día con bloques de solo lectura que terminan en raise
-- (nota del vault «CRM - perfil de carga lectura vs escritura (2026-09-29)»):
--
--   crm.inversionistas se recorrió entera 22,6 M veces en ~97 h (12.462 M
--   filas, el 95 % de todo lo que lee el esquema crm). La causa es
--   private.cartera_f5_fuentes(): su lateral por contrato
--     select i.id from crm.inversionistas i where i.perfil_id = c.cliente_id
--   no puede usar el único índice de perfil_id, inversionistas_perfil_uidx,
--   porque es PARCIAL (perfil_id is not null and estado <> 'fusionado') y la
--   consulta no repite esa condición → 679 recorridos completos por llamada
--   (uno por contrato), ~90 ms. La alcanzan 11 puertas (postventa, cartera de
--   inversionistas, fichas, contexto y solicitud de inversión).
--
-- Un índice normal sobre perfil_id sirve esa búsqueda (y la de otras 18
-- funciones con el mismo patrón, p. ej. citas_gerencia_consulta y
-- citas_testigo_mes) SIN tocar ninguna función: solo cambia el plan. En el
-- ensayo deshecho de producción las 719 filas de cartera_f5_fuentes salieron
-- idénticas (md5 antes = después); las otras 18 no se midieron una a una. El
-- índice único parcial se queda: es la regla «un perfil, una persona viva», no
-- un acelerador.
--
-- Sin CONCURRENTLY a propósito: la tabla tiene ~565 filas y casi no se escribe
-- (70 escrituras en 4 días), así que la construcción es breve. El candado
-- (SHARE) no frena las lecturas; sí haría esperar a las escrituras a la tabla
-- mientras dure. lock_timeout solo acota la ESPERA por el candado: si hay una
-- escritura larga en curso, la migración aborta en 10 s en vez de quedarse en cola.
--
-- Reversa (sin pérdida de datos):
--   drop index if exists crm.inversionistas_perfil_idx;

begin;
set local lock_timeout = '10s';

create index if not exists inversionistas_perfil_idx
  on crm.inversionistas (perfil_id);

comment on index crm.inversionistas_perfil_idx is
  'Búsqueda de personas por perfil sin la condición del índice único parcial (inversionistas_perfil_uidx). La usa el lateral por contrato de private.cartera_f5_fuentes; antes recorría la tabla entera por cada contrato (medido 29/09/2026).';

commit;
