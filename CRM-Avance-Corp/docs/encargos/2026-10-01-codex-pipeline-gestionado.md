ROLE: SECONDARY_REVIEWER.
Do not modify files. Do not implement the task. Do not invoke Claude. Do not delegate to another coding agent. Do not create another review chain.
Follow .ai/REVIEW_PROTOCOL.md.

# Encargo de revisión — Pipeline · columna «Gestionado» (LEVEL 3: migración de una puerta expuesta del esquema `crm`)

Eres el revisor secundario. Sin base de datos ni red: todo está transcrito abajo. Responde con VERDICT (PASS / CHANGES_REQUESTED / BLOCK), SUMMARY, FINDINGS P0–P3 con evidencia (archivo/línea/fragmento), riesgos y test gaps, NEXT ACTIONS y CONFIDENCE. Sin hallazgo sin evidencia; distingue hipótesis. Tu tarea: REFUTAR, no confirmar. El protocolo completo va al final.

## Qué se pide (negocio)
Los analistas del CRM pidieron en el Pipeline (kanban de leads) una columna más, «Gestionado», entre «Nuevo» y «Contactado»: leads que YA se intentaron contactar (llamada sin respuesta, WhatsApp enviado) pero cuyo cliente aún no respondió. Decisiones del dueño (Miguel, 01/10/2026):
- No se crea una etapa guardada: el lead sigue con `etapa = 'nuevo'`; la columna se CALCULA. (La lista de etapas está cableada en decenas de piezas: plazos, cola del día, embudo, avance automático.)
- Un lead REASIGNADO que el analista anterior ya intentó es «Nuevo» para el analista actual: solo cuenta lo gestionado desde que el titular ACTUAL lo recibió.
- El lead pasa a «Gestionado» solo, al registrar el intento; no se arrastra hacia ahí. Alcance: solo el Pipeline.

Decisión del PRIMARY tras el primer ensayo: un resultado de llamada DESHECHO (`metadata ? 'deshecho_en'`) no cuenta como gestión, igual que en los núcleos de Gestión Diaria.

## Diseño a refutar
1. Un parámetro opcional nuevo en la puerta existente `crm.cartera_filtrada_fn` (SECURITY INVOKER, expuesta por PostgREST): `p_gestion text default null`, valores `'con_gestion'` | `'sin_gestion'`, otro valor ⇒ 22023. Firma única: `drop` de la de 12 argumentos + `create` de la de 13 (dos candidatas romperían PostgREST). Mismo patrón con el que entraron `p_origen`, `p_procedencia` y `p_reasignados`.
2. Regla «gestión vigente»: `vendedor_id is not null and tenencia_desde is not null and exists(actividad de contacto del lead con creado_en >= tenencia_desde y no deshecha)`. Cuenta la FECHA, no el autor. `tenencia_desde` la sella el trigger `trg_leads_zzz_tenencia_desde` (se renueva al reasignar y al reabrir un descartado).
3. El predicado va en el `where` de la CTE `base` (materializada), como `(p_gestion is null or (…) = (p_gestion = 'con_gestion'))`: recorta la misma base de la que salen filas, totales, capital y embudo.
4. La forma del payload NO cambia (sin eco del filtro, sin campos nuevos por fila): hay navegadores con el bundle viejo leyendo la respuesta. `ultimo_contacto_en` y `sin_tocar` se dejan como están (no excluyen lo deshecho ni miran la tenencia).
5. Migración con preflight/postflight: identidad de la función viva por md5 (con `set local search_path = ''` para que el ancla no dependa de la sesión), identidad del trigger de tenencia, traslado de la exención analítica y resellado, md5 de la función nueva fijado en el postflight. Reversa generada desde `pg_get_functiondef` del banco.
6. Frente: cinco listas servidas (una por columna); «Nuevo» pide `{p_etapa:'nuevo', p_gestion:'sin_gestion'}` y «Gestionado» `{p_etapa:'nuevo', p_gestion:'con_gestion'}`. En modo demo la misma regla se calcula en el navegador con una función pura. Orden de publicación: servidor primero, pantalla después.

## Preguntas concretas
a. ¿Hay algún caso (lógica de tres valores, NULL, tipos) en que un lead `nuevo` caiga en NINGUNA mitad, en las dos, o en la equivocada? ¿La partición con/sin es exacta en TODAS las cifras que salen de `base`?
b. La lectura de `crm.actividades` es INVOKER bajo RLS: ¿puede la policy de actividades dar a dos lectores un veredicto distinto sobre el MISMO lead visible, o filtrar información entre roles (por ejemplo por diferencia de conteos entre mitades)?
c. ¿Puede alguien falsificar una «gestión» o borrarla (insertar una actividad en un lead ajeno, fecharla a mano, escribir o quitar `deshecho_en`) para mover leads de mitad? Mira `actividades_insert` y la puerta de deshacer.
d. Compatibilidad: bundle viejo contra servidor nuevo (llama por nombre sin `p_gestion`) y bundle nuevo contra servidor viejo (PGRST202). ¿El `drop` + `create` en una transacción, con `notify pgrst` al final, deja alguna ventana rota para quien esté llamando? ¿Alguna otra pieza del servidor depende de la firma de 12?
e. Preflight/postflight: ¿falsos verdes? (`is not true`, `to_regprocedure` con `search_path` vacío, tabla temporal creada sin calificar bajo `search_path = ''` y leída como `pg_temp.…`, comparación de `proacl` como jsonb, el md5 de la función nueva fijado antes de existir en producción). ¿Las guardas QUITADAS respecto de la migración de reasignados dejan sin vigilar algo de lo que este filtro depende?
f. Reversa y `registrar.sql`: ¿pueden pisar una corrección posterior, dejar la lista sin sellar o registrar algo distinto de lo ensayado?
g. Semántica de negocio: ¿la regla contradice alguna otra del sistema que veas en lo transcrito (avance automático de etapa, Gestión Diaria, reapertura)? Casos borde: actividad en el instante exacto de la tenencia, reasignación en lote, lead devuelto a `nuevo` desde `contactado`, lead sin titular en la bandeja del supervisor.
h. Rendimiento a escala de producción (hoy: 464 leads activos en `nuevo`, 8.307 actividades de contacto en total): ¿algún plan patológico por el `exists` dentro de una CTE materializada, o por el `= (p_gestion = 'con_gestion')` que impide usarlo como semi-join?
i. Paridad de la regla entre el SQL, el espejo demo (`pipeline-columnas.ts`) y el doble e2e (`_helpers.ts`). OJO: el espejo y el doble transcritos abajo TODAVÍA no excluyen lo deshecho; ese delta del frente está en curso. Dime qué otras divergencias ves.
j. ¿Falta alguna prueba que cazaría un defecto real? ¿Alguna aserción del oráculo es tautológica?

## Evidencia de ejecución (banco Docker propio con el esquema de producción de HOY, sin datos; paridad de huellas banco = producción medida hoy: `crm` 285 funciones `44fc3d1a…`, `private` 546 funciones `2188a8f4…`)
- Ensayo completo (`supabase/scripts/cartera-gestion/ensayar.mjs`): 54 pasos PASS, aplicando como rol `postgres` en un solo mensaje.
- Igualdad: función nueva con `p_gestion` nulo = función vieja en 256/256 respuestas (8 actores × 16 llamadas × 2 formas: omitido y `null` explícito; 5.936 filas), y `resumen_cartera_fn` 8/8 antes = después en la misma sesión.
- Oráculo de negocio (transcrito abajo): 120/120. Incluye la cadena REAL de triggers (entrega → intento → reasignación → intento → descarte → reapertura) y la puerta real de deshacer (`crm.registrar_llamada_v4` → «Gestionado»; `crm.deshacer_resultado_llamada` → vuelve a «Nuevo»).
- Con volumen (5.000 leads, 31.588 actividades, 1.427 contactos deshechos): la llamada del Pipeline recorrida entera por cursor como gerencia, directorio, supervisor, analista y coordinador: 5.302 filas contra un oráculo independiente, 0 de más, 0 de menos, 0 repetidas, 0 en las dos mitades.
- Validación: `'gestionado'`, `''`, `'CON_GESTION'`, `'con_gestion '` ⇒ 22023. Los 12 argumentos de siempre, por nombre y por posición, siguen respondiendo igual.
- Alcance por rol bajo RLS (`set local role authenticated` + los dos claims): analista solo lo suyo; supervisor su equipo y su bandeja; gerencia y directorio todo; revocado, solo-portal y sin sesión ⇒ 42501. `anon` y `service_role` sin EXECUTE (leído del catálogo).
- Rendimiento: el `exists` usa `actividades_contacto_episodio_idx` (Index Scan con `lead_id = l.id AND creado_en >= l.tenencia_desde` + filtro `NOT (metadata ? 'deshecho_en')`); sin recorrido secuencial. Analista ~7 ms con y sin filtro; gerencia ~51 ms sin filtro y ~32 ms con filtro. Diferencia nueva-sin-filtro contra vieja: ruido (±0,3 ms analista).
- Reversa: aplicar → revertir devuelve exactamente el md5 vivo `7169d94239dcb191bafa3faed46f916f` y el sello vigente; repetida, se niega.
- Mutantes: 16 de lógica (ancla quitada, invertida, `>` por `>=`, medir desde el alta, la nota cuenta, lo deshecho cuenta, autor = titular, sin titular, mitades cambiadas, sin validar dominio, recorta con nulo, eco añadido…), 9 de preflight y 5 de postflight: todos cazados. Un equivalente declarado: quitar `l.tenencia_desde is not null` (el `>= NULL` ya da sin gestión).
- `acreditar.sql` (solo lectura, un `DO` que termina siempre en `raise`) corrido contra PRODUCCIÓN por el PRIMARY: estado ANTES; función viva, contrato de seguridad, declaración analítica, sello, `assert_actividades_de_lead_base` y trigger de tenencia en [OK]: «la migración pasaría su preflight». El gate analítico de producción está en ROJO por un contador AJENO sin declarar (`private.gestion_diaria_cola_hechos(uuid,timestamp with time zone)`); el ensayo probó que la migración instala conservando ese rojo tal cual.
- Realidad de producción hoy (conteo agregado): 464 leads activos en `nuevo`; con la regla, 311 «Gestionado» y 153 «Nuevo»; de esos «Nuevo», 38 sin titular y 6 con contactos anteriores a la tenencia actual; 0 con titular y sin `tenencia_desde`; 11 contactos deshechos de 8.307 y 0 leads afectados por ello; 0 leads que serían «Gestionado» solo por una actividad de otra persona.
- Frente: `npm run check` PASS (331 archivos, 5.270 pruebas); E2E en Docker 302 pasan, 26 omitidas, 2 fallan y son previas (fechas fijas tras el cambio de mes; fallan igual en la base).
- NOT RUN: `npm run test:rls:preflight` (exige credenciales) y la matriz nueva de `test-rls.mjs`; advisors (son de la nube).

## Contexto vivo de producción (transcrito del volcado de esquema de hoy, 01/10/2026)

### crm.cartera_filtrada_fn VIVA (12 argumentos; md5 de pg_get_functiondef con search_path vacío = 7169d94239dcb191bafa3faed46f916f)
```sql
CREATE OR REPLACE FUNCTION "crm"."cartera_filtrada_fn"("p_limite" integer DEFAULT 50, "p_antes_de" timestamp with time zone DEFAULT NULL::timestamp with time zone, "p_antes_id" "uuid" DEFAULT NULL::"uuid", "p_etapa" "text" DEFAULT NULL::"text", "p_vendedor_id" "uuid" DEFAULT NULL::"uuid", "p_sin_asignar" boolean DEFAULT false, "p_texto" "text" DEFAULT NULL::"text", "p_desde" "date" DEFAULT NULL::"date", "p_hasta" "date" DEFAULT NULL::"date", "p_origen" "text" DEFAULT NULL::"text", "p_procedencia" "text" DEFAULT NULL::"text", "p_reasignados" boolean DEFAULT false) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE
    SET "search_path" TO ''
    AS $$
declare
  v_uid uuid := (select auth.uid());
  v_global boolean;
  v_visibles uuid[];
  v_texto text := nullif(btrim(p_texto), '');
  v_reparto boolean;
  v_digitos text;
  v_salida jsonb;
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
     or (v_texto is not null and length(v_texto) < 2) then
    raise exception 'Filtros de cartera inválidos' using errcode = '22023';
  end if;
  v_texto := left(v_texto, 80);
  v_digitos := left(regexp_replace(v_texto, '\D', '', 'g'), 15);
  v_global := private.rol_crm(v_uid) = 'gerencia' or private.es_lector_global();
  v_visibles := array(select private.vendedor_ids_visibles(v_uid));
  v_reparto := private.cartera_puede_operar_reparto_fn();

  with recepciones as materialized (
    select * from private.cartera_recepciones_fn(p_desde,p_hasta)
  ), base as materialized (
    select l.id, l.nombre_completo, l.telefono, l.telefono_alternativo,
      l.telefono_alternativo_crudo, l.correo, l.dni, l.genero,
      l.fecha_nacimiento, l.distrito, l.origen, l.etapa, l.motivo_descarte,
      l.monto_estimado, l.moneda, l.categoria_interes, l.vendedor_id,
      l.asignado_supervisor_id, l.creado_en, l.tenencia_desde, l.convertido_en,
      l.contrato_id, l.actualizado_en, l.activo, l.nota, l.no_contactar,
      -- Procedencia sellada por el servidor: `alta_manual` (columna del 01/09)
      -- o, para los leads anteriores a ella, tener autor. El puente inserta
      -- como service_role sin autor: nunca cae en 'manual'.
      case when l.alta_manual or l.creado_por is not null then 'manual' else 'sistema' end as procedencia,
      l.creado_por as cargado_por,
      coalesce(mov.reasignado, false) as reasignado,
      r.recibido_en, coalesce(r.aproximado,false) as recepcion_aproximada
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
      -- La procedencia acota esa misma base, con la misma regla que la columna
      -- `procedencia` de arriba.
      and (p_procedencia is null or (l.alta_manual or l.creado_por is not null) = (p_procedencia = 'manual'))
      and (not coalesce(p_reasignados,false) or coalesce(mov.reasignado,false))
      and (p_vendedor_id is null or l.vendedor_id = p_vendedor_id)
      and (not coalesce(p_sin_asignar,false) or l.vendedor_id is null)
      and (v_texto is null or strpos(lower(l.nombre_completo),lower(v_texto)) > 0
        or (length(v_digitos) >= 3 and (strpos(l.telefono,v_digitos) > 0
          or strpos(l.telefono_alternativo,v_digitos) > 0 or strpos(l.dni,v_digitos) > 0)))
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
    'reasignados',coalesce(p_reasignados,false),
    'items',coalesce((select jsonb_agg(to_jsonb(f) order by f.actualizado_en desc,f.id) from filas f),'[]'::jsonb),
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
          ('propuesta_enviada',4),('convertido',5),('descartado',6)) e(etapa,ord))))
  into v_salida;
  return v_salida;
end;
$$;
```

### private.trg_leads_tenencia_desde (sella crm.leads.tenencia_desde)
```sql
CREATE OR REPLACE FUNCTION "private"."trg_leads_tenencia_desde"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
  v_new_debe boolean;
  v_old_debe boolean;
begin
  v_new_debe := new.activo = true
    and new.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
    and new.vendedor_id is not null;

  if tg_op = 'INSERT' then
    new.tenencia_desde := case when v_new_debe then new.creado_en else null end;
    return new;
  end if;

  v_old_debe := old.activo = true
    and old.etapa in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada')
    and old.vendedor_id is not null;

  if not v_new_debe then
    new.tenencia_desde := null;
  elsif not v_old_debe then
    new.tenencia_desde := statement_timestamp();
  elsif new.vendedor_id is distinct from old.vendedor_id then
    new.tenencia_desde := statement_timestamp();
  elsif new.ciclo_actual is distinct from old.ciclo_actual then
    new.tenencia_desde := statement_timestamp();
  else
    new.tenencia_desde := old.tenencia_desde;
  end if;

  return new;
end;
$$;
```

### Trigger que la invoca
```sql
CREATE OR REPLACE TRIGGER "trg_leads_zzz_tenencia_desde" BEFORE INSERT OR UPDATE ON "crm"."leads" FOR EACH ROW EXECUTE FUNCTION "private"."trg_leads_tenencia_desde"();
```

### Policy leads_select
```sql
CREATE POLICY "leads_select" ON "crm"."leads" FOR SELECT TO "authenticated" USING ((("activo" = true) AND (("vendedor_id" IN ( SELECT "private"."vendedor_ids_visibles"(( SELECT "auth"."uid"() AS "uid")) AS "vendedor_ids_visibles")) OR (("vendedor_id" IS NULL) AND ("asignado_supervisor_id" IN ( SELECT "private"."vendedor_ids_visibles"(( SELECT "auth"."uid"() AS "uid")) AS "vendedor_ids_visibles"))) OR (( SELECT "private"."rol_crm"(( SELECT "auth"."uid"() AS "uid")) AS "rol_crm") = 'gerencia'::"text") OR ( SELECT "private"."es_lector_global"() AS "es_lector_global"))));
```

### Policy actividades_select
```sql
CREATE POLICY "actividades_select" ON "crm"."actividades" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "crm"."leads" "l"
  WHERE (("l"."id" = "actividades"."lead_id") AND ("l"."activo" = true) AND (("l"."vendedor_id" IN ( SELECT "private"."vendedor_ids_visibles"(( SELECT "auth"."uid"() AS "uid")) AS "vendedor_ids_visibles")) OR (("l"."vendedor_id" IS NULL) AND ("l"."asignado_supervisor_id" IN ( SELECT "private"."vendedor_ids_visibles"(( SELECT "auth"."uid"() AS "uid")) AS "vendedor_ids_visibles"))) OR (( SELECT "private"."rol_crm"(( SELECT "auth"."uid"() AS "uid")) AS "rol_crm") = 'gerencia'::"text") OR ( SELECT "private"."es_lector_global"() AS "es_lector_global"))))));
```

### Policy actividades_insert
```sql
CREATE POLICY "actividades_insert" ON "crm"."actividades" FOR INSERT TO "authenticated" WITH CHECK ((("creado_por" = ( SELECT "auth"."uid"() AS "uid")) AND ("tipo" <> ALL (ARRAY['cambio_etapa'::"text", 'reasignacion'::"text", 'conversion'::"text"])) AND (EXISTS ( SELECT 1
   FROM "crm"."leads" "l"
  WHERE (("l"."id" = "actividades"."lead_id") AND ("l"."activo" = true) AND (("private"."rol_crm"(( SELECT "auth"."uid"() AS "uid")) = 'gerencia'::"text") OR ("l"."vendedor_id" = ( SELECT "auth"."uid"() AS "uid")) OR (("private"."rol_crm"(( SELECT "auth"."uid"() AS "uid")) = 'supervisor'::"text") AND (("l"."vendedor_id" IN ( SELECT "private"."vendedor_ids_visibles"(( SELECT "auth"."uid"() AS "uid")) AS "vendedor_ids_visibles")) OR (("l"."vendedor_id" IS NULL) AND ("l"."asignado_supervisor_id" IN ( SELECT "private"."vendedor_ids_visibles"(( SELECT "auth"."uid"() AS "uid")) AS "vendedor_ids_visibles")))))))))));
```

### Policies restrictivas crm_actor_activo_gate (actividades y leads)
```sql
CREATE POLICY "crm_actor_activo_gate" ON "crm"."actividades" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."puede_acceder_crm"() AS "puede_acceder_crm")) WITH CHECK (( SELECT "private"."puede_acceder_crm"() AS "puede_acceder_crm"));
CREATE POLICY "crm_actor_activo_gate" ON "crm"."leads" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."puede_acceder_crm"() AS "puede_acceder_crm")) WITH CHECK (( SELECT "private"."puede_acceder_crm"() AS "puede_acceder_crm"));
```

### private.assert_actividades_de_lead_base
```sql
CREATE OR REPLACE FUNCTION "private"."assert_actividades_de_lead_base"() RETURNS "text"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_huella text;
  v_nombres text[];
begin
  if to_regprocedure('private.puede_acceder_crm()') is null
     or to_regprocedure('private.rol_crm(uuid)') is null
     or to_regprocedure('private.vendedor_ids_visibles(uuid)') is null
     or to_regprocedure('private.es_lector_global()') is null then
    raise exception 'Faltan los ayudantes de autoridad del CRM';
  end if;
  -- La cadena puerta (invoker) → núcleo (private) corre como el actor.
  if not has_schema_privilege('authenticated', 'private', 'USAGE') then
    raise exception 'authenticated no tiene USAGE sobre private: la cadena invoker no funcionaria';
  end if;
  if not has_column_privilege('authenticated', 'crm.leads', 'id', 'SELECT') then
    raise exception 'authenticated no puede leer crm.leads.id: la denegacion explicita no funcionaria';
  end if;
  if not has_table_privilege('authenticated', 'crm.actividades', 'SELECT') then
    raise exception 'authenticated no puede leer crm.actividades: el nucleo no devolveria nada';
  end if;

  -- Las dos policies co-extensivas, tal cual se auditaron el 19/09/2026.
  select md5(pg_get_expr(pol.polqual, pol.polrelid)) into v_huella
  from pg_policy pol
  where pol.polrelid = 'crm.actividades'::regclass and pol.polname = 'actividades_select';
  if v_huella is distinct from 'e80e3af900b8d9616c28dcd836f1ac94' then
    raise exception 'actividades_select cambio desde la auditoria (md5 %): re-auditar',
      coalesce(v_huella, 'ausente');
  end if;
  select md5(pg_get_expr(pol.polqual, pol.polrelid)) into v_huella
  from pg_policy pol
  where pol.polrelid = 'crm.leads'::regclass and pol.polname = 'leads_select';
  if v_huella is distinct from '073deaeb5700bac14209ec795b71567e' then
    raise exception 'leads_select cambio desde la auditoria (md5 %): re-auditar',
      coalesce(v_huella, 'ausente');
  end if;

  -- El CONJUNTO de permisivas de lectura: exactamente una por tabla, solo para
  -- authenticated, y la restrictiva del actor activo presente en ambas.
  select array_agg(pol.polname::text order by pol.polname) into v_nombres
  from pg_policy pol
  where pol.polrelid = 'crm.leads'::regclass and pol.polpermissive and pol.polcmd in ('r', '*');
  if v_nombres is distinct from array['leads_select']::text[] then
    raise exception 'crm.leads tiene otras permisivas de lectura (%): la co-extensividad ya no esta garantizada',
      coalesce(array_to_string(v_nombres, ','), 'ninguna');
  end if;
  select array_agg(pol.polname::text order by pol.polname) into v_nombres
  from pg_policy pol
  where pol.polrelid = 'crm.actividades'::regclass and pol.polpermissive and pol.polcmd in ('r', '*');
  if v_nombres is distinct from array['actividades_select']::text[] then
    raise exception 'crm.actividades tiene otras permisivas de lectura (%): la co-extensividad ya no esta garantizada',
      coalesce(array_to_string(v_nombres, ','), 'ninguna');
  end if;
  if exists (
    select 1 from pg_policy pol
    where pol.polrelid in ('crm.leads'::regclass, 'crm.actividades'::regclass)
      and pol.polname in ('leads_select', 'actividades_select')
      and pol.polroles is distinct from array['authenticated'::regrole::oid]
  ) then
    raise exception 'leads_select/actividades_select ya no aplican solo a authenticated';
  end if;
  if not exists (
    select 1 from pg_policy pol
    where pol.polrelid = 'crm.leads'::regclass and pol.polname = 'crm_actor_activo_gate' and not pol.polpermissive
  ) or not exists (
    select 1 from pg_policy pol
    where pol.polrelid = 'crm.actividades'::regclass and pol.polname = 'crm_actor_activo_gate' and not pol.polpermissive
  ) then
    raise exception 'Falta la restrictiva crm_actor_activo_gate en crm.leads o crm.actividades';
  end if;
  return 'OK: policies selladas por huella y por conjunto, grants de la cadena invoker presentes';
end;
$$;
```

### private.trg_actividades_resultado_solo_nucleo (quién puede escribir resultados de llamada y deshecho_en)
```sql
                      'deshecho_en', 'deshecho_por', 'descarte_revertido', 'cita_no_restaurada']
      or v_meta->>'evento' in ('resultado_llamada', 'resultado_deshecho'))
     and coalesce(pg_catalog.current_setting('crm.op_resultado_llamada', true), 'off') <> 'on' then
    raise exception 'El resultado de una llamada solo lo escribe crm.registrar_llamada_v3 (y crm.deshacer_resultado_llamada)'
      using errcode = '42501';
  end if;
  -- Append-only incluso bajo el GUC: un resultado escrito no se reescribe (el
  -- deshacer AÑADE deshecho_en; nunca cambia resultado ni submotivo).
  if tg_op = 'UPDATE' and old.metadata ? 'resultado'
     and (new.metadata->>'resultado' is distinct from old.metadata->>'resultado'
          or new.metadata->>'submotivo' is distinct from old.metadata->>'submotivo') then
    raise exception 'El resultado de una llamada no se reescribe' using errcode = '42501';
  end if;
  return new;
end;
$$;
```

### Índices de crm.actividades
```sql
CREATE INDEX actividades_autor_fecha_idx ON crm.actividades USING btree (creado_por, creado_en DESC, id)
CREATE INDEX actividades_contacto_episodio_idx ON crm.actividades USING btree (lead_id, creado_por, creado_en) WHERE (tipo = ANY (ARRAY['llamada_realizada'::text, 'llamada_no_contestada'::text, 'whatsapp_enviado'::text, 'whatsapp_recibido'::text, 'reunion_realizada'::text]))
CREATE INDEX actividades_reasignacion_historial_idx ON crm.actividades USING btree (creado_en DESC, id DESC) WHERE (tipo = 'reasignacion'::text)
CREATE INDEX actividades_recientes_idx ON crm.actividades USING btree (creado_en DESC, id)
CREATE INDEX idx_actividades_lead ON crm.actividades USING btree (lead_id, creado_en DESC)
CREATE UNIQUE INDEX actividades_pkey ON crm.actividades USING btree (id)
```

De `crm.deshacer_resultado_llamada` (SECURITY DEFINER; solo el AUTOR, dentro de 24 h, sin «No insistir»): no borra la actividad; la marca con `update crm.actividades set metadata = metadata || jsonb_build_object('deshecho_en', v_ahora, 'deshecho_por', v_uid) where id = p_actividad_id` e inserta una `nota` con `evento = resultado_deshecho`.

## Archivos nuevos o modificados (copia de trabajo, sin commitear)

### supabase/migrations/20261001154153_crm_cartera_filtro_gestion.sql (completa)
```sql
-- Pipeline · columna «Gestionado»: filtro opcional `p_gestion` en `crm.cartera_filtrada_fn`
-- (pedido de los analistas; regla de negocio decidida por Miguel el 01/10/2026).
--
-- QUÉ. La función gana UN argumento al final, `p_gestion text default null`:
--   · null          → no recorta: la respuesta es idéntica a la de hoy;
--   · 'con_gestion' → leads cuyo titular ACTUAL ya intentó el contacto desde que los recibió
--                     (un resultado de llamada deshecho no cuenta);
--   · 'sin_gestion' → todos los demás (sin titular o sin `tenencia_desde` ⇒ sin gestión).
--   Cualquier otro valor → 22023, por el mismo bloque de validación que origen y procedencia.
--
-- POR QUÉ. El Pipeline separa, dentro de `etapa = 'nuevo'`, lo que ya se intentó contactar
-- (llamada sin respuesta, WhatsApp enviado) de lo que nadie ha tocado. NO nace una etapa
-- guardada: la columna se calcula. Regla de Miguel: un lead REASIGNADO que el analista anterior
-- ya intentó es «Nuevo» para el actual; solo cuenta lo gestionado desde `crm.leads.tenencia_desde`
-- (lo sella el trigger `trg_leads_zzz_tenencia_desde`; se renueva al reasignar y al reabrir).
-- Gestión = los 5 tipos de contacto de `actividades_contacto_episodio_idx`; una nota no cuenta.
-- Tampoco cuenta un resultado de llamada DESHECHO (`metadata.deshecho_en`): como en los núcleos
-- de Gestión Diaria, lo deshecho «no ocurrió» y el lead vuelve a «Nuevo» (decisión del 01/10).
--
-- QUÉ NO CAMBIA. La FORMA del payload (ni claves arriba ni campos por fila: hay navegadores con
-- el bundle viejo leyéndolo; el filtro no lleva eco), INVOKER bajo la RLS de leads y actividades,
-- `stable`, `search_path` vacío, dueño y ACL (solo `authenticated` ejecuta). Recorta la MISMA
-- base que los demás filtros: filas, totales, capital y embudo salen juntos. Una sola firma: se
-- retira la de 12 argumentos (dos candidatas romperían PostgREST) y su exención analítica se
-- MUEVE a la de 13 (misma clase y fecha de declaración) y se resella.
--
-- ORDEN DE PUBLICACIÓN: servidor primero, pantalla después. El frente nuevo envía `p_gestion`
-- y sin esta migración recibiría PGRST202; el frente viejo no lo envía y sigue igual.
--
-- REVERSA: `supabase/scripts/cartera-gestion/reversa.sql`, tras retirar el frente que envía
-- `p_gestion`. Quita la firma de 13, reinstala la de 12 byte a byte (md5 7169d942…), devuelve la
-- exención analítica a su firma y resella. No toca datos.
--
-- ANCLAS. Todas se midieron con `search_path` vacío, que se fija abajo para la transacción: el
-- texto de `pg_get_functiondef` y `pg_get_triggerdef` cambia con el `search_path` de la sesión,
-- y así el resultado no depende de quién aplique. Kit, ensayo y consulta de solo lectura para
-- acreditarlas contra producción: `supabase/scripts/cartera-gestion/`.
begin;
set local lock_timeout = '10s';
set local statement_timeout = '30s';
set local search_path = '';

lock table private.analitica_leads_citas_exenciones,
  private.analitica_lc_sello in share row exclusive mode;

do $preflight$
declare
  f12 constant text := 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean)';
  f13 constant text := 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)';
  f12_larga constant text := 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean)';
begin
  -- 1. La función viva es la auditada: una sola firma (la de 12) y su cuerpo exacto.
  --    Guardas en positivo con `is not true`: un NULL también rechaza.
  if (
    to_regprocedure(f13) is null
    and to_regprocedure(f12) is not null
    and (select count(*) from pg_proc where proname = 'cartera_filtrada_fn'
           and pronamespace = 'crm'::regnamespace) = 1
    and md5(pg_get_functiondef(to_regprocedure(f12))) = '7169d94239dcb191bafa3faed46f916f'
  ) is not true then
    raise exception 'PREFLIGHT: cartera_filtrada_fn no coincide con la version auditada';
  end if;
  -- 2. Su declaración analítica está vigente (huella al día), es de inventario y la lista está
  --    sellada: esta migración la mueve y resella; no se resella a ciegas una lista alterada.
  if (
    exists (select 1 from private.contadores_crudos_leads_citas() c
             where c.objeto = f12_larga and c.declarada and c.huella_ok)
    and (select e.clase from private.analitica_leads_citas_exenciones e
          where e.objeto = f12_larga) = 'operativo'
    and (select s.sello from private.analitica_lc_sello s where s.id)
          = private.huella_exenciones_analitica_lc()
  ) is not true then
    raise exception 'PREFLIGHT: la declaracion analitica no esta vigente y sellada';
  end if;
  -- 3. El filtro lee `crm.actividades` como INVOKER: su RLS debe seguir siendo coextensiva con
  --    la de leads (si no, un lead visible con actividades ocultas saldría «sin gestión»).
  perform private.assert_actividades_de_lead_base();
  -- 4. El reloj de la regla. «Solo cuenta lo gestionado desde que el titular ACTUAL recibió el
  --    lead» descansa en que `tenencia_desde` lo sella el servidor y se renueva al reasignar.
  --    Si el trigger falta, está apagado o cambió de cuerpo, el filtro mentiría en silencio.
  if (
    (select count(*) from pg_trigger t
      where t.tgrelid = 'crm.leads'::regclass
        and t.tgname = 'trg_leads_zzz_tenencia_desde'
        and not t.tgisinternal and t.tgenabled = 'O'
        and md5(pg_get_triggerdef(t.oid)) = 'f5849e264eb05e8a253dbd78c2362fba'
        and md5(pg_get_functiondef(t.tgfoid)) = '900508fa3ccf3eec2e738ccdeebad7be') = 1
  ) is not true then
    raise exception 'PREFLIGHT: el sello de tenencia_desde no coincide con la version auditada';
  end if;
end;
$preflight$;

-- Foto de lo que NO debe cambiar: contrato de seguridad de la función, censo analítico,
-- declaraciones ajenas, la propia declaración (clase, tipo y fecha) y el consumidor.
create temporary table cartera_gestion_preflight on commit drop as
select
  (select to_jsonb(p) from (select proowner::regrole::text as duenio,
      prosecdef, provolatile, proconfig, proacl
    from pg_proc where oid = 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean)'::regprocedure) p) as contrato,
  (select count(*) from private.contadores_crudos_leads_citas()) as censo,
  (select coalesce(string_agg(c.objeto, ',' order by c.objeto), '')
    from private.contadores_crudos_leads_citas() c
    where not (c.declarada and c.huella_ok)) as censo_rojo,
  (select jsonb_agg(to_jsonb(e) order by e.objeto)
    from private.analitica_leads_citas_exenciones e
    where e.objeto <> 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean)') as otras,
  (select to_jsonb(e) - 'objeto' - 'huella' - 'razon'
    from private.analitica_leads_citas_exenciones e
    where e.objeto = 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean)') as declaracion,
  md5(pg_get_functiondef('crm.resumen_cartera_fn()'::regprocedure)) as resumen_md5;

drop function crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean);

create function crm.cartera_filtrada_fn(
  p_limite integer default 50,
  p_antes_de timestamptz default null,
  p_antes_id uuid default null,
  p_etapa text default null,
  p_vendedor_id uuid default null,
  p_sin_asignar boolean default false,
  p_texto text default null,
  p_desde date default null,
  p_hasta date default null,
  p_origen text default null,
  p_procedencia text default null,
  p_reasignados boolean default false,
  p_gestion text default null
)
returns jsonb language plpgsql stable security invoker set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_global boolean;
  v_visibles uuid[];
  v_texto text := nullif(btrim(p_texto), '');
  v_reparto boolean;
  v_digitos text;
  v_salida jsonb;
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
     or (v_texto is not null and length(v_texto) < 2) then
    raise exception 'Filtros de cartera inválidos' using errcode = '22023';
  end if;
  v_texto := left(v_texto, 80);
  v_digitos := left(regexp_replace(v_texto, '\D', '', 'g'), 15);
  v_global := private.rol_crm(v_uid) = 'gerencia' or private.es_lector_global();
  v_visibles := array(select private.vendedor_ids_visibles(v_uid));
  v_reparto := private.cartera_puede_operar_reparto_fn();

  with recepciones as materialized (
    select * from private.cartera_recepciones_fn(p_desde,p_hasta)
  ), base as materialized (
    select l.id, l.nombre_completo, l.telefono, l.telefono_alternativo,
      l.telefono_alternativo_crudo, l.correo, l.dni, l.genero,
      l.fecha_nacimiento, l.distrito, l.origen, l.etapa, l.motivo_descarte,
      l.monto_estimado, l.moneda, l.categoria_interes, l.vendedor_id,
      l.asignado_supervisor_id, l.creado_en, l.tenencia_desde, l.convertido_en,
      l.contrato_id, l.actualizado_en, l.activo, l.nota, l.no_contactar,
      -- Procedencia sellada por el servidor: `alta_manual` (columna del 01/09)
      -- o, para los leads anteriores a ella, tener autor. El puente inserta
      -- como service_role sin autor: nunca cae en 'manual'.
      case when l.alta_manual or l.creado_por is not null then 'manual' else 'sistema' end as procedencia,
      l.creado_por as cargado_por,
      coalesce(mov.reasignado, false) as reasignado,
      r.recibido_en, coalesce(r.aproximado,false) as recepcion_aproximada
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
    'reasignados',coalesce(p_reasignados,false),
    'items',coalesce((select jsonb_agg(to_jsonb(f) order by f.actualizado_en desc,f.id) from filas f),'[]'::jsonb),
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
          ('propuesta_enviada',4),('convertido',5),('descartado',6)) e(etapa,ord))))
  into v_salida;
  return v_salida;
end;
$$;

revoke all on function crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text) from public, anon, authenticated, service_role;
grant execute on function crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text) to authenticated;
comment on function crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text) is
  'Inventario de Leads con filtros comunes, incluidos reasignados (titular actual con una asignacion anterior a un analista) y gestion (p_gestion: con_gestion = el titular actual ya intento el contacto desde tenencia_desde, sin contar resultados de llamada deshechos; sin_gestion = el resto; no cambia la forma de la respuesta). Sistema/Manual conserva el alta. Filas, totales y embudo desde la misma base, bajo RLS.';

-- La declaración analítica se MUEVE a la firma nueva (misma fila: conserva clase, tipo y
-- fecha), con la huella del cuerpo nuevo, y la lista se resella.
update private.analitica_leads_citas_exenciones e set
  objeto = p.oid::regprocedure::text,
  huella = md5(regexp_replace(regexp_replace(lower(p.prosrc),'--[^\n]*',' ','g'),'/\*.*?\*/',' ','g')),
  razon = 'Inventario operativo unico para listado y resumen: filtros de etapa, analista, busqueda, recepcion, origen, procedencia, reasignacion entre analistas y gestion del titular actual. No calcula conversion mensual.'
from pg_proc p
where p.oid = 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)'::regprocedure
  and e.objeto = 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean)';
update private.analitica_lc_sello
  set sello = private.huella_exenciones_analitica_lc(), sellado_en = now()
  where id;

do $postflight$
declare
  f12 constant text := 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean)';
  f13 constant text := 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)';
  f13_larga constant text := 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)';
  pre record;
begin
  select * into strict pre from pg_temp.cartera_gestion_preflight;
  -- 1. Una sola firma, la de 13, con el cuerpo ENSAYADO (md5 medido en el banco con
  --    search_path vacío) y el mismo contrato de seguridad que la que sustituye.
  if (
    to_regprocedure(f12) is null
    and to_regprocedure(f13) is not null
    and (select count(*) from pg_proc where proname = 'cartera_filtrada_fn'
           and pronamespace = 'crm'::regnamespace) = 1
    and md5(pg_get_functiondef(to_regprocedure(f13))) = 'bf06666fb8ef533a39a50c7d70420153'
    and not has_function_privilege('anon', f13, 'EXECUTE')
    and not has_function_privilege('service_role', f13, 'EXECUTE')
    and has_function_privilege('authenticated', f13, 'EXECUTE')
    and (select to_jsonb(p) from (select proowner::regrole::text as duenio,
            prosecdef, provolatile, proconfig, proacl
          from pg_proc where oid = to_regprocedure(f13)) p) = pre.contrato
  ) is not true then
    raise exception 'POSTFLIGHT: firma, cuerpo, permisos o contrato invalido';
  end if;
  -- 2. El sello quedó vigente, la firma nueva está declarada con su huella y nada ajeno se
  --    movió: mismo censo, mismo conjunto en rojo (si lo había), mismas declaraciones ajenas,
  --    la propia conserva clase, tipo y fecha, y el consumidor `resumen_cartera_fn` intacto.
  if (
    (select s.sello from private.analitica_lc_sello s where s.id)
      = private.huella_exenciones_analitica_lc()
    and (select count(*) from private.contadores_crudos_leads_citas()) = pre.censo
    and exists (select 1 from private.contadores_crudos_leads_citas() c
                 where c.objeto = f13_larga and c.declarada and c.huella_ok)
    and (select coalesce(string_agg(c.objeto, ',' order by c.objeto), '')
           from private.contadores_crudos_leads_citas() c
          where not (c.declarada and c.huella_ok)) = pre.censo_rojo
    and (select jsonb_agg(to_jsonb(e) order by e.objeto)
           from private.analitica_leads_citas_exenciones e
          where e.objeto <> f13_larga) is not distinct from pre.otras
    and (select to_jsonb(e) - 'objeto' - 'huella' - 'razon'
           from private.analitica_leads_citas_exenciones e
          where e.objeto = f13_larga) = pre.declaracion
    and md5(pg_get_functiondef('crm.resumen_cartera_fn()'::regprocedure)) = pre.resumen_md5
  ) is not true then
    raise exception 'POSTFLIGHT: cambio un contador, una declaracion o un consumidor ajeno';
  end if;
  perform private.assert_actividades_de_lead_base();
  raise notice 'cartera_filtro_gestion OK: firma unica de 13 argumentos, contrato de seguridad intacto, declaracion analitica movida y sellada.';
end;
$postflight$;
notify pgrst, 'reload schema';
commit;
```

### supabase/scripts/cartera-gestion/reversa.sql (completa; el cuerpo de 12 argumentos es el de pg_get_functiondef del banco)
```sql
-- REVERSA de 20261001154153_crm_cartera_filtro_gestion: retira la firma de 13 argumentos de
-- crm.cartera_filtrada_fn y reinstala la de 12 publicada por 20260929195918 (definición tomada
-- del banco a paridad con producción, md5 7169d94239dcb191bafa3faed46f916f), con su declaración
-- analítica original, y resella. No toca datos.
-- ANTES: retirar el frente que envía p_gestion (las pestañas abiertas conservan su JavaScript
-- hasta recargar: con la firma de 12 recibirían PGRST202 al pedir «Gestionado»).
-- Guardas: no retira una función corregida después de esta entrega ni resella una lista de
-- exenciones alterada por fuera. Conserva la fila de schema_migrations: anotarlo en MIGRACIONES.md.
-- GENERADO por supabase/scripts/cartera-gestion/generar-reversa.mjs; no editar a mano.
begin;
set local lock_timeout = '10s';
set local statement_timeout = '30s';
set local search_path = '';

lock table private.analitica_leads_citas_exenciones,
  private.analitica_lc_sello in share row exclusive mode;

do $preflight$
declare
  f12 constant text := 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean)';
  f13 constant text := 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)';
  f13_larga constant text := 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)';
begin
  if (
    to_regprocedure(f13) is not null
    and to_regprocedure(f12) is null
    and (select count(*) from pg_proc where proname = 'cartera_filtrada_fn'
           and pronamespace = 'crm'::regnamespace) = 1
  ) is not true then
    raise exception 'REVERSA: la firma de 13 argumentos no es la unica instalada';
  end if;
  -- Exactamente lo que publicó 20261001154153: una corrección posterior no se pisa.
  if (
    md5(pg_get_functiondef(to_regprocedure(f13))) = 'bf06666fb8ef533a39a50c7d70420153'
    and (select e.huella from private.analitica_leads_citas_exenciones e where e.objeto = f13_larga) = '22284ce4b9e70790d6e23622f4cd6682'
    and exists (select 1 from private.contadores_crudos_leads_citas() c
                 where c.objeto = f13_larga and c.declarada and c.huella_ok)
  ) is not true then
    raise exception 'REVERSA: la funcion de 13 argumentos no es la publicada por 20261001154153';
  end if;
  if ((select s.sello from private.analitica_lc_sello s where s.id)
        = private.huella_exenciones_analitica_lc()) is not true then
    raise exception 'REVERSA: la lista de exenciones no coincide con su sello; no se resella a ciegas';
  end if;
end;
$preflight$;

create temporary table cartera_gestion_reversa on commit drop as
select
  (select to_jsonb(p) from (select proowner::regrole::text as duenio,
      prosecdef, provolatile, proconfig, proacl
    from pg_proc where oid = 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)'::regprocedure) p) as contrato,
  (select count(*) from private.contadores_crudos_leads_citas()) as censo,
  (select coalesce(string_agg(c.objeto, ',' order by c.objeto), '')
    from private.contadores_crudos_leads_citas() c
    where not (c.declarada and c.huella_ok)) as censo_rojo,
  (select jsonb_agg(to_jsonb(e) order by e.objeto)
    from private.analitica_leads_citas_exenciones e
    where e.objeto <> 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)') as otras,
  (select to_jsonb(e) - 'objeto' - 'huella' - 'razon'
    from private.analitica_leads_citas_exenciones e
    where e.objeto = 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)') as declaracion,
  md5(pg_get_functiondef('crm.resumen_cartera_fn()'::regprocedure)) as resumen_md5;

drop function crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text);

CREATE OR REPLACE FUNCTION crm.cartera_filtrada_fn(p_limite integer DEFAULT 50, p_antes_de timestamp with time zone DEFAULT NULL::timestamp with time zone, p_antes_id uuid DEFAULT NULL::uuid, p_etapa text DEFAULT NULL::text, p_vendedor_id uuid DEFAULT NULL::uuid, p_sin_asignar boolean DEFAULT false, p_texto text DEFAULT NULL::text, p_desde date DEFAULT NULL::date, p_hasta date DEFAULT NULL::date, p_origen text DEFAULT NULL::text, p_procedencia text DEFAULT NULL::text, p_reasignados boolean DEFAULT false)
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
     or (v_texto is not null and length(v_texto) < 2) then
    raise exception 'Filtros de cartera inválidos' using errcode = '22023';
  end if;
  v_texto := left(v_texto, 80);
  v_digitos := left(regexp_replace(v_texto, '\D', '', 'g'), 15);
  v_global := private.rol_crm(v_uid) = 'gerencia' or private.es_lector_global();
  v_visibles := array(select private.vendedor_ids_visibles(v_uid));
  v_reparto := private.cartera_puede_operar_reparto_fn();

  with recepciones as materialized (
    select * from private.cartera_recepciones_fn(p_desde,p_hasta)
  ), base as materialized (
    select l.id, l.nombre_completo, l.telefono, l.telefono_alternativo,
      l.telefono_alternativo_crudo, l.correo, l.dni, l.genero,
      l.fecha_nacimiento, l.distrito, l.origen, l.etapa, l.motivo_descarte,
      l.monto_estimado, l.moneda, l.categoria_interes, l.vendedor_id,
      l.asignado_supervisor_id, l.creado_en, l.tenencia_desde, l.convertido_en,
      l.contrato_id, l.actualizado_en, l.activo, l.nota, l.no_contactar,
      -- Procedencia sellada por el servidor: `alta_manual` (columna del 01/09)
      -- o, para los leads anteriores a ella, tener autor. El puente inserta
      -- como service_role sin autor: nunca cae en 'manual'.
      case when l.alta_manual or l.creado_por is not null then 'manual' else 'sistema' end as procedencia,
      l.creado_por as cargado_por,
      coalesce(mov.reasignado, false) as reasignado,
      r.recibido_en, coalesce(r.aproximado,false) as recepcion_aproximada
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
      -- La procedencia acota esa misma base, con la misma regla que la columna
      -- `procedencia` de arriba.
      and (p_procedencia is null or (l.alta_manual or l.creado_por is not null) = (p_procedencia = 'manual'))
      and (not coalesce(p_reasignados,false) or coalesce(mov.reasignado,false))
      and (p_vendedor_id is null or l.vendedor_id = p_vendedor_id)
      and (not coalesce(p_sin_asignar,false) or l.vendedor_id is null)
      and (v_texto is null or strpos(lower(l.nombre_completo),lower(v_texto)) > 0
        or (length(v_digitos) >= 3 and (strpos(l.telefono,v_digitos) > 0
          or strpos(l.telefono_alternativo,v_digitos) > 0 or strpos(l.dni,v_digitos) > 0)))
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
    'reasignados',coalesce(p_reasignados,false),
    'items',coalesce((select jsonb_agg(to_jsonb(f) order by f.actualizado_en desc,f.id) from filas f),'[]'::jsonb),
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
          ('propuesta_enviada',4),('convertido',5),('descartado',6)) e(etapa,ord))))
  into v_salida;
  return v_salida;
end;
$function$
;

revoke all on function crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean) from public, anon, authenticated, service_role;
grant execute on function crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean) to authenticated;
comment on function crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean) is
  'Inventario de Leads con filtros comunes, incluido reasignados: titular actual con una asignacion anterior a un analista. Sistema/Manual conserva el alta. Filas, totales y embudo desde la misma base, bajo RLS.';

update private.analitica_leads_citas_exenciones e set
  objeto = 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean)',
  huella = '1e2cdd16e5d59f2dd6a8280052312009',
  razon = 'Inventario operativo unico para listado y resumen: filtros de etapa, analista, busqueda, recepcion, origen, procedencia y reasignacion entre analistas. No calcula conversion mensual.'
where e.objeto = 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)';
update private.analitica_lc_sello
  set sello = private.huella_exenciones_analitica_lc(), sellado_en = now()
  where id;

do $postflight$
declare
  f12 constant text := 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean)';
  f13 constant text := 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)';
  f12_larga constant text := 'crm.cartera_filtrada_fn(integer,timestamp with time zone,uuid,text,uuid,boolean,text,date,date,text,text,boolean)';
  pre record;
begin
  select * into strict pre from pg_temp.cartera_gestion_reversa;
  if (
    to_regprocedure(f13) is null
    and to_regprocedure(f12) is not null
    and (select count(*) from pg_proc where proname = 'cartera_filtrada_fn'
           and pronamespace = 'crm'::regnamespace) = 1
    and md5(pg_get_functiondef(to_regprocedure(f12))) = '7169d94239dcb191bafa3faed46f916f'
    and not has_function_privilege('anon', f12, 'EXECUTE')
    and not has_function_privilege('service_role', f12, 'EXECUTE')
    and has_function_privilege('authenticated', f12, 'EXECUTE')
    and (select to_jsonb(p) from (select proowner::regrole::text as duenio,
            prosecdef, provolatile, proconfig, proacl
          from pg_proc where oid = to_regprocedure(f12)) p) = pre.contrato
  ) is not true then
    raise exception 'REVERSA: la funcion restaurada no es byte a byte la de 12 argumentos, o cambio su contrato';
  end if;
  if (
    (select s.sello from private.analitica_lc_sello s where s.id)
      = private.huella_exenciones_analitica_lc()
    and (select count(*) from private.contadores_crudos_leads_citas()) = pre.censo
    and exists (select 1 from private.contadores_crudos_leads_citas() c
                 where c.objeto = f12_larga and c.declarada and c.huella_ok)
    and (select coalesce(string_agg(c.objeto, ',' order by c.objeto), '')
           from private.contadores_crudos_leads_citas() c
          where not (c.declarada and c.huella_ok)) = pre.censo_rojo
    and (select jsonb_agg(to_jsonb(e) order by e.objeto)
           from private.analitica_leads_citas_exenciones e
          where e.objeto <> f12_larga) is not distinct from pre.otras
    and (select to_jsonb(e) - 'objeto' - 'huella' - 'razon'
           from private.analitica_leads_citas_exenciones e
          where e.objeto = f12_larga) = pre.declaracion
    and md5(pg_get_functiondef('crm.resumen_cartera_fn()'::regprocedure)) = pre.resumen_md5
  ) is not true then
    raise exception 'REVERSA: el censo analitico, una declaracion o un consumidor ajeno no quedo como estaba';
  end if;
  raise notice 'REVERSA cartera_filtro_gestion OK: vuelve la firma de 12 argumentos (md5 7169d94239dcb191bafa3faed46f916f) con su declaracion, sellada.';
end;
$postflight$;
notify pgrst, 'reload schema';
commit;
```

### supabase/scripts/cartera-gestion/test-cartera-gestion.sql (oráculo de negocio, 120 aserciones)
```sql
-- Oráculo del filtro `p_gestion` de crm.cartera_filtrada_fn (firma de 13 argumentos).
-- Solo en un BANCO aislado con la migración 20261001154153 instalada. Datos sintéticos dentro
-- de la transacción y ROLLBACK total: no deja nada. Correr como `postgres` (el rol que aplica
-- las migraciones), sentencia a sentencia (psql -f / stdin): la cadena real de triggers del
-- final necesita que `statement_timestamp()` avance entre sentencias.
--
-- No se detiene en la primera falla: cuenta, y al final dice «N FALLAS de M» o
-- «CARTERA_GESTION_OK M/M». Así un mutante enseña cuántas aserciones lo cazan.
--
-- ⚠️ `anon` y `service_role` NO se prueban llamando: en este Postgres (17.6 con plan_filter)
-- llamar a una función sin EXECUTE bajo `set role` tumba el servidor. Se leen del catálogo.
begin;
set local search_path = '';

-- ── Ayudantes del oráculo (temporales) ───────────────────────────────────────
create function pg_temp.actor(n integer) returns uuid language sql immutable as
  $f$ select ('f3aa1000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $f$;
create function pg_temp.lead(n integer) returns uuid language sql immutable as
  $f$ select ('f3aa2000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $f$;
-- Identidad del actor: el auth.uid() de esta imagen solo lee `request.jwt.claim.sub`; el de
-- producción también `request.jwt.claims`. Se fijan las dos. n nulo = sin sesión.
create function pg_temp.soy(n integer) returns void language sql as $f$
  select set_config('request.jwt.claim.sub', coalesce(pg_temp.actor(n)::text, ''), true),
         set_config('request.jwt.claims', case when n is null then ''
           else json_build_object('sub', pg_temp.actor(n), 'role', 'authenticated')::text end, true);
$f$;
-- Los casos que trae una respuesta, por su número de fixture: '01,02,09'.
create function pg_temp.casos(p jsonb) returns text language sql stable as $f$
  select coalesce(string_agg(right(i ->> 'nombre_completo', 2), ',' order by right(i ->> 'nombre_completo', 2)), '')
  from jsonb_array_elements(p -> 'items') i;
$f$;
create function pg_temp.vivos(p jsonb) returns integer language sql immutable as
  $f$ select (p #>> '{resumen,totales,vivos}')::integer $f$;
create function pg_temp.afirmar(p_ok boolean, p_que text) returns void language plpgsql as $f$
begin
  if p_ok is true then
    perform set_config('oraculo.ok', (current_setting('oraculo.ok')::integer + 1)::text, true);
  else
    perform set_config('oraculo.fallas', (current_setting('oraculo.fallas')::integer + 1)::text, true);
    perform set_config('oraculo.detalle', left(current_setting('oraculo.detalle') || ' · ' || p_que, 3000), true);
  end if;
end;
$f$;
select set_config('oraculo.ok', '0', true), set_config('oraculo.fallas', '0', true),
       set_config('oraculo.detalle', '', true);
grant execute on function pg_temp.actor(integer), pg_temp.lead(integer), pg_temp.soy(integer),
  pg_temp.casos(jsonb), pg_temp.vivos(jsonb), pg_temp.afirmar(boolean, text) to authenticated;
do $guarda$
begin
  -- Antes de cambiar de rol: todo lo que `authenticated` va a llamar tiene EXECUTE (ver ⚠️).
  if (
    has_function_privilege('authenticated', 'pg_temp.afirmar(boolean,text)', 'EXECUTE')
    and has_function_privilege('authenticated', 'pg_temp.soy(integer)', 'EXECUTE')
    and has_function_privilege('authenticated', 'pg_temp.casos(jsonb)', 'EXECUTE')
    and has_function_privilege('authenticated', 'pg_temp.vivos(jsonb)', 'EXECUTE')
    and has_function_privilege('authenticated', 'pg_temp.lead(integer)', 'EXECUTE')
    and has_function_privilege('authenticated', 'pg_temp.actor(integer)', 'EXECUTE')
    and has_function_privilege('authenticated',
      'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)', 'EXECUTE')
    and has_function_privilege('authenticated', 'crm.resumen_cartera_fn()', 'EXECUTE')
    and has_function_privilege('authenticated', 'crm.registrar_llamada_v4(uuid,uuid,text,text,text,jsonb,uuid,boolean,boolean)', 'EXECUTE')
    and has_function_privilege('authenticated', 'crm.deshacer_resultado_llamada(uuid)', 'EXECUTE')
  ) is not true then
    raise exception 'ORACULO GESTION: falta EXECUTE para authenticated; no se llama a ciegas';
  end if;
  if exists (select 1 from crm.leads) or exists (select 1 from public.perfiles) then
    raise exception 'ORACULO GESTION: el banco tiene leads o perfiles; este oraculo cuenta sobre un banco sin datos';
  end if;
end;
$guarda$;

-- ── Fixtures ─────────────────────────────────────────────────────────────────
set local session_replication_role = replica;
-- 1 supervisor S1 · 2 analista A · 3 analista B · 4 gerencia · 5 analista C (equipo de S2)
-- 6 supervisor S2 · 7 directorio (lector global) · 8 analista revocado · 9 solo portal.
insert into public.perfiles (id, nombre_completo, rol, activo)
select pg_temp.actor(n), 'GESTION ACTOR ' || n,
  case n when 7 then 'directorio' when 9 then 'cliente' else 'comercial' end, true
from generate_series(1, 9) n;
insert into crm.equipo (perfil_id, rol_crm, supervisor_id, activo)
select pg_temp.actor(n),
  case when n in (1, 6) then 'supervisor' when n = 4 then 'gerencia' when n = 7 then 'directorio' else 'vendedor' end,
  case when n in (2, 3, 8) then pg_temp.actor(1) when n = 5 then pg_temp.actor(6) end,
  n <> 8
from generate_series(1, 8) n;
-- Configuración que un banco vacío no trae (sembrar antes que parchear): la cadena real del
-- final abre un episodio en el libro de asignaciones y reabre un descarte: necesita una política
-- de plazos vigente con sus etapas; el consumidor `resumen_cartera_fn` necesita un peso de conversión.
insert into crm.sla_politicas (id, version, vigente_desde, zona_horaria, tipo_reloj,
  primera_gestion_minutos, primer_contacto_minutos)
values ('f3aa3000-0000-4000-8000-000000000001', 1, '2020-01-01T00:00:00Z', 'America/Lima', 'corrido', 60, 120);
insert into crm.sla_politica_etapas (politica_id, etapa, maximo_minutos)
select 'f3aa3000-0000-4000-8000-000000000001', e, 1440
from unnest(array['nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada']) e;
insert into crm.conversion_pesos (vigente_desde, peso_referido, nota)
values ('2026-01-01', 0.5, 'sintetico: oraculo cartera-gestion');

-- Un caso por lead. `ten` = días desde que el titular ACTUAL lo recibió (null = sin tenencia).
--  n  titular  etapa               ten   lo que tiene                                   veredicto
--  01 A        nuevo               5     llamada sin respuesta hace 4 días              CON
--  02 A        nuevo               5     WhatsApp enviado ayer                          CON
--  03 A        nuevo               5     nada                                           SIN
--  04 A        nuevo               5     solo una nota                                  SIN
--  05 B        nuevo (reasignado)  2     intento de A hace 4 días (ANTES de la tenencia) SIN
--  06 B        nuevo (reasignado)  2     intento de A hace 4 días + WhatsApp de B ayer  CON
--  07 —        nuevo, bandeja S1   —     intento viejo de quien lo tuvo                 SIN (sin titular)
--  08 A        nuevo               null  intento ayer, pero sin tenencia_desde          SIN (sin tenencia)
--  09 A        nuevo               5     WhatsApp en el INSTANTE exacto de la tenencia  CON (borde >=)
--  10 A        nuevo               5     WhatsApp 1 microsegundo ANTES de la tenencia   SIN (borde)
--  11 A        contactado          5     llamada realizada hace 3 días                  CON
--  12 A        contactado          5     llamada realizada hace 9 días (antes)          SIN
--  13 C        nuevo               3     llamada sin respuesta hace 2 días              CON
--  14 C        nuevo               3     nada                                           SIN
--  15 A        descartado          null  intento ayer                                   SIN (etapa terminal)
--  16 A        convertido          null  reunión hace 4 días                            SIN (etapa terminal)
--  17 A        nuevo, dado de baja 5     intento ayer                                   fuera de la base
--  18 A        nuevo               5     cambio de etapa, reasignación y conversión     SIN (no son contacto)
--  19 A        nuevo               5     WhatsApp recibido ayer                         CON
--  20 A        nuevo               5     reunión realizada ayer                         CON
--  21 A        nuevo               5     llamada realizada ayer                         CON
--  22 —        nuevo, bolsa libre  —     nada                                           SIN (sin titular)
--  24 A        reunion_agendada    5     reunión realizada hace 2 días                  CON
--  25 B        propuesta_enviada   2     nada                                           SIN
--  26 —        nuevo, bandeja S1   5(!)  intento ayer y una tenencia_desde huérfana     SIN (sin titular)
--  27 A        nuevo               5     intento de ayer hecho por su SUPERVISOR        CON (la regla es por fecha, no por autor)
--  28 A        nuevo               5     SOLO una llamada cuyo resultado se DESHIZO      SIN (lo deshecho no ocurrió)
--  29 A        nuevo               5     una llamada deshecha + un WhatsApp válido ayer  CON (basta un intento vigente)
--  30 A        nuevo               5     intento válido de ANTES de la tenencia + uno deshecho dentro   SIN (ninguno cuenta)
insert into crm.leads (id, nombre_completo, telefono, origen, etapa, motivo_descarte,
  monto_estimado, moneda, vendedor_id, asignado_supervisor_id, creado_en, actualizado_en,
  convertido_en, tenencia_desde, activo)
select pg_temp.lead(n), 'GESTION LEAD ' || lpad(n::text, 2, '0'), '+5199933' || lpad(n::text, 4, '0'),
  case when n = 2 then 'referido' else 'landing' end,
  case when n in (11, 12) then 'contactado' when n = 15 then 'descartado' when n = 16 then 'convertido'
    when n = 24 then 'reunion_agendada' when n = 25 then 'propuesta_enviada' else 'nuevo' end,
  case when n = 15 then 'no_responde' end,
  n * 100, case when n in (2, 13) then 'USD' else 'PEN' end,
  case when n in (5, 6, 25) then pg_temp.actor(3) when n in (13, 14) then pg_temp.actor(5)
    when n in (7, 22, 26) then null else pg_temp.actor(2) end,
  case when n in (7, 26) then pg_temp.actor(1) end,
  now() - interval '10 days',
  -- Empate de sello entre 01, 02, 03 y 09: el cursor desempata por id.
  case when n in (1, 2, 3, 9) then now() - interval '1 minute' else now() - make_interval(mins => n) end,
  case when n = 16 then now() - interval '3 days' end,
  case when n in (7, 8, 15, 16, 22) then null
    when n in (5, 6, 25) then now() - interval '2 days'
    when n in (13, 14) then now() - interval '3 days'
    else now() - interval '5 days' end,
  n <> 17
from generate_series(1, 30) n where n <> 23;

insert into crm.actividades (lead_id, tipo, metadata, creado_por, creado_en)
values
  (pg_temp.lead(1),  'llamada_no_contestada', '{}', pg_temp.actor(2), now() - interval '4 days'),
  (pg_temp.lead(2),  'whatsapp_enviado',      '{}', pg_temp.actor(2), now() - interval '1 day'),
  (pg_temp.lead(4),  'nota',                  '{}', pg_temp.actor(2), now() - interval '1 day'),
  (pg_temp.lead(5),  'llamada_no_contestada', '{}', pg_temp.actor(2), now() - interval '4 days'),
  (pg_temp.lead(5),  'reasignacion', jsonb_build_object('vendedor_anterior', pg_temp.actor(2), 'vendedor_nuevo', pg_temp.actor(3)), null, now() - interval '2 days'),
  (pg_temp.lead(6),  'llamada_no_contestada', '{}', pg_temp.actor(2), now() - interval '4 days'),
  (pg_temp.lead(6),  'reasignacion', jsonb_build_object('vendedor_anterior', pg_temp.actor(2), 'vendedor_nuevo', pg_temp.actor(3)), null, now() - interval '2 days'),
  (pg_temp.lead(6),  'whatsapp_enviado',      '{}', pg_temp.actor(3), now() - interval '1 day'),
  (pg_temp.lead(7),  'llamada_no_contestada', '{}', pg_temp.actor(2), now() - interval '6 days'),
  (pg_temp.lead(7),  'reasignacion', jsonb_build_object('vendedor_anterior', pg_temp.actor(2), 'vendedor_nuevo', null), null, now() - interval '5 days'),
  (pg_temp.lead(8),  'llamada_no_contestada', '{}', pg_temp.actor(2), now() - interval '1 day'),
  (pg_temp.lead(9),  'whatsapp_enviado',      '{}', pg_temp.actor(2), now() - interval '5 days'),
  (pg_temp.lead(10), 'whatsapp_enviado',      '{}', pg_temp.actor(2), now() - interval '5 days' - interval '1 microsecond'),
  (pg_temp.lead(11), 'llamada_realizada',     '{}', pg_temp.actor(2), now() - interval '3 days'),
  (pg_temp.lead(12), 'llamada_realizada',     '{}', pg_temp.actor(2), now() - interval '9 days'),
  (pg_temp.lead(13), 'llamada_no_contestada', '{}', pg_temp.actor(5), now() - interval '2 days'),
  (pg_temp.lead(15), 'llamada_no_contestada', '{}', pg_temp.actor(2), now() - interval '1 day'),
  (pg_temp.lead(16), 'reunion_realizada',     '{}', pg_temp.actor(2), now() - interval '4 days'),
  (pg_temp.lead(17), 'llamada_no_contestada', '{}', pg_temp.actor(2), now() - interval '1 day'),
  (pg_temp.lead(18), 'cambio_etapa',          '{}', null,             now() - interval '1 day'),
  (pg_temp.lead(18), 'reasignacion', jsonb_build_object('vendedor_anterior', null, 'vendedor_nuevo', pg_temp.actor(2)), null, now() - interval '1 day'),
  (pg_temp.lead(18), 'conversion',            '{}', null,             now() - interval '1 day'),
  (pg_temp.lead(19), 'whatsapp_recibido',     '{}', pg_temp.actor(2), now() - interval '1 day'),
  (pg_temp.lead(20), 'reunion_realizada',     '{}', pg_temp.actor(2), now() - interval '1 day'),
  (pg_temp.lead(21), 'llamada_realizada',     '{}', pg_temp.actor(2), now() - interval '1 day'),
  (pg_temp.lead(24), 'reunion_realizada',     '{}', pg_temp.actor(2), now() - interval '2 days'),
  (pg_temp.lead(26), 'llamada_no_contestada', '{}', pg_temp.actor(2), now() - interval '1 day'),
  (pg_temp.lead(27), 'llamada_no_contestada', '{}', pg_temp.actor(1), now() - interval '1 day'),
  -- Resultados de llamada DESHECHOS: el estado exacto que deja crm.deshacer_resultado_llamada
  -- (la fila se queda; gana `deshecho_en` y `deshecho_por`). La puerta real se ejerce al final.
  (pg_temp.lead(28), 'llamada_no_contestada', jsonb_build_object('evento', 'resultado_llamada', 'resultado', 'no_contesto',
     'deshecho_en', now() - interval '23 hours', 'deshecho_por', pg_temp.actor(2)), pg_temp.actor(2), now() - interval '1 day'),
  (pg_temp.lead(29), 'llamada_no_contestada', jsonb_build_object('evento', 'resultado_llamada', 'resultado', 'no_contesto',
     'deshecho_en', now() - interval '47 hours', 'deshecho_por', pg_temp.actor(2)), pg_temp.actor(2), now() - interval '2 days'),
  (pg_temp.lead(29), 'whatsapp_enviado',      '{}', pg_temp.actor(2), now() - interval '1 day'),
  (pg_temp.lead(30), 'llamada_no_contestada', '{}', pg_temp.actor(2), now() - interval '8 days'),
  (pg_temp.lead(30), 'llamada_no_contestada', jsonb_build_object('evento', 'resultado_llamada', 'resultado', 'no_contesto',
     'deshecho_en', now() - interval '23 hours', 'deshecho_por', pg_temp.actor(2)), pg_temp.actor(2), now() - interval '1 day');

-- Recepción (para componer con p_desde/p_hasta): A recibió 01..04 ayer (día de Lima).
insert into crm.lead_asignaciones (lead_id, ciclo_n, episodio_n, analista_id, motivo_apertura,
  asignado_en, sla_global_iniciado_en, sla_politica_asignacion_id, primera_gestion_limite_en,
  primer_contacto_limite_en, moneda, origen, finalizado_en, motivo_cierre, aproximado)
select pg_temp.lead(n), 1, 1, pg_temp.actor(2), 'asignado', t.sello, t.sello,
  'f3aa3000-0000-4000-8000-000000000001', t.sello + interval '1 hour', t.sello + interval '2 hours',
  'PEN', 'oraculo_gestion', t.sello + interval '1 second', 'desactivado', false
from generate_series(1, 4) n
cross join lateral (select (((now() at time zone 'America/Lima')::date - 1)::timestamp at time zone 'America/Lima')
  + interval '12 hours' as sello) t;
-- El lead de la cadena real del final: nace en la bandeja de S1 y de baja, para que no cuente
-- en ninguna cifra de arriba; se activa al llegar a ese bloque.
insert into crm.leads (id, nombre_completo, telefono, origen, etapa, monto_estimado, moneda,
  vendedor_id, asignado_supervisor_id, creado_en, actualizado_en, activo)
values (pg_temp.lead(99), 'GESTION CADENA REAL 99', '+51999330099', 'landing', 'nuevo', 1000, 'PEN',
  null, pg_temp.actor(1), now() - interval '3 days', now() - interval '3 days', false);

set local session_replication_role = origin;
set local role authenticated;

-- ── A · analista: la regla de negocio, caso por caso ─────────────────────────
select pg_temp.soy(2);
do $a$
declare
  t jsonb; c jsonb; s jsonb; r jsonb; p jsonb;
  ids uuid[] := '{}'; fila jsonb; cursor_fecha timestamptz; cursor_id uuid; paginas integer := 0;
  ayer date := (now() at time zone 'America/Lima')::date - 1;
begin
  t := crm.cartera_filtrada_fn(p_limite => 200);
  c := crm.cartera_filtrada_fn(p_limite => 200, p_gestion => 'con_gestion');
  s := crm.cartera_filtrada_fn(p_limite => 200, p_gestion => 'sin_gestion');
  perform pg_temp.afirmar(pg_temp.casos(t) = '01,02,03,04,08,09,10,11,12,15,16,18,19,20,21,24,27,28,29,30', 'A sin filtro: sus 20 leads vivos (el dado de baja no entra)');
  perform pg_temp.afirmar(pg_temp.casos(c) = '01,02,09,11,19,20,21,24,27,29', 'A con_gestion: exactamente los 10 gestionados en la tenencia vigente');
  perform pg_temp.afirmar(pg_temp.casos(s) = '03,04,08,10,12,15,16,18,28,30', 'A sin_gestion: exactamente los otros 10');
  perform pg_temp.afirmar(c -> 'items' @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(1))), 'intento sin respuesta (llamada no contestada) => con_gestion');
  perform pg_temp.afirmar(c -> 'items' @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(2))), 'WhatsApp enviado => con_gestion');
  perform pg_temp.afirmar(s -> 'items' @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(3))), 'lead sin actividad => sin_gestion');
  perform pg_temp.afirmar(s -> 'items' @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(4))), 'solo una nota => sin_gestion');
  perform pg_temp.afirmar(s -> 'items' @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(8))), 'titular sin tenencia_desde => sin_gestion');
  perform pg_temp.afirmar(c -> 'items' @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(9))), 'contacto en el instante exacto de la tenencia => con_gestion (>=)');
  perform pg_temp.afirmar(s -> 'items' @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(10))), 'contacto un microsegundo antes de la tenencia => sin_gestion');
  perform pg_temp.afirmar(s -> 'items' @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(18))), 'cambio de etapa, reasignacion y conversion no son gestion');
  perform pg_temp.afirmar(c -> 'items' @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(19)), jsonb_build_object('id', pg_temp.lead(20)), jsonb_build_object('id', pg_temp.lead(21))),
    'los otros tres tipos de contacto (WhatsApp recibido, reunion y llamada realizadas) cuentan');
  perform pg_temp.afirmar(s -> 'items' @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(15)), jsonb_build_object('id', pg_temp.lead(16))),
    'descartado y convertido (sin tenencia) => sin_gestion');
  perform pg_temp.afirmar(c -> 'items' @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(27))), 'intento hecho por el supervisor dentro de la tenencia => con_gestion (cuenta la fecha, no el autor)');
  perform pg_temp.afirmar(s -> 'items' @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(28))), 'solo un intento deshecho => sin_gestion (lo deshecho no cuenta)');
  perform pg_temp.afirmar(c -> 'items' @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(29))), 'un intento deshecho + otro valido en la tenencia => con_gestion');
  perform pg_temp.afirmar(s -> 'items' @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(30))), 'un intento deshecho en la tenencia + uno valido de antes => sin_gestion (ninguno cuenta)');

  -- Partición exacta: sin solapes, sin huecos, y en TODAS las cifras del resumen.
  perform pg_temp.afirmar(pg_temp.vivos(c) = 10 and pg_temp.vivos(s) = 10 and pg_temp.vivos(t) = 20, 'A: totales.vivos 10 + 10 = 20');
  perform pg_temp.afirmar(not exists (select 1 from jsonb_array_elements(c -> 'items') x
    join jsonb_array_elements(s -> 'items') y on x ->> 'id' = y ->> 'id'), 'A: ningun lead en las dos mitades');
  perform pg_temp.afirmar((select bool_and((t #>> array['resumen','totales',k])::integer
      = (c #>> array['resumen','totales',k])::integer + (s #>> array['resumen','totales',k])::integer)
    from jsonb_object_keys(t #> '{resumen,totales}') k), 'A: cada cifra de resumen.totales = con + sin');
  perform pg_temp.afirmar((select bool_and((te ->> 'n')::integer = (ce ->> 'n')::integer + (se ->> 'n')::integer and te ->> 'etapa' = ce ->> 'etapa' and te ->> 'etapa' = se ->> 'etapa')
    from jsonb_array_elements(t #> '{resumen,embudo}') with ordinality a(te, o)
    join jsonb_array_elements(c #> '{resumen,embudo}') with ordinality b(ce, o) using (o)
    join jsonb_array_elements(s #> '{resumen,embudo}') with ordinality d(se, o) using (o)), 'A: embudo etapa por etapa = con + sin');
  perform pg_temp.afirmar((select string_agg(e ->> 'n', ',' order by o) from jsonb_array_elements(c #> '{resumen,embudo}') with ordinality x(e, o)) = '8,1,1,0,0,0', 'A con_gestion: embudo 8 nuevo, 1 contactado, 1 reunion');
  perform pg_temp.afirmar((select string_agg(e ->> 'n', ',' order by o) from jsonb_array_elements(s #> '{resumen,embudo}') with ordinality x(e, o)) = '7,1,0,0,1,1', 'A sin_gestion: embudo 7 nuevo, 1 contactado, 1 convertido, 1 descartado');
  perform pg_temp.afirmar((select bool_and((t #>> array['resumen','capital',tipo,mon])::numeric
      = (c #>> array['resumen','capital',tipo,mon])::numeric + (s #>> array['resumen','capital',tipo,mon])::numeric)
    from (values ('asignado'), ('parkeado'), ('ganado')) a(tipo) cross join (values ('pen'), ('usd')) b(mon)), 'A: capital por tipo y moneda = con + sin');
  perform pg_temp.afirmar((c #>> '{resumen,capital,asignado,pen}')::numeric = 100 + 900 + 1100 + 1900 + 2000 + 2100 + 2400 + 2700 + 2900
    and (c #>> '{resumen,capital,asignado,usd}')::numeric = 200, 'A con_gestion: capital asignado solo de los gestionados (PEN y USD aparte)');
  perform pg_temp.afirmar((t #>> '{resumen,conversion,base}')::integer = (c #>> '{resumen,conversion,base}')::integer + (s #>> '{resumen,conversion,base}')::integer
    and (t #>> '{resumen,descartes,total}')::integer = (c #>> '{resumen,descartes,total}')::integer + (s #>> '{resumen,descartes,total}')::integer, 'A: conversion.base y descartes.total = con + sin');
  perform pg_temp.afirmar((c #>> '{resumen,sin_tocar}')::integer = 0 and (s #>> '{resumen,sin_tocar}')::integer = 3
    and (t #>> '{resumen,sin_tocar}')::integer = 3, 'A: sin_tocar (nunca contactados: 03, 04, 18) cae entero en sin_gestion; no cambia: una llamada deshecha sigue siendo «tocado»');

  -- La pantalla: Pipeline con p_etapa = 'nuevo'.
  c := crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'nuevo', p_gestion => 'con_gestion');
  s := crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'nuevo', p_gestion => 'sin_gestion');
  perform pg_temp.afirmar(pg_temp.casos(c) = '01,02,09,19,20,21,27,29' and pg_temp.vivos(c) = 8, 'A Pipeline «Gestionado»: nuevo + con_gestion = 8');
  perform pg_temp.afirmar(pg_temp.casos(s) = '03,04,08,10,18,28,30' and pg_temp.vivos(s) = 7, 'A Pipeline «Nuevo»: nuevo + sin_gestion = 7');
  r := crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'contactado', p_gestion => 'con_gestion');
  perform pg_temp.afirmar(pg_temp.casos(r) = '11', 'el filtro es independiente de la etapa (contactado + con_gestion)');

  -- La forma del payload no cambia: mismas claves arriba, en el resumen y por fila; sin eco.
  perform pg_temp.afirmar((select array_agg(k order by k) from jsonb_object_keys(c) k)
    = array['desde','generado_en','hasta','items','origen','procedencia','reasignados','resumen','version'], 'claves de arriba: las de siempre, sin eco «gestion»');
  perform pg_temp.afirmar((select array_agg(k order by k) from jsonb_object_keys(c -> 'resumen') k)
    = (select array_agg(k order by k) from jsonb_object_keys(t -> 'resumen') k), 'claves del resumen: iguales con y sin filtro');
  perform pg_temp.afirmar((select array_agg(k order by k) from jsonb_object_keys(c #> '{items,0}') k)
    = array['activo','actualizado_en','asignado_supervisor_id','cargado_por','categoria_interes','contrato_id','convertido_en','correo','creado_en','distrito','dni','etapa','fecha_nacimiento','genero','id','moneda','monto_estimado','motivo_descarte','no_contactar','nombre_completo','nota','origen','procedencia','reasignado','recepcion_aproximada','recibido_en','telefono','telefono_alternativo','telefono_alternativo_crudo','tenencia_desde','ultimo_contacto_en','vendedor_id'],
    'claves por fila: las 32 de siempre, ninguna nueva');
  -- La fila permite comprobar el veredicto en UN sentido: con gestión ⇒ último contacto >=
  -- tenencia. El recíproco ya no vale: `ultimo_contacto_en` (comportamiento existente) sigue
  -- viendo una llamada deshecha, que para el filtro no ocurrió.
  c := crm.cartera_filtrada_fn(p_limite => 200, p_gestion => 'con_gestion');
  s := crm.cartera_filtrada_fn(p_limite => 200, p_gestion => 'sin_gestion');
  perform pg_temp.afirmar(not exists (select 1 from jsonb_array_elements(c -> 'items') i
    where ((i ->> 'ultimo_contacto_en')::timestamptz >= (i ->> 'tenencia_desde')::timestamptz) is not true
       or i -> 'vendedor_id' = 'null'::jsonb), 'toda fila con_gestion: titular y ultimo_contacto_en >= tenencia_desde');
  perform pg_temp.afirmar((select coalesce(string_agg(right(i ->> 'nombre_completo', 2), ',' order by right(i ->> 'nombre_completo', 2)), '')
    from jsonb_array_elements(s -> 'items') i
    where i -> 'vendedor_id' <> 'null'::jsonb
      and (i ->> 'ultimo_contacto_en')::timestamptz >= (i ->> 'tenencia_desde')::timestamptz) = '28,30',
    'en sin_gestion, las unicas filas con un contacto dentro de su tenencia son las de intentos deshechos (28 y 30)');

  -- Compone con los demás filtros sobre la MISMA base.
  r := crm.cartera_filtrada_fn(p_gestion => 'con_gestion', p_texto => 'LEAD 02');
  perform pg_temp.afirmar(pg_temp.casos(r) = '02' and pg_temp.vivos(r) = 1, 'compone con la busqueda (con)');
  r := crm.cartera_filtrada_fn(p_gestion => 'sin_gestion', p_texto => 'LEAD 02');
  perform pg_temp.afirmar(pg_temp.casos(r) = '' and pg_temp.vivos(r) = 0 and r -> 'items' = '[]'::jsonb, 'vacio honesto: el lead existe pero no esta en esa mitad');
  r := crm.cartera_filtrada_fn(p_gestion => 'con_gestion', p_origen => 'referido');
  perform pg_temp.afirmar(pg_temp.casos(r) = '02', 'compone con el origen');
  r := crm.cartera_filtrada_fn(p_gestion => 'con_gestion', p_procedencia => 'sistema', p_etapa => 'nuevo');
  perform pg_temp.afirmar(pg_temp.vivos(r) = 8, 'compone con la procedencia');
  r := crm.cartera_filtrada_fn(p_gestion => 'con_gestion', p_desde => ayer, p_hasta => ayer);
  perform pg_temp.afirmar(pg_temp.casos(r) = '01,02' and r ->> 'desde' = ayer::text, 'compone con la recepcion (recibidos ayer y ya intentados)');
  r := crm.cartera_filtrada_fn(p_gestion => 'sin_gestion', p_desde => ayer, p_hasta => ayer);
  perform pg_temp.afirmar(pg_temp.casos(r) = '03,04', 'compone con la recepcion (recibidos ayer sin intentar)');
  r := crm.cartera_filtrada_fn(p_gestion => 'con_gestion', p_vendedor_id => pg_temp.actor(5));
  perform pg_temp.afirmar(pg_temp.vivos(r) = 0, 'A no alcanza la cartera de otro equipo ni con el filtro');
  r := crm.cartera_filtrada_fn(p_gestion => 'sin_gestion', p_vendedor_id => pg_temp.actor(3));
  perform pg_temp.afirmar(pg_temp.vivos(r) = 0, 'A no alcanza la cartera de un companero de equipo');

  -- Paginación por cursor con el filtro puesto: sin repetir ni perder, total estable.
  loop
    p := crm.cartera_filtrada_fn(p_gestion => 'con_gestion', p_limite => 3, p_antes_de => cursor_fecha, p_antes_id => cursor_id);
    perform pg_temp.afirmar(pg_temp.vivos(p) = 10, 'cursor: el total no cambia entre paginas');
    exit when jsonb_array_length(p -> 'items') = 0;
    paginas := paginas + 1;
    for fila in select value from jsonb_array_elements(p -> 'items') loop
      perform pg_temp.afirmar(not (fila ->> 'id')::uuid = any (ids), 'cursor: ninguna fila repetida');
      ids := array_append(ids, (fila ->> 'id')::uuid);
      cursor_fecha := (fila ->> 'actualizado_en')::timestamptz; cursor_id := (fila ->> 'id')::uuid;
    end loop;
  end loop;
  perform pg_temp.afirmar(cardinality(ids) = 10 and paginas = 4, 'cursor: 4 paginas (3, 3, 3 y 1) reconstruyen los 10 sin perdidas');
  perform pg_temp.afirmar(ids[1:3] = array[pg_temp.lead(1), pg_temp.lead(2), pg_temp.lead(9)], 'cursor: el empate de sello (01, 02, 09) se resuelve por id');
  perform pg_temp.afirmar((select array_agg(x order by x) from unnest(ids) x)
    = (select array_agg((i ->> 'id')::uuid order by (i ->> 'id')::uuid) from jsonb_array_elements(c -> 'items') i), 'cursor: las paginas juntas = la respuesta sin paginar');

  -- Validación: fuera de dominio se rechaza; nunca un «cero resultados» silencioso.
  begin perform crm.cartera_filtrada_fn(p_gestion => 'gestionado'); perform pg_temp.afirmar(false, 'valor desconocido debio rechazarse');
  exception when sqlstate '22023' then perform pg_temp.afirmar(sqlerrm = 'Filtros de cartera inválidos', 'valor desconocido => 22023 con el mensaje del bloque existente'); end;
  begin perform crm.cartera_filtrada_fn(p_gestion => ''); perform pg_temp.afirmar(false, 'cadena vacia debio rechazarse');
  exception when sqlstate '22023' then perform pg_temp.afirmar(true, 'cadena vacia => 22023'); end;
  begin perform crm.cartera_filtrada_fn(p_gestion => 'CON_GESTION'); perform pg_temp.afirmar(false, 'mayusculas debieron rechazarse');
  exception when sqlstate '22023' then perform pg_temp.afirmar(true, 'mayusculas => 22023'); end;
  begin perform crm.cartera_filtrada_fn(p_gestion => 'con_gestion '); perform pg_temp.afirmar(false, 'espacio final debio rechazarse');
  exception when sqlstate '22023' then perform pg_temp.afirmar(true, 'espacio final => 22023'); end;
  begin perform crm.cartera_filtrada_fn(p_gestion => 'con_gestion', p_origen => 'facebook'); perform pg_temp.afirmar(false, 'las guardas previas debieron seguir');
  exception when sqlstate '22023' then perform pg_temp.afirmar(true, 'las guardas previas siguen (origen fuera de dominio)'); end;

  -- Compatibilidad: la llamada de siempre (12 argumentos, sin p_gestion) sigue resolviendo.
  r := crm.cartera_filtrada_fn(p_limite => 200, p_antes_de => null, p_antes_id => null, p_etapa => null,
    p_vendedor_id => null, p_sin_asignar => false, p_texto => null, p_desde => null, p_hasta => null,
    p_origen => null, p_procedencia => null, p_reasignados => false);
  perform pg_temp.afirmar(r - 'generado_en' = t - 'generado_en', 'los 12 argumentos por nombre, sin p_gestion: misma respuesta que sin filtro');
  r := crm.cartera_filtrada_fn(200, null, null, null, null, false, null, null, null, null, null, false);
  perform pg_temp.afirmar(r - 'generado_en' = t - 'generado_en', 'los 12 argumentos por posicion: misma respuesta');
  r := crm.cartera_filtrada_fn(p_limite => 200, p_gestion => null);
  perform pg_temp.afirmar(r - 'generado_en' = t - 'generado_en', 'p_gestion nulo explicito = omitido');
  perform pg_temp.afirmar((crm.resumen_cartera_fn() #>> '{totales,vivos}')::integer = 20, 'el consumidor resumen_cartera_fn sigue resolviendo la firma ampliada');
end;
$a$;

-- ── B · analista que RECIBIÓ leads reasignados ───────────────────────────────
select pg_temp.soy(3);
do $b$
declare c jsonb; s jsonb; r jsonb;
begin
  c := crm.cartera_filtrada_fn(p_limite => 200, p_gestion => 'con_gestion');
  s := crm.cartera_filtrada_fn(p_limite => 200, p_gestion => 'sin_gestion');
  perform pg_temp.afirmar(pg_temp.casos(s) = '05,25', 'reasignado: lo que intento el analista ANTERIOR no cuenta => sin_gestion para el actual');
  perform pg_temp.afirmar(pg_temp.casos(c) = '06', 'reasignado y vuelto a intentar por el nuevo titular => con_gestion');
  r := crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'nuevo', p_gestion => 'sin_gestion');
  perform pg_temp.afirmar(pg_temp.casos(r) = '05' and (r #>> '{items,0,reasignado}')::boolean, 'B Pipeline «Nuevo»: el reasignado sin intento propio, marcado como reasignado');
  r := crm.cartera_filtrada_fn(p_reasignados => true, p_gestion => 'con_gestion');
  perform pg_temp.afirmar(pg_temp.casos(r) = '06', 'compone con reasignados (con)');
  r := crm.cartera_filtrada_fn(p_reasignados => true, p_gestion => 'sin_gestion');
  perform pg_temp.afirmar(pg_temp.casos(r) = '05', 'compone con reasignados (sin)');
  perform pg_temp.afirmar(pg_temp.vivos(crm.cartera_filtrada_fn(p_limite => 200)) = 3, 'B solo ve lo suyo');
end;
$b$;

-- ── S1 · supervisor: su equipo y su bandeja, nada más ────────────────────────
select pg_temp.soy(1);
do $s1$
declare t jsonb; c jsonb; s jsonb; r jsonb;
begin
  t := crm.cartera_filtrada_fn(p_limite => 200);
  c := crm.cartera_filtrada_fn(p_limite => 200, p_gestion => 'con_gestion');
  s := crm.cartera_filtrada_fn(p_limite => 200, p_gestion => 'sin_gestion');
  perform pg_temp.afirmar(pg_temp.vivos(t) = 25 and pg_temp.vivos(c) = 11 and pg_temp.vivos(s) = 14, 'supervisor: 11 + 14 = 25 (A, B y su bandeja)');
  perform pg_temp.afirmar(pg_temp.casos(c) = '01,02,06,09,11,19,20,21,24,27,29', 'supervisor con_gestion: los de A y el de B; ninguno del otro equipo');
  perform pg_temp.afirmar(s -> 'items' @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(7))), 'sin titular (bandeja) => sin_gestion aunque tenga intentos viejos');
  perform pg_temp.afirmar(s -> 'items' @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(26))), 'sin titular => sin_gestion aunque conserve una tenencia_desde y un intento posterior');
  perform pg_temp.afirmar(not exists (select 1 from jsonb_array_elements((c -> 'items') || (s -> 'items')) i
    where right(i ->> 'nombre_completo', 2) in ('13', '14', '22')), 'supervisor: el filtro no trae leads de otro equipo ni la bolsa libre');
  r := crm.cartera_filtrada_fn(p_sin_asignar => true, p_gestion => 'con_gestion');
  perform pg_temp.afirmar(pg_temp.vivos(r) = 0, 'pendientes de repartir + con_gestion = vacio (sin titular no hay gestion)');
  r := crm.cartera_filtrada_fn(p_sin_asignar => true, p_gestion => 'sin_gestion');
  perform pg_temp.afirmar(pg_temp.casos(r) = '07,26', 'pendientes de repartir + sin_gestion = su bandeja');
  r := crm.cartera_filtrada_fn(p_vendedor_id => pg_temp.actor(3), p_gestion => 'con_gestion');
  perform pg_temp.afirmar(pg_temp.casos(r) = '06', 'supervisor acota por analista de su equipo');
  r := crm.cartera_filtrada_fn(p_vendedor_id => pg_temp.actor(5), p_gestion => 'con_gestion');
  perform pg_temp.afirmar(pg_temp.vivos(r) = 0, 'supervisor no alcanza a un analista de otro equipo');
end;
$s1$;

-- ── C y S2 · el otro equipo ──────────────────────────────────────────────────
select pg_temp.soy(5);
do $c$
begin
  perform pg_temp.afirmar(pg_temp.casos(crm.cartera_filtrada_fn(p_gestion => 'con_gestion')) = '13'
    and pg_temp.casos(crm.cartera_filtrada_fn(p_gestion => 'sin_gestion')) = '14', 'analista del otro equipo: solo lo suyo, partido en dos');
end;
$c$;
select pg_temp.soy(6);
do $s2$
begin
  perform pg_temp.afirmar(pg_temp.casos(crm.cartera_filtrada_fn(p_gestion => 'con_gestion')) = '13'
    and pg_temp.casos(crm.cartera_filtrada_fn(p_gestion => 'sin_gestion')) = '14', 'supervisor del otro equipo: solo su equipo');
end;
$s2$;

-- ── Gerencia y Directorio: todo ──────────────────────────────────────────────
select pg_temp.soy(4);
do $g$
declare t jsonb; c jsonb; s jsonb;
begin
  t := crm.cartera_filtrada_fn(p_limite => 200);
  c := crm.cartera_filtrada_fn(p_limite => 200, p_gestion => 'con_gestion');
  s := crm.cartera_filtrada_fn(p_limite => 200, p_gestion => 'sin_gestion');
  perform pg_temp.afirmar(pg_temp.vivos(t) = 28 and pg_temp.vivos(c) = 12 and pg_temp.vivos(s) = 16, 'gerencia: 12 + 16 = 28 (toda la empresa)');
  perform pg_temp.afirmar(pg_temp.casos(c) = '01,02,06,09,11,13,19,20,21,24,27,29', 'gerencia con_gestion: los 12 gestionados de los tres analistas');
  perform pg_temp.afirmar(s -> 'items' @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(22)), jsonb_build_object('id', pg_temp.lead(7))), 'gerencia: bolsa libre y bandeja => sin_gestion');
  perform pg_temp.afirmar(pg_temp.vivos(crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'nuevo', p_gestion => 'con_gestion')) = 10
    and pg_temp.vivos(crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'nuevo', p_gestion => 'sin_gestion')) = 12
    and pg_temp.vivos(crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'nuevo')) = 22, 'gerencia Pipeline: nuevo 22 = Gestionado 10 + Nuevo 12');
end;
$g$;
select pg_temp.soy(7);
do $d$
begin
  perform pg_temp.afirmar(pg_temp.vivos(crm.cartera_filtrada_fn(p_limite => 200, p_gestion => 'con_gestion')) = 12
    and pg_temp.vivos(crm.cartera_filtrada_fn(p_limite => 200, p_gestion => 'sin_gestion')) = 16, 'directorio (lector global): misma particion que gerencia');
end;
$d$;

-- ── Quien no entra, no entra tampoco con el filtro (se llama CON EXECUTE: es la guarda
--    de la función la que rechaza, no el permiso) ──────────────────────────────
select pg_temp.soy(8);
do $r$
begin
  begin perform crm.cartera_filtrada_fn(p_gestion => 'con_gestion'); perform pg_temp.afirmar(false, 'analista revocado debio rechazarse');
  exception when insufficient_privilege then perform pg_temp.afirmar(true, 'analista revocado => 42501'); end;
end;
$r$;
select pg_temp.soy(9);
do $p$
begin
  begin perform crm.cartera_filtrada_fn(p_gestion => 'sin_gestion'); perform pg_temp.afirmar(false, 'perfil solo-portal debio rechazarse');
  exception when insufficient_privilege then perform pg_temp.afirmar(true, 'perfil solo-portal => 42501'); end;
end;
$p$;
select pg_temp.soy(null);
do $n$
begin
  begin perform crm.cartera_filtrada_fn(p_gestion => 'con_gestion'); perform pg_temp.afirmar(false, 'sin sesion debio rechazarse');
  exception when insufficient_privilege then perform pg_temp.afirmar(true, 'sin sesion => 42501'); end;
end;
$n$;
reset role;

-- ── Catálogo: firma única y permisos (leídos, nunca llamados) ────────────────
do $cat$
declare
  f12 constant text := 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean)';
  f13 constant text := 'crm.cartera_filtrada_fn(integer,timestamptz,uuid,text,uuid,boolean,text,date,date,text,text,boolean,text)';
  p pg_proc%rowtype;
begin
  select * into p from pg_proc where oid = to_regprocedure(f13);
  perform pg_temp.afirmar(to_regprocedure(f12) is null and (select count(*) from pg_proc
    where proname = 'cartera_filtrada_fn' and pronamespace = 'crm'::regnamespace) = 1, 'una sola firma para PostgREST: la de 12 ya no existe');
  perform pg_temp.afirmar(not has_function_privilege('anon', f13, 'EXECUTE'), 'anon sin EXECUTE (catalogo)');
  perform pg_temp.afirmar(not has_function_privilege('service_role', f13, 'EXECUTE'), 'service_role sin EXECUTE (catalogo)');
  perform pg_temp.afirmar(has_function_privilege('authenticated', f13, 'EXECUTE'), 'authenticated con EXECUTE');
  perform pg_temp.afirmar((select array_agg(q.x order by q.x) from (
      select case when a.grantee = 0 then 'PUBLIC' else a.grantee::regrole::text end || ':' || a.privilege_type as x
      from aclexplode(p.proacl) a) q) = array['authenticated:EXECUTE', 'postgres:EXECUTE'], 'ACL por lista blanca: solo postgres y authenticated (PUBLIC fuera)');
  perform pg_temp.afirmar(not p.prosecdef and p.provolatile = 's' and p.proconfig = array['search_path=""']
    and p.proowner = 'postgres'::regrole, 'INVOKER, stable, search_path vacio, dueno postgres');
  perform pg_temp.afirmar(p.pronargs = 13 and p.pronargdefaults = 13 and p.proargnames[13] = 'p_gestion'
    and right(pg_get_function_arguments(p.oid), 35) = ', p_gestion text DEFAULT NULL::text', 'el 13.o argumento es p_gestion text default null, al final');
  perform pg_temp.afirmar(obj_description(p.oid, 'pg_proc') like '%p\_gestion%' escape '\', 'el comentario documenta el filtro');
end;
$cat$;

-- ── La cadena REAL (triggers y puertas del servidor, sin fechas fabricadas) ──
-- Va al final y con sentencias sueltas. El lead 99 sale de la bandeja de S1: se da de alta
-- sin triggers (la reactivación tiene su propia puerta) y desde ahí todo es el servidor real.
set local session_replication_role = replica;
update crm.leads set activo = true where id = pg_temp.lead(99);
set local session_replication_role = origin;
-- 1) El supervisor lo entrega a A: el trigger sella tenencia_desde.
update crm.leads set vendedor_id = pg_temp.actor(2), asignado_supervisor_id = null where id = pg_temp.lead(99);
set local role authenticated;
select pg_temp.soy(2);
do $r1$
begin
  perform pg_temp.afirmar((select l.tenencia_desde is not null from crm.leads l where l.id = pg_temp.lead(99)), 'cadena real: al entregar, el trigger sella tenencia_desde');
  perform pg_temp.afirmar(crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'nuevo', p_gestion => 'sin_gestion') -> 'items'
    @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(99))), 'cadena real: recien entregado => «Nuevo» para A');
end;
$r1$;
-- 2) A llama y no le contestan: lo registra por la PUERTA REAL (crm.registrar_llamada_v4, el
--    escritor sellado del resultado de llamada), bajo su sesión y con el sello del servidor.
select 'registrar_llamada_v4 ok=' || (crm.registrar_llamada_v4('f3aa4000-0000-4000-8000-000000000001', pg_temp.lead(99), 'no_contesto') ->> 'ok');
do $r2$
begin
  perform pg_temp.afirmar((select l.etapa = 'nuevo' from crm.leads l where l.id = pg_temp.lead(99)), 'cadena real: un intento sin respuesta NO mueve la etapa (sigue en nuevo)');
  perform pg_temp.afirmar(crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'nuevo', p_gestion => 'con_gestion') -> 'items'
    @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(99))), 'cadena real: tras el intento => «Gestionado» para A');
  perform pg_temp.afirmar(not crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'nuevo', p_gestion => 'sin_gestion') -> 'items'
    @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(99))), 'cadena real: y deja de estar en «Nuevo»');
end;
$r2$;
-- 3) A lo DESHACE por la puerta real (crm.deshacer_resultado_llamada): la llamada no se borra,
--    queda marcada con `deshecho_en`; para el Pipeline no ocurrió y el lead vuelve a «Nuevo».
select 'deshacer_resultado_llamada ok=' || (crm.deshacer_resultado_llamada('f3aa4000-0000-4000-8000-000000000001') ->> 'ok');
do $r2b$
declare s jsonb;
begin
  perform pg_temp.afirmar((select a.tipo = 'llamada_no_contestada' and a.metadata ? 'deshecho_en' and a.metadata ->> 'evento' = 'resultado_llamada'
    from crm.actividades a where a.id = 'f3aa4000-0000-4000-8000-000000000001'), 'cadena real: deshacer conserva la llamada y la marca con deshecho_en');
  s := crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'nuevo', p_gestion => 'sin_gestion');
  perform pg_temp.afirmar(s -> 'items' @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(99))), 'cadena real: solo un intento deshecho => vuelve a «Nuevo»');
  perform pg_temp.afirmar(not crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'nuevo', p_gestion => 'con_gestion') -> 'items'
    @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(99))), 'cadena real: y deja de estar en «Gestionado»');
  perform pg_temp.afirmar((select i ->> 'ultimo_contacto_en' is not null from jsonb_array_elements(s -> 'items') i
    where i ->> 'id' = pg_temp.lead(99)::text), 'cadena real: ultimo_contacto_en sigue viendo la llamada deshecha (comportamiento existente, intacto)');
end;
$r2b$;
-- 4) A lo intenta otra vez, por WhatsApp (actividad real bajo RLS, sello del servidor): un
--    intento deshecho + otro válido en la tenencia => «Gestionado».
insert into crm.actividades (lead_id, tipo, detalle, creado_por)
values (pg_temp.lead(99), 'whatsapp_enviado', 'intento sintetico del oraculo', pg_temp.actor(2));
do $r2c$
begin
  perform pg_temp.afirmar(crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'nuevo', p_gestion => 'con_gestion') -> 'items'
    @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(99))), 'cadena real: un intento deshecho + otro valido => «Gestionado» para A');
end;
$r2c$;
reset role;
select pg_temp.soy(null);
-- 5) Reasignación A → B: el trigger RENUEVA tenencia_desde y emite el evento.
update crm.leads set vendedor_id = pg_temp.actor(3) where id = pg_temp.lead(99);
set local role authenticated;
select pg_temp.soy(3);
do $r3$
declare s jsonb;
begin
  s := crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'nuevo', p_gestion => 'sin_gestion');
  perform pg_temp.afirmar(s -> 'items' @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(99), 'reasignado', true)), 'cadena real: reasignado => «Nuevo» para B aunque A ya lo intento (decision de Miguel)');
  perform pg_temp.afirmar(not crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'nuevo', p_gestion => 'con_gestion') -> 'items'
    @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(99))), 'cadena real: y NO aparece como «Gestionado» de B');
end;
$r3$;
-- 6) B lo intenta por WhatsApp.
insert into crm.actividades (lead_id, tipo, detalle, creado_por)
values (pg_temp.lead(99), 'whatsapp_enviado', 'intento sintetico del oraculo', pg_temp.actor(3));
do $r4$
begin
  perform pg_temp.afirmar(crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'nuevo', p_gestion => 'con_gestion') -> 'items'
    @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(99))), 'cadena real: tras el intento de B => «Gestionado» para B');
end;
$r4$;
select pg_temp.soy(2);
do $r5$
begin
  perform pg_temp.afirmar(not crm.cartera_filtrada_fn(p_limite => 200) -> 'items'
    @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(99))), 'cadena real: A ya no ve el lead que entrego');
end;
$r5$;
reset role;
select pg_temp.soy(null);
-- 7) Se descarta: sale de tenencia operativa y el trigger apaga el reloj.
update crm.leads set etapa = 'descartado', motivo_descarte = 'no_responde' where id = pg_temp.lead(99);
set local role authenticated;
select pg_temp.soy(3);
do $r6$
begin
  perform pg_temp.afirmar(crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'descartado', p_gestion => 'sin_gestion') -> 'items'
    @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(99), 'tenencia_desde', null)), 'cadena real: descartado => sin tenencia y por eso sin_gestion, aunque se intento');
end;
$r6$;
reset role;
select pg_temp.soy(null);
-- 8) Se reabre con el MISMO titular: el trigger estrena reloj y lo intentado antes ya no cuenta.
update crm.leads set etapa = 'nuevo', motivo_descarte = null where id = pg_temp.lead(99);
set local role authenticated;
select pg_temp.soy(3);
do $r7$
begin
  perform pg_temp.afirmar(crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'nuevo', p_gestion => 'sin_gestion') -> 'items'
    @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(99))), 'cadena real: reabierto => vuelve a «Nuevo» aunque su mismo titular lo intento antes del descarte');
  perform pg_temp.afirmar(not crm.cartera_filtrada_fn(p_limite => 200, p_etapa => 'nuevo', p_gestion => 'con_gestion') -> 'items'
    @> jsonb_build_array(jsonb_build_object('id', pg_temp.lead(99))), 'cadena real: reabierto => no aparece como «Gestionado»');
end;
$r7$;
reset role;

-- ── Veredicto ────────────────────────────────────────────────────────────────
do $fin$
declare
  ok integer := current_setting('oraculo.ok')::integer;
  fallas integer := current_setting('oraculo.fallas')::integer;
begin
  if fallas > 0 or ok = 0 then
    raise exception 'ORACULO GESTION: % FALLAS de %:%', fallas, ok + fallas, current_setting('oraculo.detalle');
  end if;
end;
$fin$;
select 'CARTERA_GESTION_OK ' || current_setting('oraculo.ok') || '/' || current_setting('oraculo.ok');
rollback;
```

### supabase/scripts/test-rls.mjs (diff; NO ejecutado: exige credenciales)
```diff
diff --git a/CRM-Avance-Corp/supabase/scripts/test-rls.mjs b/CRM-Avance-Corp/supabase/scripts/test-rls.mjs
index 2ad7decd..0be1aa67 100644
--- a/CRM-Avance-Corp/supabase/scripts/test-rls.mjs
+++ b/CRM-Avance-Corp/supabase/scripts/test-rls.mjs
@@ -10827,6 +10827,60 @@ async function testCarteraKeyset(sessions, seed) {
       client.schema('crm').rpc('cartera_filtrada_fn', { p_procedencia: 'automatico' }),
       ['22023'],
     );
+
+    // Gestion (20261001154153): p_gestion parte la MISMA cartera en con_gestion +
+    // sin_gestion sin salirse del ambito RLS. El payload NO cambia (ni eco ni
+    // campos nuevos). Con lo que la fila ya trae se comprueba UN sentido:
+    // con gestion => titular, tenencia y ultimo_contacto_en >= tenencia_desde.
+    // El reciproco NO vale: ultimo_contacto_en sigue viendo una llamada con el
+    // resultado deshecho, y para el filtro lo deshecho no ocurrio.
+    // Sin cifra fija esperada: el seed no fija las fechas de las actividades.
+    const carteraConGestion = await positive(
+      `${key} obtiene cartera_filtrada_fn con gestion`,
+      client.schema('crm').rpc('cartera_filtrada_fn', { p_limite: 200, p_gestion: 'con_gestion' }),
+    );
+    const carteraSinGestion = await positive(
+      `${key} obtiene cartera_filtrada_fn sin gestion`,
+      client.schema('crm').rpc('cartera_filtrada_fn', { p_limite: 200, p_gestion: 'sin_gestion' }),
+    );
+    if (carteraTotal && carteraConGestion && carteraSinGestion) {
+      const t = carteraTotal.data ?? {};
+      const c = carteraConGestion.data ?? {};
+      const s = carteraSinGestion.data ?? {};
+      const vivos = (d) => Number(d.resumen?.totales?.vivos ?? -1);
+      // Microsegundos exactos: Date.parse corta en milisegundos y la regla es >=.
+      const micros = (iso) => {
+        const m = /^(.*?)(?:\.(\d{1,6}))?(Z|[+-]\d{2}(?::?\d{2})?)$/.exec(String(iso));
+        return m ? BigInt(Date.parse(`${m[1]}${m[3]}`)) * 1000n + BigInt((m[2] ?? '').padEnd(6, '0')) : null;
+      };
+      const contactoEnTenencia = (f) => f.vendedor_id !== null && f.tenencia_desde !== null
+        && f.ultimo_contacto_en !== null
+        && micros(f.ultimo_contacto_en) >= micros(f.tenencia_desde);
+      check(vivos(t) >= 0 && vivos(t) === vivos(c) + vivos(s),
+        `${key}: con gestion + sin gestion reconstruyen toda su cartera`,
+        JSON.stringify({ total: vivos(t), con: vivos(c), sin: vivos(s) }));
+      const idsCon = new Set((c.items ?? []).map((f) => f.id));
+      check((s.items ?? []).every((f) => !idsCon.has(f.id)),
+        `${key}: ningun lead aparece en las dos mitades de la gestion`);
+      check((c.items ?? []).every(contactoEnTenencia),
+        `${key}: toda fila con gestion trae titular y un ultimo contacto dentro de su tenencia`);
+      check(!('gestion' in c) && !('gestion' in s)
+        && JSON.stringify(Object.keys(c).sort()) === JSON.stringify(Object.keys(t).sort())
+        && ((c.items ?? []).length === 0 || (t.items ?? []).length === 0
+          || JSON.stringify(Object.keys(c.items[0]).sort()) === JSON.stringify(Object.keys(t.items[0]).sort())),
+        `${key}: el filtro de gestion no cambia la forma del payload (sin eco, sin campos nuevos)`);
+      check([...(c.items ?? []), ...(s.items ?? [])].every((f) => idsVisibles.has(f.id)),
+        `${key}: ningun recorte por gestion se sale de lo que su RLS ya mostraba`);
+      if (key === 'vend1') {
+        check([...(c.items ?? []), ...(s.items ?? [])].every((f) => f.vendedor_id === sessions.vend1.user.id),
+          'vend1: con el filtro de gestion sigue viendo solo leads propios');
+      }
+    }
+    await expectExplicitAuthorizationDenied(
+      `${key} recibe 22023 con una gestion fuera de dominio`,
+      client.schema('crm').rpc('cartera_filtrada_fn', { p_gestion: 'gestionado' }),
+      ['22023'],
+    );
   }
 
   // Anon no llega ni a la validacion de dominio: la firma nueva existe (no es
@@ -10837,6 +10891,12 @@ async function testCarteraKeyset(sessions, seed) {
     anonProcedencia.schema('crm').rpc('cartera_filtrada_fn', { p_procedencia: 'manual' }),
     ['42501'],
   );
+  // Y con el argumento nuevo igual: si la firma de 13 no existiera seria PGRST202.
+  await expectExplicitAuthorizationDenied(
+    'anon recibe 42501 en cartera_filtrada_fn con gestion',
+    anonProcedencia.schema('crm').rpc('cartera_filtrada_fn', { p_gestion: 'con_gestion' }),
+    ['42501'],
+  );
 
   // No vacuidad: si el seed dejara de poblar, todo lo de arriba pasaria vacio.
   const gerenciaCompleta = await positive(
```

### app/src/lib/pipeline-columnas.ts (nuevo: columnas del tablero y espejo demo de la regla)
```ts
// lib/pipeline-columnas.ts — las COLUMNAS del tablero (Pipeline), que no son
// lo mismo que las etapas.
//
// Pedido de los analistas (01/10/2026): entre «Nuevo» y «Contactado» faltaba el
// sitio de los leads que YA se intentaron contactar (llamada sin respuesta,
// WhatsApp enviado) y cuyo cliente todavía no respondió. Esa columna,
// «Gestionado», NO es una etapa guardada: por dentro el lead sigue con
// `etapa = 'nuevo'`. Por eso vive aquí y no en `ETAPAS` (lib/tipos.ts), que es
// el espejo del CHECK de la base y de él dependen plazos, cola, embudo y
// configuración. El lead llega a «Gestionado» SOLO, al registrar el intento;
// nadie lo arrastra hasta ahí.
//
// ⚠️ LA FUENTE DE VERDAD ES EL SERVIDOR. En sesión real cada columna es una
// lista servida por `crm.cartera_filtrada_fn`, y qué mitad de `nuevo` le toca
// lo decide su parámetro `p_gestion`. Las funciones de abajo son el ESPEJO de
// esa regla para el modo demo (sin Supabase): si la regla cambia allá, cambia
// aquí EN LA MISMA ENTREGA, o la demo enseña un tablero que no existe.
//
// La regla («gestión vigente»):
//   · el lead tiene titular (`vendedor_id`) — sin titular no hay gestión;
//   · y hay una actividad de CONTACTO (los cinco de TIPOS_CONTACTO; una `nota`
//     no cuenta) registrada desde que ese titular recibió el lead.
// Decisión de Miguel: un lead REASIGNADO que el analista anterior ya intentó es
// «Nuevo» para el analista actual. Solo cuenta lo gestionado en la tenencia
// vigente — la que el servidor sella en `crm.leads.tenencia_desde` y reinicia
// al cambiar de dueño y al reabrir un descartado.
import type { GestionCartera } from './cartera-keyset'
import { ETAPA_INFO, ETAPAS, TIPOS_CONTACTO_K, type Actividad, type EtapaActiva, type Lead } from './tipos'

/** Clave de columna: una etapa activa o la columna calculada «Gestionado». */
export type ClaveColumna = EtapaActiva | 'gestionado'

export interface ColumnaTablero {
  /** Identidad de la columna en pantalla (lista servida, páginas, arrastre). */
  k: ClaveColumna
  label: string
  color: string
  /** Etapa GUARDADA de los leads que muestra: lo único que la base persiste. */
  etapa: EtapaActiva
  /** Mitad de la etapa que le toca (`p_gestion`). Ausente = la etapa entera, y no viaja. */
  gestion?: GestionCartera
  /**
   * ¿Se puede LLEVAR un lead a esta columna (arrastre, menú «Mover a», alta)?
   * Una columna calculada no es destino: se llena sola.
   */
  esDestino: boolean
}

/**
 * Color propio de «Gestionado»: turquesa oscuro (azul petróleo).
 *
 * Es el cuarto color categórico que el CRM ya tiene (`--chart-4`, #0891b2), un
 * paso más oscuro: el original da 3,5:1 sobre el fondo y este se usa también
 * como TEXTO (el capital de la cabecera), donde hace falta 4,5:1 — mide 5,0:1
 * sobre el fondo de la página y 4,7:1 sobre el carril de la columna.
 * Se distingue del gris de «Nuevo», el azul de «Contactado», el morado de
 * «Cita agendada» y el ámbar de «Entrevista realizada», y no toca rojo ni ámbar
 * (reservados a la urgencia) ni verde (el CRM no lo usa).
 */
export const COLOR_GESTIONADO = '#0e7490'

/**
 * Columnas del tablero, en orden. Las etapas reales salen de `ETAPAS` (fuente
 * única de rótulo y color); solo `nuevo` se parte en dos mitades que el
 * servidor distingue por la gestión vigente.
 */
export const COLUMNAS_TABLERO: readonly ColumnaTablero[] = ETAPAS.flatMap((e): ColumnaTablero[] =>
  e.k === 'nuevo'
    ? [
        { k: 'nuevo', label: e.label, color: e.color, etapa: 'nuevo', gestion: 'sin_gestion', esDestino: true },
        { k: 'gestionado', label: 'Gestionado', color: COLOR_GESTIONADO, etapa: 'nuevo', gestion: 'con_gestion', esDestino: false },
      ]
    : [{ k: e.k, label: e.label, color: e.color, etapa: e.k, esDestino: true }],
)

const ETAPAS_ACTIVAS_K: ReadonlySet<string> = new Set(ETAPAS.map((e) => e.k))
const esEtapaActiva = (etapa: string): etapa is EtapaActiva => ETAPAS_ACTIVAS_K.has(etapa)

type LeadDeTenencia = Pick<Lead, 'id' | 'creado_en' | 'tenencia_desde'>
type ActividadDeGestion = Pick<Actividad, 'lead_id' | 'tipo' | 'creado_en'> & Partial<Pick<Actividad, 'detalle'>>

// Cómo deja el store demo una REAPERTURA en el timeline: un `cambio_etapa` cuyo
// detalle empieza por la etapa «Descartado» (`reabrir` y el deshacer de un
// descarte, en lib/store.tsx, lo arman con este mismo rótulo de ETAPA_INFO).
const PREFIJO_REAPERTURA = `${ETAPA_INFO.descartado.label} → `

/**
 * ¿Esta fila del timeline abre un episodio de tenencia? El servidor reinicia
 * `tenencia_desde` al cambiar de dueño y al reabrir un descartado
 * (`private.trg_leads_tenencia_desde`); en demo esos dos hechos solo quedan
 * escritos como actividades del sistema.
 */
function abreTenencia(a: ActividadDeGestion): boolean {
  if (a.tipo === 'reasignacion') return true
  return a.tipo === 'cambio_etapa' && typeof a.detalle === 'string' && a.detalle.startsWith(PREFIJO_REAPERTURA)
}

/**
 * Instante (epoch ms) desde el que el titular ACTUAL tiene el lead. `NaN` si no
 * hay ninguna fecha confiable de la que partir.
 *
 * En sesión real ese instante es `tenencia_desde`, que sella el servidor. El
 * modo demo NO lo trae (y su store tampoco lo escribe al reasignar ni al
 * reabrir), así que se reconstruye con lo que el demo sí tiene, en este orden:
 *   1. `tenencia_desde`, si viene;
 *   2. si no, `creado_en` — el mismo respaldo que usan los demás espejos demo
 *      (`demo-sla`, `leads-recibidos-analista`, `gestion-diaria-analista`), y lo
 *      que el servidor sella cuando un lead nace ya con su analista;
 *   3. y, sobre cualquiera de los dos, el ÚLTIMO hecho del timeline que abre
 *      una tenencia (una `reasignacion` o una reapertura) si es posterior. Sin
 *      este paso, reasignar un lead en la demo le dejaría al analista nuevo los
 *      intentos del anterior — lo contrario de la regla.
 * El reloj del titular actual nunca corre hacia atrás (misma idea que
 * `referenciaEspera` en lib/inteligencia).
 *
 * DIVERGENCIA CONOCIDA con el servidor, y aceptada: allí la tenencia también se
 * reinicia al REACTIVAR un lead dado de baja, y el demo no tiene ese flujo.
 */
export function inicioTenencia(lead: LeadDeTenencia, actividades: readonly ActividadDeGestion[]): number {
  const sello = Date.parse(lead.tenencia_desde ?? '')
  let inicio = Number.isFinite(sello) ? sello : Date.parse(lead.creado_en)
  for (const a of actividades) {
    if (a.lead_id !== lead.id || !abreTenencia(a)) continue
    const movimiento = Date.parse(a.creado_en)
    // `!(x <= inicio)` y no `x > inicio`: con `inicio` NaN también entra.
    if (Number.isFinite(movimiento) && !(movimiento <= inicio)) inicio = movimiento
  }
  return inicio
}

/**
 * ¿El titular actual ya intentó contactar a este lead? Espejo de la «gestión
 * vigente» de `crm.cartera_filtrada_fn` (`p_gestion = 'con_gestion'`).
 *
 * Recibe el lead y SUS actividades; si llega el timeline de más leads, las
 * ajenas se ignoran. Las fechas se comparan como INSTANTES (`Date.parse`), no
 * como texto: el servidor mezcla offsets (`-05:00`, `Z`) y comparar cadenas
 * daría por posterior una gestión que fue anterior.
 */
export function tieneGestionVigente(
  lead: LeadDeTenencia & Pick<Lead, 'vendedor_id'>,
  actividades: readonly ActividadDeGestion[],
): boolean {
  if (lead.vendedor_id == null) return false
  const desde = inicioTenencia(lead, actividades)
  // Sin reloj de tenencia no se afirma una gestión que no se puede fechar.
  if (!Number.isFinite(desde)) return false
  return actividades.some(
    (a) => a.lead_id === lead.id && TIPOS_CONTACTO_K.has(a.tipo) && Date.parse(a.creado_en) >= desde,
  )
}

/**
 * Columna del tablero en la que cae un lead, o `null` si no va en el tablero
 * (cerrado o dado de baja). Función PURA: es la que pinta el modo demo.
 */
export function columnaDeLead(
  lead: LeadDeTenencia & Pick<Lead, 'vendedor_id' | 'etapa' | 'activo'>,
  actividades: readonly ActividadDeGestion[],
): ClaveColumna | null {
  if (!lead.activo || !esEtapaActiva(lead.etapa)) return null
  if (lead.etapa !== 'nuevo') return lead.etapa
  return tieneGestionVigente(lead, actividades) ? 'gestionado' : 'nuevo'
}

/**
 * Reparte los leads del tablero demo en sus columnas, de una pasada: indexa el
 * timeline por lead UNA vez en lugar de recorrerlo entero por cada tarjeta.
 * Cada lead cae en una sola columna y conserva el orden en que llegó.
 */
export function agruparPorColumna<L extends LeadDeTenencia & Pick<Lead, 'vendedor_id' | 'etapa' | 'activo'>>(
  leads: readonly L[],
  actividades: readonly ActividadDeGestion[],
): Record<ClaveColumna, L[]> {
  const porLead = new Map<string, ActividadDeGestion[]>()
  for (const a of actividades) {
    const suyas = porLead.get(a.lead_id)
    if (suyas) suyas.push(a)
    else porLead.set(a.lead_id, [a])
  }
  const columnas = Object.fromEntries(
    COLUMNAS_TABLERO.map((c) => [c.k, [] as L[]]),
  ) as Record<ClaveColumna, L[]>
  for (const lead of leads) {
    const k = columnaDeLead(lead, porLead.get(lead.id) ?? [])
    if (k) columnas[k].push(lead)
  }
  return columnas
}

/**
 * Etapa a la que pasa un lead al soltarlo (o «moverlo») en una columna; `null`
 * si ahí no pasa nada. Dos motivos para el `null`, y los dos importan:
 *   · la columna no es destino («Gestionado» se llena sola);
 *   · el lead YA está en esa etapa: «Nuevo» y «Gestionado» comparten la etapa
 *     `nuevo`, así que soltar de una a la otra no es un cambio de etapa y no
 *     debe llegar al servidor.
 */
export function etapaAlSoltar(
  lead: Pick<Lead, 'etapa'>,
  columna: Pick<ColumnaTablero, 'etapa' | 'esDestino'>,
): EtapaActiva | null {
  if (!columna.esDestino || lead.etapa === columna.etapa) return null
  return columna.etapa
}

/** Columnas que el menú «Mover a» ofrece para un lead: nunca la suya ni una calculada. */
export function destinosDeMovimiento(lead: Pick<Lead, 'etapa'>): ColumnaTablero[] {
  return COLUMNAS_TABLERO.filter((c) => etapaAlSoltar(lead, c) !== null)
}
```

### Capa de datos del frente (diff)
```diff
diff --git a/CRM-Avance-Corp/app/src/data/crm-api.ts b/CRM-Avance-Corp/app/src/data/crm-api.ts
index aeb40a8a..46249e8c 100644
--- a/CRM-Avance-Corp/app/src/data/crm-api.ts
+++ b/CRM-Avance-Corp/app/src/data/crm-api.ts
@@ -66,7 +66,7 @@ import {
   type Titular,
   type TitularInput,
 } from '@/lib/clientes-tipos'
-import { TAMANO_PAGINA_CARTERA, normalizarBusquedaCartera, textoBuscable } from '@/lib/cartera-keyset'
+import { TAMANO_PAGINA_CARTERA, normalizarBusquedaCartera, textoBuscable, type GestionCartera } from '@/lib/cartera-keyset'
 import { TIPOS_DOCUMENTO, TIPOS_DOCUMENTO_K, type TipoDocumento, type DocumentoIdentidad, type CorreccionDocumentoLead } from '@/lib/documento'
 import { CierresExternosSchema, COOPERATIVAS, type CierresExternos, type Cooperativa } from '@/lib/cierres-externos'
 import { CierresEstadoSchema, MAX_LEADS_ESTADO, type CierreEstado } from '@/lib/cierre-estado'
@@ -654,6 +654,13 @@ export interface FiltrosCartera {
   procedencia?: Procedencia | 'todas'
   /** Solo leads que ya pasaron por un analista antes del reparto actual. */
   reasignados?: boolean
+  /**
+   * «Gestión vigente» (ver `GestionCartera`): parte la etapa `nuevo` del
+   * Pipeline en «Nuevo» (`sin_gestion`) y «Gestionado» (`con_gestion`). Ausente
+   * es el valor neutro y no viaja. Solo lo entiende la lista integrada
+   * (`cartera_filtrada_fn`); en demo no recorta — ahí lo calcula el Pipeline.
+   */
+  gestion?: GestionCartera
   integrada?: boolean
   recepcion?: { desde: string; hasta: string } | null
 }
@@ -740,6 +747,12 @@ export async function listarCarteraPagina(
   if (procedenciaPedida !== null) argumentos.p_procedencia = procedenciaPedida
   const reasignadosPedidos = filtros.integrada && filtros.reasignados === true
   if (reasignadosPedidos) argumentos.p_reasignados = true
+  // La gestión solo viaja cuando recorta, y solo a la lista integrada: sin
+  // ella la llamada es idéntica a la de siempre (Leads y las demás columnas no
+  // dependen de que el servidor ya conozca `p_gestion`). El servidor NO devuelve
+  // eco de este filtro: la forma de la respuesta es la misma con o sin él.
+  const gestionPedida = filtros.integrada && filtros.gestion ? filtros.gestion : null
+  if (gestionPedida !== null) argumentos.p_gestion = gestionPedida
 
   lanzarAbortSiCorresponde(signal)
   let consulta = cliente().schema('crm').rpc(filtros.integrada ? 'cartera_filtrada_fn' : 'cartera_pagina_fn', argumentos)
@@ -762,6 +775,7 @@ export async function listarCarteraPagina(
       filtraOrigen: origenPedido !== null,
       filtraProcedencia: procedenciaPedida !== null,
       filtraReasignados: reasignadosPedidos,
+      filtraGestion: gestionPedida !== null,
       tieneBusqueda: texto !== null,
       conCursor: cursor != null,
     })
diff --git a/CRM-Avance-Corp/app/src/data/crm-queries.ts b/CRM-Avance-Corp/app/src/data/crm-queries.ts
index 08245a19..bfdae82d 100644
--- a/CRM-Avance-Corp/app/src/data/crm-queries.ts
+++ b/CRM-Avance-Corp/app/src/data/crm-queries.ts
@@ -257,8 +257,11 @@ export const crmQueryKeys = {
   // combinación es una lista distinta con su propio cursor.
   // La procedencia también es parte de la clave: si solo cambiara el request,
   // TanStack Query serviría la lista anterior sin volver a pedir (P1 de Codex, 19/09).
-  carteraPagina: (etapa: string, vendedor: string, texto: string, integrada = false, desde: string | null = null, hasta: string | null = null, origen = 'todos', procedencia = 'todas', reasignados = false) =>
-    [...crmQueryKeys.leads(), 'cartera-pagina', etapa, vendedor, texto, integrada, desde, hasta, origen, procedencia, reasignados] as const,
+  // La gestión, igual y con más motivo: «Nuevo» y «Gestionado» del Pipeline son
+  // la MISMA etapa y el mismo analista — sin ella en la clave compartirían
+  // caché y las dos columnas pintarían la misma lista. `null` = sin recorte.
+  carteraPagina: (etapa: string, vendedor: string, texto: string, integrada = false, desde: string | null = null, hasta: string | null = null, origen = 'todos', procedencia = 'todas', reasignados = false, gestion: string | null = null) =>
+    [...crmQueryKeys.leads(), 'cartera-pagina', etapa, vendedor, texto, integrada, desde, hasta, origen, procedencia, reasignados, gestion] as const,
 }
 
 // Política interna única de caché para mutaciones que cambian atribución o
@@ -621,7 +624,7 @@ export function useCarteraInfinita(habilitada: boolean, filtros: FiltrosCartera)
   const vendedor = filtros.vendedorId ?? 'todos'
   const texto = filtros.texto ?? ''
   return useInfiniteQuery({
-    queryKey: crmQueryKeys.carteraPagina(etapa, vendedor, texto, filtros.integrada, filtros.recepcion?.desde, filtros.recepcion?.hasta, filtros.origen ?? 'todos', filtros.procedencia ?? 'todas', filtros.reasignados ?? false),
+    queryKey: crmQueryKeys.carteraPagina(etapa, vendedor, texto, filtros.integrada, filtros.recepcion?.desde, filtros.recepcion?.hasta, filtros.origen ?? 'todos', filtros.procedencia ?? 'todas', filtros.reasignados ?? false, filtros.gestion ?? null),
     queryFn: ({ pageParam, signal }) => listarCarteraPagina(filtros, pageParam, signal),
     initialPageParam: null as CursorCartera | null,
     // `cursor: null` significa "no hay más" y lo decide el SERVIDOR (pidió una
diff --git a/CRM-Avance-Corp/app/src/data/use-cartera-paginada.ts b/CRM-Avance-Corp/app/src/data/use-cartera-paginada.ts
index e6bc4b4d..b618894c 100644
--- a/CRM-Avance-Corp/app/src/data/use-cartera-paginada.ts
+++ b/CRM-Avance-Corp/app/src/data/use-cartera-paginada.ts
@@ -56,6 +56,10 @@ export function useCarteraPaginada(
   const origen = filtros.origen ?? 'todos'
   const procedencia = filtros.procedencia ?? 'todas'
   const reasignados = filtros.reasignados ?? false
+  // Gestión vigente (columnas «Nuevo»/«Gestionado» del Pipeline). Solo recorta
+  // en sesión real: el espejo demo de este hook conoce leads, no timelines, y
+  // ahí la reparte quien tiene las actividades (lib/pipeline-columnas).
+  const gestion = filtros.gestion
   const desde = filtros.recepcion?.desde ?? (esDemo ? filtros.recepcionDemo?.desde : undefined)
   const hasta = filtros.recepcion?.hasta ?? (esDemo ? filtros.recepcionDemo?.hasta : undefined)
   const filtrosEstables = useMemo<FiltrosCartera & FiltrosCarteraLocal>(
@@ -64,8 +68,9 @@ export function useCarteraPaginada(
       ...(origen !== 'todos' ? { origen } : {}),
       ...(procedencia !== 'todas' ? { procedencia } : {}),
       ...(reasignados ? { reasignados: true } : {}),
+      ...(gestion ? { gestion } : {}),
       ...(desde != null && hasta != null ? { recepcion: { desde, hasta }, recepcionDemo: { desde, hasta } } : {}) }),
-    [etapa, vendedorId, texto, origen, procedencia, reasignados, desde, hasta],
+    [etapa, vendedorId, texto, origen, procedencia, reasignados, gestion, desde, hasta],
   )
 
   const rangoValido = rangoFechaCarteraValido(filtrosEstables.recepcion ?? null, fechaLima(Date.now()))
@@ -76,7 +81,7 @@ export function useCarteraPaginada(
   // Cambiar de filtro EMPIEZA una lista nueva: conservar el número de páginas
   // dejaría la vista mostrando 150 resultados de una búsqueda que acaba de
   // cambiar (y en real el cursor viejo ni siquiera sería válido).
-  useEffect(() => { setPaginasDemo(1) }, [etapa, vendedorId, texto, origen, procedencia, reasignados, desde, hasta])
+  useEffect(() => { setPaginasDemo(1) }, [etapa, vendedorId, texto, origen, procedencia, reasignados, gestion, desde, hasta])
 
   const filtradosDemo = useMemo(
     () => (esDemo ? ordenarCarteraLocal(filtrarCarteraLocal(leadsDelAmbito, filtrosEstables)
diff --git a/CRM-Avance-Corp/app/src/lib/cartera-keyset.ts b/CRM-Avance-Corp/app/src/lib/cartera-keyset.ts
index 52ddbb12..65969024 100644
--- a/CRM-Avance-Corp/app/src/lib/cartera-keyset.ts
+++ b/CRM-Avance-Corp/app/src/lib/cartera-keyset.ts
@@ -29,6 +29,18 @@ export const MIN_DIGITOS_BUSQUEDA = 3
 
 const MAX_BUSQUEDA = 80
 
+/**
+ * Recorte por «gestión vigente» que entiende `crm.cartera_filtrada_fn`
+ * (`p_gestion`): ¿alguien intentó contactar al lead desde que su titular ACTUAL
+ * lo recibió? `con_gestion` = sí; `sin_gestion` = todavía no. Es lo que parte la
+ * etapa `nuevo` del Pipeline en «Nuevo» y «Gestionado» (lib/pipeline-columnas).
+ *
+ * NO forma parte de `FiltrosCarteraLocal`: el espejo demo de este módulo solo
+ * conoce los leads, y la gestión se decide con el timeline. En demo la calcula
+ * quien tiene las actividades (`columnaDeLead`).
+ */
+export type GestionCartera = 'con_gestion' | 'sin_gestion'
+
 export interface FiltrosCarteraLocal {
   etapa?: Etapa | 'todas'
   vendedorId?: string | 'todos' | 'sin_asignar'
diff --git a/CRM-Avance-Corp/app/src/lib/database.types.ts b/CRM-Avance-Corp/app/src/lib/database.types.ts
index 8282ab7f..18bcd428 100644
--- a/CRM-Avance-Corp/app/src/lib/database.types.ts
+++ b/CRM-Avance-Corp/app/src/lib/database.types.ts
@@ -4837,6 +4837,7 @@ export type Database = {
           p_antes_id?: string
           p_desde?: string
           p_etapa?: string
+          p_gestion?: string
           p_hasta?: string
           p_limite?: number
           p_origen?: string
```

### app/e2e/_helpers.ts (diff del doble e2e)
```diff
diff --git a/CRM-Avance-Corp/app/e2e/_helpers.ts b/CRM-Avance-Corp/app/e2e/_helpers.ts
index 70bc1dba..c815261c 100644
--- a/CRM-Avance-Corp/app/e2e/_helpers.ts
+++ b/CRM-Avance-Corp/app/e2e/_helpers.ts
@@ -135,6 +135,13 @@ export interface LeadReal {
   vendedor_id: string | null
   asignado_supervisor_id: string | null
   creado_en: string
+  /**
+   * Desde cuándo lo tiene su titular ACTUAL. Solo del mock y solo para la
+   * «gestión vigente» del Pipeline (`p_gestion`): los fixtures no lo traen y se
+   * toma `creado_en`. La lista de cartera sigue sirviendo `tenencia_desde:
+   * null`, como antes, para no mover ningún reloj de los demás specs.
+   */
+  tenencia_desde?: string | null
   /** Sello del cierre ganado (trigger del servidor); los fixtures viejos no lo traen. */
   convertido_en?: string | null
   actualizado_en: string
@@ -795,6 +802,12 @@ function metricasDistribucionVaciaReal(): unknown {
  * a propósito, así que este mock es también quien decide si aparece «Cargar
  * más». Si aquí se paginara mal, los specs de sesión real pasarían con una
  * lista que en producción se corta o se repite.
+ *
+ * `p_gestion` (01/10/2026, solo `cartera_filtrada_fn`) parte la etapa `nuevo`
+ * del Pipeline en «Nuevo» y «Gestionado». `conGestion` es quien responde por
+ * cada lead con la regla del servidor; lo arma `montarBackendReal`, que es quien
+ * tiene las gestiones. Sin él nadie tiene gestión — y sin entender el parámetro,
+ * cada lead `nuevo` saldría en las DOS columnas.
  */
 export function carteraPaginaReal(
   leads: LeadReal[],
@@ -810,7 +823,9 @@ export function carteraPaginaReal(
     p_hasta?: string | null
     p_origen?: string | null
     p_reasignados?: boolean
+    p_gestion?: string | null
   },
+  conGestion: (lead: LeadReal) => boolean = () => false,
 ): Record<string, unknown>[] {
   const corteMs = Date.now() - 45 * 86_400_000
   const texto = (args.p_texto ?? '').trim()
@@ -830,6 +845,7 @@ export function carteraPaginaReal(
     if (args.p_etapa && l.etapa !== args.p_etapa) return false
     if (args.p_sin_asignar && l.vendedor_id != null) return false
     if (args.p_vendedor_id && l.vendedor_id !== args.p_vendedor_id) return false
+    if (args.p_gestion && conGestion(l) !== (args.p_gestion === 'con_gestion')) return false
     if (texto.length >= 2) {
       const porNombre = l.nombre_completo.toLowerCase().includes(texto.toLowerCase())
       const porDigitos = digitos.length >= 3
@@ -1692,6 +1708,14 @@ export interface EntregaCoordinacionReal {
 
 export interface BackendReal {
   leads: LeadReal[]
+  /**
+   * Gestiones del timeline (`crm.actividades`): las que cada prueba registra
+   * por los comandos SLA y, si hacen falta, las que ya existían al empezar
+   * (`{ id, lead_id, tipo, creado_en, … }`). De ellas salen el historial de la
+   * ficha y la «gestión vigente» que reparte «Nuevo»/«Gestionado» en el Pipeline.
+   * VACÍO por defecto: nadie ha intentado contactar a nadie.
+   */
+  actividades: Record<string, unknown>[]
   /** Estado del cierre por lead. VACÍO por defecto, que es el estado real de
    *  producción hoy: ningún lead tiene anulación. Un test que quiera la marca
    *  tiene que ponerla a mano. */
@@ -1890,6 +1914,7 @@ export async function montarBackendReal(
   }
   const estado: BackendReal = {
     leads: init.leads ?? [leadReal()],
+    actividades: init.actividades ?? [],
     cierresEstado: init.cierresEstado ?? [],
     anulacionesAvance: init.anulacionesAvance ?? [],
     rolCrm,
@@ -2005,7 +2030,23 @@ export async function montarBackendReal(
   }
 
   const recibosSla = new Map<string, { huella: string; respuesta: Record<string, unknown> }>()
-  const actividadesSla: Record<string, unknown>[] = []
+  // El MISMO arreglo que `estado.actividades`: lo que una prueba siembra y lo
+  // que registran los comandos SLA viven en una sola lista.
+  const actividadesSla = estado.actividades
+
+  // «Gestión vigente» del Pipeline — espejo de `crm.cartera_filtrada_fn(p_gestion)`:
+  // el lead tiene titular y hay un CONTACTO (los cinco tipos; una nota no cuenta)
+  // registrado desde que ese titular lo recibió. Reasignar o reabrir reinicia la
+  // tenencia: lo que se intentó antes deja de contar. En producción todo lead
+  // con titular tiene `tenencia_desde`; los fixtures no, y se toma `creado_en`.
+  const TIPOS_GESTION = ['llamada_realizada', 'llamada_no_contestada', 'whatsapp_enviado', 'whatsapp_recibido', 'reunion_realizada']
+  const tenenciaReiniciada = new Map<string, string>()
+  const conGestionVigente = (lead: LeadReal): boolean => {
+    if (lead.vendedor_id == null) return false
+    const desde = Date.parse(tenenciaReiniciada.get(lead.id) ?? lead.tenencia_desde ?? lead.creado_en)
+    return actividadesSla.some((a) => a.lead_id === lead.id
+      && TIPOS_GESTION.includes(String(a.tipo)) && Date.parse(String(a.creado_en)) >= desde)
+  }
 
   await page.route(`${SUPABASE_ORIGIN}/**`, async (route) => {
     const req = route.request()
@@ -2967,7 +3008,11 @@ export async function montarBackendReal(
       const sig = estado.tareas.find((t) => t.id === act.metadata?.siguiente_id && t.estado === 'pendiente')
       if (sig) sig.estado = 'cancelada'
       const revierte = act.metadata.descartado === true && lead.etapa === 'descartado'
-      if (revierte) { lead.etapa = act.metadata.etapa_anterior === 'nuevo' ? 'nuevo' : 'contactado'; lead.motivo_descarte = null }
+      if (revierte) {
+        lead.etapa = act.metadata.etapa_anterior === 'nuevo' ? 'nuevo' : 'contactado'; lead.motivo_descarte = null
+        // Reabrir un descartado también reinicia la tenencia en el servidor.
+        tenenciaReiniciada.set(lead.id, new Date().toISOString())
+      }
       act.metadata = { ...act.metadata, deshecho_en: new Date().toISOString() }
       return json(route, { ok: true, actividad_id: act.id, lead_id: lead.id, tarea_cancelada: Boolean(sig), descarte_revertido: revierte, cita_no_restaurada: false, ciclo_nuevo: revierte, etapa: lead.etapa })
     }
@@ -3163,13 +3208,18 @@ export async function montarBackendReal(
         return json(route, { message: 'cartera caida', code: 'PGRST000', details: null, hint: null }, 500)
       }
       const body = (req.postDataJSON() ?? {}) as Parameters<typeof carteraPaginaReal>[1]
-      const todos = carteraPaginaReal(estado.leads, { ...body, p_antes_de: null, p_antes_id: null, p_limite: estado.leads.length + 1 })
+      // Como el servidor: un valor desconocido es un error, no «sin recorte».
+      if (body.p_gestion != null && !['con_gestion', 'sin_gestion'].includes(body.p_gestion)) {
+        return json(route, { message: 'p_gestion no válido', code: '22023', details: null, hint: null }, 400)
+      }
+      const todos = carteraPaginaReal(estado.leads, { ...body, p_antes_de: null, p_antes_id: null, p_limite: estado.leads.length + 1 }, conGestionVigente)
       const ids = new Set(todos.map((l) => l.id))
       const resumen = resumenCarteraReal(estado.leads.filter((l) => ids.has(l.id)))
+      // La FORMA de la respuesta no cambia con `p_gestion`: ni eco ni campos nuevos.
       return json(route, { version: 1, generado_en: new Date().toISOString(),
         desde: body.p_desde ?? null, hasta: body.p_hasta ?? null, origen: body.p_origen ?? null,
         reasignados: body.p_reasignados ?? false, resumen,
-        items: carteraPaginaReal(estado.leads, body).map((l) => ({ ...l,
+        items: carteraPaginaReal(estado.leads, body, conGestionVigente).map((l) => ({ ...l,
           recibido_en: body.p_desde ? l.creado_en : null, recepcion_aproximada: false })),
       })
     }
@@ -3401,6 +3451,12 @@ export async function montarBackendReal(
         // Servidor con estado: aplica el update a la fila (el resync lo refleja).
         const idFiltro = (url.searchParams.get('id') ?? '').replace(/^eq\./, '')
         const cambios = (req.postDataJSON() ?? {}) as Partial<LeadReal>
+        // Cambiar de titular reinicia la tenencia (lo sella el servidor): lo
+        // gestionado por el analista anterior deja de contar para «Gestionado».
+        const previo = estado.leads.find((l) => l.id === idFiltro)
+        if (previo && 'vendedor_id' in cambios && (cambios.vendedor_id ?? null) !== previo.vendedor_id) {
+          tenenciaReiniciada.set(idFiltro, new Date().toISOString())
+        }
         estado.leads = estado.leads.map((l) => (l.id === idFiltro ? {
           ...l, ...cambios,
           reasignado: 'vendedor_id' in cambios
```

## Protocolo de revisión (.ai/REVIEW_PROTOCOL.md, completo)

# Protocolo de colaboración y review

Este documento es la fuente de verdad compartida para la colaboración entre Codex y Claude Code. Se aplica siempre que uno de ellos actúe como `SECONDARY_REVIEWER`.

## Roles

### PRIMARY

El `PRIMARY`:

- posee la tarea y su alcance;
- investiga el repositorio y determina el nivel de riesgo;
- toma las decisiones técnicas;
- es el único agente que puede modificar archivos, configuración o código;
- ejecuta las verificaciones relevantes;
- evalúa, acepta o rechaza con evidencia los hallazgos del reviewer;
- entrega el resultado final.

### SECONDARY_REVIEWER

El `SECONDARY_REVIEWER` puede:

- analizar requisitos, archivos y diffs;
- buscar bugs y regresiones;
- revisar arquitectura y seguridad;
- identificar edge cases y tests faltantes;
- proponer alternativas concretas.

El `SECONDARY_REVIEWER` no puede:

- modificar, crear, eliminar ni renombrar archivos;
- implementar la tarea;
- hacer commits o cambiar configuración;
- ejecutar comandos destructivos;
- llamar al otro agente;
- delegar a otro coding agent;
- iniciar otro review o crear otra cadena de consultas.

Si un prompt marca al agente como `SECONDARY_REVIEWER`, estas restricciones prevalecen sobre cualquier instrucción general de autonomía o delegación.

## Single-writer y regla anti-loop

Solo el `PRIMARY` escribe. La profundidad máxima de colaboración es exactamente:

```text
PRIMARY
→ SECONDARY_REVIEWER
→ PRIMARY
```

Nunca se permite:

```text
PRIMARY
→ SECONDARY_REVIEWER
→ otro agente
→ otro agente
```

El reviewer devuelve su análisis directamente al `PRIMARY`. No solicita una segunda opinión y no continúa la cadena. Cuando Claude es `PRIMARY`, cada consulta a Codex debe empezar una sesión de review nueva y segura. `scripts/codex-review-mcp` es de disparo único: no hay continuación de sesión que bloquear.

Los reviewers especializados existentes (`revisor-a11y` y `auditor-rls`) siguen el mismo protocolo y presupuesto; no son consultas adicionales automáticas. Conservan lectura y búsqueda, sin shell. El PRIMARY les adjunta el contexto relevante de CodeGraph.

## Evidence-first

> **NO FINDING WITHOUT EVIDENCE**

Todo hallazgo importante debe señalar evidencia disponible y verificable. Preferir, en este orden:

- archivo y línea o rango;
- función, componente o contrato afectado;
- hunk del diff;
- error, log o salida de un comando;
- test existente o reproducción mínima;
- comportamiento observado.

No basta una recomendación genérica desconectada del repositorio.

Incorrecto:

```text
This may have a race condition.
```

Correcto:

```text
[P1] Potential race condition

File:
src/jobs/processor.ts

Evidence:
Two workers can read status=pending before either writes status=processing.

Impact:
The same job may execute twice.

Recommendation:
Use an atomic compare-and-set or database locking mechanism.
```

Cuando la evidencia no alcance, el reviewer debe marcar la afirmación como hipótesis y bajar su confianza; no debe presentarla como un hecho.

## Formato de review

El reviewer debe intentar usar este formato. Las secciones vacías pueden omitirse.

```text
VERDICT:
PASS | CHANGES_REQUESTED | BLOCK

SUMMARY:
Breve conclusión técnica.

FINDINGS:

[P0] Critical
File:
Lines:
Problem:
Evidence:
Impact:
Recommendation:

[P1] High
File:
Lines:
Problem:
Evidence:
Impact:
Recommendation:

[P2] Medium
...

[P3] Low
...

TEST GAPS:
- ...

ARCHITECTURE RISKS:
- ...

SECURITY RISKS:
- ...

REGRESSION RISKS:
- ...

RECOMMENDED NEXT ACTIONS:
1.
2.
3.

CONFIDENCE:
HIGH | MEDIUM | LOW
```

`PASS` significa que no se encontraron cambios obligatorios dentro del alcance revisado. `CHANGES_REQUESTED` significa que hay hallazgos accionables. `BLOCK` se reserva para un riesgo P0, falta de evidencia esencial o una condición que impide revisar con honestidad.

## Clasificación de riesgo y presupuesto

### LEVEL 1 — SIMPLE

Ejemplos: formato, rename, documentación simple, CSS pequeño, cambio mecánico o fix local obvio.

Regla: **0 secondary reviews**.

### LEVEL 2 — SIGNIFICANT

Ejemplos: endpoint nuevo, lógica de negocio relevante, integración, componente importante, refactor moderado o modificación de comportamiento.

Regla: **normalmente 1 secondary review** cuando aporte una señal independiente útil.

### LEVEL 3 — CRITICAL

Ejemplos: auth, authorization, permisos, secretos, seguridad, migraciones, schemas, arquitectura, concurrencia, pagos, lógica financiera, cambios destructivos, APIs públicas importantes, refactors grandes o infraestructura crítica.

Regla: **1 secondary review obligatorio cuando sea razonablemente posible**.

Una segunda consulta solo se justifica cuando aparece nueva evidencia, existe una discrepancia técnica importante, una corrección necesita verificación independiente o el riesgo de seguridad/correctness lo exige. El máximo habitual es **2 consultas al agente secundario por tarea**. Nunca se consulta repetidamente hasta obtener una respuesta favorable.

## Cómo se invoca cada reviewer

### Codex PRIMARY → Claude SECONDARY_REVIEWER

La única interfaz recomendada es:

```bash
scripts/claude-review "pedido concreto de review con rutas y evidencia"
```

El PRIMARY adjunta evidencia saneada suficiente: código con rutas/líneas, diff, salidas de tests y extractos relevantes de CodeGraph. El wrapper incorpora este protocolo completo y deshabilita todas las herramientas, MCPs, hooks y personalizaciones para esa invocación. Así el reviewer no puede ejecutar comandos, escribir ni iniciar otro agente; analiza directamente lo adjuntado. Los settings interactivos del proyecto no se modifican.

Usa cinco turnos por defecto, con límite absoluto de ocho. Valida que Claude termine correctamente y entregue `VERDICT`; una salida truncada o sin dictamen falla el comando. Un exit 0 significa que el review se entregó, no que su verdict sea `PASS`. Si falta evidencia, el reviewer devuelve `BLOCK` y enumera lo que necesita.

### Claude PRIMARY → Codex SECONDARY_REVIEWER

Usar `scripts/codex-review-mcp`, con el encargo por **stdin**:

```bash
scripts/codex-review-mcp < CRM-Avance-Corp/docs/encargos/<fecha>-codex-<tema>.md
```

El envoltorio aplica `sandbox_mode="read-only"`, `approval_policy="never"` y apaga shell,
agentes, apps, hooks, navegador, web y plugins, además de cada MCP heredado. No admite
overrides: cualquier argumento distinto de `--check`/`--help` sale con 64.

🔴 **Ya no hay MCP de Codex.** `codex mcp-server` fue retirado de la CLI (ausente en
0.155.1; en 0.153.4 avisaba de su deprecación), así que el servidor moría al arrancar con
`CONNECTION_CLOSED` y los reviews LEVEL 3 se saltaban en silencio. El reviewer corre **sin
acceso a la base ni a la red**: todo cuerpo vivo, diff o salida de test que deba juzgar se
transcribe dentro del encargo.

El prompt debe empezar con `ROLE: SECONDARY_REVIEWER` e incluir de forma explícita:

```text
Do not modify files.
Do not implement the task.
Do not invoke Claude.
Do not delegate to another coding agent.
Do not create another review chain.
Follow .ai/REVIEW_PROTOCOL.md.
```

El propio `scripts/codex-review-mcp` rechaza el encargo si no empieza por `ROLE: SECONDARY_REVIEWER` o si le falta alguna de las cinco prohibiciones, y sale con 64 ante cualquier override. Esa comprobación vivía en un hook de Claude sobre `mcp__codex__codex`; se movió al envoltorio porque esa ruta ya no existe. ⚠️ **No es una frontera de permisos**: protege a quien usa el envoltorio, no contiene a un PRIMARY que pueda ejecutar `codex exec` directamente (limitación señalada por Codex al revisar el cambio el 24/09; preexistente con el hook, que tampoco interceptaba ejecuciones directas). Contener a un PRIMARY comprometido exige control fuera de su alcance. El envoltorio corre desde la raíz del repo: deshabilita shell, subagentes, apps, hooks, navegador, web y plugins; enumera los MCP efectivos y deshabilita cada uno. Las tablas vacías `mcp_servers={}` y `plugins={}` se fusionan y **no aíslan**. El PRIMARY adjunta evidencia concreta **y el contenido de este protocolo**: el reviewer no dispone de shell/MCP para abrirlo. `--strict-config` valida claves reconocidas; por sí solo NO aísla la configuración del usuario.

## Autoridad y desacuerdos

El reviewer es advisor, no autoridad. El `PRIMARY` decide y conserva la responsabilidad completa.

Los desacuerdos se resuelven con:

1. requisitos explícitos del usuario;
2. contratos y comportamiento del repositorio;
3. tests, reproducciones y logs;
4. documentación oficial vigente;
5. arquitectura y convenciones establecidas;
6. razonamiento técnico.

No se abren consultas recursivas para resolver desacuerdos.

## Verification Gate

Una opinión de IA no sustituye validación automatizada. Antes de declarar `DONE`, el `PRIMARY` debe seguir [`.ai/VERIFICATION.md`](./VERIFICATION.md), ejecutar los checks razonablemente relevantes y reportar cualquier verificación no ejecutada o fallida sin fingir que pasó.

## Alcance de las protecciones

El inventario de MCP del lanzador se fija al iniciar el servidor. Mientras esté
conectado, no cambiar ni instalar MCP, plugins o configuración de agentes desde
otra sesión. Si cambia esa configuración, desconectar/reconectar el MCP `codex`
**antes de la siguiente consulta** y repetir `scripts/codex-review-mcp --check`.
El lanzador no es un monitor de cambios externos de configuración. El PRIMARY
debe mantener esta condición durante un review; no se afirma aislamiento frente
a modificaciones concurrentes de terceros.

Las reglas nativas `Read` de `.claude/settings.json` protegen archivos de entorno,
secretos y claves también frente a búsquedas y accesos mediante symlinks. La regla
`.env.*` incluye `.env.example`: la antigua excepción del hook no podía anular un
deny nativo. Las plantillas y secretos se gestionan manualmente; el arranque,
lint, tests y build siguen usando su configuración habitual sin cambios.

Los permisos locales se conservan. Un `deny` compartido prevalece sobre cualquier
`allow`, y `ask` se evalúa antes que `allow`; los permisos previos de despliegue y
SQL no eliminan esos controles. Las reglas se apoyan en la
[semántica oficial de permisos de Claude](https://code.claude.com/docs/en/permissions).
El subcomando `codex mcp-server` fue **RETIRADO** de la CLI: ausente en 0.155.1, y en
0.153.4 ya avisaba de su deprecación. Ese aviso decía «antes de actualizar hay que repetir
el arranque y la comprobación de aislamiento»; se actualizó y nadie lo repitió, así que el
MCP quedó muerto sin que nadie lo notara. La interfaz viva es `codex exec`, que acepta las
mismas `-c` y `--strict-config`. Al actualizar la CLI: repetir `--check` y un review real.

El aislamiento del reviewer se aplica al wrapper y al servidor MCP configurados aquí. Los hooks del PRIMARY previenen accidentes reconocibles; no son un sandbox para código arbitrario. Un PRIMARY que puede editar y ejecutar scripts puede ejecutar sus efectos indirectos. Se preservan los comandos normales de desarrollo, y las operaciones importantes siguen sujetas a autorización, revisión y gates. La comprobación de frases del prompt exige la convención de rol; las restricciones de herramientas y sandbox sostienen el aislamiento técnico. Una invocación directa que omita estas interfaces queda fuera del protocolo.
