CREATE OR REPLACE FUNCTION crm.fusion_previsualizar_fn(p_perdedora uuid, p_canonica uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_p crm.inversionistas%rowtype; v_c crm.inversionistas%rowtype; v_lead crm.leads%rowtype;
  v_bloq text[]; v_adv text[] := '{}'; v_foto jsonb;
  v_tp crm.inversionista_responsables%rowtype; v_tc crm.inversionista_responsables%rowtype;
begin
  if not coalesce((select f.activo from crm.multiempresa_flags f where f.nombre = 'resolver_en_puertas'), false) then
    raise exception 'Identidad unificada apagada' using errcode = 'P0409';
  end if;
  if not private.es_gerencia_crm_activa() then
    raise exception 'Solo Gerencia previsualiza una fusión' using errcode = '42501';
  end if;
  v_bloq := private.fusion_bloqueos(p_perdedora, p_canonica);
  select * into v_p from crm.inversionistas where id = p_perdedora;
  select * into v_c from crm.inversionistas where id = p_canonica;
  if v_p.id is null or v_c.id is null or p_perdedora = p_canonica then
    return pg_catalog.jsonb_build_object('viable', false, 'bloqueos', pg_catalog.to_jsonb(v_bloq),
      'advertencias', '[]'::jsonb, 'hash', null, 'foto', null, 'impacto', null);
  end if;
  if exists (select 1 from crm.inversionista_identificadores a
             join crm.inversionista_identificadores b on b.tipo_documento = a.tipo_documento and b.documento_normalizado <> a.documento_normalizado
             where a.inversionista_id = p_perdedora and b.inversionista_id = p_canonica and a.estado = 'vigente' and b.estado = 'vigente') then
    v_adv := pg_catalog.array_append(v_adv, 'Las dos tienen un documento vigente del mismo tipo: una está mal; corrige el documento después de fusionar (indicando cuál sale)'::text);
  end if;
  if v_p.no_contactar <> v_c.no_contactar
     or exists (select 1 from crm.leads l where l.id in (select private.leads_de_identidades(array[p_perdedora, p_canonica])) and l.no_contactar <> (v_p.no_contactar or v_c.no_contactar)) then
    v_adv := pg_catalog.array_append(v_adv, 'Vetos distintos: el resultado es «No contactar» en la persona y el lead, y se cancelan las tareas pendientes del lead'::text);
  end if;
  select * into v_tp from crm.inversionista_responsables where inversionista_id = p_perdedora and hasta is null;
  select * into v_tc from crm.inversionista_responsables where inversionista_id = p_canonica and hasta is null;
  if v_tp.responsable_id is not null and v_tc.responsable_id is not null and v_tp.responsable_id <> v_tc.responsable_id then
    v_adv := pg_catalog.array_append(v_adv, 'Responsables de relación distintos: gana el de la canónica; se cierra el tramo de la perdedora'::text);
  elsif v_tp.responsable_id is not null and v_tc.responsable_id is null then
    v_adv := pg_catalog.array_append(v_adv, 'La canónica hereda el responsable de relación de la perdedora'::text);
  end if;
  if exists (select 1 from crm.inversiones where inversionista_id = p_perdedora)
     or exists (select 1 from crm.inversion_titulares where inversionista_id = p_perdedora)
     or exists (select 1 from crm.cierres_externos where inversionista_id = p_perdedora) then
    v_adv := pg_catalog.array_append(v_adv, 'La perdedora tiene inversiones, titularidades o cierres: se reapuntan a la canónica; el dinero y sus fotos no se tocan'::text);
  end if;
  if exists (select 1 from crm.inversionistas where inversionista_canonico_id = p_perdedora) then
    v_adv := pg_catalog.array_append(v_adv, 'La perdedora es canónica de otras identidades fusionadas: se aplanan a la nueva canónica'::text);
  end if;
  select * into v_lead from crm.leads where id in (select private.leads_de_identidades(array[p_perdedora, p_canonica])) order by id limit 1;
  if v_lead.id is not null and not v_lead.activo then
    v_adv := pg_catalog.array_append(v_adv, 'El lead está inactivo: no se deja nota de actividad (el libro de fusiones es el rastro)'::text);
  end if;
  v_adv := pg_catalog.array_append(v_adv, 'La conversión mensual sigue siendo por lead/cliente hasta Contrato-F3: la fusión no altera cifras ni meses sellados'::text);
  v_foto := private.fusion_estado_jsonb(p_perdedora, p_canonica);
  return pg_catalog.jsonb_build_object(
    'viable', pg_catalog.cardinality(v_bloq) = 0,
    'bloqueos', pg_catalog.to_jsonb(v_bloq),
    'advertencias', pg_catalog.to_jsonb(v_adv),
    'hash', private.idem_hash(v_foto),
    'foto', v_foto,
    'impacto', pg_catalog.jsonb_build_object(
      'leads', (select count(*) from private.leads_de_identidades(array[p_perdedora])),
      'puente', (select count(*) from crm.inversionista_leads where inversionista_id = p_perdedora),
      'tareas_pendientes', (select count(*) from crm.tareas t where t.estado = 'pendiente' and t.lead_id in (select private.leads_de_identidades(array[p_perdedora, p_canonica]))),
      'identificadores', (select count(*) from crm.inversionista_identificadores where inversionista_id = p_perdedora and estado = 'vigente'),
      'tramos', (select count(*) from crm.inversionista_responsables where inversionista_id = p_perdedora and hasta is null),
      'cierres', (select count(*) from crm.cierres_externos where inversionista_id = p_perdedora),
      'inversiones', (select count(*) from crm.inversiones where inversionista_id = p_perdedora),
      'titulares', (select count(*) from crm.inversion_titulares where inversionista_id = p_perdedora),
      'reservas', (select count(*) from crm.conversion_reservas where inversionista_id = p_perdedora),
      'predecesoras', (select count(*) from crm.inversionistas where inversionista_canonico_id = p_perdedora)));
end;
$function$
