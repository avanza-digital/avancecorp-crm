-- =========================================================================
-- CRM · Ola 2 · La puerta #10 (multiempresa) DECLARA y DELEGA
-- =========================================================================
-- QUE HACE: `crm.metricas_multiempresa_fn(date)` deja de publicar su propia
-- division en el bloque `conversion` y publica `divisor`, `numerador` y
-- `tasa_pct` tal como los sirve `crm.conversion_mensual_fn`, declarandolo.
--
-- POR QUE ES LA MAS URGENTE DE LAS QUE QUEDABAN, Y A LA VEZ LA MAS BARATA:
-- era la UNICA puerta que calculaba por su cuenta y NO llamaba nunca a la
-- mensual. Pero hoy no llega a ninguna pantalla: vive detras de la bandera
-- `metricas_multiempresa_sombra` en `crm.multiempresa_flags`, que esta
-- APAGADA, y sin ella responde `P0409 · El informe multiempresa esta en
-- preparacion`. Medido el 22/09/2026. Arreglarla ANTES de encender esa bandera
-- cuesta lo que cuesta ahora; despues costaria una cifra publicada mal.
--
-- Sin consumidor en el front (solo aparece en `database.types.ts`), asi que no
-- necesita pestillo: no hay ningun `strictObject` que tumbar.
--
-- LA CONDICION DE LA REGLA SE CUMPLE SIEMPRE AQUI: `v_mes` es siempre el dia 1
-- de un mes y `v_hasta` es `least(hoy, fin de mes)` — eso ES «mes calendario
-- completo» — y la funcion no tiene filtro de fuente. Por eso delega sin `if`.
--
-- QUE NO CAMBIA: los recuentos `cierres`, `renovaciones`, `upgrades` y
-- `anulados` del mismo bloque siguen siendo los suyos, en vivo. Son
-- descriptivos, no la cifra. Y `factor_referido` tampoco se toca.
--
-- 🔴 ESTA PUERTA ESTA DENTRO DE UNA CADENA DE CANDADOS DE DOS ESLABONES, y
--    cambiarla exige recorrerla ENTERA en la misma transaccion. Medido el
--    22/09 (el primer ensayo murio con «Un auxiliar auditado cambio,
--    desaparecio o perdio su declaracion vigente»):
--
--      crm.metricas_multiempresa_fn(date)
--        ^ su md5 esta CLAVADO dentro de
--      private.auxiliares_analitica_lc_auditados()   (4ab8a07f4794...)
--        ^ y el md5 de ESTA esta clavado dentro de
--      private.assert_analitica_leads_citas()        (e43357800b6d...)
--        ^ y a esta no la clava nadie: el censo la excluye por identidad.
--
--    Ademas, `auxiliares_...` fija tambien la ACL de la puerta
--    (`[["authenticated","EXECUTE",false],["postgres","EXECUTE",false]]`) y el
--    assert fija la ACL y el dueno de `auxiliares_...`. `create or replace`
--    conserva ACL y dueno, asi que esas dos no se mueven.
--
--    Los dos eslabones de arriba se regeneran POR ANCLAS con SQL dinamico:
--    se lee su `pg_get_functiondef` VIVO y se sustituye la huella vieja por la
--    nueva, calculada en la propia transaccion. Nunca se reteclea un cuerpo.
--
-- MEDIDO EN PRODUCCION EL 22/09/2026, y fijado en el preflight:
--   · md5(pg_get_functiondef) = 4ab8a07f4794c015c4bb7264206dafcf
--   · dueno postgres · clase `analitica` · **SI en el censo** -> se re-sella su
--     declaracion y se refresca el sello. Huella anterior, para la reversa:
--     117113e7ba5e... (la completa la lee el propio `update` de abajo).
--
-- REVERSA: volver a declarar el cuerpo sin el bloque de sustitucion, restaurar
-- la huella anterior, quitar el texto anadido a `razon` y refrescar el sello.
-- =========================================================================

begin;

set local statement_timeout = '180s';
set local lock_timeout = '5s';
lock table private.analitica_leads_citas_exenciones,
           private.analitica_lc_sello in share row exclusive mode;

do $preflight$
declare v_md5 text; v_bandera boolean;
begin
  select md5(pg_get_functiondef(p.oid)) into v_md5 from pg_proc p
   where p.oid = to_regprocedure('crm.metricas_multiempresa_fn(date)');
  if v_md5 is distinct from '4ab8a07f4794c015c4bb7264206dafcf' then
    raise exception 'PREFLIGHT: el cuerpo vivo NO es el revisado (md5 %)', v_md5;
  end if;
  if not exists (select 1 from pg_proc p
                  where p.oid = to_regprocedure('crm.metricas_multiempresa_fn(date)')
                    and p.proowner = 'postgres'::regrole and p.prosecdef and p.provolatile = 's') then
    raise exception 'PREFLIGHT: dueno, definer o volatilidad inesperados';
  end if;
  if to_regprocedure('crm.conversion_mensual_fn(date)') is null then
    raise exception 'PREFLIGHT: crm.conversion_mensual_fn(date) no existe';
  end if;
  -- La bandera tiene que seguir APAGADA: si alguien la encendio, este cambio
  -- deja de ser invisible y merece mirarse antes de entrar.
  select coalesce(activo, false) into v_bandera
    from crm.multiempresa_flags where nombre = 'metricas_multiempresa_sombra';
  if coalesce(v_bandera, false) then
    raise exception 'PREFLIGHT: la bandera metricas_multiempresa_sombra esta ENCENDIDA; este cambio ya seria visible y hay que revisarlo antes';
  end if;
end;
$preflight$;

-- ---------------------------------------------------------------------------
-- (b) El cuerpo, generado POR ANCLAS sobre el vivo acreditado arriba.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm.metricas_multiempresa_fn(p_mes date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_hoy date := (statement_timestamp() at time zone 'America/Lima')::date;
  v_mes date := date_trunc('month',coalesce(p_mes,v_hoy))::date;
  v_hasta date;
  v_ini timestamptz;
  v_fin timestamptz;
  v_factor numeric;
  v_payload jsonb;
  v_oficial jsonb;
begin
  if not private.metricas_f7_autorizada() then
    raise exception 'No autorizado' using errcode='42501';
  end if;
  if not coalesce((select activo from crm.multiempresa_flags
    where nombre='metricas_multiempresa_sombra'),false) then
    raise exception 'El informe multiempresa está en preparación' using errcode='P0409';
  end if;
  if not isfinite(v_mes) or v_mes>v_hoy or v_mes<date '2000-01-01' then
    raise exception 'Mes inválido' using errcode='22023';
  end if;
  v_hasta:=least(v_hoy,(v_mes+interval '1 month'-interval '1 day')::date);
  v_ini:=v_mes::timestamp at time zone 'America/Lima';
  v_fin:=(v_hasta+1)::timestamp at time zone 'America/Lima';
  v_factor:=private.peso_referido_conversion(v_mes);

  with fuentes as materialized (
    select * from private.metricas_f7_fuentes() where fecha_imputacion<=v_hoy
  ), ordenadas as (
    -- Ordenar sobre la propia fila evita multiplicarla con otro join.
    select f.*,case when inversionista_id is not null then row_number() over (
      partition by inversionista_id
      order by fecha_comercial nulls last,creado_en nulls last,empresa,fuente_id
    ) end as orden from fuentes f
  ), mes as materialized (
    select * from ordenadas where fecha_imputacion between v_mes and v_hasta
  ), produccion as materialized (
    select empresa,moneda,count(*) as operaciones,sum(capital) as capital,
      count(*) filter(where orden=1) as primeras,
      count(*) filter(where orden>1) as posteriores,
      count(*) filter(where orden is null) as sin_identidad
    from mes group by empresa,moneda
  ), tipos as (
    select empresa,moneda,tipo_capital,count(*) as operaciones,sum(capital) as capital
    from mes group by empresa,moneda,tipo_capital
  ), atribucion as materialized (
    select m.empresa,m.moneda,m.analista_id,p.nombre_completo as analista_nombre,
      count(*) as operaciones,sum(m.capital) as capital
    from mes m left join public.perfiles p on p.id=m.analista_id
    group by m.empresa,m.moneda,m.analista_id,p.nombre_completo
  ), participantes as materialized (
    select distinct empresa,inversionista_id from fuentes where inversionista_id is not null
    union
    select distinct f.empresa,private.inversionista_canonica(t.inversionista_id)
    from fuentes f join crm.inversion_titulares t on t.inversion_id=f.inversion_id
    where f.identidad_coherente and t.rol='cotitular'
  ), personas as materialized (
    select inversionista_id,count(*) as empresas
    from participantes where inversionista_id is not null group by inversionista_id
  ), capital_nucleo as (
    select case when e.contrato_id is not null then 'avance' else ce.cooperativa end as empresa,
      e.moneda,sum(e.monto) as capital,count(*) as operaciones
    from private.capital_episodios(v_ini,v_fin,true,'{}') e
    left join crm.cierres_externos ce on ce.id=e.cierre_externo_id
    where e.medida='stock' group by 1,2
  ), conciliacion as (
    select coalesce(n.empresa,p.empresa) as empresa,coalesce(n.moneda,p.moneda) as moneda,
      coalesce(n.capital,0) as capital_nucleo,coalesce(p.capital,0) as capital_informe,
      coalesce(n.operaciones,0) as operaciones_nucleo,coalesce(p.operaciones,0) as operaciones_informe,
      coalesce(p.capital,0)-coalesce(n.capital,0) as diferencia_capital,
      coalesce(p.operaciones,0)-coalesce(n.operaciones,0) as diferencia_operaciones,
      coalesce((select sum(a.capital) from atribucion a
        where a.empresa=coalesce(n.empresa,p.empresa) and a.moneda=coalesce(n.moneda,p.moneda)),0)
        -coalesce(n.capital,0) as diferencia_atribucion
    from capital_nucleo n full join produccion p using(empresa,moneda)
  ), conversion as materialized (
    select * from private.conversion_episodios(v_ini,v_fin,v_mes,true,'{}',v_factor)
  ), vencimientos as (
    select empresa,moneda,count(*) as operaciones,sum(capital) as capital
    from fuentes where vence_en between v_hoy and v_hoy+30
      and ((fuente_tipo='contrato' and estado='activo') or (fuente_tipo='cierre' and estado='vigente'))
    group by empresa,moneda
  ), oportunidades as (
    select e.clave as empresa,count(p.inversionista_id) as personas
    from crm.empresas e left join personas p on not exists (
      select 1 from participantes v where v.inversionista_id=p.inversionista_id and v.empresa=e.clave
    ) and exists(select 1 from crm.inversionistas i
      where i.id=p.inversionista_id and i.estado='activo' and not i.no_contactar
        and not exists(select 1 from crm.leads l
          where l.id in (select private.leads_de_persona_veto(i.id)) and l.no_contactar))
    where e.activa group by e.clave
  )
  select jsonb_build_object(
    'version',1,'modo','sombra','mes',v_mes,'hasta',v_hasta,'hoy',v_hoy,
    'generado_en',statement_timestamp(),'habilitada',true,
    'mes_sellado',exists(select 1 from crm.periodos_cerrados where periodo=v_mes),
    'produccion',coalesce((select jsonb_agg(p order by empresa,moneda) from produccion p),'[]'::jsonb),
    'tipos_capital',coalesce((select jsonb_agg(t order by empresa,moneda,tipo_capital) from tipos t),'[]'::jsonb),
    'atribucion',coalesce((select jsonb_agg(a order by empresa,moneda,analista_nombre nulls last,analista_id) from atribucion a),'[]'::jsonb),
    'personas',jsonb_build_object(
      'total',(select count(*) from personas),
      'una_empresa',(select count(*) from personas where empresas=1),
      'dos_empresas',(select count(*) from personas where empresas=2),
      'tres_empresas',(select count(*) from personas where empresas>=3),
      'por_empresa',coalesce((select jsonb_agg(x order by empresa) from (
        select empresa,count(*) as personas from participantes where inversionista_id is not null group by empresa
      ) x),'[]'::jsonb),
      'fuentes_sin_identidad',(select count(*) from fuentes where inversionista_id is null),
      'fuentes_coherentes',(select count(*) from fuentes where identidad_estado='coherente'),
      'fuentes_contradictorias',(select count(*) from fuentes where identidad_estado='contradictoria'),
      'fuentes_sin_enlace',(select count(*) from fuentes where identidad_estado='ausente')
    ),
    'conversion',(
      select jsonb_build_object('factor_referido',v_factor,'divisor',coalesce(sum(aporte_divisor),0),
        'numerador',coalesce(sum(aporte_numerador),0),
        'tasa_pct',case when sum(aporte_divisor)>0 then round(100*sum(aporte_numerador)/sum(aporte_divisor),2) end,
        'cierres',count(*) filter(where tipo='cierre' and aporte_numerador>0),
        'renovaciones',count(*) filter(where tipo='operacion' and categoria='renovacion'),
        'upgrades',count(*) filter(where tipo='operacion' and categoria='upgrade'),
        'anulados',count(*) filter(where tipo='cierre' and anulado)) from conversion
    ),
    'vencimientos',coalesce((select jsonb_agg(v order by empresa,moneda) from vencimientos v),'[]'::jsonb),
    'oportunidades',coalesce((select jsonb_agg(o order by empresa) from oportunidades o),'[]'::jsonb),
    'conciliacion',coalesce((select jsonb_agg(c order by empresa,moneda) from conciliacion c),'[]'::jsonb),
    'fuentes_duplicadas',(select count(*) from (
      select fuente_tipo,fuente_id from fuentes group by fuente_tipo,fuente_id having count(*)>1
    ) d)
  ) into v_payload;

  -- ══ OLA 2 · DECLARAR Y DELEGAR ═════════════════════════════════════════
  -- Esta era la unica puerta que calculaba la conversion por su cuenta Y NO
  -- llamaba nunca a la mensual. No llega a ninguna pantalla —vive detras de la
  -- bandera `metricas_multiempresa_sombra`, apagada, y sin ella responde
  -- P0409— pero el dia que se encienda publicaria una cifra distinta de la
  -- oficial en cuanto hubiera un mes sellado o deuda de anulacion. Se arregla
  -- ANTES de encenderla, que es cuando sale barato.
  --
  -- Aqui la condicion de la regla de Miguel se cumple SIEMPRE: `v_mes` es
  -- siempre el dia 1 de un mes y `v_hasta` es `least(hoy, fin de mes)`, que es
  -- exactamente «mes calendario completo»; y esta funcion no tiene filtro de
  -- fuente. Por eso delega sin condicion.
  --
  -- El gate ya paso (`private.metricas_f7_autorizada()`), asi que hay identidad
  -- y `crm.conversion_mensual_fn` —cuyo gate es mas ancho— no puede negarse.
  v_oficial := crm.conversion_mensual_fn(v_mes);
  v_payload := jsonb_set(v_payload, '{conversion}',
    (v_payload -> 'conversion') || jsonb_build_object(
      'es_mes_calendario', true,
      'fuente', 'mensual',
      'sellado', coalesce((v_oficial #>> '{cierre,cerrado}')::boolean, false),
      'ajuste_aplicado', true,
      'divisor', v_oficial #> '{total,divisor}',
      'numerador', v_oficial #> '{total,numerador}',
      'tasa_pct', v_oficial #> '{total,conversion_pct}',
      -- Lo que esta funcion habria publicado, al lado. Los recuentos de abajo
      -- (`cierres`, `renovaciones`, `upgrades`, `anulados`) siguen siendo los
      -- suyos, en vivo: son descriptivos, no la cifra.
      'recalculo_vivo', jsonb_build_object(
        'divisor', v_payload #> '{conversion,divisor}',
        'numerador', v_payload #> '{conversion,numerador}',
        'tasa_pct', v_payload #> '{conversion,tasa_pct}')
    ), false);

  return v_payload;
end;
$function$;

-- ---------------------------------------------------------------------------
-- (b2) LA CADENA. Los dos eslabones que clavan el md5 del de abajo, regenerados
--      por anclas sobre su propio cuerpo VIVO. Si alguna sustitucion no encaja,
--      la migracion se detiene: no se escribe un cuerpo a medias.
-- ---------------------------------------------------------------------------
do $cadena$
declare
  v_md5_puerta text; v_md5_aux_viejo text; v_md5_aux_nuevo text;
  v_def text; v_nuevo text;
begin
  -- 1. La huella NUEVA de la puerta, ya redeclarada arriba.
  select md5(pg_get_functiondef(p.oid)) into v_md5_puerta
    from pg_proc p where p.oid = to_regprocedure('crm.metricas_multiempresa_fn(date)');
  if v_md5_puerta = '4ab8a07f4794c015c4bb7264206dafcf' then
    raise exception 'CADENA: el cuerpo de la puerta no cambio; la migracion no hizo nada';
  end if;

  -- 2. Primer eslabon: `auxiliares_analitica_lc_auditados`, por anclas.
  select pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
    into v_def, v_md5_aux_viejo
    from pg_proc p where p.oid = to_regprocedure('private.auxiliares_analitica_lc_auditados()');
  if v_md5_aux_viejo <> 'e43357800b6d79050c7ca7af6c6844b8' then
    raise exception 'CADENA: el primer eslabon no es el revisado (md5 %)', v_md5_aux_viejo;
  end if;
  if (length(v_def) - length(replace(v_def, '4ab8a07f4794c015c4bb7264206dafcf', ''))) / 32 <> 1 then
    raise exception 'CADENA: la huella vieja de la puerta no aparece EXACTAMENTE una vez en el primer eslabon';
  end if;
  v_nuevo := replace(v_def, '4ab8a07f4794c015c4bb7264206dafcf', v_md5_puerta);
  execute v_nuevo;

  select md5(pg_get_functiondef(p.oid)) into v_md5_aux_nuevo
    from pg_proc p where p.oid = to_regprocedure('private.auxiliares_analitica_lc_auditados()');
  if v_md5_aux_nuevo = v_md5_aux_viejo then
    raise exception 'CADENA: el primer eslabon no cambio de huella';
  end if;

  -- 3. Segundo eslabon: el propio assert, tambien por anclas.
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p where p.oid = to_regprocedure('private.assert_analitica_leads_citas()');
  if (length(v_def) - length(replace(v_def, 'e43357800b6d79050c7ca7af6c6844b8', ''))) / 32 <> 1 then
    raise exception 'CADENA: la huella vieja del primer eslabon no aparece EXACTAMENTE una vez en el assert';
  end if;
  v_nuevo := replace(v_def, 'e43357800b6d79050c7ca7af6c6844b8', v_md5_aux_nuevo);
  execute v_nuevo;

  -- 4. Y nadie mas clava esas dos huellas: si alguien lo hiciera, quedaria
  --    apuntando a un cuerpo que ya no existe.
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname in ('private','crm','public')
                and p.oid <> to_regprocedure('private.auxiliares_analitica_lc_auditados()')
                and p.prosrc like '%4ab8a07f4794c015c4bb7264206dafcf%') then
    raise exception 'CADENA: alguien mas clavaba la huella vieja de la puerta';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname in ('private','crm','public')
                and p.oid <> to_regprocedure('private.assert_analitica_leads_citas()')
                and p.prosrc like '%e43357800b6d79050c7ca7af6c6844b8%') then
    raise exception 'CADENA: alguien mas clavaba la huella vieja del primer eslabon';
  end if;
end;
$cadena$;

-- ---------------------------------------------------------------------------
-- (c) Re-sellar su declaracion, con la normalizacion DEL CENSO.
-- ---------------------------------------------------------------------------
update private.analitica_leads_citas_exenciones e
   set huella = md5(regexp_replace(regexp_replace(
                      lower(coalesce(p.prosrc, pg_get_functiondef(p.oid))),
                      '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g')),
       razon  = e.razon || ' Ola 2 (22/09/2026): deja de dividir por su cuenta y DELEGA divisor, '
                        || 'numerador y tasa_pct en crm.conversion_mensual_fn, declarandolo '
                        || '(fuente=mensual, ajuste_aplicado=true) y conservando su recalculo en '
                        || 'recalculo_vivo. Los recuentos del bloque siguen siendo los suyos.'
  from pg_proc p
 where p.oid = to_regprocedure(e.objeto)
   and e.objeto = 'crm.metricas_multiempresa_fn(date)';

update private.analitica_lc_sello
   set sello = private.huella_exenciones_analitica_lc(), sellado_en = now()
 where id;

-- ---------------------------------------------------------------------------
-- (d) POSTFLIGHT. La funcion esta detras de una bandera apagada, asi que para
--     poder MEDIRLA se enciende dentro de un SAVEPOINT y se deshace: al salir,
--     la bandera queda exactamente como estaba, sin rastro en la bitacora.
-- ---------------------------------------------------------------------------
do $postflight$
declare
  v_ok text; v_conv jsonb; v_of jsonb; v_p0409 boolean := false;
  v_claims text := current_setting('request.jwt.claims', true);
  v_gerente uuid;
begin
  v_ok := private.assert_analitica_leads_citas();
  if v_ok not like 'OK:%' then
    raise exception 'POSTFLIGHT: el trinquete quedo en rojo: %', v_ok;
  end if;

  select e.perfil_id into v_gerente from crm.equipo e
   where e.rol_crm = 'gerencia' and e.activo and private.rol_crm(e.perfil_id) = 'gerencia'
   order by e.perfil_id limit 1;
  if v_gerente is null then
    raise exception 'POSTFLIGHT: no hay perfil de gerencia activo';
  end if;
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', v_gerente, 'role', 'authenticated')::text, true);

  -- 1) Con la bandera APAGADA sigue negandose. El candado no se ha tocado.
  begin
    perform crm.metricas_multiempresa_fn(date_trunc('month', (now() at time zone 'America/Lima'))::date);
  exception
    when sqlstate 'P0409' then v_p0409 := true;
    when others then
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      raise;
  end;
  if not v_p0409 then
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    raise exception 'POSTFLIGHT: con la bandera apagada la funcion deberia responder P0409 y respondio';
  end if;

  -- 2) Encendida (en un savepoint que se deshace), publica la cifra OFICIAL.
  begin
    update crm.multiempresa_flags set activo = true
     where nombre = 'metricas_multiempresa_sombra';
    v_conv := crm.metricas_multiempresa_fn(
                date_trunc('month', (now() at time zone 'America/Lima'))::date) -> 'conversion';
    v_of := crm.conversion_mensual_fn(
              date_trunc('month', (now() at time zone 'America/Lima'))::date) -> 'total';

    if (v_conv -> 'divisor')   is distinct from (v_of -> 'divisor')
       or (v_conv -> 'numerador') is distinct from (v_of -> 'numerador')
       or (v_conv -> 'tasa_pct')  is distinct from (v_of -> 'conversion_pct') then
      raise exception 'POSTFLIGHT: NO publica la cifra oficial. puerta % · oficial %', v_conv, v_of;
    end if;
    if (v_conv ->> 'fuente') is distinct from 'mensual'
       or (v_conv ->> 'es_mes_calendario')::boolean is not true
       or (v_conv ->> 'ajuste_aplicado')::boolean is not true
       or (v_conv -> 'sellado') is distinct from (
            crm.conversion_mensual_fn(date_trunc('month', (now() at time zone 'America/Lima'))::date)
              #> '{cierre,cerrado}') then
      raise exception 'POSTFLIGHT: delego pero no lo declara: %', v_conv;
    end if;
    if v_conv -> 'recalculo_vivo' is null then
      raise exception 'POSTFLIGHT: falta recalculo_vivo';
    end if;
    -- Los recuentos descriptivos siguen ahi.
    if v_conv -> 'cierres' is null or v_conv -> 'anulados' is null
       or v_conv -> 'factor_referido' is null then
      raise exception 'POSTFLIGHT: desaparecio algun recuento del bloque conversion: %', v_conv;
    end if;
    raise exception 'DESHACIENDO_LA_BANDERA';
  exception
    when others then
      if sqlerrm <> 'DESHACIENDO_LA_BANDERA' then
        perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
        raise;
      end if;
  end;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);

  -- 3) La bandera quedo como estaba: APAGADA.
  if coalesce((select activo from crm.multiempresa_flags
                where nombre = 'metricas_multiempresa_sombra'), false) then
    raise exception 'POSTFLIGHT: la bandera quedo ENCENDIDA; hay que apagarla antes de nada';
  end if;

  -- 4) Dueno, definer, volatilidad y search_path, intactos.
  if not exists (select 1 from pg_proc p
                  where p.oid = to_regprocedure('crm.metricas_multiempresa_fn(date)')
                    and p.proowner = 'postgres'::regrole and p.prosecdef
                    and p.provolatile = 's' and p.proconfig @> array['search_path=""']) then
    raise exception 'POSTFLIGHT: cambio el dueno, el definer, la volatilidad o el search_path';
  end if;
end;
$postflight$;

comment on function crm.metricas_multiempresa_fn(date) is
  'Informe multiempresa (detras de la bandera metricas_multiempresa_sombra). Desde la Ola 2 '
  '(22/09/2026) su bloque `conversion` DELEGA divisor, numerador y tasa_pct en '
  'crm.conversion_mensual_fn y lo declara (es_mes_calendario=true, fuente=mensual, '
  'sellado=<lo que diga la oficial>, ajuste_aplicado=true), conservando en recalculo_vivo lo '
  'que ella misma habria calculado. Era la unica puerta que calculaba por su cuenta y no '
  'llamaba nunca a la mensual. Los recuentos cierres/renovaciones/upgrades/anulados y '
  'factor_referido siguen siendo los suyos, en vivo.';

select 'puerta10-declara-y-delega' as migracion,
       private.assert_analitica_leads_citas() as trinquete,
       coalesce((select activo from crm.multiempresa_flags
                  where nombre = 'metricas_multiempresa_sombra'), false) as bandera_sigue_apagada_false;

commit;
