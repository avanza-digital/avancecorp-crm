-- P-055 Fase 5.c - LA REGLA DE VENTAS, EN EL NUCLEO DEL DINERO.
--
-- DECISION DE MIGUEL (30/08, Opcion B): "cualquier analista puede registrar una
-- venta a nombre de cualquier cliente; la venta le cuenta a quien la cierra".
-- Se suelta el SCOPE DE CARTERA en el camino REAL que usa la pantalla de
-- contratos (crear/actualizar_contrato_con_cuenta_pdf_v2/v3 -> estos 4 nucleos),
-- que hasta hoy gateaban por P04 (`puede_gestionar_cuentas_cliente`, por cliente).
--
-- ASI LA PREGUNTA ES UNA SOLA: las 7 gemelas (F5.b) y el nucleo del dinero
-- preguntan lo MISMO -`private.puede_registrar_ventas()`-.
--
-- DOS CUIDADOS QUE OBLIGARON LAS AUDITORIAS PREVIAS Y LA MEDICION:
--  1) La pregunta se AMPLIA para no denegar a nadie que HOY pueda crear: el
--     nucleo admitia es_analista (portal) OR gestor OR gerencia OR catalogado.
--     `puede_registrar_ventas` sumaba admin + miembro CRM pero NO el analista
--     de portal sin ficha. Se le anade `es_analista_vigente()` (analista del
--     Portal Y no revocado; asi no nace en el censo de la F5.a) - prevalencia
--     P04 / F5.a. Operaciones-a-secas queda fuera
--     -no es "equipo comercial" de la decision D1; 0 usuarios hoy-.
--  2) P04 tambien validaba que EL CLIENTE EXISTA Y ESTE ACTIVO (cli.activo=true).
--     Se conserva ese candado ENTERO: en `crear_contrato` se ENDURECE el for-share
--     a `rol = 'cliente' and p.activo` (antes solo miraba el rol) para que un
--     cliente dado de baja no reciba contratos nuevos; en las variantes _con_cuenta
--     el alta delega en ese mismo nucleo. En la EDICION no se exige activo (corregir
--     el contrato historico de un cliente de baja es coherente). Aqui se cambia la
--     AUTORIDAD (se suelta la cartera) SIN perder la validez del cliente.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- =====================================================================
-- 0) PREFLIGHT por huella cruda (30/08).
-- =====================================================================
do $$
declare
  v_fn constant text[][] := array[
    array['private.puede_registrar_ventas()',                        'PENDIENTE'],
    array['public.crear_contrato(jsonb,jsonb)',                      'cf5ef9458610b8d74b9a501d9b69835f'],
    array['public.actualizar_contrato(uuid,jsonb,jsonb)',            'e3f2758b3149a69d9cac695397599c33'],
    array['crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)',        '03993a1bf97f921f22a0cb171fdd878b'],
    array['crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb)',    '71d710b60975b19aa76aa7e76a481c29']
  ];
  v_fila text[]; v_h text;
begin
  foreach v_fila slice 1 in array v_fn loop
    if v_fila[2] = 'PENDIENTE' then continue; end if;
    select md5(p.prosrc) into v_h from pg_proc p where p.oid = v_fila[1]::regprocedure;
    if v_h is distinct from v_fila[2] then
      raise exception 'F5.c preflight: % cambio (huella %)', v_fila[1], v_h;
    end if;
  end loop;
end $$;

-- =====================================================================
-- 1) LA PREGUNTA, AMPLIADA (no deniega a nadie que hoy pueda crear).
-- =====================================================================
create or replace function private.puede_registrar_ventas()
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  -- D1 (Opcion B): quien puede registrar/editar una venta, SIN scope de cartera.
  -- Union de los roles que el nucleo del dinero admitia, menos el revocado.
  select (select auth.uid()) is not null
     and not private.membresia_crm_revocada()
     and (
       public.es_admin()                       -- administracion del Portal
       or private.es_analista_vigente()         -- analista del Portal (con o sin ficha CRM) y NO revocado
       or private.puede_gestionar_contratos_crm() -- miembro activo del CRM (vendedor/supervisor/gerencia)
     );
  -- NOTA F5.a: se pregunta es_analista_VIGENTE (no es_analista a secas) para no
  -- nacer como "puerta del rol del Portal sin vigencia" en el censo. Semantica
  -- identica: el `not membresia_crm_revocada()` de arriba ya cubre las tres ramas.
$function$;
comment on function private.puede_registrar_ventas() is
  'P-055 F5.b/F5.c. LA pregunta unica de "registrar/editar una venta": admin del Portal O analista del Portal O miembro activo del CRM, y NUNCA revocado. Sin scope de cartera (decision B de Miguel: cualquier analista, cualquier cliente; la venta cuenta a quien la cierra, campo analista_cierre de la F3).';
revoke all on function private.puede_registrar_ventas() from public;

-- =====================================================================
-- 2) LOS 4 NUCLEOS DEL DINERO PREGUNTAN LO MISMO (solo la AUTORIDAD;
--    la validez del cliente se conserva - INCLUIDO el "cliente ACTIVO").
-- =====================================================================
-- Cada nucleo lleva una lista PLANA de pares [ancla, reemplazo]: se leen del
-- cuerpo vivo por identidad, cada ancla debe aparecer EXACTAMENTE una vez y se
-- aplican en orden sobre la MISMA definicion antes de re-crearla.
do $$
declare
  v_fn text; v_pares text[]; v_def text; v_veces integer; i integer;
begin
  for v_fn, v_pares in
    select * from (values
      -- public.crear_contrato: (a) se reemplaza el bloque de roles + P04 por la
      -- pregunta unica; (b) el candado "cliente existe" se ENDURECE a "cliente
      -- existe Y ACTIVO" - P04 exigia cli.activo=true y el for-share solo miraba
      -- el rol; sin esto se podria crear un contrato de dinero para un cliente
      -- dado de baja (soft-delete). "Cualquier cliente" (decision B) es cualquier
      -- cliente ACTIVO, no uno inactivo.
      ('public.crear_contrato(jsonb,jsonb)'::text, array[
        '(
    v_es_analista or v_es_gestor_cartera or v_es_gerencia_crm or v_es_crm_catalogado
  ) or not private.puede_gestionar_cuentas_cliente(v_cliente_id)',
        '(select private.puede_registrar_ventas())',
        'where p.id = v_cliente_id and p.rol = ''cliente''',
        'where p.id = v_cliente_id and p.rol = ''cliente'' and p.activo'
      ]),
      -- public.actualizar_contrato: la rama de correccion del analista - se
      -- conserva "solo lo que tu creaste" y la ventana de 5h; se cambia el
      -- candado de cartera. La edicion de contratos historicos de un cliente
      -- dado de baja es coherente con la rama admin/gestor, asi que aqui NO se
      -- exige activo.
      ('public.actualizar_contrato(uuid,jsonb,jsonb)'::text, array[
        'not private.puede_gestionar_cuentas_cliente(v_row.cliente_id)',
        'not (select private.puede_registrar_ventas())'
      ]),
      -- crm.crear_contrato_con_cuenta: pre-gate; el cliente (existe Y activo) lo
      -- valida el nucleo crear_contrato al que delega, con rollback atomico.
      ('crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)'::text, array[
        'v_uid is null or not private.puede_gestionar_cuentas_cliente(v_cliente_id)',
        'not (select private.puede_registrar_ventas())'
      ]),
      -- crm.actualizar_contrato_con_cuenta: se conserva el "not found" del contrato.
      ('crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb)'::text, array[
        'not found or not private.puede_gestionar_cuentas_cliente(v_cliente_id)',
        'not found or not (select private.puede_registrar_ventas())'
      ])
    ) as t(fn, pares)
  loop
    select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.oid = v_fn::regprocedure;
    i := 1;
    while i < array_length(v_pares, 1) loop
      v_veces := (length(v_def) - length(replace(v_def, v_pares[i], ''))) / length(v_pares[i]);
      if v_veces <> 1 then
        raise exception 'F5.c: el ancla #% de % aparece % veces', (i + 1) / 2, v_fn, v_veces;
      end if;
      v_def := replace(v_def, v_pares[i], v_pares[i + 1]);
      i := i + 2;
    end loop;
    execute v_def;
  end loop;
end $$;

-- =====================================================================
-- 2.5) RE-FIJAR LAS HUELLAS DEL TRINQUETE DE VIGENCIA (F5.a).
-- =====================================================================
-- crear_contrato y actualizar_contrato SIGUEN nombrando es_analista() en su
-- DECLARE (linea muerta tras el cambio de gate), por eso siguen en el censo de
-- la F5.a y necesitan su exencion. Pero su CUERPO cambio en F5.c -> su huella
-- (sin comentarios, misma normalizacion que el censo) cambio -> hay que re-fijar
-- la exencion o el trinquete queda caduco y el gate revienta (leccion F1.6).
-- La razon sigue en pie: ambas gatean ahora por puede_registrar_ventas(), que
-- exige NO estar revocado (la misma garantia que P04 daba via membresia).
do $$
declare v_obj text; v_h text;
begin
  foreach v_obj in array array[
    'public.crear_contrato(jsonb,jsonb)',
    'public.actualizar_contrato(uuid,jsonb,jsonb)'
  ] loop
    select md5(regexp_replace(regexp_replace(p.prosrc, '--[^\n]*', ' ', 'g'), '/\*.*?\*/', ' ', 'g'))
      into v_h
      from pg_proc p where p.oid = v_obj::regprocedure;
    update private.analista_vigencia_exenciones
       set huella = v_h,
           razon = 'P-055 F5.c: gatea por private.puede_registrar_ventas(), que exige NO estar revocado (la misma garantia que P04 daba via membresia). Sigue nombrando es_analista() en el DECLARE (linea muerta), por eso permanece en el censo y exenta; huella re-fijada al cuerpo de F5.c.'
     where objeto = v_obj;
    if not found then
      raise exception 'F5.c: no existe la exencion de vigencia de % que re-fijar', v_obj;
    end if;
  end loop;
end $$;

-- =====================================================================
-- 3) POSTFLIGHT.
-- =====================================================================
do $$
declare v_n integer;
begin
  -- Los 4 nucleos ya no gatean por P04-cartera para la AUTORIDAD (la palabra
  -- puede_gestionar_cuentas_cliente desaparece de estos 4; P04 sigue viva para
  -- cuentas bancarias, PDF, domicilio - esas SI conservan la cartera).
  select count(*) into v_n from pg_proc p
   where p.oid in ('public.crear_contrato(jsonb,jsonb)'::regprocedure,
                   'public.actualizar_contrato(uuid,jsonb,jsonb)'::regprocedure,
                   'crm.crear_contrato_con_cuenta(jsonb,jsonb,jsonb)'::regprocedure,
                   'crm.actualizar_contrato_con_cuenta(uuid,jsonb,jsonb)'::regprocedure)
     and strpos(p.prosrc, 'puede_registrar_ventas') > 0
     and strpos(p.prosrc, 'puede_gestionar_cuentas_cliente') = 0;
  if v_n <> 4 then
    raise exception 'F5.c postflight: solo % de 4 nucleos quedaron unificados', v_n;
  end if;

  -- La pregunta amplia incluye al analista (via es_analista_vigente) y excluye
  -- al revocado. Se pregunta la VIGENTE para no nacer en el censo de la F5.a.
  if not exists (select 1 from pg_proc p
    where p.oid = 'private.puede_registrar_ventas()'::regprocedure
      and p.prosrc ~ 'es_analista_vigente' and p.prosrc ~ 'membresia_crm_revocada') then
    raise exception 'F5.c postflight: la pregunta no quedo ampliada (falta es_analista_vigente o el no-revocado)';
  end if;

  -- El cliente-existe-Y-ACTIVO sobrevive en crear_contrato (for share + activo +
  -- not found). El `and p.activo` es el candado que P04 daba y que aqui se
  -- conserva explicitamente.
  if not exists (select 1 from pg_proc p
    where p.oid = 'public.crear_contrato(jsonb,jsonb)'::regprocedure
      and p.prosrc ~ 'for share' and p.prosrc ~ 'Cliente no encontrado'
      and p.prosrc ~ 'rol = ''cliente'' and p.activo') then
    raise exception 'F5.c postflight: crear_contrato perdio el candado de cliente-existe-y-activo';
  end if;

  -- Y las gemelas de la F5.b siguen preguntando lo mismo (coherencia total).
  select count(*) into v_n from pg_proc p
   where p.oid in ('public.crear_contrato_producto(uuid,jsonb,jsonb)'::regprocedure,
                   'crm.crear_contrato_producto(uuid,jsonb,jsonb)'::regprocedure)
     and strpos(p.prosrc, 'puede_registrar_ventas') > 0;
  if v_n <> 2 then
    raise exception 'F5.c postflight: las gemelas de la F5.b se desincronizaron';
  end if;

  -- LECCION F1.6: no se puede cambiar el cuerpo de un nucleo y dejar el gate de
  -- vigencia (F5.a) caduco pero el commit verde. Se corre el trinquete AQUI, en
  -- la misma transaccion: si una exencion quedo con la huella vieja, revienta y
  -- deshace todo. Igual el de analitica de leads/citas (F6), por higiene.
  perform private.assert_analista_vigencia();
  perform private.assert_analitica_leads_citas();
end $$;

commit;
