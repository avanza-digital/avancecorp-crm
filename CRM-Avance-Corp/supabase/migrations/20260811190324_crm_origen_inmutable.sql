-- ============================================================================
-- Migración D — el ORIGEN de un lead no se cambia después del alta
--   (SIN cambio de esquema · SIN escritura de datos permanente · 1 función)
-- ============================================================================
-- Responde a la §3.4 del plan «Conversión mensual - plan de implementación»
-- (vault, 2026-08-11). Va SIEMPRE después de la migración A
-- (`20260811154434_crm_conversion_mensual_ponderada.sql`).
--
-- SUSTITUYE ENTERA a `20260811164017_crm_origen_inmutable_correccion_gerencia.sql`
-- (descartada por Miguel el 2026-08-11: quedarse con la mitad simple). Ese
-- fichero HAY QUE BORRARLO DEL ÁRBOL ANTES de crear el branch — ver «Nota de
-- aplicación», punto 1; no es opcional y no basta con ignorarlo.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- QUÉ HACE, EN UNA FRASE
-- ─────────────────────────────────────────────────────────────────────────────
-- Añade UN bloque a `private.leads_before_update()`: si un UPDATE mueve
-- `crm.leads.origen`, la transacción aborta con `P0409` y un mensaje que dice el
-- valor viejo, el nuevo y por dónde sí se elige el origen.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- QUÉ PROTEGE DE VERDAD — y qué NO protege, porque ya estaba protegido
-- ─────────────────────────────────────────────────────────────────────────────
-- ⚠️ Corrección sobre el borrador de esta misma migración, que decía que sin
-- este sello «se movería el divisor de un mes ya contado». **Es falso**, y
-- conviene tenerlo claro antes de leer el resto:
--
-- · El divisor y el numerador de la conversión mensual salen del SNAPSHOT
--   `crm.lead_asignaciones.origen` (migración A, `la.origen` en las líneas 519 y
--   544), NO de la ficha. Y ese snapshot ya era inmutable ANTES de esta
--   migración: `private.trg_lead_asignaciones_inmutables` lista
--   `old.origen is distinct from new.origen` dentro de «La fotografia de un
--   episodio es inmutable», rechaza toda escritura cuando
--   `old.finalizado_en is not null` («Un episodio cerrado es inmutable») y exige
--   `crm.ledger_writer = 'on'` con `pg_trigger_depth() >= 2`. Encima,
--   `crm.lead_asignaciones` no tiene NINGÚN grant para `authenticated`, `anon`
--   ni `service_role`. Un mes ya contado no estaba en riesgo, y esta migración
--   no es lo que lo salva.
--
-- Lo que este sello SÍ cierra son los dos caminos que quedaban abiertos, ambos
-- verificados contra producción el 2026-08-11:
--
--   (1) **El origen de los episodios FUTUROS del mismo lead.** `private.
--       trg_leads_asignaciones` abre cada episodio nuevo copiando `new.origen`
--       de la ficha (`insert into crm.lead_asignaciones (... origen ...) values
--       (... new.origen ...)`). Aparcar un lead (cierra episodio), cambiarle el
--       origen a 'referido' y reasignarlo abría un episodio nuevo marcado como
--       referido — y ESE sí sale del divisor del mes en curso. Es el agujero
--       real, y es del futuro, no del pasado.
--   (2) **`referidos.dados_de_alta`**, el único número del payload que lee la
--       columna viva (migración A, CTE `alta_referidos`, líneas 855-866:
--       `from crm.leads l where l.origen = 'referido'`, agrupado por
--       `creado_por` y filtrado por `creado_en`). La propia A lo declara «FUERA
--       de la aritmetica, como dato al lado» precisamente porque no es
--       reproducible hacia atrás: cambiar la ficha hoy mueve ese bloque en el
--       mes de ALTA del lead, aunque ese mes ya esté cerrado.
--
-- Con la regla T10 el origen dejó de ser una etiqueta informativa. Sigue siendo
-- cierto que mueve el porcentaje de alguien; lo que no es cierto es que lo
-- mueva reescribiendo la historia.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- LO QUE ESTA MIGRACIÓN **NO** CONSIGUE — léase antes que nada
-- ─────────────────────────────────────────────────────────────────────────────
-- · **El origen se ELIGE en el alta, y ese camino queda ABIERTO.**
--   `crm.crear_lead_si_disponible` es ejecutable por `authenticated`
--   (`proacl = authenticated=X/postgres`, verificado el 2026-08-11), su gate
--   admite el rol `vendedor` y valida `p_origen` sólo contra el dominio de 8
--   valores del CHECK `leads_origen_check` ('referido','landing','formulario',
--   'oficina','otro','web','campania','whatsapp'). Un analista puede, por tanto,
--   **dar de alta como 'referido'** los leads que no espera cerrar y sacarlos de
--   su propio divisor desde el primer segundo. Sellar el UPDATE impide
--   REESCRIBIR el origen después; no impide ELEGIRLO mal al nacer. Cerrar esa
--   puerta es otra migración, sobre otra función, y exige que Miguel decida qué
--   rol puede declarar un referido.
--
-- · **El sello NO alcanza a una sesión SQL directa, y es deliberado.**
--   ⚠️ Corrección sobre el borrador, que afirmaba «no hay corrección posible por
--   la API; ni gerencia, ni `service_role`, ni el SQL editor». La segunda mitad
--   es falsa y se comprobó ejecutándola en un PostgreSQL 16.14 efímero:
--   `crm.op_privilegiada` es un GUC *placeholder* (prefijo sin extensión que lo
--   registre), o sea USERSET, así que CUALQUIER sesión —incluido un rol no
--   superusuario como `authenticated`— puede armarlo ella misma con un simple
--   `set crm.op_privilegiada = 'on'` y luego mover el origen. Reproducido:
--   `set role authenticated` → el UPDATE devuelve P0409; `set
--   crm.op_privilegiada='on'` → el MISMO UPDATE devuelve `UPDATE 1`.
--   Lo que el sello sí cierra por completo es **PostgREST**: un cliente HTTP no
--   puede emitir `SET`, `set_config` vive en `pg_catalog` (no expuesto) y
--   ninguna RPC del CRM arma ese GUC salvo `crm.convertir_lead`, que no toca
--   `origen` en ninguna de sus sentencias (verificado: sólo tres funciones en
--   toda la base mencionan `crm.op_privilegiada` — `crm.convertir_lead`,
--   `private.leads_before_insert` y `private.leads_before_update`).
--   O sea: bloqueado para el front y para cualquier cliente de la API; abierto,
--   a propósito, para quien pueda escribir SQL directo. Es exactamente la misma
--   válvula que ya tienen hoy `perfil_id`, `contrato_id` y `convertido_en`, y es
--   la que evita que el dato quede incorregible para siempre.
--
--   ✗ **NO se añade `revoke update (origen) on crm.leads from authenticated`.**
--   Sería un no-op silencioso, y también se comprobó ejecutándolo: `crm.leads`
--   tiene el UPDATE concedido a nivel de TABLA
--   (`relacl = {postgres=arwdDxtm/postgres,authenticated=rw/postgres,
--   service_role=arwd/postgres}`), y PostgreSQL **no puede revocar por columna
--   un privilegio que viene del grant de tabla**: el REVOKE reporta éxito, el
--   `attacl` de `origen` sigue vacío y `has_column_privilege('authenticated',
--   'crm.leads','origen','UPDATE')` sigue devolviendo `true`. Para que sirviera
--   habría que revocar el UPDATE de tabla y re-concederlo columna a columna
--   sobre las 33 columnas: un cambio de grants grande, con su propio ciclo de
--   `auditor-rls`, que no cabe en esta migración. El trigger cubre el caso.
--
-- · **La corrección de gerencia queda APARCADA** (decisión de Miguel, 2026-08-11).
--   La versión descartada daba a gerencia una ventana de 24 h para corregir el
--   origen y propagaba la corrección al snapshot del ledger. Toda su complejidad
--   —y los cuatro reparos del auditor: concurrencia del carve-out, orden de
--   triggers, debilitamiento de «un episodio cerrado es inmutable», y el bug de
--   la ventana que cruza el fin de mes y mueve un mes ya cerrado— nacía de esa
--   ventana. Y resolvía un problema que **no existe**: en todo
--   `public.audit_log` hay **CERO** cambios históricos de `origen` (verificado en
--   producción el 2026-08-11). Se aparca hasta que aparezca el primer caso real.
--   Si vuelve, vuelve como diseño propio, no como carve-out del ledger.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- COLOCACIÓN: EL SELLO VA **DEBAJO** DEL GATE `crm.op_privilegiada`
-- ─────────────────────────────────────────────────────────────────────────────
-- ⚠️ Corrección sobre el borrador, que justificaba esto diciendo que «la versión
-- anterior puso el sello POR ENCIMA del gate y el auditor lo marcó como GRAVE».
-- Releído el fichero descartado: su condición es
-- `if not v_priv and new.origen is distinct from old.origen` (línea 508), o sea
-- que TAMBIÉN estaba debajo del gate. No se le atribuye aquí un defecto que no
-- tiene; la colocación se defiende por sí sola:
--
-- Encima del gate el dato quedaría **incorregible para siempre** —ninguna RPC
-- del owner, ninguna migración de backfill, nadie— y el único remedio sería
-- `alter table crm.leads disable trigger` en producción, que CLAUDE.md prohíbe.
-- Debajo del gate, el sello se comporta como las otras dos protecciones
-- condicionadas de esta misma función (la guardia de conversión y la
-- restauración de `perfil_id`/`contrato_id`/`convertido_en`): bloquea todo lo
-- que llega por la API y deja una vía al SQL directo. El preflight (0.6)
-- comprueba, además, que el GUC no venga armado ni de la sesión ni de
-- `pg_db_role_setting` — porque un `alter role authenticated set
-- crm.op_privilegiada = 'on'` no desarmaría sólo este sello, sino también la
-- prohibición de convertir por UPDATE y la restauración de `perfil_id`.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- LOS DOS ESCRITORES DE PAYLOAD COMPLETO QUE MANDAN `origen` — y por qué NO se
-- les exceptúa
-- ─────────────────────────────────────────────────────────────────────────────
-- El auditor avisó de que dos escritores legítimos mandan `origen` dentro de un
-- UPDATE de payload completo como `service_role`. Es CIERTO, y son éstos dos
-- (rastreados en el repo el 2026-08-11; no hay un tercero):
--
--   1. `supabase/scripts/seed-demo.mjs` → `ensureLead()` (líneas 261-284):
--      arma un `payload` con `origen: 'oficina'` y, si el lead ya existe,
--      ejecuta `.update(payload).eq('id', id)`.
--   2. `supabase/scripts/test-rls.mjs` → `restoreSeedIfNeeded()` (611-690):
--      `businessState()` copia 18 columnas —`origen` incluido— y las reescribe
--      con `.update(businessState(original))` cuando el fixture se desvió.
--
-- Ninguna EDGE FUNCTION escribe `crm.leads.origen`: `crm-importar-leads` sólo
-- hace `.insert()` (index.ts:485) y `crm-convertir-lead` lee el lead y delega en
-- la RPC `crm.convertir_lead`. El puente `scripts/puente-drive-origen.gs` no
-- toca la base: sólo escribe filas en la hoja de cálculo. Y en el front,
-- `actualizarLead` manda un parche PARCIAL y el único formulario que lo llama
-- (`components/app/lead-drawer.tsx:935`) **no incluye `origen`** en el payload.
--
-- DECISIÓN: **no se les exceptúa**. La condición del sello es
-- `new.origen is distinct from old.origen`, que es FALSA cuando el payload
-- reenvía el mismo valor — y los dos escritores reenvían siempre el mismo valor
-- por construcción:
--   · `seed-demo` escribe literalmente `'oficina'` tanto en el INSERT como en el
--     UPDATE, así que el valor que manda es el que la fila ya tiene;
--   · `test-rls` restaura el valor ORIGINAL leído del fixture, es decir el mismo,
--     salvo que algo lo hubiera cambiado — y después de esta migración nada lo
--     cambia por la API, así que ese «salvo» deja de ser alcanzable desde el
--     único sitio desde el que el gate corre.
-- Exceptuarlos explícitamente (por rol, por GUC o por nombre) sería abrir un
-- boquete permanente para `service_role` a cambio de nada: el caso que
-- preocupaba ya está cubierto por la semántica de `is distinct from`. El
-- postflight (2) lo demuestra ejecutando ese UPDATE, no razonándolo.
-- ⚠️ Único borde que queda vivo: `seed-demo.ensureLead()` localiza el lead POR
-- TELÉFONO; si algún día ese teléfono cayera en una fila con otro origen, el
-- seed abortaría con `P0409` en vez de pisarlo en silencio. Es el comportamiento
-- correcto —el arreglo va en el script, que es un fixture— y hoy no ocurre:
-- todos los leads del fixture nacen y se restauran con `'oficina'`.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- POR QUÉ EXCEPCIÓN Y NO RESTAURACIÓN MUDA — y qué llega hoy al usuario
-- ─────────────────────────────────────────────────────────────────────────────
-- La casa restaura en silencio sus columnas inmutables (`id`, `creado_por`,
-- `creado_en` aquí mismo; `ciclo_actual` en `trg_leads_00_guard_tenencia`;
-- `sla_global_*` en `trg_leads_01_sla_global`; `clasificacion_auto` y
-- `descartado_*` en `trg_leads_zz_sello_descarte`; `tenencia_desde` en
-- `trg_leads_zzz_tenencia_desde`). **Ese patrón se conserva INTACTO**: esta
-- migración no toca ni una de esas restauraciones.
--
-- `origen` se sella con EXCEPCIÓN por honestidad. Un 200 mudo dejaría a quien lo
-- intentó creyendo que corrigió: `aplicar()` es optimista en el store del front,
-- así que vería el valor nuevo en pantalla y cerraría la pestaña convencida de
-- que el lead salió del divisor. Con la excepción, el intento aborta.
--
-- SQLSTATE `P0409`, siguiendo el vocabulario que la casa ya usa para sus errores
-- propios (`P0429` en el reparto, `P0481` en la disponibilidad): `P0` + el número
-- HTTP que describe el caso (409 Conflict). NO se reutiliza `P0002`
-- (`no_data_found`): es el código que PL/pgSQL genera solo cuando un
-- `select ... into strict` no encuentra filas, y confundirlos haría que una
-- invariante rota se leyera como una regla de negocio.
--
-- ⚠️ Corrección sobre el borrador, que afirmaba que «el front distingue por
-- `error.code`». **Hoy NO lo distingue.** `aErrorApi`
-- (`app/src/data/crm-api.ts:954-1012`) ramifica 23505, 23502/23514,
-- 42501/PGRST301, P0429, P0002, 40001, P0481 y P0001/22023 — y nada más. Un
-- `P0409` cae al `else` y sale como `code = 'POSTGREST_ERROR'`,
-- `mensaje = 'No se pudo guardar el cambio.'`; peor,
-- `aResultadoPersistenciaFallida` excluye `POSTGREST_ERROR` por ser un mensaje
-- de lectura, así que el usuario vería un toast genérico, un 500 y un evento
-- Sentry `crm.mutacion_revertida`. Es tolerable **sólo** porque hoy ninguna
-- pantalla puede provocarlo (ningún formulario manda `origen` en un UPDATE):
-- esto es un backstop de servidor, no un mensaje de producto.
-- SEGUIMIENTO (front, fuera de esta migración): añadir en `aErrorApi` la rama
--   `else if (codigoPg === 'P0409') { code = 'ORIGEN_SELLADO'; if (error.message)
--    mensaje = error.message }`
-- el día que alguna pantalla pueda llegar a provocarlo.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- LO QUE NO CAMBIA
-- ─────────────────────────────────────────────────────────────────────────────
-- Ninguna tabla, ninguna columna, ningún grant, ninguna policy, ningún índice,
-- ningún trigger (se usa `create or replace function`, así que
-- `trg_leads_before_update` sigue siendo el mismo objeto) y ningún objeto de
-- `public`. **No se escribe NI UNA LÍNEA en `crm.lead_asignaciones`**: el
-- carve-out del ledger de la versión descartada desaparece por completo, y con
-- él los reparos del auditor sobre concurrencia, orden de triggers y meses
-- cerrados. El postflight lo COMPRUEBA contando el ledger dentro de la propia
-- subtransacción, no lo promete.
--
-- ⚠️ Matiz honesto sobre «ninguna fila de datos»: el postflight **sí** crea una
-- fila transitoria en `crm.leads` y, por `trg_audit_leads → private.
-- log_audit_crm`, cinco filas transitorias en `public.audit_log`. Las siete se
-- deshacen con la subtransacción. Lo único que sobrevive son huecos en las
-- secuencias (los `nextval` no son transaccionales), que es el precio de un
-- postflight que ejercita el comportamiento en vez de leer el `prosrc`. No es
-- DDL sobre `public`: es un INSERT que el propio trigger de auditoría de `crm`
-- ya hace en cada escritura normal del CRM.
--
-- Las protecciones que ya tenía `private.leads_before_update()` se reproducen
-- ÍNTEGRAS y EN EL MISMO ORDEN, y el preflight (0.4) lo verifica contra el
-- `prosrc` VIVO por md5, no por muestreo de frases.
-- ============================================================================

begin;

set local lock_timeout = '10s';

-- ---------------------------------------------------------------------------
-- 0. Preflight — sin estas piezas el reemplazo sería a ciegas
-- ---------------------------------------------------------------------------
do $preflight$
declare
  -- md5 del cuerpo VIVO de private.leads_before_update() en producción el
  -- 2026-08-11, normalizando los blancos:
  --   select md5(regexp_replace(prosrc, '\s+', ' ', 'g'))
  --   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  --   where n.nspname = 'private' and p.proname = 'leads_before_update';
  -- Es el pre-imagen EXACTO que la sección 1 reproduce (verificado montando ese
  -- cuerpo en un PostgreSQL 16.14 efímero: mismo md5).
  c_md5_esperado constant text := 'b280d0229cfb7f6ade5c162208593eb7';
  v_src text;
  v_md5 text;
begin
  -- (0.1) La función y su trigger existen y están VIVOS. Reemplazar el cuerpo de
  --       una función cuyo trigger está en 'D' (deshabilitado por un backfill que
  --       no lo volvió a encender) sería sellar una puerta que nadie vigila.
  if to_regprocedure('private.leads_before_update()') is null then
    raise exception 'Falta private.leads_before_update(): esta migracion reemplaza su cuerpo, no lo crea';
  end if;
  if not exists (
    select 1 from pg_catalog.pg_trigger t
    where t.tgrelid = 'crm.leads'::pg_catalog.regclass
      and t.tgname = 'trg_leads_before_update'
      and not t.tgisinternal
      and t.tgenabled = 'O'
  ) then
    raise exception 'trg_leads_before_update no existe o no esta habilitado sobre crm.leads';
  end if;

  -- (0.2) La migración DESCARTADA `20260811164017_crm_origen_inmutable_
  --       correccion_gerencia.sql` NO puede haberse aplicado antes que ésta.
  --       Su timestamp es ANTERIOR, así que `supabase db push` la aplicaría
  --       PRIMERO si sigue en el árbol, y el aborto de (0.3) llegaría cuando el
  --       diseño que Miguel rechazó ya estuviera vivo en el branch. Esto lo dice
  --       por su nombre y con el remedio, en vez de morir con un mensaje que
  --       hace pensar en otra cosa.
  if to_regprocedure('private.trg_leads_propagar_origen_snapshot()') is not null
     or exists (
       select 1 from pg_catalog.pg_trigger t
       where t.tgrelid = 'crm.leads'::pg_catalog.regclass
         and t.tgname = 'trg_leads_zy_origen_snapshot'
         and not t.tgisinternal
     ) then
    raise exception 'Se aplico la migracion DESCARTADA 20260811164017 (ventana de gerencia + carve-out del ledger): borrar ese fichero del arbol, tirar el branch y rehacerlo';
  end if;

  select p.prosrc into v_src
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private' and p.proname = 'leads_before_update';

  -- (0.3) Si el sello ya estuviera puesto, esta migración es un no-op peligroso.
  --       Se comprueba ANTES del md5 sólo para dar el diagnóstico preciso: el
  --       md5 también lo cazaría, pero diciendo «el cuerpo no coincide».
  if pg_catalog.strpos(v_src, 'new.origen is distinct from old.origen') > 0 then
    raise exception 'private.leads_before_update() ya sella el origen: esta migracion ya se aplico (o se aplico la version descartada)';
  end if;

  -- (0.4) El cuerpo vivo es BYTE A BYTE (salvo blancos) el que la sección 1
  --       reproduce. Este chequeo sustituye al muestreo de cinco frases que
  --       llevaba el borrador, que NO podía cumplir lo que su comentario
  --       prometía: buscar cadenas que este mismo fichero ya conoce es un test
  --       de PRESENCIA de lo viejo, jamás de AUSENCIA de lo nuevo. Una
  --       protección AÑADIDA después (un `new.no_contactar := old.no_contactar`,
  --       un hotfix cualquiera) dejaba las cinco cadenas intactas, el preflight
  --       pasaba y el `create or replace` la borraba EN SILENCIO de una función
  --       SECURITY DEFINER que custodia el camino de conversión a cliente.
  --       Reproducido en un PostgreSQL 16.14 efímero: con una sexta protección
  --       añadida, el chequeo viejo imprimía «PASA» y éste aborta.
  v_md5 := pg_catalog.md5(pg_catalog.regexp_replace(v_src, '\s+', ' ', 'g'));
  if v_md5 is distinct from c_md5_esperado then
    raise exception using
      errcode = 'P0001',
      message = 'El cuerpo vivo de private.leads_before_update() NO es el que esta migracion reproduce',
      detail  = pg_catalog.format('md5 esperado %s, md5 vivo %s', c_md5_esperado, v_md5),
      hint    = 'Alguien lo cambio despues del 2026-08-11. Diffear el prosrc vivo contra la seccion 1 '
                'de esta migracion, incorporar AQUI la proteccion nueva y recalcular el md5 esperado '
                'antes de volver a aplicar. No forzar: el create or replace borraria esa proteccion.';
  end if;

  -- (0.5) El postflight FABRICA un lead de usar y tirar dentro de una
  --       subtransacción que se deshace. Ese INSERT pasa por
  --       `trg_leads_02_sla_versionado`, que exige política SLA vigente y un
  --       tramo para la etapa 'nuevo'. Sin ellas el postflight abortaría por una
  --       razón que no tiene nada que ver con el origen; mejor decirlo aquí.
  if private.sla_politica_vigente(pg_catalog.now()) is null then
    raise exception 'No hay politica SLA vigente: el postflight no puede fabricar su lead de prueba';
  end if;
  if not exists (
    select 1 from crm.sla_politica_etapas pe
    where pe.politica_id = private.sla_politica_vigente(pg_catalog.now())
      and pe.etapa = 'nuevo'
  ) then
    raise exception 'La politica SLA vigente no cubre la etapa nuevo: el postflight no puede fabricar su lead de prueba';
  end if;

  -- (0.6) La válvula no puede venir armada de fábrica. Dos sitios, no uno:
  --       · la sesión que aplica la migración (postgresql.conf, PGOPTIONS…);
  --       · `pg_db_role_setting`, que es el que de verdad importa — un
  --         `alter role authenticated set crm.op_privilegiada = 'on'` deja el
  --         sello NACIENDO APAGADO para todo usuario de la API, y de paso
  --         desarma la prohibición de convertir por UPDATE y la restauración de
  --         perfil_id/contrato_id/convertido_en, que viven en el mismo `if not
  --         v_priv`. El borrador sólo miraba su propia sesión, que es la del
  --         owner: daba verde por accidente.
  --       Hoy está limpio (consultado en producción el 2026-08-11: las únicas
  --       entradas son statement_timeout, search_path, log_statement,
  --       session_preload_libraries, lock_timeout, idle_in_transaction_session_
  --       timeout, default_transaction_read_only y app.settings.jwt_exp).
  if coalesce(current_setting('crm.op_privilegiada', true), 'off') = 'on' then
    raise exception 'crm.op_privilegiada viene armado en esta sesion: el sello nace apagado';
  end if;
  if exists (
    select 1
    from pg_catalog.pg_db_role_setting s,
         lateral pg_catalog.unnest(s.setconfig) as c(v)
    where c.v like 'crm.op_privilegiada=%'
  ) then
    raise exception 'crm.op_privilegiada esta fijado en pg_db_role_setting (por rol o por base): el sello nacería apagado para ese rol';
  end if;

  -- (0.7) La migración se aplica SIN sesión humana. El postflight fabrica un
  --       lead sin analista y sin bandeja; con `auth.uid()` no nulo,
  --       `private.trg_leads_guard_tenencia` lo rechazaría con «Solo Gerencia
  --       puede dejar un lead en la cola global» (o
  --       `trg_leads_00_disponibilidad_insert` con 42501 «Acceso CRM revocado»),
  --       y la migración moriría con un mensaje que no habla del origen.
  if (select auth.uid()) is not null then
    raise exception 'Esta migracion se aplica sin sesion (auth.uid() debe ser NULL): el postflight fabrica un lead en cola global y trg_leads_00_guard_tenencia lo rechazaria';
  end if;
end;
$preflight$;

-- ---------------------------------------------------------------------------
-- 1. `private.leads_before_update()` — cuerpo ÍNTEGRO de producción + el sello
--
--    Todo lo que sigue es el cuerpo real (pg_get_functiondef, 2026-08-11) salvo
--    el bloque marcado «SELLO DEL ORIGEN»; el preflight (0.4) lo ancla por md5.
--    Las protecciones existentes quedan en el MISMO ORDEN:
--      (P1) restaurar id / creado_por / creado_en y sellar actualizado_en;
--      (P2) [sin válvula privilegiada] prohibir la conversión por UPDATE;
--      (P3) [sin válvula privilegiada] restaurar perfil_id / contrato_id /
--           convertido_en;
--      (P4) [siempre] un lead convertido debe tener perfil_id.
--    El sello entra como (P3-bis), al final del bloque `if not v_priv`, para no
--    alterar el orden de ninguna de las cuatro.
-- ---------------------------------------------------------------------------
create or replace function private.leads_before_update()
returns trigger
language plpgsql
security definer
set search_path to 'crm', 'public'
as $function$
declare
  v_priv boolean := coalesce(current_setting('crm.op_privilegiada', true) = 'on', false);
begin
  -- Columnas inmutables: restaurar siempre desde OLD.
  new.id := old.id;
  new.creado_por := old.creado_por;
  new.creado_en := old.creado_en;
  new.actualizado_en := now();

  -- Conversión y enlace al portal: SOLO desde una RPC privilegiada
  -- (que fija crm.op_privilegiada='on'). Un cliente API no puede convertir
  -- ni enlazar perfil_id/contrato_id a mano.
  if not v_priv then
    if new.etapa = 'convertido' and old.etapa <> 'convertido' then
      raise exception 'La conversión a cliente solo se hace vía la operación de conversión';
    end if;
    new.perfil_id := old.perfil_id;
    new.contrato_id := old.contrato_id;
    new.convertido_en := old.convertido_en;

    -- ── SELLO DEL ORIGEN (migración D, 2026-08-11) ────────────────────────
    -- El origen se elige al ALTA y no se vuelve a mover. Lo que esto protege
    -- NO es un mes ya contado —el snapshot `lead_asignaciones.origen` ya era
    -- inmutable por `trg_lead_asignaciones_00_inmutables`— sino dos cosas del
    -- presente y del futuro:
    --   · el origen que copiará `private.trg_leads_asignaciones` al abrir el
    --     PRÓXIMO episodio de este lead (y ése sí sale del divisor del mes en
    --     curso si dice 'referido');
    --   · el bloque `referidos.dados_de_alta`, único número del payload que
    --     lee esta columna viva, agrupado por el mes de ALTA del lead.
    -- Se avisa con EXCEPCIÓN en vez de restaurar en silencio porque el store
    -- del front es optimista: un 200 mudo dejaría al usuario convencido de
    -- que corrigió.
    -- Va DENTRO de `if not v_priv`, a propósito: encima del gate el dato
    -- quedaría incorregible para siempre y el único remedio sería
    -- `disable trigger` en producción, que CLAUDE.md prohíbe.
    -- `is distinct from` (y no `<>`) hace que un UPDATE de payload completo que
    -- reenvía el MISMO valor no lance nada: es el caso de seed-demo.mjs y de
    -- test-rls.mjs, los dos únicos escritores que mandan `origen` en un UPDATE.
    if new.origen is distinct from old.origen then
      raise exception using
        errcode = 'P0409',
        message = 'El origen de un lead no se cambia despues del alta',
        detail  = pg_catalog.format(
          'lead %s: origen actual %L, intento %L',
          old.id, old.origen, new.origen),
        hint    = 'El origen se elige al crear el lead (crm.crear_lead_si_disponible). '
                  'La conversion mensual lee la FOTO del episodio, que ya es inmutable: '
                  'cambiar la ficha no mueve ningun mes ya contado, pero si moveria el '
                  'origen de los episodios FUTUROS de este lead y el bloque de referidos '
                  'dados de alta de su mes de creacion.';
    end if;
  end if;

  -- Invariante de negocio en la transición (no como CHECK de tabla):
  if new.etapa = 'convertido' and new.perfil_id is null then
    raise exception 'Un lead convertido debe estar enlazado a un perfil de cliente';
  end if;

  return new;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 2. Postflight — se EJERCITA el comportamiento, no se lee el cuerpo
--
--    Todo ocurre dentro de una subtransacción PL/pgSQL que SIEMPRE se deshace
--    (el `raise` con `P0999` la aborta y el handler la absorbe). Las variables
--    PL/pgSQL NO se revierten con la subtransacción, así que los veredictos
--    sobreviven al rollback y se comprueban fuera.
--
--    Las cinco cosas que se prueban, TODAS medidas DENTRO de la subtransacción
--    (una comprobación hecha después del rollback compararía el mundo consigo
--    mismo y no podría fallar nunca — el defecto que tenía el residuo del
--    borrador):
--      (1) cambiar el origen FALLA con P0409;
--      (2) reenviar el MISMO origen PASA  → los dos escritores de payload
--          completo (seed-demo, test-rls) siguen funcionando sin excepción;
--      (3) mover OTRA columna PASA        → el sello no bloquea la edición;
--      (4) con `crm.op_privilegiada='on'` el cambio PASA → el sello está DEBAJO
--          del gate y el dato no queda incorregible (el reparo grave del auditor);
--      (5) `crm.lead_asignaciones` no ha ganado NI UNA FILA → la promesa
--          «no se escribe una línea en el ledger» queda comprobada, no prometida.
--          Ésta sí puede fallar: si el INSERT del lead abriera episodio (o si
--          alguna de las cuatro escrituras tocara el ledger), el conteo diferiría.
--    Probado en un PostgreSQL 16.14 efímero con los controles negativos: sin el
--    sello falla (1); con el sello encima del gate falla (4). Un postflight que
--    no puede fallar no prueba nada.
-- ---------------------------------------------------------------------------
do $postflight$
declare
  v_id           uuid;
  v_tel          text;
  v_asig_antes   bigint;
  v_asig_dentro  bigint;
  v_rechazo_ok   boolean := false;
  v_mismo_ok     boolean := false;
  v_otra_ok      boolean := false;
  v_valvula_ok   boolean := false;
  v_ledger_ok    boolean := false;
  v_origen_final text;
begin
  select count(*) into v_asig_antes from crm.lead_asignaciones;

  begin
    -- Teléfono sintético libre (formato +519########, el que exige
    -- private.trg_leads_disponibilidad_atomica).
    for i in 1..200 loop
      v_tel := '+519' || pg_catalog.lpad((90000000 + i)::text, 8, '0');
      exit when not exists (select 1 from crm.leads l where l.telefono = v_tel);
      v_tel := null;
    end loop;
    if v_tel is null then
      raise exception 'Postflight: no queda telefono sintetico libre para la prueba';
    end if;

    -- Sin analista ni bandeja: así el AFTER `trg_leads_asignaciones` no abre
    -- episodio (`v_new_debe_tener` exige vendedor_id no nulo) y el ledger no se
    -- toca ni siquiera dentro de la subtransaccion que se deshace. El veredicto
    -- (5) lo comprueba en vez de darlo por hecho.
    insert into crm.leads (
      nombre_completo, telefono, origen, etapa, monto_estimado, moneda,
      vendedor_id, asignado_supervisor_id, activo
    ) values (
      'POSTFLIGHT origen inmutable', v_tel, 'otro', 'nuevo', 1000, 'PEN',
      null, null, true
    )
    returning id into v_id;

    -- (1) cambiar el origen DEBE fallar con P0409
    begin
      update crm.leads set origen = 'referido' where id = v_id;
    exception when sqlstate 'P0409' then
      v_rechazo_ok := true;
    end;

    -- (2) reenviar el MISMO origen dentro de un payload con otras columnas
    --     DEBE pasar (el caso de seed-demo.mjs y test-rls.mjs)
    update crm.leads
       set origen = 'otro', nota = 'postflight D (2)', monto_estimado = 1500
     where id = v_id;
    v_mismo_ok := true;

    -- (3) mover OTRA columna DEBE pasar
    update crm.leads set nota = 'postflight D (3)' where id = v_id;
    v_otra_ok := true;

    -- (4) la válvula privilegiada SÍ puede corregir (el sello va DEBAJO del gate).
    --     El P0409 se captura a propósito: si el sello estuviera ENCIMA del gate,
    --     este update reventaría y sin el `exception` la migración moriría con el
    --     mensaje del sello, que no dice cuál es el defecto. Capturándolo, muere
    --     con «Postflight (4)», que sí lo dice.
    begin
      perform pg_catalog.set_config('crm.op_privilegiada', 'on', true);
      update crm.leads set origen = 'referido' where id = v_id;
      select l.origen into v_origen_final from crm.leads l where l.id = v_id;
      v_valvula_ok := (v_origen_final = 'referido');
    exception when sqlstate 'P0409' then
      v_valvula_ok := false;
    end;
    perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);

    -- (5) el ledger no se ha tocado. Se mide AQUÍ, con la fila de prueba todavía
    --     viva: medirlo después del rollback sería comparar el mundo consigo
    --     mismo.
    select count(*) into v_asig_dentro from crm.lead_asignaciones;
    v_ledger_ok := (v_asig_dentro = v_asig_antes);

    -- Deshacer la subtransacción entera: el lead de prueba no existe.
    raise exception using errcode = 'P0999', message = 'postflight: deshacer';
  exception
    when sqlstate 'P0999' then
      perform pg_catalog.set_config('crm.op_privilegiada', 'off', true);
  end;

  if not v_rechazo_ok then
    raise exception 'Postflight (1): cambiar crm.leads.origen NO fue rechazado con P0409';
  end if;
  if not v_mismo_ok then
    raise exception 'Postflight (2): reenviar el MISMO origen fue rechazado — rompe seed-demo y test-rls';
  end if;
  if not v_otra_ok then
    raise exception 'Postflight (3): un UPDATE de otra columna fue rechazado';
  end if;
  if not v_valvula_ok then
    raise exception 'Postflight (4): con crm.op_privilegiada=on el origen NO se pudo corregir — el sello quedo ENCIMA del gate';
  end if;
  if not v_ledger_ok then
    raise exception 'Postflight (5): el postflight escribio en crm.lead_asignaciones (antes %, durante %) — esta migracion no debe tocar el ledger',
      v_asig_antes, v_asig_dentro;
  end if;

  raise notice 'Postflight D OK: origen sellado (P0409), mismo valor pasa, otra columna pasa, valvula privilegiada viva, ledger intacto';
end;
$postflight$;

commit;

-- ============================================================================
-- Nota de aplicacion — los puntos 1 y 2 son BLOQUEANTES y van ANTES del branch
-- ============================================================================
-- 1. BORRAR `supabase/migrations/20260811164017_crm_origen_inmutable_correccion_
--    gerencia.sql` del arbol. Es UNTRACKED y nunca se aplico, pero su timestamp
--    es ANTERIOR al de este fichero: si se deja, `supabase db push` lo aplica
--    PRIMERO y deja vivos en el branch la ventana de 24 h de gerencia, el
--    carve-out del ledger y el trigger `trg_leads_zy_origen_snapshot` — es
--    decir, justo el diseno que Miguel descarto. El preflight (0.2) de este
--    fichero lo DETECTA y lo nombra, pero detectar no es prevenir: para cuando
--    aborta, el branch ya esta contaminado y hay que tirarlo.
--
-- 2. ACTUALIZAR `supabase/migrations/MIGRACIONES.md`, que hoy apunta al fichero
--    descartado y no menciona ni a esta migracion ni a la C:
--      · fila 1449: `20260811164017 | crm_origen_inmutable (…_correccion_
--        gerencia.sql) | ESCRITA, SIN APLICAR` -> sustituir por
--        `20260811190324 | crm_origen_inmutable`, dejando constancia de que
--        164017 queda DESCARTADA y nunca se aplico;
--      · seccion 1685: reescribir para este fichero;
--      · anadir la fila de `20260811190310 | crm_ledger_cierres_integros`;
--      · linea 1798: la receta dice «aplicar (20260811154434 -> 20260811164017)»
--        y hay que corregirla al orden real
--        `20260811154434` (A) -> `20260811190310` (C) -> `20260811190324` (D).
--    ⚠️ La «Nota de aplicacion» de la migracion A (lineas 1279-1282) tambien
--    nombra el fichero descartado: corregirla en la misma pasada.
--
-- 3. Orden de despliegue: esta migracion va DESPUES de la A
--    (`20260811154434_crm_conversion_mensual_ponderada.sql`) y de la C
--    (`20260811190310_crm_ledger_cierres_integros.sql`), y ANTES de la F
--    (`20260811210049_crm_alta_manual_origen_restringido.sql`, la regla D8 del
--    alta, anadida el mismo dia). Las cuatro en el paso 1, en ese orden.
--
-- 4. Ciclo obligatorio (CLAUDE.md): branch de Supabase -> aplicar -> gate
--    `npm run test:rls:preflight` -> advisors -> merge. Prohibido
--    `apply_migration` directo a produccion.
--
-- 5. No hace falta `npm run gen:types`: no cambia el esquema (ni tablas, ni
--    columnas, ni firmas de RPC).
--
-- 6. Si el preflight (0.4) aborta por md5, NO tocar el hash a ojo: significa que
--    alguien cambio `private.leads_before_update()` despues del 2026-08-11.
--    Hay que diffear el prosrc vivo contra la seccion 1, INCORPORAR aqui la
--    proteccion nueva y recalcular el md5. Saltarse ese paso borra la proteccion
--    de una funcion SECURITY DEFINER que custodia la conversion a cliente.
