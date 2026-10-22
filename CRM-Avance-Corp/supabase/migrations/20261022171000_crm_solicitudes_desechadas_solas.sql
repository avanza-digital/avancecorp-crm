-- 20261022171000_crm_solicitudes_desechadas_solas.sql — bloque 2.15 del plan «Mantenibilidad y consistencia del backend CRM» (fecha de trabajo 20261010000200_crm_solicitudes_desechadas_solas.sql; integrado el 2026/10/22, C2 del grupo C)
-- EL CRM CANCELA SOLO LAS SOLICITUDES DE INVERSIÓN QUE YA NO CORRESPONDEN — bloque 2.15 del plan de mantenibilidad del backend
-- (AVANCE-BACKEND-0810-F2). Orden de Miguel D-58 («hagamos que el sistema pueda solo desechar solicitudes que ya no corresponden»,
-- 09/10/2026), con D-59 (los dos casos), D-63 (30 días) y el plan corto aprobado en D-66; decisiones de la ronda 2 (10/10/2026):
-- D-74 (la preparada SIN número también se desecha a los 30 días: D-63 manda sobre D-56), D-75 (NO se toca `public`: a los
-- contratos del Portal los cubre la pasada nocturna), D-76 (nunca se toca sola una solicitud con `auth_claim_id`) y D-77 (pasada
-- nocturna «número usado» como red; las reinversiones que la continuidad rechaza quedan preparadas e informadas; 02:17 Lima).
-- Antecedente: la lectura de producción F4.7 del 09/10 (`fase-4/F4.7/RESULTADOS-0910-2215.md`, `solicitudes-numero-repetido.sql`)
-- y las 6 solicitudes canceladas a mano (D-58, como D-19).
--
-- QUÉ PASABA (medido en producción, solo lectura, 09/10). Una solicitud de inversión preparada de Avance crea su contrato al
-- confirmarse (`crm.confirmar_inversion_revisada_fn` → `crm.crear_contrato_con_cuenta_pdf_v2` → … → `public.crear_contrato`)
-- con el número de `datos.contrato.numero_contrato`. Si mientras tanto ese número lo tomó OTRO contrato, la solicitud ya no se
-- puede confirmar nunca («El N de contrato … ya existe», P0001; el UNIQUE `contratos_numero_contrato_key` lo garantiza) y se
-- queda «preparada» para siempre: había 6. El producto retira una solicitud CANCELÁNDOLA (`crm.cancelar_solicitud_inversion_fn`:
-- `estado = 'cancelada'`, `actualizado_en`; nunca se borra; guardas: sin acceso Avance pendiente —`auth_claim_id`—, sin
-- inversión, no confirmada).
--
-- DÓNDE NACEN LOS CONTRATOS (medido en el catálogo del laboratorio = producción, 10/10/2026): todas las vías llegan a
-- `public.crear_contrato(jsonb,jsonb)` (EXECUTE para `authenticated` y `service_role`): (1) el CRM, por su ÚNICA puerta viva
-- de alta `crm.crear_contrato_con_cuenta_pdf_v2` (EXECUTE para `authenticated`; la llaman la pantalla «Contrato nuevo» y
-- `crm.confirmar_inversion_revisada_fn`), que baja por `crm.crear_contrato_con_cuenta` (EXECUTE solo para el dueño; F7 cerrada
-- permanente, su único llamador permitido es la puerta v2); (2) el Portal, con la llamada DIRECTA a `public.crear_contrato`; (3)
-- `public.crear_contrato_producto` y `crm.crear_contrato_con_cuenta_producto` (F7 en observación, sin EXECUTE de la API, sin
-- llamadores vivos). Esta migración engancha en `crm` (la vía 1) y NO toca `public`: la vía 2 solo podría cubrirse al instante
-- desde `public` (un disparador sobre `public.contratos` o un parche en `public.crear_contrato`), que exige el OK explícito de
-- Miguel (D-11); Miguel decidió NO tocar `public` (D-75, 10/10/2026): a los contratos del Portal los cubre la tarea nocturna
-- (abajo), con un día de retraso como máximo. LÍMITE documentado: entre un alta por el Portal y la pasada de las 02:17 Lima la
-- solicitud sigue «preparada»; si alguien intenta confirmarla en ese lapso, el UNIQUE la rechaza como hoy («El N de contrato …
-- ya existe») y la pasada nocturna la desecha después con su motivo.
--
-- QUÉ HACE.
--   · Dos columnas en `crm.inversion_solicitudes`: `cancelacion_motivo` (`numero_contrato_usado` | `sin_movimiento`; NULL en las
--     cancelaciones de siempre, las de la pantalla) y `cancelacion_detalle` (objeto: con cuál contrato —id y número—, por qué vía
--     —`alta` o `tarea`—, la corrida, los días y el último movimiento, cuándo). Un CHECK ata el motivo al estado `cancelada`.
--     La tabla no tiene grants para la API (se lee por sus puertas): no hay grants que tocar. El auditor de la tabla
--     (`private.log_audit_sin_secretos`) conserva, como siempre, el antes y el después.
--   · Pieza del núcleo `private.solicitud_desechar(uuid, text, jsonb) → text`: el ÚNICO escritor de la cancelación automática.
--     Toma la fila con `FOR UPDATE SKIP LOCKED` (no espera por esa fila: si otra sesión la está confirmando, corrigiendo o
--     cancelando, la deja para la próxima pasada) y relee bajo el candado las MISMAS guardas que `crm.cancelar_solicitud_inversion_fn`
--     (D-19, D-58): sigue preparada, sin acceso Avance pendiente (`auth_claim_id`), sin inversión y sin haber creado su
--     contrato (sin fila en `private.contrato_altas_idempotentes` con su id como clave), Y EL MOTIVO (auditor r1, P2; ronda 3):
--     para `numero_contrato_usado`, que el número actual de la solicitud siga siendo exactamente el del detalle; para
--     `sin_movimiento`, que `actualizado_en` siga siendo el último movimiento observado y ≤ corte − días. Las candidatas se
--     eligen en una consulta y la fila puede haber sido corregida antes de tomar el candado (`corregir_solicitud_inversion_fn`
--     cambia el número y mueve `actualizado_en`): si el motivo ya no es cierto, `omitida: …` y la fila no se toca (sin detalle
--     suficiente también se omite: fail-closed). Y EL CONTRATO (Codex r1, P2-1; ronda 4): para `numero_contrato_usado`, el
--     contrato del detalle tiene que existir y seguir con ese número, leído bajo `FOR KEY SHARE SKIP LOCKED` (una eliminación
--     o renumeración en curso no se espera: `omitida`; una posterior espera a que esta cancelación confirme). Si pasa, `estado = 'cancelada'`,
--     `actualizado_en`, motivo y detalle; el UPDATE va en su propia subtransacción: si un disparador de la tabla se niega
--     (p. ej. la continuidad de una reinversión), la solicitud queda como estaba y la pieza lo dice («rechazada: …») en vez de
--     tumbar a quien la llamó. Devuelve `cancelada`, `omitida: <guarda>` o `rechazada: <SQLSTATE> <mensaje>`.
--   · Pieza `private.solicitudes_desechar_por_contrato(uuid) → jsonb` (CASO 1, al instante): dado el contrato recién nacido,
--     cancela las solicitudes PREPARADAS de las empresas que crean contrato Avance (`crm.empresas.crea_contrato_avance`) cuyo
--     `datos.contrato.numero_contrato` recortado es su número y que NO son la que lo creó (la clave de idempotencia del alta,
--     en `private.contrato_altas_idempotentes`, es el id de la solicitud que confirma: `crm.confirmar_inversion_revisada_fn`
--     manda `'clave_idempotencia', v_s.id`). Motivo `numero_contrato_usado`, detalle con el contrato y la vía `alta`.
--   · Re-emite `crm.crear_contrato_con_cuenta_pdf_v2` con UN cambio por ancla única: tras guardar la memoria de idempotencia
--     del alta (ya existe la fila que identifica a la creadora) y antes del `return`, llama a esa pieza. La rama idempotente
--     (un reintento devuelve el mismo contrato) no pasa por ahí: no nace ningún contrato. El rechazo de un disparador al
--     cancelar queda aislado en la subtransacción de la pieza y no tumba el alta (las consultas previas y un `query_canceled`
--     no están cubiertos por ella).
--   · Pieza `private.solicitudes_desechar_ciclo(timestamptz, integer, integer) → jsonb` (CASO 2, cada noche): dos pasadas,
--     con un presupuesto ÚNICO de `p_limite` (200) CANCELACIONES por corrida (Codex r1, P2-2: las omitidas y rechazadas no lo
--     consumen y las exclusiones permanentes se descartan antes del recorrido, P2-3), de la más antigua a la más nueva, sin
--     esperar por filas ocupadas: PRIMERO las
--     preparadas de Avance cuyo número ya lo usa un contrato que no creó esa solicitud (la misma regla del caso 1, como red para
--     los contratos nacidos fuera del CRM: Portal), DESPUÉS las preparadas de cualquier empresa que llevan `p_dias` (30, D-63)
--     días o más sin confirmarse ni corregirse (`actualizado_en <= corte − 30 días`), motivo `sin_movimiento`. Deja rastro de
--     cuántas canceló, omitió y rechazó en `crm.solicitudes_desechadas_corridas` (una fila por corrida, con el detalle por
--     solicitud) y lo devuelve. Idempotente: repetirla no cancela nada más y deja otra fila de corrida.
--   · Tabla `crm.solicitudes_desechadas_corridas` (RLS, sin grants para la API, auditor `private.log_audit_crm`): el rastro de
--     cada corrida. Sin columna de empresa: CRM de una sola empresa (misma excepción documentada que `crm.llamadas_celular_politica`).
--   · pg_cron `crm-solicitudes-desechar` a las 07:17 UTC (02:17 Lima) todos los días: `select private.solicitudes_desechar_ciclo()`
--     (como `postgres`, BYPASSRLS; sin EXECUTE para la API). El reloj es OBLIGATORIO (Codex r1, P2-6): sin pg_cron la migración
--     se niega; solo un banco de laboratorio sin reloj puede seguir, con la marca `crm.laboratorio_sin_cron = 1` que pone el
--     armador del ensayo (`--sin-cron`), nunca una migración ni la app. La marca es una EXCEPCIÓN OPERATIVA explícita, no una
--     frontera de permisos (cualquier sesión puede ponerla): con pg_cron presente y la marca puesta la migración se niega, y el
--     ejecutor real comprueba antes de aplicar que no hay marca y sí reloj (runbook; Codex r2, ronda 5).
--   · Pieza `private.solicitud_cancelacion_vista(uuid) → jsonb` (STABLE) y re-emisión de `crm.solicitud_inversion_fn` por ancla
--     única: la consulta de una solicitud devuelve además `cancelacion_motivo`, `cancelacion_detalle` —sin `contrato_id`: el UUID
--     de un contrato ajeno no sale a la API; queda en la fila y en `public.audit_log` (Codex r1, ronda 4)— y `cancelacion_texto` (el
--     texto que ve el asesor: «El CRM canceló esta solicitud: el número de contrato N ya lo usa otro contrato.» / «… llevaba 30
--     días sin confirmarse ni corregirse.»; nulos si no la canceló el CRM). La app valida con `v.object` (no estricto): una app
--     anterior ignora las claves; la nueva las muestra en «Solicitud cancelada». Sin orden de despliegue.
--
-- QUÉ NO CAMBIA. `crm.cancelar_solicitud_inversion_fn` (la cancelación de la pantalla), `crm.confirmar_inversion_revisada_fn`,
-- `crm.corregir_solicitud_inversion_fn` y `private.inversion_solicitud_resultado` no se tocan (se fijan por huella y ficha en el
-- preflight y se exigen intactas en el postflight: las guardas y la clave de idempotencia de las que depende esta regla viven
-- ahí). No se toca `public` (ni `public.crear_contrato`, ni `public.contratos`), ni policies, ni grants de tablas. No se borra
-- ninguna fila, nunca. No se cancela por «la persona ya tiene esa inversión» (D-59 no lo eligió). Una solicitud con acceso
-- Avance reservado (`auth_claim_id` no nulo) NUNCA se toca por esta vía, ni siquiera si su acceso ya quedó enlazado ni a los
-- 30 días: la cancelación de la pantalla sigue siendo el camino para esas (D-76). La preparada SIN número de contrato no es un
-- caso aparte: a los 30 días sin confirmarse ni corregirse se desecha como las demás (D-74: D-63 manda sobre D-56). Una
-- reinversión o upgrade cuya continuidad de postventa (`trg_solicitudes_zz_postventa`) se niega a cancelar queda preparada y
-- la corrida la informa como «rechazada» para que una persona decida (D-77).
--
-- CONCURRENCIA. Dos altas con el mismo número: el UNIQUE de `public.contratos.numero_contrato` deja nacer solo a una; la otra
-- muere con «El N de contrato … ya existe» y todo lo suyo (cancelaciones incluidas) se deshace. La solicitud que otra sesión
-- está confirmando (FOR UPDATE en `confirmar`) no se espera (SKIP LOCKED): si esa confirmación muere por el número repetido, la
-- recoge la tarea nocturna. Una corrección entre la consulta de candidatas y el candado la detecta la relectura del motivo
-- (ronda 3); un contrato eliminado o renumerado entre medias, la relectura del contrato bajo KEY SHARE SKIP LOCKED (ronda 4).
-- La pieza no espera por la solicitud ni por el contrato; lo que SÍ puede esperar son los disparadores de la tabla con sus
-- propios candados (la continuidad de postventa toma `for share nowait` sobre el cierre de origen y convierte la espera en
-- 40001 ⇒ «rechazada»), acotado por `lock_timeout` (10 s en la tarea, 5 s en el alta).
--
-- FAIL-CLOSED. El preflight exige, antes de tocar nada: las dos puertas que se re-emiten con la huella (`md5(prosrc)` y
-- `md5(pg_get_functiondef)`), la ficha (dueño `postgres`, DEFINER, volatilidad, modo paralelo, `proconfig`, ACL con opción de
-- concesión) y el comentario auditados, y el ancla EXACTAMENTE una vez (si ya está la llamada, la migración ya está aplicada y
-- se niega); las cuatro funciones de las que la regla da por sabido su comportamiento (cancelar, confirmar —con la clave de
-- idempotencia en su texto—, corregir y el resultado público) con huella y ficha; la forma de `crm.inversion_solicitudes`
-- (dueño, RLS, sin ACL, columnas, CHECK de estado, auditor exacto y HABILITADO, disparador de postventa fijado con su guarda y la
-- continuidad por huella —Codex r1, P2-4—), de `private.contrato_altas_idempotentes`
-- (PK actor+clave, FK al contrato con SET NULL), de `public.contratos` (UNIQUE del número) y de `crm.empresas`
-- (`crea_contrato_avance`); que no existan las columnas, la tabla, ninguna función `private` con los nombres nuevos ni el job;
-- el reloj OBLIGATORIO (pg_cron presente salvo la marca de laboratorio; usuario `postgres` con BYPASSRLS, `cron.timezone` GMT); y la FOTO de los `private.assert_*()` sin
-- argumentos y sin los `*_mutantes` (estado, o SQLSTATE y texto íntegro del primer error). POSTFLIGHT: las dos puertas con la
-- huella exacta ensayada, la ficha idéntica a la previa (y sin EXECUTE para `anon` ni `service_role`: P3 del auditor r1) y su
-- comentario; las cuatro piezas con su ficha (dueño `postgres`,
-- INVOKER, `search_path` vacío, EXECUTE solo el dueño, volatilidad); columnas, CHECK, tabla (RLS, sin grants, auditor completo:
-- `private.tablas_sin_rastro()` no la lista); el job activo con su comando; lo que no se toca, intacto; una SONDA que se
-- deshace (la tarea y la pieza del alta ejecutadas de verdad dentro de una subtransacción que siempre se revierte: nada queda
-- cancelado ni anotado al aplicar); y la foto de los `assert_*` idéntica.
--
-- VERIFICACIÓN: `supabase/scripts/solicitudes-desechadas-solas/` (ROJO sin la migración; VERDE con ella; mutantes, derivas,
-- reversa, trinquetes). Verificada solo en el laboratorio local. REVERSA: `supabase/scripts/solicitudes-desechadas-solas/reversa.sql`
-- (falla cerrada; repone las dos puertas byte a byte y sus comentarios, quita las piezas, el job, la tabla y las columnas; las
-- cancelaciones ya hechas se CONSERVAN —son estado de negocio— y sus motivos quedan en `public.audit_log`).
-- RESELLE C2 (22/10/2026, plan AVANCE-BACKEND-1310-C2): crm.confirmar_inversion_revisada_fn se fija por su huella de producción del 22/10 (cuerpo ef53419d…, definición 33af606a…; antes 5a4693a2…/68828d0a…: 20261019001700 «recorrido» le añadió private.recorrido_exigir(…,'confirmar_inversion') antes de los hechos financieros; la clave de idempotencia = id de la solicitud, lo único que esta regla da por sabido de ella, sigue igual), en preflight y postflight; regla, mensajes y candados sin cambio.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

-- ── 0 · Preflight (fail-closed) ──────────────────────────────────────────────────────────────────────────────────────────────
do $preflight$
declare
  v_h record;
  v_ficha text;
  v_def text;
  v_foto text := '';
  v text;
  r record;
begin
  -- 0.1 Las dos puertas que se re-emiten: huella, ficha, comentario y ancla única.
  if to_regprocedure('crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)') is null
     or to_regprocedure('crm.solicitud_inversion_fn(uuid)') is null then
    raise exception 'PREFLIGHT solicitudes_desechadas_solas: falta crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb) o crm.solicitud_inversion_fn(uuid)';
  end if;
  for v_h in
    select * from (values
      ('crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)', '505598d6fef7ea585a965f925a8eb9fb', 'd0b33d8fb1d27ef2da62105b7ccabd88',
       'postgres|true|v|u|search_path=""|authenticated:EXECUTE:false,postgres:EXECUTE:false',
       'Alta CRM atómica de contrato, cronograma, cuenta de pago y reserva documental v2.'),
      ('crm.solicitud_inversion_fn(uuid)', '0427b888c4a0c4082831e42244c2e0e1', '1c5867eaed3a1ea89b2b4626e2c9385e',
       'postgres|true|v|u|search_path="";lock_timeout=5s|authenticated:EXECUTE:false,postgres:EXECUTE:false',
       'Consulta una solicitud de inversión. Autoriza con la solicitud como llave: en venta cruzada, su analista y su cadena; en cartera, la regla de siempre.'),
      -- 0.2 Lo que la regla da por sabido y NO toca: la cancelación de la pantalla (sus guardas son las que se reproducen), la
      --     confirmación (manda la clave de idempotencia = id de la solicitud), la corrección (mueve actualizado_en) y la forma
      --     pública de la solicitud (lo que valida la app).
      ('crm.cancelar_solicitud_inversion_fn(uuid,integer)', '5e92b8ef8c54b160578463932c1eca1a', 'f17eac08c7e2bc4e27fad45616458731',
       'postgres|true|v|u|search_path="";lock_timeout=5s|authenticated:EXECUTE:false,postgres:EXECUTE:false',
       'Cancela una solicitud preparada (o devuelve el resultado si ya se confirmó). Autoriza con la solicitud como llave; una venta cruzada la cancela quien la opera.'),
      ('crm.confirmar_inversion_revisada_fn(uuid,integer)', 'ef53419d436583b116ff68e5a1509855', '33af606a814c74de5de8a080430bb299',
       'postgres|true|v|u|search_path="";lock_timeout=5s|authenticated:EXECUTE:false,postgres:EXECUTE:false',
       'Confirma una solicitud y crea su fuente (contrato Avance o cierre cooperativo). En venta cruzada la confirma quien la opera, atribuye al analista congelado, no toca al responsable (D7), exige al analista activo y solo admite nueva o upgrade (D5).'),
      ('crm.corregir_solicitud_inversion_fn(uuid,uuid,integer,jsonb,text)', '3977f1ab0fd4a134c58cf8edd5556ae6', 'c41aa8ee34da4b3f828289058c41e4f4',
       'postgres|true|v|u|search_path="";lock_timeout=5s|authenticated:EXECUTE:false,postgres:EXECUTE:false',
       'Corrige una solicitud preparada. En venta cruzada la corrige quien la opera, no exige que el responsable coincida (D7) y valida el analista contra el congelado.'),
      ('private.inversion_solicitud_resultado(uuid,jsonb)', '26dac93e46ffd7b2b9d12691c7905790', 'cfa456428eeb7fdfe5e50f2a72d0c6aa',
       'postgres|true|s|u|search_path=""|postgres:EXECUTE:false',
       'Forma pública de una solicitud de inversión. En venta cruzada añade puerta y analista_cierre_id y solo pide revisar el responsable si falta el acceso Avance (D7).')
    ) as h(firma, prosrc, def, ficha, comentario)
  loop
    if to_regprocedure(v_h.firma) is null then
      raise exception 'PREFLIGHT solicitudes_desechadas_solas: falta %', v_h.firma;
    end if;
    if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure(v_h.firma)) is distinct from v_h.prosrc
       or md5(pg_get_functiondef(to_regprocedure(v_h.firma))) is distinct from v_h.def then
      raise exception 'PREFLIGHT solicitudes_desechadas_solas: % no es la auditada (cuerpo o definición distintos; o esta migración ya está aplicada): revisar antes de instalar', v_h.firma;
    end if;
    select p.proowner::regrole::text || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || p.proparallel::text
             || '|' || coalesce(array_to_string(p.proconfig, ';'), '-')
             || '|' || coalesce((select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text)
                                   from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a), '-')
      into v_ficha
      from pg_proc p where p.oid = to_regprocedure(v_h.firma);
    if v_ficha is distinct from v_h.ficha then
      raise exception 'PREFLIGHT solicitudes_desechadas_solas: la ficha de % no es la auditada (medida «%»; auditada «%»)', v_h.firma, v_ficha, v_h.ficha;
    end if;
    if obj_description(to_regprocedure(v_h.firma), 'pg_proc') is distinct from v_h.comentario then
      raise exception 'PREFLIGHT solicitudes_desechadas_solas: el comentario de % no es el auditado: revisar antes de instalar', v_h.firma;
    end if;
  end loop;
  v_def := pg_get_functiondef('crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)'::regprocedure);
  if cardinality(string_to_array(v_def, $a$    values (v_actor_id, v_clave, v_contrato_id, v_huella, v_resultado);
  end if;
  return v_resultado;
$a$)) <> 2 then
    raise exception 'PREFLIGHT solicitudes_desechadas_solas: el ancla del alta (la memoria de idempotencia y el return) no aparece exactamente una vez en crm.crear_contrato_con_cuenta_pdf_v2';
  end if;
  v_def := pg_get_functiondef('crm.solicitud_inversion_fn(uuid)'::regprocedure);
  if cardinality(string_to_array(v_def, $a$  return private.inversion_solicitud_resultado(p_solicitud,v_ctx)||jsonb_build_object('datos',v_datos);$a$)) <> 2 then
    raise exception 'PREFLIGHT solicitudes_desechadas_solas: el ancla del return no aparece exactamente una vez en crm.solicitud_inversion_fn';
  end if;
  if position($t$'clave_idempotencia',v_s.id$t$ in (select p.prosrc from pg_proc p where p.oid = 'crm.confirmar_inversion_revisada_fn(uuid,integer)'::regprocedure)) = 0 then
    raise exception 'PREFLIGHT solicitudes_desechadas_solas: crm.confirmar_inversion_revisada_fn ya no manda el id de la solicitud como clave de idempotencia del alta: la exclusión de la solicitud creadora dejaría de valer';
  end if;

  -- 0.3 La forma de las tablas de las que depende la regla.
  if (select c.relowner::regrole::text || '|' || c.relrowsecurity::text || '|' || coalesce(c.relacl::text, '-')
        from pg_class c where c.oid = 'crm.inversion_solicitudes'::regclass) is distinct from 'postgres|true|-' then
    raise exception 'PREFLIGHT solicitudes_desechadas_solas: crm.inversion_solicitudes no tiene la ficha auditada (dueño postgres, RLS activa, sin grants)';
  end if;
  if (select string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod) || ':' || a.attnotnull::text, ',' order by a.attname)
        from pg_attribute a where a.attrelid = 'crm.inversion_solicitudes'::regclass and a.attnum > 0 and not a.attisdropped
         and a.attname in ('id','estado','auth_claim_id','inversion_id','actualizado_en','creado_en','datos','empresa_id','cancelacion_motivo','cancelacion_detalle'))
     is distinct from 'actualizado_en:timestamp with time zone:true,auth_claim_id:uuid:false,creado_en:timestamp with time zone:true,datos:jsonb:true,empresa_id:uuid:true,estado:text:true,id:uuid:true,inversion_id:uuid:false' then
    raise exception 'PREFLIGHT solicitudes_desechadas_solas: las columnas de crm.inversion_solicitudes no son las auditadas (o ya existen cancelacion_motivo/cancelacion_detalle: migración ya aplicada)';
  end if;
  if (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conrelid = 'crm.inversion_solicitudes'::regclass and c.conname = 'inversion_solicitudes_estado_check')
     is distinct from $c$CHECK ((estado = ANY (ARRAY['preparada'::text, 'confirmada'::text, 'cancelada'::text])))$c$ then
    raise exception 'PREFLIGHT solicitudes_desechadas_solas: el CHECK de estado de crm.inversion_solicitudes cambió: revisar qué significa cancelada';
  end if;
  if (select pg_get_triggerdef(t.oid) || '|' || t.tgenabled::text from pg_trigger t where t.tgrelid = 'crm.inversion_solicitudes'::regclass and t.tgname = 'trg_audit_inversion_solicitudes')
     is distinct from $c$CREATE TRIGGER trg_audit_inversion_solicitudes AFTER INSERT OR DELETE OR UPDATE ON crm.inversion_solicitudes FOR EACH ROW EXECUTE FUNCTION private.log_audit_sin_secretos('datos', 'auth_contexto', 'motivo_atribucion')$c$ || '|O' then
    raise exception 'PREFLIGHT solicitudes_desechadas_solas: el auditor de crm.inversion_solicitudes no es el de hoy o está deshabilitado (tgenabled distinto de O): el rastro de la cancelación automática no sería el auditado';
  end if;
  -- La continuidad de postventa (el disparador que puede negarse a cancelar una reinversión), fijada entera: definición del
  -- disparador, habilitado, y huella de su función y de la guarda a la que llama (Codex r1, P2-4; ronda 4).
  if (select pg_get_triggerdef(t.oid) || '|' || t.tgenabled::text from pg_trigger t where t.tgrelid = 'crm.inversion_solicitudes'::regclass and t.tgname = 'trg_solicitudes_zz_postventa')
     is distinct from $c$CREATE TRIGGER trg_solicitudes_zz_postventa BEFORE UPDATE OF datos, estado, inversionista_id, empresa_id ON crm.inversion_solicitudes FOR EACH ROW EXECUTE FUNCTION private.postventa_reinversion_guard()$c$ || '|O' then
    raise exception 'PREFLIGHT solicitudes_desechadas_solas: el disparador trg_solicitudes_zz_postventa no es el auditado o está deshabilitado (la subtransacción de la pieza y la expectativa de las reinversiones existen para él)';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.postventa_reinversion_guard()')) is distinct from '4755f4c8ca3cbaf85aa619141c03a145'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.continuidad_coopac_fuente(uuid,uuid,text,text)')) is distinct from '93f51bbfbcc75a6bec3b972a5900a1ed' then
    raise exception 'PREFLIGHT solicitudes_desechadas_solas: private.postventa_reinversion_guard() o private.continuidad_coopac_fuente(uuid,uuid,text,text) no es la auditada: la regla da por sabido cómo decide la continuidad de postventa (upgrade preparada→cancelada pasa; reinversión sin origen disponible se rechaza)';
  end if;
  -- …y su FICHA (dueño, DEFINER, configuración), que md5(prosrc) no fija (Codex r2, P3; ronda 5): medida en el laboratorio y cotejada
  -- en producción por el Director.
  if (select p.proowner::regrole::text || '|' || p.prosecdef::text || '|' || coalesce(array_to_string(p.proconfig, ';'), '-')
        from pg_proc p where p.oid = to_regprocedure('private.postventa_reinversion_guard()')) is distinct from 'postgres|true|search_path="";lock_timeout=5s'
     or (select p.proowner::regrole::text || '|' || p.prosecdef::text || '|' || coalesce(array_to_string(p.proconfig, ';'), '-')
        from pg_proc p where p.oid = to_regprocedure('private.continuidad_coopac_fuente(uuid,uuid,text,text)')) is distinct from 'postgres|false|search_path=""' then
    raise exception 'PREFLIGHT solicitudes_desechadas_solas: la ficha (dueño, DEFINER, configuración) de private.postventa_reinversion_guard() o de private.continuidad_coopac_fuente(uuid,uuid,text,text) no es la auditada: revisar antes de instalar';
  end if;
  if (select string_agg(c.conname || ':' || pg_get_constraintdef(c.oid), ';' order by c.conname)
        from pg_constraint c where c.conrelid = 'private.contrato_altas_idempotentes'::regclass and c.contype in ('p','f'))
     is distinct from 'contrato_altas_idempotentes_contrato_id_fkey:FOREIGN KEY (contrato_id) REFERENCES contratos(id) ON DELETE SET NULL;contrato_altas_idempotentes_pkey:PRIMARY KEY (actor_id, clave)' then
    raise exception 'PREFLIGHT solicitudes_desechadas_solas: private.contrato_altas_idempotentes no tiene la forma auditada (PK actor_id+clave, FK al contrato con SET NULL)';
  end if;
  if (select string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod), ',' order by a.attname)
        from pg_attribute a where a.attrelid = 'private.contrato_altas_idempotentes'::regclass and a.attnum > 0 and not a.attisdropped
         and a.attname in ('actor_id','clave','contrato_id'))
     is distinct from 'actor_id:uuid,clave:uuid,contrato_id:uuid' then
    raise exception 'PREFLIGHT solicitudes_desechadas_solas: las columnas de private.contrato_altas_idempotentes no son las auditadas';
  end if;
  if (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conrelid = 'public.contratos'::regclass and c.conname = 'contratos_numero_contrato_key')
     is distinct from 'UNIQUE (numero_contrato)' then
    raise exception 'PREFLIGHT solicitudes_desechadas_solas: public.contratos ya no tiene el UNIQUE contratos_numero_contrato_key (numero_contrato): sin él, «el número ya lo usa otro contrato» no tiene sentido';
  end if;
  if not exists (select 1 from pg_attribute a where a.attrelid = 'crm.empresas'::regclass and a.attname = 'crea_contrato_avance'
                   and format_type(a.atttypid, a.atttypmod) = 'boolean' and a.attnotnull and not a.attisdropped) then
    raise exception 'PREFLIGHT solicitudes_desechadas_solas: crm.empresas no tiene crea_contrato_avance boolean NOT NULL';
  end if;

  -- 0.4 Nada de lo nuevo existe ya.
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'private'
                and p.proname in ('solicitud_desechar', 'solicitudes_desechar_por_contrato', 'solicitudes_desechar_ciclo', 'solicitud_cancelacion_vista')) then
    raise exception 'PREFLIGHT solicitudes_desechadas_solas: ya existe una función private.solicitud_desechar, private.solicitudes_desechar_por_contrato, private.solicitudes_desechar_ciclo o private.solicitud_cancelacion_vista (con cualquier firma)';
  end if;
  if to_regclass('crm.solicitudes_desechadas_corridas') is not null then
    raise exception 'PREFLIGHT solicitudes_desechadas_solas: ya existe crm.solicitudes_desechadas_corridas';
  end if;

  -- 0.5 El reloj: OBLIGATORIO (Codex r1, P2-6; ronda 4). Sin pg_cron (cron.job y cron.schedule) la tarea nocturna no se puede
  --     programar y la migración se niega; la única excepción es un banco de laboratorio sin reloj, y solo con la marca
  --     explícita crm.laboratorio_sin_cron = 1 (la pone el armador del ensayo con --sin-cron; nunca una migración ni la app).
  --     Con reloj: el job correría como postgres (BYPASSRLS) en GMT, y no existe ya.
  if to_regclass('cron.job') is null or to_regprocedure('cron.schedule(text,text,text)') is null then
    if coalesce(current_setting('crm.laboratorio_sin_cron', true), '') <> '1' then
      raise exception 'PREFLIGHT solicitudes_desechadas_solas: sin pg_cron (cron.job o cron.schedule) la tarea nocturna crm-solicitudes-desechar no se puede programar: la migración se niega (solo un banco de laboratorio sin reloj puede seguir, con la marca crm.laboratorio_sin_cron = 1)';
    end if;
  end if;
  -- La marca es una EXCEPCIÓN OPERATIVA explícita, no una frontera de permisos (cualquier sesión puede ponerla: Codex r2, P3; ronda 5).
  -- Donde hay reloj no hace falta y es sospechosa: con pg_cron presente y la marca puesta, la migración se niega. El residuo (una
  -- base real SIN pg_cron y con una marca ajena ⇒ entra sin job) lo cubre la precondición del ejecutor en el runbook: antes de
  -- aplicar, current_setting('crm.laboratorio_sin_cron', true) vacío o nulo Y to_regclass('cron.job') no nulo.
  if to_regclass('cron.job') is not null and to_regprocedure('cron.schedule(text,text,text)') is not null
     and coalesce(current_setting('crm.laboratorio_sin_cron', true), '') = '1' then
    raise exception 'PREFLIGHT solicitudes_desechadas_solas: la marca crm.laboratorio_sin_cron está puesta y pg_cron está presente: una marca donde no hace falta es sospechosa (es una excepción operativa, no una frontera de permisos); quitarla (RESET) antes de aplicar';
  end if;
  if to_regclass('cron.job') is not null then
    if (current_user = 'postgres'
        and coalesce(current_setting('cron.timezone', true), 'GMT') in ('GMT', 'UTC', 'Etc/UTC')
        and (select ro.rolbypassrls from pg_roles ro where ro.rolname = 'postgres')) is not true then
      raise exception 'PREFLIGHT solicitudes_desechadas_solas: el job quedaría con otro usuario (%), sin BYPASSRLS o con cron.timezone distinto de GMT (%)',
        current_user, current_setting('cron.timezone', true);
    end if;
    if exists (select 1 from cron.job j where j.jobname = 'crm-solicitudes-desechar') then
      raise exception 'PREFLIGHT solicitudes_desechadas_solas: ya existe un job crm-solicitudes-desechar';
    end if;
  end if;

  -- 0.6 Fichas previas de las dos puertas (create or replace conserva dueño y ACL: se exigen idénticas después) y la FOTO de
  --     los private.assert_*() sin argumentos y sin los *_mutantes.
  perform set_config('crm.c215_pdf_v2_ficha_previa',
    (select p.oid::regprocedure::text || '|' || p.proowner::regrole::text || '|' || p.prosecdef::text
        || '|' || coalesce(p.proconfig::text, '-') || '|' || coalesce(p.proacl::text, '-')
        || '|' || p.provolatile::text || '|' || p.proparallel::text || '|' || p.proleakproof::text
        || '|' || p.prorettype::regtype::text
       from pg_proc p where p.oid = 'crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)'::regprocedure), true);
  perform set_config('crm.c215_consulta_ficha_previa',
    (select p.oid::regprocedure::text || '|' || p.proowner::regrole::text || '|' || p.prosecdef::text
        || '|' || coalesce(p.proconfig::text, '-') || '|' || coalesce(p.proacl::text, '-')
        || '|' || p.provolatile::text || '|' || p.proparallel::text || '|' || p.proleakproof::text
        || '|' || p.prorettype::regtype::text
       from pg_proc p where p.oid = 'crm.solicitud_inversion_fn(uuid)'::regprocedure), true);
  for r in
    select p.oid::regprocedure::text as f
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private' and p.proname like 'assert\_%' and p.proname !~ '_mutantes$' and p.pronargs = 0
    order by 1
  loop
    begin
      execute 'select ' || r.f;
      v := 'pasa';
    exception when others then
      v := 'cae: ' || sqlstate || ' ' || sqlerrm;
    end;
    v_foto := v_foto || r.f || ' => ' || v || E'\n';
  end loop;
  perform set_config('crm.c215_trinquetes_previos', v_foto, true);
end
$preflight$;

-- ── 1 · El motivo a la vista: dos columnas en la solicitud ──────────────────────────────────────────────────────────────────
alter table crm.inversion_solicitudes
  add column cancelacion_motivo text,
  add column cancelacion_detalle jsonb;
alter table crm.inversion_solicitudes
  add constraint inversion_solicitud_cancelacion_motivo_valido
    check (cancelacion_motivo is null or cancelacion_motivo in ('numero_contrato_usado', 'sin_movimiento')),
  add constraint inversion_solicitud_cancelacion_coherente
    check ((cancelacion_motivo is null and cancelacion_detalle is null)
        or (estado = 'cancelada' and cancelacion_motivo is not null and cancelacion_detalle is not null
            and jsonb_typeof(cancelacion_detalle) = 'object'));
comment on column crm.inversion_solicitudes.cancelacion_motivo is
  'Por qué la canceló el CRM solo (bloque 2.15; D-58, D-59, D-63): numero_contrato_usado (el número de contrato de la solicitud ya lo usa otro contrato) o sin_movimiento (30 días sin confirmarse ni corregirse). NULL en las cancelaciones de la pantalla (crm.cancelar_solicitud_inversion_fn). Solo con estado = cancelada.';
comment on column crm.inversion_solicitudes.cancelacion_detalle is
  'Detalle de la cancelación automática (objeto): via (alta | tarea), contrato_id y numero_contrato (con cuál), corrida_id (la corrida de la tarea), dias y ultimo_movimiento (sin movimiento), corte, cancelada_en. NULL si no la canceló el CRM.';

-- ── 2 · El rastro de cada corrida nocturna ──────────────────────────────────────────────────────────────────────────────────
create table crm.solicitudes_desechadas_corridas (
  id uuid primary key,
  creado_en timestamptz not null default clock_timestamp(),
  corte timestamptz not null,
  dias integer not null check (dias >= 1),
  limite integer not null check (limite >= 1),
  canceladas_numero_usado integer not null check (canceladas_numero_usado >= 0),
  canceladas_sin_movimiento integer not null check (canceladas_sin_movimiento >= 0),
  omitidas integer not null check (omitidas >= 0),
  rechazadas integer not null check (rechazadas >= 0),
  detalle jsonb not null check (jsonb_typeof(detalle) = 'array'),
  duracion_ms integer not null check (duracion_ms >= 0),
  constraint solicitudes_desechadas_corridas_tiempos_finitos check (isfinite(creado_en) and isfinite(corte))
);
alter table crm.solicitudes_desechadas_corridas owner to postgres; -- de postgres la aplique quien la aplique (el postflight lo exige; ronda 4)
alter table crm.solicitudes_desechadas_corridas enable row level security;
revoke all on table crm.solicitudes_desechadas_corridas from public, anon, authenticated, service_role;
create trigger trg_audit_solicitudes_desechadas_corridas after insert or update or delete on crm.solicitudes_desechadas_corridas
  for each row execute function private.log_audit_crm();
comment on table crm.solicitudes_desechadas_corridas is
  'Rastro de cada corrida de private.solicitudes_desechar_ciclo (bloque 2.15: el CRM cancela solo las solicitudes de inversión que ya no corresponden; D-58, D-59, D-63): cuántas canceló por número de contrato ya usado y por 30 días sin movimiento, cuántas omitió (guardas o fila ocupada) y cuántas rechazó un disparador, con el detalle por solicitud. Append-only; sin grants para la API; sin columna de empresa (CRM de una sola empresa, excepción documentada).';
comment on column crm.solicitudes_desechadas_corridas.id is 'Identificador de la corrida; viaja en cancelacion_detalle.corrida_id de cada solicitud cancelada.';
comment on column crm.solicitudes_desechadas_corridas.creado_en is 'Cuándo terminó la corrida.';
comment on column crm.solicitudes_desechadas_corridas.corte is 'Instante de corte con el que se evaluó «sin movimiento» (p_corte).';
comment on column crm.solicitudes_desechadas_corridas.dias is 'Días sin movimiento exigidos (30, D-63).';
comment on column crm.solicitudes_desechadas_corridas.limite is 'Presupuesto de cancelaciones por corrida (200), compartido por las dos pasadas; las omitidas y rechazadas no lo consumen.';
comment on column crm.solicitudes_desechadas_corridas.canceladas_numero_usado is 'Canceladas por número de contrato ya usado por otro contrato (pasada 1).';
comment on column crm.solicitudes_desechadas_corridas.canceladas_sin_movimiento is 'Canceladas por 30 días sin confirmarse ni corregirse (pasada 2).';
comment on column crm.solicitudes_desechadas_corridas.omitidas is 'Candidatas que no se tocaron: una guarda bajo el candado o fila ocupada por otra sesión.';
comment on column crm.solicitudes_desechadas_corridas.rechazadas is 'Candidatas cuya cancelación rechazó un disparador de la tabla (quedaron como estaban).';
comment on column crm.solicitudes_desechadas_corridas.detalle is 'Lista: por solicitud candidata, su id, el motivo evaluado y el resultado (cancelada | omitida: … | rechazada: …).';
comment on column crm.solicitudes_desechadas_corridas.duracion_ms is 'Duración de la corrida en milisegundos.';

-- ── 3 · Piezas del núcleo ────────────────────────────────────────────────────────────────────────────────────────────────────
-- 3.1 El único escritor de la cancelación automática.
create function private.solicitud_desechar(p_solicitud uuid, p_motivo text, p_detalle jsonb)
returns text
language plpgsql
volatile
security invoker
set search_path = ''
as $function$
declare
  v_s crm.inversion_solicitudes%rowtype;
  v_guarda text;
  v_num_contrato text;
  v_contrato_id uuid;
  v_ahora timestamptz := pg_catalog.statement_timestamp();
begin
  if p_solicitud is null or p_motivo is null or p_motivo not in ('numero_contrato_usado', 'sin_movimiento')
     or p_detalle is null or pg_catalog.jsonb_typeof(p_detalle) <> 'object' then
    raise exception 'Solicitud, motivo (numero_contrato_usado | sin_movimiento) y detalle (objeto) requeridos' using errcode = '22023';
  end if;
  -- Nunca espera: la fila que otra sesion tiene (la esta confirmando, corrigiendo o cancelando) se deja para la proxima pasada.
  select s.* into v_s from crm.inversion_solicitudes s where s.id = p_solicitud for update skip locked;
  if not found then
    return case when exists (select 1 from crm.inversion_solicitudes s where s.id = p_solicitud)
                then 'omitida: ocupada por otra sesion' else 'omitida: no existe' end;
  end if;
  -- Las guardas de crm.cancelar_solicitud_inversion_fn (D-19, D-58), releidas bajo el candado: nunca una confirmada o ya
  -- cancelada, nunca una con acceso Avance reservado, nunca una con inversion, nunca una que ya creo su contrato.
  v_guarda := case
    when v_s.estado <> 'preparada' then 'estado ' || v_s.estado
    when v_s.auth_claim_id is not null then 'acceso Avance pendiente'
    when v_s.inversion_id is not null then 'con inversion'
    when exists (select 1 from private.contrato_altas_idempotentes a where a.clave = v_s.id) then 'ya creo su contrato'
    else null end;
  if v_guarda is not null then
    return 'omitida: ' || v_guarda;
  end if;
  -- El MOTIVO, releido bajo el candado (auditor r1, P2; ronda 3): las candidatas se eligen en una consulta y la fila puede haber
  -- sido corregida antes de tomar el candado (otro numero; actualizado_en movido). Si el motivo ya no es cierto, no se toca.
  -- Sin detalle suficiente tampoco (fail-closed).
  v_guarda := case p_motivo
    when 'numero_contrato_usado' then case
      when p_detalle ->> 'numero_contrato' is null then 'detalle sin numero_contrato'
      when coalesce(p_detalle ->> 'contrato_id', '') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then 'detalle sin contrato_id'
      when pg_catalog.btrim(v_s.datos -> 'contrato' ->> 'numero_contrato') is distinct from p_detalle ->> 'numero_contrato' then 'el numero cambio bajo el candado'
      else null end
    when 'sin_movimiento' then case
      when p_detalle ->> 'ultimo_movimiento' is null or p_detalle ->> 'corte' is null or p_detalle ->> 'dias' is null then 'detalle sin corte, dias o ultimo_movimiento'
      when v_s.actualizado_en is distinct from (p_detalle ->> 'ultimo_movimiento')::timestamptz then 'se movio bajo el candado'
      when v_s.actualizado_en > (p_detalle ->> 'corte')::timestamptz - pg_catalog.make_interval(days => (p_detalle ->> 'dias')::integer) then 'ya no cumple el corte'
      else null end
    end;
  if v_guarda is not null then
    return 'omitida: ' || v_guarda;
  end if;
  -- El CONTRATO del motivo, releido bajo candado (Codex r1, P2-1; ronda 4): el contrato del detalle tiene que existir y seguir
  -- con ese numero. KEY SHARE no bloquea lecturas ni UPDATE de columnas no clave y detiene al DELETE (y al UPDATE de clave)
  -- hasta que esta cancelacion confirme; SKIP LOCKED: si otra sesion lo esta eliminando o cambiando, no se espera (omitida).
  -- Orden de candados: solicitud (FOR UPDATE) y despues contrato (KEY SHARE), el mismo que la confirmacion (FOR UPDATE de la
  -- solicitud y despues INSERT del contrato); la eliminacion de contratos (crm.contrato_eliminacion_finalizar) bloquea solo
  -- el contrato y no toca solicitudes: sin ciclo en las vias directas medidas en el catalogo (eliminacion, confirmacion, alta v2);
  -- no se excluyen accesos transitivos por funciones o disparadores (las pruebas con dos sesiones quedan en F4.6).
  -- «ocupado por otra sesion» / «ya no existe» es un diagnostico APROXIMADO bajo READ COMMITTED (el exists posterior puede ver
  -- otro estado que el intento de candado): las dos ramas omiten sin tocar la fila, asi que la imprecision no cancela nada.
  if p_motivo = 'numero_contrato_usado' then
    v_contrato_id := (p_detalle ->> 'contrato_id')::uuid;
    select c.numero_contrato into v_num_contrato from public.contratos c where c.id = v_contrato_id for key share skip locked;
    if not found then
      return case when exists (select 1 from public.contratos c where c.id = v_contrato_id)
                  then 'omitida: contrato ocupado por otra sesion' else 'omitida: el contrato ya no existe' end;
    end if;
    if v_num_contrato is distinct from p_detalle ->> 'numero_contrato' then
      return 'omitida: el contrato ya no lleva ese numero';
    end if;
  end if;
  -- Subtransaccion: si un disparador de la tabla se niega, la solicitud queda como estaba y se informa; quien llama sigue.
  begin
    update crm.inversion_solicitudes
       set estado = 'cancelada',
           actualizado_en = v_ahora,
           cancelacion_motivo = p_motivo,
           cancelacion_detalle = p_detalle || pg_catalog.jsonb_build_object('cancelada_en', v_ahora)
     where id = v_s.id and estado = 'preparada';
    if not found then
      return 'omitida: cambio bajo el candado';
    end if;
  exception when others then
    return 'rechazada: ' || sqlstate || ' ' || sqlerrm;
  end;
  return 'cancelada';
end;
$function$;
comment on function private.solicitud_desechar(uuid, text, jsonb) is
'Único escritor de la cancelación automática de una solicitud de inversión (bloque 2.15). Toma la fila con FOR UPDATE SKIP LOCKED (nunca espera) y relee bajo el candado las mismas guardas de crm.cancelar_solicitud_inversion_fn —preparada, sin acceso Avance pendiente (auth_claim_id), sin inversión y sin haber creado su contrato (sin fila en private.contrato_altas_idempotentes con su id como clave)— Y el motivo: para numero_contrato_usado, que el número actual de la solicitud siga siendo el del detalle y que el contrato del detalle exista y siga con ese número (FOR KEY SHARE SKIP LOCKED sobre public.contratos; si lo está cambiando otra sesión, no se espera); para sin_movimiento, que actualizado_en siga siendo el último movimiento observado y ≤ corte − días (si el motivo ya no es cierto o el detalle no trae esos datos: omitida, sin tocar la fila). Si pasa: estado cancelada, actualizado_en, cancelacion_motivo y cancelacion_detalle (+ cancelada_en), en una subtransacción que aísla el rechazo de un disparador al UPDATE (la fila queda como estaba); las consultas previas y un query_canceled no están cubiertos por ella. Devuelve cancelada | omitida: <guarda> | rechazada: <SQLSTATE> <mensaje>. Sin EXECUTE para la API.';

-- 3.2 CASO 1 (al instante): el contrato recién nacido retira las preparadas que llevan su número.
create function private.solicitudes_desechar_por_contrato(p_contrato_id uuid)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $function$
declare
  v_numero text;
  v_creadoras uuid[];
  v_detalle jsonb;
  v_res text;
  v_canceladas integer := 0;
  v_omitidas integer := 0;
  v_rechazadas integer := 0;
  v_lista jsonb := '[]'::jsonb;
  r record;
begin
  if p_contrato_id is null then
    raise exception 'Contrato requerido' using errcode = '22023';
  end if;
  select c.numero_contrato into v_numero from public.contratos c where c.id = p_contrato_id;
  if v_numero is null then
    return pg_catalog.jsonb_build_object('contrato_id', p_contrato_id, 'numero_contrato', null, 'canceladas', 0, 'omitidas', 0,
      'rechazadas', 0, 'solicitudes', '[]'::jsonb);
  end if;
  -- La solicitud que creo ESTE contrato: su id viaja como clave de idempotencia del alta (la confirmacion de la solicitud
  -- manda clave_idempotencia = id de la solicitud; la puerta v2 lo guarda en private.contrato_altas_idempotentes).
  select coalesce(pg_catalog.array_agg(a.clave), '{}'::uuid[]) into v_creadoras
    from private.contrato_altas_idempotentes a where a.contrato_id = p_contrato_id;
  v_detalle := pg_catalog.jsonb_build_object('via', 'alta', 'contrato_id', p_contrato_id, 'numero_contrato', v_numero);
  for r in
    select s.id
      from crm.inversion_solicitudes s
      join crm.empresas e on e.id = s.empresa_id
     where s.estado = 'preparada'
       and e.crea_contrato_avance
       and pg_catalog.btrim(s.datos -> 'contrato' ->> 'numero_contrato') = v_numero
       and s.id <> all (v_creadoras)
     order by s.creado_en, s.id
  loop
    v_res := private.solicitud_desechar(r.id, 'numero_contrato_usado', v_detalle);
    if v_res = 'cancelada' then v_canceladas := v_canceladas + 1;
    elsif v_res like 'rechazada:%' then v_rechazadas := v_rechazadas + 1;
    else v_omitidas := v_omitidas + 1;
    end if;
    v_lista := v_lista || pg_catalog.jsonb_build_object('solicitud_id', r.id, 'resultado', v_res);
  end loop;
  if v_canceladas + v_rechazadas > 0 then
    raise notice 'solicitudes_desechar_por_contrato: contrato % (%): % cancelada(s), % omitida(s), % rechazada(s)',
      v_numero, p_contrato_id, v_canceladas, v_omitidas, v_rechazadas;
  end if;
  return pg_catalog.jsonb_build_object('contrato_id', p_contrato_id, 'numero_contrato', v_numero, 'canceladas', v_canceladas,
    'omitidas', v_omitidas, 'rechazadas', v_rechazadas, 'solicitudes', v_lista);
end;
$function$;
comment on function private.solicitudes_desechar_por_contrato(uuid) is
'CASO 1 del bloque 2.15 (D-59): dado un contrato recién nacido, cancela —por private.solicitud_desechar— las solicitudes de inversión PREPARADAS de las empresas que crean contrato Avance cuyo datos.contrato.numero_contrato (recortado) es su número y que no son la que lo creó (las claves de private.contrato_altas_idempotentes de ese contrato), con motivo numero_contrato_usado y detalle (via alta, contrato_id, numero_contrato). Devuelve el resumen (canceladas, omitidas, rechazadas y la lista). La llama crm.crear_contrato_con_cuenta_pdf_v2 tras guardar la memoria de idempotencia. No espera por la fila de una solicitud ni por el contrato (SKIP LOCKED); el rechazo de un disparador al cancelar queda aislado en la subtransacción de la pieza y no tumba el alta (las consultas previas y un query_canceled no están cubiertos). Sin EXECUTE para la API.';

-- 3.3 CASO 2 (cada noche): número ya usado (red para los contratos nacidos fuera del CRM) y 30 días sin movimiento.
create function private.solicitudes_desechar_ciclo(
  p_corte timestamptz default pg_catalog.now(),
  p_dias integer default 30,
  p_limite integer default 200
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
set lock_timeout = '10s'
as $function$
declare
  v_inicio timestamptz := pg_catalog.clock_timestamp();
  v_corrida uuid := pg_catalog.gen_random_uuid();
  v_umbral timestamptz;
  v_restante integer;
  v_res text;
  v_nu_c integer := 0; v_nu_o integer := 0; v_nu_r integer := 0;
  v_sm_c integer := 0; v_sm_o integer := 0; v_sm_r integer := 0;
  v_lista jsonb := '[]'::jsonb;
  v_duracion integer;
  r record;
begin
  if p_corte is null or p_dias is null or p_dias < 1 or p_limite is null or p_limite < 1 then
    raise exception 'Instante de corte, días (>= 1) y límite (>= 1) requeridos' using errcode = '22023';
  end if;
  v_umbral := p_corte - pg_catalog.make_interval(days => p_dias);
  -- PRESUPUESTO UNICO por corrida (Codex r1, P2-2; ronda 4): como mucho p_limite (200) CANCELACIONES entre las dos pasadas, la
  -- de «numero usado» primero. Las omitidas y las rechazadas no lo consumen (P2-3): el recorrido sigue, en orden estable, hasta
  -- agotar las candidatas o el presupuesto. Las exclusiones permanentes que la consulta puede conocer (acceso Avance pendiente,
  -- con inversion, ya creo su contrato) se descartan ANTES, no en la pieza: una cola de excluidas no tapa a una candidata valida.
  v_restante := p_limite;

  -- Pasada 1 (D-59, caso 1 como red; D-79): preparadas de Avance cuyo numero ya lo usa un contrato que no creo esa solicitud.
  for r in
    select s.id, c.id as contrato_id, c.numero_contrato
      from crm.inversion_solicitudes s
      join crm.empresas e on e.id = s.empresa_id
      join public.contratos c on c.numero_contrato = pg_catalog.btrim(s.datos -> 'contrato' ->> 'numero_contrato')
     where s.estado = 'preparada'
       and e.crea_contrato_avance
       and s.auth_claim_id is null
       and s.inversion_id is null
       and not exists (select 1 from private.contrato_altas_idempotentes a where a.clave = s.id)
     order by s.creado_en, s.id
  loop
    exit when v_restante <= 0;
    v_res := private.solicitud_desechar(r.id, 'numero_contrato_usado',
      pg_catalog.jsonb_build_object('via', 'tarea', 'corrida_id', v_corrida, 'corte', p_corte,
        'contrato_id', r.contrato_id, 'numero_contrato', r.numero_contrato));
    if v_res = 'cancelada' then v_nu_c := v_nu_c + 1; v_restante := v_restante - 1;
    elsif v_res like 'rechazada:%' then v_nu_r := v_nu_r + 1;
    else v_nu_o := v_nu_o + 1;
    end if;
    v_lista := v_lista || pg_catalog.jsonb_build_object('solicitud_id', r.id, 'motivo', 'numero_contrato_usado', 'resultado', v_res);
  end loop;

  -- Pasada 2 (D-63, D-74): preparadas de cualquier empresa sin confirmarse ni corregirse (actualizado_en) desde hace p_dias dias
  -- o mas, con el presupuesto que quede.
  for r in
    select s.id, s.actualizado_en
      from crm.inversion_solicitudes s
     where s.estado = 'preparada'
       and s.auth_claim_id is null
       and s.inversion_id is null
       and not exists (select 1 from private.contrato_altas_idempotentes a where a.clave = s.id)
       and s.actualizado_en <= v_umbral
     order by s.actualizado_en, s.id
  loop
    exit when v_restante <= 0;
    v_res := private.solicitud_desechar(r.id, 'sin_movimiento',
      pg_catalog.jsonb_build_object('via', 'tarea', 'corrida_id', v_corrida, 'corte', p_corte,
        'dias', p_dias, 'ultimo_movimiento', r.actualizado_en));
    if v_res = 'cancelada' then v_sm_c := v_sm_c + 1; v_restante := v_restante - 1;
    elsif v_res like 'rechazada:%' then v_sm_r := v_sm_r + 1;
    else v_sm_o := v_sm_o + 1;
    end if;
    v_lista := v_lista || pg_catalog.jsonb_build_object('solicitud_id', r.id, 'motivo', 'sin_movimiento', 'resultado', v_res);
  end loop;

  v_duracion := greatest(0, (extract(epoch from pg_catalog.clock_timestamp() - v_inicio) * 1000)::integer);
  insert into crm.solicitudes_desechadas_corridas
    (id, corte, dias, limite, canceladas_numero_usado, canceladas_sin_movimiento, omitidas, rechazadas, detalle, duracion_ms)
  values
    (v_corrida, p_corte, p_dias, p_limite, v_nu_c, v_sm_c, v_nu_o + v_sm_o, v_nu_r + v_sm_r, v_lista, v_duracion);
  return pg_catalog.jsonb_build_object('corrida_id', v_corrida, 'corte', p_corte, 'dias', p_dias, 'limite', p_limite,
    'numero_contrato_usado', pg_catalog.jsonb_build_object('canceladas', v_nu_c, 'omitidas', v_nu_o, 'rechazadas', v_nu_r),
    'sin_movimiento', pg_catalog.jsonb_build_object('canceladas', v_sm_c, 'omitidas', v_sm_o, 'rechazadas', v_sm_r),
    'duracion_ms', v_duracion, 'solicitudes', v_lista);
end;
$function$;
comment on function private.solicitudes_desechar_ciclo(timestamptz, integer, integer) is
'CASO 2 del bloque 2.15 (D-59, D-63): corrida nocturna. Pasada 1: las solicitudes de inversión PREPARADAS de Avance cuyo número de contrato ya lo usa un contrato que no creó esa solicitud (red para los contratos nacidos fuera del CRM), motivo numero_contrato_usado. Pasada 2: las preparadas de cualquier empresa con p_dias (30) días o más sin confirmarse ni corregirse (actualizado_en <= p_corte − p_dias), motivo sin_movimiento. Presupuesto único por corrida: como mucho p_limite (200) cancelaciones entre las dos pasadas, de la más antigua a la más nueva; las omitidas y las rechazadas no lo consumen (el recorrido sigue hasta agotar candidatas o presupuesto); las exclusiones permanentes (acceso Avance pendiente, con inversión, ya creó su contrato) se descartan antes del recorrido. No espera por la fila de una solicitud (SKIP LOCKED) ni por su contrato (KEY SHARE SKIP LOCKED); los disparadores de la tabla pueden esperar según sus propios candados (lock_timeout 10s). Deja una fila en crm.solicitudes_desechadas_corridas y devuelve el resumen. Idempotente (sin efectos duplicados sobre la misma solicitud). La invoca pg_cron (crm-solicitudes-desechar) como postgres. Sin EXECUTE para la API.';

-- 3.4 Lo que ve el asesor.
create function private.solicitud_cancelacion_vista(p_solicitud uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $function$
  select coalesce((
    select pg_catalog.jsonb_build_object(
      'cancelacion_motivo', s.cancelacion_motivo,
      'cancelacion_detalle', s.cancelacion_detalle - 'contrato_id',
      'cancelacion_texto', case s.cancelacion_motivo
        when 'numero_contrato_usado' then
          'El CRM canceló esta solicitud: el número de contrato ' || coalesce(s.cancelacion_detalle ->> 'numero_contrato', '(sin número)')
          || ' ya lo usa otro contrato.'
        when 'sin_movimiento' then
          'El CRM canceló esta solicitud: llevaba ' || coalesce(s.cancelacion_detalle ->> 'dias', '30')
          || ' días sin confirmarse ni corregirse.'
        else null end)
    from crm.inversion_solicitudes s where s.id = p_solicitud
  ), pg_catalog.jsonb_build_object('cancelacion_motivo', null, 'cancelacion_detalle', null, 'cancelacion_texto', null));
$function$;
comment on function private.solicitud_cancelacion_vista(uuid) is
'Bloque 2.15: las tres claves que la consulta de una solicitud (crm.solicitud_inversion_fn) añade a su respuesta: cancelacion_motivo, cancelacion_detalle (sin contrato_id: el UUID del contrato ajeno no sale a la API; queda en la fila y en public.audit_log) y cancelacion_texto (el texto que ve el asesor); nulas si el CRM no la canceló solo. Sin EXECUTE para la API.';

alter function private.solicitud_desechar(uuid, text, jsonb) owner to postgres;
alter function private.solicitudes_desechar_por_contrato(uuid) owner to postgres;
alter function private.solicitudes_desechar_ciclo(timestamptz, integer, integer) owner to postgres;
alter function private.solicitud_cancelacion_vista(uuid) owner to postgres;
revoke all on function private.solicitud_desechar(uuid, text, jsonb) from public, anon, authenticated, service_role;
revoke all on function private.solicitudes_desechar_por_contrato(uuid) from public, anon, authenticated, service_role;
revoke all on function private.solicitudes_desechar_ciclo(timestamptz, integer, integer) from public, anon, authenticated, service_role;
revoke all on function private.solicitud_cancelacion_vista(uuid) from public, anon, authenticated, service_role;

-- ── 4 · El alta del CRM retira, al instante, las preparadas que llevan su número (por ancla única) ───────────────────────────
do $patch$
declare
  v_def   text;
  v_ancla text;
  v_nueva text;
begin
  v_def := pg_get_functiondef('crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)'::regprocedure);
  v_ancla := $antes$    values (v_actor_id, v_clave, v_contrato_id, v_huella, v_resultado);
  end if;
  return v_resultado;
$antes$;
  v_nueva := $despues$    values (v_actor_id, v_clave, v_contrato_id, v_huella, v_resultado);
  end if;
  -- BLOQUE 2.15 (plan AVANCE-BACKEND-0810-F2; D-58, D-59): el contrato ya tiene su numero. Las solicitudes de inversion
  -- PREPARADAS de Avance que llevan ese mismo numero y no son la que lo creo (su clave de idempotencia, arriba) ya no se
  -- podran confirmar nunca: se cancelan solas, con el motivo a la vista de su asesor. Cada cancelacion va en su propia
  -- subtransaccion dentro de la pieza: nunca tumba el alta.
  perform private.solicitudes_desechar_por_contrato(v_contrato_id);
  return v_resultado;
$despues$;
  if cardinality(string_to_array(v_def, v_ancla)) <> 2 then
    raise exception 'PATCH solicitudes_desechadas_solas: el ancla del alta no es única en crm.crear_contrato_con_cuenta_pdf_v2';
  end if;
  execute replace(v_def, v_ancla, v_nueva);
end
$patch$;
comment on function crm.crear_contrato_con_cuenta_pdf_v2(jsonb, jsonb, jsonb) is
  'Alta CRM atómica de contrato, cronograma, cuenta de pago y reserva documental v2. Bloque 2.15 (D-58, D-59): tras el alta, las solicitudes de inversión PREPARADAS de Avance que llevan el mismo número de contrato y no son la que lo creó se cancelan solas, con el motivo a la vista de su asesor (private.solicitudes_desechar_por_contrato); el rechazo de un disparador al cancelar no tumba el alta (subtransacción por solicitud).';

-- ── 5 · La consulta de una solicitud dice por qué la canceló el CRM (por ancla única) ───────────────────────────────────────
do $patch$
declare
  v_def   text;
  v_ancla text;
  v_nueva text;
begin
  v_def := pg_get_functiondef('crm.solicitud_inversion_fn(uuid)'::regprocedure);
  v_ancla := $antes$  return private.inversion_solicitud_resultado(p_solicitud,v_ctx)||jsonb_build_object('datos',v_datos);$antes$;
  v_nueva := $despues$  return private.inversion_solicitud_resultado(p_solicitud,v_ctx)||jsonb_build_object('datos',v_datos)||private.solicitud_cancelacion_vista(p_solicitud);$despues$;
  if cardinality(string_to_array(v_def, v_ancla)) <> 2 then
    raise exception 'PATCH solicitudes_desechadas_solas: el ancla del return no es única en crm.solicitud_inversion_fn';
  end if;
  execute replace(v_def, v_ancla, v_nueva);
end
$patch$;
comment on function crm.solicitud_inversion_fn(uuid) is
  'Consulta una solicitud de inversión. Autoriza con la solicitud como llave: en venta cruzada, su analista y su cadena; en cartera, la regla de siempre. Bloque 2.15: añade cancelacion_motivo, cancelacion_detalle y cancelacion_texto (nulos si el CRM no la canceló solo).';

-- ── 6 · El reloj: cada noche a las 07:17 UTC (02:17 Lima) ───────────────────────────────────────────────────────────────────
do $reloj$
begin
  if to_regclass('cron.job') is null or to_regprocedure('cron.schedule(text,text,text)') is null then
    -- Solo se llega aquí con la marca de laboratorio (el preflight se negó si no estaba).
    if coalesce(current_setting('crm.laboratorio_sin_cron', true), '') <> '1' then
      raise exception 'RELOJ solicitudes_desechadas_solas: sin pg_cron y sin la marca crm.laboratorio_sin_cron: no se puede seguir';
    end if;
    raise notice 'LABORATORIO SIN RELOJ (marca crm.laboratorio_sin_cron = 1): no se programa la tarea crm-solicitudes-desechar. En una base real esto es un error.';
    return;
  end if;
  -- `cron.schedule` reemplaza por nombre: reaplicar sería idempotente (el preflight se niega de todos modos).
  perform cron.schedule('crm-solicitudes-desechar', '17 7 * * *', 'select private.solicitudes_desechar_ciclo()');
end;
$reloj$;

-- ── 7 · Postflight (fail-closed) ────────────────────────────────────────────────────────────────────────────────────────────
do $postflight$
declare
  v_h record;
  v_ficha text;
  v_obtenida text;
  v_foto text := '';
  v text;
  v_sonda jsonb;
  v_n integer;
  r record;
begin
  -- 7.1 Las dos puertas: el cuerpo ensayado (huella exacta), la ficha idéntica a la previa y su comentario nuevo.
  select md5(p.prosrc) into v_obtenida from pg_proc p where p.oid = 'crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)'::regprocedure;
  if v_obtenida is distinct from '6ecd78e32f1b39dff4ee9827dc00c459' then
    raise exception 'POSTFLIGHT solicitudes_desechadas_solas: el cuerpo de crm.crear_contrato_con_cuenta_pdf_v2 no es el ensayado (huella obtenida %)', v_obtenida;
  end if;
  if (select p.oid::regprocedure::text || '|' || p.proowner::regrole::text || '|' || p.prosecdef::text
        || '|' || coalesce(p.proconfig::text, '-') || '|' || coalesce(p.proacl::text, '-')
        || '|' || p.provolatile::text || '|' || p.proparallel::text || '|' || p.proleakproof::text
        || '|' || p.prorettype::regtype::text
       from pg_proc p where p.oid = 'crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)'::regprocedure)
     is distinct from current_setting('crm.c215_pdf_v2_ficha_previa', true) then
    raise exception 'POSTFLIGHT solicitudes_desechadas_solas: cambió el dueño, la ACL o un atributo de crm.crear_contrato_con_cuenta_pdf_v2';
  end if;
  if (select position('perform private.solicitudes_desechar_por_contrato(v_contrato_id);' in p.prosrc) = 0
        from pg_proc p where p.oid = 'crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)'::regprocedure) then
    raise exception 'POSTFLIGHT solicitudes_desechadas_solas: la llamada a la pieza no quedó en crm.crear_contrato_con_cuenta_pdf_v2';
  end if;
  select md5(p.prosrc) into v_obtenida from pg_proc p where p.oid = 'crm.solicitud_inversion_fn(uuid)'::regprocedure;
  if v_obtenida is distinct from 'ca715d075ca160afdff0257f190616dd' then
    raise exception 'POSTFLIGHT solicitudes_desechadas_solas: el cuerpo de crm.solicitud_inversion_fn no es el ensayado (huella obtenida %)', v_obtenida;
  end if;
  if (select p.oid::regprocedure::text || '|' || p.proowner::regrole::text || '|' || p.prosecdef::text
        || '|' || coalesce(p.proconfig::text, '-') || '|' || coalesce(p.proacl::text, '-')
        || '|' || p.provolatile::text || '|' || p.proparallel::text || '|' || p.proleakproof::text
        || '|' || p.prorettype::regtype::text
       from pg_proc p where p.oid = 'crm.solicitud_inversion_fn(uuid)'::regprocedure)
     is distinct from current_setting('crm.c215_consulta_ficha_previa', true) then
    raise exception 'POSTFLIGHT solicitudes_desechadas_solas: cambió el dueño, la ACL o un atributo de crm.solicitud_inversion_fn';
  end if;
  if has_function_privilege('anon', 'crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)', 'EXECUTE')
     or has_function_privilege('anon', 'crm.solicitud_inversion_fn(uuid)', 'EXECUTE')
     or has_function_privilege('service_role', 'crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)', 'EXECUTE')
     or has_function_privilege('service_role', 'crm.solicitud_inversion_fn(uuid)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'crm.solicitud_inversion_fn(uuid)', 'EXECUTE') then
    raise exception 'POSTFLIGHT solicitudes_desechadas_solas: las dos puertas deben seguir con EXECUTE para authenticated y sin EXECUTE para anon ni service_role';
  end if;
  if obj_description('crm.crear_contrato_con_cuenta_pdf_v2(jsonb,jsonb,jsonb)'::regprocedure, 'pg_proc') not like '%Bloque 2.15%'
     or obj_description('crm.solicitud_inversion_fn(uuid)'::regprocedure, 'pg_proc') not like '%Bloque 2.15%' then
    raise exception 'POSTFLIGHT solicitudes_desechadas_solas: falta el comentario nuevo en una de las dos puertas';
  end if;

  -- 7.2 Las cuatro piezas, con su ficha.
  for v_h in
    select * from (values
      ('private.solicitud_desechar(uuid,text,jsonb)', 'postgres|false|v|u|search_path=""|postgres:EXECUTE:false'),
      ('private.solicitudes_desechar_por_contrato(uuid)', 'postgres|false|v|u|search_path=""|postgres:EXECUTE:false'),
      ('private.solicitudes_desechar_ciclo(timestamp with time zone,integer,integer)', 'postgres|false|v|u|search_path="";lock_timeout=10s|postgres:EXECUTE:false'),
      ('private.solicitud_cancelacion_vista(uuid)', 'postgres|false|s|u|search_path=""|postgres:EXECUTE:false')
    ) as h(firma, ficha)
  loop
    if to_regprocedure(v_h.firma) is null then
      raise exception 'POSTFLIGHT solicitudes_desechadas_solas: falta la pieza %', v_h.firma;
    end if;
    select p.proowner::regrole::text || '|' || p.prosecdef::text || '|' || p.provolatile::text || '|' || p.proparallel::text
             || '|' || coalesce(array_to_string(p.proconfig, ';'), '-')
             || '|' || coalesce((select string_agg(a.grantee::regrole::text || ':' || a.privilege_type || ':' || a.is_grantable::text, ',' order by a.grantee::regrole::text)
                                   from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a), '-')
      into v_ficha
      from pg_proc p where p.oid = to_regprocedure(v_h.firma);
    if v_ficha is distinct from v_h.ficha then
      raise exception 'POSTFLIGHT solicitudes_desechadas_solas: la ficha de % no es la prevista (medida «%»; prevista «%»)', v_h.firma, v_ficha, v_h.ficha;
    end if;
    if obj_description(to_regprocedure(v_h.firma), 'pg_proc') is null then
      raise exception 'POSTFLIGHT solicitudes_desechadas_solas: la pieza % quedó sin comentario', v_h.firma;
    end if;
  end loop;

  -- 7.3 Columnas, CHECK, tabla con RLS, sin grants y con auditor completo (la regla de auditoría no la lista).
  if (select string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod) || ':' || a.attnotnull::text, ',' order by a.attname)
        from pg_attribute a where a.attrelid = 'crm.inversion_solicitudes'::regclass and a.attnum > 0 and not a.attisdropped
         and a.attname in ('cancelacion_motivo','cancelacion_detalle'))
     is distinct from 'cancelacion_detalle:jsonb:false,cancelacion_motivo:text:false' then
    raise exception 'POSTFLIGHT solicitudes_desechadas_solas: las columnas cancelacion_motivo/cancelacion_detalle no quedaron como se previó';
  end if;
  if not exists (select 1 from pg_constraint c where c.conrelid = 'crm.inversion_solicitudes'::regclass and c.conname = 'inversion_solicitud_cancelacion_coherente')
     or not exists (select 1 from pg_constraint c where c.conrelid = 'crm.inversion_solicitudes'::regclass and c.conname = 'inversion_solicitud_cancelacion_motivo_valido') then
    raise exception 'POSTFLIGHT solicitudes_desechadas_solas: faltan los CHECK de la cancelación';
  end if;
  if not exists (select 1 from pg_class c where c.oid = 'crm.solicitudes_desechadas_corridas'::regclass
                   and c.relowner = 'postgres'::regrole::oid and c.relrowsecurity)
     or exists (select 1 from pg_class c cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
                 where c.oid = 'crm.solicitudes_desechadas_corridas'::regclass and a.grantee <> 'postgres'::regrole::oid) then
    raise exception 'POSTFLIGHT solicitudes_desechadas_solas: crm.solicitudes_desechadas_corridas sin RLS, con grants a otro rol o con otro dueño';
  end if;
  if exists (select 1 from information_schema.role_table_grants g
              where g.table_schema = 'crm' and g.table_name = 'solicitudes_desechadas_corridas'
                and g.grantee in ('anon', 'authenticated', 'service_role', 'PUBLIC')) then
    raise exception 'POSTFLIGHT solicitudes_desechadas_solas: crm.solicitudes_desechadas_corridas tiene grants para roles de la API';
  end if;
  if exists (select 1 from private.tablas_sin_rastro() t where t.tabla = 'crm.solicitudes_desechadas_corridas') then
    raise exception 'POSTFLIGHT solicitudes_desechadas_solas: crm.solicitudes_desechadas_corridas no tiene rastro completo de auditoría';
  end if;
  if (select pg_get_triggerdef(t.oid) || '|' || t.tgenabled::text from pg_trigger t where t.tgrelid = 'crm.inversion_solicitudes'::regclass and t.tgname = 'trg_audit_inversion_solicitudes')
     is distinct from $c$CREATE TRIGGER trg_audit_inversion_solicitudes AFTER INSERT OR DELETE OR UPDATE ON crm.inversion_solicitudes FOR EACH ROW EXECUTE FUNCTION private.log_audit_sin_secretos('datos', 'auth_contexto', 'motivo_atribucion')$c$ || '|O' then
    raise exception 'POSTFLIGHT solicitudes_desechadas_solas: el auditor de crm.inversion_solicitudes cambió o quedó deshabilitado durante la migración';
  end if;
  if not exists (select 1 from pg_trigger t where t.tgrelid = 'crm.solicitudes_desechadas_corridas'::regclass
                   and t.tgname = 'trg_audit_solicitudes_desechadas_corridas' and t.tgenabled = 'O') then
    raise exception 'POSTFLIGHT solicitudes_desechadas_solas: el auditor de crm.solicitudes_desechadas_corridas no quedó habilitado';
  end if;
  if (select pg_get_triggerdef(t.oid) || '|' || t.tgenabled::text from pg_trigger t where t.tgrelid = 'crm.inversion_solicitudes'::regclass and t.tgname = 'trg_solicitudes_zz_postventa')
     is distinct from $c$CREATE TRIGGER trg_solicitudes_zz_postventa BEFORE UPDATE OF datos, estado, inversionista_id, empresa_id ON crm.inversion_solicitudes FOR EACH ROW EXECUTE FUNCTION private.postventa_reinversion_guard()$c$ || '|O'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.postventa_reinversion_guard()')) is distinct from '4755f4c8ca3cbaf85aa619141c03a145'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.continuidad_coopac_fuente(uuid,uuid,text,text)')) is distinct from '93f51bbfbcc75a6bec3b972a5900a1ed' then
    raise exception 'POSTFLIGHT solicitudes_desechadas_solas: la continuidad de postventa (disparador, guarda o continuidad) cambió durante la migración';
  end if;
  if (select p.proowner::regrole::text || '|' || p.prosecdef::text || '|' || coalesce(array_to_string(p.proconfig, ';'), '-')
        from pg_proc p where p.oid = to_regprocedure('private.postventa_reinversion_guard()')) is distinct from 'postgres|true|search_path="";lock_timeout=5s'
     or (select p.proowner::regrole::text || '|' || p.prosecdef::text || '|' || coalesce(array_to_string(p.proconfig, ';'), '-')
        from pg_proc p where p.oid = to_regprocedure('private.continuidad_coopac_fuente(uuid,uuid,text,text)')) is distinct from 'postgres|false|search_path=""' then
    raise exception 'POSTFLIGHT solicitudes_desechadas_solas: la ficha (dueño, DEFINER, configuración) de la continuidad de postventa cambió durante la migración';
  end if;

  -- 7.4 El reloj: obligatorio salvo la marca de laboratorio (preflight 0.5).
  if to_regclass('cron.job') is null or to_regprocedure('cron.schedule(text,text,text)') is null then
    if coalesce(current_setting('crm.laboratorio_sin_cron', true), '') <> '1' then
      raise exception 'POSTFLIGHT solicitudes_desechadas_solas: sin pg_cron y sin la marca crm.laboratorio_sin_cron';
    end if;
  else
    select count(*) into v_n from cron.job j
     where j.jobname = 'crm-solicitudes-desechar' and j.active
       and j.schedule = '17 7 * * *' and j.command = 'select private.solicitudes_desechar_ciclo()';
    if v_n <> 1 then
      raise exception 'POSTFLIGHT solicitudes_desechadas_solas: la tarea quedó con % jobs activos crm-solicitudes-desechar con su horario y comando, se esperaba 1', v_n;
    end if;
  end if;

  -- 7.5 Lo que no se toca, intacto.
  if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.cancelar_solicitud_inversion_fn(uuid,integer)')) is distinct from '5e92b8ef8c54b160578463932c1eca1a'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.confirmar_inversion_revisada_fn(uuid,integer)')) is distinct from 'ef53419d436583b116ff68e5a1509855'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('crm.corregir_solicitud_inversion_fn(uuid,uuid,integer,jsonb,text)')) is distinct from '3977f1ab0fd4a134c58cf8edd5556ae6'
     or (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure('private.inversion_solicitud_resultado(uuid,jsonb)')) is distinct from '26dac93e46ffd7b2b9d12691c7905790' then
    raise exception 'POSTFLIGHT solicitudes_desechadas_solas: cambió algo que esta migración no debía tocar (cancelar, confirmar, corregir o el resultado público de la solicitud)';
  end if;

  -- 7.6 SONDA que se deshace: las dos piezas ejecutadas de verdad en una subtransacción que SIEMPRE se revierte. Nada queda
  --     cancelado ni anotado al aplicar; solo se comprueba que corren y responden con su forma.
  begin
    v_sonda := private.solicitudes_desechar_por_contrato('00000000-0000-0000-0000-000000000000'::uuid);
    if (v_sonda ->> 'canceladas')::integer <> 0 or v_sonda -> 'numero_contrato' <> 'null'::jsonb then
      raise exception 'POSTFLIGHT solicitudes_desechadas_solas: la pieza del alta no responde como se previó para un contrato inexistente (%)', v_sonda;
    end if;
    v_sonda := private.solicitudes_desechar_ciclo(now(), 30, 1);
    if v_sonda is null or not (v_sonda ? 'corrida_id' and v_sonda ? 'numero_contrato_usado' and v_sonda ? 'sin_movimiento' and v_sonda ? 'solicitudes')
       or (select count(*) from crm.solicitudes_desechadas_corridas c where c.id = (v_sonda ->> 'corrida_id')::uuid) <> 1 then
      raise exception 'POSTFLIGHT solicitudes_desechadas_solas: la tarea no responde con su forma o no deja su corrida (%)', v_sonda;
    end if;
    if private.solicitud_cancelacion_vista('00000000-0000-0000-0000-000000000000'::uuid)
       is distinct from jsonb_build_object('cancelacion_motivo', null, 'cancelacion_detalle', null, 'cancelacion_texto', null) then
      raise exception 'POSTFLIGHT solicitudes_desechadas_solas: la vista de la cancelación no devuelve las tres claves nulas para una solicitud inexistente';
    end if;
    raise notice 'POSTFLIGHT solicitudes_desechadas_solas: sonda de la tarea (se deshace): número usado %, sin movimiento %',
      v_sonda -> 'numero_contrato_usado', v_sonda -> 'sin_movimiento';
    raise exception using errcode = 'ZZRB5', message = 'deshacer la sonda';
  exception
    when sqlstate 'ZZRB5' then null;
  end;
  if exists (select 1 from crm.solicitudes_desechadas_corridas) then
    raise exception 'POSTFLIGHT solicitudes_desechadas_solas: la sonda dejó una corrida escrita (no se deshizo)';
  end if;

  -- 7.7 La FOTO de los private.assert_*() (sin los *_mutantes), EXACTAMENTE la misma que antes de la migración.
  for r in
    select p.oid::regprocedure::text as f
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private' and p.proname like 'assert\_%' and p.proname !~ '_mutantes$' and p.pronargs = 0
    order by 1
  loop
    begin
      execute 'select ' || r.f;
      v := 'pasa';
    exception when others then
      v := 'cae: ' || sqlstate || ' ' || sqlerrm;
    end;
    v_foto := v_foto || r.f || ' => ' || v || E'\n';
  end loop;
  if v_foto is distinct from current_setting('crm.c215_trinquetes_previos', true) then
    raise exception E'POSTFLIGHT solicitudes_desechadas_solas: algún private.assert_*() da otro resultado que antes de la migración.\nANTES:\n%\nDESPUÉS:\n%',
      current_setting('crm.c215_trinquetes_previos', true), v_foto;
  end if;
  raise notice 'POSTFLIGHT solicitudes_desechadas_solas: alta v2 con la pieza · consulta con el motivo · 4 piezas · 2 columnas · corridas · job crm-solicitudes-desechar 07:17 UTC · sonda deshecha · trinquetes idénticos';
end
$postflight$;

commit;
