-- Identidad para el avance de Citas independiente de la conversión.
-- Extensión compatible del lector ya ensayado. No cambia los núcleos ni datos.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
lock table private.analitica_leads_citas_exenciones,private.analitica_lc_sello in share row exclusive mode;
do $cambio$
declare
  v_def text;
  v_buscar text := $buscar$'lead_id',p.id,'nombre',p.nombre_completo,$buscar$;
  v_nuevo text := $nuevo$'lead_id',p.id,'nombre',p.nombre_completo,
    'identidad_persona',coalesce(
      case when p.inversionista_id is not null then
        'persona:'||private.inversionista_canonica(p.inversionista_id)::text end,
      (select distinct 'persona:'||private.inversionista_canonica(i.id)::text
        from crm.inversionistas i where i.perfil_id=p.perfil_id),
      'perfil:'||p.perfil_id::text,
      'lead:'||p.id::text),$nuevo$;
begin
  v_def:=pg_get_functiondef('private.citas_gerencia_consulta(date,date)'::regprocedure);
  if md5(v_def)<>'75cad408f156fdfcffc0300d89ec22df' then
    raise exception 'El lector de Citas difiere de la versión preparada; conciliar antes de continuar';
  end if;
  perform private.assert_analitica_leads_citas();
  if (length(v_def)-length(replace(v_def,v_buscar,'')))/length(v_buscar)<>1 then
    raise exception 'No se reconoce el único punto de población del lector de Citas';
  end if;
  execute replace(v_def,v_buscar,v_nuevo);
end $cambio$;
update private.analitica_leads_citas_exenciones e
set huella=md5(regexp_replace(regexp_replace(lower(p.prosrc),'--[^\n]*',' ','g'),'/\*.*?\*/',' ','g')),
 razon='Detalle operativo Gerencia: citas desde citas_episodios y cierres desde conversion_cierres. Base mensual desde ledger inmutable lead_asignaciones, personas distintas por analista; identidad y autor de alta manual desde leads. Incluye hechos mensuales de registro de citas, atribución de origen y de cierre, y capital inicial real desde capital_episodios. No usa importes estimados como depósitos. La población conserva la identidad del inversionista canónico, con respaldo en perfil o lead cuando no existe ese vínculo, incluso sin conversión.'
from pg_proc p where p.oid='private.citas_gerencia_consulta(date,date)'::regprocedure
 and e.objeto='private.citas_gerencia_consulta(date,date)';
update private.analitica_lc_sello set sello=private.huella_exenciones_analitica_lc(),sellado_en=now() where id;
select private.assert_analitica_leads_citas();
commit;
