-- Re-declara la exención analítica de crm.cierres_externos_fn(date) tras F8.
-- 20260914213928 (condiciones anuales COOPAC) recreó la función en producción
-- sin renovar su huella en private.analitica_leads_citas_exenciones; desde
-- entonces private.assert_analitica_leads_citas() falla con «cuerpo CAMBIÓ desde
-- que se declararon» y bloquea cualquier migración de Citas (detectado el 15/09
-- al ensayar 20260915170018). Sólo bendice exactamente el cuerpo de F8 (md5
-- verificado contra el archivo de la migración); no toca la función ni datos.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
lock table private.analitica_leads_citas_exenciones,private.analitica_lc_sello in share row exclusive mode;
do $f8$ begin
  if md5(pg_get_functiondef('crm.cierres_externos_fn(date)'::regprocedure))<>'d44dec0ba4b92ecd1991a7ff204dc57e' then
    raise exception 'crm.cierres_externos_fn(date) no es el cuerpo de F8 (20260914213928); revisar antes de re-declarar';
  end if;
  if (select huella from private.analitica_leads_citas_exenciones where objeto='crm.cierres_externos_fn(date)')
    is distinct from 'd6e3164f7ee36803bd30bf577efb65ac' then
    raise exception 'La exención de cierres_externos_fn ya no es la declarada el 30/08; revisar';
  end if;
end $f8$;
update private.analitica_leads_citas_exenciones e
set huella=md5(regexp_replace(regexp_replace(lower(p.prosrc),'--[^\n]*',' ','g'),'/\*.*?\*/',' ','g')),
  razon=e.razon||' F8 (20260914213928): el listado devuelve además plazo_meses y tasa_anual pactados por cierre; período, conteos, exclusión de demo y permisos conservados.'
from pg_proc p where p.oid='crm.cierres_externos_fn(date)'::regprocedure
  and e.objeto='crm.cierres_externos_fn(date)';
update private.analitica_lc_sello set sello=private.huella_exenciones_analitica_lc(),sellado_en=now() where id;
select private.assert_analitica_leads_citas();
commit;
