-- P-055 Fase 3.7 - El analista pasa a ser OBLIGATORIO.
--
-- Movida de snippets/ a migrations/ el 2026-08-29 CON EL FRONT YA VIVO
-- (release crm-20260829T182429Z-6088501b533d desplegado y verificado): la
-- condicion del hallazgo P1-5 de Codex quedo satisfecha.
--
-- ⛔ NO PUBLICAR ESTA MIGRACION ANTES QUE EL FRONT (cumplido). Es el ultimo paso de la
-- Fase 3 a proposito. El orden de este proyecto para una clave nueva que viaja
-- en la PETICION es: servidor la acepta (20260829181000) -> el front la manda
-- -> recien entonces se exige. Publicada antes de tiempo, la primera
-- administrativa que registre un contrato con la pantalla vieja se lleva un
-- error en la cara y no puede trabajar.
--
-- QUE CAMBIA, exactamente una rama. Hasta ahora, si la peticion NO traia el
-- campo:
--     * quien registra es del equipo comercial -> la venta queda a su nombre;
--     * quien registra NO lo es -> el contrato nacia SIN DUENO.
-- A partir de aqui, ese segundo caso FALLA y pide elegir. El primero se queda
-- igual, porque es literalmente la decision 2 de Miguel: «si no corresponde a
-- nadie, lo pone a su nombre».
--
-- POR QUE NO SE PONE `not null` EN LA COLUMNA: porque el historico tiene 15
-- contratos sin dueno a proposito -12 por la decision 18, 2 demos y 1 caso
-- declarado sin regla-. Un `not null` obligaria a inventarles un dueno, que es
-- justo lo que la decision 18 dice que NO se haga. La obligatoriedad vive en la
-- puerta de entrada, que es donde se puede exigir sin mentirle al pasado.

begin;

do $parche$
declare
  v_src   text;
  v_nuevo text;
  v_ancla text := '  else
    -- No vino: «si no corresponde a nadie, lo pone a su nombre» (decision 2).
    -- Si quien registra no es del equipo comercial, el contrato nace sin dueno
    -- en vez de romperle el trabajo: la obligatoriedad llega con el front.
    v_analista_cierre := case
      when exists (select 1 from crm.equipo e where e.perfil_id = v_uid) then v_uid
    end;
  end if;';
begin
  set local lock_timeout = '5s';

  select p.prosrc into v_src
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'crear_contrato'
    and pg_get_function_identity_arguments(p.oid) = 'p_contrato jsonb, p_cronograma jsonb';

  if v_src is null then
    raise exception 'No existe public.crear_contrato(jsonb, jsonb): ABORTA';
  end if;
  if (length(v_src) - length(replace(v_src, v_ancla, ''))) / length(v_ancla) <> 1 then
    raise exception 'No esta la rama de transicion de 20260829181000, o esta duplicada: ABORTA';
  end if;

  v_nuevo := replace(v_src, v_ancla, '  else
    -- No vino. «Si no corresponde a nadie, lo pone a su nombre» (decision 2):
    -- eso solo tiene sentido si quien registra PUEDE tener ventas. Si no puede
    -- -una administrativa, por ejemplo-, tiene que elegir a quien corresponde.
    if not exists (select 1 from crm.equipo e where e.perfil_id = v_uid and e.activo) then
      raise exception ''Elige el analista de la venta''
        using errcode = ''22023'',
              hint = ''Quien registra no forma parte del equipo comercial, asi que la venta no puede quedar a su nombre.'';
    end if;
    v_analista_cierre := v_uid;
  end if;');

  if v_nuevo = v_src then
    raise exception 'El parche no cambio nada: ABORTA';
  end if;

  execute format(
    'create or replace function public.crear_contrato(p_contrato jsonb, p_cronograma jsonb) '
    'returns jsonb language plpgsql security definer set search_path to '''' as %L', v_nuevo);
end
$parche$;

do $postflight$
declare v_src text; v_cfg text[]; v_secdef boolean; v_args text;
begin
  select p.prosrc, p.proconfig, p.prosecdef, pg_get_function_identity_arguments(p.oid)
    into v_src, v_cfg, v_secdef, v_args
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='crear_contrato';

  if v_src is null then raise exception 'POSTFLIGHT: crear_contrato desaparecio'; end if;
  if v_args <> 'p_contrato jsonb, p_cronograma jsonb' then
    raise exception 'POSTFLIGHT: cambio la firma (%)', v_args; end if;
  if not v_secdef then raise exception 'POSTFLIGHT: dejo de ser SECURITY DEFINER'; end if;
  if v_cfg is null or not (v_cfg @> array['search_path=""']::text[]) then
    raise exception 'POSTFLIGHT: sin search_path vacio (%)', v_cfg; end if;

  if strpos(v_src, 'Elige el analista de la venta') = 0 then
    raise exception 'POSTFLIGHT: no quedo la exigencia'; end if;
  -- La rama blanda ya no puede estar: si sobrevive, un contrato puede seguir
  -- naciendo sin dueno y esta migracion no sirvio de nada.
  if strpos(v_src, 'el contrato nace sin dueno') > 0 then
    raise exception 'POSTFLIGHT: la rama de transicion sigue viva'; end if;
  -- Y lo de siempre no se perdio.
  if strpos(v_src, 'Cliente no encontrado o fuera de tu cartera') = 0
     or strpos(v_src, 'crm.operaciones_cartera') = 0
     or strpos(v_src, 'creado_por, analista_cierre_id') = 0 then
    raise exception 'POSTFLIGHT: el parche se llevo algo por delante'; end if;

  raise notice 'POSTFLIGHT OK: el analista de la venta es obligatorio';
end
$postflight$;

commit;
