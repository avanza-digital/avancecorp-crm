-- ============================================================================
-- F2 tramo 1 — Cursor keyset de la cartera (Plan de escalabilidad, fase F2)
-- ============================================================================
-- La cartera deja de descargarse entera para recortarse en el navegador. Una
-- RPC pagina por keyset `(actualizado_en desc, id asc)` sobre el indice
-- `leads_orden_cartera_idx` (20260808155128), con TODOS los filtros
-- (etapa / vendedor / texto) resueltos en el servidor.
--
--   crm.cartera_pagina_fn(p_limite, p_antes_de, p_antes_id,
--                         p_etapa, p_vendedor_id, p_sin_asignar, p_texto)
--
-- Decision de diseno del plan (absorbe un hallazgo mayor de inyeccion): los
-- parametros viajan TIPADOS. Nada de `.or()` de PostgREST interpolando strings
-- del cliente: el cursor lo valida Postgres, no una allowlist fragil del front.
--
-- ⚠️ SECURITY INVOKER — DIVERGENCIA DELIBERADA del patron de la casa
-- ----------------------------------------------------------------------------
-- Las 8 RPC de F1 son `security definer` porque devuelven AGREGADOS: numeros
-- que no identifican a nadie, y re-implementar el predicado de visibilidad es
-- el precio de agregarlos de una pasada. Esta NO devuelve numeros: devuelve
-- FILAS DE LEADS con PII (nombre, telefono, DNI, fecha de nacimiento). Con
-- `definer`, un solo error en el predicado copiado abriria la cartera entera de
-- la empresa a cualquier vendedor; con `invoker` la unica fuente de verdad del
-- alcance es la policy `leads_select` — la MISMA que hoy recorta la lectura que
-- esta funcion sustituye, sin una linea duplicada que pueda desincronizarse.
--
-- El `ultimo_contacto_en` no diverge por ello: `actividades_select`
-- (20260709000001:465) es co-extensiva con `leads_select` — quien ve el lead ve
-- TODAS sus actividades —, asi que el lateral calcula lo mismo que calcularia
-- una definer. (No es el caso de `resumen_tareas_fn`, donde el anti-join sobre
-- tareas AJENAS sí exigia definer; ver divergencia 5 del ledger de la tanda 2.)
--
-- Guardia de ADMISION + RLS de ALCANCE: la funcion conserva la guardia 42501 de
-- las otras RPC (uid nulo o ajeno al CRM) para que el contrato de denegacion
-- siga siendo uniforme y un revocado no reciba una lista vacia indistinguible
-- de "no tienes leads" (P04: revocado ≠ ajeno al CRM). Lo que NO hace es
-- re-implementar QUIEN ve QUE: de eso sigue respondiendo la RLS.
--
-- PISTA DE AMBITO PARA EL PLANNER (hallazgo MAYOR de la auditoria RLS): el
-- recorte que aplica la policy llega como `vendedor_id in (select
-- private.vendedor_ids_visibles(...))`, un SubPlan hasheado — filtro, NUNCA
-- index qual. Sin nada mas, un vendedor con 20 leads sobre un millon obliga a
-- recorrer el indice global hasta juntar 50 coincidencias EN CADA PAGINA: justo
-- el trabajo que esta fase viene a matar. Por eso el cuerpo captura el array de
-- visibles una vez y repite el predicado como `= any(...)` (misma tecnica que
-- la tanda 2 de F1, 20260809144920). Es REDUNDANTE a proposito y la asimetria
-- importa: bajo `invoker`, un error en este predicado solo puede OCULTAR filas
-- —la RLS mantiene la ultima palabra sobre lo que se ve—, mientras que el mismo
-- error bajo `definer` las abriria. Por eso se copia aqui y no alli.
--
-- Ventana de convertidos (decision de Miguel 2026-08-08, F0§5): el ambito
-- operativo excluye convertidos de mas de 45 dias — el MISMO corte que
-- `resumen_cartera_fn` y que `listarLeadsDelAmbito`.
--
-- Donde los tiles y las filas NO cuadran, y por que se acepta (auditoria RLS):
--   · DIRECTORIO: `resumen_cartera_fn` filtra `activo is true` siempre; aqui no
--     se filtra, y `leads_select` entrega los soft-borrados al lector global.
--     Es el comportamiento de HOY (`listarLeadsDelAmbito` tampoco filtra) y
--     alinearlo cambiaria lo que ve un rol de auditoria sin que nadie lo pida:
--     queda anotado, no corregido de tapadillo.
--   · COORDINADOR: sus tiles cuentan los sin-dueno de la cola global (rama
--     `puede_operar_reparto_crm`, 20260809144920) y aqui recibe 0 filas. NO es
--     visible en producto: ese rol tiene `verLeads: false` y la vista `cartera`
--     no se le abre (app/src/lib/vistas.ts) — su destino es «Repartir».
--
-- El keyset ordena por una columna MUTABLE (`actualizado_en` lo reescribe cada
-- UPDATE). Consecuencia asumida: un lead editado durante el scroll puede
-- REPETIRSE (el front deduplica por id) o SALTARSE (si cruza hacia delante del
-- cursor, no aparece en las paginas siguientes). No se congela un snapshot a
-- proposito: el precio de la foto fija es servir datos viejos.
--
-- Divergencias DELIBERADAS respecto del filtrado en el navegador:
--   a. La busqueda por telefono/DNI exige 3 digitos (hoy el filtro local
--      reacciona desde 1): con la cartera grande, `%9%` sobre dos columnas es
--      un escaneo completo en cada tecla. Es la MISMA regla que ya aplicaba
--      `listarLeads`. El NOMBRE se acepta desde 2 caracteres — no desde 3 — por
--      compatibilidad con esa lectura y con el filtro que los comerciales ya
--      usan; el coste de `%ro%` sobre una sola columna es asumible y el minimo
--      real de la busqueda util lo pone el usuario, no el indice.
--   b. `%` y `_` del usuario se escapan: son literales que el cliente teclea,
--      no comodines que pueda inyectar en el patron.
--   c. No se filtra `activo = true` explicitamente — igual que
--      `listarLeadsDelAmbito`, se confia en la RLS (su predicado tiene el
--      `activo` dentro de un OR con `es_lector_global`, y forzarlo aqui
--      cambiaria lo que ve el directorio respecto de hoy).
--
-- No toca tablas, policies, columnas ni datos. Ningun objeto de `public`.
-- ============================================================================

begin;
set local lock_timeout = '10s';

create function crm.cartera_pagina_fn(
  p_limite integer default 50,
  p_antes_de timestamptz default null,
  p_antes_id uuid default null,
  p_etapa text default null,
  p_vendedor_id uuid default null,
  p_sin_asignar boolean default false,
  p_texto text default null
)
returns table (
  id uuid,
  nombre_completo text,
  telefono text,
  correo text,
  dni text,
  genero text,
  fecha_nacimiento date,
  distrito text,
  origen text,
  etapa text,
  motivo_descarte text,
  monto_estimado numeric,
  moneda text,
  categoria_interes text,
  vendedor_id uuid,
  asignado_supervisor_id uuid,
  creado_en timestamptz,
  tenencia_desde timestamptz,
  convertido_en timestamptz,
  contrato_id uuid,
  actualizado_en timestamptz,
  activo boolean,
  nota text,
  no_contactar boolean,
  ultimo_contacto_en timestamptz
)
language plpgsql
stable security invoker
set search_path = ''
rows 200
as $function$
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
  -- Guardia de ADMISION (el ALCANCE lo pone la RLS, ver cabecera).
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
  -- solo puede ser un bug del llamante, y devolver 0 filas lo escondería.
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
    -- abajo declaran `escape '\'` explicitamente en vez de confiar en el
    -- default: asi la intencion no depende de `standard_conforming_strings`.
    v_patron_texto := '%' || replace(replace(replace(v_texto, E'\\', E'\\\\'), '%', E'\\%'), '_', E'\\_') || '%';
    v_patron_digitos := case when length(v_digitos) >= 3 then '%' || v_digitos || '%' end;
  end if;

  return query
  select l.id,
         l.nombre_completo,
         l.telefono,
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
         uc.creado_en as ultimo_contacto_en
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
  where (l.etapa <> 'convertido' or l.convertido_en >= v_corte)
    -- Pista de ambito: REDUNDANTE con la policy (ver cabecera). Solo puede
    -- restar filas; lo que se ve lo sigue decidiendo `leads_select`.
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
               or l.dni ilike v_patron_digitos escape E'\\'))
    )
  order by l.actualizado_en desc, l.id asc
  limit p_limite;
end;
$function$;

comment on function crm.cartera_pagina_fn(integer, timestamptz, uuid, text, uuid, boolean, text) is
  'Pagina de la cartera por cursor keyset (actualizado_en desc, id asc) con filtros de etapa/vendedor/texto en el servidor. SECURITY INVOKER a proposito: devuelve filas con PII y el alcance lo pone leads_select, no un predicado copiado. Ventana de convertidos de 45 dias.';

revoke all on function crm.cartera_pagina_fn(integer, timestamptz, uuid, text, uuid, boolean, text)
  from public, anon, authenticated, service_role;
grant execute on function crm.cartera_pagina_fn(integer, timestamptz, uuid, text, uuid, boolean, text)
  to authenticated;

commit;
