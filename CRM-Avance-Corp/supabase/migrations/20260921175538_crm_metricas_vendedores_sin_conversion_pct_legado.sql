-- Fuera el campo muerto `conversion_pct` de crm.metricas_vendedores_fn (Miguel, 21/09/2026).
--
-- Que hacia: en cada fila de `vendedores` y de `equipos` viajaba un entero
-- `conversion_pct` = round(nucleo_conversion_pct), y CERO cuando el nucleo no
-- podia publicar. Ninguna pantalla lo lee (comprobado en CRM y portal el 21/09):
-- el front solo consume los campos `nucleo_*` y ademas re-divide numerador entre
-- divisor para verificar el porcentaje. Pero cualquiera que abriera el JSON leia
-- dos porcentajes distintos para la misma analista (6 frente a 5.79) y, peor, un
-- 0 alli donde la verdad es «no medible». Es el antipatron del cero fabricado.
--
-- Que cambia: el cuerpo es BYTE A BYTE el de 20260828173154 (huella md5
-- d8226991aba1783b042eaf087568ba49, verificada contra produccion) menos los dos
-- bloques `'conversion_pct', case ... else 0 end,` de SALIDA: 12 lineas quitadas,
-- 0 anadidas. Huella candidata del cuerpo nuevo: 9675b589f24c595ad58ead3d767b083c.
-- Las lecturas de `conversion_pct` que quedan son del contrato de ENTRADA de
-- crm.conversion_mensual_fn y no cambian. Ni roles, ni ambitos, ni grants.
--
-- Orden de publicacion (regla del proyecto: clave que DESAPARECE de la respuesta
-- => front primero): el front que admite el campo como opcional
-- (lib/metricas-vendedores.ts, tests «F1 (21/09/2026)») debe estar publicado
-- ANTES de instalar esto; el ledger anota el buildId vivo en ese momento.
--
-- TRINQUETE DE ANALITICA: crm.metricas_vendedores_fn() esta DECLARADA como
-- contador crudo con huella vigente (comprobado en produccion el 21/09:
-- declarada=true, huella_ok=true). Cambiarle el cuerpo CADUCA esa razon y pone
-- private.assert_analitica_leads_citas() en rojo con «Contadores exentos cuyo
-- cuerpo CAMBIO desde que se declararon». Por eso esta migracion refresca su
-- propia declaracion y resella, en la MISMA transaccion que el reemplazo. La
-- huella la calcula la base con la expresion del censo, nunca a mano.
-- No se pone el assert en el preflight: el trinquete arrastra la deuda de
-- crm.contrato_eliminar_auditado (sin declarar desde el 05/09), que se resuelve
-- en 20260921190145; bloquear esto con deuda ajena solo pararia el trabajo.
--
-- Plan: «Una sola definicion de conversion», fase F1 (vault, 21/09/2026).
-- Revision: auditor-rls 21/09 (CAMBIOS: literal sin cerrar y postflight ausente;
-- ambos corregidos aqui). Sin hallazgos de seguridad.
-- Reversa: reinstalar la definicion de 20260828173154 tal cual.
-- Requiere aprobacion expresa antes de instalar en produccion.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';
set local search_path = pg_catalog;
-- La declaracion de esta funcion se refresca abajo: se toma la exclusion antes.
lock table private.analitica_leads_citas_exenciones, private.analitica_lc_sello
  in share row exclusive mode;
do $preflight$
begin
  -- Solo se reemplaza la funcion que se audito. Si produccion cambio, se para.
  if (select pg_catalog.md5(p.prosrc)
      from pg_catalog.pg_proc p
      where p.oid = 'crm.metricas_vendedores_fn()'::regprocedure)
     is distinct from 'd8226991aba1783b042eaf087568ba49' then
    raise exception 'PREFLIGHT F1: crm.metricas_vendedores_fn no es la version auditada (d8226991)';
  end if;
end;
$preflight$;

create or replace function crm.metricas_vendedores_fn()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rol text;
  v_lector boolean;
  v_global boolean;
  v_alcance text;
  v_visibles uuid[];
  v_ahora timestamptz := now();
  v_corte timestamptz;
  v_mes date;
  v_factor numeric;
  v_mensual jsonb;
  v_conversion_publicable boolean;
  v_payload jsonb;
begin
  v_rol := private.rol_crm(v_uid);
  v_lector := private.es_lector_global();

  if v_uid is null
     or (v_rol is null and not coalesce(v_lector, false)) then
    raise exception 'No autorizado' using errcode = '42501';
  end if;

  v_visibles := array(
    select private.vendedor_ids_visibles(v_uid)
  );

  v_global := coalesce(v_rol = 'gerencia', false)
              or coalesce(v_lector, false);
  v_alcance := case
    when v_global then 'global'
    when v_rol = 'supervisor' then 'equipo'
    else 'propio'
  end;

  v_corte := v_ahora - interval '45 days';
  v_mes := date_trunc(
    'month',
    v_ahora at time zone 'America/Lima'
  )::date;
  v_factor := private.peso_referido_conversion(v_mes);

  -- Compatibilidad historica M13e: el coordinador puede llamar esta RPC,
  -- pero su ambito de vendedores/equipos es vacio. No debe llamar al wrapper
  -- mensual, que correctamente lo deniega con 42501.
  if v_rol = 'coordinador' and not coalesce(v_lector, false) then
    return jsonb_build_object(
      'version', 1,
      'generado_en', v_ahora,
      'ventana_convertidos_dias', 45,
      'ventana_metrica', 'mes_calendario',
      'mes_metrica', v_mes,
      'peso_referido', v_factor,
      'cobertura_conversion', null,
      'nucleo_total', jsonb_build_object(
        'nucleo_convertidos', null,
        'operaciones_cartera', null,
        'nucleo_divisor', null,
        'nucleo_numerador', null,
        'nucleo_conversion_pct', null
      ),
      'vendedores', '[]'::jsonb,
      'equipos', '[]'::jsonb
    );
  end if;

  -- La cobertura exacta de abajo es para el mes VIVO y su roster actual. La
  -- regla de cierre impide sellar este periodo; si el estado viola esa regla,
  -- no mezclar una foto historica con el equipo vivo aunque sus UUID coincidan.
  if exists (
    select 1
    from crm.periodos_cerrados pc
    where pc.periodo = v_mes
  ) then
    raise exception
      'El mes operativo actual aparece sellado inesperadamente'
      using errcode = '55000';
  end if;

  -- Un solo contrato para la conversion mostrada. Este payload ya contiene
  -- el ajuste pendiente aplicado por vendedor y la cartera deduplicada.
  v_mensual := crm.conversion_mensual_fn(v_mes);

  -- Fallar cerrado si el contrato canonico deriva. Nunca coalescear una clave
  -- ausente a cero porque convertiria un fallo del servidor en una cifra.
  if pg_catalog.jsonb_typeof(v_mensual) is distinct from 'object'
     or pg_catalog.jsonb_typeof(v_mensual -> 'version')
        is distinct from 'number'
     or pg_catalog.jsonb_typeof(v_mensual -> 'alcance')
        is distinct from 'string'
     or pg_catalog.jsonb_typeof(v_mensual #> '{periodo,mes}')
        is distinct from 'string'
     or pg_catalog.jsonb_typeof(
          v_mensual #> '{ponderacion,referido}'
        ) is distinct from 'number'
     or pg_catalog.jsonb_typeof(v_mensual -> 'cobertura')
        is distinct from 'object'
     or pg_catalog.jsonb_typeof(v_mensual -> 'total')
        is distinct from 'object'
     or pg_catalog.jsonb_typeof(v_mensual -> 'responsables')
        is distinct from 'array' then
    raise exception
      'Contrato interno de conversion mensual inesperado'
      using errcode = '55000';
  end if;

  if (v_mensual ->> 'version')::numeric is distinct from 1
     or (v_mensual ->> 'alcance') is distinct from v_alcance
     or v_mensual #>> '{periodo,mes}'
        is distinct from pg_catalog.to_char(v_mes, 'YYYY-MM')
     or (v_mensual #>> '{ponderacion,referido}')::numeric
        is distinct from v_factor then
    raise exception
      'Contrato interno de conversion mensual inconsistente'
      using errcode = '55000';
  end if;

  -- Cobertura y total viajan hasta Gestión/Directorio. Validarlos aquí evita
  -- que una sonda ausente, un motivo nuevo o un total incoherente se conviertan
  -- en disponibilidad por accidente.
  if not ((v_mensual -> 'cobertura') ?& array[
       'medible',
       'suelo_historico',
       'motivo_no_medible',
       'divisor_aproximado',
       'divisor_por_motivo',
       'cierres_sin_episodio',
       'fuera_de_roster'
     ]::text[])
     or pg_catalog.jsonb_typeof(v_mensual #> '{cobertura,medible}')
        is distinct from 'boolean'
     or pg_catalog.jsonb_typeof(v_mensual #> '{cobertura,suelo_historico}')
        not in ('string', 'null')
     or pg_catalog.jsonb_typeof(v_mensual #> '{cobertura,motivo_no_medible}')
        not in ('string', 'null')
     or pg_catalog.jsonb_typeof(v_mensual #> '{cobertura,divisor_aproximado}')
        is distinct from 'number'
     or pg_catalog.jsonb_typeof(v_mensual #> '{cobertura,divisor_por_motivo}')
        is distinct from 'object'
     or pg_catalog.jsonb_typeof(v_mensual #> '{cobertura,cierres_sin_episodio}')
        is distinct from 'number'
     or pg_catalog.jsonb_typeof(v_mensual #> '{cobertura,fuera_de_roster}')
        is distinct from 'object'
     or not ((v_mensual #> '{cobertura,fuera_de_roster}') ?& array[
       'analistas', 'divisor', 'cierres', 'numerador'
     ]::text[])
     or pg_catalog.jsonb_typeof(v_mensual #> '{cobertura,fuera_de_roster,analistas}')
        is distinct from 'number'
     or pg_catalog.jsonb_typeof(v_mensual #> '{cobertura,fuera_de_roster,divisor}')
        is distinct from 'number'
     or pg_catalog.jsonb_typeof(v_mensual #> '{cobertura,fuera_de_roster,cierres}')
        is distinct from 'number'
     or pg_catalog.jsonb_typeof(v_mensual #> '{cobertura,fuera_de_roster,numerador}')
        is distinct from 'number'
     or not ((v_mensual -> 'total') ?& array[
       'divisor',
       'cierres_no_referidos',
       'cierres_referidos',
       'numerador',
       'conversion_pct',
       'cartera'
     ]::text[])
     or pg_catalog.jsonb_typeof(v_mensual #> '{total,divisor}')
        is distinct from 'number'
     or pg_catalog.jsonb_typeof(v_mensual #> '{total,cierres_no_referidos}')
        is distinct from 'number'
     or pg_catalog.jsonb_typeof(v_mensual #> '{total,cierres_referidos}')
        is distinct from 'number'
     or pg_catalog.jsonb_typeof(v_mensual #> '{total,numerador}')
        is distinct from 'number'
     or pg_catalog.jsonb_typeof(v_mensual #> '{total,conversion_pct}')
        not in ('number', 'null')
     or pg_catalog.jsonb_typeof(v_mensual #> '{total,cartera}')
        is distinct from 'object'
     or not ((v_mensual #> '{total,cartera}') ? 'conversiones_clientes')
     or pg_catalog.jsonb_typeof(
       v_mensual #> '{total,cartera,conversiones_clientes}'
     ) is distinct from 'number' then
    raise exception
      'Cobertura o total interno de conversion mensual incompleto'
      using errcode = '55000';
  end if;

  -- La etapa anterior ya certificó que este nodo es un objeto. Separar la
  -- iteración evita que `jsonb_each` produzca un error nativo antes del 55000
  -- contractual cuando el wrapper trae un tipo anidado corrupto.
  if exists (
    select 1
    from pg_catalog.jsonb_each(
      v_mensual #> '{cobertura,divisor_por_motivo}'
    ) m(clave, valor)
    where pg_catalog.jsonb_typeof(m.valor) is distinct from 'number'
  ) then
    raise exception
      'Cobertura interna: divisor_por_motivo contiene un valor no numerico'
      using errcode = '55000';
  end if;

  if (v_mensual #>> '{cobertura,motivo_no_medible}') is not null
       and (v_mensual #>> '{cobertura,motivo_no_medible}') not in (
         'sin_ledger',
         'anterior_al_ledger',
         'mes_parcial',
         'sin_supervisor',
         'supervisor_inactivo',
         'supervisor_no_es_supervisor'
       )
     or (
       (v_mensual #>> '{cobertura,medible}')::boolean
       and pg_catalog.jsonb_typeof(
         v_mensual #> '{cobertura,motivo_no_medible}'
       ) is distinct from 'null'
     )
     or (
       not (v_mensual #>> '{cobertura,medible}')::boolean
       and pg_catalog.jsonb_typeof(
         v_mensual #> '{cobertura,motivo_no_medible}'
       ) is distinct from 'string'
     )
     or (v_mensual #>> '{cobertura,divisor_aproximado}')::numeric < 0
     or (v_mensual #>> '{cobertura,divisor_aproximado}')::numeric
        <> trunc((v_mensual #>> '{cobertura,divisor_aproximado}')::numeric)
     or (v_mensual #>> '{cobertura,cierres_sin_episodio}')::numeric < 0
     or (v_mensual #>> '{cobertura,cierres_sin_episodio}')::numeric
        <> trunc((v_mensual #>> '{cobertura,cierres_sin_episodio}')::numeric)
     or exists (
       select 1
       from pg_catalog.jsonb_each(
         v_mensual #> '{cobertura,divisor_por_motivo}'
       ) m(clave, valor)
       where (m.valor #>> '{}')::numeric < 0
          or (m.valor #>> '{}')::numeric
             <> trunc((m.valor #>> '{}')::numeric)
     )
     or (v_mensual #>> '{cobertura,fuera_de_roster,analistas}')::numeric < 0
     or (v_mensual #>> '{cobertura,fuera_de_roster,analistas}')::numeric
        <> trunc((v_mensual #>> '{cobertura,fuera_de_roster,analistas}')::numeric)
     or (v_mensual #>> '{cobertura,fuera_de_roster,divisor}')::numeric < 0
     or (v_mensual #>> '{cobertura,fuera_de_roster,divisor}')::numeric
        <> trunc((v_mensual #>> '{cobertura,fuera_de_roster,divisor}')::numeric)
     or (v_mensual #>> '{cobertura,fuera_de_roster,cierres}')::numeric < 0
     or (v_mensual #>> '{cobertura,fuera_de_roster,cierres}')::numeric
        <> trunc((v_mensual #>> '{cobertura,fuera_de_roster,cierres}')::numeric)
     or (v_mensual #>> '{cobertura,fuera_de_roster,numerador}')::numeric < 0
     or (v_mensual #>> '{total,divisor}')::numeric < 0
     or (v_mensual #>> '{total,divisor}')::numeric
        <> trunc((v_mensual #>> '{total,divisor}')::numeric)
     or (v_mensual #>> '{total,cierres_no_referidos}')::numeric < 0
     or (v_mensual #>> '{total,cierres_no_referidos}')::numeric
        <> trunc((v_mensual #>> '{total,cierres_no_referidos}')::numeric)
     or (v_mensual #>> '{total,cierres_referidos}')::numeric < 0
     or (v_mensual #>> '{total,cierres_referidos}')::numeric
        <> trunc((v_mensual #>> '{total,cierres_referidos}')::numeric)
     or (v_mensual #>> '{total,numerador}')::numeric < 0
     or (v_mensual #>> '{total,cartera,conversiones_clientes}')::numeric < 0
     or (v_mensual #>> '{total,cartera,conversiones_clientes}')::numeric
        <> trunc((v_mensual #>> '{total,cartera,conversiones_clientes}')::numeric)
     or (
       case
          when (v_mensual #>> '{total,divisor}')::numeric = 0 then
            pg_catalog.jsonb_typeof(v_mensual #> '{total,conversion_pct}')
              is distinct from 'null'
          else
            pg_catalog.jsonb_typeof(v_mensual #> '{total,conversion_pct}')
              is distinct from 'number'
            or (v_mensual #>> '{total,conversion_pct}')::numeric
               is distinct from round(
                 100.0
                 * (v_mensual #>> '{total,numerador}')::numeric
                 / (v_mensual #>> '{total,divisor}')::numeric,
                 2
               )
       end
     ) then
    raise exception
      'Cobertura o total interno de conversion mensual inconsistente'
      using errcode = '55000';
  end if;

  -- Decisión viva: un mes parcial se VE como provisional. Ausencia real de
  -- ledger o cualquier cierre sin episodio ocultan todo el bundle exacto;
  -- la foto operativa sigue disponible para no tumbar Gestión/Directorio.
  v_conversion_publicable := (
    (v_mensual #>> '{cobertura,medible}')::boolean
    or v_mensual #>> '{cobertura,motivo_no_medible}' = 'mes_parcial'
  ) and (v_mensual #>> '{cobertura,cierres_sin_episodio}')::int = 0;

  if exists (
    select 1
    from pg_catalog.jsonb_array_elements(
      v_mensual -> 'responsables'
    ) as e(value)
    where pg_catalog.jsonb_typeof(e.value) is distinct from 'object'
       or not (
         e.value ?& array[
           'vendedor_id',
           'supervisor_id',
           'divisor',
           'cierres_no_referidos',
           'cierres_referidos',
           'numerador',
           'conversion_pct',
           'cartera'
         ]::text[]
       )
       or pg_catalog.jsonb_typeof(e.value -> 'vendedor_id')
          is distinct from 'string'
       or (e.value ->> 'vendedor_id') !~*
          '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       or pg_catalog.jsonb_typeof(e.value -> 'supervisor_id')
          not in ('string', 'null')
       or (
         pg_catalog.jsonb_typeof(e.value -> 'supervisor_id') = 'string'
         and (e.value ->> 'supervisor_id') !~*
           '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       )
       or pg_catalog.jsonb_typeof(e.value -> 'divisor')
          is distinct from 'number'
       or pg_catalog.jsonb_typeof(e.value -> 'cierres_no_referidos')
          is distinct from 'number'
       or pg_catalog.jsonb_typeof(e.value -> 'cierres_referidos')
          is distinct from 'number'
       or pg_catalog.jsonb_typeof(e.value -> 'numerador')
          is distinct from 'number'
       or pg_catalog.jsonb_typeof(e.value -> 'conversion_pct')
          not in ('number', 'null')
       or pg_catalog.jsonb_typeof(e.value -> 'cartera')
          is distinct from 'object'
       or not (
         (e.value -> 'cartera')
         ? 'conversiones_clientes'
       )
       or pg_catalog.jsonb_typeof(
         e.value #> '{cartera,conversiones_clientes}'
       ) is distinct from 'number'
  ) then
    raise exception
      'Fila interna de conversion mensual incompleta'
      using errcode = '55000';
  end if;

  if exists (
    select 1
    from pg_catalog.jsonb_array_elements(
      v_mensual -> 'responsables'
    ) as e(value)
    where (e.value ->> 'divisor')::numeric < 0
       or (e.value ->> 'divisor')::numeric
          <> trunc((e.value ->> 'divisor')::numeric)
       or (e.value ->> 'cierres_no_referidos')::numeric < 0
       or (e.value ->> 'cierres_no_referidos')::numeric
          <> trunc((e.value ->> 'cierres_no_referidos')::numeric)
       or (e.value ->> 'cierres_referidos')::numeric < 0
       or (e.value ->> 'cierres_referidos')::numeric
          <> trunc((e.value ->> 'cierres_referidos')::numeric)
       or (e.value #>> '{cartera,conversiones_clientes}')::numeric < 0
       or (e.value #>> '{cartera,conversiones_clientes}')::numeric
          <> trunc(
            (e.value #>> '{cartera,conversiones_clientes}')::numeric
          )
       or (e.value ->> 'numerador')::numeric < 0
       or (
         case
            when (e.value ->> 'divisor')::numeric = 0 then
              pg_catalog.jsonb_typeof(e.value -> 'conversion_pct')
                is distinct from 'null'
            else
              pg_catalog.jsonb_typeof(e.value -> 'conversion_pct')
                is distinct from 'number'
              or (e.value ->> 'conversion_pct')::numeric
                 is distinct from round(
                   100.0
                   * (e.value ->> 'numerador')::numeric
                   / (e.value ->> 'divisor')::numeric,
                   2
                 )
         end
       )
  ) then
    raise exception
      'Aritmetica interna de conversion mensual inconsistente'
      using errcode = '55000';
  end if;

  if exists (
    select 1
    from pg_catalog.jsonb_array_elements(
      v_mensual -> 'responsables'
    ) as e(value)
    -- UUID tipado, no texto: variantes de mayusculas/forma no eluden la
    -- unicidad y cualquier identidad invalida falla antes del coalesce.
    group by (e.value ->> 'vendedor_id')::uuid
    having count(*) > 1
  ) then
    raise exception
      'Conversion mensual duplico un responsable'
      using errcode = '55000';
  end if;

  -- Cobertura exacta ANTES de cualquier coalesce. Para el mes actual el
  -- wrapper abierto fabrica una fila incluso cuando el vendedor no produjo:
  -- exactamente una por cada vendedor del roster canonico visible. El mes en
  -- curso no puede estar sellado (cerrar_periodo exige p_periodo < mes actual),
  -- por lo que aqui no existe una excepcion historica legitima.
  --
  -- No se compara contra `roster` de esta RPC: ese roster tambien contiene
  -- supervisor/gerencia, inactivos visibles y vendedores fuera de roster. El
  -- contrato mensual representa solo vendedores activos con supervisor activo;
  -- la produccion fuera de roster queda fuera de responsables/equipos, declarada
  -- en cobertura e incluida en el total global anonimo.
  if exists (
    with esperados as materialized (
      select r.vendedor_id, r.supervisor_id
      from private.roster_metas_vendedores() r
      where v_global
         or r.vendedor_id = any(v_visibles)
    ),
    recibidos as materialized (
      select
        (e.value ->> 'vendedor_id')::uuid as vendedor_id,
        nullif(e.value ->> 'supervisor_id', '')::uuid
          as supervisor_id
      from pg_catalog.jsonb_array_elements(
        v_mensual -> 'responsables'
      ) as e(value)
    )
    select 1
    from esperados x
    full join recibidos r using (vendedor_id)
    where x.vendedor_id is null       -- fila extra / rol no vendedor / fuera
       or r.vendedor_id is null       -- vendedor canonico visible faltante
       or r.supervisor_id is distinct from x.supervisor_id
                                      -- equipo inesperado o contaminado
  ) then
    raise exception
      'Cobertura interna de conversion mensual no coincide con el roster visible'
      using errcode = '55000';
  end if;

  with roster as materialized (
    select e.perfil_id, e.rol_crm, e.activo
    from crm.equipo e
    where e.rol_crm in ('vendedor', 'supervisor', 'gerencia')
      and (
        e.perfil_id = any(v_visibles)
        or v_global
      )
  ),
  ambito as materialized (
    select
      l.id,
      l.moneda,
      coalesce(l.monto_estimado, 0) as monto,
      l.vendedor_id,
      l.asignado_supervisor_id,
      l.creado_en,
      (l.etapa not in ('convertido', 'descartado')) as abierto
    from crm.leads l
    where l.activo is true
      and (
        l.etapa <> 'convertido'
        or l.convertido_en >= v_corte
      )
      and (
        l.vendedor_id = any(v_visibles)
        or (
          l.vendedor_id is null
          and l.asignado_supervisor_id = any(v_visibles)
        )
        or v_global
      )
  ),
  nucleo_mes as materialized (
    select
      (e.value ->> 'vendedor_id')::uuid as analista_id,
      nullif(e.value ->> 'supervisor_id', '')::uuid
        as supervisor_id,
      (e.value ->> 'divisor')::int as divisor,
      (e.value ->> 'cierres_no_referidos')::int
        as cierres_no_referidos,
      (e.value ->> 'cierres_referidos')::int
        as cierres_referidos,
      (e.value ->> 'numerador')::numeric as numerador,
      case
        when pg_catalog.jsonb_typeof(
          e.value -> 'conversion_pct'
        ) = 'number'
        then (e.value ->> 'conversion_pct')::numeric
      end as conversion_pct,
      (e.value #>> '{cartera,conversiones_clientes}')::int
        as operaciones_cartera
    from pg_catalog.jsonb_array_elements(
      v_mensual -> 'responsables'
    ) as e(value)
  ),
  por_vendedor as (
    select
      r.perfil_id,
      r.rol_crm,
      r.activo,
      count(a.id) filter (where a.abierto)::int as activos,
      coalesce(
        sum(a.monto) filter (
          where a.abierto
            and a.moneda is distinct from 'USD'
        ),
        0
      ) as capital_pen,
      coalesce(
        sum(a.monto) filter (
          where a.abierto
            and a.moneda = 'USD'
        ),
        0
      ) as capital_usd,
      (
        coalesce(nm.cierres_no_referidos, 0)
        + coalesce(nm.cierres_referidos, 0)
      )::int as convertidos,
      case
        when v_conversion_publicable and nm.analista_id is not null
        then (nm.cierres_no_referidos + nm.cierres_referidos)::int
      end as nucleo_convertidos,
      case when v_conversion_publicable
        then nm.operaciones_cartera end as operaciones_cartera,
      case when v_conversion_publicable
        then nm.divisor end as nucleo_divisor,
      case when v_conversion_publicable
        then nm.numerador end as nucleo_numerador,
      case when v_conversion_publicable
        then nm.conversion_pct end as nucleo_conversion_pct
    from roster r
    left join ambito a
      on a.vendedor_id = r.perfil_id
    left join nucleo_mes nm
      on nm.analista_id = r.perfil_id
    group by
      r.perfil_id,
      r.rol_crm,
      r.activo,
      nm.analista_id,
      nm.cierres_no_referidos,
      nm.cierres_referidos,
      nm.operaciones_cartera,
      nm.divisor,
      nm.numerador,
      nm.conversion_pct
  ),
  senales as (
    select
      r.perfil_id,
      count(*) filter (where uc.lead_id is null)::int
        as sin_tocar,
      coalesce(
        max(
          extract(
            epoch from (
              v_ahora
              - coalesce(ua.ultima, a.creado_en)
            )
          ) / 86400.0
        ),
        0
      ) as dias_max
    from roster r
    join ambito a
      on a.vendedor_id = r.perfil_id
     and a.abierto
    left join lateral (
      select act.lead_id
      from crm.actividades act
      where act.lead_id = a.id
        and act.tipo in (
          'llamada_realizada',
          'llamada_no_contestada',
          'whatsapp_enviado',
          'whatsapp_recibido',
          'reunion_realizada'
        )
      limit 1
    ) uc on true
    left join lateral (
      select max(act.creado_en) as ultima
      from crm.actividades act
      where act.lead_id = a.id
    ) ua on true
    group by r.perfil_id
  ),
  agg_duenio as (
    select
      a.vendedor_id,
      count(*) filter (where a.abierto)::int as activos,
      coalesce(
        sum(a.monto) filter (
          where a.abierto
            and a.moneda is distinct from 'USD'
        ),
        0
      ) as capital_pen,
      coalesce(
        sum(a.monto) filter (
          where a.abierto
            and a.moneda = 'USD'
        ),
        0
      ) as capital_usd
    from ambito a
    where a.vendedor_id is not null
    group by a.vendedor_id
  ),
  parkeados_bandeja as (
    select
      a.asignado_supervisor_id as supervisor_id,
      count(*)::int as n
    from ambito a
    where a.abierto
      and a.vendedor_id is null
      and a.asignado_supervisor_id is not null
    group by a.asignado_supervisor_id
  ),
  nucleo_equipos as (
    select
      nm.supervisor_id,
      sum(
        nm.cierres_no_referidos
        + nm.cierres_referidos
      )::int as convertidos,
      sum(nm.operaciones_cartera)::int
        as operaciones_cartera,
      sum(nm.divisor)::int as nucleo_divisor,
      sum(nm.numerador)::numeric as nucleo_numerador
    from nucleo_mes nm
    where nm.supervisor_id is not null
    group by nm.supervisor_id
  ),
  equipos_calc as (
    select
      s.perfil_id as supervisor_id,
      directos.n as vendedores,
      stats.activos,
      stats.capital_pen,
      stats.capital_usd,
      coalesce(ne.convertidos, 0)::int as convertidos,
      case when v_conversion_publicable and cobertura.completa
        then coalesce(ne.convertidos, 0)::int
      end as nucleo_convertidos,
      case when v_conversion_publicable and cobertura.completa
        then coalesce(ne.operaciones_cartera, 0)::int
      end as operaciones_cartera,
      case when v_conversion_publicable and cobertura.completa
        then coalesce(ne.nucleo_divisor, 0)::int
      end as nucleo_divisor,
      case when v_conversion_publicable and cobertura.completa
        then coalesce(ne.nucleo_numerador, 0::numeric)
      end as nucleo_numerador,
      case
        when v_conversion_publicable
          and cobertura.completa
          and coalesce(ne.nucleo_divisor, 0) > 0
        then round(
          100.0
          * coalesce(ne.nucleo_numerador, 0::numeric)
          / ne.nucleo_divisor,
          2
        )
      end as nucleo_conversion_pct,
      coalesce(pb.n, 0)::int as parkeados
    from roster s
    cross join lateral (
      select count(*)::int as n
      from crm.equipo m
      where m.supervisor_id = s.perfil_id
        and m.activo is true
    ) directos
    cross join lateral (
      select not exists (
        select 1
        from (
          select m.perfil_id as vendedor_id
          from crm.equipo m
          where m.supervisor_id = s.perfil_id
            and m.activo is true
            and m.rol_crm = 'vendedor'
        ) d
        full join (
          select nm.analista_id as vendedor_id
          from nucleo_mes nm
          where nm.supervisor_id = s.perfil_id
        ) c on c.vendedor_id = d.vendedor_id
        where d.vendedor_id is null
           or c.vendedor_id is null
      ) as completa
    ) cobertura
    cross join lateral (
      select
        coalesce(sum(ad.activos), 0)::int as activos,
        coalesce(sum(ad.capital_pen), 0) as capital_pen,
        coalesce(sum(ad.capital_usd), 0) as capital_usd
      from agg_duenio ad
      where ad.vendedor_id = s.perfil_id
         or ad.vendedor_id in (
           select m.perfil_id
           from crm.equipo m
           where m.supervisor_id = s.perfil_id
             and m.activo is true
         )
    ) stats
    left join nucleo_equipos ne
      on ne.supervisor_id = s.perfil_id
    left join parkeados_bandeja pb
      on pb.supervisor_id = s.perfil_id
    where s.rol_crm = 'supervisor'
      and s.activo is true
      and private.rol_crm(s.perfil_id) = 'supervisor'
  )
  select jsonb_build_object(
    'version', 1,
    'generado_en', v_ahora,
    'ventana_convertidos_dias', 45,
    'ventana_metrica', 'mes_calendario',
    'mes_metrica', v_mes,
    'peso_referido', v_factor,
    'cobertura_conversion', v_mensual -> 'cobertura',
    -- Proyección exacta del total del wrapper: incluye fuera-de-roster desde
    -- F2.6. Nunca se recompone sumando equipos, porque ese agregado no tiene
    -- identidad.
    'nucleo_total', jsonb_build_object(
      'nucleo_convertidos', case when v_conversion_publicable then
        (v_mensual #>> '{total,cierres_no_referidos}')::int
        + (v_mensual #>> '{total,cierres_referidos}')::int
      end,
      'operaciones_cartera', case when v_conversion_publicable then
        (v_mensual #>> '{total,cartera,conversiones_clientes}')::int
      end,
      'nucleo_divisor', case when v_conversion_publicable then
        (v_mensual #>> '{total,divisor}')::int
      end,
      'nucleo_numerador', case when v_conversion_publicable then
        (v_mensual #>> '{total,numerador}')::numeric
      end,
      'nucleo_conversion_pct', case
        when v_conversion_publicable
          and pg_catalog.jsonb_typeof(
            v_mensual #> '{total,conversion_pct}'
          ) = 'number'
        then (v_mensual #>> '{total,conversion_pct}')::numeric
      end
    ),
    'vendedores', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'vendedor_id', pv.perfil_id,
            'rol_crm', pv.rol_crm,
            'activo', pv.activo,
            'activos', pv.activos,
            'capital_pen', pv.capital_pen,
            'capital_usd', pv.capital_usd,
            'convertidos', pv.convertidos,
            'nucleo_convertidos', pv.nucleo_convertidos,
            'operaciones_cartera', pv.operaciones_cartera,
            'nucleo_divisor', pv.nucleo_divisor,
            'nucleo_numerador', pv.nucleo_numerador,
            'nucleo_conversion_pct',
              pv.nucleo_conversion_pct,
            'sin_tocar', coalesce(sn.sin_tocar, 0),
            'dias_sin_actividad_max',
              round(coalesce(sn.dias_max, 0), 4)
          )
          order by
            pv.capital_pen desc,
            pv.perfil_id
        )
        from por_vendedor pv
        left join senales sn
          on sn.perfil_id = pv.perfil_id
      ),
      '[]'::jsonb
    ),
    'equipos', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'supervisor_id', ec.supervisor_id,
            'vendedores', ec.vendedores,
            'activos', ec.activos,
            'capital_pen', ec.capital_pen,
            'capital_usd', ec.capital_usd,
            'convertidos', ec.convertidos,
            'nucleo_convertidos', ec.nucleo_convertidos,
            'operaciones_cartera',
              ec.operaciones_cartera,
            'nucleo_divisor', ec.nucleo_divisor,
            'nucleo_numerador', ec.nucleo_numerador,
            'nucleo_conversion_pct',
              ec.nucleo_conversion_pct,
            'parkeados', ec.parkeados
          )
          order by
            ec.capital_pen desc,
            ec.supervisor_id
        )
        from equipos_calc ec
      ),
      '[]'::jsonb
    )
  )
  into v_payload;

  return v_payload;
end;
$function$;

comment on function crm.metricas_vendedores_fn() is
  'Vista operativa de 45 dias para activos, capital y senales; conversion del mes calendario tomada del contrato canonico crm.conversion_mensual_fn. Propaga cobertura literal y una proyeccion exacta renombrada del total del wrapper (incluido fuera-de-roster). Por vendedor y equipo expone nucleo_convertidos, divisor, numerador neto, porcentaje exacto nullable y operaciones de cartera. Mes parcial se publica provisional; sin ledger, cierre sin episodio, fila fuera de roster o equipo con roster incompleto dejan el bundle exacto en NULL sin borrar activos/capital. Los equipos suman numeradores/divisores por supervisor_id y nunca promedian porcentajes. La clave legacy convertidos queda por compatibilidad temporal; el entero conversion_pct se retiro el 21/09/2026 porque redondeaba y fabricaba un 0 donde la verdad es no medible. Coordinador conserva cobertura NULL y vendedores/equipos vacios.';

revoke all on function crm.metricas_vendedores_fn()
  from public, anon, authenticated, service_role;

grant execute on function crm.metricas_vendedores_fn()
  to authenticated;

-- La razon de esta funcion en el trinquete, refrescada con la huella del cuerpo
-- NUEVO y con la mencion del entero retirado. Si no se hiciera, el vigilante
-- diria «la razon caduco» y tendria razon.
update private.analitica_leads_citas_exenciones e
set huella = md5(regexp_replace(regexp_replace(lower(coalesce(p.prosrc, pg_get_functiondef(p.oid))),
      '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g')),
    razon = 'MIXTA: la metrica es MENSUAL y viene de crm.conversion_mensual_fn (nucleo por transitividad), rotulada ventana_metrica=mes_calendario; sus counts crudos son la VISTA de 45 dias (que convertidos siguen visibles en cartera) y estan rotulados como vista. Desde el 21/09/2026 ya no publica el entero conversion_pct, que redondeaba el porcentaje exacto del nucleo y fabricaba un 0 donde la verdad es no medible; las cifras del nucleo (nucleo_divisor, nucleo_numerador, nucleo_conversion_pct, nucleo_convertidos, operaciones_cartera) no cambian.',
    declarado_en = now()
from pg_catalog.pg_proc p
where p.oid = 'crm.metricas_vendedores_fn()'::regprocedure
  and e.objeto = 'crm.metricas_vendedores_fn()';

update private.analitica_lc_sello
  set sello = private.huella_exenciones_analitica_lc(), sellado_en = now()
  where id;

do $postflight$
declare
  v_src text;
  v_md5 text;
  v_owner text;
  v_secdef boolean;
  v_volatility "char";
  v_config text[];
begin
  select p.prosrc, pg_catalog.md5(p.prosrc), r.rolname, p.prosecdef, p.provolatile, p.proconfig
    into v_src, v_md5, v_owner, v_secdef, v_volatility, v_config
  from pg_catalog.pg_proc p
  join pg_catalog.pg_roles r on r.oid = p.proowner
  where p.oid = 'crm.metricas_vendedores_fn()'::regprocedure;

  -- (a) El cuerpo instalado es exactamente el candidato auditado.
  if v_md5 is distinct from '9675b589f24c595ad58ead3d767b083c' then
    raise exception 'POSTFLIGHT F1: cuerpo inesperado (% vs 9675b589f24c595ad58ead3d767b083c)', v_md5;
  end if;
  -- (b) Las dos proyecciones del entero han desaparecido. `strpos`, nunca LIKE:
  --     el guion bajo es comodin (trampa del vault).
  if pg_catalog.strpos(v_src, 'then round(pv.nucleo_conversion_pct)::int') > 0
     or pg_catalog.strpos(v_src, 'then round(ec.nucleo_conversion_pct)::int') > 0 then
    raise exception 'POSTFLIGHT F1: el entero conversion_pct sigue en la salida';
  end if;
  -- (c) El contrato de ENTRADA con conversion_mensual_fn sigue intacto.
  if pg_catalog.strpos(v_src, '{total,conversion_pct}') = 0
     or pg_catalog.strpos(v_src, 'e.value -> ''conversion_pct''') = 0
     or pg_catalog.strpos(v_src, '''nucleo_conversion_pct'',') = 0 then
    raise exception 'POSTFLIGHT F1: el contrato de entrada o las claves nucleo_* no estan';
  end if;
  -- (d) Owner, definer, stable y search_path vacio CON comillas (trampa del vault).
  if v_owner is distinct from 'postgres'
     or not v_secdef
     or v_volatility is distinct from 's'
     or v_config is distinct from array['search_path=""']::text[] then
    raise exception 'POSTFLIGHT F1: owner/secdef/stable/search_path inesperados';
  end if;
  -- (e) ACL: solo postgres y authenticated pueden ejecutarla.
  if not exists (
    select 1 from pg_catalog.pg_proc p
    cross join lateral pg_catalog.aclexplode(coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))) a
    join pg_catalog.pg_roles g on g.oid = a.grantee
    where p.oid = 'crm.metricas_vendedores_fn()'::regprocedure
      and g.rolname = 'authenticated' and a.privilege_type = 'EXECUTE' and not a.is_grantable
  ) or exists (
    select 1 from pg_catalog.pg_proc p
    cross join lateral pg_catalog.aclexplode(coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))) a
    left join pg_catalog.pg_roles g on g.oid = a.grantee
    where p.oid = 'crm.metricas_vendedores_fn()'::regprocedure
      and a.privilege_type = 'EXECUTE'
      and coalesce(g.rolname, 'PUBLIC') not in ('postgres', 'authenticated')
  ) then
    raise exception 'POSTFLIGHT F1: ACL fuera de allowlist';
  end if;
  if not pg_catalog.has_function_privilege('authenticated', 'crm.metricas_vendedores_fn()', 'EXECUTE')
     or pg_catalog.has_function_privilege('anon', 'crm.metricas_vendedores_fn()', 'EXECUTE')
     or pg_catalog.has_function_privilege('service_role', 'crm.metricas_vendedores_fn()', 'EXECUTE') then
    raise exception 'POSTFLIGHT F1: privilegios efectivos inesperados';
  end if;
  -- (f) Su declaracion en el trinquete sigue vigente con el cuerpo NUEVO.
  if not exists (
    select 1 from private.contadores_crudos_leads_citas() c
    where c.objeto = 'crm.metricas_vendedores_fn()' and c.declarada and c.huella_ok
  ) then
    raise exception 'POSTFLIGHT F1: la declaracion de metricas_vendedores_fn quedo caducada tras el reemplazo';
  end if;
  if (select sello from private.analitica_lc_sello where id)
     is distinct from private.huella_exenciones_analitica_lc() then
    raise exception 'POSTFLIGHT F1: el sello del trinquete no coincide con las exenciones';
  end if;
end;
$postflight$;

commit;
