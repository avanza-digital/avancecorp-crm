-- P-055 Fase 1.1 - Rastro de lo que tiene valor probatorio (Miguel, 28/08).
--
-- QUE: cuatro tablas dejan de poder cambiar sin dejar rastro.
--   1. public.contrato_titulares -> auditor NUEVO (INSERT/UPDATE/DELETE).
--      Es el unico ROTO real del inventario P-053: los co-titulares de una
--      cuenta mancomunada se agregan y se quitan por delete+reinsert desde
--      public._sync_contrato_titulares y hoy no queda una sola linea (0 filas
--      en audit_log contra 1083 del contrato al que pertenecen). Es el dato
--      con mas peso legal del sistema.
--   2. crm.actividades_cliente -> auditor NUEVO (INSERT/UPDATE/DELETE).
--      Historial de gestion del cliente: hoy sin auditor de ningun tipo.
--   3. crm.actividades -> auditor NUEVO para el cambio y el borrado (el que ya
--      existe, de solo INSERT, no se toca): se podia borrar la gestion de un
--      lead sin rastro.
--   4. public.cronograma_pagos -> auditor NUEVO solo para el ALTA y la BAJA de
--      una cuota. El auditor de UPDATE que ya existe NO SE TOCA (ver abajo).
--
-- COMO: TODO ES ADITIVO. No se borra ni se recrea un solo trigger existente, y
-- no se toca ninguna funcion de auditoria: solo se cuelgan cuatro triggers
-- nuevos. No es estilo: es la leccion de la version anterior de este mismo
-- archivo (ver el aviso de abajo), y evita tres riesgos de una vez:
--   * perder atributos que `tgtype` no codifica -clausula WHEN, `UPDATE OF`,
--     enabled/replica, deferibilidad-, porque no se recrea nada;
--   * el candado: `drop trigger` exige ACCESS EXCLUSIVE sobre una tabla viva;
--     `create trigger` se conforma con SHARE ROW EXCLUSIVE;
--   * cambiar sin querer el orden de disparo.
-- Cada trigger nuevo mira eventos que NINGUN otro auditor mira en esa tabla
-- (UPDATE/DELETE en la gestion del lead, INSERT/DELETE en las cuotas), asi que
-- no hay doble registro de una misma operacion.
--
-- AVISO: EL TRIGGER DE CUOTAS NO SE RECREA - Y ESTO ESTUVO A PUNTO DE SER UN
-- FALLO. La primera version de esta migracion hacia DROP+CREATE tambien sobre
-- `trg_audit_cronograma_pago` para anadirle INSERT y DELETE. Ese trigger tiene
-- una clausula WHEN puesta a proposito en la auditoria del portal del
-- 2026-06-13: audita SOLO los UPDATE que tocan el pago (estado, monto_pagado,
-- fecha_pago_real, registrado_por). Recrearlo la habria borrado en silencio, y
-- con ella la unica defensa contra el ruido: el cron diario de recordatorios
-- escribe `notif_pago_enviada_en` y `recordatorio_3d_enviado_en` en muchas
-- filas, y sin el WHEN cada uno de esos sellos dejaria una fila de auditoria
-- con el JSON entero del antes y el despues. Asi que el trigger de UPDATE se
-- queda EXACTAMENTE como esta, y el hueco probatorio -que era el borrado- se
-- cierra con un trigger APARTE para INSERT y DELETE, donde una clausula WHEN
-- sobre `old`/`new` ni siquiera seria valida.
--
-- CONVENCION DE AUDITORIA - decision declarada, no descuido: cada esquema
-- conserva la suya. `public` usa public.log_audit_change (la columna `tabla`
-- guarda el nombre SIN esquema, como ya lo guardan contratos, perfiles y
-- cronograma_pagos) y `crm` usa private.log_audit_crm (la guarda CON esquema).
-- Unificarlas cambiaria el significado de las 22.000 filas ya escritas y
-- romperia toda consulta que lea `tabla`; el log partido queda DECLARADO aqui.
--
-- POR QUE AHORA: la Fase 1 tiene que estar publicada antes del primer cierre
-- de mes real. El coste es cero: son triggers, no datos.
--
-- FUERA DE ALCANCE A PROPOSITO (la Fase 7 los arregla o los declara):
--   * crm.operaciones_cartera: ledger append-only deliberado, con autoria en
--     la propia fila y un trigger que lo hace cumplir. REFUTADO como roto.
--   * crm.usuario_eventos: su `id` es BIGINT y private.log_audit_crm lo
--     castea a uuid -> colgarselo tal cual ABORTARIA todo su DML. Necesita su
--     propio auditor, no este.
--   * public.audit_log: auditarse a si mismo es recursion infinita.
--   * crm.agenda_ics, public.novedades_leidas, public.suscripciones_push y las
--     tablas operativas de `private`: sin valor probatorio.
--
-- LO QUE ESTO AMPLIA Y HAY QUE DECIR EN VOZ ALTA (auditoria RLS, 28/08):
--   * `crm.actividades_cliente` tiene su lectura acotada por RLS al subarbol
--     (gerencia, lector global, o el equipo del cliente). Su AUDITORIA, en
--     cambio, se escribe en `public.audit_log`, cuya lectura la gobiernan
--     `es_admin()`/`es_superadmin()` del PORTAL. Es decir: un admin del portal
--     que no sea gerencia del CRM pasa a poder leer el `detalle` de la gestion
--     comercial y, con `contrato_titulares`, el documento de cada co-titular.
--     Es el mismo trato que ya recibe `crm.leads` (que audita ahi con DNI y
--     telefono desde los cimientos), asi que no es una excepcion nueva; pero
--     queda DECLARADO. La vista de `audit_log` recortada por ambito es tarea
--     de la Fase 7.
--   * La bandeja de actividad del portal NO se contamina: `bandeja_actividad`
--     filtra por lista blanca (`al.tabla in ('perfiles','contratos')`),
--     verificado en produccion el 28/08. Su canal en vivo se suscribe a todo
--     `audit_log` con un retardo de 500 ms, asi que un alta de contrato puede
--     provocar una recarga mas de una pantalla ya abierta: la misma que ya
--     provoca hoy el alta del contrato en si.
--
-- AUTORIZACION: toca objetos de `public` (el portal en produccion) con el OK
-- explicito de Miguel al aprobar la Fase 1 del PLAN MAESTRO del servidor
-- (P-055). Ninguna funcion, policy ni grant cambia en esta migracion.

-- Que esto no se quede esperando detras de una transaccion larga: si no consigue
-- el candado en 5 segundos, falla y se reintenta, en vez de formar cola delante
-- de las escrituras del portal.
set local lock_timeout = '5s';

-- == Preflight: el mundo vivo tiene que ser el que este cambio describe =======
do $preflight$
declare
  v_md5_public text;
  v_md5_crm    text;
  v_tipo       smallint;
  v_trg        oid;
  v_def        text;
begin
  -- Las dos funciones de auditoria son las auditadas el 28/08. Si alguna
  -- cambio, este trigger podria estar colgando otra cosa.
  select md5(p.prosrc) into v_md5_public
  from pg_catalog.pg_proc p
  where p.oid = 'public.log_audit_change()'::regprocedure;
  if v_md5_public is distinct from '0a71bb602eddd63669dfd6993246d16e' then
    raise exception 'public.log_audit_change viva (md5 %) no es la esperada', v_md5_public;
  end if;
  -- El hash cubre el CUERPO, no los atributos: una funcion con el mismo texto
  -- pero sin SECURITY DEFINER no podria escribir en `audit_log` y abortaria todo
  -- el DML de las tablas que la cuelguen. Se comprueba aparte.
  if not (select p.prosecdef from pg_catalog.pg_proc p
          where p.oid = 'public.log_audit_change()'::regprocedure) then
    raise exception 'public.log_audit_change no es SECURITY DEFINER: colgarla abortaria el DML';
  end if;

  select md5(p.prosrc) into v_md5_crm
  from pg_catalog.pg_proc p
  where p.oid = 'private.log_audit_crm()'::regprocedure;
  if v_md5_crm is distinct from '461846328cab450929731c0ca9edd319' then
    raise exception 'private.log_audit_crm viva (md5 %) no es la esperada', v_md5_crm;
  end if;
  if not (select p.prosecdef from pg_catalog.pg_proc p
          where p.oid = 'private.log_audit_crm()'::regprocedure) then
    raise exception 'private.log_audit_crm no es SECURITY DEFINER: colgarla abortaria el DML';
  end if;

  -- Las dos tablas sin auditor siguen sin auditor.
  if exists (
    select 1 from pg_catalog.pg_trigger t
    join pg_catalog.pg_proc p on p.oid = t.tgfoid
    where t.tgrelid = 'public.contrato_titulares'::regclass
      and not t.tgisinternal and p.proname in ('log_audit_change','log_audit_crm')
  ) then
    raise exception 'public.contrato_titulares YA tiene auditor: re-basar antes de aplicar';
  end if;
  if exists (
    select 1 from pg_catalog.pg_trigger t
    join pg_catalog.pg_proc p on p.oid = t.tgfoid
    where t.tgrelid = 'crm.actividades_cliente'::regclass
      and not t.tgisinternal and p.proname in ('log_audit_change','log_audit_crm')
  ) then
    raise exception 'crm.actividades_cliente YA tiene auditor: re-basar antes de aplicar';
  end if;

  -- Los dos auditores parciales siguen siendo parciales, y son los que creemos.
  -- tgtype: 1=FOR EACH ROW, 2=BEFORE, 4=INSERT, 8=DELETE, 16=UPDATE.
  select t.tgtype into v_tipo
  from pg_catalog.pg_trigger t
  where t.tgrelid = 'crm.actividades'::regclass and t.tgname = 'trg_audit_actividades';
  if v_tipo is null then
    raise exception 'no existe trg_audit_actividades: re-basar antes de aplicar';
  end if;
  if v_tipo <> 5 then  -- AFTER (sin bit 2) + ROW (1) + INSERT (4)
    raise exception 'trg_audit_actividades ya no es AFTER INSERT FOR EACH ROW (tgtype %)', v_tipo;
  end if;

  -- Y el trigger nuevo de la gestion del lead no puede existir ya.
  if exists (
    select 1 from pg_catalog.pg_trigger t
    where t.tgrelid = 'crm.actividades'::regclass
      and t.tgname = 'trg_audit_actividades_cambio_baja'
  ) then
    raise exception 'trg_audit_actividades_cambio_baja ya existe: re-basar antes de aplicar';
  end if;

  -- El auditor de cuotas sigue siendo el de la auditoria del portal del 13/06,
  -- con su WHEN intacto. No se toca, pero si cambio hay que enterarse.
  select t.tgtype into v_tipo
  from pg_catalog.pg_trigger t
  where t.tgrelid = 'public.cronograma_pagos'::regclass and t.tgname = 'trg_audit_cronograma_pago';
  if v_tipo is null then
    raise exception 'no existe trg_audit_cronograma_pago: re-basar antes de aplicar';
  end if;
  if v_tipo <> 17 then  -- AFTER + ROW (1) + UPDATE (16)
    raise exception 'trg_audit_cronograma_pago ya no es AFTER UPDATE FOR EACH ROW (tgtype %)', v_tipo;
  end if;
  -- Su clausula WHEN tiene que seguir nombrando las cuatro casillas de pago.
  -- Se comprueba por contenido y no por parentesis: la forma exacta que imprime
  -- pg_get_triggerdef es cosa suya, los cuatro campos son cosa nuestra.
  select t.oid into v_trg from pg_catalog.pg_trigger t
  where t.tgrelid = 'public.cronograma_pagos'::regclass
    and t.tgname = 'trg_audit_cronograma_pago';
  v_def := pg_catalog.pg_get_triggerdef(v_trg);
  if v_def is null
     or strpos(v_def, 'WHEN (') = 0
     or strpos(v_def, 'old.estado IS DISTINCT FROM new.estado') = 0
     or strpos(v_def, 'old.monto_pagado IS DISTINCT FROM new.monto_pagado') = 0
     or strpos(v_def, 'old.fecha_pago_real IS DISTINCT FROM new.fecha_pago_real') = 0
     or strpos(v_def, 'old.registrado_por IS DISTINCT FROM new.registrado_por') = 0 then
    raise exception 'el WHEN de trg_audit_cronograma_pago no es el esperado: revisar antes de aplicar. Vivo: %', v_def;
  end if;

  -- Y el trigger nuevo de alta/baja no puede existir ya.
  if exists (
    select 1 from pg_catalog.pg_trigger t
    where t.tgrelid = 'public.cronograma_pagos'::regclass
      and t.tgname = 'trg_audit_cronograma_pago_alta_baja'
  ) then
    raise exception 'trg_audit_cronograma_pago_alta_baja ya existe: re-basar antes de aplicar';
  end if;
end
$preflight$;

-- == 1. Co-titulares: el rastro que faltaba ==================================
create trigger trg_audit_contrato_titulares
  after insert or update or delete on public.contrato_titulares
  for each row execute function public.log_audit_change();

-- == 2. Historial de gestion del cliente =====================================
create trigger trg_audit_actividades_cliente
  after insert or update or delete on crm.actividades_cliente
  for each row execute function private.log_audit_crm();

-- == 3. Gestion del lead: el cambio y el borrado, que era el hueco ===========
-- Trigger APARTE, no un reemplazo del que ya audita el alta: asi no se toca un
-- objeto vivo de una tabla con 3.952 filas ni se arriesga a perder nada suyo.
-- Para UPDATE y DELETE es el unico trigger de la tabla, asi que el orden de
-- disparo del alta (`trg_audit_actividades` antes que `trg_zy_...` y
-- `trg_zz_...`) queda exactamente como estaba.
create trigger trg_audit_actividades_cambio_baja
  after update or delete on crm.actividades
  for each row execute function private.log_audit_crm();

-- == 4. Cuotas de pago: el alta y la baja, que era el hueco =================
-- Trigger APARTE, para no tocar el de UPDATE y su WHEN (ver la cabecera). Se
-- audita tambien el alta y no solo el borrado -que es el hueco probatorio- para
-- que una cuota que aparece de la nada tenga la misma explicacion que una que
-- desaparece; ademas es lo que permite leer la regeneracion masiva del
-- cronograma (DELETE+INSERT) como lo que es. El coste es una fila por cuota
-- creada o borrada: un contrato escribe una decena, no miles.
create trigger trg_audit_cronograma_pago_alta_baja
  after insert or delete on public.cronograma_pagos
  for each row execute function public.log_audit_change();

-- == Postflight: los cuatro auditores existen y miran los tres eventos =======
do $postflight$
declare
  v_faltan text[] := '{}';
  v_par    record;
begin
  for v_par in
    select * from (values
      ('public.contrato_titulares', 'trg_audit_contrato_titulares'),
      ('crm.actividades_cliente',   'trg_audit_actividades_cliente')
    ) as v(tabla, trigger_)
  loop
    if not exists (
      select 1 from pg_catalog.pg_trigger t
      where t.tgrelid = v_par.tabla::regclass
        and t.tgname = v_par.trigger_
        and t.tgenabled = 'O'
        and t.tgtype = 29  -- AFTER + ROW(1) + INSERT(4) + DELETE(8) + UPDATE(16)
    ) then
      v_faltan := v_faltan || (v_par.tabla || '.' || v_par.trigger_);
    end if;
  end loop;
  if array_length(v_faltan, 1) is not null then
    raise exception 'POSTFLIGHT: auditores incompletos -> %', array_to_string(v_faltan, ', ');
  end if;

  -- Gestion del lead: el nuevo mira cambio y baja (tgtype 25 = AFTER + ROW(1) +
  -- DELETE(8) + UPDATE(16)) y el que auditaba el alta sigue intacto.
  if not exists (
    select 1 from pg_catalog.pg_trigger t
    where t.tgrelid = 'crm.actividades'::regclass
      and t.tgname = 'trg_audit_actividades_cambio_baja'
      and t.tgenabled = 'O' and t.tgtype = 25
  ) then
    raise exception 'POSTFLIGHT: falta el auditor de cambio/baja de la gestion del lead';
  end if;
  if not exists (
    select 1 from pg_catalog.pg_trigger t
    where t.tgrelid = 'crm.actividades'::regclass
      and t.tgname = 'trg_audit_actividades' and t.tgtype = 5
  ) then
    raise exception 'POSTFLIGHT: el auditor del alta de la gestion del lead ya no es AFTER INSERT';
  end if;

  -- Cuotas: el nuevo mira alta y baja (tgtype 13 = AFTER + ROW + INSERT +
  -- DELETE) y el viejo sigue vivo, con su WHEN.
  if not exists (
    select 1 from pg_catalog.pg_trigger t
    where t.tgrelid = 'public.cronograma_pagos'::regclass
      and t.tgname = 'trg_audit_cronograma_pago_alta_baja'
      and t.tgenabled = 'O' and t.tgtype = 13
  ) then
    raise exception 'POSTFLIGHT: falta el auditor de alta/baja de cuotas';
  end if;
  if not exists (
    select 1 from pg_catalog.pg_trigger t
    where t.tgrelid = 'public.cronograma_pagos'::regclass
      and t.tgname = 'trg_audit_cronograma_pago'
      and t.tgqual is not null
  ) then
    raise exception 'POSTFLIGHT: el auditor de UPDATE de cuotas perdio su clausula WHEN';
  end if;

  raise notice 'POSTFLIGHT OK: 4 auditores nuevos, ninguno recreado, y el WHEN del UPDATE de cuotas intacto';
end
$postflight$;
