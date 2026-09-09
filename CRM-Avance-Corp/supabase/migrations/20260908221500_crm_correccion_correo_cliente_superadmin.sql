-- Corrección administrativa del CORREO de un cliente (puerta del superadmin).
--
-- POR QUÉ EXISTE. El correo de un cliente no es un dato de contacto: es su
-- CREDENCIAL DE ACCESO al portal, y vive en TRES sitios que tienen que moverse
-- juntos — `auth.users.email`, `auth.identities` (donde GoTrue busca de verdad
-- al usuario cuando inicia sesión) y `public.perfiles.correo`. Medido en
-- producción el 08/09/2026: los 435 clientes tienen los tres alineados, 0
-- desviaciones. Cambiar solo uno deja al cliente sin acceso EN SILENCIO: no
-- hay error, simplemente su correo deja de abrir la puerta.
--
-- Los dos que viven en `auth` solo se mueven juntos desde la API de
-- administración (`auth.admin.updateUserById`), que es de la edge, no de SQL.
-- Por eso esta migración instala la mitad que sí es del servidor:
--
--   1. `crm.correcciones_correo_cliente` — el rastro: quién, cuándo, de qué
--      correo a cuál, POR QUÉ y —clave— SI `auth` llegó a moverse.
--      `public.audit_log` ya guarda el antes/después de la fila entera, pero el
--      MOTIVO no cabe ahí y es justo lo que hay que poder buscar cuando un
--      cliente reclama que no puede entrar.
--   2. `crm.corregir_correo_cliente_admin_fn` — la única puerta: superadmin
--      del Portal, motivo obligatorio, correo único, todo en una transacción.
--   3. `crm.confirmar_correccion_correo_fn` — el acuse: la edge la llama DESPUÉS
--      de que `auth` respondió OK. Sin esto el rastro guardaría la INTENCIÓN y
--      no el RESULTADO, y una caída entre ambos pasos dejaría una fila idéntica
--      a la de un éxito (hallazgo P1-2 del auditor-rls, 08/09).
--   4. `crm.desviaciones_correo_cliente_fn` — el detector: cuenta los clientes
--      cuyo espejo no coincide con `auth`. Sin él, la premisa entera del diseño
--      («los tres se mueven juntos») no es verificable DESPUÉS de desplegar.
--
-- El CANDADO que cierra el UPDATE suelto de `perfiles.correo` NO va aquí: es un
-- trigger sobre `public.perfiles`, y tocar un objeto de `public` (el portal en
-- producción) exige el OK explícito de Miguel anotado en el ledger. Vive en
-- `20260908221501_crm_candado_correo_perfiles.sql` y se aplica aparte. Sin él
-- esta puerta funciona igual; lo que falta es la reja del atajo.
--
-- Molde: `crm.corregir_documento_cliente_admin_fn` y su
-- `trg_perfiles_zz_documento_protegido`, que resuelven exactamente el mismo
-- problema para el documento. Se copian sus dos llaves de paso
-- (`crm.op_privilegiada` + una propia) para que el candado distinga la puerta
-- legítima de un UPDATE suelto.
--
-- Decisiones de Miguel (08/09/2026): la corrección es SILENCIOSA (no se
-- notifica al cliente por correo) y la puede hacer SOLO el superadmin — no
-- admin, que sí puede corregir el documento. Por coherencia con esa decisión,
-- el rastro también lo LEE solo el superadmin.
--
-- APAGADA de hecho hasta que se despliegue la edge `corregir-correo-cliente`:
-- sin ella la RPC mueve el espejo pero no `auth`, así que la edge es la que
-- manda y esta migración no cambia ninguna conducta por sí sola.

begin;
set local lock_timeout='5s';
set local check_function_bodies=true;
select pg_advisory_xact_lock(hashtext('crm_correccion_correo_cliente'));

do $guard$
begin
  if to_regclass('crm.correcciones_correo_cliente') is not null then
    raise exception 'La corrección de correo ya está instalada';
  end if;
  -- El gate del gate: si `es_superadmin` cambió, esta puerta puede estar
  -- dejando pasar a quien no debe. Se recaptura y se revisa a mano.
  if md5(pg_get_functiondef('public.es_superadmin()'::regprocedure))
     is distinct from '12a443a1fd1597612d12a696ba501671' then
    raise exception 'Cambió public.es_superadmin(); recapturar y revisar antes de aplicar';
  end if;
  -- El auditor que la tabla nueva va a usar tiene que ser el vivo, no un homónimo.
  if md5(pg_get_functiondef('private.log_audit_crm()'::regprocedure))
     is distinct from '2d1b31c407d6eb882047112224792e73' then
    raise exception 'Cambió private.log_audit_crm(); recapturar y revisar antes de aplicar';
  end if;
  -- La tabla nace con FORCE RLS y su único escritor es un SECURITY DEFINER, así
  -- que el INSERT depende de que el dueño tenga BYPASSRLS. Medido el 08/09:
  -- postgres = true. Se comprueba en vez de darse por cierto.
  if not exists (select 1 from pg_roles where rolname = 'postgres' and rolbypassrls) then
    raise exception 'postgres perdió BYPASSRLS: el escritor DEFINER no podría insertar bajo FORCE RLS';
  end if;
end
$guard$;

-- ── 1. El rastro ─────────────────────────────────────────────────────────────
create table crm.correcciones_correo_cliente (
  id uuid primary key default gen_random_uuid(),
  -- ANULABLE y `on delete set null` a propósito: `crm.eliminar_cliente_fn` hace
  -- hard-delete de `public.perfiles`, y con CASCADE se borraría el registro de
  -- quién cambió una credencial y por qué — lo único que NO está en
  -- `public.audit_log`. Los dos correos quedan como identificación.
  cliente_id uuid references public.perfiles(id) on delete set null,
  correo_anterior text not null,
  correo_nuevo text not null,
  motivo text not null,
  -- Sin FK y anulable A PROPÓSITO: un rastro nunca puede tumbar la operación
  -- que audita. Un actor de Auth sin perfil dejaría el INSERT en rojo y con él
  -- la corrección entera; se guarda sin actor antes que reventar.
  por uuid,
  -- NULL = «el espejo se movió, pero nadie confirmó que `auth` también». Es la
  -- diferencia entre la INTENCIÓN y el RESULTADO: una fila que se queda así es
  -- una desviación que hay que mirar, no un éxito.
  auth_confirmado_en timestamptz,
  creado_en timestamptz not null default now()
);

create index correcciones_correo_cliente_cliente_idx
  on crm.correcciones_correo_cliente (cliente_id, creado_en desc);
-- Para encontrar de un vistazo las que se quedaron a medias.
create index correcciones_correo_cliente_sin_confirmar_idx
  on crm.correcciones_correo_cliente (creado_en desc)
  where auth_confirmado_en is null;

comment on table crm.correcciones_correo_cliente is
  'Rastro de las correcciones del correo de acceso de un cliente (puerta del superadmin). Append-only por RLS: la única escritura es crm.corregir_correo_cliente_admin_fn. auth_confirmado_en NULL = el espejo se movió sin que nadie confirmara auth.';
comment on column crm.correcciones_correo_cliente.auth_confirmado_en is
  'Cuándo la edge confirmó que auth.users/auth.identities también se movieron. NULL = a medias: revisar con crm.desviaciones_correo_cliente_fn().';

alter table crm.correcciones_correo_cliente enable row level security;
alter table crm.correcciones_correo_cliente force row level security;

-- Se lee, no se escribe: la única vía de escritura es la RPC SECURITY DEFINER,
-- que pasa por encima de RLS (postgres tiene BYPASSRLS, comprobado arriba). Sin
-- política de INSERT/UPDATE/DELETE, cualquier otra vía queda cerrada por defecto.
--
-- Lo lee SOLO el superadmin, no `es_admin()`: guarda dos direcciones de correo
-- (PII) y Miguel excluyó explícitamente a `admin` de esta operación — no tendría
-- sentido negarle hacerla y dejarle leer quién la hizo.
create policy correcciones_correo_cliente_superadmin_select
  on crm.correcciones_correo_cliente
  for select
  to authenticated
  using (public.es_superadmin());

revoke all on crm.correcciones_correo_cliente from anon, authenticated;
grant select on crm.correcciones_correo_cliente to authenticated;

-- El trinquete de auditoría exige los TRES verbos, AFTER, FOR EACH ROW, sin
-- `UPDATE OF` parcial y sin `WHEN`: cualquier recorte deja la tabla en rojo en
-- `private.tablas_sin_rastro()`.
create trigger trg_audit_correcciones_correo_cliente
  after insert or delete or update on crm.correcciones_correo_cliente
  for each row execute function private.log_audit_crm();

-- ── 2. La puerta ─────────────────────────────────────────────────────────────
create or replace function crm.corregir_correo_cliente_admin_fn(
  p_cliente_id uuid,
  p_correo text,
  p_motivo text
) returns jsonb
language plpgsql
security definer
set search_path to ''
set lock_timeout to '5s'
as $function$
DECLARE
  v_uid uuid := (SELECT auth.uid());
  v_nuevo text;
  v_anterior text;
  v_motivo text := pg_catalog.btrim(coalesce(p_motivo, ''));
  v_auth text;
  v_rastro uuid;
  -- Las llaves se GUARDAN y se RESTAURAN, como `private.enlazar_lead_reabierto`:
  -- `crm.op_privilegiada` es una válvula COMPARTIDA que otras guardas aceptan
  -- sola, y no se deja abierta detrás de uno. (P3-1 del auditor-rls.)
  v_previo_op text;
  v_previo_correo text;
BEGIN
  -- Decisión de Miguel 08/09: el correo es la llave de la casa, así que la
  -- puerta es más estrecha que la del documento (que sí admite `admin`).
  IF NOT public.es_superadmin() THEN
    RAISE EXCEPTION 'Solo el superadmin del Portal puede corregir el correo de acceso de un cliente'
      USING ERRCODE = '42501';
  END IF;

  v_nuevo := pg_catalog.lower(pg_catalog.btrim(coalesce(p_correo, '')));

  IF v_nuevo = '' THEN
    RAISE EXCEPTION 'El correo es obligatorio' USING ERRCODE = '22023';
  END IF;
  IF pg_catalog.length(v_nuevo) > 254 THEN
    RAISE EXCEPTION 'El correo es demasiado largo' USING ERRCODE = '22023';
  END IF;
  -- Deliberadamente laxo: la validación fuerte la hace GoTrue al mover
  -- `auth.users`. Aquí solo se rechaza lo que ni siquiera parece un correo,
  -- para no inventar una segunda gramática que discrepe de la de Auth.
  IF v_nuevo !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN
    RAISE EXCEPTION 'El correo electrónico no es válido' USING ERRCODE = '22023';
  END IF;

  IF pg_catalog.length(v_motivo) NOT BETWEEN 3 AND 500 THEN
    RAISE EXCEPTION 'El motivo debe tener entre 3 y 500 caracteres' USING ERRCODE = '22023';
  END IF;

  -- FOR UPDATE: sin el candado de fila, dos correcciones simultáneas leen el
  -- mismo `v_anterior` y la segunda registra en el rastro un «anterior» que ya
  -- no era el vigente. (P1-B de Codex.)
  SELECT pg_catalog.lower(pg_catalog.btrim(coalesce(p.correo, '')))
  INTO v_anterior
  FROM public.perfiles p
  WHERE p.id = p_cliente_id
    AND p.rol = 'cliente'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'El cliente no existe' USING ERRCODE = 'P0002';
  END IF;

  -- 🔑 «¿Ya está puesto?» se pregunta a AUTH, que es donde vive la verdad, NO al
  --    espejo. Si se preguntara al espejo, una caída entre moverlo y mover el
  --    acceso dejaría la operación ATASCADA PARA SIEMPRE: el operador reintenta
  --    el mismo correo, el espejo ya lo tiene, la RPC responde «es el mismo que
  --    el actual» y el acceso se queda atrás sin que nadie pueda repararlo desde
  --    la pantalla. Preguntando a auth, el reintento es el camino de REPARACIÓN.
  --    (P1-C de Codex.)
  SELECT pg_catalog.lower(pg_catalog.btrim(coalesce(u.email, '')))
  INTO v_auth
  FROM auth.users u
  WHERE u.id = p_cliente_id;

  IF v_auth IS NULL THEN
    RAISE EXCEPTION 'El cliente no tiene cuenta de acceso' USING ERRCODE = 'P0002';
  END IF;

  IF v_auth = v_nuevo THEN
    RAISE EXCEPTION 'El correo nuevo es el mismo con el que el cliente ya entra'
      USING ERRCODE = '22023';
  END IF;

  -- El choque real lo decide `auth.users`, que esta función no puede tocar;
  -- esto solo evita el viaje a la edge cuando ya se ve desde el espejo.
  IF EXISTS (
    SELECT 1 FROM public.perfiles p
    WHERE p.id <> p_cliente_id
      AND pg_catalog.lower(pg_catalog.btrim(coalesce(p.correo, ''))) = v_nuevo
  ) THEN
    RAISE EXCEPTION 'Ese correo ya pertenece a otra cuenta del Portal'
      USING ERRCODE = '23505';
  END IF;

  -- Las dos llaves del candado, solo hasta el final de esta transacción.
  v_previo_op := coalesce(pg_catalog.current_setting('crm.op_privilegiada', true), 'off');
  v_previo_correo := coalesce(pg_catalog.current_setting('crm.correccion_correo', true), 'off');
  PERFORM pg_catalog.set_config('crm.op_privilegiada', 'on', true);
  PERFORM pg_catalog.set_config('crm.correccion_correo', 'on', true);

  BEGIN
    UPDATE public.perfiles
    SET correo = v_nuevo,
        actualizado_en = pg_catalog.now()
    WHERE id = p_cliente_id
      AND rol = 'cliente';
  EXCEPTION WHEN unique_violation THEN
    -- Carrera contra otra alta o corrección: el UNIQUE global de perfiles.correo
    -- aflora crudo y con el nombre del constraint. Se traduce, como en el molde.
    PERFORM pg_catalog.set_config('crm.op_privilegiada', v_previo_op, true);
    PERFORM pg_catalog.set_config('crm.correccion_correo', v_previo_correo, true);
    RAISE EXCEPTION 'Ese correo ya pertenece a otra cuenta del Portal'
      USING ERRCODE = '23505';
  END;

  INSERT INTO crm.correcciones_correo_cliente
    (cliente_id, correo_anterior, correo_nuevo, motivo, por)
  VALUES (p_cliente_id, v_anterior, v_nuevo, v_motivo, v_uid)
  RETURNING id INTO v_rastro;

  -- La válvula compartida no se queda abierta detrás de uno.
  PERFORM pg_catalog.set_config('crm.op_privilegiada', v_previo_op, true);
  PERFORM pg_catalog.set_config('crm.correccion_correo', v_previo_correo, true);

  RETURN pg_catalog.jsonb_build_object(
    'ok', true,
    'cliente_id', p_cliente_id,
    'correo_anterior', v_anterior,
    'correo_nuevo', v_nuevo,
    'rastro_id', v_rastro,
    'por', v_uid
  );
END
$function$;

revoke all on function crm.corregir_correo_cliente_admin_fn(uuid, text, text) from public, anon;
grant execute on function crm.corregir_correo_cliente_admin_fn(uuid, text, text) to authenticated;

comment on function crm.corregir_correo_cliente_admin_fn(uuid, text, text) is
  'Mueve el ESPEJO del correo de acceso de un cliente (perfiles.correo) y abre el rastro con su motivo. Solo superadmin. La mitad de auth (users + identities) la mueve la edge corregir-correo-cliente, que DEBE cerrar el rastro con crm.confirmar_correccion_correo_fn: llamar a esta función sola deja la identidad desalineada. INVARIANTE: el tercer argumento de set_config es `true` (is_local) — con `false` las llaves sobrevivirían en un backend reutilizado del pool y se filtrarían a la siguiente petición de cualquier usuario.';

-- ── 3. El acuse: que el rastro diga si `auth` se movió ────────────────────────
create or replace function crm.confirmar_correccion_correo_fn(p_rastro_id uuid)
returns boolean
language plpgsql
security definer
set search_path to ''
set lock_timeout to '5s'
as $function$
DECLARE
  v_filas bigint := 0;
BEGIN
  IF NOT public.es_superadmin() THEN
    RAISE EXCEPTION 'Solo el superadmin del Portal puede confirmar una corrección de correo'
      USING ERRCODE = '42501';
  END IF;

  -- 🔑 EL ACUSE EXIGE PRUEBA, no palabra (P1-A de Codex). Antes cerraba la fila
  --    por decreto, así que quien llamara la RPC a mano podía mover el espejo y
  --    marcarlo «confirmado» sin que `auth` se hubiera movido jamás: una
  --    desviación disfrazada de éxito. Ahora la fila solo se cierra si el correo
  --    del rastro es de verdad el que abre la puerta.
  --
  --    Consecuencia buscada: una corrección hecha por fuera de la edge NO se
  --    puede cerrar, y queda a la vista de `crm.desviaciones_correo_cliente_fn`.
  --
  -- Idempotente: repetir el acuse no reescribe la hora del primero.
  UPDATE crm.correcciones_correo_cliente r
  SET auth_confirmado_en = pg_catalog.now()
  WHERE r.id = p_rastro_id
    AND r.auth_confirmado_en IS NULL
    AND EXISTS (
      SELECT 1 FROM auth.users u
      WHERE u.id = r.cliente_id
        AND pg_catalog.lower(pg_catalog.btrim(coalesce(u.email, ''))) = r.correo_nuevo
    );

  -- `ROW_COUNT` es un entero: capturarlo en un boolean depende de una conversión
  -- que Postgres no promete. Se guarda en bigint y se compara.
  GET DIAGNOSTICS v_filas = ROW_COUNT;
  RETURN v_filas > 0;
END
$function$;

revoke all on function crm.confirmar_correccion_correo_fn(uuid) from public, anon;
grant execute on function crm.confirmar_correccion_correo_fn(uuid) to authenticated;

comment on function crm.confirmar_correccion_correo_fn(uuid) is
  'Cierra una fila del rastro cuando la edge confirmó que auth.users/auth.identities se movieron. Una fila con auth_confirmado_en NULL es una corrección a medias.';

-- ── 4. El detector: la premisa, verificable DESPUÉS de desplegar ─────────────
create or replace function crm.desviaciones_correo_cliente_fn()
returns table (
  cliente_id uuid,
  problema text,
  correo_espejo text,
  correo_auth text,
  correo_identidad text
)
language sql
stable
security definer
set search_path to ''
as $function$
  -- «Los tres se mueven juntos» era una foto del 08/09 (435 clientes, 0
  -- desviaciones). Esto la convierte en una comprobación repetible.
  --
  -- Mira los TRES sitios, no dos: `auth.identities` es donde GoTrue busca de
  -- verdad al usuario por correo, así que un `auth.users` alineado no demuestra
  -- que el cliente pueda entrar. Y usa LEFT JOIN a propósito: un cliente SIN
  -- cuenta de acceso es la peor desviación posible y un INNER JOIN lo escondía.
  -- (P2 de Codex.)
  select p.id,
         case
           when u.id is null then 'sin cuenta de acceso'
           when i.id is null then 'sin identidad de correo en el acceso'
           when pg_catalog.lower(pg_catalog.btrim(coalesce(p.correo, '')))
                is distinct from pg_catalog.lower(pg_catalog.btrim(coalesce(u.email, '')))
             then 'la ficha no coincide con el acceso'
           else 'la identidad de acceso no coincide con el correo'
         end,
         pg_catalog.lower(pg_catalog.btrim(coalesce(p.correo, ''))),
         pg_catalog.lower(pg_catalog.btrim(coalesce(u.email, ''))),
         pg_catalog.lower(pg_catalog.btrim(coalesce(i.identity_data ->> 'email', '')))
  from public.perfiles p
  left join auth.users u on u.id = p.id
  left join auth.identities i on i.user_id = p.id and i.provider = 'email'
  where p.rol = 'cliente'
    and public.es_superadmin()
    and (
      u.id is null
      or i.id is null
      or pg_catalog.lower(pg_catalog.btrim(coalesce(p.correo, '')))
         is distinct from pg_catalog.lower(pg_catalog.btrim(coalesce(u.email, '')))
      or pg_catalog.lower(pg_catalog.btrim(coalesce(i.identity_data ->> 'email', '')))
         is distinct from pg_catalog.lower(pg_catalog.btrim(coalesce(u.email, '')))
    );
$function$;

revoke all on function crm.desviaciones_correo_cliente_fn() from public, anon;
grant execute on function crm.desviaciones_correo_cliente_fn() to authenticated;

comment on function crm.desviaciones_correo_cliente_fn() is
  'Clientes cuyos TRES sitios (perfiles.correo, auth.users.email, auth.identities) no coinciden, o a quienes les falta alguno. Debe devolver CERO filas. El gate va DENTRO del where: quien no es superadmin recibe vacío, no una lista de correos.';

-- Correcciones a medias: el espejo se movió y nadie pudo demostrar que `auth`
-- también. NO es lo mismo que una desviación —el acuse pudo perderse con todo
-- alineado— así que se pregunta aparte y no se mezcla con el detector.
create or replace function crm.correcciones_correo_sin_acuse_fn()
returns setof crm.correcciones_correo_cliente
language sql
stable
security definer
set search_path to ''
as $function$
  select r.* from crm.correcciones_correo_cliente r
  where r.auth_confirmado_en is null
    and public.es_superadmin()
  order by r.creado_en desc;
$function$;

revoke all on function crm.correcciones_correo_sin_acuse_fn() from public, anon;
grant execute on function crm.correcciones_correo_sin_acuse_fn() to authenticated;

comment on function crm.correcciones_correo_sin_acuse_fn() is
  'Correcciones cuyo acuse no se pudo cerrar. Revisar contra crm.desviaciones_correo_cliente_fn(): sin acuse PERO alineado = solo se perdió el acuse; sin acuse Y desviado = corrección a medias de verdad.';

-- ── Postflight: el veredicto viaja como FILA ─────────────────────────────────
-- `supabase db query` no transporta los `raise notice`, así que un gate que
-- buscara un aviso estaría SIEMPRE verde por vacío. Y no basta con contar
-- objetos: se comprueba lo que protege a los clientes.
do $post$
declare
  v_rel oid := 'crm.correcciones_correo_cliente'::regclass;
  v_escrituras int;
  v_grants_anon int;
  v_verbos int;
begin
  if not (select relrowsecurity and relforcerowsecurity from pg_class where oid = v_rel) then
    raise exception 'POSTFLIGHT: la tabla del rastro no quedó con RLS + FORCE';
  end if;

  select count(*) into v_escrituras
  from pg_policy where polrelid = v_rel and polcmd <> 'r';
  if v_escrituras <> 0 then
    raise exception 'POSTFLIGHT: el rastro tiene % policy(s) de escritura; debe ser solo lectura', v_escrituras;
  end if;

  -- «Revocar a anon no basta»: se mira el ACL crudo, incluido PUBLIC (grantee 0).
  select count(*) into v_grants_anon
  from pg_class c, aclexplode(c.relacl) a
  where c.oid = v_rel
    and a.grantee in (0, 'anon'::regrole::oid)
    and a.privilege_type <> 'SELECT';
  if v_grants_anon <> 0 then
    raise exception 'POSTFLIGHT: el rastro concede % privilegio(s) de escritura a anon/PUBLIC', v_grants_anon;
  end if;

  -- El trinquete de auditoría: los tres verbos, AFTER, FOR EACH ROW, sin recortes.
  select coalesce(bit_or(t.tgtype), 0) into v_verbos
  from pg_trigger t
  where t.tgrelid = v_rel and not t.tgisinternal
    and t.tgenabled in ('O','A') and (t.tgtype & 1) = 1 and (t.tgtype & 2) = 0
    and t.tgattr = ''::int2vector and t.tgqual is null
    and t.tgfoid = 'private.log_audit_crm()'::regprocedure;
  if (v_verbos & 28) <> 28 then
    raise exception 'POSTFLIGHT: el rastro no tiene auditoría completa (bit_or=%)', v_verbos;
  end if;

  if exists (select 1 from private.tablas_sin_rastro() where tabla = 'crm.correcciones_correo_cliente') then
    raise exception 'POSTFLIGHT: el trinquete de auditoría marca la tabla nueva como sin rastro';
  end if;
end
$post$;

select 'CORRECCION_CORREO_OK' as resultado,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'crm'
          and p.proname in ('corregir_correo_cliente_admin_fn',
                            'confirmar_correccion_correo_fn',
                            'desviaciones_correo_cliente_fn')) as puertas,
       (to_regclass('crm.correcciones_correo_cliente') is not null) as rastro,
       (select count(*) from private.tablas_sin_rastro()) as tablas_sin_rastro;

commit;
