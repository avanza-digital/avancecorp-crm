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

-- Verificacion: volvieron las 7, AL BYTE, y los guardianes quedan verdes.
do $rb_post$
declare
  v_fn constant text[][] := array[
    array['crm.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)', '8640b1246f620ab40558cec2875ada23'],
    array['crm.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)', '4156191492c25479be73b0365263d946'],
    array['crm.crear_contrato_con_cuenta_producto(uuid,jsonb,jsonb,jsonb)', '06f79b07b4d65dcf50cd4359fb598723'],
    array['crm.crear_contrato_producto(uuid,jsonb,jsonb)', '1148d0ca1beb33797995eeff3c579bd4'],
    array['public.actualizar_contrato_con_cuenta_producto(uuid,uuid,jsonb,jsonb)', 'b7e0de18b559ec7fd650619cd22b9cb5'],
    array['public.actualizar_contrato_producto(uuid,uuid,jsonb,jsonb)', 'f0e519cc4ee79c9334ae59a23844b23b'],
    array['public.crear_contrato_producto(uuid,jsonb,jsonb)', '893c857e27ec6405a3ac6e291458c346']
  ];
  v_fila text[]; v_h text; v_verd text;
begin
  foreach v_fila slice 1 in array v_fn loop
    select md5(p.prosrc) into v_h from pg_proc p where p.oid = v_fila[1]::regprocedure;
    if v_h is distinct from v_fila[2] then
      raise exception 'rollback F5.d: % no volvio al byte (huella %)', v_fila[1], v_h;
    end if;
  end loop;
  select private.assert_f7_piezas_cerradas() into v_verd;
  if v_verd not like 'OK%' then raise exception 'rollback F5.d: vigilante F7 en rojo: %', v_verd; end if;
  select private.assert_analitica_leads_citas() into v_verd;
  if v_verd not like 'OK%' then raise exception 'rollback F5.d: analitica en rojo: %', v_verd; end if;
end $rb_post$;

select 'ROLLBACK-F5.d-OK: las 7 piezas recreadas al byte y cerradas como estaban' as resultado;
commit;
