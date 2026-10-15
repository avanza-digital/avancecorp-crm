-- Formulario 3 · fase 2. Requiere la migración de campaña de fase 1.
-- Lectura informativa y filtro sobre la misma base de filas, totales, capital y embudo.
-- Las firmas vivas y sus dependencias se inspeccionaron el 14/10/2026.
-- No se alteran políticas, reparto, conversión, datos históricos ni objetos de public.
begin;
set local lock_timeout = '5s';

create temporary table formulario3_fase2_metadatos(nombre text primary key, comentario text) on commit drop;

do $preflight$
declare r record; f regprocedure;
begin
  if not exists (select 1 from information_schema.columns
    where table_schema='crm' and table_name='leads' and column_name='campania_origen')
    or not has_column_privilege('authenticated','crm.leads','campania_origen','SELECT')
    or has_column_privilege('authenticated','crm.leads','campania_origen','UPDATE')
    or has_column_privilege('authenticated','crm.leads','campania_origen','INSERT') then
    raise exception 'Falta fase 1 o sus permisos de campaña no coinciden';
  end if;
  for r in select * from (values
    ('crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text)', '23a63cc3965472b9db85aa81cadffbeb'),
    ('crm.cartera_pagina_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text)', '4bbfd838ef6665f3bdad4603fa400e65')
  ) esperado(firma,huella) loop
    f := to_regprocedure(r.firma);
    if f is null or md5(pg_get_functiondef(f)) <> r.huella
      or not exists (select 1 from pg_proc where oid=f
        and pg_get_userbyid(proowner)='postgres' and not prosecdef
        and provolatile='s' and proconfig=array['search_path=""']
        and proacl::text='{postgres=X/postgres,authenticated=X/postgres}') then
      raise exception 'Contrato vivo modificado: %. Revisar antes de aplicar.',r.firma;
    end if;
    if exists(select 1 from pg_depend where refclassid='pg_proc'::regclass and refobjid=f and deptype <> 'e') then
      raise exception 'Dependencia nueva sobre %. No usar CASCADE.',r.firma;
    end if;
    if exists(select 1 from pg_seclabel where classoid='pg_proc'::regclass and objoid=f) then
      raise exception 'Etiqueta de seguridad nueva sobre %. Revisar antes de recrear.',r.firma;
    end if;
    insert into formulario3_fase2_metadatos
      select proname, obj_description(oid,'pg_proc') from pg_proc where oid=f;
  end loop;
  if (select count(*) from pg_proc where pronamespace='crm'::regnamespace
      and proname in ('cartera_filtrada_fn','cartera_pagina_fn')) <> 2 then
    raise exception 'Firmas de cartera ambiguas';
  end if;
  -- pg_depend no registra llamadas dentro de cuerpos PL/pgSQL. Se inspeccionó
  -- prosrc en producción: resumen es el único llamador; cierres solo las cita
  -- en comentarios. Cualquier cuerpo nuevo o cambiado requiere otra revisión.
  if exists(select 1 from pg_proc p
      where p.prokind in ('f','p')
        and (p.prosrc ilike '%cartera_pagina_fn%' or p.prosrc ilike '%cartera_filtrada_fn%')
        and not (p.pronamespace='crm'::regnamespace and p.proname in ('cartera_pagina_fn','cartera_filtrada_fn'))
        and not (
          (p.oid='crm.resumen_cartera_fn()'::regprocedure and md5(pg_get_functiondef(p.oid))='4a896597486e8b23788a2b2497f16309')
          or (p.oid='crm.cierres_estado_fn(uuid[])'::regprocedure and md5(pg_get_functiondef(p.oid))='5f6eca13b613aaa40b459ea56f7c8ac5')
        )) then
    raise exception 'Nuevo cuerpo dependiente de cartera; revisar compatibilidad antes de aplicar';
  end if;
end;
$preflight$;

-- Cambiar los argumentos/RETURNS TABLE exige retirar las firmas exactas.
-- El wrapper resumen_cartera_fn usa parámetros nominales y sigue resolviendo
-- p_limite=>1. Su bloque resumen conserva exactamente las claves anteriores.
drop function crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text);
drop function crm.cartera_pagina_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text);

CREATE OR REPLACE FUNCTION crm.cartera_filtrada_fn(p_limite integer DEFAULT 50, p_antes_de timestamp with time zone DEFAULT NULL::timestamp with time zone, p_antes_id uuid DEFAULT NULL::uuid, p_etapa text DEFAULT NULL::text, p_vendedor_id uuid DEFAULT NULL::uuid, p_sin_asignar boolean DEFAULT false, p_texto text DEFAULT NULL::text, p_desde date DEFAULT NULL::date, p_hasta date DEFAULT NULL::date, p_origen text DEFAULT NULL::text, p_procedencia text DEFAULT NULL::text, p_reasignados boolean DEFAULT false, p_gestion text DEFAULT NULL::text, p_potencial text DEFAULT NULL::text, p_campania_origen text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_global boolean;
  v_visibles uuid[];
  v_texto text := nullif(btrim(p_texto), '');
  v_reparto boolean;
  v_digitos text;
  v_salida jsonb;
  v_potencial boolean;
begin
  if v_uid is null or not private.puede_acceder_crm() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_limite is null or p_limite < 1 or p_limite > 200
     or (p_antes_de is null) <> (p_antes_id is null)
     or (p_sin_asignar and p_vendedor_id is not null)
     or (p_sin_asignar and p_desde is not null)
     or (p_desde is null) <> (p_hasta is null)
     or p_desde > p_hasta
     or p_hasta > (now() at time zone 'America/Lima')::date
     or (p_etapa is not null and p_etapa not in
       ('nuevo','contactado','reunion_agendada','propuesta_enviada','convertido','descartado'))
     -- Mismo dominio que el CHECK de crm.leads.origen: los 5 vigentes y los 3
     -- históricos (web, campania, whatsapp) siguen siendo consultables.
     or (p_origen is not null and p_origen not in
       ('referido','landing','formulario','oficina','otro','web','campania','whatsapp'))
     -- Procedencia: 'sistema' (puente automático) o 'manual' (una persona).
     -- Otro valor se rechaza: nunca un «cero resultados» silencioso.
     or (p_procedencia is not null and p_procedencia not in ('sistema','manual'))
     -- Gestión: 'con_gestion' (el titular actual ya intentó el contacto) o
     -- 'sin_gestion' (el resto). Otro valor se rechaza, igual que arriba.
     or (p_gestion is not null and p_gestion not in ('con_gestion','sin_gestion'))
     -- Potencial: uno de los tres niveles o 'sin_marca' (leads sin marca). Otro valor se
     -- rechaza, igual que arriba.
     or (p_potencial is not null and p_potencial not in ('estrella','tibio','frio','sin_marca'))
     -- Campaña de origen: texto canónico, nunca un cambio del canal comercial.
     or (p_campania_origen is not null and
       (p_campania_origen <> btrim(p_campania_origen)
         or length(p_campania_origen) not between 1 and 80
         or p_campania_origen ~ '[[:cntrl:]]'
         or (lower(p_campania_origen) = 'formulario 3' and p_campania_origen <> 'Formulario 3')))
     or (v_texto is not null and length(v_texto) < 2) then
    raise exception 'Filtros de cartera inválidos' using errcode = '22023';
  end if;
  v_texto := left(v_texto, 80);
  v_digitos := left(regexp_replace(v_texto, '\D', '', 'g'), 15);
  v_global := private.rol_crm(v_uid) = 'gerencia' or private.es_lector_global();
  v_visibles := array(select private.vendedor_ids_visibles(v_uid));
  v_reparto := private.cartera_puede_operar_reparto_fn();
  -- El potencial solo existe con su bandera encendida y para quien tiene ámbito de FILAS (global
  -- o con analistas visibles). Sin eso la respuesta es la de siempre (sin `resumen.potencial`) y
  -- pedir el filtro se rechaza como en la puerta de marcar. Quien solo opera el reparto no lee
  -- leads por su RLS: tampoco recibe conteos por nivel (ni dentro de crm.resumen_cartera_fn).
  v_potencial := crm.bandera_activa('potencial_lead') is true
    and (coalesce(v_global, false) or cardinality(v_visibles) > 0);
  if p_potencial is not null and not v_potencial then
    raise exception 'El potencial del lead no está habilitado' using errcode = '55000';
  end if;

  with recepciones as materialized (
    select * from private.cartera_recepciones_fn(p_desde,p_hasta)
  ), marcas as materialized (
    -- Marca vigente de los leads que el actor puede ver. Ayudante DEFINER: las tablas del
    -- potencial no tienen grants de API. Sin potencial para este actor, ni se le llama.
    select m.lead_id, m.nivel from private.cartera_potencial_fn() m where v_potencial
  ), previa as materialized (
    select l.id, l.nombre_completo, l.telefono, l.telefono_alternativo,
      l.telefono_alternativo_crudo, l.correo, l.dni, l.genero,
      l.fecha_nacimiento, l.distrito, l.origen, l.campania_origen, l.etapa, l.motivo_descarte,
      l.monto_estimado, l.moneda, l.categoria_interes, l.vendedor_id,
      l.asignado_supervisor_id, l.creado_en, l.tenencia_desde, l.convertido_en,
      l.contrato_id, l.actualizado_en, l.activo, l.nota, l.no_contactar,
      -- Procedencia sellada por el servidor: `alta_manual` (columna del 01/09)
      -- o, para los leads anteriores a ella, tener autor. El puente inserta
      -- como service_role sin autor: nunca cae en 'manual'.
      case when l.alta_manual or l.creado_por is not null then 'manual' else 'sistema' end as procedencia,
      l.creado_por as cargado_por,
      coalesce(mov.reasignado, false) as reasignado,
      r.recibido_en, coalesce(r.aproximado,false) as recepcion_aproximada,
      mk.nivel as potencial_nivel
    from crm.leads l
    -- Una primera entrega desde la cola tiene vendedor_anterior NULL. Solo
    -- cuenta un analista ANTERIOR, incluso si volvió al mismo titular tras
    -- pasar por la bandeja. El evento lo emite el trigger del servidor.
    left join lateral (
      select true as reasignado
      from crm.actividades a
      where l.vendedor_id is not null
        and a.lead_id = l.id
        and a.tipo = 'reasignacion'
        and a.metadata ->> 'vendedor_anterior' is not null
      limit 1
    ) mov on true
    left join recepciones r on r.lead_id = l.id
    left join marcas mk on mk.lead_id = l.id
    where l.activo is true
      and (v_global or l.vendedor_id = any(v_visibles)
        or (l.vendedor_id is null and (l.asignado_supervisor_id = any(v_visibles)
          or v_reparto)))
      and (p_desde is null or r.lead_id is not null)
      -- La consulta por recepción puede recuperar convertidos antiguos que
      -- siguen siendo visibles por RLS; sin fechas se conserva la ventana operativa.
      and (p_desde is not null or l.etapa <> 'convertido' or l.convertido_en >= now() - interval '45 days')
      and (p_etapa is null or l.etapa = p_etapa)
      -- El origen acota la MISMA base: filas, totales, capital y embudo juntos.
      and (p_origen is null or l.origen = p_origen)
      and (p_campania_origen is null or l.campania_origen = p_campania_origen)
      -- La procedencia acota esa misma base, con la misma regla que la columna
      -- `procedencia` de arriba.
      and (p_procedencia is null or (l.alta_manual or l.creado_por is not null) = (p_procedencia = 'manual'))
      and (not coalesce(p_reasignados,false) or coalesce(mov.reasignado,false))
      -- Gestión vigente: el titular ACTUAL ya intentó el contacto desde que
      -- recibió el lead (`tenencia_desde`, que se renueva al reasignar y al
      -- reabrir). Lo que gestionó un titular anterior no cuenta, ni un resultado
      -- de llamada deshecho (`deshecho_en`: no ocurrió); sin titular o sin
      -- tenencia no hay gestión. Acota la MISMA base; el payload no cambia.
      and (p_gestion is null or (l.vendedor_id is not null
        and l.tenencia_desde is not null
        and exists (select 1 from crm.actividades g
          where g.lead_id = l.id
            and g.tipo in ('llamada_realizada','llamada_no_contestada',
              'whatsapp_enviado','whatsapp_recibido','reunion_realizada')
            and g.creado_en >= l.tenencia_desde
            and not (g.metadata ? 'deshecho_en'))) = (p_gestion = 'con_gestion'))
      and (p_vendedor_id is null or l.vendedor_id = p_vendedor_id)
      and (not coalesce(p_sin_asignar,false) or l.vendedor_id is null)
      and (v_texto is null or strpos(lower(l.nombre_completo),lower(v_texto)) > 0
        or (length(v_digitos) >= 3 and (strpos(l.telefono,v_digitos) > 0
          or strpos(l.telefono_alternativo,v_digitos) > 0 or strpos(l.dni,v_digitos) > 0)))
  ), base as not materialized (
    -- El potencial recorta DESPUÉS de los demás filtros: `previa` alimenta los conteos por
    -- nivel (cuántos hay de cada uno con los demás filtros puestos, sin que cambien al elegir
    -- uno) y `base`, como siempre, las filas, los totales, el capital y el embudo.
    select pv.* from previa pv
    where p_potencial is null
      or (p_potencial = 'sin_marca' and pv.potencial_nivel is null)
      or pv.potencial_nivel = p_potencial
  ), pagina as (
    select b.* from base b
    where p_antes_de is null or b.actualizado_en < p_antes_de
      or (b.actualizado_en = p_antes_de and b.id > p_antes_id)
    order by b.actualizado_en desc,b.id asc limit p_limite
  ), filas as (
    select p.*, uc.creado_en as ultimo_contacto_en
    from pagina p left join lateral (
      select act.creado_en from crm.actividades act
      where act.lead_id = p.id and act.tipo in ('llamada_realizada',
        'llamada_no_contestada','whatsapp_enviado','whatsapp_recibido','reunion_realizada')
      order by act.creado_en desc limit 1
    ) uc on true
  ), metricas as (
    select count(*) as vivos,
      count(*) filter(where etapa not in ('convertido','descartado')) as abiertos,
      count(*) filter(where etapa not in ('convertido','descartado') and vendedor_id is not null) as asignados,
      count(*) filter(where etapa not in ('convertido','descartado') and vendedor_id is null) as parkeados,
      count(*) filter(where etapa = 'convertido') as convertidos,
      count(*) filter(where etapa = 'descartado') as descartados,
      count(*) filter(where reasignado) as reasignados,
      count(*) filter(where etapa not in ('convertido','descartado') and vendedor_id is not null and moneda='PEN') as asignados_pen,
      count(*) filter(where etapa not in ('convertido','descartado') and vendedor_id is not null and moneda='USD') as asignados_usd
    from base
  ), capital as (
    select jsonb_object_agg(tipo,valor) as valor from (
      select t.tipo, jsonb_build_object(
        'pen',coalesce(sum(b.monto_estimado) filter(where b.moneda='PEN'),0),
        'usd',coalesce(sum(b.monto_estimado) filter(where b.moneda='USD'),0)) as valor
      from (values('asignado'),('parkeado'),('ganado')) t(tipo)
      left join base b on (t.tipo='ganado' and b.etapa='convertido')
        or (b.etapa not in ('convertido','descartado') and
          ((t.tipo='asignado' and b.vendedor_id is not null) or (t.tipo='parkeado' and b.vendedor_id is null)))
      group by t.tipo
    ) montos
  )
  select jsonb_build_object('version',1,'generado_en',now(),
    'desde',p_desde,'hasta',p_hasta,'origen',p_origen,'procedencia',p_procedencia,
    'reasignados',coalesce(p_reasignados,false),'campania_origen',p_campania_origen,
    -- La columna de trabajo `potencial_nivel` no viaja: las filas tienen la forma de siempre.
    'items',coalesce((select jsonb_agg(to_jsonb(f) - 'potencial_nivel' order by f.actualizado_en desc,f.id) from filas f),'[]'::jsonb),
    'resumen',jsonb_build_object('totales',(select to_jsonb(m) from metricas m),
      'capital',(select valor from capital),
      'conversion',jsonb_build_object(
        'convertidos',(select count(*) from base where etapa='convertido' and vendedor_id is not null),
        'base',(select count(*) from base where vendedor_id is not null),
        'pct',coalesce((select round(100.0 * count(*) filter(where etapa='convertido')
          / nullif(count(*),0))::int from base where vendedor_id is not null),0)),
      'descartes',jsonb_build_object(
        'total',(select count(*) from base where etapa='descartado'),
        'sin_motivo',(select count(*) from base where etapa='descartado' and motivo_descarte is null),
        'por_motivo',(select coalesce(jsonb_agg(to_jsonb(d) order by d.n desc,d.motivo),'[]'::jsonb)
          from (select motivo_descarte as motivo,count(*) as n from base
            where etapa='descartado' and motivo_descarte is not null group by motivo_descarte) d)),
      'sin_tocar',(select count(*) from base b where b.etapa not in('convertido','descartado')
        and b.vendedor_id is not null and not exists(select 1 from crm.actividades a
          where a.lead_id=b.id and a.tipo in ('llamada_realizada','llamada_no_contestada',
            'whatsapp_enviado','whatsapp_recibido','reunion_realizada'))),
      'embudo',(select jsonb_agg(jsonb_build_object('etapa',e.etapa,'n',
        (select count(*) from base b where b.etapa=e.etapa)) order by e.ord)
        from (values('nuevo',1),('contactado',2),('reunion_agendada',3),
          ('propuesta_enviada',4),('convertido',5),('descartado',6)) e(etapa,ord)))
      -- Conteos por nivel sobre `previa` (antes de `p_potencial`) y el eco del filtro. Solo con
      -- el potencial vigente para el actor: si no, el resumen es byte a byte el de antes.
      || case when v_potencial then jsonb_build_object('potencial',(select jsonb_build_object(
          'filtro',p_potencial,
          'estrella',count(*) filter(where pv.potencial_nivel='estrella'),
          'tibio',count(*) filter(where pv.potencial_nivel='tibio'),
          'frio',count(*) filter(where pv.potencial_nivel='frio'),
          'sin_marca',count(*) filter(where pv.potencial_nivel is null)) from previa pv))
        else '{}'::jsonb end)
  into v_salida;
  return v_salida;
end;
$function$
;
CREATE OR REPLACE FUNCTION crm.cartera_pagina_fn(p_limite integer DEFAULT 50, p_antes_de timestamp with time zone DEFAULT NULL::timestamp with time zone, p_antes_id uuid DEFAULT NULL::uuid, p_etapa text DEFAULT NULL::text, p_vendedor_id uuid DEFAULT NULL::uuid, p_sin_asignar boolean DEFAULT false, p_texto text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, nombre_completo text, telefono text, telefono_alternativo text, telefono_alternativo_crudo text, correo text, dni text, genero text, fecha_nacimiento date, distrito text, origen text, etapa text, motivo_descarte text, monto_estimado numeric, moneda text, categoria_interes text, vendedor_id uuid, asignado_supervisor_id uuid, creado_en timestamp with time zone, tenencia_desde timestamp with time zone, convertido_en timestamp with time zone, contrato_id uuid, actualizado_en timestamp with time zone, activo boolean, nota text, no_contactar boolean, ultimo_contacto_en timestamp with time zone, campania_origen text)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text;
  v_lector boolean;
  v_visibles uuid[];
  v_corte timestamptz := now() - interval '45 days'; -- ventana_convertidos_dias
  v_texto text;
  v_digitos text;
  v_patron_texto text;
  v_patron_digitos text;
begin
  -- Guardia de ADMISION (el ALCANCE lo pone la RLS, ver 20260810141953).
  v_rol := private.rol_crm(v_uid);
  v_lector := private.es_lector_global();
  if v_uid is null or (v_rol is null and not v_lector) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  -- Se resuelve UNA vez (la policy lo evalua como SubPlan en cada fila).
  v_visibles := array(select private.vendedor_ids_visibles(v_uid));

  if p_limite is null or p_limite < 1 or p_limite > 200 then
    raise exception 'Parametro p_limite invalido' using errcode = '22023';
  end if;

  -- Cursor A MEDIAS = paginas que se saltan filas en silencio. O los dos
  -- componentes o ninguno: el desempate por id es parte del cursor, no un extra.
  if (p_antes_de is null) <> (p_antes_id is null) then
    raise exception 'Cursor incompleto: p_antes_de y p_antes_id viajan juntos'
      using errcode = '22023';
  end if;

  if p_etapa is not null and p_etapa not in (
    'nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada',
    'convertido', 'descartado'
  ) then
    raise exception 'Parametro p_etapa invalido' using errcode = '22023';
  end if;

  -- "Sin asignar" y "de este vendedor" son mutuamente excluyentes: pedir ambos
  -- solo puede ser un bug del llamante, y devolver 0 filas lo esconderia.
  if coalesce(p_sin_asignar, false) and p_vendedor_id is not null then
    raise exception 'Filtro contradictorio: p_sin_asignar con p_vendedor_id'
      using errcode = '22023';
  end if;

  v_texto := nullif(btrim(coalesce(p_texto, '')), '');
  if v_texto is not null then
    if length(v_texto) < 2 then
      raise exception 'Parametro p_texto invalido: minimo 2 caracteres'
        using errcode = '22023';
    end if;
    v_texto := left(v_texto, 80);
    v_digitos := left(regexp_replace(v_texto, '\D', '', 'g'), 15);
    -- El texto del usuario es un LITERAL, no un patron: `\`, `%` y `_` se
    -- escapan antes de envolverlo en comodines (la barra PRIMERO, o se
    -- re-escaparian las que introducen los otros dos replace). Los `ilike` de
    -- abajo declaran `escape` explicitamente en vez de confiar en el default:
    -- asi la intencion no depende de `standard_conforming_strings`.
    v_patron_texto := '%' || replace(replace(replace(v_texto, E'\\', E'\\\\'), '%', E'\\%'), '_', E'\\_') || '%';
    v_patron_digitos := case when length(v_digitos) >= 3 then '%' || v_digitos || '%' end;
  end if;

  return query
  select l.id,
         l.nombre_completo,
         l.telefono,
         -- EL CAMBIO DE ESTA MIGRACION. Sin esta linea la ficha del lead no
         -- puede dibujar el segundo numero aunque la base lo tenga guardado.
         l.telefono_alternativo,
         -- EL CAMBIO DE ESTA MIGRACION. La ficha se sirve del store, no de esta
         -- pagina, asi que tecnicamente podria vivir sin la columna — pero
         -- entonces `Lead` tendria DOS formas segun de donde venga la fila, y esa
         -- divergencia es exactamente como se pierde un dato sin que nadie lo vea.
         l.telefono_alternativo_crudo,
         l.correo,
         l.dni,
         l.genero,
         l.fecha_nacimiento,
         l.distrito,
         l.origen,
         l.etapa,
         l.motivo_descarte,
         l.monto_estimado,
         l.moneda,
         l.categoria_interes,
         l.vendedor_id,
         l.asignado_supervisor_id,
         l.creado_en,
         l.tenencia_desde,
         l.convertido_en,
         l.contrato_id,
         l.actualizado_en,
         l.activo,
         l.nota,
         l.no_contactar,
         uc.creado_en as ultimo_contacto_en,
         l.campania_origen
  from crm.leads l
  -- Ultimo CONTACTO real (semaforo del kanban): los 5 tipos de TIPOS_CONTACTO,
  -- jamas cualquier fila del timeline. Mismo criterio que cola_accion_fn — que
  -- este dato viaje YA en la pagina es lo que deja a F3 sin migraciones.
  left join lateral (
    select act.creado_en
    from crm.actividades act
    where act.lead_id = l.id
      and act.tipo in ('llamada_realizada', 'llamada_no_contestada',
                       'whatsapp_enviado', 'whatsapp_recibido', 'reunion_realizada')
    order by act.creado_en desc
    limit 1
  ) uc on true
  -- Redundante para todos los roles menos el lector global, que es justamente a
  -- quien le mezclaba filas con sus tiles (20260810151433).
  where l.activo is true
    and (l.etapa <> 'convertido' or l.convertido_en >= v_corte)
    -- Pista de ambito: REDUNDANTE con la policy. Solo puede restar filas; lo
    -- que se ve lo sigue decidiendo `leads_select`.
    and (
      v_lector
      or v_rol = 'gerencia'
      or l.vendedor_id = any(v_visibles)
      or (l.vendedor_id is null and l.asignado_supervisor_id = any(v_visibles))
    )
    -- Keyset. Los sentidos del orden son MIXTOS (actualizado_en desc, id asc),
    -- asi que la comparacion NO puede escribirse como tupla `(a, b) < (x, y)`:
    -- esa forma solo es correcta cuando ambas columnas ordenan igual.
    and (
      p_antes_de is null
      or l.actualizado_en < p_antes_de
      or (l.actualizado_en = p_antes_de and l.id > p_antes_id)
    )
    and (p_etapa is null or l.etapa = p_etapa)
    and (p_vendedor_id is null or l.vendedor_id = p_vendedor_id)
    and (not coalesce(p_sin_asignar, false) or l.vendedor_id is null)
    and (
      v_texto is null
      or l.nombre_completo ilike v_patron_texto escape E'\\'
      or (v_patron_digitos is not null
          and (l.telefono ilike v_patron_digitos escape E'\\'
               -- Buscar por el SEGUNDO numero. Sin esto, el vendedor que recibe
               -- una llamada del alternativo escribe ese numero y el buscador le
               -- responde que el lead no existe.
               or l.telefono_alternativo ilike v_patron_digitos escape E'\\'
               or l.dni ilike v_patron_digitos escape E'\\'))
    )
  order by l.actualizado_en desc, l.id asc
  limit p_limite;
end;
$function$
;

revoke all on function crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text,text) from public, anon, authenticated, service_role;
grant execute on function crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text,text) to authenticated;
revoke all on function crm.cartera_pagina_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text) from public, anon, authenticated, service_role;
grant execute on function crm.cartera_pagina_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text) to authenticated;

-- DROP elimina los comentarios del catálogo: conservarlos también en OpenAPI.
do $metadatos$
declare r record; f regprocedure;
begin
  for r in select * from formulario3_fase2_metadatos loop
    select oid::regprocedure into strict f from pg_proc
      where pronamespace='crm'::regnamespace and proname=r.nombre;
    execute format('comment on function %s is %L',f,r.comentario);
    if obj_description(f,'pg_proc') is distinct from r.comentario then
      raise exception 'Comentario perdido al recrear %',f;
    end if;
  end loop;
end;
$metadatos$;

do $postflight$
begin
  if (select count(*) from pg_proc where pronamespace='crm'::regnamespace
      and proname in ('cartera_filtrada_fn','cartera_pagina_fn')) <> 2
    or to_regprocedure('crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text,text)') is not null then
    raise exception 'La cartera debe tener una sola firma por nombre';
  end if;
  if exists(select 1 from pg_proc where pronamespace='crm'::regnamespace
      and proname in ('cartera_filtrada_fn','cartera_pagina_fn')
      and (pg_get_userbyid(proowner)<>'postgres' or prosecdef
        or provolatile<>'s' or proconfig is distinct from array['search_path=""']
        or proacl::text is distinct from '{postgres=X/postgres,authenticated=X/postgres}')) then
    raise exception 'Atributos o permisos de cartera alterados';
  end if;
  if md5(pg_get_functiondef('crm.resumen_cartera_fn()'::regprocedure)) <> '4a896597486e8b23788a2b2497f16309' then
    raise exception 'El envoltorio de resumen cambió; revisar compatibilidad';
  end if;
end;
$postflight$;
notify pgrst, 'reload schema';
commit;

