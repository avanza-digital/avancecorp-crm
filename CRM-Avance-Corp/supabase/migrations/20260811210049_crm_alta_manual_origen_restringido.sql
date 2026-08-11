-- ============================================================================
-- Migración F — el alta manual solo admite los orígenes que un humano declara
-- ============================================================================
-- Implementa la decisión D8 de Miguel (2026-08-11, literal):
--   «referido, Wallking y OTRO esto puede registrar el vendedor;
--    landing y formulario se carga solo»
--   «[los referidos] solo los vendedores a su propio nombre»
--
-- LA REGLA, canal por canal
-- -------------------------
--   landing / formulario (y los heredados web / campania / whatsapp)
--       → SOLO entran por el puente (edge `crm-importar-leads`, INSERT directo
--         como service_role, que NO pasa por esta RPC y no se toca). El origen
--         de un canal automático lo pone la FUENTE; un alta manual que lo
--         declare está suplantando al canal.
--   referido   → solo el rol VENDEDOR, y siempre a su propio nombre. La
--                autoasignación YA la fuerza el bloque de destino («Solo puedes
--                crear leads asignados a ti mismo», 42501): aquí se cierra el
--                ROL, no el destino.
--   oficina (Wallking) / otro → alta manual de cualquiera de los tres roles
--                que admite la RPC (vendedor / supervisor / gerencia).
--
-- POR QUÉ IMPORTA A LA CONVERSIÓN (T10): con los referidos FUERA del divisor,
-- declarar un origen dejó de ser una etiqueta y pasó a mover el porcentaje de
-- alguien. La migración D sella la columna después de nacer; esta F cierra la
-- OTRA mitad del camino, la elección al nacer: los canales automáticos no se
-- pueden suplantar a mano, y el único origen con premio (el 15 % del referido)
-- solo lo declara quien se lo trabajó, sobre su propia cartera.
--
-- Con las dos, el escenario de re-etiquetado queda cerrado por las dos puntas:
-- lo automático trae su origen del puente y nadie lo reescribe (D); lo manual
-- del vendedor no puede hacerse pasar por un canal automático (F).
--
-- LO QUE ESTA MIGRACIÓN NO HACE, dicho sin adornos
-- ------------------------------------------------
-- · No toca el puente ni su edge: los canales automáticos siguen entrando
--   exactamente igual.
-- · No cambia el CHECK de la COLUMNA `crm.leads.origen` (los 8 valores siguen
--   siendo válidos como DATO: los históricos y los del puente los necesitan).
--   Se restringe el ALTA MANUAL, no el dominio.
-- · No arregla la VENTANA DEL FRONT: el formulario «Nuevo lead»
--   (`components/app/lead-nuevo.tsx`) ofrece hoy el catálogo entero (LANDING y
--   FORMULARIO incluidos) a cualquier rol. Hasta el release del paso 2 del
--   plan, quien elija un canal automático en ese formulario recibirá el 42501
--   de aquí con su mensaje — molesto pero honesto, y con la base en 1 lead y
--   el puente pausado, la ventana real es ~0 altas. El espejo del front
--   (filtrar ORIGENES por rol) viaja con el release.
-- · El caso POSITIVO de la regla (vendedor + referido → creado y autoasignado)
--   NO se prueba aquí: un postflight jamás inserta en producción. Vive en el
--   oráculo (CONV-23c, transaccional con rollback). Aquí solo se ejercitan las
--   DENEGACIONES, que no escriben nada.
--
-- Deriva vigilada: el cuerpo de `crm.crear_lead_si_disponible` se reproduce
-- ÍNTEGRO desde producción (pg_get_functiondef del 2026-08-11, md5
-- c14acec30e366a90b915b247b2a890e4, idéntico al de la migración
-- 20260804165440). El preflight aborta si el cuerpo vivo ya no es ese: si eso
-- pasa, alguien lo cambió después del 2026-08-11 y hay que INCORPORAR aquí su
-- cambio, no pisarlo (mismo protocolo que la migración D con
-- private.leads_before_update).
-- ============================================================================

begin;

set local lock_timeout = '10s';

-- ---------------------------------------------------------------------------
-- 0. Preflight
-- ---------------------------------------------------------------------------
do $preflight$
declare
  v_md5 text;
begin
  -- (0.1) La RPC existe con su firma completa.
  if pg_catalog.to_regprocedure(
       'crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text)'
     ) is null then
    raise exception 'PREFLIGHT F: crm.crear_lead_si_disponible no existe con la firma esperada';
  end if;

  -- (0.2) El cuerpo vivo es EXACTAMENTE el que esta migración reproduce.
  --       Si difiere, NO aplicar: diffear el prosrc vivo contra este fichero,
  --       incorporar aquí la protección nueva y recalcular el md5. Pisar a
  --       ciegas borraría un cambio hecho después del 2026-08-11.
  select pg_catalog.md5(pg_catalog.pg_get_functiondef(p.oid))
    into v_md5
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'crm' and p.proname = 'crear_lead_si_disponible';

  if v_md5 is distinct from 'c14acec30e366a90b915b247b2a890e4' then
    raise exception 'PREFLIGHT F: el cuerpo vivo de crear_lead_si_disponible (md5 %) no es el fotografiado el 2026-08-11 (c14acec30e366a90b915b247b2a890e4). Alguien lo cambio despues: incorporar ese cambio aqui y recalcular, no pisar.', v_md5;
  end if;

  -- (0.3) Los dominios que este fichero da por sentados siguen vigentes: el
  --       CHECK de la columna admite los 8 orígenes (el puente necesita los
  --       automáticos y los heredados).
  if not exists (
    select 1
    from pg_catalog.pg_constraint c
    where c.conrelid = 'crm.leads'::pg_catalog.regclass
      and c.contype = 'c'
      and pg_catalog.pg_get_constraintdef(c.oid) like '%origen%'
      and pg_catalog.pg_get_constraintdef(c.oid) like '%referido%'
      and pg_catalog.pg_get_constraintdef(c.oid) like '%landing%'
  ) then
    raise exception 'PREFLIGHT F: no se encontro el CHECK de crm.leads.origen con el dominio esperado';
  end if;
end;
$preflight$;

-- ---------------------------------------------------------------------------
-- 1. La RPC, íntegra, con la regla D8 añadida
-- ---------------------------------------------------------------------------
-- Cambio respecto del cuerpo de producción: SOLO el bloque marcado
-- «D8 (2026-08-11)» tras la validación de dominio del origen. Todo lo demás es
-- reproducción literal — perder una validación en la reescritura abriría un
-- agujero distinto del que se viene a cerrar.
create or replace function crm.crear_lead_si_disponible(
  p_nombre_completo text,
  p_telefono text,
  p_origen text,
  p_monto_estimado numeric,
  p_moneda text,
  p_id uuid default null,
  p_correo text default null,
  p_dni text default null,
  p_genero text default null,
  p_fecha_nacimiento date default null,
  p_distrito text default null,
  p_etapa text default 'nuevo',
  p_categoria_interes text default null,
  p_vendedor_id uuid default null,
  p_nota text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
set lock_timeout = '5s'
as $$
declare
  v_actor uuid := (select auth.uid());
  v_rol text;
  v_rol_actual text;
  v_id uuid := coalesce(p_id, pg_catalog.gen_random_uuid());
  v_nombre text := nullif(pg_catalog.btrim(p_nombre_completo), '');
  v_telefono text := private.normalizar_telefono(p_telefono);
  v_dni text := nullif(pg_catalog.btrim(p_dni), '');
  v_correo text := nullif(pg_catalog.btrim(p_correo), '');
  v_genero text := nullif(pg_catalog.btrim(p_genero), '');
  v_distrito text := nullif(pg_catalog.btrim(p_distrito), '');
  v_categoria text := nullif(pg_catalog.btrim(p_categoria_interes), '');
  v_nota text := nullif(pg_catalog.btrim(p_nota), '');
  v_vendedor uuid := p_vendedor_id;
  v_supervisor uuid;
  v_disponibilidad jsonb;
  v_existente crm.leads%rowtype;
  v_hoy_lima date := (pg_catalog.clock_timestamp() at time zone 'America/Lima')::date;
begin
  v_rol := private.rol_crm(v_actor);
  if v_actor is null or v_rol is null
     or v_rol not in ('vendedor', 'supervisor', 'gerencia') then
    raise exception using errcode = '42501', message = 'Acceso CRM revocado';
  end if;

  if v_nombre is null then
    raise exception using errcode = '22023', message = 'El nombre es obligatorio';
  end if;
  if v_telefono is null or v_telefono !~ '^\+519[0-9]{8}$' then
    return pg_catalog.jsonb_build_object(
      'estado', 'error',
      'detalle', 'telefono_invalido'
    );
  end if;
  if v_dni is not null and v_dni !~ '^[0-9]{8}$' then
    raise exception using errcode = '22023', message = 'El DNI debe tener exactamente 8 digitos';
  end if;
  if p_origen not in ('referido', 'landing', 'formulario', 'oficina', 'otro', 'web', 'campania', 'whatsapp') then
    raise exception using errcode = '22023', message = 'Origen invalido';
  end if;

  -- D8 (2026-08-11) · «landing y formulario se carga solo»: los canales
  -- automáticos (y los heredados) SOLO entran por el puente. Un alta manual que
  -- los declare está suplantando a la fuente — y con T10 vivo (el referido
  -- fuera del divisor), el origen mueve el porcentaje de alguien.
  if p_origen not in ('referido', 'oficina', 'otro') then
    raise exception using
      errcode = '42501',
      message = 'Ese origen entra solo por el puente: el alta manual admite referido, oficina u otro';
  end if;

  -- D8 (2026-08-11) · «solo los vendedores a su propio nombre»: el ROL se
  -- cierra aquí; el NOMBRE (autoasignación) ya lo fuerza el bloque de destino
  -- de más abajo, que rechaza con 42501 cualquier p_vendedor_id ajeno.
  if p_origen = 'referido' and v_rol <> 'vendedor' then
    raise exception using
      errcode = '42501',
      message = 'Un referido lo registra el vendedor que lo consiguio, a su propio nombre';
  end if;

  if p_etapa not in ('nuevo', 'contactado', 'reunion_agendada', 'propuesta_enviada') then
    raise exception using errcode = '22023', message = 'Un lead no puede nacer en etapa terminal';
  end if;
  if p_monto_estimado is null
     or p_monto_estimado <= 0
     or p_monto_estimado > 9999999999.99
     or p_monto_estimado <> pg_catalog.trunc(p_monto_estimado, 2) then
    raise exception using errcode = '22023', message = 'Capital estimado invalido';
  end if;
  if p_moneda not in ('PEN', 'USD') then
    raise exception using errcode = '22023', message = 'Moneda invalida';
  end if;
  if v_genero is not null and v_genero not in ('F', 'M') then
    raise exception using errcode = '22023', message = 'Genero invalido';
  end if;
  if v_categoria is not null and v_categoria not in ('nuevo', 'renovacion', 'upgrade') then
    raise exception using errcode = '22023', message = 'Categoria de interes invalida';
  end if;
  if p_fecha_nacimiento is not null
     and (
       p_fecha_nacimiento < date '1900-01-01'
       or p_fecha_nacimiento > (v_hoy_lima - interval '18 years')::date
     ) then
    raise exception using errcode = '22023', message = 'El lead debe tener al menos 18 anos';
  end if;

  -- El vendedor solo se autoasigna. Supervisor puede parkear en su propia
  -- bandeja o elegir dentro de su subarbol. Gerencia puede elegir cualquier
  -- destino operativo activo o dejar el lead en la cola global.
  if v_rol = 'vendedor' then
    if v_vendedor is not null and v_vendedor is distinct from v_actor then
      raise exception using errcode = '42501', message = 'Solo puedes crear leads asignados a ti mismo';
    end if;
    v_vendedor := v_actor;
    v_supervisor := null;
  elsif v_vendedor is null and v_rol = 'supervisor' then
    v_supervisor := v_actor;
  else
    v_supervisor := null;
  end if;

  if v_vendedor is not null then
    if not exists (
      select 1
      from private.vendedor_ids_visibles(v_actor) visible(perfil_id)
      where visible.perfil_id = v_vendedor
    ) then
      raise exception using errcode = '42501', message = 'El analista destino esta fuera de tu ambito';
    end if;
    if not private.es_destino_crm_activo(
      v_vendedor,
      array['vendedor', 'supervisor']::text[]
    ) then
      raise exception using errcode = '22023', message = 'El analista destino no puede recibir leads';
    end if;
  end if;

  -- La identidad optimista funciona también como llave idempotente: si el
  -- commit llegó pero la respuesta de red se perdió, repetir el MISMO payload
  -- antes de una mutación posterior confirma el alta anterior en vez de
  -- pintarla como un contacto ajeno.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('avancecrm:lead:id:' || v_id::text, 0)
  );
  perform private.bloquear_contactos_lead(array[v_telefono], array[v_dni]);

  -- Un administrador puede desactivar la membresia mientras esta sesion
  -- espera un contacto. El permiso se vuelve a consultar DESPUES de todos
  -- los locks para que una sesion revocada no alcance a insertar al despertar.
  v_rol_actual := private.rol_crm(v_actor);
  if v_rol_actual is distinct from v_rol
     or v_rol_actual not in ('vendedor', 'supervisor', 'gerencia') then
    raise exception using errcode = '42501', message = 'Acceso CRM revocado';
  end if;

  if v_vendedor is not null then
    if not exists (
      select 1
      from private.vendedor_ids_visibles(v_actor) visible(perfil_id)
      where visible.perfil_id = v_vendedor
    ) then
      raise exception using errcode = '42501', message = 'El analista destino esta fuera de tu ambito';
    end if;
    if not private.es_destino_crm_activo(
      v_vendedor,
      array['vendedor', 'supervisor']::text[]
    ) then
      raise exception using errcode = '22023', message = 'El analista destino no puede recibir leads';
    end if;
  end if;

  select l.* into v_existente
  from crm.leads l
  where l.id = v_id;

  if found then
    if v_existente.creado_por is not distinct from v_actor
       and v_existente.nombre_completo is not distinct from v_nombre
       and v_existente.telefono is not distinct from v_telefono
       and v_existente.correo is not distinct from v_correo
       and v_existente.dni is not distinct from v_dni
       and v_existente.genero is not distinct from v_genero
       and v_existente.fecha_nacimiento is not distinct from p_fecha_nacimiento
       and v_existente.distrito is not distinct from v_distrito
       and v_existente.origen is not distinct from p_origen
       and v_existente.etapa is not distinct from p_etapa
       and v_existente.monto_estimado is not distinct from p_monto_estimado
       and v_existente.moneda is not distinct from p_moneda
       and v_existente.categoria_interes is not distinct from v_categoria
       and v_existente.vendedor_id is not distinct from v_vendedor
       and v_existente.asignado_supervisor_id is not distinct from v_supervisor
       and v_existente.nota is not distinct from v_nota
       and v_existente.activo = true then
      return pg_catalog.jsonb_build_object('estado', 'creado', 'lead_id', v_id);
    end if;

    raise exception using
      errcode = '22023',
      message = 'El identificador de esta alta ya fue usado con datos distintos';
  end if;

  v_disponibilidad := private.verificar_disponibilidad_lead_impl(v_telefono, v_dni);

  if v_disponibilidad ->> 'estado' is distinct from 'libre' then
    return v_disponibilidad;
  end if;

  insert into crm.leads (
    id,
    nombre_completo,
    telefono,
    correo,
    dni,
    genero,
    fecha_nacimiento,
    distrito,
    origen,
    etapa,
    monto_estimado,
    moneda,
    categoria_interes,
    vendedor_id,
    asignado_supervisor_id,
    nota,
    activo,
    creado_por
  ) values (
    v_id,
    v_nombre,
    v_telefono,
    v_correo,
    v_dni,
    v_genero,
    p_fecha_nacimiento,
    v_distrito,
    p_origen,
    p_etapa,
    p_monto_estimado,
    p_moneda,
    v_categoria,
    v_vendedor,
    v_supervisor,
    v_nota,
    true,
    v_actor
  );

  return pg_catalog.jsonb_build_object('estado', 'creado', 'lead_id', v_id);
end;
$$;

comment on function crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text) is
  'Alta manual de leads (idempotente por p_id). D8 2026-08-11: solo admite origen referido/oficina/otro — landing y formulario entran SOLO por el puente — y referido exige rol vendedor con autoasignacion. Los canales automaticos no se pueden suplantar a mano.';

-- CREATE OR REPLACE conserva la ACL, pero se fija explícita por el mismo motivo
-- que en las migraciones A y D: un copy-paste incompleto rompe en silencio.
revoke all on function crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text)
  from public, anon, service_role;
grant execute on function crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Postflight
-- ---------------------------------------------------------------------------
do $postflight$
declare
  v_ok boolean;
  v_probe_vendedor uuid;
  v_probe_mando uuid;
begin
  -- (a) Forma: SECURITY DEFINER, VOLATILE, search_path vacío y lock_timeout.
  select p.prosecdef
         and p.provolatile = 'v'
         and p.proconfig @> array['search_path=""']
         and p.proconfig @> array['lock_timeout=5s']
    into v_ok
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'crm' and p.proname = 'crear_lead_si_disponible';
  if not coalesce(v_ok, false) then
    raise exception 'POSTFLIGHT F: la RPC perdio SECURITY DEFINER, la volatilidad o su proconfig';
  end if;

  -- (b) ACL: exactamente la de siempre — authenticated sí; anon y service_role no.
  if not pg_catalog.has_function_privilege(
       'authenticated',
       'crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text)'::pg_catalog.regprocedure,
       'EXECUTE') then
    raise exception 'POSTFLIGHT F: authenticated perdio EXECUTE sobre la RPC de alta';
  end if;
  if pg_catalog.has_function_privilege(
       'anon',
       'crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text)'::pg_catalog.regprocedure,
       'EXECUTE')
     or pg_catalog.has_function_privilege(
       'service_role',
       'crm.crear_lead_si_disponible(text,text,text,numeric,text,uuid,text,text,text,date,text,text,text,uuid,text)'::pg_catalog.regprocedure,
       'EXECUTE') then
    raise exception 'POSTFLIGHT F: anon o service_role ganaron EXECUTE sobre la RPC de alta';
  end if;

  -- (c) Sin sesión, la puerta sigue cerrada ANTES de llegar a la regla nueva.
  --     Solo corre cuando la migración aplica sin JWT (el caso normal); si una
  --     sesión con claims la aplicara, se salta y lo dice.
  if (select auth.uid()) is null then
    begin
      perform crm.crear_lead_si_disponible(
        'PROBE F SIN SESION', '+51999999990', 'referido', null, 'PEN');
      raise exception 'POSTFLIGHT F: CENTINELA — sin sesion la RPC debio rechazar con 42501 y no lo hizo';
    exception
      when insufficient_privilege then null; -- 42501: correcto
    end;
  else
    raise warning 'POSTFLIGHT F: se aplico con una sesion con claims; la sonda sin-sesion no corrio';
  end if;

  -- (d) Las DOS denegaciones nuevas, con identidad fabricada. Solo denegaciones:
  --     abortan en la validación, ANTES de locks y de cualquier INSERT, así que
  --     no escriben ni una fila ni en el branch ni en producción. El monto va
  --     NULL a propósito: si una regla nueva dejara pasar el origen por error,
  --     el 22023 de «Capital estimado invalido» delataría el hueco aquí mismo
  --     en vez de dejar que la sonda inserte.
  select e.perfil_id into v_probe_vendedor
  from crm.equipo e
  where e.activo and e.rol_crm = 'vendedor'
    and private.rol_crm(e.perfil_id) = 'vendedor'
  limit 1;

  select e.perfil_id into v_probe_mando
  from crm.equipo e
  where e.activo and e.rol_crm in ('supervisor', 'gerencia')
    and private.rol_crm(e.perfil_id) in ('supervisor', 'gerencia')
  limit 1;

  if v_probe_vendedor is null or v_probe_mando is null then
    -- Mundo sin roster (branch sin sembrar): las ramas quedan cubiertas por el
    -- oráculo (CONV-23a..d), que es quien las prueba con rollback. Se avisa en
    -- vez de fingir cobertura — y el ciclo corregido (seed ANTES de aplicar)
    -- hace que este aviso no deba verse nunca.
    raise warning 'POSTFLIGHT F: sin vendedor o sin mando en crm.equipo; las sondas de la regla D8 no corrieron aqui (las cubre CONV-23 del oraculo)';
  else
    -- (d1) Vendedor + canal automático → 42501 «entra solo por el puente».
    perform pg_catalog.set_config('request.jwt.claim.sub', v_probe_vendedor::text, true);
    begin
      perform crm.crear_lead_si_disponible(
        'PROBE F CANAL AUTOMATICO', '+51999999991', 'landing', null, 'PEN');
      raise exception 'POSTFLIGHT F: CENTINELA — un vendedor pudo declarar origen landing en el alta manual';
    exception
      when insufficient_privilege then
        if position('puente' in sqlerrm) = 0 then
          raise exception 'POSTFLIGHT F: el rechazo de landing llego con otro mensaje: %', sqlerrm;
        end if;
    end;

    -- (d2) Mando + referido → 42501 «solo los vendedores a su propio nombre».
    perform pg_catalog.set_config('request.jwt.claim.sub', v_probe_mando::text, true);
    begin
      perform crm.crear_lead_si_disponible(
        'PROBE F REFERIDO DE MANDO', '+51999999992', 'referido', null, 'PEN');
      raise exception 'POSTFLIGHT F: CENTINELA — un mando pudo declarar un referido';
    exception
      when insufficient_privilege then
        if position('propio nombre' in sqlerrm) = 0 then
          raise exception 'POSTFLIGHT F: el rechazo del referido de mando llego con otro mensaje: %', sqlerrm;
        end if;
    end;

    -- La identidad fabricada se retira: lo que venga después de esta migración
    -- en la misma transacción no debe heredar un JWT de mentira.
    perform pg_catalog.set_config('request.jwt.claim.sub', '', true);
  end if;
end;
$postflight$;

commit;

-- ============================================================================
-- Nota de aplicación
-- ============================================================================
-- 1. ORDEN: cuarta y última del paso 1 —
--    `20260811154434` (A) → `20260811190310` (E) → `20260811190324` (D) → ésta.
--    Todas en el MISMO ciclo de branch, con el orden corregido: `npm run
--    seed:demo` ANTES de aplicar, para que las sondas (d) de este postflight y
--    las de sus hermanas corran contra un mundo con roster y no caigan en su
--    rama de WARNING.
-- 2. Gate: el caso positivo (vendedor + referido → creado y autoasignado) y las
--    denegaciones viven en el oráculo como CONV-23a..d
--    (`supabase/scripts/test-conversion-mensual.sql`), que corre en el branch
--    con rollback. `test-rls.mjs` no necesita bloque nuevo: las denegaciones de
--    la RPC de alta ya quedan ejercitadas aquí y en el oráculo, y un caso
--    positivo por la Data API dejaría filas vivas en el branch.
-- 3. FRONT: hasta el release del paso 2, el formulario «Nuevo lead» sigue
--    ofreciendo LANDING y FORMULARIO; elegirlos devolverá el 42501 de esta
--    migración con su mensaje. Ventana aceptada (base en 1 lead, puente
--    pausado). El espejo — filtrar `ORIGENES` por rol en
--    `components/app/lead-nuevo.tsx` — viaja con ese release.
-- 4. `npm run gen:types` NO hace falta: la firma de la RPC no cambia.
-- 5. Si el preflight (0.2) aborta por md5: alguien cambió la RPC después del
--    2026-08-11. Diffear, incorporar aquí su cambio y recalcular el md5 —
--    nunca pisar a ciegas una función SECURITY DEFINER que escribe leads.
-- ============================================================================
