-- SUPERSEDIDO (03/09): este oráculo probaba el trigger único de 200000, refutado y
-- retirado. Codex #9 mostró que no probaba lo que decía (nunca togglaba
-- resolver_en_puertas; perfil arbitrario; exigía inversionista_id no nulo contra
-- la rama histórica; siembra inexistente).
-- Comportamiento Y concurrencia del lote Contrato-F2 se prueban en UN arnés que
-- ejercita LAS PUERTAS (no el trigger), toggla la bandera de verdad y corre cada
-- sesión en una sola transacción:
--   scripts/siembra-banco-f3.sql        (la siembra que este gate referenciaba)
--   scripts/oraculo-f3-concurrencia.sh  (los 5 invariantes + paridad bandera off)
select 'ORACULO-F3-COMPORTAMIENTO: SUPERSEDIDO — usa oraculo-f3-concurrencia.sh' as aviso;
