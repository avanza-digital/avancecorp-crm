-- ORÁCULO de «El servidor exige el número de contrato» — se ejecuta en el LABORATORIO (banco Docker local),
-- NUNCA contra producción, y no escribe nada.
--
-- La regla (decisiones D-11, D-12, D-16 y D-17 de Miguel; plan AVANCE-BACKEND-0610, bloque 2.3): `public.crear_contrato`
-- rechaza cualquier número de contrato que no sea `2024-01-NNNNNN`, `2025-01-NNNNNN` o `2026-01-NNNNNN` (seis dígitos,
-- ASCII), incluido el vacío o un espacio, con SQLSTATE 22023 y el mensaje fijo, en vez de inventar `AC-AAAA-NNNN`; por la
-- llamada directa y por las puertas `crm.*` que la envuelven. Excepción (D-17): quien es a la vez admin o superadmin del
-- Portal y Gerencia del CRM (`public.es_admin()` y `private.es_gerencia_crm_activa()`) conserva el comportamiento de hoy:
-- autogenera `AC-AAAA-NNNN` si va vacío y acepta cualquier número no duplicado.
--
-- Este archivo NO se ejecuta a mano: `armar-ensayo.mjs` lo pega DETRÁS de la migración real (a la que quita su
-- `begin;`/`commit;`) dentro de una única transacción que termina en `rollback`. Con `--sin-migracion` lo pega solo, y
-- entonces TIENE que salir ROJO: es la medición del defecto (el servidor acepta, o autogenera, un número fuera de forma).
--
-- Quién llama: la sesión del banco con la identidad del actor en los claims del JWT (las funciones son `security definer` y
-- deciden por `auth.uid()`), fijada en las DOS formas (`request.jwt.claim.sub` y `request.jwt.claims`). NO se cambia de
-- rol con `set role`: llamar bajo `set role` a una función sin EXECUTE tumba el Postgres del banco, así que los permisos
-- se leen del catálogo (sección 9) y nunca se prueban llamando.
--
-- Cada rechazo compara una foto de antes y de después (contratos, cronograma, titulares, operaciones de cartera, cuentas
-- bancarias, vínculos cuenta-contrato, inversiones, libro de rentabilidad, jobs de PDF, altas idempotentes) y además DESHACE
-- lo que la llamada hubiera dejado si el servidor hubiera aceptado, para que cada caso sea independiente de los demás.

set local statement_timeout = '300s';

create temp sequence ens_seq;

-- Identidad de la sesión, en las DOS formas de los claims.
create function pg_temp.sesion(p_actor uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(p_actor::text, ''), true),
         set_config('request.jwt.claims',
           case when p_actor is null then '' else json_build_object('sub', p_actor, 'role', 'authenticated')::text end, true);
$$;

-- Acumulador del informe: un caso que pasa suma una línea «ok»; uno que falla, un fallo con su texto.
create function pg_temp.reg(p_caso text, p_txt text) returns void language plpgsql as $f$
begin
  if p_txt = '' then
    perform set_config('ensayo.oks', coalesce(current_setting('ensayo.oks', true), '') || 'ok ' || p_caso || E'\n', true);
  else
    perform set_config('ensayo.fallos',
      (coalesce(nullif(current_setting('ensayo.fallos', true), ''), '0')::integer + 1)::text, true);
    perform set_config('ensayo.informe', coalesce(current_setting('ensayo.informe', true), '') || p_txt, true);
  end if;
end;
$f$;

-- Foto de todo lo que un alta de contrato puede tocar.
create function pg_temp.foto() returns text language sql as $$
  select format('contratos=%s[%s] cronograma=%s titulares=%s operaciones=%s cuentas=%s[%s] cuenta_contrato=%s inversiones=%s ledger=%s jobs_pdf=%s altas_idem=%s',
    (select count(*) from public.contratos),
    (select md5(coalesce(string_agg(c.id::text || '|' || c.numero_contrato || '|' || c.estado || '|' || coalesce(c.renovado_a_id::text, '-'), ',' order by c.id), '')) from public.contratos c),
    (select count(*) from public.cronograma_pagos),
    (select count(*) from public.contrato_titulares),
    (select count(*) from crm.operaciones_cartera),
    (select count(*) from crm.cuentas_bancarias),
    (select md5(coalesce(string_agg(cb.id::text || '|' || cb.activa::text, ',' order by cb.id), '')) from crm.cuentas_bancarias cb),
    (select count(*) from crm.contrato_cuentas_pago),
    (select count(*) from crm.inversiones),
    (select count(*) from crm.ledger_rentabilidad),
    (select count(*) from private.contrato_pdf_jobs),
    (select count(*) from private.contrato_altas_idempotentes));
$$;

-- El `p_contrato` de un alta. p_numero: texto = esa clave; '__SIN_CLAVE__' = sin la clave numero_contrato;
-- '__JSON_NULL__' = la clave con JSON null.
create function pg_temp.contrato(p_cliente uuid, p_analista uuid, p_numero text, p_categoria text default 'nuevo',
                                 p_extra jsonb default '{}'::jsonb)
returns jsonb language sql as $$
  select (jsonb_build_object('cliente_id', p_cliente, 'capital', 500, 'moneda', 'PEN', 'tasa_anual', 15,
            'modalidad', 'mensual', 'tipo_interes', 'simple',
            'fecha_inicio', (now() at time zone 'America/Lima')::date,
            'fecha_vencimiento', (now() at time zone 'America/Lima')::date + 365,
            'categoria', p_categoria, 'analista_cierre_id', p_analista)
          || case p_numero
               when '__SIN_CLAVE__' then '{}'::jsonb
               when '__JSON_NULL__' then jsonb_build_object('numero_contrato', null::text)
               else jsonb_build_object('numero_contrato', p_numero) end) || p_extra;
$$;

create function pg_temp.cron() returns jsonb language sql as $$
  select jsonb_build_array(jsonb_build_object('numero_cuota', 1,
           'fecha_programada', (now() at time zone 'America/Lima')::date + 30, 'monto_programado', 100, 'tipo', 'cuota'));
$$;

-- Una cuenta bancaria nueva distinta en cada llamada (solo letras y números, como exige la puerta).
create function pg_temp.cuenta() returns jsonb language plpgsql as $f$
declare v_n integer := nextval('pg_temp.ens_seq');
begin
  return jsonb_build_object('tipo', 'nueva', 'banco', 'BANCO ENS', 'tipo_cuenta', 'ahorros',
    'numero_cuenta', 'ENS' || v_n, 'cci', '0020000000000000' || lpad(v_n::text, 4, '0'), 'titular_distinto', false);
end;
$f$;

-- Llama a UNA puerta como el actor de la sesión. p_via: 'directa' (public.crear_contrato) | 'crm'
-- (crm.crear_contrato_con_cuenta_pdf_v2, concedida a authenticated). 'ok|<respuesta>' o 'SQLSTATE|mensaje|pista'.
-- El bloque con EXCEPTION es una subtransacción: un rechazo deshace TODO lo que la llamada había hecho (cuenta nueva incluida).
create function pg_temp.llamar(p_via text, p_actor uuid, p_contrato jsonb, p_cuenta jsonb default null)
returns text language plpgsql as $f$
declare
  v_r    jsonb;
  v_hint text;
begin
  perform pg_temp.sesion(p_actor);
  perform set_config('crm.producto_condicion_id', '', true);
  if p_via = 'directa' then
    v_r := public.crear_contrato(p_contrato, pg_temp.cron());
  else
    v_r := crm.crear_contrato_con_cuenta_pdf_v2(p_contrato, pg_temp.cron(), coalesce(p_cuenta, pg_temp.cuenta()));
  end if;
  perform pg_temp.sesion(null);
  return 'ok|' || v_r::text;
exception when others then
  get stacked diagnostics v_hint = pg_exception_hint;
  perform pg_temp.sesion(null);
  return sqlstate || '|' || sqlerrm || '|' || coalesce(v_hint, '');
end;
$f$;

-- Exige el RECHAZO de la regla (SQLSTATE, mensaje exacto y sin pista) y la foto intacta. Si el servidor aceptó, deshace lo
-- que dejó (para que el siguiente caso no choque con un duplicado) DESPUÉS de fotografiarlo.
create function pg_temp.exigir_rechazo(p_caso text, p_via text, p_actor uuid, p_contrato jsonb, p_nombre_actor text)
returns text language plpgsql as $f$
declare
  v_esperado constant text := '22023|Formato de número de contrato inválido: serie 2024-01-, 2025-01- o 2026-01- seguida de exactamente 6 dígitos|';
  v_antes text := pg_temp.foto();
  v_res text;
  v_despues text;
  v_motivos text[] := '{}';
begin
  begin
    v_res := pg_temp.llamar(p_via, p_actor, p_contrato);
    v_despues := pg_temp.foto();
    raise exception using errcode = 'ZZRB1', message = 'deshacer lo que la llamada hubiera dejado';
  exception when sqlstate 'ZZRB1' then null;
  end;
  if v_res like 'ok|%' then
    v_motivos := v_motivos || format('el servidor ACEPTÓ el número (guardó o autogeneró «%s»)', (substr(v_res, 4)::jsonb) ->> 'numero_contrato');
  elsif v_res <> v_esperado then
    v_motivos := v_motivos || ('rechazó, pero no con la regla: ' || v_res);
  end if;
  if v_despues is distinct from v_antes then
    v_motivos := v_motivos || format('no quedó como estaba: [%s] → [%s]', v_antes, v_despues);
  end if;
  if pg_temp.foto() is distinct from v_antes then
    v_motivos := v_motivos || 'el ensayo no pudo deshacer la llamada (error de montaje)';
  end if;
  if cardinality(v_motivos) = 0 then return ''; end if;
  return format(E'FALLO %s (%s · %s): %s\n', p_caso, p_via, p_nombre_actor, array_to_string(v_motivos, '; '));
end;
$f$;

-- Exige un rechazo DE SIEMPRE (42501, duplicado…): texto exacto y foto intacta.
create function pg_temp.exigir_texto(p_caso text, p_via text, p_actor uuid, p_contrato jsonb, p_nombre_actor text, p_esperado text)
returns text language plpgsql as $f$
declare
  v_antes text := pg_temp.foto();
  v_res text;
  v_despues text;
  v_motivos text[] := '{}';
begin
  begin
    v_res := pg_temp.llamar(p_via, p_actor, p_contrato);
    v_despues := pg_temp.foto();
    raise exception using errcode = 'ZZRB1', message = 'deshacer';
  exception when sqlstate 'ZZRB1' then null;
  end;
  if v_res like 'ok|%' then
    v_motivos := v_motivos || format('el servidor ACEPTÓ (número «%s»)', (substr(v_res, 4)::jsonb) ->> 'numero_contrato');
  elsif v_res <> p_esperado then
    v_motivos := v_motivos || ('rechazó, pero no como siempre: ' || v_res);
  end if;
  if v_despues is distinct from v_antes then
    v_motivos := v_motivos || format('no quedó como estaba: [%s] → [%s]', v_antes, v_despues);
  end if;
  if cardinality(v_motivos) = 0 then return ''; end if;
  return format(E'FALLO %s (%s · %s): %s\n', p_caso, p_via, p_nombre_actor, array_to_string(v_motivos, '; '));
end;
$f$;

-- El número que autogenera hoy `private.siguiente_numero_contrato(año de Lima)`, calculado aparte (como GCAR-C18).
create function pg_temp.autogenerado_esperado() returns text language sql as $$
  select 'AC-' || y.v || '-' || lpad((coalesce(max(split_part(c.numero_contrato, '-', 3)::integer), 0) + 1)::text, 4, '0')
  from (select extract(year from now() at time zone 'America/Lima')::integer as v) y
  left join public.contratos c on c.numero_contrato ~ ('^AC-' || y.v || '-[0-9]{1,4}$')
  group by y.v;
$$;

-- Exige que el alta ENTRE con el número esperado (o con el autogenerado de hoy, si p_autogen), con su cronograma y, por la
-- puerta `crm`, su cuenta vinculada; y que lo diferido sobreviva al COMMIT. Los efectos se conservan (los casos siguientes
-- los usan: duplicados, renovaciones).
create function pg_temp.exigir_acepta(p_caso text, p_via text, p_actor uuid, p_contrato jsonb, p_nombre_actor text,
                                      p_numero text, p_autogen boolean default false)
returns text language plpgsql as $f$
declare
  v_esperado text := case when p_autogen then pg_temp.autogenerado_esperado() else p_numero end;
  v_res text;
  v_r jsonb;
  v_id uuid;
  v_out text := '';
begin
  v_res := pg_temp.llamar(p_via, p_actor, p_contrato);
  if v_res not like 'ok|%' then
    return format(E'FALLO %s (%s · %s): debía entrar y se rechazó (%s)\n', p_caso, p_via, p_nombre_actor, v_res);
  end if;
  v_r := substr(v_res, 4)::jsonb;
  v_id := (v_r ->> 'id')::uuid;
  if v_r ->> 'numero_contrato' is distinct from v_esperado then
    v_out := v_out || format(E'FALLO %s (%s · %s): el número de la respuesta es «%s» y se esperaba «%s»\n', p_caso, p_via, p_nombre_actor, v_r ->> 'numero_contrato', v_esperado);
  end if;
  if not exists (select 1 from public.contratos c where c.id = v_id and c.numero_contrato = v_esperado) then
    v_out := v_out || format(E'FALLO %s (%s · %s): el contrato no quedó guardado con el número «%s»\n', p_caso, p_via, p_nombre_actor, v_esperado);
  end if;
  if (select count(*) from public.cronograma_pagos cp where cp.contrato_id = v_id) <> 1 then
    v_out := v_out || format(E'FALLO %s (%s · %s): el cronograma del contrato no quedó con su única cuota\n', p_caso, p_via, p_nombre_actor);
  end if;
  if p_via = 'crm' and not exists (select 1 from crm.contrato_cuentas_pago ccp where ccp.contrato_id = v_id) then
    v_out := v_out || format(E'FALLO %s (%s · %s): el contrato no quedó vinculado a su cuenta de pago\n', p_caso, p_via, p_nombre_actor);
  end if;
  begin
    set constraints all immediate;
  exception when others then
    v_out := v_out || format(E'FALLO %s (%s · %s): el alta no sobreviviría al COMMIT (%s %s)\n', p_caso, p_via, p_nombre_actor, sqlstate, sqlerrm);
  end;
  -- SET CONSTRAINTS dura hasta el final de la transacción: se devuelve al modo normal (diferido), o la siguiente
  -- renovación/upgrade chocaría con su cinturón de commit antes de que nazca su operación de cartera.
  set constraints all deferred;
  return v_out;
end;
$f$;

-- Lo malo que el servidor debe rechazar. Los literales del banco (ABC, 2026-01-12, 2027-01-000009, AC-2026-0001) ya
-- existen en este laboratorio como restos de la fila 2 del banco: si existen se usa una variante de la misma forma, para
-- que el rechazo medido sea el de la forma y no el de «ya existe». El caso «inválido y además duplicado» se mide aparte.
create temp table ens_malos (id text primary key, valor text not null, nota text not null);
insert into ens_malos (id, valor, nota)
select m.id,
       case when exists (select 1 from public.contratos c where c.numero_contrato = m.lit) then m.vari else m.lit end,
       case when exists (select 1 from public.contratos c where c.numero_contrato = m.lit)
            then 'variante «' || m.vari || '» (el literal «' || m.lit || '» ya existe en el laboratorio)' else 'literal' end
from (values
  ('b04-ABC',                'ABC',            'ABC-E'),
  ('b05-2026-01-12',         '2026-01-12',     '2026-01-13'),
  ('b06-2027-01-000009',     '2027-01-000009', '2027-01-000010'),
  ('b10-AC-2026-0001',       'AC-2026-0001',   'AC-2026-0099')) as m(id, lit, vari);
insert into ens_malos (id, valor, nota) values
  ('b01-sin-clave',          '__SIN_CLAVE__',                  'sin la clave numero_contrato'),
  ('b02-vacio',              '',                               'cadena vacía'),
  ('b03-espacio',            ' ',                              'un espacio'),
  ('b03b-solo-tab',          E'\t',                            'solo un tabulador (btrim no lo recorta)'),
  ('b03c-json-null',         '__JSON_NULL__',                  'la clave con JSON null'),
  ('b07-cinco-digitos',      '2026-01-12345',                  '5 dígitos'),
  ('b08-siete-digitos',      '2026-01-1234567',                '7 dígitos'),
  ('b09-no-ascii',           '2026-01-' || E'٠٠٠٠٠٩', '6 dígitos arábigo-índicos'),
  ('b09b-mixto-no-ascii',    '2026-01-00000' || E'٩',     '5 ASCII + 1 arábigo-índico'),
  ('b11-salto-final',        '2026-01-000011' || E'\n',        'válido con salto de línea final'),
  ('b11b-salto-inicial',     E'\n' || '2026-01-000011',        'válido con salto de línea inicial'),
  ('b11c-tab-final',         '2026-01-000011' || E'\t',        'válido con tabulador final'),
  ('b12-prefijo',            'X2026-01-000011',                'basura delante de un número válido'),
  ('b12b-prefijo-digito',    '02026-01-000011',                'un dígito delante de un número válido'),
  ('b13-sufijo',             '2026-01-000011X',                'basura detrás de un número válido'),
  ('b14-serie-vieja',        '2023-01-000011',                 'serie 2023'),
  ('b15-mes-distinto',       '2026-02-000011',                 'el 01 es fijo, no el mes'),
  ('b16-un-digito-de-mes',   '2026-1-000011',                  'mes de un dígito'),
  ('b17-letra',              '2026-01-00001A',                 'una letra entre los seis'),
  ('b18-dos-numeros',        '2026-01-000011 2026-01-000012',  'dos números separados por espacio');

do $ensayo$
declare
  v_msg constant text := 'Formato de número de contrato inválido: serie 2024-01-, 2025-01- o 2026-01- seguida de exactamente 6 dígitos';
  v_esperado constant text := '22023|' || v_msg || '|';
  v_anio constant integer := extract(year from now() at time zone 'America/Lima')::integer;
  v_ger_admin uuid; v_ger_super uuid; v_ger_hist uuid; v_admin uuid; v_superadmin uuid;
  v_vend uuid; v_vend3 uuid; v_sup uuid; v_cli1 uuid; v_cli3 uuid;
  v_actor uuid; v_nombre text; v_via text; v_i integer;
  v_m record;
  v_texto text; v_res text; v_res2 text; v_otros text; v_r jsonb; v_r2 jsonb;
  v_clave uuid; v_cuenta jsonb; v_contrato jsonb; v_antes text; v_n integer;
  v_origen_r uuid; v_origen_u uuid; v_ini date := (now() at time zone 'America/Lima')::date;
  v_nuevo text;
begin
  perform set_config('ensayo.oks', '', true);
  perform set_config('ensayo.fallos', '0', true);
  perform set_config('ensayo.informe', '', true);
  perform set_config('ensayo.medidas', '', true);

  -- ── Actores reales del banco (OBLIGATORIOS: sin ellos un caso se saltaría en silencio) ──────────────────────────
  select p.id into v_ger_admin  from public.perfiles p where p.nombre_completo = 'PASO08 GER_ADMIN';
  select p.id into v_ger_super  from public.perfiles p where p.nombre_completo = 'PASO08 GER_SUPER';
  select p.id into v_ger_hist   from public.perfiles p where p.nombre_completo = 'PASO08 GERENCIA';
  select p.id into v_admin      from public.perfiles p where p.nombre_completo = 'PASO08 ADMIN';
  select p.id into v_superadmin from public.perfiles p where p.nombre_completo = 'PASO08 SUPERADMIN';
  select p.id into v_vend       from public.perfiles p where p.nombre_completo = 'PASO08 VEND1';
  select p.id into v_vend3      from public.perfiles p where p.nombre_completo = 'PASO08 VEND3';
  select p.id into v_sup        from public.perfiles p where p.nombre_completo = 'PASO08 SUP1';
  select p.id into v_cli1       from public.perfiles p where p.nombre_completo = 'PASO08 CLI1';
  select p.id into v_cli3       from public.perfiles p where p.nombre_completo = 'PASO08 CLI3';
  if v_ger_admin is null or v_ger_super is null or v_ger_hist is null or v_admin is null or v_superadmin is null
     or v_vend is null or v_vend3 is null or v_sup is null or v_cli1 is null or v_cli3 is null then
    raise exception 'ENSAYO ABORTADO: faltan actores (ger_admin=%, ger_super=%, gerencia=%, admin=%, superadmin=%, vend1=%, vend3=%, sup1=%, cli1=%, cli3=%)',
      v_ger_admin, v_ger_super, v_ger_hist, v_admin, v_superadmin, v_vend, v_vend3, v_sup, v_cli1, v_cli3;
  end if;
  -- Y cada uno es el par que se declaró (rol del Portal + rol del CRM): si el banco derivó, el ensayo no prueba lo que dice.
  if (select p.rol from public.perfiles p where p.id = v_ger_admin) is distinct from 'admin'
     or private.rol_crm(v_ger_admin) is distinct from 'gerencia'
     or (select p.rol from public.perfiles p where p.id = v_ger_super) is distinct from 'superadmin'
     or private.rol_crm(v_ger_super) is distinct from 'gerencia'
     or (select p.rol from public.perfiles p where p.id = v_ger_hist) is distinct from 'comercial'
     or private.rol_crm(v_ger_hist) is distinct from 'gerencia'
     or (select p.rol from public.perfiles p where p.id = v_admin) is distinct from 'admin'
     or private.rol_crm(v_admin) is not null
     or (select p.rol from public.perfiles p where p.id = v_superadmin) is distinct from 'superadmin'
     or private.rol_crm(v_superadmin) is not null
     or private.rol_crm(v_vend) is distinct from 'vendedor'
     or private.rol_crm(v_vend3) is distinct from 'vendedor'
     or private.rol_crm(v_sup) is distinct from 'supervisor'
     or (select p.asesor_perfil_id from public.perfiles p where p.id = v_cli1) is distinct from v_vend
     or (select p.asesor_perfil_id from public.perfiles p where p.id = v_cli3) is distinct from v_vend3 then
    raise exception 'ENSAYO ABORTADO: un actor del banco no es el par esperado (ger_admin admin+gerencia, ger_super superadmin+gerencia, gerencia comercial+gerencia, admin y superadmin sin ficha, vend1/vend3/sup1, cli1 de vend1, cli3 de vend3)';
  end if;

  -- ── Los números BUENOS que el ensayo va a crear tienen que estar libres (si no, un duplicado taparía lo que se mide) ──
  select string_agg(c.numero_contrato, ', ') into v_texto from public.contratos c
   where c.numero_contrato in ('2024-01-000000', '2025-01-123456', '2026-01-000009', '2026-01-999999', '2026-01-000012',
     '2026-01-000020', '2026-01-000021', '2026-01-000030', '2026-01-000040', '2026-01-000041', '2026-01-000050',
     '2024-01-000100', '2025-01-000101', '2026-01-000102', '2026-01-000103', '2026-01-000104', 'ABC-DUP', 'ABC-X1', 'ABC-X2',
     'AC-2025-0777', 'AC-2025-0778', '2026-01-000060', '2026-01-000061');
  if v_texto is not null then
    raise exception 'ENSAYO ABORTADO: el laboratorio ya tiene números que el ensayo necesita libres: %', v_texto;
  end if;

  -- ── Las dos mitades de la excepción, medidas por sesión ─────────────────────────────────────────────────────────
  v_otros := '';
  foreach v_actor in array array[v_ger_admin, v_ger_super, v_ger_hist, v_admin, v_superadmin, v_vend, v_sup, null::uuid] loop
    perform pg_temp.sesion(v_actor);
    v_otros := v_otros || format('%s=%s/%s ', coalesce((select p.nombre_completo from public.perfiles p where p.id = v_actor), 'SIN SESIÓN'),
                                 public.es_admin(), private.es_gerencia_crm_activa());
    if coalesce(v_actor in (v_ger_admin, v_ger_super), false) is distinct from (public.es_admin() and private.es_gerencia_crm_activa()) then
      perform pg_temp.reg('5-pares', format(E'FALLO 5-pares: la excepción (es_admin y es_gerencia_crm_activa) no da %s para %s\n',
        coalesce(v_actor in (v_ger_admin, v_ger_super), false), coalesce((select p.nombre_completo from public.perfiles p where p.id = v_actor), 'SIN SESIÓN')));
    end if;
  end loop;
  perform pg_temp.sesion(null);
  perform set_config('ensayo.medidas', current_setting('ensayo.medidas')
    || E'medida 5-pares (es_admin/es_gerencia_crm_activa): ' || v_otros || E'\n', true);
  perform set_config('ensayo.medidas', current_setting('ensayo.medidas')
    || format(E'medida 0 (números malos): %s\n', (select string_agg(m.id || '=' || m.nota, ' · ' order by m.id) from ens_malos m where m.nota like 'variante%')), true);

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 1 y 2. NO EXENTOS: rechazo 22023 con el mensaje fijado por la llamada DIRECTA y por la puerta `crm` (concedida a
  --        authenticated). La `gerencia` histórica (comercial+gerencia) NO es exenta. 3: tras cada rechazo, la foto igual.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  foreach v_via in array array['directa', 'crm'] loop
    foreach v_nombre in array array['VEND1', 'GERENCIA'] loop
      v_actor := case v_nombre when 'VEND1' then v_vend else v_ger_hist end;
      for v_m in select * from ens_malos order by id loop
        -- por la puerta `crm` solo el vendedor recorre todo; la Gerencia histórica, lo esencial (sin clave y ABC)
        continue when v_via = 'crm' and v_nombre = 'GERENCIA' and v_m.id not in ('b01-sin-clave', 'b04-ABC', 'b02-vacio');
        perform pg_temp.reg(v_m.id || ' (' || v_via || ' · ' || v_nombre || ')',
          pg_temp.exigir_rechazo(v_m.id, v_via, v_actor, pg_temp.contrato(v_cli1, v_vend, v_m.valor), v_nombre));
      end loop;
    end loop;
  end loop;

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 4. POSITIVOS: las tres series, con 000000, un tope y un valor recortado; duplicado con su error de siempre.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  perform pg_temp.reg('4-2024-000000', pg_temp.exigir_acepta('4-2024-000000', 'directa', v_vend, pg_temp.contrato(v_cli1, v_vend, '2024-01-000000'), 'VEND1', '2024-01-000000'));
  perform pg_temp.reg('4-2025-123456', pg_temp.exigir_acepta('4-2025-123456', 'directa', v_vend, pg_temp.contrato(v_cli1, v_vend, '2025-01-123456'), 'VEND1', '2025-01-123456'));
  perform pg_temp.reg('4-2026-000009', pg_temp.exigir_acepta('4-2026-000009', 'directa', v_vend, pg_temp.contrato(v_cli1, v_vend, '2026-01-000009'), 'VEND1', '2026-01-000009'));
  perform pg_temp.reg('4-2026-999999', pg_temp.exigir_acepta('4-2026-999999', 'directa', v_vend, pg_temp.contrato(v_cli1, v_vend, '2026-01-999999'), 'VEND1', '2026-01-999999'));
  perform pg_temp.reg('4-recortado', pg_temp.exigir_acepta('4-recortado', 'directa', v_vend, pg_temp.contrato(v_cli1, v_vend, '  2026-01-000012  '), 'VEND1', '2026-01-000012'));
  perform pg_temp.reg('4-gerencia-historica-valido', pg_temp.exigir_acepta('4-gerencia-historica-valido', 'directa', v_ger_hist, pg_temp.contrato(v_cli1, v_vend, '2026-01-000020'), 'GERENCIA', '2026-01-000020'));
  perform pg_temp.reg('4-admin-sin-ficha-valido', pg_temp.exigir_acepta('4-admin-sin-ficha-valido', 'directa', v_admin, pg_temp.contrato(v_cli1, v_vend, '2026-01-000021'), 'ADMIN', '2026-01-000021'));
  perform pg_temp.reg('4-crm-2024', pg_temp.exigir_acepta('4-crm-2024', 'crm', v_vend, pg_temp.contrato(v_cli1, v_vend, '2024-01-000100'), 'VEND1', '2024-01-000100'));
  perform pg_temp.reg('4-crm-2025', pg_temp.exigir_acepta('4-crm-2025', 'crm', v_vend, pg_temp.contrato(v_cli1, v_vend, '2025-01-000101'), 'VEND1', '2025-01-000101'));
  perform pg_temp.reg('4-crm-2026', pg_temp.exigir_acepta('4-crm-2026', 'crm', v_vend, pg_temp.contrato(v_cli1, v_vend, '2026-01-000102'), 'VEND1', '2026-01-000102'));
  perform pg_temp.reg('4-crm-recortado', pg_temp.exigir_acepta('4-crm-recortado', 'crm', v_vend, pg_temp.contrato(v_cli1, v_vend, ' 2026-01-000103 '), 'VEND1', '2026-01-000103'));
  -- Duplicado de un número válido: su error de siempre (P0001), no el nuevo.
  perform pg_temp.reg('4-duplicado (directa · VEND1)', pg_temp.exigir_texto('4-duplicado', 'directa', v_vend,
    pg_temp.contrato(v_cli1, v_vend, '2026-01-000009'), 'VEND1', 'P0001|El N de contrato 2026-01-000009 ya existe|'));
  perform pg_temp.reg('4-duplicado (crm · VEND1)', pg_temp.exigir_texto('4-duplicado', 'crm', v_vend,
    pg_temp.contrato(v_cli1, v_vend, '2026-01-000102'), 'VEND1', 'P0001|El N de contrato 2026-01-000102 ya existe|'));

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 5. EXENTO (D-17): ger_admin (admin+gerencia) y ger_super (superadmin+gerencia) conservan el comportamiento de hoy.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  foreach v_nombre in array array['GER_ADMIN', 'GER_SUPER'] loop
    v_actor := case v_nombre when 'GER_ADMIN' then v_ger_admin else v_ger_super end;
    perform pg_temp.reg('5-' || v_nombre || '-sin-clave', pg_temp.exigir_acepta('5-' || v_nombre || '-sin-clave', 'directa', v_actor,
      pg_temp.contrato(v_cli1, v_vend, '__SIN_CLAVE__'), v_nombre, null, true));
    perform pg_temp.reg('5-' || v_nombre || '-vacio', pg_temp.exigir_acepta('5-' || v_nombre || '-vacio', 'directa', v_actor,
      pg_temp.contrato(v_cli1, v_vend, ''), v_nombre, null, true));
    perform pg_temp.reg('5-' || v_nombre || '-espacio', pg_temp.exigir_acepta('5-' || v_nombre || '-espacio', 'directa', v_actor,
      pg_temp.contrato(v_cli1, v_vend, ' '), v_nombre, null, true));
  end loop;
  perform pg_temp.reg('5-GER_ADMIN-ABC', pg_temp.exigir_acepta('5-GER_ADMIN-ABC', 'directa', v_ger_admin,
    pg_temp.contrato(v_cli1, v_vend, 'ABC-X1'), 'GER_ADMIN', 'ABC-X1'));
  perform pg_temp.reg('5-GER_SUPER-ABC', pg_temp.exigir_acepta('5-GER_SUPER-ABC', 'directa', v_ger_super,
    pg_temp.contrato(v_cli1, v_vend, 'ABC-X2'), 'GER_SUPER', 'ABC-X2'));
  -- Por la puerta `crm` también (el exento conserva todo): sin número y con un número libre.
  perform pg_temp.reg('5-crm-GER_ADMIN-sin-clave', pg_temp.exigir_acepta('5-crm-GER_ADMIN-sin-clave', 'crm', v_ger_admin,
    pg_temp.contrato(v_cli1, v_vend, '__SIN_CLAVE__'), 'GER_ADMIN', null, true));
  -- La exención NO salta el duplicado: el mismo número libre, otra vez, con su error de siempre.
  perform pg_temp.reg('5-GER_ADMIN-duplicado (directa · GER_ADMIN)', pg_temp.exigir_texto('5-GER_ADMIN-duplicado', 'directa', v_ger_admin,
    pg_temp.contrato(v_cli1, v_vend, 'ABC-X1'), 'GER_ADMIN', 'P0001|El N de contrato ABC-X1 ya existe|'));
  perform pg_temp.reg('5-GER_SUPER-duplicado (directa · GER_SUPER)', pg_temp.exigir_texto('5-GER_SUPER-duplicado', 'directa', v_ger_super,
    pg_temp.contrato(v_cli1, v_vend, '2026-01-000009'), 'GER_SUPER', 'P0001|El N de contrato 2026-01-000009 ya existe|'));

  -- Negativos de la excepción: quien NO cumple las dos mitades se rechaza, con «sin número» y con «ABC».
  foreach v_nombre in array array['GERENCIA', 'ADMIN', 'SUPERADMIN', 'VEND1', 'SUP1'] loop
    v_actor := case v_nombre when 'GERENCIA' then v_ger_hist when 'ADMIN' then v_admin when 'SUPERADMIN' then v_superadmin
                             when 'VEND1' then v_vend else v_sup end;
    perform pg_temp.reg('5n-' || v_nombre || '-sin-clave (directa · ' || v_nombre || ')',
      pg_temp.exigir_rechazo('5n-' || v_nombre || '-sin-clave', 'directa', v_actor, pg_temp.contrato(v_cli1, v_vend, '__SIN_CLAVE__'), v_nombre));
    perform pg_temp.reg('5n-' || v_nombre || '-ABC (directa · ' || v_nombre || ')',
      pg_temp.exigir_rechazo('5n-' || v_nombre || '-ABC', 'directa', v_actor, pg_temp.contrato(v_cli1, v_vend, 'ABC-N1'), v_nombre));
  end loop;
  -- Sin sesión de usuario: la llamada muere ANTES de la guarda (`puede_registrar_ventas()` exige uid): 42501, sin efecto.
  perform pg_temp.reg('5n-sin-sesion (directa · SIN SESIÓN)', pg_temp.exigir_texto('5n-sin-sesion', 'directa', null,
    pg_temp.contrato(v_cli1, v_vend, 'ABC-N1'), 'SIN SESIÓN', '42501|Cliente no encontrado o fuera de tu cartera|'));
  perform pg_temp.reg('5n-sin-sesion (crm · SIN SESIÓN)', pg_temp.exigir_texto('5n-sin-sesion', 'crm', null,
    pg_temp.contrato(v_cli1, v_vend, 'ABC-N1'), 'SIN SESIÓN', '42501|Sesión no válida|'));
  -- Inválido y ADEMÁS duplicado: gana la forma (la guarda va antes del duplicado). El exento siembra «ABC-DUP».
  perform pg_temp.reg('5-siembra-ABC-DUP', pg_temp.exigir_acepta('5-siembra-ABC-DUP', 'directa', v_ger_admin,
    pg_temp.contrato(v_cli1, v_vend, 'ABC-DUP'), 'GER_ADMIN', 'ABC-DUP'));
  perform pg_temp.reg('5n-invalido-y-duplicado (directa · VEND1)',
    pg_temp.exigir_rechazo('5n-invalido-y-duplicado', 'directa', v_vend, pg_temp.contrato(v_cli1, v_vend, 'ABC-DUP'), 'VEND1'));

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 4b. RENOVACIÓN y UPGRADE sobre contratos con número `AC-…` histórico: la regla solo mira el ALTA (el contrato nuevo).
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_origen_r := gen_random_uuid();
  v_origen_u := gen_random_uuid();
  set local session_replication_role = replica;
  insert into public.contratos (id, numero_contrato, cliente_id, capital, moneda, tasa_anual, modalidad, tipo_interes,
      fecha_inicio, fecha_vencimiento, estado, creado_por, creado_en, categoria, producto_condicion_id,
      fecha_cierre_comercial, fuente_cierre_comercial)
  values
    (v_origen_r, 'AC-2025-0777', v_cli3, 1000, 'PEN', 15, 'mensual', 'simple', v_ini - 366, v_ini - 1, 'vencido', v_vend3,
     now() - interval '1 year', 'nuevo',
     private.crear_snapshot_producto_legacy(v_origen_r, 'nuevo', 'PEN', 'mensual', 'simple', 1000, 15, v_ini - 366, v_ini - 1),
     (date_trunc('month', now() at time zone 'America/Lima') - interval '1 month')::date, 'registro'),
    (v_origen_u, 'AC-2025-0778', v_cli3, 1200, 'PEN', 15, 'mensual', 'simple', v_ini - 60, v_ini + 300, 'activo', v_vend3,
     now() - interval '2 months', 'nuevo',
     private.crear_snapshot_producto_legacy(v_origen_u, 'nuevo', 'PEN', 'mensual', 'simple', 1200, 15, v_ini - 60, v_ini + 300),
     (date_trunc('month', now() at time zone 'America/Lima') - interval '1 month')::date, 'registro');
  set local session_replication_role = origin;
  foreach v_via in array array['directa', 'crm'] loop
    -- Rechazos: la renovación y el upgrade NUEVOS con número fuera de forma o sin número (vendedor de la cartera).
    foreach v_nuevo in array array['__SIN_CLAVE__', 'ABC-R1'] loop
      perform pg_temp.reg('4b-renovacion-' || v_nuevo || ' (' || v_via || ' · VEND3)', pg_temp.exigir_rechazo('4b-renovacion-' || v_nuevo, v_via, v_vend3,
        pg_temp.contrato(v_cli3, v_vend3, v_nuevo, 'renovacion', jsonb_build_object('contrato_origen_id', v_origen_r,
          'capital', 1000, 'capital_renovado', 1000, 'capital_adicional', 0)), 'VEND3'));
      perform pg_temp.reg('4b-upgrade-' || v_nuevo || ' (' || v_via || ' · VEND3)', pg_temp.exigir_rechazo('4b-upgrade-' || v_nuevo, v_via, v_vend3,
        pg_temp.contrato(v_cli3, v_vend3, v_nuevo, 'upgrade', jsonb_build_object('contrato_origen_id', v_origen_u, 'capital', 1500)), 'VEND3'));
    end loop;
  end loop;
  -- Positivos: la renovación y el upgrade con número válido entran, y el contrato histórico CONSERVA su número `AC-…`.
  perform pg_temp.reg('4b-renovacion-valida', pg_temp.exigir_acepta('4b-renovacion-valida', 'crm', v_vend3,
    pg_temp.contrato(v_cli3, v_vend3, '2026-01-000040', 'renovacion', jsonb_build_object('contrato_origen_id', v_origen_r,
      'capital', 1000, 'capital_renovado', 1000, 'capital_adicional', 0)), 'VEND3', '2026-01-000040'));
  if (select c.numero_contrato || '|' || c.estado from public.contratos c where c.id = v_origen_r) is distinct from 'AC-2025-0777|renovado'
     or not exists (select 1 from crm.operaciones_cartera o where o.contrato_origen_id = v_origen_r and o.tipo = 'renovacion') then
    perform pg_temp.reg('4b-renovacion-origen', E'FALLO 4b-renovacion-origen: el contrato AC-2025-0777 no quedó «renovado» con su número intacto y su operación de cartera\n');
  else
    perform pg_temp.reg('4b-renovacion-origen: conserva su número AC-… y queda renovado', '');
  end if;
  perform pg_temp.reg('4b-upgrade-valido', pg_temp.exigir_acepta('4b-upgrade-valido', 'crm', v_vend3,
    pg_temp.contrato(v_cli3, v_vend3, '2026-01-000041', 'upgrade', jsonb_build_object('contrato_origen_id', v_origen_u, 'capital', 1500)),
    'VEND3', '2026-01-000041'));
  if (select c.numero_contrato || '|' || c.estado from public.contratos c where c.id = v_origen_u) is distinct from 'AC-2025-0778|activo' then
    perform pg_temp.reg('4b-upgrade-origen', E'FALLO 4b-upgrade-origen: el contrato AC-2025-0778 no conserva su número y su estado tras el upgrade\n');
  else
    perform pg_temp.reg('4b-upgrade-origen: conserva su número AC-… y su estado', '');
  end if;
  -- El exento sigue pudiendo renovar sin número (autogenera): el contrato histórico no cambia.
  -- (se cubre en la sección 5 con altas nuevas; aquí no se renueva dos veces el mismo origen)

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 6. IDEMPOTENCIA: repetir con la MISMA clave devuelve lo guardado ANTES de llegar a `public.crear_contrato`.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  v_clave := gen_random_uuid();
  v_cuenta := pg_temp.cuenta();
  v_contrato := pg_temp.contrato(v_cli1, v_vend, '2026-01-000050', 'nuevo', jsonb_build_object('clave_idempotencia', v_clave));
  v_res := pg_temp.llamar('crm', v_vend, v_contrato, v_cuenta);
  v_antes := pg_temp.foto();
  v_res2 := pg_temp.llamar('crm', v_vend, v_contrato, v_cuenta);
  if v_res not like 'ok|%' or v_res2 not like 'ok|%' then
    perform pg_temp.reg('6-idempotencia-valida', format(E'FALLO 6-idempotencia-valida: el alta o su repetición se rechazó (alta: %s · repetición: %s)\n', v_res, v_res2));
  else
    v_r := substr(v_res, 4)::jsonb; v_r2 := substr(v_res2, 4)::jsonb;
    if v_r2 -> 'idempotente' is distinct from 'true'::jsonb or v_r2 ->> 'id' is distinct from v_r ->> 'id'
       or v_r2 ->> 'numero_contrato' is distinct from '2026-01-000050' or pg_temp.foto() is distinct from v_antes then
      perform pg_temp.reg('6-idempotencia-valida', format(E'FALLO 6-idempotencia-valida: la repetición no devolvió lo guardado sin cambiar nada (%s)\n', v_res2));
    else
      perform pg_temp.reg('6-idempotencia-valida: la repetición devuelve lo guardado y no cambia nada', '');
    end if;
  end if;
  -- Y por el exento que PIERDE la exención entre el alta y su repetición (se degrada a «comercial» dentro de un bloque que
  -- se deshace): la repetición devuelve lo guardado aunque el número autogenerado no pasaría hoy, y un alta NUEVA con ABC se rechaza.
  v_clave := gen_random_uuid();
  v_cuenta := pg_temp.cuenta();
  v_contrato := pg_temp.contrato(v_cli1, v_vend, '__SIN_CLAVE__', 'nuevo', jsonb_build_object('clave_idempotencia', v_clave));
  v_res := pg_temp.llamar('crm', v_ger_admin, v_contrato, v_cuenta);
  v_texto := null;
  if v_res not like 'ok|%' then
    perform pg_temp.reg('6-idempotencia-exento', format(E'FALLO 6-idempotencia-exento: el alta del exento sin número se rechazó (%s)\n', v_res));
  else
    begin
      update public.perfiles set rol = 'comercial' where id = v_ger_admin;
      perform pg_temp.sesion(v_ger_admin);
      v_res2 := case when public.es_admin() then 'SIGUE SIENDO ADMIN' else pg_temp.llamar('crm', v_ger_admin, v_contrato, v_cuenta) end;
      v_otros := case when public.es_admin() then 'SIGUE SIENDO ADMIN' else pg_temp.llamar('directa', v_ger_admin, pg_temp.contrato(v_cli1, v_vend, 'ABC-ID'), null) end;
      perform pg_temp.sesion(null);
      raise exception using errcode = 'ZZRB2', message = v_res2 || '##' || v_otros;
    exception
      when sqlstate 'ZZRB2' then
        get stacked diagnostics v_texto = message_text;
      when others then
        v_texto := 'NOMONTA|' || sqlstate || '|' || sqlerrm;
    end;
    perform pg_temp.sesion(null);
    if v_texto like 'NOMONTA|%' then
      perform pg_temp.reg('6-idempotencia-exento', format(E'FALLO 6-idempotencia-exento: no se pudo degradar al exento para medir (%s)\n', v_texto));
    elsif split_part(v_texto, '##', 1) not like 'ok|%'
       or ((substr(split_part(v_texto, '##', 1), 4)::jsonb) -> 'idempotente') is distinct from 'true'::jsonb
       or (substr(split_part(v_texto, '##', 1), 4)::jsonb ->> 'id') is distinct from (substr(v_res, 4)::jsonb ->> 'id') then
      perform pg_temp.reg('6-idempotencia-exento', format(E'FALLO 6-idempotencia-exento: la repetición del exento degradado no devolvió lo guardado (%s)\n', split_part(v_texto, '##', 1)));
    elsif split_part(v_texto, '##', 2) <> v_esperado then
      perform pg_temp.reg('6-idempotencia-exento', format(E'FALLO 6-idempotencia-exento: degradado, un alta NUEVA con «ABC-ID» no se rechazó con la regla (%s)\n', split_part(v_texto, '##', 2)));
    else
      perform pg_temp.reg('6-idempotencia-exento: la repetición devuelve lo guardado aunque el actor ya no sea exento; un alta nueva con ABC se rechaza', '');
    end if;
  end if;
  perform pg_temp.sesion(null);

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 7. MEDICIONES del banco: con qué usuario corre y si `K.numero()` sigue dando seis dígitos.
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  perform set_config('ensayo.medidas', current_setting('ensayo.medidas')
    || E'medida 7a (usuario del banco): N1, N1b-1…4, N2, N3, N4–N8 llaman K.crear(T["vend1"], …) (paso08/42_fila2_inversion.py) = PASO08 VEND1 (comercial+vendedor), NO exento: ver «5-pares» arriba (VEND1 = f/f)\n', true);
  select string_agg(format('B=%s n=%s → %s %s', t.b, t.n, t.num, case when t.num ~ '^(2024|2025|2026)-01-[0-9]{6}$' then 'VÁLIDO' else 'INVÁLIDO' end), ' · ' order by t.b, t.n)
    into v_texto
  -- `%05d` de Python RELLENA a 5 pero no corta: con n >= 100000 salen 6 cifras (lpad sí cortaría; por eso el case).
  from (select b.b, n.n, '2026-01-' || b.b || case when n.n > 99999 then n.n::text else lpad(n.n::text, 5, '0') end as num
        from (values ('1'), ('9'), ('10')) b(b) cross join (values (1), (99999), (100000)) n(n)) t;
  perform set_config('ensayo.medidas', current_setting('ensayo.medidas')
    || E'medida 7b (K.numero(), paso08/contratos.py:19-21, reproducida: "%s-01-%s%05d" % (serie, P8_BLOCK, n)): ' || v_texto || E'\n', true);
  perform set_config('ensayo.medidas', current_setting('ensayo.medidas')
    || format(E'medida 7c (regex en este laboratorio): «\\d» casa un dígito arábigo-índico: %s · «[0-9]» lo casa: %s\n',
              (E'٩' ~ '\d'), (E'٩' ~ '[0-9]')), true);

  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 9. Catálogo: lo que la migración tiene que conservar y lo que no puede tocar
  -- ══════════════════════════════════════════════════════════════════════════════════════════════════════════════
  -- 9a. public.crear_contrato: dueño, security definer, search_path vacío y ACL exacta (sin anon; authenticated y service_role).
  if not exists (
       select 1 from pg_proc p
       where p.oid = 'public.crear_contrato(jsonb,jsonb)'::regprocedure and p.proowner = 'postgres'::regrole::oid and p.prosecdef
         and p.proconfig = array['search_path=""'])
     or (select array_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text order by a.grantee::regrole::text)
           from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
          where p.oid = 'public.crear_contrato(jsonb,jsonb)'::regprocedure)
        is distinct from array['authenticated:EXECUTE:false', 'postgres:EXECUTE:false', 'service_role:EXECUTE:false']
     or has_function_privilege('anon', 'public.crear_contrato(jsonb,jsonb)', 'EXECUTE') then
    perform pg_temp.reg('9a', E'FALLO 9a: public.crear_contrato cambió de dueño, de atributos (security definer, search_path vacío) o de permisos (anon con EXECUTE, falta authenticated/service_role, o EXECUTE con opción de concesión)\n');
  else
    perform pg_temp.reg('9a public.crear_contrato: ficha y ACL', '');
  end if;
  -- 9b. Lo que NO se toca, con su huella (md5 del cuerpo).
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'private.siguiente_numero_contrato(integer)'::regprocedure) is distinct from '921e09f03b8f2d0c468267b05729746f'
     or (select md5(p.prosrc) from pg_proc p where p.oid = 'public.actualizar_numero_contrato(uuid,text,text,text)'::regprocedure) is distinct from '44270f9706a4515b16962ead8b09ea59'
     or (select md5(p.prosrc) from pg_proc p where p.oid = 'crm.actualizar_numero_contrato_pdf_v3(uuid,text,text,text)'::regprocedure) is distinct from '11ad77e85abd0b9be7790240a6e27c1e'
     or (select md5(p.prosrc) from pg_proc p where p.oid = 'crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)'::regprocedure) is distinct from '22ec068ff5d27312c5eb0749600292fd'
     or (select md5(p.prosrc) from pg_proc p where p.oid = 'crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)'::regprocedure) is distinct from '505598d6fef7ea585a965f925a8eb9fb'
     or (select md5(p.prosrc) from pg_proc p where p.oid = 'public.es_admin()'::regprocedure) is distinct from 'f4e01285f0b006f72b984213a6a95310'
     or (select md5(p.prosrc) from pg_proc p where p.oid = 'private.es_gerencia_crm_activa()'::regprocedure) is distinct from 'e2e84b58044078e40e506f623985e86d'
     or (select md5(p.prosrc) from pg_proc p where p.oid = 'private.rol_crm(uuid)'::regprocedure) is distinct from 'd2878a210be96ac85973d51dfcfb27a5'
     or (select md5(p.prosrc) from pg_proc p where p.oid = 'private.puede_registrar_ventas()'::regprocedure) is distinct from '2749bb0e5616eae42a0dd410bee4f52a' then
    perform pg_temp.reg('9b', E'FALLO 9b: cambió algo que no se toca (siguiente_numero_contrato, actualizar_numero_contrato, crm.crear_contrato_con_cuenta[_pdf_v2], es_admin, es_gerencia_crm_activa, rol_crm o puede_registrar_ventas)\n');
  else
    perform pg_temp.reg('9b huellas de lo que no se toca', '');
  end if;
  perform set_config('ensayo.medidas', current_setting('ensayo.medidas')
    || format(E'medida 9c: md5(prosrc) de public.crear_contrato = %s · md5(definición) = %s\n',
       (select md5(p.prosrc) from pg_proc p where p.oid = 'public.crear_contrato(jsonb,jsonb)'::regprocedure),
       (select md5(pg_get_functiondef(p.oid)) from pg_proc p where p.oid = 'public.crear_contrato(jsonb,jsonb)'::regprocedure)), true);

  -- ── Lo diferido se comprueba AHORA, no en un COMMIT que nunca llega ───────────────────────────────────────────────
  begin
    set constraints all immediate;
  exception when others then
    perform pg_temp.reg('11', format(E'FALLO 11: algo de lo aceptado no sobreviviría al COMMIT (%s %s)\n', sqlstate, sqlerrm));
  end;

  -- ── Veredicto, y rollback SIEMPRE ───────────────────────────────────────────────────────────────────────────────
  raise exception E'ENSAYO %:\n%\n%\n%(rollback a propósito — nada queda escrito)',
    case when current_setting('ensayo.fallos')::integer = 0 then 'VERDE — 0 fallos'
         else format('ROJO — %s fallo(s)', current_setting('ensayo.fallos')) end,
    current_setting('ensayo.informe'),
    current_setting('ensayo.medidas'),
    current_setting('ensayo.oks');
end;
$ensayo$;
