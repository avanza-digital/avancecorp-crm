-- ============================================================================
-- F2 tramo 1 (corrección) — la cartera del DIRECTORIO deja de mezclar borrados
-- ============================================================================
-- `20260810141953` dejó anotada una divergencia y NO la corrigió, a propósito,
-- para que la decidiera Miguel: la RPC no filtraba `activo` —igual que la
-- lectura que sustituye— mientras que `resumen_cartera_fn` sí lo hace SIEMPRE.
-- Para vendedor, supervisor y gerencia daba lo mismo (su policy `leads_select`
-- ya exige `activo = true`), pero el DIRECTORIO es lector global y su rama del
-- OR no lo exige: veía en las FILAS los leads soft-borrados que sus propios
-- TILES no contaban. Miguel: «arregla lo del directorio».
--
-- Único cambio: `and l.activo is true` en el WHERE. Todo lo demás —firma,
-- invoker, guardia de admisión, pista de ámbito, keyset, filtros, escapes— es
-- byte a byte lo aplicado el 2026-08-10.
--
-- Qué cambia y para quién:
--   · directorio/admin (lector global): la Cartera pasa a mostrar SOLO leads
--     vivos. Los soft-borrados siguen siendo suyos por RLS en cualquier otra
--     lectura; lo que se corrige es que esta pantalla dijera una cosa arriba
--     (tiles) y otra abajo (filas).
--   · vendedor / supervisor / gerencia / coordinador: NADA. El predicado ya era
--     redundante para ellos.
--
-- Qué NO cambia, y conviene no confundirlo: los leads DESCARTADOS del flujo
-- comercial conservan `activo = true` (los descarta `etapa`, no el soft-delete)
-- y siguen apareciendo, con su motivo, para todos los roles. Los que
-- desaparecen de la vista del directorio son los que `crm.descartar_lead`
-- cierra sobre la cola global — los que ningún otro rol veía ya.
--
-- Nota para F3: `leads_orden_cartera_idx` se creó DELIBERADAMENTE no parcial
-- (20260808155128) porque `listarLeadsDelAmbito` no enviaba `activo = true` y
-- un índice `where activo = true` la habría dejado sin él. Esta RPC sí lo
-- envía; cuando esa lectura muera con el store (F3), el índice podrá pasar a
-- parcial y encoger. No se toca ahora: mientras las dos lecturas convivan, el
-- índice tiene que servir a ambas.
--
-- No toca tablas, policies, columnas ni datos. Ningun objeto de `public`.
-- ============================================================================

begin;
set local lock_timeout = '10s';

create or replace function crm.cartera_pagina_fn(
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
  -- ⬇️ EL CAMBIO DE ESTA MIGRACION. Redundante para todos los roles menos el
  -- lector global, que es justamente a quien le mezclaba filas con sus tiles.
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
               or l.dni ilike v_patron_digitos escape E'\\'))
    )
  order by l.actualizado_en desc, l.id asc
  limit p_limite;
end;
$function$;

comment on function crm.cartera_pagina_fn(integer, timestamptz, uuid, text, uuid, boolean, text) is
  'Pagina de la cartera por cursor keyset (actualizado_en desc, id asc) con filtros de etapa/vendedor/texto en el servidor. SECURITY INVOKER a proposito: devuelve filas con PII y el alcance lo pone leads_select, no un predicado copiado. Solo leads vivos (activo) y ventana de convertidos de 45 dias: las filas cuentan lo mismo que los tiles de resumen_cartera_fn tambien para el lector global.';

-- `create or replace` CONSERVA el ACL previo; se repite igualmente porque el
-- dia que esta funcion se recree desde cero en otro entorno, el bloque tiene
-- que viajar con ella (una funcion nueva sin revoke hereda EXECUTE de PUBLIC).
revoke all on function crm.cartera_pagina_fn(integer, timestamptz, uuid, text, uuid, boolean, text)
  from public, anon, authenticated, service_role;
grant execute on function crm.cartera_pagina_fn(integer, timestamptz, uuid, text, uuid, boolean, text)
  to authenticated;

commit;
