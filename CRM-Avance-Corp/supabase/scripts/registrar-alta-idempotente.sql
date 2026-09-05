-- REGISTRO en supabase_migrations.schema_migrations de «el alta de contrato es idempotente por clave».
-- `db query --linked --file` NO registra: correr DESPUÉS de aplicar la migración.
-- Idempotente; se niega si la versión ya está registrada con OTRO contenido.
begin;
do $chk$
begin
  if exists (select 1 from supabase_migrations.schema_migrations where version='20260905190000' and md5(statements[1]) <> 'f5a149c10037a947023a8712ee2c7794') then
    raise exception 'REGISTRO ALTA IDEMPOTENTE: la versión 20260905190000 ya está registrada con otro contenido';
  end if;
end
$chk$;
insert into supabase_migrations.schema_migrations (version, name, statements)
values ('20260905190000', 'crm_alta_contrato_idempotente', array[$m$-- ============================================================================
-- CRM · EL ALTA DE CONTRATO ES IDEMPOTENTE POR CLAVE (crm.crear_contrato_con_cuenta_pdf_v2)
-- ============================================================================
--
-- QUÉ PASÓ (05/09/2026, medido en producción). DIAZ VILLANUEVA quedó con DOS contratos
-- idénticos: 2026-01-000025 (16:04:19 UTC) y 2026-01-000253 (16:05:20 UTC). El primer
-- alta salió 200; el front lo leyó como error («El servidor no confirmó completamente
-- el contrato…») porque el contrato está firmado el 11/03/2026 —régimen documental
-- ANTERIOR, el servidor no emite PDF y responde pdf.estado = 'sin_reserva'— y el
-- esquema del navegador exigía la reserva 'pendiente'. El analista reintentó con el
-- mismo número (400 «El N de contrato 2026-01-000025 ya existe»), cambió el número y
-- creó el duplicado. Desde el 21/08, 33 altas del régimen anterior pasaron por ese
-- error falso; el 04/09 se ven dos ciclos iguales (22:05:59 y 22:12:42). La ÚNICA
-- protección que había era el chequeo del número repetido, y se salta cambiándolo.
--
-- QUÉ HACE. El front manda dentro de p_contrato una `clave_idempotencia` (uuid por
-- intento de formulario, la misma en cada reintento). Este wrapper —la puerta VIVA del
-- alta— la lee, serializa por (actor, clave) con un lock advisory, y si ya registró
-- un alta con esa clave devuelve el MISMO contrato (con el estado documental de hoy y
-- `idempotente: true`); si no, quita la clave del JSON, corre la cadena EXACTAMENTE
-- como hoy (crm.crear_contrato_con_cuenta → public.crear_contrato → reserva PDF) y
-- guarda la respuesta en private.contrato_altas_idempotentes dentro de la misma transacción.
-- Sin clave, el comportamiento es byte a byte el de producción: los clientes viejos
-- no cambian. La firma y el tipo de retorno no cambian (no hace falta DROP).
--
-- QUÉ NO TOCA. Ni crm.crear_contrato_con_cuenta ni public.crear_contrato (el bug
-- estaba en el cliente; el servidor solo gana la memoria del intento). No crea,
-- altera ni borra ningún objeto de `public` (la FK referencia public.contratos, como
-- ya hace private.contrato_eliminaciones). La tabla vive en `private`: sin grants para
-- la API, RLS forzada, solo la escribe este DEFINER. Una fila por alta (~15/día).
-- Borrar el contrato (puerta oficial) borra su fila en cascada: un replay posterior
-- crea uno nuevo, que es lo correcto tras una eliminación deliberada.
--
-- Transformada desde el texto VIVO (scripts/idempotencia/gen-alta-idempotente.py):
-- guarda md5 EXACTA del vivo (68cc6c91e84061c0bdf6a62306085c14), postflight byte a byte (079d047f00d6355929615b1c49060b47).
-- Ensayo: scripts/oraculo-alta-idempotente.sh (banco). Reversa: scripts/rollback-alta-idempotente.sql.

begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';
select pg_advisory_xact_lock(hashtext('crm_alta_contrato_idempotente'));

do $guard$
declare v_h text; v_owner text; v_definer boolean; v_config text[];
begin
  select md5(p.prosrc), p.proowner::regrole::text, p.prosecdef, p.proconfig
    into v_h, v_owner, v_definer, v_config
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'crm' and p.proname = 'crear_contrato_con_cuenta_pdf_v2'
    and pg_get_function_identity_arguments(p.oid) = 'p_contrato jsonb, p_cronograma jsonb, p_cuenta jsonb';
  if v_h is null then
    raise exception 'ALTA IDEMPOTENTE: falta crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)';
  end if;
  if v_h is distinct from '68cc6c91e84061c0bdf6a62306085c14' and v_h is distinct from '079d047f00d6355929615b1c49060b47' then
    raise exception 'ALTA IDEMPOTENTE: crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb) no es ni el texto vivo de producción ni el de esta migración (%)', v_h;
  end if;
  if v_owner <> 'postgres' or not v_definer or v_config is null or not (v_config @> array['search_path=""']) then
    raise exception 'ALTA IDEMPOTENTE: crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb) perdió dueño postgres, DEFINER o search_path vacío (%, %, %)', v_owner, v_definer, v_config;
  end if;
  if not has_function_privilege('authenticated', 'crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)', 'EXECUTE')
     or has_function_privilege('anon', 'crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)', 'EXECUTE')
     or has_function_privilege('service_role', 'crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)', 'EXECUTE')
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = 'crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)'::regprocedure and a.grantee = 0) then
    raise exception 'ALTA IDEMPOTENTE: los grants de crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb) no son los vivos (solo postgres y authenticated; ni anon, ni service_role, ni PUBLIC)';
  end if;
  if to_regprocedure('private.contrato_pdf_estado_base(uuid)') is null
     or to_regprocedure('private.crear_job_contrato_pdf_base(uuid,uuid)') is null
     or to_regprocedure('crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)') is null then
    raise exception 'ALTA IDEMPOTENTE: falta una pieza de la cadena viva (estado_base, crear_job o crear_contrato_con_cuenta)';
  end if;
end
$guard$;

-- ── La memoria del intento ──────────────────────────────────────────────────────
create table if not exists private.contrato_altas_idempotentes (
  -- auth.uid() del actor. Sin FK a perfiles a propósito: un rastro jamás puede tumbar
  -- el alta que acompaña (regla de la auditoría F1.4), y el actor ya pasó la puerta.
  actor_id uuid not null,
  clave uuid not null,
  contrato_id uuid not null
    references public.contratos(id) on delete cascade,
  respuesta jsonb not null
    constraint contrato_altas_idempotentes_respuesta_objeto
      check (jsonb_typeof(respuesta) = 'object'),
  creado_en timestamptz not null default statement_timestamp(),
  primary key (actor_id, clave)
);
create index if not exists contrato_altas_idempotentes_contrato_idx
  on private.contrato_altas_idempotentes (contrato_id);
comment on table private.contrato_altas_idempotentes is
  'Memoria de idempotencia del alta de contrato (crm.crear_contrato_con_cuenta_pdf_v2): '
  'por (actor, clave) guarda el contrato creado y la respuesta devuelta. Un reintento '
  'con la misma clave devuelve el mismo contrato en vez de crear otro (incidente del '
  '05/09/2026: dos contratos idénticos por un error falso del front). Solo la escribe '
  'el wrapper DEFINER; sin grants para la API; se limpia en cascada al borrar el contrato.';
alter table private.contrato_altas_idempotentes enable row level security;
alter table private.contrato_altas_idempotentes force row level security;
revoke all on table private.contrato_altas_idempotentes from public, anon, authenticated, service_role;

-- ── La puerta viva, con memoria ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION crm.crear_contrato_con_cuenta_pdf_v2(p_contrato jsonb, p_cronograma jsonb, p_cuenta jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor_id uuid := (select auth.uid());
  v_contrato jsonb := p_contrato;
  v_resultado jsonb;
  v_contrato_id uuid;
  v_pdf jsonb;
  v_clave_texto text := nullif(btrim(coalesce(p_contrato->>'clave_idempotencia', '')), '');
  v_clave uuid;
begin
  if v_actor_id is null then
    raise insufficient_privilege using message = 'Sesión no válida';
  end if;

  -- IDEMPOTENCIA DEL ALTA (05/09/2026). El front manda una clave (uuid) por intento de
  -- formulario, la MISMA en cada reintento. Si este actor ya registró un alta con esa
  -- clave, se devuelve el MISMO contrato en vez de crear otro. Viaja DENTRO de
  -- p_contrato para no cambiar la firma del RPC; es del transporte, no del contrato:
  -- se quita antes de bajar a la cadena, que recibe EXACTAMENTE lo que recibía.
  -- Sin clave, nada cambia (los clientes que no la mandan siguen igual).
  if v_clave_texto is not null then
    begin
      v_clave := v_clave_texto::uuid;
    exception when invalid_text_representation then
      raise exception 'La clave de idempotencia del alta no es válida'
        using errcode = '22023';
    end;
    -- Dos envíos simultáneos con la misma clave del mismo actor (doble clic, dos
    -- pestañas) se serializan aquí: el segundo espera y lee el alta del primero.
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        'crm.alta_contrato_idempotente|' || v_actor_id::text || '|' || v_clave::text, 0
      )
    );
    select a.respuesta, a.contrato_id into v_resultado, v_contrato_id
    from private.contrato_altas_idempotentes a
    where a.actor_id = v_actor_id and a.clave = v_clave;
    if found then
      -- El MISMO contrato, con el estado documental de HOY (la reserva pudo avanzar
      -- desde el primer intento) y la marca de que es un alta ya registrada.
      return (v_resultado - 'pdf')
        || jsonb_build_object('pdf', private.contrato_pdf_estado_base(v_contrato_id))
        || jsonb_build_object('idempotente', true);
    end if;
    v_contrato := p_contrato - 'clave_idempotencia';
  end if;

  -- El contrato, cronograma, cuenta, vínculo, snapshot y job se confirman o
  -- revierten juntos porque toda la cadena corre en esta transacción RPC.
  v_resultado := crm.crear_contrato_con_cuenta(
    v_contrato,
    p_cronograma,
    p_cuenta
  );
  begin
    v_contrato_id := (v_resultado->>'id')::uuid;
  exception when invalid_text_representation then
    raise exception 'El alta no devolvió un contrato válido'
      using errcode = 'P0001';
  end;
  if v_contrato_id is null then
    raise exception 'El alta no devolvió un contrato válido'
      using errcode = 'P0001';
  end if;

  v_pdf := private.crear_job_contrato_pdf_base(v_contrato_id, v_actor_id);
  v_resultado := v_resultado || jsonb_build_object('pdf', v_pdf);
  if v_clave is not null then
    -- Misma transacción que el alta: o quedan los dos, o ninguno.
    insert into private.contrato_altas_idempotentes (actor_id, clave, contrato_id, respuesta)
    values (v_actor_id, v_clave, v_contrato_id, v_resultado);
  end if;
  return v_resultado;
end;
$function$;

do $post$
declare v_h text; v_owner text; v_definer boolean; v_config text[];
begin
  select md5(p.prosrc), p.proowner::regrole::text, p.prosecdef, p.proconfig
    into v_h, v_owner, v_definer, v_config
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'crm' and p.proname = 'crear_contrato_con_cuenta_pdf_v2'
    and pg_get_function_identity_arguments(p.oid) = 'p_contrato jsonb, p_cronograma jsonb, p_cuenta jsonb';
  if v_h is null then
    raise exception 'ALTA IDEMPOTENTE: falta crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)';
  end if;
  if v_h is distinct from '68cc6c91e84061c0bdf6a62306085c14' and v_h is distinct from '079d047f00d6355929615b1c49060b47' then
    raise exception 'ALTA IDEMPOTENTE: crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb) no es ni el texto vivo de producción ni el de esta migración (%)', v_h;
  end if;
  if v_owner <> 'postgres' or not v_definer or v_config is null or not (v_config @> array['search_path=""']) then
    raise exception 'ALTA IDEMPOTENTE: crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb) perdió dueño postgres, DEFINER o search_path vacío (%, %, %)', v_owner, v_definer, v_config;
  end if;
  if v_h is distinct from '079d047f00d6355929615b1c49060b47' then
    raise exception 'POSTFLIGHT ALTA IDEMPOTENTE: el texto instalado no es el esperado (%)', v_h;
  end if;
  if not has_function_privilege('authenticated', 'crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)', 'EXECUTE')
     or has_function_privilege('anon', 'crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)', 'EXECUTE')
     or has_function_privilege('service_role', 'crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)', 'EXECUTE')
     or exists (select 1 from pg_proc p, aclexplode(p.proacl) a where p.oid = 'crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)'::regprocedure and a.grantee = 0) then
    raise exception 'ALTA IDEMPOTENTE: los grants de crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb) no son los vivos (solo postgres y authenticated; ni anon, ni service_role, ni PUBLIC)';
  end if;
  if not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                 where n.nspname = 'private' and c.relname = 'contrato_altas_idempotentes'
                   and c.relrowsecurity and c.relforcerowsecurity) then
    raise exception 'ALTA IDEMPOTENTE: private.contrato_altas_idempotentes sin RLS forzada';
  end if;
  if exists (select 1 from information_schema.role_table_grants g
             where g.table_schema = 'private' and g.table_name = 'contrato_altas_idempotentes'
               and g.grantee in ('anon', 'authenticated', 'service_role', 'PUBLIC')) then
    raise exception 'ALTA IDEMPOTENTE: private.contrato_altas_idempotentes tiene grants para roles de la API';
  end if;
  if not exists (select 1 from pg_constraint k where k.conrelid = 'private.contrato_altas_idempotentes'::regclass and k.contype = 'p'
                 and pg_get_constraintdef(k.oid) = 'PRIMARY KEY (actor_id, clave)') then
    raise exception 'ALTA IDEMPOTENTE: private.contrato_altas_idempotentes sin la clave primaria (actor_id, clave)';
  end if;
  if not exists (select 1 from pg_constraint k where k.conrelid = 'private.contrato_altas_idempotentes'::regclass and k.contype = 'f'
                 and k.confrelid = 'public.contratos'::regclass and k.confdeltype = 'c') then
    raise exception 'ALTA IDEMPOTENTE: private.contrato_altas_idempotentes sin la FK ON DELETE CASCADE a public.contratos';
  end if;
end
$post$;

commit;

-- El veredicto viaja como FILA (db query no transporta los notice).
select 'ALTA_IDEMPOTENTE_OK' as resultado,
       (select md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'crm' and p.proname = 'crear_contrato_con_cuenta_pdf_v2') as huella,
       (select count(*) from private.contrato_altas_idempotentes) as altas_recordadas;
$m$])
on conflict (version) do nothing;
commit;
select 'REGISTRO_ALTA_IDEMPOTENTE_OK' as resultado, version, name, md5(statements[1]) as huella_archivo
from supabase_migrations.schema_migrations where version = '20260905190000';
