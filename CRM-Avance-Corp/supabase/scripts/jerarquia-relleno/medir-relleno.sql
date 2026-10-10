-- medir-relleno.sql — Facturación, FASE 5 (Carmen y Jorge). SOLO LECTURA.
--
-- PARA QUÉ: antes de anotar ningún cambio de supervisor «de relleno», medir en
-- PRODUCCIÓN qué personas tienen hoy un supervisor distinto del que dice su último
-- evento (derivas), con qué evidencia se puede fechar ese cambio, si vendieron en
-- la ventana sin rastro y QUÉ CAMBIARÍA en Facturación, mes a mes, si se anotara.
-- No escribe nada: cuenta, lista y SIMULA en memoria.
--
-- AL DÍA CON PRODUCCIÓN (10/10/2026): fase 2 (20261009223000), baja de analista
-- (20261009200000: el analista es el EFECTIVO de private.capital_episodios) y 3A
-- (20261009224000). El lado «hoy» sale de la función VIVA
-- private.facturacion_operaciones; la réplica de sus tramos se VALIDA contra ella
-- operación por operación (validacion.discrepancias debe ser 0) y solo entonces el
-- lado «con relleno» (misma réplica + el evento simulado) es fiable.
--
-- CÓMO SE CORRE (desde CRM-Avance-Corp):
--   supabase db query --linked -f <ruta>/medir-relleno.sql --output-format json
-- `db query --linked` solo devuelve la última sentencia con filas y no trae NOTICE:
-- el resultado viaja en un GUC LOCAL (set_config(..., true)), que no escribe y muere
-- con el ROLLBACK.
--
-- POR QUÉ ES SEGURO
--   · Transacción READ ONLY y el bloque lo comprueba: si no lo fuera, se niega.
--   · Solo llama a funciones STABLE (capital_episodios, facturacion_operaciones).
--   · Cada sección en su subbloque: si una falla deja {"error": ...} y las demás siguen.

begin transaction read only;
set transaction read only;
set local statement_timeout = '180s';
set local lock_timeout = '5s';

do $medir$
declare
  v_res jsonb := '{}'::jsonb;
  v_tmp jsonb;
begin
  if current_setting('transaction_read_only') <> 'on' then
    raise exception 'medir-relleno: la transacción no es de solo lectura; no se mide';
  end if;

  -- ── R0. Resumen y huellas de lo que se replica ────────────────────────────
  begin
    v_tmp := jsonb_build_object(
      'generado_en_lima', to_char(now() at time zone 'America/Lima', 'YYYY-MM-DD HH24:MI:SS'),
      'eventos_jerarquia', (select count(*) from crm.usuario_eventos ue
                            where ue.accion = 'jerarquia_actualizada'),
      'eventos_jerarquia_por_via', (
        select coalesce(jsonb_object_agg(x.via, x.n), '{}'::jsonb)
        from (select coalesce(ue.detalle ->> 'via', '(sin via)') as via, count(*) as n
              from crm.usuario_eventos ue where ue.accion = 'jerarquia_actualizada'
              group by 1) x),
      'meses_sellados', (select coalesce(jsonb_agg(pc.periodo order by pc.periodo), '[]'::jsonb)
                         from crm.periodos_cerrados pc),
      'huellas', jsonb_build_object(
        'capital_episodios', md5(pg_get_functiondef(
          to_regprocedure('private.capital_episodios(timestamptz,timestamptz,boolean,uuid[])'))),
        'facturacion_operaciones', md5(pg_get_functiondef(
          to_regprocedure('private.facturacion_operaciones(timestamptz,timestamptz)'))),
        'trg_equipo_evento_jerarquia', md5(pg_get_functiondef(
          to_regprocedure('private.trg_equipo_evento_jerarquia()')))),
      'huellas_esperadas', jsonb_build_object(
        'capital_episodios', '2ed07da302e9a1b881a4962724234dd7',
        'facturacion_operaciones', '5d63cb537b0b286ad47feb7f5b26d161',
        'trg_equipo_evento_jerarquia', '93906f654ba2e4c358ecfe6da1c95f77')
    );
  exception when others then
    v_tmp := jsonb_build_object('error', sqlstate || ': ' || sqlerrm);
  end;
  v_res := v_res || jsonb_build_object('R0_resumen', v_tmp);

  -- ── R1. Auditoría de crm.equipo: ¿rastro con fecha exacta y antes/después? ─
  begin
    v_tmp := (
      with
      aud as (
        select al.operacion, al.fila_id::text as perfil_txt, al.ts as en,
               al.data_antes ->> 'supervisor_id' as de,
               al.data_despues ->> 'supervisor_id' as a_sup,
               al.usuario_id::text as por_txt
        from public.audit_log al
        where al.tabla = 'crm.equipo'
      ),
      cambios as (
        select x.*,
               exists (select 1 from crm.usuario_eventos j
                       where j.accion = 'jerarquia_actualizada'
                         and j.objetivo_id::text = x.perfil_txt
                         and (j.detalle ->> 'supervisor_nuevo') is not distinct from x.a_sup
                         and j.creado_en between x.en - interval '5 minutes'
                                             and x.en + interval '5 minutes') as con_evento
        from aud x
        where x.operacion = 'UPDATE' and x.de is distinct from x.a_sup
      )
      select jsonb_build_object(
        'filas', (select count(*) from aud),
        'desde_lima', (select to_char(min(a.en) at time zone 'America/Lima', 'YYYY-MM-DD HH24:MI') from aud a),
        'hasta_lima', (select to_char(max(a.en) at time zone 'America/Lima', 'YYYY-MM-DD HH24:MI') from aud a),
        'cambios_de_supervisor', (select count(*) from cambios),
        'cambios_de_supervisor_sin_evento', (select count(*) from cambios c where not c.con_evento),
        'detalle_sin_evento', (
          select coalesce(jsonb_agg(jsonb_build_object(
                   'en_lima', to_char(c.en at time zone 'America/Lima', 'YYYY-MM-DD HH24:MI'),
                   'persona', pp.nombre_completo,
                   'de', pd.nombre_completo, 'a', pa.nombre_completo,
                   'hecho_por', pu.nombre_completo)
                 order by c.en), '[]'::jsonb)
          from cambios c
          left join public.perfiles pp on pp.id::text = c.perfil_txt
          left join public.perfiles pd on pd.id::text = c.de
          left join public.perfiles pa on pa.id::text = c.a_sup
          left join public.perfiles pu on pu.id::text = c.por_txt
          where not c.con_evento)
      ));
  exception when others then
    v_tmp := jsonb_build_object('error', sqlstate || ': ' || sqlerrm);
  end;
  v_res := v_res || jsonb_build_object('R1_auditoria_equipo', v_tmp);

  -- ── R2. Derivas: el supervisor de HOY no es el del último evento ──────────
  begin
    v_tmp := (
      with
      ult as (
        select distinct on (ue.objetivo_id)
               ue.objetivo_id, ue.creado_en,
               (ue.detalle ->> 'supervisor_nuevo')::uuid as segun
        from crm.usuario_eventos ue
        where ue.accion = 'jerarquia_actualizada'
        order by ue.objetivo_id, ue.creado_en desc, ue.id desc
      ),
      der as (
        select u.objetivo_id as perfil_id, u.creado_en as ultimo_evento, u.segun,
               e.supervisor_id as hoy, e.rol_crm, e.activo, e.actualizado_en,
               (e.perfil_id is not null) as en_equipo
        from ult u
        left join crm.equipo e on e.perfil_id = u.objetivo_id
        where e.supervisor_id is distinct from u.segun
      )
      select coalesce(jsonb_agg(jsonb_build_object(
               'perfil_id', d.perfil_id, 'persona', pp.nombre_completo,
               'rol', d.rol_crm, 'activo', d.activo, 'existe_en_equipo', d.en_equipo,
               'supervisor_hoy', ph.nombre_completo,
               'rol_supervisor_hoy', (select e2.rol_crm from crm.equipo e2 where e2.perfil_id = d.hoy),
               'segun_ultimo_evento', ps.nombre_completo,
               'rol_hoy_de_ese_supervisor', (select e3.rol_crm from crm.equipo e3 where e3.perfil_id = d.segun),
               'ultimo_evento_lima', to_char(d.ultimo_evento at time zone 'America/Lima', 'YYYY-MM-DD HH24:MI'),
               'equipo_actualizado_lima', to_char(d.actualizado_en at time zone 'America/Lima', 'YYYY-MM-DD HH24:MI'),
               'eventos_propios', (
                 select coalesce(jsonb_agg(jsonb_build_object(
                          'accion', x.accion,
                          'en_lima', to_char(x.creado_en at time zone 'America/Lima', 'YYYY-MM-DD HH24:MI'),
                          'detalle', x.detalle) order by x.creado_en, x.id), '[]'::jsonb)
                 from crm.usuario_eventos x where x.objetivo_id = d.perfil_id),
               'eventos_del_supervisor_anterior_despues', (
                 select coalesce(jsonb_agg(jsonb_build_object(
                          'accion', x.accion,
                          'en_lima', to_char(x.creado_en at time zone 'America/Lima', 'YYYY-MM-DD HH24:MI'),
                          'detalle', x.detalle) order by x.creado_en, x.id), '[]'::jsonb)
                 from crm.usuario_eventos x
                 where x.objetivo_id = d.segun and x.creado_en > d.ultimo_evento),
               -- Cota superior: dejar de ser jefe (desactivarse o cambiar de rol) exige
               -- no tener subordinados activos (20260828210351:302-325 y el guion de
               -- Carlos, carlos-valles-directorio-a-gerencia.sql:46-52).
               'cota_superior_lima', (
                 select to_char(min(x.creado_en) at time zone 'America/Lima', 'YYYY-MM-DD HH24:MI')
                 from crm.usuario_eventos x
                 where x.objetivo_id = d.segun and x.creado_en > d.ultimo_evento
                   and x.accion in ('membresia_desactivada', 'rol_cambiado')),
               'fotos_metas_desde_ultimo_evento', (
                 select coalesce(jsonb_agg(jsonb_build_object(
                          'periodo', mp.periodo, 'revision', mp.revision,
                          'publicada_lima', to_char(mp.publicada_en at time zone 'America/Lima', 'YYYY-MM-DD HH24:MI'),
                          'supervisor', pm.nombre_completo) order by mp.publicada_en), '[]'::jsonb)
                 from crm.metas_vendedor mv
                 join crm.meta_periodos mp on mp.id = mv.meta_periodo_id
                 left join public.perfiles pm on pm.id = mv.supervisor_id
                 where mv.vendedor_id = d.perfil_id and mp.publicada_en > d.ultimo_evento),
               'fotos_cierre_mes', (
                 select coalesce(jsonb_agg(jsonb_build_object(
                          'periodo', cm.periodo, 'supervisor', pc.nombre_completo)
                        order by cm.periodo), '[]'::jsonb)
                 from crm.cierre_mes_vendedor cm
                 left join public.perfiles pc on pc.id = cm.supervisor_id
                 where cm.vendedor_id = d.perfil_id))
             order by pp.nombre_completo), '[]'::jsonb)
      from der d
      left join public.perfiles pp on pp.id = d.perfil_id
      left join public.perfiles ph on ph.id = d.hoy
      left join public.perfiles ps on ps.id = d.segun);
  exception when others then
    v_tmp := jsonb_build_object('error', sqlstate || ': ' || sqlerrm);
  end;
  v_res := v_res || jsonb_build_object('R2_derivas', v_tmp);

  -- ── R6. SIMULACIÓN del relleno (en memoria) contra la función VIVA ────────
  --    Candidatos SOLO con evidencia:
  --      · 'auditoria': cambio de public.audit_log sin evento (fecha exacta);
  --      · 'cota_supervisor_anterior': deriva sin auditoría; antes = el del último
  --        evento, después = el de hoy, fecha = la cota. Solo aceptable si
  --        ventas_en_ventana = 0 (entonces la fecha exacta no mueve dinero).
  --    «hoy» = supervisor que devuelve private.facturacion_operaciones (vivo).
  --    «réplica» = sus tramos copiados al byte (20261009224000:155-203); debe
  --    coincidir con «hoy» en el 100 % de las operaciones.
  --    «con relleno» = la misma réplica con los eventos simulados.
  begin
    v_tmp := (
      with
      ev_real as (
        select ue.id, ue.objetivo_id, ue.creado_en,
               (ue.detalle ->> 'supervisor_anterior')::uuid as antes,
               (ue.detalle ->> 'supervisor_nuevo')::uuid as despues
        from crm.usuario_eventos ue
        where ue.accion = 'jerarquia_actualizada'
      ),
      aud_sin_evento as (
        select al.fila_id::text as perfil_txt, al.ts as en,
               al.data_antes ->> 'supervisor_id' as de,
               al.data_despues ->> 'supervisor_id' as a_sup
        from public.audit_log al
        where al.tabla = 'crm.equipo' and al.operacion = 'UPDATE'
          and (al.data_antes ->> 'supervisor_id') is distinct from (al.data_despues ->> 'supervisor_id')
          and not exists (
            select 1 from ev_real j
            where j.objetivo_id::text = al.fila_id::text
              and j.despues::text is not distinct from (al.data_despues ->> 'supervisor_id')
              and j.creado_en between al.ts - interval '5 minutes' and al.ts + interval '5 minutes')
      ),
      ult as (
        select distinct on (r.objetivo_id) r.objetivo_id, r.creado_en, r.despues
        from ev_real r
        order by r.objetivo_id, r.creado_en desc, r.id desc
      ),
      deriva as (
        select u.objetivo_id, u.creado_en as desde, u.despues as segun, e.supervisor_id as hoy,
               (select min(x.creado_en) from crm.usuario_eventos x
                 where x.objetivo_id = u.despues and x.creado_en > u.creado_en
                   and x.accion in ('membresia_desactivada', 'rol_cambiado')) as cota
        from ult u
        join crm.equipo e on e.perfil_id = u.objetivo_id
        where e.supervisor_id is distinct from u.despues
          and e.supervisor_id is not null and u.despues is not null
      ),
      sint as (
        select a.perfil_txt::uuid as objetivo_id, a.en as creado_en,
               nullif(a.de, '')::uuid as antes, nullif(a.a_sup, '')::uuid as despues,
               'auditoria'::text as fuente, a.en as ventana_desde
        from aud_sin_evento a
        union all
        select d.objetivo_id, d.cota, d.segun, d.hoy, 'cota_supervisor_anterior'::text, d.desde
        from deriva d
        where d.cota is not null
          and not exists (select 1 from aud_sin_evento a
                          where a.perfil_txt = d.objetivo_id::text and a.en > d.desde)
      ),
      hipo as (
        select r.id, r.objetivo_id, r.creado_en, r.antes, r.despues from ev_real r
        union all
        select 9000000000000000000::bigint + row_number() over (order by s.objetivo_id, s.creado_en),
               s.objetivo_id, s.creado_en, s.antes, s.despues
        from sint s
      ),
      -- Réplica al byte de los tramos de private.facturacion_operaciones.
      n_real as (
        select r.objetivo_id as analista_id,
               (r.creado_en at time zone 'America/Lima')::date as dia_cambio,
               r.antes, r.despues,
               row_number() over (partition by r.objetivo_id order by r.creado_en, r.id) as n
        from ev_real r
      ),
      t_real as (
        select e.analista_id, '-infinity'::date as desde, e.dia_cambio as hasta, e.antes as supervisor_id
        from n_real e where e.n = 1
        union all
        select e.analista_id, e.dia_cambio, coalesce(sig.dia_cambio, 'infinity'::date), e.despues
        from n_real e
        left join n_real sig on sig.analista_id = e.analista_id and sig.n = e.n + 1
      ),
      n_hipo as (
        select h.objetivo_id as analista_id,
               (h.creado_en at time zone 'America/Lima')::date as dia_cambio,
               h.antes, h.despues,
               row_number() over (partition by h.objetivo_id order by h.creado_en, h.id) as n
        from hipo h
      ),
      t_hipo as (
        select e.analista_id, '-infinity'::date as desde, e.dia_cambio as hasta, e.antes as supervisor_id
        from n_hipo e where e.n = 1
        union all
        select e.analista_id, e.dia_cambio, coalesce(sig.dia_cambio, 'infinity'::date), e.despues
        from n_hipo e
        left join n_hipo sig on sig.analista_id = e.analista_id and sig.n = e.n + 1
      ),
      ops as (
        select o.operacion_id, o.dia, o.tipo, o.moneda, o.monto, o.analista_id, o.anulado,
               o.supervisor_id as sup_hoy
        from private.facturacion_operaciones('-infinity'::timestamptz, 'infinity'::timestamptz) o
      ),
      calc as (
        select o.*,
               coalesce(tr.supervisor_id, eq.supervisor_id) as sup_replica,
               coalesce(th.supervisor_id, eq.supervisor_id) as sup_relleno
        from ops o
        left join t_real tr
          on tr.analista_id = o.analista_id and o.dia >= tr.desde and o.dia < tr.hasta
        left join t_hipo th
          on th.analista_id = o.analista_id and o.dia >= th.desde and o.dia < th.hasta
        left join crm.equipo eq on eq.perfil_id = o.analista_id
      ),
      cambia as (
        select c.* from calc c where c.sup_relleno is distinct from c.sup_hoy
      )
      select jsonb_build_object(
        'validacion', jsonb_build_object(
          'operaciones_vivas', (select count(*) from ops),
          'filas_replica', (select count(*) from calc),
          'discrepancias', (select count(*) from calc c where c.sup_replica is distinct from c.sup_hoy),
          'fiable', (select count(*) from ops) = (select count(*) from calc)
                    and not exists (select 1 from calc c where c.sup_replica is distinct from c.sup_hoy)),
        'candidatos', (
          select coalesce(jsonb_agg(jsonb_build_object(
                   'persona', pp.nombre_completo, 'perfil_id', s.objetivo_id,
                   'fuente', s.fuente,
                   'ventana_desde_lima', to_char(s.ventana_desde at time zone 'America/Lima', 'YYYY-MM-DD HH24:MI'),
                   'fecha_propuesta_lima', to_char(s.creado_en at time zone 'America/Lima', 'YYYY-MM-DD HH24:MI'),
                   'antes', pa.nombre_completo, 'despues', pd.nombre_completo,
                   'seria_primer_evento', not exists (
                     select 1 from ev_real r
                     where r.objetivo_id = s.objetivo_id and r.creado_en < s.creado_en),
                   'ventas_en_ventana', (
                     select count(*) from ops o
                     where o.analista_id = s.objetivo_id
                       and o.dia >= (s.ventana_desde at time zone 'America/Lima')::date
                       and o.dia <= (s.creado_en at time zone 'America/Lima')::date),
                   'ventas_en_ventana_detalle', (
                     select coalesce(jsonb_agg(jsonb_build_object(
                              'dia', o.dia, 'tipo', o.tipo, 'moneda', o.moneda,
                              'monto', o.monto, 'anulado', o.anulado) order by o.dia), '[]'::jsonb)
                     from ops o
                     where o.analista_id = s.objetivo_id
                       and o.dia >= (s.ventana_desde at time zone 'America/Lima')::date
                       and o.dia <= (s.creado_en at time zone 'America/Lima')::date),
                   'ventas_totales_del_analista', (
                     select count(*) from ops o where o.analista_id = s.objetivo_id),
                   -- Desde su evento anterior (o desde siempre) hasta el cambio: con la
                   -- hora exacta, estas ventas NO cambian (siguen con «antes»).
                   'evento_anterior_lima', to_char(prev.creado_en at time zone 'America/Lima', 'YYYY-MM-DD HH24:MI'),
                   'ventas_entre_evento_anterior_y_cambio', (
                     select coalesce(jsonb_agg(jsonb_build_object(
                              'dia', o.dia, 'tipo', o.tipo, 'moneda', o.moneda, 'monto', o.monto,
                              'anulado', o.anulado,
                              'supervisor_hoy', coalesce(ph.nombre_completo, 'Sin supervisor'))
                            order by o.dia), '[]'::jsonb)
                     from ops o
                     left join public.perfiles ph on ph.id = o.sup_hoy
                     where o.analista_id = s.objetivo_id
                       and o.dia >= coalesce((prev.creado_en at time zone 'America/Lima')::date, '-infinity'::date)
                       and o.dia < (s.creado_en at time zone 'America/Lima')::date),
                   'fotos_metas_que_contradicen_antes', (
                     select count(*) from crm.metas_vendedor mv
                     join crm.meta_periodos mp on mp.id = mv.meta_periodo_id
                     where mv.vendedor_id = s.objetivo_id and mp.publicada_en < s.creado_en
                       and (prev.creado_en is null or mp.publicada_en > prev.creado_en)
                       and mv.supervisor_id is distinct from s.antes))
                 order by pp.nombre_completo, s.creado_en), '[]'::jsonb)
          from sint s
          left join lateral (
            select r.creado_en from ev_real r
            where r.objetivo_id = s.objetivo_id and r.creado_en < s.creado_en
            order by r.creado_en desc, r.id desc limit 1) prev on true
          left join public.perfiles pp on pp.id = s.objetivo_id
          left join public.perfiles pa on pa.id = s.antes
          left join public.perfiles pd on pd.id = s.despues),
        'derivas_sin_fecha_probable', (
          select coalesce(jsonb_agg(jsonb_build_object(
                   'persona', pp.nombre_completo,
                   'motivo', 'sin auditoría y sin evento del supervisor anterior que acote la fecha')), '[]'::jsonb)
          from deriva d
          left join public.perfiles pp on pp.id = d.objetivo_id
          where d.cota is null
            and not exists (select 1 from aud_sin_evento a
                            where a.perfil_txt = d.objetivo_id::text and a.en > d.desde)),
        'operaciones_que_cambian_de_supervisor', (select count(*) from cambia),
        'detalle_por_mes', (
          select coalesce(jsonb_agg(jsonb_build_object(
                   'mes', to_char(x.mes, 'YYYY-MM'),
                   'mes_sellado', exists (select 1 from crm.periodos_cerrados pc where pc.periodo = x.mes),
                   'analista', pa.nombre_completo,
                   'de', coalesce(p1.nombre_completo, 'Sin supervisor'),
                   'a', coalesce(p2.nombre_completo, 'Sin supervisor'),
                   'moneda', x.moneda, 'operaciones', x.ops, 'capital', x.cap)
                 order by x.mes, pa.nombre_completo, x.moneda), '[]'::jsonb)
          from (select date_trunc('month', c.dia)::date as mes, c.analista_id, c.sup_hoy,
                       c.sup_relleno, c.moneda, count(*) as ops, sum(c.monto) as cap
                from cambia c group by 1, 2, 3, 4, 5) x
          left join public.perfiles pa on pa.id = x.analista_id
          left join public.perfiles p1 on p1.id = x.sup_hoy
          left join public.perfiles p2 on p2.id = x.sup_relleno),
        'detalle_por_operacion', (
          select coalesce(jsonb_agg(jsonb_build_object(
                   'dia', c.dia, 'analista', pa.nombre_completo, 'tipo', c.tipo,
                   'moneda', c.moneda, 'monto', c.monto, 'anulado', c.anulado,
                   'de', coalesce(p1.nombre_completo, 'Sin supervisor'),
                   'a', coalesce(p2.nombre_completo, 'Sin supervisor'))
                 order by c.dia, pa.nombre_completo, c.operacion_id), '[]'::jsonb)
          from (select * from cambia order by dia limit 300) c
          left join public.perfiles pa on pa.id = c.analista_id
          left join public.perfiles p1 on p1.id = c.sup_hoy
          left join public.perfiles p2 on p2.id = c.sup_relleno)
      ));
  exception when others then
    v_tmp := jsonb_build_object('error', sqlstate || ': ' || sqlerrm);
  end;
  v_res := v_res || jsonb_build_object('R6_simulacion_relleno', v_tmp);

  perform set_config('medir.relleno', v_res::text, true);
end
$medir$;

select current_setting('medir.relleno', true)::jsonb as resultado;

rollback;
