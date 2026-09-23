-- Temperatura del lead (Gestión Diaria · señal para ordenar «Mi día») — FASE 1.
--
-- QUÉ HACE. Guarda, por lead, una señal de 0 a 3 que dice qué tan cerca está esa
-- persona de invertir, leída de las NOTAS que el analista escribió tras cada
-- gestión. La calcula un modelo externo (TypeSafe/Jev) desde la Edge Function
-- `crm-temperatura-lead`; aquí vive la cola de trabajo, el resultado y los
-- candados. Esta migración NO cambia ningún orden ni ninguna pantalla: solo
-- deja la señal medida y guardada. El `order by` de «Mi día» se toca en la F2,
-- cuando haya semanas de señal acumulada para comparar.
--
-- POR QUÉ. «Mi día» ordena hoy solo por vencimiento
-- (`20260920041500_crm_gestion_diaria_analista.sql`: `order by referencia, id`).
-- Un lead que pidió el contrato y otro que nunca contestó compiten por la misma
-- posición. En la prueba del 20/09 sobre 45 leads reales con historial, la señal
-- separó a los que llegaron a cita o entrevista de los descartados con AUC 0.84
-- (medias 1.74 / 1.06 / 0.44 por grupo).
--
-- CÓMO SE REVIERTE. `select cron.unschedule('crm-temperatura-lead');` y
-- `drop table crm.lead_temperatura cascade;` (se lleva el trigger), más el
-- `drop` de las seis funciones. Ninguna puerta existente las llama todavía.
--
-- MULTITENANCY. `crm.leads` no tiene `negocio_id` en este proyecto; la
-- visibilidad se resuelve por `vendedor_id`/`asignado_supervisor_id` a través de
-- las puertas. Esta tabla NO se expone: no lleva policies y solo la leen
-- funciones `security definer`, así que no añade superficie de lectura.
--
-- AUDITORÍA. `private.log_audit_sin_secretos` resuelve `fila_id` por `id` o
-- `perfil_id` (`20260829235000:119-125`) y esta tabla no tiene ninguna de las
-- dos: su PK es `lead_id`. Por eso `fila_id` quedará NULL en toda su bitácora,
-- y se declara aquí por escrito como en `20260811154434:413-416`. La fila se
-- identifica igual por `datos_nuevos->>'lead_id'`.
--
-- ADVISOR ESPERADO. `rls_enabled_no_policy` (INFO) sobre `crm.lead_temperatura`:
-- es deliberado (deny-by-default sin lectores directos), no una alerta nueva.
--
-- SECRETOS. Requiere en Vault `cron_temperatura_secret` (firma del cron) y
-- reutiliza `crm_push_proyecto`. La clave del modelo (`TYPESAFE_API_KEY`) vive
-- SOLO en los secretos de la Edge Function: nunca en la base, ni en el código,
-- ni en esta migración.
begin;

-- ---------------------------------------------------------------------------
-- 1. Tabla: es a la vez la COLA de trabajo y el RESULTADO vigente (una fila por
--    lead). Se prefiere una sola tabla a un par cola/resultado porque la señal
--    no tiene historia útil: solo importa la última, y recalcularla es barato.
-- ---------------------------------------------------------------------------
create table crm.lead_temperatura (
  lead_id uuid primary key references crm.leads(id) on delete cascade,
  estado text not null default 'pendiente'
    check (estado in ('pendiente','calculando','listo','fallido')),
  -- 0 = nunca se le pudo hablar o dijo que no; 3 = dio fecha, monto o pidió el
  -- contrato. Cae entre niveles a propósito: es un promedio ponderado.
  nivel numeric(4,2) check (nivel >= 0 and nivel <= 3),
  -- Lo que devuelve un tercero entra con forma acotada, como en los avisos de
  -- tasa: ni un jsonb sin techo ni un `modelo` de longitud libre.
  probabilidades jsonb check (probabilidades is null or length(probabilidades::text) <= 2000),
  confianza numeric(4,3) check (confianza >= 0 and confianza <= 1),
  modelo text check (modelo is null or length(modelo) between 1 and 80),
  -- SHA-256 del historial exacto con el que se calculó esta señal: sirve para
  -- saber QUÉ texto la produjo cuando haya que explicar un orden raro.
  huella_historial text check (huella_historial is null or huella_historial ~ '^[a-f0-9]{64}$'),
  calculado_en timestamptz,
  intentos integer not null default 0 check (intentos between 0 and 8),
  disponible_en timestamptz not null default now(),
  reserva uuid,
  reservado_hasta timestamptz,
  error_codigo text,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  -- Una fila «listo» sin nivel sería una señal fantasma que la F2 ordenaría mal.
  constraint lead_temperatura_listo_completo check (
    estado <> 'listo'
    or (nivel is not null and modelo is not null
        and calculado_en is not null and huella_historial is not null))
);
alter table crm.lead_temperatura enable row level security;
-- También a `service_role`: la Edge Function entra por las puertas `_fn`, nunca
-- a la tabla, y `service_role` es `bypassrls` — dejarle la tabla abierta sería
-- la única lectura directa que existe.
revoke all on crm.lead_temperatura from public, anon, authenticated, service_role;
-- Deny-by-default SIN policies y a propósito: nadie la lee directo. Las puertas
-- que la usen serán `security definer` y filtrarán por su propio ámbito.
create index lead_temperatura_cola_idx on crm.lead_temperatura(disponible_en)
  where estado in ('pendiente','calculando');
create index lead_temperatura_nivel_idx on crm.lead_temperatura(nivel)
  where estado = 'listo';
create trigger trg_audit_lead_temperatura after insert or update or delete
  on crm.lead_temperatura for each row execute function
  private.log_audit_sin_secretos('reserva','probabilidades');

comment on table crm.lead_temperatura is
  'Señal 0-3 de cercanía del lead a invertir, derivada por un modelo externo de las notas de gestión. Cola y resultado en una sola fila por lead. No se expone a la API: solo la leen funciones security definer. Su bitácora lleva fila_id NULL (la PK es lead_id, no id).';
comment on column crm.lead_temperatura.nivel is
  'Promedio ponderado entre 0 (nunca se le habló o dijo que no) y 3 (dio fecha, monto o pidió el contrato). Puede caer entre niveles.';
comment on column crm.lead_temperatura.probabilidades is
  'Distribución completa devuelta por el modelo, nivel -> probabilidad. Se guarda para poder recalibrar sin volver a preguntar.';
comment on column crm.lead_temperatura.confianza is
  'Concentración de la distribución (0-1). En la medición del 20/09 resultó casi una función del propio nivel, así que NO se usa para ordenar.';
comment on column crm.lead_temperatura.huella_historial is
  'SHA-256 del texto de historial con el que se calculó la señal. Es trazabilidad, no caché: hoy nadie la compara antes de preguntar.';
comment on column crm.lead_temperatura.error_codigo is
  'Motivo del último fallo (http_429, http_500, timeout, respuesta_invalida...). Nunca el cuerpo de la respuesta ni la clave.';

-- ---------------------------------------------------------------------------
-- 2. Núcleo: el texto que se le manda al modelo.
--    Solo gestiones humanas, las 12 últimas, en orden cronológico,
--    «DD/MM tipo: nota». Sin nombre, sin teléfono, sin documento — al modelo no
--    le hace falta la identidad para juzgar la conversación, y así no sale de
--    la casa. OJO: `detalle` es texto libre del analista, así que puede llevar
--    PII tecleada a mano; lo que se garantiza es que no van campos estructurados.
--    El recorte es por la IZQUIERDA (`right`): si hay que perder texto, se
--    pierde el más viejo, nunca la última nota, que es la que define la
--    temperatura de hoy.
-- ---------------------------------------------------------------------------
create function private.temperatura_historial_lead(p_lead_id uuid)
returns text language sql stable set search_path = '' as $$
  with ultimas as (
    select a.creado_en, a.id, a.tipo, a.detalle
    from crm.actividades a
    where a.lead_id = p_lead_id
      and a.tipo not in ('cambio_etapa','reasignacion','conversion')
    order by a.creado_en desc, a.id desc
    limit 12
  )
  select pg_catalog.right(pg_catalog.string_agg(
           pg_catalog.to_char(u.creado_en at time zone 'America/Lima','DD/MM')
             || ' ' || u.tipo || ': '
             || coalesce(nullif(pg_catalog.btrim(u.detalle), ''), '(sin nota)'),
           ' | ' order by u.creado_en, u.id), 3000)
  from ultimas u;
$$;
comment on function private.temperatura_historial_lead(uuid) is
  'Arma el historial de gestión que se envía al modelo: 12 últimas actividades humanas, recortado por el extremo viejo, sin campos personales.';

-- ---------------------------------------------------------------------------
-- 3. Núcleo: encolar. Toda gestión humana nueva invalida la señal del lead,
--    INCLUIDO el cálculo que esté en vuelo: se anula su reserva para que la
--    respuesta tardía no aterrice con un historial que ya cambió. Se pierde una
--    consulta (dos centésimas de centavo) y se gana no tener señales rancias.
-- ---------------------------------------------------------------------------
create function private.encolar_temperatura_lead() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.tipo in ('cambio_etapa','reasignacion','conversion') then
    return null;
  end if;
  insert into crm.lead_temperatura (lead_id, estado, disponible_en)
  values (new.lead_id, 'pendiente', pg_catalog.now())
  on conflict (lead_id) do update
    set estado = 'pendiente',
        disponible_en = pg_catalog.now(),
        intentos = 0,
        reserva = null,
        reservado_hasta = null,
        actualizado_en = pg_catalog.now();
  return null;
exception when others then
  -- La señal es un efecto AUXILIAR colgado de la ruta crítica del analista
  -- (`registrar_llamada_v3` → `crm.actividades`). Jamás puede tumbar el
  -- registro de una gestión real; el cron recupera lo que falte.
  raise warning 'No se pudo encolar la temperatura del lead (SQLSTATE %)', sqlstate;
  return null;
end;
$$;
create trigger trg_zz_actividades_temperatura after insert on crm.actividades
  for each row execute function private.encolar_temperatura_lead();
comment on function private.encolar_temperatura_lead() is
  'Marca la temperatura del lead como pendiente cuando se registra una gestión humana nueva. Nunca invalida la actividad: atrapa cualquier error y avisa.';

-- ---------------------------------------------------------------------------
-- 4. Núcleo: devolver a la cola lo que quedó reservado y nadie confirmó.
-- ---------------------------------------------------------------------------
create function private.reconciliar_temperatura() returns void
language sql security definer set search_path = '' as $$
  update crm.lead_temperatura
     set estado = 'pendiente', reserva = null, reservado_hasta = null,
         actualizado_en = pg_catalog.now()
   where estado = 'calculando' and reservado_hasta < pg_catalog.now();
$$;
comment on function private.reconciliar_temperatura() is
  'Devuelve a pendiente las filas cuya reserva caducó sin confirmación. Conserva intentos: el tope lo aplica tomar_temperatura_lead_fn.';

-- ---------------------------------------------------------------------------
-- 5. Puerta de la Edge Function: tomar / confirmar. Solo `service_role`, con
--    candado DENTRO además del grant (el ACL solo no basta: una restauración de
--    plataforma que repise privilegios no deja rastro en el código).
-- ---------------------------------------------------------------------------
create function crm.tomar_temperatura_lead_fn(p_limite integer)
returns table (lead_id uuid, historial text, reserva uuid)
language plpgsql security definer set search_path = '' as $$
begin
  if auth.jwt()->>'role' is distinct from 'service_role' then
    raise exception 'Acceso interno' using errcode = '42501';
  end if;
  if p_limite is null or p_limite < 1 or p_limite > 50 then
    raise exception using errcode = '22023', message = 'Limite fuera de rango';
  end if;
  -- Primero se jubila lo agotado. Sin esto, la 9.ª toma de una fila rompería el
  -- CHECK de `intentos` y la excepción se llevaría por delante el lote entero
  -- — y como esa fila es la más antigua, TODAS las tomas siguientes también.
  update crm.lead_temperatura t
     set estado = 'fallido', reserva = null, reservado_hasta = null,
         actualizado_en = pg_catalog.now()
   where t.estado = 'pendiente' and t.intentos >= 8;
  return query
  with elegidas as (
    select t.lead_id from crm.lead_temperatura t
    where t.estado = 'pendiente' and t.disponible_en <= pg_catalog.now()
      and t.intentos < 8
    order by t.disponible_en
    limit p_limite
    for update skip locked
  ), tomadas as (
    -- Una reserva POR FILA: con una sola para todo el lote, quien la tuviera
    -- podría confirmar cualquier otro lead del mismo lote.
    update crm.lead_temperatura t
       set estado = 'calculando', reserva = pg_catalog.gen_random_uuid(),
           reservado_hasta = pg_catalog.now() + interval '5 minutes',
           intentos = t.intentos + 1, actualizado_en = pg_catalog.now()
      from elegidas e where e.lead_id = t.lead_id
    returning t.lead_id, t.reserva
  )
  select tm.lead_id, private.temperatura_historial_lead(tm.lead_id), tm.reserva
  from tomadas tm;
end;
$$;
comment on function crm.tomar_temperatura_lead_fn(integer) is
  'Reserva hasta p_limite leads pendientes (reserva propia por fila, 5 min) y devuelve su historial. Jubila las filas con 8 intentos. Solo service_role.';

create function crm.confirmar_temperatura_lead_fn(
  p_lead_id uuid, p_reserva uuid, p_nivel numeric, p_probabilidades jsonb,
  p_confianza numeric, p_modelo text, p_huella text, p_error text
) returns boolean
language plpgsql security definer set search_path = '' as $$
declare v_ok boolean;
begin
  if auth.jwt()->>'role' is distinct from 'service_role' then
    raise exception 'Acceso interno' using errcode = '42501';
  end if;
  if p_error is not null then
    -- Espera creciente: 2, 4, 8… minutos, con techo. `least` NO se califica:
    -- es una construcción del parser, no una función de `pg_catalog` (42883).
    update crm.lead_temperatura t
       set estado = case when t.intentos >= 8 then 'fallido' else 'pendiente' end,
           disponible_en = pg_catalog.now()
             + (interval '1 minute' * pg_catalog.power(2, least(t.intentos, 6))),
           reserva = null, reservado_hasta = null,
           error_codigo = pg_catalog.left(p_error, 40),
           actualizado_en = pg_catalog.now()
     where t.lead_id = p_lead_id and t.reserva = p_reserva
       and t.estado = 'calculando' and t.reservado_hasta > pg_catalog.now()
    returning true into v_ok;
    return coalesce(v_ok, false);
  end if;
  if p_nivel is null or p_nivel < 0 or p_nivel > 3 or p_modelo is null or p_huella is null then
    raise exception using errcode = '22023', message = 'Resultado de temperatura invalido';
  end if;
  -- La reserva viva es el candado: si el analista registró una gestión mientras
  -- se calculaba, el trigger la anuló y esta respuesta —ya vieja— no aterriza.
  update crm.lead_temperatura t
     set estado = 'listo', nivel = p_nivel, probabilidades = p_probabilidades,
         confianza = p_confianza, modelo = p_modelo, huella_historial = p_huella,
         calculado_en = pg_catalog.now(), intentos = 0, reserva = null,
         reservado_hasta = null, error_codigo = null,
         actualizado_en = pg_catalog.now()
   where t.lead_id = p_lead_id and t.reserva = p_reserva
     and t.estado = 'calculando' and t.reservado_hasta > pg_catalog.now()
  returning true into v_ok;
  return coalesce(v_ok, false);
end;
$$;
comment on function crm.confirmar_temperatura_lead_fn(uuid,uuid,numeric,jsonb,numeric,text,text,text) is
  'Guarda el resultado del modelo, o reprograma con espera creciente si falló. Exige reserva propia y vigente: una respuesta tardía no pisa un cálculo nuevo.';

-- ---------------------------------------------------------------------------
-- 6. Firma del cron. Mismo blindaje que los avisos de tasa: la Edge Function se
--    despliega con `verify_jwt=false`, así que su único portero es esta firma y
--    la comparación tiene que ser de tamaño fijo.
-- ---------------------------------------------------------------------------
create function crm.verificar_cron_temperatura_fn(p_firma text, p_instante bigint)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare v_proyecto text; v_secreto text;
        v_ahora bigint := pg_catalog.floor(extract(epoch from pg_catalog.now()))::bigint;
begin
  if auth.jwt()->>'role' is distinct from 'service_role' then
    raise exception 'Acceso interno' using errcode = '42501';
  end if;
  if p_firma is null or p_firma !~ '^[a-f0-9]{64}$' or p_instante is null
     or p_instante < v_ahora - 120 or p_instante > v_ahora + 30 then return false; end if;
  select decrypted_secret into v_proyecto from vault.decrypted_secrets where name = 'crm_push_proyecto';
  select decrypted_secret into v_secreto from vault.decrypted_secrets where name = 'cron_temperatura_secret';
  if v_proyecto is null or v_secreto is null then return false; end if;
  -- Compara hashes de tamaño fijo para no revelar prefijos de la firma válida.
  return extensions.digest(pg_catalog.decode(p_firma,'hex'),'sha256') = extensions.digest(
    extensions.hmac('crm-temperatura:' || v_proyecto || ':' || p_instante::text,
                    v_secreto, 'sha256'), 'sha256');
end;
$$;
comment on function crm.verificar_cron_temperatura_fn(text,bigint) is
  'Valida la firma HMAC del cron contra el Vault, con ventana -120/+30 s y comparación de tamaño fijo. Cadena propia (crm-temperatura:) para que una firma no valga en otra función.';

create function private.despertar_temperatura() returns void
language plpgsql security definer set search_path = '' as $$
declare v_proyecto text; v_secreto text;
        v_instante bigint := pg_catalog.floor(extract(epoch from pg_catalog.now()))::bigint;
begin
  perform private.reconciliar_temperatura();
  if not exists (select 1 from crm.lead_temperatura
                 where estado = 'pendiente' and disponible_en <= pg_catalog.now()) then
    return;
  end if;
  select decrypted_secret into v_proyecto from vault.decrypted_secrets where name = 'crm_push_proyecto';
  select decrypted_secret into v_secreto from vault.decrypted_secrets where name = 'cron_temperatura_secret';
  -- Sin secretos configurados no se llama a nadie: la cola simplemente espera.
  if v_proyecto is null or v_proyecto !~ '^[a-z]{20}$' or v_secreto is null then return; end if;
  perform net.http_post(
    url := 'https://' || v_proyecto || '.supabase.co/functions/v1/crm-temperatura-lead',
    headers := jsonb_build_object('Content-Type','application/json',
      'x-cron-instante', v_instante::text,
      'x-cron-firma', pg_catalog.encode(extensions.hmac(
        'crm-temperatura:' || v_proyecto || ':' || v_instante::text, v_secreto, 'sha256'), 'hex')),
    body := '{"accion":"procesar"}'::jsonb, timeout_milliseconds := 55000);
end;
$$;
comment on function private.despertar_temperatura() is
  'Cron cada 2 minutos: reconcilia reservas caducadas y despierta la Edge Function si hay cola. Sin secretos en Vault no llama a nadie.';

-- ---------------------------------------------------------------------------
-- 7. Permisos. Nada para anon/authenticated: la señal no se lee desde el front.
-- ---------------------------------------------------------------------------
revoke all on function private.temperatura_historial_lead(uuid),
  private.encolar_temperatura_lead(), private.reconciliar_temperatura(),
  private.despertar_temperatura()
  from public, anon, authenticated, service_role;
revoke all on function crm.tomar_temperatura_lead_fn(integer),
  crm.confirmar_temperatura_lead_fn(uuid,uuid,numeric,jsonb,numeric,text,text,text),
  crm.verificar_cron_temperatura_fn(text,bigint)
  from public, anon, authenticated, service_role;
grant execute on function crm.tomar_temperatura_lead_fn(integer),
  crm.confirmar_temperatura_lead_fn(uuid,uuid,numeric,jsonb,numeric,text,text,text),
  crm.verificar_cron_temperatura_fn(text,bigint) to service_role;

-- ---------------------------------------------------------------------------
-- 8. Siembra: los leads vivos con al menos dos gestiones humanas. Los demás no
--    tienen nada que leer, y un lead sin señal no estorba (la F2 lo tratará
--    como «desconocido», que NO es lo mismo que «frío»).
-- ---------------------------------------------------------------------------
insert into crm.lead_temperatura (lead_id)
select l.id from crm.leads l
where l.activo = true
  and l.etapa in ('nuevo','contactado','reunion_agendada','propuesta_enviada')
  and (select count(*) from crm.actividades a
       where a.lead_id = l.id
         and a.tipo not in ('cambio_etapa','reasignacion','conversion')) >= 2
on conflict (lead_id) do nothing;

select cron.schedule('crm-temperatura-lead','*/2 * * * *','select private.despertar_temperatura()');

-- ---------------------------------------------------------------------------
-- 9. Postflight: se cuenta lo que QUEDÓ, no lo que se quiso. Cualquier fallo
--    aborta la transacción entera.
-- ---------------------------------------------------------------------------
do $$
declare v_n integer;
begin
  if not (select relrowsecurity from pg_class where oid = 'crm.lead_temperatura'::regclass) then
    raise exception 'Postflight: RLS apagada en crm.lead_temperatura';
  end if;
  select count(*) into v_n from pg_policies
   where schemaname = 'crm' and tablename = 'lead_temperatura';
  if v_n <> 0 then raise exception 'Postflight: % policies inesperadas', v_n; end if;

  for v_n in select 1 from unnest(array['anon','authenticated']) r
    where has_table_privilege(r, 'crm.lead_temperatura', 'select')
       or has_table_privilege(r, 'crm.lead_temperatura', 'insert')
       or has_table_privilege(r, 'crm.lead_temperatura', 'update')
  loop
    raise exception 'Postflight: un rol del front alcanza crm.lead_temperatura';
  end loop;

  select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where (n.nspname, p.proname) in (
           ('private','temperatura_historial_lead'), ('private','encolar_temperatura_lead'),
           ('private','reconciliar_temperatura'), ('private','despertar_temperatura'),
           ('crm','tomar_temperatura_lead_fn'), ('crm','confirmar_temperatura_lead_fn'),
           ('crm','verificar_cron_temperatura_fn'))
     and p.proconfig @> array['search_path=""'];  -- el vacío se guarda CON comillas
  if v_n <> 7 then raise exception 'Postflight: % de 7 funciones con search_path fijo', v_n; end if;

  for v_n in select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace,
                  unnest(array['anon','authenticated','public']) r
    where n.nspname in ('crm','private') and p.proname like '%temperatura%'
      and has_function_privilege(r, p.oid, 'execute')
  loop
    raise exception 'Postflight: una funcion de temperatura es ejecutable por el front';
  end loop;

  if not exists (select 1 from pg_trigger
                 where tgrelid = 'crm.actividades'::regclass
                   and tgname = 'trg_zz_actividades_temperatura' and not tgisinternal) then
    raise exception 'Postflight: falta el trigger de encolado';
  end if;

  select count(*) into v_n from crm.lead_temperatura;
  raise notice 'Postflight OK — % leads sembrados en la cola', v_n;
end;
$$;

notify pgrst,'reload schema';
commit;
