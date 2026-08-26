-- ---------------------------------------------------------------------------
-- La pagina de la cartera devuelve tambien el segundo numero SIN VALIDAR
-- ---------------------------------------------------------------------------
-- Continuacion de 20260826151907 y de 20260826173523: la columna
-- `telefono_alternativo_crudo` ya existe en la tabla y el front ya la pide en
-- `COLUMNAS_LEAD`, pero la RPC de la cartera no la devolvia. La ficha del lead
-- se sirve del store (`listarLeadsDelAmbito`, que consulta la tabla directo), asi
-- que funcionaria igual sin esto — y precisamente por eso hay que hacerlo: dos
-- caminos que producen un `Lead` con forma distinta es como se pierde un dato en
-- silencio, que es la leccion entera de este ciclo.
--
-- Mismo `drop` + `create` que 20260826151907 (Postgres no deja cambiar el tipo de
-- retorno), mismo preflight anclado al md5 del cuerpo VIVO, mismos postflights.
-- El cuerpo es el de esa migracion con dos lineas mas.
-- ---------------------------------------------------------------------------

begin;

set local lock_timeout = '10s';

do $preflight$
begin
  if not exists (
    select 1 from pg_catalog.pg_attribute
    where attrelid = 'crm.leads'::regclass
      and attname = 'telefono_alternativo_crudo'
      and not attisdropped
  ) then
    raise exception 'Falta crm.leads.telefono_alternativo_crudo: aplicar antes 20260826173523.';
  end if;

  if (select md5(prosrc)
        from pg_catalog.pg_proc p
        join pg_catalog.pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'crm' and p.proname = 'cartera_pagina_fn')
     is distinct from '6ce36d259520b58ea5f47574a8dd8960' then
    raise exception 'crm.cartera_pagina_fn cambio desde que se escribio esta migracion: contrastar el cuerpo vivo antes de reemplazarlo.';
  end if;
end;
$preflight$;

drop function crm.cartera_pagina_fn(
  integer, timestamptz, uuid, text, uuid, boolean, text
);

create function crm.cartera_pagina_fn(
  p_limite       integer     default 50,
  p_antes_de     timestamptz default null,
  p_antes_id     uuid        default null,
  p_etapa        text        default null,
  p_vendedor_id  uuid        default null,
  p_sin_asignar  boolean     default false,
  p_texto        text        default null
)
returns table (
  id                    uuid,
  nombre_completo       text,
  telefono              text,
  telefono_alternativo  text,
  telefono_alternativo_crudo text,
  correo                text,
  dni                   text,
  genero                text,
  fecha_nacimiento      date,
  distrito              text,
  origen                text,
  etapa                 text,
  motivo_descarte       text,
  monto_estimado        numeric,
  moneda                text,
  categoria_interes     text,
  vendedor_id           uuid,
  asignado_supervisor_id uuid,
  creado_en             timestamptz,
  tenencia_desde        timestamptz,
  convertido_en         timestamptz,
  contrato_id           uuid,
  actualizado_en        timestamptz,
  activo                boolean,
  nota                  text,
  no_contactar          boolean,
  ultimo_contacto_en    timestamptz
)
language plpgsql
stable
security invoker
set search_path = ''
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
$function$;

comment on function crm.cartera_pagina_fn(integer, timestamptz, uuid, text, uuid, boolean, text) is
  'Pagina keyset de la cartera (cursor actualizado_en desc, id asc). SECURITY INVOKER: el alcance lo pone la policy leads_select; la funcion solo pone la guardia de admision al CRM. Desde 20260826 devuelve telefono_alternativo y el buscador por digitos tambien lo mira.';

revoke all on function crm.cartera_pagina_fn(integer, timestamptz, uuid, text, uuid, boolean, text)
  from public, anon, service_role;
grant execute on function crm.cartera_pagina_fn(integer, timestamptz, uuid, text, uuid, boolean, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Postflight — estructural
-- ---------------------------------------------------------------------------
do $postflight$
declare
  v_oid oid := 'crm.cartera_pagina_fn(integer, timestamptz, uuid, text, uuid, boolean, text)'::regprocedure;
  v_def text := pg_get_functiondef(v_oid);
begin
  -- Que la columna viaje DE VERDAD en el contrato de salida. Declararla en el
  -- `returns table` y olvidarla en el `select` es el fallo exacto que esta
  -- migracion viene a corregir, una fila mas abajo.
  if position('telefono_alternativo' in pg_get_function_result(v_oid)) = 0 then
    raise exception 'postflight: el contrato de salida no declara telefono_alternativo';
  end if;
  if position('l.telefono_alternativo,' in v_def) = 0 then
    raise exception 'postflight: la funcion declara la columna pero no la selecciona';
  end if;
  -- Y la columna nueva, con el mismo rasero: declararla en el `returns table` y
  -- olvidarla en el `select` es el fallo que ya se corrigio una vez aqui mismo.
  if position('telefono_alternativo_crudo' in pg_get_function_result(v_oid)) = 0 then
    raise exception 'postflight: el contrato de salida no declara telefono_alternativo_crudo';
  end if;
  if position('l.telefono_alternativo_crudo,' in v_def) = 0 then
    raise exception 'postflight: declara el crudo pero no lo selecciona';
  end if;
  -- Que el buscador la mire.
  if position('l.telefono_alternativo ilike v_patron_digitos' in v_def) = 0 then
    raise exception 'postflight: el buscador no mira el segundo numero';
  end if;
  -- Que NO se haya convertido en DEFINER por el camino: es una RPC con filas de
  -- PII y el alcance tiene que seguir poniendolo la RLS.
  if (select prosecdef from pg_catalog.pg_proc where oid = v_oid) then
    raise exception 'postflight: cartera_pagina_fn quedo SECURITY DEFINER';
  end if;
  -- Que la guardia de admision siga ahi.
  if position('No autorizado' in v_def) = 0 then
    raise exception 'postflight: la pagina perdio la guardia de admision';
  end if;
  -- Y que el recorte de ambito siga siendo el PREDICADO, no solo la palabra.
  -- Buscar 'vendedor_ids_visibles' a secas no sirve: el nombre sobrevive en la
  -- asignacion de v_visibles aunque el `where` se haya sustituido por un `true`.
  -- Un mutante que reemplazaba la rama del vendedor por `or true` pasaba ese
  -- control sin despeinarse. Se ancla la expresion entera.
  if position('or l.vendedor_id = any(v_visibles)' in v_def) = 0
     or position('or (l.vendedor_id is null and l.asignado_supervisor_id = any(v_visibles))' in v_def) = 0
     or position('v_rol = ''gerencia''' in v_def) = 0 then
    raise exception 'postflight: la pagina perdio el recorte de ambito';
  end if;
  -- La ventana de convertidos es parte del contrato de la pantalla: sin ella la
  -- cartera se llena de cerrados viejos y los tiles dejan de cuadrar con la lista.
  if position('l.etapa <> ''convertido'' or l.convertido_en >= v_corte' in v_def) = 0 then
    raise exception 'postflight: la pagina perdio la ventana de convertidos';
  end if;
  -- Que el grant quedara donde estaba y en NADIE mas.
  if not has_function_privilege('authenticated', v_oid, 'EXECUTE') then
    raise exception 'postflight: authenticated perdio el execute';
  end if;
  if has_function_privilege('anon', v_oid, 'EXECUTE')
     or has_function_privilege('service_role', v_oid, 'EXECUTE') then
    raise exception 'postflight: el drop+create abrio la funcion a un rol que no la tenia';
  end if;
end;
$postflight$;

commit;
