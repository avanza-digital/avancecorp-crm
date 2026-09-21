-- Re-declarar un verificador cuyo cuerpo cambió — SOLO cuando el vigilante dice
-- «Contadores exentos cuyo cuerpo CAMBIO desde que se declararon (la razon caduco)».
--
-- Por qué existe: la exclusión de los verificadores del censo va atada a la
-- HUELLA de su cuerpo (eso es lo que impide que sea una puerta abierta). Si otra
-- migración redefine `crm.contrato_eliminar_auditado` —pasó el 21/09 con dos
-- sesiones en paralelo— la huella declarada deja de casar y el vigilante salta.
-- Eso es el detector funcionando, no un fallo. Este guion refresca la huella
-- DESPUÉS de que alguien haya mirado el cuerpo nuevo y confirmado que sigue
-- siendo un falso positivo.
--
-- NO ES AUTOMÁTICO A PROPÓSITO: si el cuerpo cambió, alguien tiene que volver a
-- mirar si de verdad sigue sin contar leads. Imprime el `count(` que encuentra
-- para que se pueda comprobar de un vistazo.
begin;
set local lock_timeout = '5s';
lock table private.analitica_leads_citas_exenciones, private.analitica_lc_sello
  in share row exclusive mode;

-- Lo que hay que mirar ANTES de aceptar: ¿sus count() siguen siendo del catálogo?
select p.oid::regprocedure::text as verificador,
       (select string_agg(m[1], ' ⏐ ') from regexp_matches(p.prosrc, '([^\n]*count\s*\([^\n]*)', 'g') m) as sus_count,
       (select string_agg(m[1], ' ⏐ ') from regexp_matches(p.prosrc, '([^\n]*crm\.leads[^\n]*)', 'g') m) as donde_menciona_leads
from pg_proc p
where p.oid = 'crm.contrato_eliminar_auditado(uuid,uuid)'::regprocedure;

update private.analitica_leads_citas_exenciones e
set huella = md5(regexp_replace(regexp_replace(lower(coalesce(p.prosrc, pg_get_functiondef(p.oid))),
      '--[^' || chr(10) || ']*', ' ', 'g'), '/\*.*?\*/', ' ', 'g')),
    declarado_en = now()
from pg_proc p
where p.oid = 'crm.contrato_eliminar_auditado(uuid,uuid)'::regprocedure
  and e.objeto = 'crm.contrato_eliminar_auditado(uuid,uuid)';

update private.analitica_lc_sello
  set sello = private.huella_exenciones_analitica_lc(), sellado_en = now() where id;

-- El veredicto. Si no dice OK, NO se hace commit.
select private.assert_analitica_leads_citas() as vigilante;

-- Cambiar a `commit;` solo si la línea de arriba dijo OK y el cuerpo nuevo
-- sigue sin contar leads.
rollback;
