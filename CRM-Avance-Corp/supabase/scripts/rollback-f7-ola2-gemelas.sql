-- MARCHA ATRAS de la OLA 2 (las siete gemelas) — recrea las 7 piezas con su DEFINICION VIVA,
-- capturada de produccion el 2026-09-01 (owner, atributos y comentario incluidos).
--
-- Por que la fuente es la CAPTURA y no el repo: el repo tiene 167 de 193
-- archivos y la F5.d cambio los cuerpos de las gemelas DESPUES de que nacieran.
-- La carpeta local mentiria; el catalogo vivo no.
--
-- ⚠️ La fila del registro NO se borra aqui: retirarla A MANO (regla del proyecto).
-- ⚠️ Recrear en `public` SI REABRE la puerta: los default privileges de Supabase
--    devuelven EXECUTE a anon/authenticated/service_role en cuanto la funcion
--    vuelve a existir, y `revoke ... from public` (el ROL) no los quita. Por eso
--    cada recreacion revoca EXPLICITAMENTE a los tres roles de la API.
--    Lo cazo el vigilante F7 durante el ensayo del 01/09, no una lectura.

begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- Anti-pisado: solo se recrea si de verdad NO estan (si alguien ya las repuso,
-- este guion no las machaca a ciegas).
do $rb_pre$
declare v_n int;
begin
  select count(*) into v_n from unnest(array['crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)', 'crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)', 'crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb)', 'crm.crear_contrato_producto(uuid,jsonb,jsonb)', 'public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)', 'public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)', 'public.crear_contrato_producto(uuid,jsonb,jsonb)']) f
   where to_regprocedure(f) is not null;
  if v_n > 0 then
    raise exception 'rollback F5.d: % pieza(s) YA existen — investigar antes de recrear', v_n;
  end if;
  select count(*) into v_n from private.f7_piezas_en_observacion
   where ola = 'F5.d' and estado = 'demolida';
  if v_n <> 7 then
    raise exception 'rollback F5.d: el libro marca % demolidas, esperaba 7 — el mundo no es el que este guion revierte', v_n;
  end if;
end $rb_pre$;

CREATE OR REPLACE FUNCTION crm.actualizar_contrato_con_cuenta_producto(p_id uuid, p_producto_condicion_id uuid, p_contrato jsonb, p_cronograma jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_resultado jsonb;
  v_condicion_resultante uuid;
begin
  if not (select private.puede_registrar_ventas()) then
    raise insufficient_privilege using message = 'No autorizado para gestionar contratos desde el CRM';
  end if;
  if p_producto_condicion_id is null then
    raise exception 'Selecciona un producto de inversión'
      using errcode = '22023';
  end if;
  perform pg_catalog.set_config(
    'crm.producto_condicion_id', p_producto_condicion_id::text, true
  );
  perform crm.actualizar_contrato_con_cuenta(
    p_id, p_contrato, p_cronograma
  );
  perform pg_catalog.set_config('crm.producto_condicion_id', '', true);
  select c.producto_condicion_id into v_condicion_resultante
  from public.contratos c
  where c.id = p_id;
  if not found then
    raise exception 'Contrato no encontrado' using errcode = 'P0002';
  end if;
  v_resultado := jsonb_build_object('id', p_id, 'ok', true)
    || private.metadata_condicion_producto(v_condicion_resultante);
  return v_resultado;
exception when others then
  perform pg_catalog.set_config('crm.producto_condicion_id', '', true);
  raise;
end;
$function$;
alter function crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb) owner to postgres;
revoke all on function crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb) from public, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION crm.actualizar_contrato_producto(p_id uuid, p_producto_condicion_id uuid, p_contrato jsonb, p_cronograma jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_resultado jsonb;
  v_condicion_resultante uuid;
begin
  if not (select private.puede_registrar_ventas()) then
    raise insufficient_privilege using message = 'No autorizado para gestionar contratos desde el CRM';
  end if;
  if p_producto_condicion_id is null then
    raise exception 'Selecciona un producto de inversión'
      using errcode = '22023';
  end if;
  perform pg_catalog.set_config(
    'crm.producto_condicion_id', p_producto_condicion_id::text, true
  );
  v_resultado := public.actualizar_contrato(p_id, p_contrato, p_cronograma);
  perform pg_catalog.set_config('crm.producto_condicion_id', '', true);
  select c.producto_condicion_id into v_condicion_resultante
  from public.contratos c
  where c.id = p_id;
  if not found then
    raise exception 'Contrato no encontrado' using errcode = 'P0002';
  end if;
  return v_resultado
    || private.metadata_condicion_producto(v_condicion_resultante);
exception when others then
  perform pg_catalog.set_config('crm.producto_condicion_id', '', true);
  raise;
end;
$function$;
alter function crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb) owner to postgres;
revoke all on function crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb) from public, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION crm.crear_contrato_con_cuenta_producto(p_producto_condicion_id uuid, p_contrato jsonb, p_cronograma jsonb, p_cuenta jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_resultado jsonb;
begin
  if not (select private.puede_registrar_ventas()) then
    raise insufficient_privilege using message = 'No autorizado para gestionar contratos desde el CRM';
  end if;
  if p_producto_condicion_id is null then
    raise exception 'Selecciona un producto de inversión'
      using errcode = '22023';
  end if;
  perform pg_catalog.set_config(
    'crm.producto_condicion_id', p_producto_condicion_id::text, true
  );
  v_resultado := crm.crear_contrato_con_cuenta(
    p_contrato, p_cronograma, p_cuenta
  );
  perform pg_catalog.set_config('crm.producto_condicion_id', '', true);
  return v_resultado
    || private.metadata_condicion_producto(p_producto_condicion_id);
exception when others then
  perform pg_catalog.set_config('crm.producto_condicion_id', '', true);
  raise;
end;
$function$;
alter function crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb) owner to postgres;
revoke all on function crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb) from public, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION crm.crear_contrato_producto(p_producto_condicion_id uuid, p_contrato jsonb, p_cronograma jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_resultado jsonb;
begin
  if not (select private.puede_registrar_ventas()) then
    raise insufficient_privilege using message = 'No autorizado para gestionar contratos desde el CRM';
  end if;
  if p_producto_condicion_id is null then
    raise exception 'Selecciona un producto de inversión'
      using errcode = '22023';
  end if;
  perform pg_catalog.set_config(
    'crm.producto_condicion_id', p_producto_condicion_id::text, true
  );
  v_resultado := public.crear_contrato(p_contrato, p_cronograma);
  perform pg_catalog.set_config('crm.producto_condicion_id', '', true);
  return v_resultado
    || private.metadata_condicion_producto(p_producto_condicion_id);
exception when others then
  perform pg_catalog.set_config('crm.producto_condicion_id', '', true);
  raise;
end;
$function$;
alter function crm.crear_contrato_producto(uuid,jsonb,jsonb) owner to postgres;
revoke all on function crm.crear_contrato_producto(uuid,jsonb,jsonb) from public, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.actualizar_contrato_con_cuenta_producto(p_id uuid, p_producto_condicion_id uuid, p_contrato jsonb, p_cronograma jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_condicion_resultante uuid;
  v_resultado jsonb;
  v_config_anterior text := current_setting('crm.producto_condicion_id', true);
begin
  if not (select private.puede_registrar_ventas()) then
    raise insufficient_privilege using message = 'No autorizado para actualizar contratos con cuenta desde el Portal';
  end if;
  if p_producto_condicion_id is null then
    raise exception 'Selecciona un producto de inversión'
      using errcode = '22023';
  end if;

  perform pg_catalog.set_config(
    'crm.producto_condicion_id', p_producto_condicion_id::text, true
  );
  perform crm.actualizar_contrato_con_cuenta(
    p_id, p_contrato, p_cronograma
  );
  perform pg_catalog.set_config(
    'crm.producto_condicion_id', coalesce(v_config_anterior, ''), true
  );

  select ct.producto_condicion_id into v_condicion_resultante
  from public.contratos ct
  where ct.id = p_id;
  if not found then
    raise exception 'Contrato no encontrado' using errcode = 'P0002';
  end if;
  v_resultado := jsonb_build_object('id', p_id, 'ok', true)
    || private.metadata_condicion_producto(v_condicion_resultante);
  return v_resultado;
exception when others then
  perform pg_catalog.set_config(
    'crm.producto_condicion_id', coalesce(v_config_anterior, ''), true
  );
  raise;
end;
$function$;
alter function public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb) owner to postgres;
revoke all on function public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb) from public, anon, authenticated, service_role;
comment on function public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb) is $cmt$Corrección Portal catalogada que además conserva la coherencia de la cuenta bancaria contractual.$cmt$;

CREATE OR REPLACE FUNCTION public.actualizar_contrato_producto(p_id uuid, p_producto_condicion_id uuid, p_contrato jsonb, p_cronograma jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_resultado jsonb;
  v_condicion_resultante uuid;
  v_config_anterior text := current_setting('crm.producto_condicion_id', true);
begin
  if not (select private.puede_registrar_ventas()) then
    raise insufficient_privilege using message = 'No autorizado para actualizar contratos desde el Portal';
  end if;
  if p_producto_condicion_id is null then
    raise exception 'Selecciona un producto de inversión'
      using errcode = '22023';
  end if;

  perform pg_catalog.set_config(
    'crm.producto_condicion_id', p_producto_condicion_id::text, true
  );
  v_resultado := public.actualizar_contrato(p_id, p_contrato, p_cronograma);
  perform pg_catalog.set_config(
    'crm.producto_condicion_id', coalesce(v_config_anterior, ''), true
  );

  select ct.producto_condicion_id into v_condicion_resultante
  from public.contratos ct
  where ct.id = p_id;
  if not found then
    raise exception 'Contrato no encontrado' using errcode = 'P0002';
  end if;
  return v_resultado
    || private.metadata_condicion_producto(v_condicion_resultante);
exception when others then
  perform pg_catalog.set_config(
    'crm.producto_condicion_id', coalesce(v_config_anterior, ''), true
  );
  raise;
end;
$function$;
alter function public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb) owner to postgres;
revoke all on function public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb) from public, anon, authenticated, service_role;
comment on function public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb) is $cmt$Corrección Portal catalogada; conserva Admin/Superadmin/Analista, cartera, ventana y cierres de public.actualizar_contrato.$cmt$;

CREATE OR REPLACE FUNCTION public.crear_contrato_producto(p_producto_condicion_id uuid, p_contrato jsonb, p_cronograma jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_resultado jsonb;
  v_contrato_id uuid;
  v_condicion_resultante uuid;
  v_config_anterior text := current_setting('crm.producto_condicion_id', true);
begin
  if not (select private.puede_registrar_ventas()) then
    raise insufficient_privilege using message = 'No autorizado para crear contratos desde el Portal';
  end if;
  if p_producto_condicion_id is null then
    raise exception 'Selecciona un producto de inversión'
      using errcode = '22023';
  end if;

  perform pg_catalog.set_config(
    'crm.producto_condicion_id', p_producto_condicion_id::text, true
  );
  v_resultado := public.crear_contrato(p_contrato, p_cronograma);
  perform pg_catalog.set_config(
    'crm.producto_condicion_id', coalesce(v_config_anterior, ''), true
  );

  v_contrato_id := (v_resultado->>'id')::uuid;
  select ct.producto_condicion_id into v_condicion_resultante
  from public.contratos ct
  where ct.id = v_contrato_id;
  if not found then
    raise exception 'Contrato no encontrado después del alta' using errcode = 'P0002';
  end if;
  return v_resultado
    || private.metadata_condicion_producto(v_condicion_resultante);
exception when others then
  perform pg_catalog.set_config(
    'crm.producto_condicion_id', coalesce(v_config_anterior, ''), true
  );
  raise;
end;
$function$;
alter function public.crear_contrato_producto(uuid,jsonb,jsonb) owner to postgres;
revoke all on function public.crear_contrato_producto(uuid,jsonb,jsonb) from public, anon, authenticated, service_role;
comment on function public.crear_contrato_producto(uuid,jsonb,jsonb) is $cmt$Alta Portal catalogada; conserva la autorización de public.crear_contrato y fija la condición en la misma transacción.$cmt$;

-- El libro vuelve a `observacion`. La maquina de estados PROHIBE salir de
-- `demolida` salvo «por migracion con el candado bajado» (doctrina
-- limpieza-leads): se baja el trigger NOMBRADO, se corrige y se vuelve a subir
-- en la MISMA transaccion. Jamas un `disable trigger user` a ciegas.
alter table private.f7_piezas_en_observacion disable trigger trg_f7_obs_00_solo_crece;
update private.f7_piezas_en_observacion
   set estado = 'observacion',
       nota = coalesce(nota,'') || ' | REVERTIDA a observacion por la marcha atras ('
              || to_char((now() at time zone 'America/Lima')::date, 'YYYY-MM-DD')
              || '): la pieza fue recreada al byte desde la captura viva del 01/09.'
 where ola = 'F5.d' and estado = 'demolida';
alter table private.f7_piezas_en_observacion enable trigger trg_f7_obs_00_solo_crece;

-- Verificacion: volvieron las 7 ENTERAS y los guardianes quedan verdes.
-- ✏️ 01/09 (auditoria de Codex): comparar solo `md5(prosrc)` NO acredita una
--    recreacion fiel — en la Ola 2b una funcion volvio SIN su comentario y el
--    ensayo salio verde igual. Aqui se fija ademas la DEFINICION COMPLETA
--    (`pg_get_functiondef`: args, retorno, volatilidad, SECURITY DEFINER,
--    search_path, coste, filas), el COMENTARIO, el DUEÑO y el ACL EFECTIVO.
do $rb_post$
declare
  -- firma | huella del CUERPO | huella de la DEFINICION | comentario vivo (null = sin comentario)
  v_fn constant text[][] := array[
    array['crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)',
          '8640b1246f620ab40558cec2875ada23','956fb5f32191291d4b7ebafce5abbdb1', null],
    array['crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)',
          '4156191492c25479be73b0365263d946','1d884ef9f60a55dd4d0613a256e3ea71', null],
    array['crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb)',
          '06f79b07b4d65dcf50cd4359fb598723','a93f2db825cc26c19b1756cde0cdc435', null],
    array['crm.crear_contrato_producto(uuid,jsonb,jsonb)',
          '1148d0ca1beb33797995eeff3c579bd4','230bcc46e72191600cbd5fc789e1d503', null],
    array['public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)',
          'b7e0de18b559ec7fd650619cd22b9cb5','c786d25a9aca26f6a818dd57abe6ef72',
          'Corrección Portal catalogada que además conserva la coherencia de la cuenta bancaria contractual.'],
    array['public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)',
          'f0e519cc4ee79c9334ae59a23844b23b','7128b0ebb65497e67c56d5383988b512',
          'Corrección Portal catalogada; conserva Admin/Superadmin/Analista, cartera, ventana y cierres de public.actualizar_contrato.'],
    array['public.crear_contrato_producto(uuid,jsonb,jsonb)',
          '893c857e27ec6405a3ac6e291458c346','58f41209f1cedf46198e7c76903f7bbb',
          'Alta Portal catalogada; conserva la autorización de public.crear_contrato y fija la condición en la misma transacción.']
  ];
  v_fila text[]; v_h text; v_hd text; v_com text; v_own text;
  v_verd text; v_n int; v_oid oid;
begin
  foreach v_fila slice 1 in array v_fn loop
    v_oid := to_regprocedure(v_fila[1]);
    if v_oid is null then
      raise exception 'rollback F5.d: % no se recreo', v_fila[1];
    end if;
    select md5(p.prosrc), md5(pg_get_functiondef(p.oid)),
           obj_description(p.oid,'pg_proc'), pg_get_userbyid(p.proowner)
      into v_h, v_hd, v_com, v_own
    from pg_proc p where p.oid = v_oid;

    if v_h is distinct from v_fila[2] then
      raise exception 'rollback F5.d: % no volvio al byte en el CUERPO (huella %)', v_fila[1], v_h;
    end if;
    if v_hd is distinct from v_fila[3] then
      raise exception 'rollback F5.d: % no volvio al byte en la DEFINICION (huella %) — algun atributo derivo', v_fila[1], v_hd;
    end if;
    if v_com is distinct from v_fila[4] then
      raise exception 'rollback F5.d: % no recupero su COMENTARIO (quedo: %)', v_fila[1], coalesce(v_com,'<null>');
    end if;
    if v_own is distinct from 'postgres' then
      raise exception 'rollback F5.d: % quedo con dueño «%»', v_fila[1], v_own;
    end if;

    -- Y CERRADA: recrear una funcion hace que los default privileges le
    -- devuelvan EXECUTE a anon/authenticated/service_role.
    select count(*) into v_n
    from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
    where p.oid = v_oid and a.privilege_type = 'EXECUTE'
      and a.grantee is distinct from p.proowner;
    if v_n > 0 then
      raise exception 'rollback F5.d: % quedo con % concesion(es) EXECUTE fuera del dueño', v_fila[1], v_n;
    end if;
    select count(*) into v_n from unnest(array['anon','authenticated','service_role']) as r(rol)
     where has_function_privilege(r.rol, v_oid, 'EXECUTE');
    if v_n > 0 then
      raise exception 'rollback F5.d: % conserva privilegio EFECTIVO para % rol(es) de la API', v_fila[1], v_n;
    end if;
  end loop;

  -- El libro devolvio LAS SIETE FIRMAS EXACTAS a observacion. Contar 7 filas de
  -- la ola no basta: una cohorte sustituida cumple el conteo con el conjunto
  -- equivocado, y esto es una marcha atras de emergencia — el peor momento para
  -- enterarse. (Lo pidio Codex en la 2.ª vuelta.)
  select count(*) into v_n
  from unnest(array[
    'crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)',
    'crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)',
    'crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb)',
    'crm.crear_contrato_producto(uuid,jsonb,jsonb)',
    'public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)',
    'public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)',
    'public.crear_contrato_producto(uuid,jsonb,jsonb)']) as f(firma)
  where not exists (
    select 1 from private.f7_piezas_en_observacion l
     where l.firma = f.firma and l.ola = 'F5.d' and l.estado = 'observacion');
  if v_n > 0 then
    raise exception 'rollback F5.d: % de las 7 firmas NO volvieron a observacion', v_n;
  end if;
  -- Y la cohorte no tiene filas de mas ni ninguna demolida.
  select count(*) into v_n from private.f7_piezas_en_observacion
   where ola = 'F5.d' and estado = 'demolida';
  if v_n <> 0 then
    raise exception 'rollback F5.d: quedan % gemelas marcadas demolidas', v_n;
  end if;
  select count(*) into v_n from private.f7_piezas_en_observacion where ola = 'F5.d';
  if v_n <> 7 then
    raise exception 'rollback F5.d: la cohorte F5.d tiene % filas, esperaba exactamente 7', v_n;
  end if;

  select private.assert_f7_piezas_cerradas() into v_verd;
  if v_verd not like 'OK%' then raise exception 'rollback F5.d: vigilante F7 en rojo: %', v_verd; end if;
  select private.assert_analitica_leads_citas() into v_verd;
  if v_verd not like 'OK%' then raise exception 'rollback F5.d: analitica en rojo: %', v_verd; end if;
end $rb_post$;

select 'ROLLBACK-F5.d-OK: las 7 piezas recreadas al byte y cerradas como estaban' as resultado;
commit;
