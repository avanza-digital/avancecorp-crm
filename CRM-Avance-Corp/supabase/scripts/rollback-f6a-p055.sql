-- MARCHA ATRAS de la Fase 6.a (nucleo de citas y censo sellado).
--
-- Devuelve la pantalla de reuniones a sus banderas crudas (reemplazo INVERSO
-- anclado sobre el cuerpo VIVO) y retira nucleo, censo, gate y vigia.
-- ⚠️ Las TABLAS y SUS CANDADOS no se borran a proposito: conservan las razones
--    declaradas y la propiedad "el tope solo baja" TAMBIEN entre un rollback y
--    una re-aplicacion (hallazgo de las auditorias: antes se borraban los
--    triggers y la promesa quedaba coja).

begin;
set local lock_timeout = '5s';

do $$
declare v_def text; v_veces integer; v_ancla text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p where p.oid = 'private.metricas_reuniones_implementacion(date,date)'::regprocedure;

  v_ancla := $a$ce.debio_ocurrir as metrica_debio_ocurrir,
      ce.realizada as metrica_realizada,
      ce.no_show as metrica_no_show,
      ce.cancelada_asesor as metrica_cancelada_asesor,
      ce.cancelada_sistema as metrica_cancelada_sistema,
      ce.reprogramada as metrica_reprogramada,
      ce.pendiente_cierre as metrica_pendiente_cierre,
      ce.programada_futura as metrica_programada_futura$a$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then raise exception 'rollback F6.a: ancla 1 aparece % veces (¿ya revertida?)', v_veces; end if;
  v_def := replace(v_def, v_ancla, $b$t.vence_en <= v_ahora as metrica_debio_ocurrir,
      t.estado = 'completada' as metrica_realizada,
      t.estado = 'no_show' as metrica_no_show,
      (t.estado = 'cancelada' and t.cancelada_por = 'asesor')
        as metrica_cancelada_asesor,
      (t.estado = 'cancelada' and t.cancelada_por is distinct from 'asesor')
        as metrica_cancelada_sistema,
      t.estado = 'reprogramada' as metrica_reprogramada,
      (t.estado = 'pendiente' and t.vence_en <= v_ahora)
        as metrica_pendiente_cierre,
      (t.estado = 'pendiente' and t.vence_en > v_ahora)
        as metrica_programada_futura$b$);

  v_ancla := 'ce.modalidad as modalidad,';
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then raise exception 'rollback F6.a: ancla 2 aparece % veces', v_veces; end if;
  v_def := replace(v_def, v_ancla, $b$coalesce(t.modalidad_reunion, 'sin_clasificar') as modalidad,$b$);

  v_ancla := $a$from private.citas_episodios(v_ini, v_fin, v_ahora) ce
    join crm.tareas t on t.id = ce.tarea_id
    left join crm.leads l on l.id = t.lead_id$a$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then raise exception 'rollback F6.a: ancla 3 aparece % veces', v_veces; end if;
  v_def := replace(v_def, v_ancla, $b$from crm.tareas t
    left join crm.leads l on l.id = t.lead_id$b$);

  -- El WHERE que la conversion borro, restaurado tras el ultimo join del FROM
  -- con el whitespace EXACTO del original (la conversion se llevo el salto y la
  -- sangria previos, aqui se devuelven).
  v_ancla := $a$left join public.perfiles ps on ps.id = e.supervisor_id$a$;
  v_veces := (length(v_def) - length(replace(v_def, v_ancla, ''))) / length(v_ancla);
  if v_veces <> 1 then raise exception 'rollback F6.a: ancla 4 aparece % veces', v_veces; end if;
  v_def := replace(v_def, v_ancla, $b$left join public.perfiles ps on ps.id = e.supervisor_id$b$
    || e'\n    ' || $b$where t.tipo = 'reunion' and t.activo
      and t.vence_en >= v_ini and t.vence_en < v_fin$b$);

  execute v_def;
end $$;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'crm-analitica-lc-vigia') then
    perform cron.unschedule('crm-analitica-lc-vigia');
  end if;
end $$;
drop function if exists private.vigia_analitica_leads_citas();
drop function if exists private.assert_analitica_leads_citas();
drop function if exists private.contadores_crudos_leads_citas();
-- ⚠️ LO QUE SE CONSERVA, a proposito:
--   - las tablas (exenciones, tope, sello, alertas) Y SUS CANDADOS (triggers
--     del tope y de exenciones, y sus funciones): entre un rollback y una
--     re-aplicacion el tope NO se puede subir ni la lista relavarse;
--   - `private.huella_exenciones_analitica_lc()` (el sello necesita su regla);
--   - el vigia REPARADO de la F5.a (`vigia_analista_vigencia`): es un arreglo
--     de un defecto vivo, no parte de esta fase; revertirlo seria re-romperlo.

-- Antes de retirar el nucleo: que NADIE mas lo llame (Postgres no rastrea
-- dependencias funcion->funcion; un drop alegre romperia en silencio).
do $$
declare v text;
begin
  select string_agg(p.oid::regprocedure::text, ', ') into v
    from pg_proc p
   where p.prokind in ('f','p')
     and regexp_replace(regexp_replace(coalesce(p.prosrc,''),'--[^\n]*',' ','g'),'/\*.*?\*/',' ','g')
         ~ '\mcitas_episodios\s*\('
     and p.oid <> 'private.metricas_reuniones_implementacion(date,date)'::regprocedure;
  if v is not null then
    raise exception 'rollback F6.a: estos consumidores aun llaman a citas_episodios: %', v;
  end if;
end $$;
drop function if exists private.citas_episodios(timestamptz, timestamptz, timestamptz);

-- POSTFLIGHT: la pantalla vuelve a su huella original EXACTA.
do $$
declare v_h text;
begin
  select md5(regexp_replace(regexp_replace(p.prosrc,'--[^\n]*',' ','g'),'/\*.*?\*/',' ','g'))
    into v_h from pg_proc p
   where p.oid = 'private.metricas_reuniones_implementacion(date,date)'::regprocedure;
  if v_h is distinct from 'b2afc1ef6e48d95f6547cfc91b8885d9' then
    raise exception 'rollback F6.a: la pantalla de reuniones no volvio a su huella (%)', v_h;
  end if;
end $$;

commit;
