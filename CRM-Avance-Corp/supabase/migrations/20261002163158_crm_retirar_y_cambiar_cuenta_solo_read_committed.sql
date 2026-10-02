-- Cuentas de pago · «Retirar cuenta» y «Cambiar cuenta de pago» solo en READ COMMITTED (02/10/2026).
--
-- Qué hace: a los dos núcleos (private.retirar_cuenta_cliente_autorizado, F4 del 27/09, y
-- private.cambiar_cuenta_pago_contratos_autorizado, F3 del 26/09 corregida el 27/09) se les añade, como
-- PRIMERA comprobación, la misma negativa de modo de transacción que ya lleva «Asignar cuenta»
-- (20261002005004): si la transacción no va en READ COMMITTED, error 0A000 antes de mirar nada. El resto
-- del cuerpo queda byte a byte igual: mismas puertas, permisos, candados, textos de error y registros.
--
-- Por qué: riesgo medido en el banco de «Asignar cuenta» (01–02/10): en otro modo de transacción, «Retirar
-- cuenta» podía retirar una cuenta recién asignada que, en READ COMMITTED, se niega a retirar; y «Cambiar
-- cuenta de pago» podía dar por vigente a un administrador ya revocado. Solo alcanzable con SQL lanzado a
-- mano: PostgREST siempre va en READ COMMITTED, así que ninguna pantalla ni edge cambia. Decisión de
-- Miguel, 02/10/2026 (~11:05): «Sí, después de entregar F6».
--
-- Qué NO toca: las puertas crm.retirar_cuenta_cliente y crm.cambiar_cuenta_pago_contratos, grants, ACL,
-- search_path, triggers, tablas, ni nada de public. No crea objetos. Es idempotente en el sentido de que
-- se niega a aplicarse dos veces (los cuerpos vivos ya no serían los esperados).
--
-- Seguros: se niega si los cuerpos vivos no son exactamente los de hoy (huellas de abajo); tras aplicar,
-- exige las huellas nuevas, SECURITY DEFINER, search_path vacío y la ACL de siempre (solo authenticated).
-- Atomicidad: va envuelta en begin/commit con lock_timeout 5 s y statement_timeout 60 s, como sus hermanas de
-- octubre; si falla el pre o el postflight, no queda nada aplicado (`db query --file` manda el archivo entero en
-- una petición; acreditado el 02/10/2026 con el ensayo de 20261001233019, que termina en error sin dejar rastro).
-- Reversa: supabase/scripts/cuentas-pago-negativa/reversa.sql (repone los cuerpos anteriores exactos).
-- Registro: supabase/scripts/cuentas-pago-negativa/registrar.sql (db query no registra).
-- Huellas (md5 de prosrc): retirar vivo 3ab8983f87f343e896acaefafbbcf4d4 → 748918fb544b22cd96c4daf884761b52;
--                          cambiar vivo 61bec6b3d7d7589e67b4740bd9e7d630 → 1d6443c826ecd6b64db32c9dc247f7f8.

begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

-- ── 1. Preflight: los cuerpos vivos son los de hoy ─────────────────────────────────────────────
do $preflight$
begin
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception 'SOLO_READ_COMMITTED: esta migración se aplica en READ COMMITTED (va en %)',
      pg_catalog.current_setting('transaction_isolation');
  end if;
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure('private.retirar_cuenta_cliente_autorizado(uuid,uuid,uuid,text,text)')) is distinct from '3ab8983f87f343e896acaefafbbcf4d4' then
    raise exception 'SOLO_READ_COMMITTED: private.retirar_cuenta_cliente_autorizado no tiene el cuerpo esperado (vivo hoy); no se toca nada';
  end if;
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure('private.cambiar_cuenta_pago_contratos_autorizado(uuid,uuid,uuid,uuid[],text,text)')) is distinct from '61bec6b3d7d7589e67b4740bd9e7d630' then
    raise exception 'SOLO_READ_COMMITTED: private.cambiar_cuenta_pago_contratos_autorizado no tiene el cuerpo esperado (vivo hoy); no se toca nada';
  end if;
end $preflight$;

-- ── 2. Los dos núcleos, con la negativa como primera comprobación ──────────────────────────────
create or replace function private.retirar_cuenta_cliente_autorizado(
  p_solicitud_id uuid, p_cliente_id uuid, p_cuenta_id uuid, p_motivo text, p_respaldo_ruta text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_motivo text := pg_catalog.regexp_replace(coalesce(p_motivo, ''), '^[[:space:]\u00a0\u1680\u2000-\u200b\u2028\u2029\u202f\u205f\u3000\ufeff]+|[[:space:]\u00a0\u1680\u2000-\u200b\u2028\u2029\u202f\u205f\u3000\ufeff]+$', '', 'g');
  v_ruta text := nullif(pg_catalog.btrim(coalesce(p_respaldo_ruta, '')), '');
  v_previo crm.cuentas_bancarias_retiros%rowtype;
  v_cuenta crm.cuentas_bancarias%rowtype;
  v_obj storage.objects%rowtype;
  v_abiertos text[];
  v_quien text;
begin
  -- Solo READ COMMITTED: la misma negativa que lleva «Asignar cuenta» (20261002005004). Con una
  -- fotografía fija (REPEATABLE READ o SERIALIZABLE) se podría ver vigente a un administrador ya
  -- revocado, o no ver un vínculo que otro intento acaba de crear. Se comprueba antes de mirar nada.
  -- Por la API (PostgREST) la transacción siempre va en READ COMMITTED: ninguna pantalla cambia.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception using errcode = '0A000',
      message = 'El retiro de cuenta no admite este modo de transacción';
  end if;
  if not coalesce(private.admin_banca_vigente(v_actor), false) then
    raise exception using errcode = '42501', message = 'Solo administración puede retirar cuentas bancarias';
  end if;
  if p_solicitud_id is null or p_cliente_id is null or p_cuenta_id is null then
    raise exception using errcode = '22023', message = 'Faltan datos del retiro';
  end if;
  if pg_catalog.length(pg_catalog.regexp_replace(v_motivo, '[[:space:]\u00a0\u1680\u2000-\u200b\u2028\u2029\u202f\u205f\u3000\ufeff]', '', 'g')) < 5
     or pg_catalog.length(v_motivo) > 500 then
    raise exception using errcode = '22023', message = 'Escribe el motivo del retiro (5 a 500 caracteres)';
  end if;

  -- Idempotencia: la misma solicitud (doble clic, reintento) no se aplica dos veces; con otros
  -- datos se rechaza. Va antes de mirar la cuenta, que tras el primer intento ya está retirada.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('retiro-cuenta:' || p_solicitud_id::text, 0));
  select * into v_previo from crm.cuentas_bancarias_retiros where solicitud_id = p_solicitud_id;
  if found then
    if v_previo.cuenta_id = p_cuenta_id and v_previo.cliente_id = p_cliente_id
       and v_previo.motivo = v_motivo and v_previo.respaldo_ruta is not distinct from v_ruta then
      return pg_catalog.jsonb_build_object('solicitud_id', p_solicitud_id, 'ya_aplicada', true,
        'cuenta_id', p_cuenta_id);
    end if;
    raise exception using errcode = '22023', message = 'Esta solicitud ya se usó con otros datos';
  end if;

  -- La cuenta: del cliente y vigente. Bloqueo exclusivo: un alta de contrato o un cambio de F3
  -- que la elijan esperan a este retiro y después la ven retirada.
  select * into v_cuenta from crm.cuentas_bancarias where id = p_cuenta_id for update;
  if not found or v_cuenta.cliente_id is distinct from p_cliente_id then
    raise exception using errcode = '22023', message = 'La cuenta no es de este cliente';
  end if;
  if not v_cuenta.activa then
    select pr.nombre_completo into v_quien
    from public.perfiles pr
    where pr.id = v_cuenta.desactivada_por and pr.rol <> 'cliente';
    if exists (select 1 from crm.cuentas_bancarias_retiros r where r.cuenta_id = p_cuenta_id) then
      raise exception using errcode = '22023',
        message = pg_catalog.format('La cuenta ya fue retirada el %s%s',
          pg_catalog.to_char(v_cuenta.desactivada_en at time zone 'America/Lima', 'DD/MM/YYYY'),
          case when v_quien is not null then ' por ' || v_quien else '' end);
    end if;
    -- Desactivada por una corrección de datos (nueva versión) u otra vía: no fue un «retiro».
    raise exception using errcode = '22023',
      message = pg_catalog.format('La cuenta ya no está vigente desde el %s: se reemplazó por una versión corregida',
        pg_catalog.to_char(v_cuenta.desactivada_en at time zone 'America/Lima', 'DD/MM/YYYY'));
  end if;

  -- Contratos abiertos que todavía cobran en esta cuenta FÍSICA (mismo cliente, moneda y CCI): una
  -- cuenta corregida deja versiones viejas, inactivas pero todavía enlazadas a sus contratos, y el
  -- registro de pagos las acepta como instrucción contractual. Primero se cambia su cuenta de pago
  -- (F3). Ninguna vía crea enlaces hacia versiones inactivas (alta y F3 exigen activa bajo bloqueo):
  -- los enlaces viejos solo pueden irse, y eso falla cerrado.
  select pg_catalog.array_agg(ct.numero_contrato order by ct.numero_contrato) into v_abiertos
  from crm.contrato_cuentas_pago l
  join crm.cuentas_bancarias cb on cb.id = l.cuenta_bancaria_id
  join public.contratos ct on ct.id = l.contrato_id
  where cb.cliente_id = v_cuenta.cliente_id
    and cb.moneda = v_cuenta.moneda
    and cb.cci = v_cuenta.cci
    and ct.estado in ('activo', 'vencido');
  if coalesce(pg_catalog.cardinality(v_abiertos), 0) > 0 then
    raise exception using errcode = '22023', detail = 'contratos_abiertos',
      message = pg_catalog.format('La cuenta todavía cobra %s %s. Primero cambia su cuenta de pago',
        case when pg_catalog.cardinality(v_abiertos) = 1 then 'el contrato' else 'los contratos' end,
        pg_catalog.array_to_string(v_abiertos, ', '));
  end if;

  -- Respaldo opcional: si viene, el correo del cliente en su carpeta, subido por este mismo admin.
  -- Puede ser el mismo correo de un cambio de F3 («cambien mi cuenta y retiren la vieja»).
  if v_ruta is not null then
    if pg_catalog.split_part(v_ruta, '/', 1) is distinct from p_cliente_id::text
       or not coalesce(v_ruta ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(pdf|jpg|jpeg|png)$', false) then
      raise exception using errcode = '22023', message = 'El respaldo no es un archivo válido de este cliente';
    end if;
    select * into v_obj from storage.objects
    where bucket_id = 'respaldos-cambio-cuenta' and name = v_ruta;
    if not found
       or coalesce((v_obj.metadata->>'size')::bigint, 0) not between 1 and 10485760
       or coalesce(v_obj.metadata->>'mimetype', '') not in ('application/pdf', 'image/jpeg', 'image/png') then
      raise exception using errcode = '22023', message = 'El respaldo no es un archivo válido de este cliente';
    end if;
    if coalesce(v_obj.owner_id, v_obj.owner::text) is distinct from v_actor::text then
      raise exception using errcode = '22023', message = 'El respaldo debe subirlo quien retira la cuenta';
    end if;
  end if;

  update crm.cuentas_bancarias
     set activa = false,
         desactivada_por = v_actor,
         desactivada_en = pg_catalog.now()
   where id = p_cuenta_id;
  insert into crm.cuentas_bancarias_retiros
    (solicitud_id, cuenta_id, cliente_id, moneda, motivo, respaldo_ruta, retirado_por, retirado_en)
  values
    (p_solicitud_id, p_cuenta_id, p_cliente_id, v_cuenta.moneda, v_motivo, v_ruta, v_actor, pg_catalog.now());

  return pg_catalog.jsonb_build_object(
    'solicitud_id', p_solicitud_id, 'ya_aplicada', false, 'cuenta_id', p_cuenta_id,
    'banco', v_cuenta.banco, 'moneda', v_cuenta.moneda,
    'ultimos', pg_catalog.right(v_cuenta.numero_cuenta, 4));
end;
$function$;

create or replace function private.cambiar_cuenta_pago_contratos_autorizado(
  p_solicitud_id uuid, p_cliente_id uuid, p_cuenta_nueva_id uuid,
  p_contrato_ids uuid[], p_motivo text, p_respaldo_ruta text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_ids uuid[];
  v_motivo text := pg_catalog.regexp_replace(coalesce(p_motivo, ''), '^[[:space:]\u00a0\u1680\u2000-\u200b\u2028\u2029\u202f\u205f\u3000\ufeff]+|[[:space:]\u00a0\u1680\u2000-\u200b\u2028\u2029\u202f\u205f\u3000\ufeff]+$', '', 'g');
  v_previos integer;
  v_igual boolean;
  v_prev_ids uuid[];
  v_cuenta crm.cuentas_bancarias%rowtype;
  v_obj storage.objects%rowtype;
  v_ct record;
  v_contados integer := 0;
  v_hechos integer;
  v_etag text;
  v_en_curso text;
begin
  -- Solo READ COMMITTED: la misma negativa que lleva «Asignar cuenta» (20261002005004). Con una
  -- fotografía fija (REPEATABLE READ o SERIALIZABLE) se podría ver vigente a un administrador ya
  -- revocado, o no ver un vínculo que otro intento acaba de crear. Se comprueba antes de mirar nada.
  -- Por la API (PostgREST) la transacción siempre va en READ COMMITTED: ninguna pantalla cambia.
  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
    raise exception using errcode = '0A000',
      message = 'El cambio de cuenta de pago no admite este modo de transacción';
  end if;
  if not coalesce(private.admin_banca_vigente(v_actor), false) then
    raise exception using errcode = '42501',
      message = 'Solo administración puede cambiar la cuenta de pago';
  end if;
  if p_solicitud_id is null or p_cliente_id is null or p_cuenta_nueva_id is null then
    raise exception using errcode = '22023', message = 'Faltan datos del cambio';
  end if;
  v_ids := array(select distinct x from pg_catalog.unnest(p_contrato_ids) x where x is not null order by x);
  if coalesce(pg_catalog.cardinality(v_ids), 0) = 0
     or pg_catalog.cardinality(v_ids) <> coalesce(pg_catalog.cardinality(p_contrato_ids), 0)
     or pg_catalog.cardinality(v_ids) > 100 then
    raise exception using errcode = '22023', message = 'Elige entre 1 y 100 contratos, sin repetir';
  end if;
  if pg_catalog.length(pg_catalog.regexp_replace(v_motivo, '[[:space:]\u00a0\u1680\u2000-\u200b\u2028\u2029\u202f\u205f\u3000\ufeff]', '', 'g')) < 5
     or pg_catalog.length(v_motivo) > 500 then
    raise exception using errcode = '22023', message = 'Escribe el motivo del cambio (5 a 500 caracteres)';
  end if;

  -- Idempotencia: la misma solicitud (doble clic, reintento) no se aplica dos veces; con datos
  -- distintos (cuenta, contratos, motivo o respaldo) se rechaza.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('cambio-cuenta:' || p_solicitud_id::text, 0));
  select count(*),
         bool_and(c.cliente_id = p_cliente_id and c.cuenta_nueva_id = p_cuenta_nueva_id
                  and c.motivo = v_motivo and c.respaldo_ruta = p_respaldo_ruta),
         array_agg(c.contrato_id order by c.contrato_id)
    into v_previos, v_igual, v_prev_ids
  from crm.contrato_cuenta_pago_cambios c
  where c.solicitud_id = p_solicitud_id;
  if v_previos > 0 then
    if v_igual and v_prev_ids = v_ids then
      return pg_catalog.jsonb_build_object('solicitud_id', p_solicitud_id, 'ya_aplicada', true,
        'contratos', v_previos);
    end if;
    raise exception using errcode = '22023', message = 'Esta solicitud ya se usó con otros datos';
  end if;

  -- Respaldo: el correo del cliente, en su carpeta, subido por este mismo admin y sin usar en otra
  -- solicitud (el segundo candado serializa dos solicitudes que intenten el mismo archivo).
  if p_respaldo_ruta is null
     or pg_catalog.split_part(p_respaldo_ruta, '/', 1) is distinct from p_cliente_id::text
     or not coalesce(p_respaldo_ruta ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(pdf|jpg|jpeg|png)$', false) then
    raise exception using errcode = '22023', message = 'Adjunta el correo del cliente donde pide el cambio';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('respaldo-cambio-cuenta:' || p_respaldo_ruta, 0));
  select * into v_obj from storage.objects
  where bucket_id = 'respaldos-cambio-cuenta' and name = p_respaldo_ruta;
  if not found
     or coalesce((v_obj.metadata->>'size')::bigint, 0) not between 1 and 10485760
     or coalesce(v_obj.metadata->>'mimetype', '') not in ('application/pdf', 'image/jpeg', 'image/png') then
    raise exception using errcode = '22023', message = 'Adjunta el correo del cliente donde pide el cambio';
  end if;
  if coalesce(v_obj.owner_id, v_obj.owner::text) is distinct from v_actor::text then
    raise exception using errcode = '22023', message = 'El respaldo debe subirlo quien hace el cambio';
  end if;
  if exists (select 1 from crm.contrato_cuenta_pago_cambios c
             where c.respaldo_ruta = p_respaldo_ruta and c.solicitud_id <> p_solicitud_id) then
    raise exception using errcode = '22023', message = 'Ese correo ya respalda otro cambio registrado; revisa el historial o adjunta el correo de esta solicitud';
  end if;
  -- El mismo archivo subido otra vez con otra ruta tampoco vale: se compara la huella del
  -- contenido que calcula Storage (eTag), no un dato del navegador.
  v_etag := nullif(pg_catalog.btrim(v_obj.metadata->>'eTag', '"'), '');
  if v_etag is not null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('respaldo-etag:' || v_etag, 0));
    if exists (select 1 from crm.contrato_cuenta_pago_cambios c
               join storage.objects o on o.bucket_id = 'respaldos-cambio-cuenta' and o.name = c.respaldo_ruta
               where c.solicitud_id <> p_solicitud_id
                 and pg_catalog.btrim(o.metadata->>'eTag', '"') = v_etag) then
      raise exception using errcode = '22023', message = 'Ese correo ya respalda otro cambio registrado; revisa el historial o adjunta el correo de esta solicitud';
    end if;
  end if;

  -- Cuenta nueva: del cliente y vigente.
  select * into v_cuenta from crm.cuentas_bancarias where id = p_cuenta_nueva_id for share;
  if not found or v_cuenta.cliente_id is distinct from p_cliente_id then
    raise exception using errcode = '22023', message = 'La cuenta nueva no es de este cliente';
  end if;
  if not v_cuenta.activa then
    raise exception using errcode = '22023', message = 'La cuenta nueva ya no está vigente';
  end if;

  -- Contratos (se bloquean antes que los enlaces, como al registrar un pago): del cliente,
  -- abiertos y en la moneda de la cuenta.
  for v_ct in
    select ct.id, ct.cliente_id, ct.moneda, ct.estado, ct.numero_contrato
    from public.contratos ct
    where ct.id = any(v_ids)
    order by ct.id
    for share
  loop
    if v_ct.cliente_id is distinct from p_cliente_id then
      raise exception using errcode = '22023',
        message = pg_catalog.format('El contrato %s no es de este cliente', v_ct.numero_contrato);
    end if;
    if v_ct.estado not in ('activo', 'vencido') then
      raise exception using errcode = '22023',
        message = pg_catalog.format('El contrato %s está cerrado (%s)', v_ct.numero_contrato, v_ct.estado);
    end if;
    if v_ct.moneda is distinct from v_cuenta.moneda then
      raise exception using errcode = '22023',
        message = pg_catalog.format('El contrato %s es en %s y la cuenta nueva en %s',
          v_ct.numero_contrato, v_ct.moneda, v_cuenta.moneda);
    end if;
    v_contados := v_contados + 1;
  end loop;
  if v_contados <> pg_catalog.cardinality(v_ids) then
    raise exception using errcode = '22023', message = 'Algún contrato no existe';
  end if;
  perform 1 from crm.contrato_cuentas_pago l where l.contrato_id = any(v_ids) order by l.contrato_id for update;

  -- Un aviso al cliente en curso para estos contratos (reservado y sin confirmar): si el cambio
  -- entrara ahora, ese aviso anunciaría una cuenta que este cambio deja atrás. Con los enlaces ya
  -- bloqueados, toda reserva hecha antes está confirmada en la base y se ve aquí.
  select ct.numero_contrato into v_en_curso
  from crm.contrato_cuenta_pago_cambios c
  join crm.cambio_cuenta_avisos av on av.solicitud_id = c.solicitud_id
  join public.contratos ct on ct.id = c.contrato_id
  where c.contrato_id = any(v_ids)
    and av.reserva is not null
    and av.reclamado_en > pg_catalog.clock_timestamp() - interval '10 minutes'
  order by ct.numero_contrato
  limit 1;
  if v_en_curso is not null then
    raise exception using errcode = '22023',
      message = pg_catalog.format('Se está enviando al cliente el aviso de un cambio anterior del contrato %s; espera unos segundos y vuelve a intentar', v_en_curso);
  end if;

  -- Enlaces actuales: cada contrato debe tener cuenta de pago y no ser ya la nueva.
  for v_ct in
    select ct.numero_contrato, l.cuenta_bancaria_id
    from public.contratos ct
    left join crm.contrato_cuentas_pago l on l.contrato_id = ct.id
    where ct.id = any(v_ids)
    order by ct.id
  loop
    if v_ct.cuenta_bancaria_id is null then
      raise exception using errcode = '22023',
        message = pg_catalog.format('El contrato %s no tiene cuenta de pago; requiere conciliación', v_ct.numero_contrato);
    end if;
    if v_ct.cuenta_bancaria_id = p_cuenta_nueva_id then
      raise exception using errcode = '22023',
        message = pg_catalog.format('El contrato %s ya cobra en esa cuenta', v_ct.numero_contrato);
    end if;
  end loop;

  -- Primero la historia; luego el enlace (el candado exige esa historia en esta transacción).
  insert into crm.contrato_cuenta_pago_cambios
    (solicitud_id, contrato_id, cliente_id, cuenta_anterior_id, cuenta_nueva_id,
     motivo, respaldo_ruta, cambiado_por)
  select p_solicitud_id, l.contrato_id, p_cliente_id, l.cuenta_bancaria_id, p_cuenta_nueva_id,
         v_motivo, p_respaldo_ruta, v_actor
  from crm.contrato_cuentas_pago l
  where l.contrato_id = any(v_ids);

  update crm.contrato_cuentas_pago
     set cuenta_bancaria_id = p_cuenta_nueva_id
   where contrato_id = any(v_ids);
  get diagnostics v_hechos = row_count;
  if v_hechos <> pg_catalog.cardinality(v_ids) then
    raise exception 'CAMBIO_CUENTA: se esperaban % enlaces y se cambiaron %', pg_catalog.cardinality(v_ids), v_hechos;
  end if;

  return pg_catalog.jsonb_build_object(
    'solicitud_id', p_solicitud_id, 'ya_aplicada', false, 'contratos', v_hechos,
    'banco', v_cuenta.banco, 'moneda', v_cuenta.moneda);
end;
$function$;

-- ── 3. Comentarios: se conserva el texto que tenían y se añade una frase ──────────────────────
do $comentarios$
declare
  v_f record;
begin
  for v_f in select * from (values
      ('private.retirar_cuenta_cliente_autorizado(uuid,uuid,uuid,text,text)'),
      ('private.cambiar_cuenta_pago_contratos_autorizado(uuid,uuid,uuid,uuid[],text,text)')) as f(firma)
  loop
    execute pg_catalog.format('comment on function %s is %L', v_f.firma,
      coalesce(pg_catalog.obj_description(pg_catalog.to_regprocedure(v_f.firma), 'pg_proc'), '')
      || ' Solo admite READ COMMITTED (0A000 en cualquier otro modo; 20261002163158).');
  end loop;
end $comentarios$;

-- ── 4. Postflight: huellas nuevas y nada más cambió ────────────────────────────────────────────
do $postflight$
declare
  v_f record;
begin
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure('private.retirar_cuenta_cliente_autorizado(uuid,uuid,uuid,text,text)')) is distinct from '748918fb544b22cd96c4daf884761b52' then
    raise exception 'SOLO_READ_COMMITTED: private.retirar_cuenta_cliente_autorizado no tiene el cuerpo esperado (tras aplicar); no se toca nada';
  end if;
  if (select pg_catalog.md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure('private.cambiar_cuenta_pago_contratos_autorizado(uuid,uuid,uuid,uuid[],text,text)')) is distinct from '1d6443c826ecd6b64db32c9dc247f7f8' then
    raise exception 'SOLO_READ_COMMITTED: private.cambiar_cuenta_pago_contratos_autorizado no tiene el cuerpo esperado (tras aplicar); no se toca nada';
  end if;
  for v_f in select * from (values
      ('private.retirar_cuenta_cliente_autorizado(uuid,uuid,uuid,text,text)'),
      ('private.cambiar_cuenta_pago_contratos_autorizado(uuid,uuid,uuid,uuid[],text,text)')) as f(firma)
  loop
    if not exists (select 1 from pg_catalog.pg_proc p
                   where p.oid = pg_catalog.to_regprocedure(v_f.firma)
                     and p.prosecdef and p.provolatile = 'v' and not p.proleakproof and p.proconfig = array['search_path=""']) then
      raise exception 'SOLO_READ_COMMITTED: % perdió DEFINER, VOLATILE, el search_path vacío exacto o ganó LEAKPROOF', v_f.firma;
    end if;
    if exists (select 1 from pg_catalog.pg_proc p, pg_catalog.aclexplode(p.proacl) a
               where p.oid = pg_catalog.to_regprocedure(v_f.firma) and a.privilege_type = 'EXECUTE'
                 and a.grantee <> p.proowner and a.grantee <> 'authenticated'::regrole::oid)
       or (select p.proacl is null from pg_catalog.pg_proc p where p.oid = pg_catalog.to_regprocedure(v_f.firma))
       or not pg_catalog.has_function_privilege('authenticated', v_f.firma, 'EXECUTE') then
      raise exception 'SOLO_READ_COMMITTED: ACL inesperada en %', v_f.firma;
    end if;
  end loop;
end $postflight$;

select 'RETIRAR_CAMBIAR_SOLO_READ_COMMITTED_OK' as resultado;
commit;
