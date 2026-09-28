-- Recupera el canal de contratos con una acreditación explícita confirmada,
-- aunque el lead se haya cargado después del cierre comercial (backfill).
-- No cambia capital, categoría financiera, atribución, conversión ni fotos.
-- Reversa: restaurar el cuerpo capturado antes del cambio y su huella analítica;
-- retirar ranking_origenes_acreditados_filas solo después de restaurar el lector.
-- Ensayar en rama propia; nunca aplicar directamente en producción.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '90s';

do $preflight$
begin
  if (select md5(prosrc) from pg_proc where oid =
      'private.ranking_capital_origen_filas(timestamptz,timestamptz,uuid)'::regprocedure)
      is distinct from 'a3d29d52a70901186ade2d3267553c3f' then
    raise exception 'Cambió el lector de Ranking; recapturar antes de aplicar';
  end if;
  if (select sello from private.analitica_lc_sello where id)
      is distinct from private.huella_exenciones_analitica_lc() then
    raise exception 'El inventario analítico ya estaba des-sellado';
  end if;
  if exists (select 1 from pg_proc where oid in (
      'crm.ranking_origen_vendedor_fn(date,uuid)'::regprocedure,
      'private.ranking_origen_live(date,uuid,jsonb)'::regprocedure,
      'private.ranking_capital_origen_filas(timestamptz,timestamptz,uuid)'::regprocedure
    ) and (not prosecdef or proowner <> 'postgres'::regrole::oid)) then
    raise exception 'Cambió el rol efectivo de la cadena de lectura de Ranking';
  end if;
end;
$preflight$;

-- Núcleo de lectura: hechos sin agregación. La acreditación ya contiene
-- fuente y origen confirmados; no se infiere identidad por nombre o contacto.
create function private.ranking_origenes_acreditados_filas(p_contrato_ids uuid[])
returns table (contrato_id uuid, origen text, fecha_comercial date)
language sql stable security definer set search_path = ''
as $function$
  select ca.fuente_id, ca.origen, ca.fecha_comercial
  from crm.conversion_acreditaciones ca
  where ca.fuente_tipo = 'contrato' and ca.fuente_id = any(p_contrato_ids)
    and ca.estado = 'acreditada' and ca.periodo_comercial >= date '2026-09-01'
    and exists (select 1 from crm.conversion_politica where activada_en is not null)
    and private.conversion_exclusion_fuente(ca.fuente_tipo, ca.fuente_id) = 'elegible';
$function$;
alter function private.ranking_origenes_acreditados_filas(uuid[]) owner to postgres;
revoke all on function private.ranking_origenes_acreditados_filas(uuid[])
  from public, anon, authenticated, service_role;
comment on function private.ranking_origenes_acreditados_filas(uuid[]) is
  'Canales explícitamente acreditados de contratos elegibles desde septiembre de 2026. Filas sin agregar, sin importes y sin acceso de clientes.';

-- Cambio acotado sobre la versión viva verificada. CREATE OR REPLACE conserva
-- la firma, owner, ACL y configuración de la función anterior.
do $cambio$
declare
  v_original text := pg_get_functiondef(
    'private.ranking_capital_origen_filas(timestamptz,timestamptz,uuid)'::regprocedure);
  v_nuevo text;
  v_patron text := E'        ) then ''cartera''\n        else ''sin_origen''';
begin
  if (length(v_original)-length(replace(v_original,v_patron,'')))/length(v_patron) <> 1 then
    raise exception 'El fallback esperado no aparece exactamente una vez';
  end if;
  v_nuevo := replace(v_original,
    v_patron,
    E'        ) then ''cartera''\n        when acreditado.cantidad > 0 then\n          case when acreditado.origenes_distintos = 1 then acreditado.origen_unico else ''sin_origen'' end\n        else ''sin_origen''');
  if v_nuevo = v_original then raise exception 'No se encontró el fallback de origen esperado'; end if;
  v_original := v_nuevo;
  v_patron := E'    where c.fecha_cierre_comercial >=';
  if (length(v_original)-length(replace(v_original,v_patron,'')))/length(v_patron) <> 1 then
    raise exception 'El filtro esperado no aparece exactamente una vez';
  end if;
  v_nuevo := replace(v_nuevo,
    v_patron,
    E'    left join lateral (\n      select count(*) as cantidad,\n        count(distinct coalesce(a.origen, ''sin_origen'')) as origenes_distintos,\n        min(coalesce(a.origen, ''sin_origen'')) as origen_unico\n      from private.ranking_origenes_acreditados_filas(array[c.id]) a\n      where a.fecha_comercial = c.fecha_cierre_comercial\n    ) acreditado on true\n    where c.fecha_cierre_comercial >=');
  if v_nuevo = v_original then raise exception 'No se encontró la unión esperada'; end if;
  execute v_nuevo;
end;
$cambio$;

-- Actualiza solo la declaración existente del lector modificado; no añade
-- exenciones, no cambia clases y no eleva el techo de contadores.
do $huella$
declare v_filas integer;
begin
  update private.analitica_leads_citas_exenciones e
  set huella = md5(regexp_replace(regexp_replace(lower(p.prosrc),
      '--[^\n]*',' ','g'),'/\*.*?\*/',' ','g'))
  from pg_proc p
  where p.oid = 'private.ranking_capital_origen_filas(timestamptz,timestamptz,uuid)'::regprocedure
    and e.objeto = 'private.ranking_capital_origen_filas(timestamp with time zone,timestamp with time zone,uuid)'
    and e.clase = 'analitica';
  get diagnostics v_filas = row_count;
  if v_filas <> 1 then raise exception 'Se esperaba actualizar una sola declaración analítica'; end if;
end;
$huella$;
update private.analitica_lc_sello
set sello = private.huella_exenciones_analitica_lc(), sellado_en = now()
where id;

do $postflight$
begin
  if exists (select 1 from private.contadores_crudos_leads_citas()
      where not declarada or not huella_ok) then
    raise exception 'El cambio dejó contadores sin declarar o huellas caducas';
  end if;
  if not exists (select 1 from private.analitica_leads_citas_exenciones
      where objeto = 'private.ranking_capital_origen_filas(timestamp with time zone,timestamp with time zone,uuid)'
        and clase = 'analitica') then
    raise exception 'Falta la declaración analítica del lector';
  end if;
  if (select md5(prosrc) from pg_proc where oid =
      'private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])'::regprocedure)
      is distinct from '214c6bada3dc63f553d7f9b62fd7963c'
    or (select md5(prosrc) from pg_proc where oid =
      'private.produccion_mes_por_vendedor(timestamptz,timestamptz,uuid)'::regprocedure)
      is distinct from 'ecfdf7e030497af2f299ba327102a5ea' then
    raise exception 'Cambió el núcleo monetario';
  end if;
end;
$postflight$;
commit;
