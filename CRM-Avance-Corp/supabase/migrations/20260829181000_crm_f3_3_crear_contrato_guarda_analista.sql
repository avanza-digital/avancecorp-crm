-- P-055 Fase 3.3 - La puerta de entrada guarda el analista que cierra.
--
-- TOCA `public` (la funcion `crear_contrato`): con permiso explicito de Miguel.
--
-- QUE, en una linea: `public.crear_contrato` pasa a aceptar
-- `analista_cierre_id` y a guardarlo en el contrato. Nada mas cambia.
--
-- POR QUE ASI Y NO OBLIGATORIO DE GOLPE. La decision 2 dice «obligatorio desde
-- ya», y lo sera. Pero el orden de despliegue de este proyecto es claro: una
-- clave NUEVA que viaja en la PETICION se acepta primero en el servidor, luego
-- la manda el front, y solo entonces se exige. Al reves, el primer analista que
-- registre un contrato con el front viejo se lleva un error en la cara. La
-- exigencia se enciende en `20260829182000`, cuando el front ya la mande.
--
-- QUE PASA MIENTRAS TANTO, exactamente:
--   * si la peticion TRAE el campo -> se valida y se guarda. Si el elegido no es
--     del equipo comercial, la creacion FALLA: no se guarda una atribucion a
--     alguien que no puede tener ventas.
--   * si la peticion NO lo trae -> la venta queda a nombre de quien la registra,
--     que es literalmente la decision 2: «si no corresponde a nadie, lo pone a
--     su nombre». Y si quien registra no es del equipo comercial (una
--     administrativa, por ejemplo), el contrato nace SIN DUENO en vez de
--     reventar: hoy esa persona puede registrar y no se le puede romper el
--     trabajo por un campo que su pantalla todavia no tiene.
--
-- LA UNICA VALIDACION QUE SE ANADE, y por que es la minima posible: el elegido
-- tiene que existir en `crm.equipo`. No se exige que este ACTIVO, porque la
-- decision 15 dice que la venta de quien ya no esta «cuenta igual». No se exige
-- un `rol_crm` concreto, porque Miguel no lo dijo y la funcion ya tiene su
-- propio criterio para las operaciones de cartera. Sin esta comprobacion, el
-- campo podria apuntar a un cliente.
--
-- COMO SE HACE EL CAMBIO: NO se vuelve a teclear la funcion. `crear_contrato`
-- tiene 9138 caracteres y es la unica puerta que inserta contratos: copiarla a
-- mano es la forma mas facil de perder una linea sin que nadie lo note. Se lee
-- la version VIVA, se ancla por `md5`, se comprueba que cada punto de insercion
-- aparece EXACTAMENTE UNA VEZ, y se parchea. Si algo no calza, aborta.
--
-- LO QUE NO SE TOCA: `creado_por` sigue siendo el registrador y no se pisa;
-- `actualizar_contrato` no cambia -actualiza columna por columna y no incluye
-- este campo, asi que corregir un contrato no puede mover su atribucion-; la
-- reasignacion tiene su propia puerta, con motivo, en `20260829181500`.

begin;

do $parche$
declare
  v_src      text;
  v_nuevo    text;
  v_huella   text;
  v_ancla_dec  text := '  v_upgrade_elegible boolean;';
  v_ancla_val  text := '  if v_moneda not in (''PEN'', ''USD'') then
    raise exception ''Moneda inválida'' using errcode = ''22023'';
  end if;';
  v_ancla_cols text := '    categoria, estado, creado_por
  ) values (';
  v_ancla_vals text := '    v_categoria, ''activo'', v_uid
  ) returning id, fecha_cierre_comercial into v_contrato_id, v_fecha_operacion;';
begin
  set local lock_timeout = '5s';

  ------------------------------------------------------------------ PREFLIGHT --
  select p.prosrc, md5(p.prosrc) into v_src, v_huella
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'crear_contrato'
    and pg_get_function_identity_arguments(p.oid) = 'p_contrato jsonb, p_cronograma jsonb';

  if v_src is null then
    raise exception 'No existe public.crear_contrato(jsonb, jsonb): ABORTA';
  end if;
  -- Huella RE-ANCLADA el 29/08 por la tarde: una sesion paralela publico
  -- `20260829175638_crm_gestion_cartera_autorizacion_integral` y reemplazo
  -- crear_contrato (f50b62e1... -> 2699cc72...). Se verifico que las CUATRO
  -- anclas de este parche siguen apareciendo exactamente una vez en el cuerpo
  -- nuevo antes de re-anclar. La leccion de la casa aplica: verificar el
  -- git status y el hash vivo ANTES de publicar (sesiones-paralelas-deploy).
  if v_huella <> '2699cc72bc69073895881399c02d7815' then
    raise exception 'crear_contrato cambio desde que se escribio esta migracion (huella viva %): ABORTA', v_huella;
  end if;
  if not exists (select 1 from pg_attribute
                 where attrelid='public.contratos'::regclass
                   and attname='analista_cierre_id' and not attisdropped) then
    raise exception 'Falta la migracion 20260829180000 (el campo): ABORTA';
  end if;

  -- Cada punto de insercion, EXACTAMENTE una vez. Si aparece dos veces, el
  -- parche se aplicaria dos veces y nadie lo notaria hasta produccion.
  if (length(v_src) - length(replace(v_src, v_ancla_dec,  ''))) / length(v_ancla_dec)  <> 1
   or (length(v_src) - length(replace(v_src, v_ancla_val,  ''))) / length(v_ancla_val)  <> 1
   or (length(v_src) - length(replace(v_src, v_ancla_cols, ''))) / length(v_ancla_cols) <> 1
   or (length(v_src) - length(replace(v_src, v_ancla_vals, ''))) / length(v_ancla_vals) <> 1 then
    raise exception 'Los puntos de insercion no aparecen exactamente una vez: ABORTA';
  end if;

  -------------------------------------------------------------------- PARCHE --
  v_nuevo := v_src;

  -- (1) la variable
  v_nuevo := replace(v_nuevo, v_ancla_dec,
    v_ancla_dec || E'\n  v_analista_cierre uuid;');

  -- (2) de quien es la venta, justo despues de validar la moneda
  v_nuevo := replace(v_nuevo, v_ancla_val, v_ancla_val || E'\n
  -- EL ANALISTA QUE CIERRA (decision 2 del plan P-055). Es de quien VENDIO, no
  -- de quien tecleo: `creado_por` se conserva aparte y no se pisa.
  begin
    v_analista_cierre := nullif(btrim(coalesce(p_contrato->>''analista_cierre_id'', '''')), '''')::uuid;
  exception when invalid_text_representation then
    raise exception ''El analista que cierra no es valido'' using errcode = ''22023'';
  end;

  if v_analista_cierre is not null then
    -- Elegido a mano: tiene que poder tener ventas. SOLO ACTIVOS (decision de
    -- Miguel, 29/08): una venta NUEVA es de alguien que esta trabajando; la
    -- venta vieja de alguien que se fue entra por la reasignacion de gerencia
    -- (que si acepta inactivos, con motivo y rastro). Y los roles OFF-ROSTER
    -- (coordinador, directorio) no son organigrama comercial por diseno.
    if not exists (
      select 1 from crm.equipo e where e.perfil_id = v_analista_cierre
        and e.activo
        and e.rol_crm in (''vendedor'',''supervisor'',''gerencia'')
    ) then
      raise exception ''El analista que cierra tiene que estar activo en el equipo comercial''
        using errcode = ''22023'';
    end if;
  else
    -- No vino: «si no corresponde a nadie, lo pone a su nombre» (decision 2).
    -- Si quien registra no es del equipo comercial, el contrato nace sin dueno
    -- en vez de romperle el trabajo: la obligatoriedad llega con el front.
    v_analista_cierre := case
      when exists (select 1 from crm.equipo e where e.perfil_id = v_uid) then v_uid
    end;
  end if;');

  -- (3) y (4) la columna y su valor en el INSERT
  v_nuevo := replace(v_nuevo, v_ancla_cols,
    '    categoria, estado, creado_por, analista_cierre_id
  ) values (');
  v_nuevo := replace(v_nuevo, v_ancla_vals,
    '    v_categoria, ''activo'', v_uid, v_analista_cierre
  ) returning id, fecha_cierre_comercial into v_contrato_id, v_fecha_operacion;');

  if v_nuevo = v_src then
    raise exception 'El parche no cambio nada: ABORTA';
  end if;

  execute format(
    'create or replace function public.crear_contrato(p_contrato jsonb, p_cronograma jsonb) '
    'returns jsonb language plpgsql security definer set search_path to '''' as %L', v_nuevo);
end
$parche$;

-- --------------------------------------------------------------- POSTFLIGHT --
do $postflight$
declare
  v_src text; v_secdef boolean; v_cfg text[]; v_args text; v_duenyo text;
  v_ejecutan text;
begin
  select p.prosrc, p.prosecdef, p.proconfig,
         pg_get_function_identity_arguments(p.oid),
         (select rolname from pg_roles where oid = p.proowner),
         (select string_agg(distinct pr.rolname, ', ') from aclexplode(p.proacl) a
          left join pg_roles pr on pr.oid = a.grantee where a.privilege_type = 'EXECUTE')
    into v_src, v_secdef, v_cfg, v_args, v_duenyo, v_ejecutan
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'crear_contrato';

  if v_src is null then raise exception 'POSTFLIGHT: crear_contrato desaparecio'; end if;
  if v_args <> 'p_contrato jsonb, p_cronograma jsonb' then
    raise exception 'POSTFLIGHT: cambio la firma (%)', v_args; end if;
  if not v_secdef then raise exception 'POSTFLIGHT: dejo de ser SECURITY DEFINER'; end if;
  if v_duenyo <> 'postgres' then raise exception 'POSTFLIGHT: cambio de dueno (%)', v_duenyo; end if;
  -- ⚠️ `search_path=""` se guarda CON comillas.
  if v_cfg is null or not (v_cfg @> array['search_path=""']::text[]) then
    raise exception 'POSTFLIGHT: se quedo sin search_path vacio (%)', v_cfg; end if;
  if v_ejecutan is null or v_ejecutan !~ 'authenticated' or v_ejecutan !~ 'service_role' then
    raise exception 'POSTFLIGHT: se perdieron permisos de ejecucion (%)', coalesce(v_ejecutan,'(ninguno)'); end if;

  -- Lo nuevo esta.
  if strpos(v_src, 'v_analista_cierre') = 0
     or strpos(v_src, 'analista_cierre_id') = 0
     or strpos(v_src, 'tiene que estar activo en el equipo comercial') = 0 then
    raise exception 'POSTFLIGHT: el parche del analista no quedo'; end if;

  -- Y lo viejo NO se perdio: los guardas que ya protegian esta puerta.
  if strpos(v_src, 'Cliente no encontrado o fuera de tu cartera') = 0
     or strpos(v_src, 'El capital debe estar entre 100 y 100,000,000') = 0
     or strpos(v_src, 'asesor_perfil_id') = 0
     or strpos(v_src, 'pg_advisory_xact_lock') = 0
     or strpos(v_src, '_sync_contrato_titulares') = 0
     or strpos(v_src, 'crm.operaciones_cartera') = 0
     or strpos(v_src, 'El cronograma no puede estar vacío') = 0
     or strpos(v_src, 'renovado_a_id = v_contrato_id') = 0 then
    raise exception 'POSTFLIGHT: el parche se llevo por delante algo de la funcion viva: ABORTA';
  end if;
  -- El registrador sigue siendo el registrador.
  if strpos(v_src, 'creado_por, analista_cierre_id') = 0 then
    raise exception 'POSTFLIGHT: creado_por dejo de escribirse junto al analista';
  end if;

  raise notice 'POSTFLIGHT OK: crear_contrato acepta y guarda el analista que cierra. Huella nueva: %', md5(v_src);
end
$postflight$;

commit;
