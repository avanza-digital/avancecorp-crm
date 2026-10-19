ROLE: SECONDARY_REVIEWER.

Do not modify files. Do not implement the task. Do not invoke Claude.
Do not delegate to another coding agent. Do not create another review chain.
Follow the review protocol (transcrito al final).

Responde en español. No tienes shell, red ni base de datos: todo lo que debes juzgar está transcrito aquí (los
archivos llevan número de línea). Formato: VERDICT (PASS/CHANGES_REQUESTED/BLOCK), SUMMARY, RESPUESTA a cada
pregunta P1–P8 (sí/no + por qué, con evidencia archivo:línea del texto transcrito), FINDINGS P0–P3, RIESGOS y test
gaps, NEXT ACTIONS, CONFIDENCE. Pídete REFUTAR: busca lo que el plan no cierra o lo que rompe, no lo que está bien.
Es una revisión de DISEÑO (todavía no hay código): ronda 1 de máximo 2.

# Encargo: Gestión Diaria debe contar las llamadas a CLIENTES en el número de llamadas del analista — PLAN — LEVEL 3
(permisos/RLS, funciones selladas por huella, métricas que gobiernan cortes de jornada). Generado el 2026-10-19.

## Qué es
CRM interno (Supabase/Postgres 17). Esquema `crm` expuesto por PostgREST (puertas = funciones no trigger de `crm`),
núcleo en `private`, tablas con RLS deny-by-default. «Gestión Diaria» muestra al analista su marcador del día
(llamadas, contestadas, útiles, tasa de contacto, personas tocadas, por hora), al supervisor la vista de equipo y a
gerencia Pulso/Hábitos. Hoy TODO ese marcador sale de UN lector: `private.gestion_diaria_llamadas_eventos`, que lee
`crm.actividades` (tabla de leads: `lead_id NOT NULL`). Las llamadas a CLIENTES (postventa) se guardan en OTRA
tabla, `crm.inversionista_gestiones` (tipo 'cierre' de una tarea de tipo 'llamada', con `metadata.resultado`), y el
marcador nunca la mira.

## Síntoma confirmado en producción (19/10/2026, Lima)
Analista VLADIMIR JURADO, hoy: 1 llamada a lead (cuenta) y 6 cierres de tareas de llamada a clientes
(resultados: agendo_reunion ×3, volver_a_llamar ×2, sin_resultado ×1) que NO cuentan. Su marcador muestra «1».
Últimos 30 días, toda la empresa: 6.823 llamadas a leads en `crm.actividades` (23 analistas); 33 cierres de tareas
de llamada a clientes en `crm.inversionista_gestiones` (10 analistas); 2 filas de llamada en `crm.actividades_cliente`
(camino legado); 50 cierres de postventa con `metadata.resultado` (todas las clases); 24 tareas de llamada a clientes
pendientes. Banderas `postventa_neutral` y `ficha_360_neutral` ACTIVAS.
`pg_policies` sobre `crm.inversionista_gestiones`: NINGUNA policy SELECT (deny-by-default; solo se lee vía funciones
DEFINER). `crm.tareas` sí tiene `tareas_select` (vendedor_ids_visibles / gerencia) y `tareas_postventa_lectura`
(`inversionista_id is null or private.postventa_visible(inversionista_id)`).

## Decisiones de Miguel (19/10/2026)
1. Las llamadas a clientes SUMAN al mismo número «Llamadas» del analista (no cifra aparte).
2. Entran también en la TASA DE CONTACTO.
3. Cuentan hacia los cortes de jornada y el mínimo de llamadas útiles.
Regla propuesta por Claude (pendiente de confirmar): un cierre de cliente SIN resultado cuenta como llamada pero no
como contestada ni útil (igual que ya lo hace la tabla «Gestión de clientes», ver gestiones_clientes_eventos).

## PLAN que debes refutar

### Fase 1 · Servidor (una migración)
1. Nuevo ayudante `private.gestion_diaria_llamadas_clientes_eventos(p_ini timestamptz, p_fin timestamptz,
   p_vendedor_ids uuid[])` SECURITY DEFINER, owner postgres, `set search_path=''`, STABLE, EXECUTE solo a
   `authenticated`. Dentro: exige `auth.uid()` no nulo; exige que TODO id no nulo de `p_vendedor_ids` esté en
   `private.vendedor_ids_visibles(auth.uid())` (si no, 42501); si la postventa no está habilitada
   (`crm.postventa_estado_fn()->>'habilitada'`), devuelve vacío; ignora los NULL de `p_vendedor_ids`. Lee
   `crm.inversionista_gestiones g join crm.tareas t on t.id=g.tarea_id` con `g.tipo='cierre'`,
   `coalesce(g.metadata->>'tipo_tarea',t.tipo)='llamada'`, `g.metadata->>'estado'='completada'`,
   `g.creado_por = any(p_vendedor_ids)`, ventana `[p_ini,p_fin)` sobre `g.creado_en`. Devuelve las mismas columnas
   que el lector de leads: `vendedor_id=g.creado_por, id=g.id, lead_id=NULL, tipo` (= 'llamada_no_contestada' si
   resultado ∈ {no_contesto, numero_errado, no_es_la_persona}; si no 'llamada_realizada'), `creado_en, resultado`
   (coalesce(metadata->>'resultado','sin_resultado')), `util` (= resultado ∉ {numero_errado, no_es_la_persona,
   sin_resultado}), `hora` (Lima) y además `persona_id = g.inversionista_id`.
   Motivo del DEFINER: la tabla no tiene policy de lectura y la cadena del marcador corre como el actor (INVOKER,
   sellado así por el gate). El ayudante es un ESPEJO de la visibilidad (vendedor_ids_visibles), no una puerta.
2. `private.gestion_diaria_llamadas_eventos` (INVOKER, sin cambiar firma de entrada) pasa a devolver
   leads ∪ clientes (`union all` del cuerpo actual + el ayudante) y gana la columna `persona_id`
   (leads: `lead_id`; clientes: `inversionista_id`). Requiere DROP + CREATE por el cambio de tipo de retorno.
3. `private.gestion_diaria_llamadas` (agregador): `leads_tocados` se calcula sobre `persona_id` (personas tocadas,
   leads y clientes) en vez de `lead_id`. Nada más cambia. Sin `count(` crudo (trinquete del censo analítico:
   `cardinality(array_agg(...))`).
4. Re-sellar las huellas md5 donde esas dos funciones están selladas (`private.assert_gestion_diaria_analista`,
   y comprobar en banco `assert_gestion_diaria_citas`/`_pulso`/`_cortes`/`_equipo` y el censo analítico) y añadir
   mutantes al `assert_gestion_diaria_analista_mutantes`: (a) ayudante que no valida vendedor_ids_visibles, (b)
   ayudante con EXECUTE a anon/public, (c) ayudante que ignora la bandera de postventa, (d) lector sin la unión
   (vuelve a solo leads), (e) `count(` crudo en el ayudante.
   Efecto automático (todos leen el mismo lector): Mi día, Equipo, «Llamadas de hoy» del supervisor, cortes de
   jornada, mínimo de útiles, Pulso y Hábitos. LÍMITE DECLARADO: el sub-número «leads distintos» del Pulso
   (`count(distinct lead_id)` en pulso_metricas) sigue contando solo leads en esta fase (no se toca el pulso).
### Fase 2 · Pantalla (misma PR)
Textos: «Tocaste N personas (leads y clientes)», nota aclaratoria, «Personas distintas» en el resumen del equipo;
fixtures y tests al contrato. El número ya se abre: el Registro del día tiene selector Leads/Clientes.
### Verificación
Banco Docker a paridad con producción, gate RLS antes/después, kit `supabase/scripts/gestion-diaria-analista` con el
caso de Vladimir sembrado; auditor-rls; Codex (esta ronda + 1 opcional sobre el diff); check front; E2E Gestión
Diaria en Docker. Aplicación en producción la hace Miguel.

## Preguntas concretas (responde cada una)
P1. ¿El ayudante DEFINER abre algún camino de lectura que hoy no exista? Compáralo con `gestiones_clientes_eventos`
    (DEFINER, valida con `gestiones_validar`) y con `vendedor_ids_visibles`. ¿Falta alguna condición (p. ej. equipo
    activo, `postventa_visible`, inversionista canónica, reasignación de cartera)?
P2. ¿Es correcto que el lector siga siendo INVOKER llamando a un DEFINER? ¿Rompe algo del gate
    `assert_gestion_diaria_analista` (sección 1: INVOKER/ACL/sin count crudo)?
P3. Clasificación: mismo catálogo de 7 resultados en leads y clientes (ver postventa_tarea_fn). ¿La traducción
    propuesta (tipo/util/contestada) es coherente con la del marcador de leads (`gestion_diaria_llamadas`:
    contestadas = tipo realizada AND util; util = resultado ∉ {numero_errado, no_es_la_persona}, «sin resultado
    cuenta como útil») y con la de `gestiones_clientes_eventos`? Señala cualquier incoherencia entre las dos
    pantallas tras el cambio.
P4. Invariantes del front (`gestion-diaria-equipo.ts`: suma por hora = llamadas; contestadas por hora −
    contestadas ≤ llamadas − útiles). ¿Se mantienen con la clase «sin_resultado → realizada, no útil»?
P5. `leads_tocados` sobre `persona_id`: ¿algún consumidor (pulso, hábitos, cortes) depende de que `lead_id` no sea
    NULL o de `count(distinct lead_id)`? ¿Hay riesgo de que un NULL entre en `array_agg(distinct ...)` y sume 1?
P6. Doble conteo: ¿puede una misma llamada a cliente aparecer en `crm.actividades` (lead convertido que conserva su
    ficha) Y en `inversionista_gestiones`? ¿Y entre `actividades_cliente` (legado, 2 filas/30 días) e
    `inversionista_gestiones`? ¿Hay que excluir `actividades_cliente` explícitamente o incluirla con la misma regla
    de `gestiones_clientes_eventos` (not exists cierre)?
P7. Cortes de jornada y mínimo de útiles (`gestion_diaria_cortes`; política con `minimo_llamadas_utiles`):
    ¿algún efecto no deseado (p. ej. alertas retroactivas del día de hoy al aplicar, cortes ya reconocidos)?
P8. ¿Qué falta en el plan de pruebas? Propón los casos mínimos del kit (incluye negativo de visibilidad: un
    supervisor pidiendo un analista de OTRO equipo; un vendedor pidiendo otro id).

## EVIDENCIA TRANSCRITA

### supabase/migrations/20260924201358_crm_gestion_diaria_pulso_habitos.sql (líneas 7–33)
```
    7  -- Fuente única de eventos para el marcador, los únicos globales y los huecos.
    8  -- La autorización de filas sigue en RLS; cada llamador limita los autores.
    9  create or replace function private.gestion_diaria_llamadas_eventos(
   10    p_ini timestamptz,p_fin timestamptz,p_vendedor_ids uuid[])
   11  returns table(vendedor_id uuid,id uuid,lead_id uuid,tipo text,creado_en timestamptz,
   12    resultado text,util boolean,hora integer)
   13  language sql stable security invoker set search_path='' as $$
   14    select a.creado_por,a.id,a.lead_id,a.tipo,a.creado_en,
   15      coalesce(a.metadata->>'resultado','sin_resultado'),
   16      coalesce(a.metadata->>'resultado','') not in ('numero_errado','no_es_la_persona'),
   17      extract(hour from a.creado_en at time zone 'America/Lima')::integer
   18    from crm.actividades a where
   19      (a.creado_por=any(p_vendedor_ids)
   20        or (a.creado_por is null and array_position(p_vendedor_ids,null) is not null))
   21      and a.tipo in ('llamada_realizada','llamada_no_contestada')
   22      and a.creado_en>=p_ini and a.creado_en<p_fin;
   23  $$;
   24  
   25  -- Hechos de gestión, con la misma definición de actividad de F4.
   26  create or replace function private.gestion_diaria_gestiones_eventos(p_ini timestamptz,p_fin timestamptz)
   27  returns table(id uuid,creado_por uuid,creado_en timestamptz)
   28  language sql stable security invoker set search_path='' as $$
   29    select a.id,a.creado_por,a.creado_en from crm.actividades a
   30    where a.creado_en>=p_ini and a.creado_en<p_fin
   31      and a.tipo in ('llamada_realizada','llamada_no_contestada','whatsapp_enviado',
   32        'reunion_realizada','nota','conversion');
   33  $$;
```

### supabase/migrations/20260924201358_crm_gestion_diaria_pulso_habitos.sql (líneas 35–118)
```
   35  CREATE OR REPLACE FUNCTION private.gestion_diaria_llamadas(p_ini timestamp with time zone, p_fin timestamp with time zone, p_vendedor_ids uuid[])
   36   RETURNS TABLE(vendedor_id uuid, llamadas integer, contestadas integer, utiles integer, leads_tocados integer, citas_agendadas integer, primera_llamada_en timestamp with time zone, ultima_llamada_en timestamp with time zone, por_resultado jsonb, por_hora jsonb)
   37   LANGUAGE sql
   38   STABLE
   39   SET search_path TO ''
   40  AS $function$
   41    with vendedores as (
   42      select distinct v.id from unnest(p_vendedor_ids) as v(id)
   43    ),
   44    ll as (
   45      select * from private.gestion_diaria_llamadas_eventos(p_ini,p_fin,p_vendedor_ids)
   46    ),
   47    agg as (
   48      select l.vendedor_id,
   49             cardinality(array_agg(l.id)) as llamadas,
   50             -- Contestadas ⊆ útiles POR CONSTRUCCIÓN: la tasa nunca puede pasar del
   51             -- 100 % aunque una fila histórica llevara un resultado incoherente
   52             -- con su tipo (hoy no hay ninguna: medido en producción el 20/09).
   53             coalesce(cardinality(array_agg(l.id) filter (where l.tipo = 'llamada_realizada' and l.util)), 0) as contestadas,
   54             coalesce(cardinality(array_agg(l.id) filter (where l.util)), 0) as utiles,
   55             cardinality(array_agg(distinct l.lead_id)) as leads_tocados,
   56             min(l.creado_en) as primera_llamada_en,
   57             max(l.creado_en) as ultima_llamada_en
   58      from ll l
   59      group by l.vendedor_id
   60    ),
   61    por_resultado as (
   62      select r.vendedor_id, jsonb_object_agg(r.resultado, r.n) as por_resultado
   63      from (
   64        select l.vendedor_id, l.resultado, cardinality(array_agg(l.id)) as n
   65        from ll l
   66        group by l.vendedor_id, l.resultado
   67      ) r
   68      group by r.vendedor_id
   69    ),
   70    por_hora as (
   71      select h.vendedor_id,
   72             jsonb_agg(jsonb_build_object('hora', h.hora, 'llamadas', h.n, 'contestadas', h.c) order by h.hora) as por_hora
   73      from (
   74        select l.vendedor_id, l.hora, cardinality(array_agg(l.id)) as n,
   75               coalesce(cardinality(array_agg(l.id) filter (where l.tipo = 'llamada_realizada')), 0) as c
   76        from ll l
   77        group by l.vendedor_id, l.hora
   78      ) h
   79      group by h.vendedor_id
   80    ),
   81    citas as (
   82      -- Cita agendada = tarea de cita CREADA en la ventana por el analista (la
   83      -- misma definición que metricas_agenda_fn). Las reprogramadas crean otra
   84      -- tarea y cuentan igual que allí.
   85      select t.vendedor_id, cardinality(array_agg(t.id)) as citas_agendadas
   86      from crm.tareas t
   87      where (t.vendedor_id in (select v.id from vendedores v)
   88        or (t.vendedor_id is null and array_position(p_vendedor_ids, null) is not null))
   89        and t.tipo = 'reunion'
   90        and t.creado_en >= p_ini
   91        and t.creado_en <  p_fin
   92      group by t.vendedor_id
   93    )
   94    select v.id,
   95           coalesce(a.llamadas, 0),
   96           coalesce(a.contestadas, 0),
   97           coalesce(a.utiles, 0),
   98           coalesce(a.leads_tocados, 0),
   99           coalesce(c.citas_agendadas, 0),
  100           a.primera_llamada_en,
  101           a.ultima_llamada_en,
  102           coalesce(r.por_resultado, '{}'::jsonb),
  103           coalesce(h.por_hora, '[]'::jsonb)
  104    from vendedores v
  105    left join agg a on a.vendedor_id is not distinct from v.id
  106    left join por_resultado r on r.vendedor_id is not distinct from v.id
  107    left join por_hora h on h.vendedor_id is not distinct from v.id
  108    left join citas c on c.vendedor_id is not distinct from v.id
  109    order by v.id;
  110  $function$;
  111  
  112  create or replace function private.gestion_diaria_pulso_autorizar()
  113  returns void language plpgsql stable security invoker set search_path='' as $$
  114  begin
  115    if auth.uid() is null or not private.puede_acceder_crm()
  116      or not (coalesce(private.rol_crm(auth.uid())='gerencia',false)
  117        or coalesce(private.es_lector_global(),false)) then
  118      raise exception 'Solo gerencia puede consultar toda la operación' using errcode='42501';
```

### supabase/migrations/20260924201358_crm_gestion_diaria_pulso_habitos.sql (líneas 226–237)
```
  226    -- Mismo universo de eventos; distinta granularidad para deduplicar un lead
  227    -- compartido entre autores/equipos. No es otro contador de llamadas.
  228    with roster as materialized (select * from private.gestion_diaria_pulso_roster()),
  229    eventos as materialized (
  230      select a.lead_id,coalesce(r.supervisor_id::text,'fuera') as clave_equipo
  231      from private.gestion_diaria_llamadas_eventos(v_ini,v_fin,v_ids) a
  232      left join roster r on r.analista_id=a.vendedor_id
  233    ), por_equipo as (
  234      select clave_equipo,count(distinct lead_id) as n from eventos group by clave_equipo
  235    ) select (select count(distinct lead_id)::integer from eventos),
  236        coalesce((select jsonb_object_agg(clave_equipo,n) from por_equipo),'{}'::jsonb)
  237      into v_unicos,v_por_equipo;
```

### supabase/migrations/20260924201358_crm_gestion_diaria_pulso_habitos.sql (líneas 333–345)
```
  333      v_fin:=greatest(v_inicio,least(p_ahora,v_cierre));
  334    end if;
  335    with eventos as materialized (
  336      select a.vendedor_id as creado_por,a.id,a.creado_en,
  337        lag(a.creado_en) over(partition by a.vendedor_id order by a.creado_en,a.id) as anterior
  338      from private.gestion_diaria_llamadas_eventos(v_inicio,v_fin,p_analistas) a
  339    ), huecos as (
  340      select e.*,row_number() over(partition by e.creado_por
  341        order by e.creado_en-e.anterior desc,e.anterior,e.creado_en,e.id) as posicion
  342      from eventos e where e.anterior is not null
  343    ), extremos as (
  344      select creado_por,min(creado_en) as primera,max(creado_en) as ultima
  345      from eventos group by creado_por
```

### supabase/migrations/20260921214018_crm_gestion_diaria_cortes.sql (líneas 183–202)
```
  183    v_limite_recuperacion := coalesce(v_corte2, v_fin);
  184    v_minimo := case when v_dow = 6 then v_p.sabado_minimo else v_p.corte_1_minimo end;
  185    v_puede_avisar := p_dia = (p_ahora at time zone 'America/Lima')::date
  186      and p_ahora >= v_inicio and p_ahora < v_fin;
  187  
  188    with roster as (
  189      select unnest(v_ids) as analista_id
  190    ), primero as materialized (
  191      select ll.* from private.gestion_diaria_llamadas(v_ini, v_corte1,
  192        case when p_ahora >= v_corte1 then v_ids else '{}'::uuid[] end) ll
  193    ), segundo as materialized (
  194      select ll.* from private.gestion_diaria_llamadas(v_ini, coalesce(v_corte2, v_ini),
  195        case when p_ahora >= v_corte2 then v_ids else '{}'::uuid[] end) ll
  196    ), recuperacion as materialized (
  197      select ll.* from private.gestion_diaria_llamadas(v_ini, least(p_ahora, v_limite_recuperacion),
  198        case when p_ahora >= v_corte1 then v_ids else '{}'::uuid[] end) ll
  199    ), base as (
  200      select r.analista_id,
  201        exists(select 1 from crm.leads l where l.vendedor_id = r.analista_id and l.activo
  202          and l.etapa not in ('convertido', 'descartado')) as cartera_abierta,
```

### supabase/migrations/20260924201358_crm_gestion_diaria_pulso_habitos.sql (líneas 486–561)
```
  486  CREATE OR REPLACE FUNCTION private.assert_gestion_diaria_analista()
  487   RETURNS text
  488   LANGUAGE plpgsql
  489   STABLE SECURITY DEFINER
  490   SET search_path TO ''
  491  AS $function$
  492  declare
  493    v_firma text;
  494    v_md5 text;
  495    v_id oid;
  496  begin
  497    -- 1. Puerta y núcleos: INVOKER, estables, search_path vacío, owner postgres,
  498    --    EXECUTE exactamente para authenticated (la cadena corre como el actor).
  499    foreach v_firma in array array[
  500      'crm.gestion_diaria_analista_fn(date,uuid)',
  501      'private.gestion_diaria_analista_core(uuid,date,timestamptz,timestamptz,timestamptz,timestamptz,uuid)',
  502      'private.gestion_diaria_llamadas(timestamptz,timestamptz,uuid[])',
  503      'private.gestion_diaria_llamadas_eventos(timestamptz,timestamptz,uuid[])',
  504      'private.gestion_diaria_umbrales()'
  505    ] loop
  506      v_id := to_regprocedure(v_firma);
  507      if v_id is null or not exists (
  508        select 1 from pg_proc p
  509        where p.oid = v_id and not p.prosecdef
  510          and p.proowner = 'postgres'::regrole::oid
  511          and p.provolatile = 's'
  512          and p.proconfig @> array['search_path=""']
  513      ) then
  514        raise exception 'Contrato del dia del analista alterado (debe ser INVOKER, stable, search_path vacio): %', v_firma;
  515      end if;
  516      if not has_function_privilege('authenticated', v_id, 'EXECUTE')
  517         or exists (
  518           select 1 from pg_proc p
  519           cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
  520           where p.oid = v_id
  521             and a.grantee not in ('postgres'::regrole::oid, 'authenticated'::regrole::oid)
  522         ) then
  523        raise exception 'ACL del dia del analista alterada: %', v_firma;
  524      end if;
  525      -- Ningún contador crudo en los cuerpos propios (trinquete del censo analítico).
  526      if exists (select 1 from pg_proc p where p.oid = v_id
  527                 and (lower(p.prosrc) ~ '\mcount\s*\(' or lower(p.prosrc) ~ '\msum\s*\(\s*1\s*\)')) then
  528        raise exception 'Una funcion del dia del analista cuenta a crudo: %', v_firma;
  529      end if;
  530    end loop;
  531  
  532    -- 2. Los CUERPOS propios, sellados (medidos en el banco, dos pasadas).
  533    for v_firma, v_md5 in select * from (values
  534      ('crm.gestion_diaria_analista_fn(date,uuid)',                                                          'ba3d0502ae4bf0d010677562d47634a5'),
  535      ('private.gestion_diaria_analista_core(uuid,date,timestamptz,timestamptz,timestamptz,timestamptz,uuid)',    '4dd5313e606b57485cd105b125f412b7'),
  536      ('private.gestion_diaria_llamadas(timestamptz,timestamptz,uuid[])',                                    '7c5d14e65cc0e55e57214589d11e9c9d'),
  537      ('private.gestion_diaria_llamadas_eventos(timestamptz,timestamptz,uuid[])', '27d25609c74e04c58f82e36af45d7327'),
  538      ('private.gestion_diaria_umbrales()',                                                                   '151860fa342b98d4f2ce9ed7054e390b'),
  539      -- El roster ES la autorización para mirar el día de otro: si alguien lo
  540      -- reescribe, este gate se pone en rojo y hay que re-sellar a conciencia
  541      -- (md5 medido en producción el 20/09/2026).
  542      ('crm.equipo_visible_fn()',                                                                             '200162f4519586a6c68d8ccf0cf591f7')
  543    ) as m(firma, md5) loop
  544      if to_regprocedure(v_firma) is null
  545         or md5(pg_get_functiondef(to_regprocedure(v_firma))) is distinct from v_md5 then
  546        raise exception 'El cuerpo de % cambio: re-sellar el dia del analista de Gestion Diaria (md5 %)',
  547          v_firma, coalesce(md5(pg_get_functiondef(to_regprocedure(v_firma))), 'ausente');
  548      end if;
  549    end loop;
  550  
  551    -- 3. La cola de la que bebe la pantalla, en su forma: DEFINER, estable,
  552    --    search_path vacío, ejecutable por authenticated. (Su cuerpo no se sella
  553    --    aquí: pertenece al mundo SLA; el front valida el contrato de la página.)
  554    v_id := to_regprocedure('crm.cola_accion_v2_fn(integer,text,text,uuid,jsonb)');
  555    if v_id is null or not exists (
  556      select 1 from pg_proc p
  557      where p.oid = v_id and p.prosecdef and p.proowner = 'postgres'::regrole::oid
  558        and p.provolatile = 's' and p.proconfig @> array['search_path=""']
  559    ) or not has_function_privilege('authenticated', v_id, 'EXECUTE') then
  560      raise exception 'crm.cola_accion_v2_fn perdio su forma o su EXECUTE';
  561    end if;
```

### supabase/migrations/20260709000001_cimientos_crm.sql (líneas 205–217)
```
  205  create table crm.actividades (
  206    id         uuid primary key default gen_random_uuid(),
  207    lead_id    uuid not null references crm.leads(id) on delete cascade,
  208    tipo       text not null check (tipo in (
  209      'llamada_realizada','llamada_no_contestada','whatsapp_enviado',
  210      'whatsapp_recibido','reunion_realizada','nota','cambio_etapa',
  211      'reasignacion','conversion')),
  212    detalle    text,
  213    metadata   jsonb not null default '{}'::jsonb,
  214    creado_por uuid references public.perfiles(id) on delete set null,
  215    creado_en  timestamptz not null default now()
  216  );
  217  comment on table crm.actividades is
```

### supabase/migrations/20261006012208_crm_gestiones_clientes_supervision.sql (líneas 79–149)
```
   79  create function private.gestiones_clientes_eventos(p_desde date,p_hasta date,p_autores uuid[] default null,
   80    p_detalles boolean default true,p_limite integer default 500,p_tipos text[] default null,
   81    p_antes_de timestamptz default null,p_antes_id uuid default null,p_antes_origen text default null)
   82  returns table(id uuid,origen text,identidad jsonb,tipo text,detalle text,metadata jsonb,
   83    creado_por uuid,autor_nombre text,creado_en timestamptz,operativa boolean,contacto boolean)
   84  language plpgsql security definer set search_path='' as $$
   85  declare v_ids uuid[]; v_f6 boolean; v_limite integer;
   86  begin
   87    perform private.gestiones_validar(p_desde,p_hasta,p_autores);
   88    if p_detalles is null or p_limite is null or p_limite not between 1 and 500 then
   89      raise exception 'Página de gestiones inválida' using errcode='22023'; end if;
   90    -- Los conteos recorren todas las filas autorizadas, sin resolver identidad ni PII.
   91    v_limite:=case when p_detalles then p_limite end;
   92    select array_agg(x) into v_ids from private.vendedor_ids_visibles(auth.uid()) x
   93      where p_autores is null or x=any(p_autores);
   94    v_f6:=coalesce((crm.postventa_estado_fn()->>'habilitada')::boolean,false);
   95    return query
   96    with eventos as (
   97      select g.id,'postventa'::text origen,g.inversionista_id persona,null::uuid perfil,g.tarea_id,
   98        g.creado_por,g.creado_en,case when p_detalles then g.detalle end detalle,
   99        coalesce(g.metadata->>'tipo_tarea',t.tipo) tarea_tipo,
  100        coalesce(g.metadata->>'estado',t.estado) estado,
  101        coalesce(g.metadata->>'resultado','sin_resultado') resultado,
  102        coalesce(g.metadata->>'resultado_reunion',t.resultado_reunion,'sin_clasificar') resultado_reunion,
  103        null::text tipo_legacy
  104      from crm.inversionista_gestiones g join crm.tareas t on t.id=g.tarea_id
  105      where v_f6 and g.tipo='cierre' and g.creado_por=any(v_ids)
  106        and g.creado_en>=p_desde::timestamp at time zone 'America/Lima'
  107        and g.creado_en<(p_hasta+1)::timestamp at time zone 'America/Lima'
  108      union all
  109      select a.id,'perfil',null,a.cliente_id,a.tarea_id,a.creado_por,a.creado_en,case when p_detalles then a.detalle end,
  110        t.tipo,coalesce(t.estado,'completada'),'sin_resultado',coalesce(t.resultado_reunion,'sin_clasificar'),a.tipo
  111      from crm.actividades_cliente a left join crm.tareas t on t.id=a.tarea_id
  112      where a.creado_por=any(v_ids)
  113        and a.creado_en>=p_desde::timestamp at time zone 'America/Lima'
  114        and a.creado_en<(p_hasta+1)::timestamp at time zone 'America/Lima'
  115        -- Los espejos F6 no se convierten en una vía heredada al apagar la bandera.
  116        and not exists(select 1 from crm.inversionista_gestiones g where g.tarea_id=a.tarea_id and g.tipo='cierre')
  117    ), clasificados as (
  118      select e.*,coalesce(e.tipo_legacy,case when e.estado='completada' then
  119        case e.tarea_tipo when 'llamada' then case when e.resultado in ('no_contesto','numero_errado','no_es_la_persona') then 'llamada_no_contestada' else 'llamada_realizada' end
  120          when 'whatsapp' then case when e.resultado='respondio' then 'whatsapp_recibido' else 'whatsapp_enviado' end
  121          when 'reunion' then 'reunion_realizada' else 'nota' end else 'nota' end) clase
  122      from eventos e
  123    ), pagina as materialized (
  124      select e.* from clasificados e
  125      where (p_tipos is null or e.clase=any(p_tipos))
  126        and (p_antes_de is null or e.creado_en<p_antes_de
  127          or (e.creado_en=p_antes_de and (e.origen,e.id)>(p_antes_origen,p_antes_id)))
  128      order by e.creado_en desc,e.origen,e.id limit v_limite
  129    ), sujetos as materialized (
  130      select * from private.gestiones_clientes_identidades(coalesce((select jsonb_agg(to_jsonb(e))
  131        from (select distinct e.persona,e.perfil from pagina e where p_detalles) e),'[]'))
  132    )
  133    select e.id,e.origen,s.identidad,e.clase,
  134      case when (s.identidad->>'identidad_visible')::boolean then e.detalle end,
  135      case when p_detalles then jsonb_build_object('resultado',case when e.clase in ('llamada_realizada','llamada_no_contestada','whatsapp_enviado','whatsapp_recibido') then e.resultado end,
  136        'resultado_reunion',case when e.clase='reunion_realizada' then e.resultado_reunion end,'estado',e.estado,
  137        'tarea_id',case when (s.identidad->>'identidad_visible')::boolean then e.tarea_id end,
  138        'resultado_origen',case when (e.clase='reunion_realizada' and e.resultado_reunion='sin_clasificar')
  139          or (e.clase in ('llamada_realizada','llamada_no_contestada','whatsapp_enviado','whatsapp_recibido') and e.resultado='sin_resultado')
  140          then 'legacy_sin_resultado' else 'declarado' end) end,
  141      e.creado_por,case when p_detalles then coalesce(private.nombre_de_autor(e.creado_por),'—') end,e.creado_en,
  142      e.estado='completada' and e.clase in ('llamada_realizada','llamada_no_contestada','whatsapp_enviado','whatsapp_recibido','reunion_realizada','nota'),
  143      e.clase='llamada_realizada' and (e.tipo_legacy='llamada_realizada' or e.resultado not in ('sin_resultado','numero_errado','no_es_la_persona'))
  144    from pagina e left join sujetos s on s.persona is not distinct from e.persona and s.perfil is not distinct from e.perfil;
  145  end;
  146  $$;
  147  
  148  -- INVOKER: la rama de leads mantiene su RLS. La rama definer solo devuelve clientes autorizados.
  149  create function private.gestiones_operativas_eventos(p_desde date,p_hasta date,p_autores uuid[] default null,
```

### supabase/migrations/20261005224214_crm_resultados_cliente_postventa.sql (líneas 36–70)
```
   36      v_resultado:=p_datos->>'resultado';
   37      v_resultado_reunion:=p_datos->>'resultado_reunion';
   38      if p_datos ? 'version' and p_datos->'version' is distinct from '2'::jsonb then
   39        raise exception 'Versión de cierre inválida' using errcode='22023'; end if;
   40      if v_estado='completada' then
   41        if p_datos->'version' = '2'::jsonb and (
   42          (v_t.tipo in ('llamada','whatsapp') and v_resultado is null)
   43          or (v_t.tipo='reunion' and v_resultado_reunion is null)) then
   44          raise exception 'Selecciona el resultado de la gestión' using errcode='22023'; end if;
   45        if v_t.tipo='llamada' then
   46          if v_resultado is not null and v_resultado not in
   47            ('no_contesto','volver_a_llamar','agendo_reunion','no_interesado',
   48             'numero_errado','no_es_la_persona','pide_otro_producto') then
   49            raise exception 'Resultado de llamada inválido' using errcode='22023'; end if;
   50          if v_resultado_reunion is not null then
   51            raise exception 'Resultado comercial solo para citas' using errcode='22023'; end if;
   52          if v_resultado='agendo_reunion' and
   53            (p_datos->'siguiente'->>'tipo') is distinct from 'reunion' then
   54            raise exception 'Agenda la cita que resultó de la llamada' using errcode='22023'; end if;
   55          if v_resultado='volver_a_llamar' and
   56            (p_datos->'siguiente'->>'tipo') is distinct from 'llamada' then
   57            raise exception 'Agenda la siguiente llamada' using errcode='22023'; end if;
   58        elsif v_t.tipo='whatsapp' then
   59          if v_resultado is not null and v_resultado not in ('enviado','respondio') then
   60            raise exception 'Resultado de WhatsApp inválido' using errcode='22023'; end if;
   61          if v_resultado_reunion is not null then
   62            raise exception 'Resultado comercial solo para citas' using errcode='22023'; end if;
   63        elsif v_t.tipo='reunion' then
   64          if v_resultado is not null then
   65            raise exception 'Resultado de llamada solo para llamadas' using errcode='22023'; end if;
   66          if v_resultado_reunion is not null and v_resultado_reunion not in
   67            ('interesado','seguimiento','propuesta','inicia_registro','no_interesado') then
   68            raise exception 'Resultado comercial inválido' using errcode='22023'; end if;
   69        elsif v_resultado is not null or v_resultado_reunion is not null then
   70          raise exception 'Esta tarea solo registra detalle' using errcode='22023';
```

### supabase/migrations/20261005224214_crm_resultados_cliente_postventa.sql (líneas 105–120)
```
  105      $despues$      resultado_reunion=case when tipo='reunion' and v_estado='completada'
  106          then coalesce(v_resultado_reunion,'sin_clasificar') end,$despues$);
  107  
  108    v_nuevo := replace(v_nuevo,
  109      $antes$      coalesce(v_detalle,'Reunión confirmada'),jsonb_build_object('estado',v_t.estado,'siguiente_id',v_sig.id),auth.uid());$antes$,
  110      $despues$      case when v_etiqueta is null then coalesce(v_detalle,'Reunión confirmada')
  111          else v_etiqueta||' · '||v_detalle end,
  112        jsonb_build_object('estado',v_t.estado,'siguiente_id',v_sig.id,
  113          'resultado',v_resultado,'resultado_reunion',v_resultado_reunion,
  114          'tipo_tarea',v_t.tipo,'responsable_tarea_id',v_t.vendedor_id,
  115          'resultado_origen',case when p_accion='cerrar' and v_estado='completada'
  116            and v_t.tipo in ('llamada','whatsapp','reunion')
  117            and coalesce(v_resultado,v_resultado_reunion) is null then 'legacy_sin_resultado'
  118            else 'declarado' end),auth.uid());$despues$);
  119  
  120    if v_nuevo = v_anterior
```

### supabase/migrations/20260803164348_crm_offboarding_gate_activos.sql (líneas 38–78)
```
   38  create or replace function private.vendedor_ids_visibles(p_perfil_id uuid)
   39  returns setof uuid
   40  language plpgsql
   41  stable
   42  security definer
   43  set search_path = ''
   44  as $$
   45  declare
   46    v_rol text;
   47  begin
   48    if p_perfil_id is distinct from (select auth.uid())
   49       and not private.es_lector_global() then
   50      return; -- defensa en profundidad: no enumerar equipos ajenos
   51    end if;
   52  
   53    v_rol := private.rol_crm(p_perfil_id);
   54  
   55    if v_rol is null then
   56      return;
   57    elsif v_rol = 'gerencia' then
   58      return query select e.perfil_id from crm.equipo e; -- incluye históricos
   59    elsif v_rol = 'supervisor' then
   60      return query
   61        with recursive subarbol as (
   62          select e.perfil_id
   63          from crm.equipo e
   64          where e.perfil_id = p_perfil_id
   65          union -- corta ciclos accidentales A↔B
   66          select e.perfil_id
   67          from crm.equipo e
   68          join subarbol s on e.supervisor_id = s.perfil_id
   69        )
   70        select s.perfil_id from subarbol s;
   71    elsif v_rol = 'vendedor' then
   72      return next p_perfil_id;
   73    else
   74      return; -- coordinador/rol futuro: deny-by-default
   75    end if;
   76  end;
   77  $$;
   78  
```

### supabase/migrations/20260910150039_crm_f6_postventa_persona.sql (líneas 83–99)
```
   83  create function crm.postventa_estado_fn() returns jsonb
   84  language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
   85  declare v_rol text; v_on boolean;
   86  begin
   87    v_rol:=private.rol_crm(auth.uid());
   88    if auth.uid() is null or not private.puede_acceder_crm() then
   89      raise exception 'No autorizado' using errcode='42501';
   90    end if;
   91    v_on:=private.postventa_modo();
   92    v_rol:=private.rol_crm(auth.uid());
   93    v_on:=v_on and coalesce(v_rol in ('vendedor','supervisor','gerencia'),false)
   94      and not private.es_lector_global();
   95    if v_on then v_on:=(crm.cartera_inversionistas_estado_fn()->>'habilitada')::boolean; end if;
   96    return jsonb_build_object('version',1,'habilitada',v_on);
   97  end;
   98  $$;
   99  
```

### supabase/migrations/20260910150039_crm_f6_postventa_persona.sql (líneas 117–147)
```
  117  create function private.postventa_visible(p_persona uuid) returns boolean
  118  language sql stable security definer set search_path='' as $$
  119    select private.postventa_visible_actor(p_persona,auth.uid());
  120  $$;
  121  create policy tareas_postventa_lectura on crm.tareas as restrictive for select to authenticated
  122    using(inversionista_id is null or private.postventa_visible(inversionista_id));
  123  create policy tareas_postventa_insert on crm.tareas as restrictive for insert to authenticated
  124    with check(inversionista_id is null);
  125  create policy tareas_postventa_update on crm.tareas as restrictive for update to authenticated
  126    using(inversionista_id is null) with check(inversionista_id is null);
  127  
  128  create function private.postventa_persona(p_persona uuid,p_contacto boolean default false) returns crm.inversionistas
  129  language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
  130  declare v_id uuid; v_i crm.inversionistas%rowtype; v_docs text[]; v_ahora text[];
  131  begin
  132    if auth.uid() is null or private.rol_crm(auth.uid()) is null
  133      or private.rol_crm(auth.uid()) not in ('vendedor','supervisor','gerencia') then
  134      raise exception 'No autorizado' using errcode='42501'; end if;
  135    if not private.postventa_modo() then
  136      raise exception 'La postventa por persona todavía no está habilitada' using errcode='P0409'; end if;
  137    perform private.cartera_f5_exigir();
  138    perform pg_advisory_xact_lock_shared(hashtextextended('crm.equipo.usuarios_jerarquia',0));
  139    v_id:=private.inversionista_canonica(p_persona);
  140    v_docs:=private.identidad_bloquear_documentos_de(array[v_id]);
  141    select * into v_i from crm.inversionistas where id=v_id for update;
  142    if not found or not private.postventa_visible(v_id) then
  143      raise exception 'Persona no encontrada o fuera de tu ámbito' using errcode='42501'; end if;
  144    if private.inversionista_canonica(p_persona) is distinct from v_id then
  145      raise exception 'La identidad cambió; vuelve a cargar la ficha' using errcode='40001'; end if;
  146    select coalesce(array_agg(k order by k),'{}') into v_ahora
  147      from (select distinct tipo_documento||':'||documento_normalizado k
```

### app/src/lib/gestion-diaria-analista.ts (líneas 30–80)
```
   30  export const UmbralesSchema = v.object({
   31    version: v.literal(1),
   32    /** Versión de política; distinta de la versión estable del contrato JSON. */
   33    politica_version: v.optional(v.pipe(v.number(), v.integer(), v.minValue(1))),
   34    bien_min_pct: v.number(),
   35    atencion_min_pct: v.number(),
   36    minimo_llamadas_utiles: v.number(),
   37  })
   38  
   39  export const MarcadorSchema = v.object({
   40    llamadas: v.number(),
   41    contestadas: v.number(),
   42    utiles: v.number(),
   43    /** null cuando no hubo llamadas útiles: «—», nunca 0 %. */
   44    tasa_contacto_pct: v.nullable(v.number()),
   45    /** null por debajo del mínimo de llamadas útiles: sin chip (decisión #7). */
   46    nivel: v.nullable(v.picklist(['bien', 'atencion', 'bajo'])),
   47    leads_tocados: v.number(),
   48    citas_agendadas: v.number(),
   49    primera_llamada_en: v.nullable(v.string()),
   50    ultima_llamada_en: v.nullable(v.string()),
   51    por_resultado: v.record(v.string(), v.number()),
   52    por_hora: v.array(v.object({ hora: v.number(), llamadas: v.number(), contestadas: v.number() })),
   53  })
   54  export type Marcador = v.InferOutput<typeof MarcadorSchema>
   55  
   56  export const CompromisoSchema = v.object({
   57    tarea_id: v.string(),
   58    lead_id: v.string(),
   59    lead_nombre: v.string(),
   60    lead_etapa: v.string(),
   61    tipo: v.picklist(['llamada', 'reunion']),
   62    titulo: v.string(),
   63    vence_en: v.string(),
   64    modalidad_reunion: v.nullable(v.string()),
   65  })
   66  export type Compromiso = v.InferOutput<typeof CompromisoSchema>
   67  
   68  export const SenalCarteraSchema = v.object({
   69    lead_id: v.string(),
   70    nombre_completo: v.string(),
   71    etapa: v.string(),
   72    tenencia_desde: v.nullable(v.string()),
   73    ciclo_desde: v.nullable(v.string()),
   74    llamadas_ciclo: v.number(),
   75    intentos_sin_respuesta: v.number(),
   76    ultima_llamada_en: v.nullable(v.string()),
   77    ultima_llamada_tipo: v.nullable(v.string()),
   78    ultima_llamada_resultado: v.nullable(v.string()),
   79    ultima_conversacion_en: v.nullable(v.string()),
   80    dias_sin_conversacion: v.number(),
```

### app/src/lib/gestion-diaria-equipo.ts (líneas 150–170)
```
  150    if (minutos === 0) return 'Menos de 1 min'
  151    return minutos < 60 ? `${minutos} min` : `${Math.floor(minutos / 60)} h ${minutos % 60} min`
  152  }
  153  
  154  /** No pintar barras a cero si llegó un desglose parcial o inconsistente. */
  155  export function horarioConfirmado(marcador: Marcador): boolean {
  156    const horas = marcador.por_hora
  157    const contestadasPorHora = horas.reduce((total, h) => total + h.contestadas, 0)
  158    return new Set(horas.map((h) => h.hora)).size === horas.length
  159      && horas.every((h) => Number.isInteger(h.hora) && h.hora >= 0 && h.hora <= 23
  160        && Number.isInteger(h.llamadas) && h.llamadas >= 0
  161        && Number.isInteger(h.contestadas) && h.contestadas >= 0 && h.contestadas <= h.llamadas)
  162      && horas.reduce((total, h) => total + h.llamadas, 0) === marcador.llamadas
  163      // gestion_diaria_llamadas cuenta por hora todas las llamada_realizada;
  164      // el total para la tasa excluye numero_errado/no_es_la_persona. Admitir
  165      // esa diferencia histórica sólo dentro del número de llamadas no útiles.
  166      && contestadasPorHora >= marcador.contestadas
  167      && contestadasPorHora - marcador.contestadas <= marcador.llamadas - marcador.utiles
  168  }
  169  
  170  /**
```

### app/src/screens/gestion-diaria/analista.tsx (líneas 1080–1094)
```
 1080        <div className="space-y-2">
 1081          <BarrasPorHora porHora={m.por_hora} titulo="Llamadas por hora" alto={130}
 1082            apoyo={m.ultima_llamada_en !== null ? `Primera ${horaLimaDe(m.primera_llamada_en)} · última ${horaLimaDe(m.ultima_llamada_en)}` : undefined} />
 1083          <p className="text-xs leading-relaxed text-[var(--muted-foreground-strong)]">
 1084            Tocaste {m.leads_tocados} {m.leads_tocados === 1 ? 'lead' : 'leads'}. Llamadas = marcadas + no contestadas; no incluye WhatsApp ni citas.
 1085            Un número errado no entra en el contacto, y el nivel se juzga desde {dia.umbrales.minimo_llamadas_utiles} llamadas útiles. Tu supervisor ve esto mismo de ti.
 1086          </p>
 1087        </div>
 1088        <Descartados dia={dia} deshaciendo={deshaciendo} onDeshacer={onDeshacer} onAbrirFicha={onAbrirFicha} tituloRef={tituloDescartesRef} />
 1089        {analistaId !== null && (
 1090          // Versión compacta del registro compartido: supervisor y gerencia
 1091          // conservan la suya hasta sus propios planes.
 1092          <RegistroActividad dia={hoy} analistaIds={[analistaId]} mostrarAnalista={false} permitirExportar={false} compacto />
 1093        )}
 1094      </div>
```

### pg_policies en producción (crm.inversionista_gestiones y crm.tareas, SELECT/ALL)
```
tareas | crm_actor_activo_gate | ALL | {authenticated} | ( SELECT private.puede_acceder_crm() )
tareas | tareas_postventa_lectura | SELECT | {authenticated} | ((inversionista_id IS NULL) OR private.postventa_visible(inversionista_id))
tareas | tareas_select | SELECT | {authenticated} | (((activo = true) AND ((vendedor_id IN (SELECT private.vendedor_ids_visibles(auth.uid()))) OR ((vendedor_id IS NULL) AND (asignado_supervisor_id IN (SELECT private.vendedor_ids_visibles(auth.uid())))) OR (private.rol_crm(auth.uid()) = 'gerencia') OR ( SELECT private.es_… (truncado)
inversionista_gestiones | (sin policies SELECT)
```

## Reglas del proyecto que aplican
- Arquitectura en 4 capas: pantalla → puerta (`crm`) → núcleo (`private`) → tablas con RLS. `security definer` solo con
  justificación escrita, `set search_path=''`, nombres calificados y verificación explícita de rol/visibilidad dentro.
- Lección registrada: «Un envoltorio DEFINER se salta la RLS: el ayudante debe ser ESPEJO de la policy».
- Trinquete del censo analítico: ninguna función del día del analista puede tener `count(` ni `sum(1)` crudos.
- Cambiar una función sellada por huella = RE-SELLAR el gate en la misma migración; por cada defensa, un mutante.
- Migraciones: nunca editar una commiteada; una nueva `AAAAMMDDHHMMSS_crm_<tema>.sql`; sin policy DELETE; grants
  explícitos; `COMMENT ON`; reversa documentada.

## Protocolo global de revisión (transcrito)
# Protocolo global Codex ↔ Claude Code

Aplica al usuario de esta Mac, en cualquier proyecto, aunque no exista `.ai/`.
Las instrucciones del repositorio definen negocio, arquitectura y comandos;
este protocolo define los roles y el aislamiento de las consultas.

## Roles y autoridad

- PRIMARY: posee la tarea, inspecciona, decide, implementa, ejecuta checks,
  evalúa hallazgos y entrega el resultado. Es el único escritor.
- SECONDARY_REVIEWER: analiza evidencia, bugs, regresiones, seguridad,
  arquitectura, casos límite y pruebas faltantes. No escribe archivos, no
  implementa, no hace commits, no cambia configuración, no ejecuta acciones
  destructivas, no llama al otro agente y no delega ni inicia otro review.
- Una tarea normal del usuario define un PRIMARY. Un prompt que comienza con
  `ROLE: SECONDARY_REVIEWER` define un consultor, aunque existan instrucciones
  generales de autonomía. Si le piden otra opinión, devuelve su propio análisis.
- La única cadena permitida es PRIMARY → SECONDARY_REVIEWER → PRIMARY.
- El reviewer es asesor; el PRIMARY decide con evidencia. Un PASS de IA no
  significa que la tarea esté terminada.

## Cuándo consultar

- LEVEL 1: formato, documentación sencilla, CSS pequeño, rename o fix obvio:
  cero consultas.
- LEVEL 2: lógica relevante, integración, endpoint, componente importante o
  refactor moderado: normalmente una consulta si aporta valor independiente.
- LEVEL 3: auth, permisos, secretos, seguridad, schemas/migraciones, arquitectura,
  concurrencia, pagos, lógica financiera, APIs importantes o cambios destructivos:
  una consulta cuando sea razonablemente posible.
- Máximo habitual: dos consultas por tarea, contando reviewers especializados.
  La segunda necesita nueva evidencia, discrepancia importante o corrección de
  riesgo que justifique otra verificación. No repetir hasta conseguir un PASS.
- Las instrucciones explícitas del usuario sobre consultas prevalecen. No
  consultar para confirmar trivialidades ni abrir cadenas recursivas.

## Evidence-first y formato

**NO FINDING WITHOUT EVIDENCE.** Citar archivo/líneas, símbolo, diff, test,
error, log o reproducción. Identificar como hipótesis lo no demostrado.
Omitir secciones vacías y recomendaciones genéricas sin relación con la tarea.

```text
VERDICT:
PASS | CHANGES_REQUESTED | BLOCK

SUMMARY:
Conclusión técnica breve.

FINDINGS:
[P0 | P1 | P2 | P3] Título
File:
Lines:
Problem:
Evidence:
Impact:
Recommendation:

TEST GAPS:
- ...
ARCHITECTURE RISKS:
- ...
SECURITY RISKS:
- ...
REGRESSION RISKS:
- ...
RECOMMENDED NEXT ACTIONS:
1. ...
CONFIDENCE:
HIGH | MEDIUM | LOW
```

PASS: sin hallazgos obligatorios en lo revisado. CHANGES_REQUESTED: correcciones
accionables. BLOCK: riesgo crítico o evidencia insuficiente para revisar.
Resolver desacuerdos por requisitos, comportamiento, pruebas y documentación
oficial, no mediante consultas repetitivas.

## Interfaces

Codex PRIMARY usa `~/.local/bin/claude-review`, o el wrapper del repo cuando
sus instrucciones lo requieran. Adjunta código/diff saneado, rutas/líneas,
requisitos y resultados de checks. No enviar secretos. CodeGraph se usa por
el PRIMARY si el proyecto está indexado, nunca se indexa automáticamente.

El wrapper global incorpora este protocolo y, si existe, el protocolo `.ai/`
del proyecto. Claude reviewer tiene todas las herramientas, MCP, hooks y
personalizaciones deshabilitadas; no persiste la sesión. Cinco turnos por
defecto, máximo ocho. Exit 0 indica entrega válida, no necesariamente PASS.
Usa `dontAsk`, sin solicitudes de permiso, y comprueba que el evento de inicio
declare cero herramientas y cero MCP antes de aceptar un resultado único.
Las menciones genéricas a herramientas en el texto del modelo no acreditan
disponibilidad: la comprobación debe usar el inventario efectivo de la CLI.

Claude PRIMARY usa `mcp__codex__codex` con:

```text
sandbox: read-only
approval-policy: never
prompt:
ROLE: SECONDARY_REVIEWER.
Claude is the PRIMARY agent.
Do not modify files.
Do not implement the task.
Do not invoke Claude.
Do not delegate to another coding agent.
Do not create another review chain.
```

Adjuntar el contenido de este protocolo, las reglas relevantes del proyecto y
la evidencia: el reviewer no tiene herramientas para abrirlos. Solo se permite
añadir `model`; no `cwd`, `config` ni overrides de instrucciones. `codex-reply`
está bloqueado; una segunda consulta justificada inicia otro review seguro.

El MCP global usa `~/.local/bin/codex-review-mcp`. Trabaja en una carpeta neutral
de esta instalación para no cargar configuración específica de otros proyectos.
Deshabilita shell, subagentes, apps, hooks, navegador, plugins y cada MCP heredado.
Las tablas vacías TOML se fusionan: no sirven para eliminar los MCP del usuario.
Una entrada MCP local/de proyecto puede tener precedencia; comprobar su
aislamiento antes de usarla. No sustituir una interfaz protegida por una directa.

## Verificación, simultaneidad y límites

Aplicar `~/.config/ai-collaboration/VERIFICATION.md` y los gates concretos del repo.
Dos PRIMARY simultáneos en tareas distintas requieren working trees separados.
No crear worktrees automáticamente; un reviewer read-only no necesita uno.

Los hooks globales de Claude protegen secretos y operaciones peligrosas comunes;
los hooks no analizan los efectos indirectos de scripts arbitrarios. Las reglas
nativas ocultan `.env.*` también en búsquedas; incluyen `.env.example`, que se
gestiona manualmente. El usuario conserva sus modelos, plugins y ajustes normales.

El inventario del MCP se fija al arrancar. No cambiar MCP/plugins/configuración
de agentes durante el review. Tras cambiarlos, reconectar `codex` y ejecutar
`~/.local/bin/codex-review-mcp --check` antes de la siguiente consulta. No se
afirma aislamiento frente a cambios concurrentes de terceros.
