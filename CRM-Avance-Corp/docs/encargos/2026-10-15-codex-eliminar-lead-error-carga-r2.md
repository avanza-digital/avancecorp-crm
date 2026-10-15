ROLE: SECONDARY_REVIEWER.
Do not modify files. Do not implement the task. Do not invoke Claude. Do not delegate to another coding agent. Do not create another review chain.

# Encargo r2 (última, LEVEL 3): ¿quedaron cerrados tus hallazgos de r1? — migración «eliminar lead por error de carga»

En r1 diste CHANGES_REQUESTED con: [P1] carrera de copia (INSERT concurrente borrado sin copia), [P2] lista de FK solo por
pares de tablas, [P2] la llave aceptaba contención jsonb en vez de igualdad; y riesgos (aislamiento RR, `now()`, SET NULL
entre leads, identidad de triggers, dueños/ACL de los candados). El auditor RLS añadió: la copia era legible por la API
(gerencia), reversa a ciegas, INSERT de la copia podía filtrar PII en el DETAIL, permisos incompletos en postflight.
Abajo: el diff r1→r2 y la EVIDENCIA ejecutada en un banco Docker con el esquema de producción (huella de 1.049 funciones
crm+private idéntica a producción). Responde SOLO: ¿cada hallazgo de r1 quedó cerrado? ¿Introduce r2 algún defecto
nuevo? Mismo formato (VERDICT, SUMMARY, FINDINGS P0–P3 con línea/escenario, RISKS, NEXT ACTIONS, CONFIDENCE). No repitas lo
ya cerrado salvo para refutar el cierre con evidencia.

## Evidencia ejecutada (banco Docker, Postgres 17.6.1.105 de Supabase, misma huella que producción)
- Migración aplicada como `postgres` con preflight (12 huellas + identidad de 17 triggers) y postflight en verde:
  1049 → 1053 funciones.
- Pruebas `test-eliminar-lead.sql` (una transacción, ROLLBACK): **66 PASS / 0 FAIL / 0 NOT RUN**. Incluye: 7 roles negados
  (vendedor, supervisor, sin sesión, coordinador, directorio, gerencia dada de baja, admin inactivo) → 42501; motivo
  corto/nulo/501 y lead nulo → 22023; 18 rechazos P0409 aislados (conversión, contrato, >30 días, reserva, perfil,
  inversionista, resultado convertido, cierre externo, acreditación, cierre anulado, ajuste de mes, solicitud de tasa,
  solicitud de inversión de origen, inversionista_leads, inversionista_operaciones, búsqueda, gestión de inversionista,
  tarea de otro lead reagendada desde una suya); mes cerrado → P0409; FK nueva desconocida (tabla temporal en la
  transacción) → 55000; 13 DELETE directos sin la puerta siguen bloqueados con el mensaje original de cada candado;
  authenticated directo → permission denied; 8 copias TRUCADAS (control positivo que SÍ borra + fila distinta, campo de
  más, otra tabla, otro actor, permiso con otro lead, otra transacción, sin sesión → bloqueadas); borrado completo por
  gerencia (17 tablas, cuadre y copia con autor, rol y motivo normalizado), por admin y por superadmin; tras la puerta,
  fila de OTRO lead con el permiso puesto a mano → bloqueada; copia inmutable (DELETE/UPDATE/TRUNCATE → 42501);
  `listar_leads_eliminados`: gerencia 3 filas, admin y vendedor → 42501; lectura directa de la tabla por gerencia → 42501.
- Mutantes de la llave (`private.borrado_lead_error_autoriza`), suite completa por cada uno:
  M1 sin «permiso = lead» → cae «permiso con otro lead»; M2 sin transacción → cae «otra transacción»; M3 sin actor → cae
  «otro actor»; M4 contención en vez de igualdad → cae «campo de más»; M6 cualquier tabla → cae «otra tabla»;
  M5 sin «auth.uid() is not null» → SOBREVIVE (redundante: sin sesión ya falla `eliminado_por = auth.uid()`).
- Carrera real con DOS conexiones: B inserta `actividades_cliente` sobre la tarea del lead y espera 4 s sin confirmar; A
  llama a la puerta 1 s después. A esperó a B (terminó 15 ms después del COMMIT de B), la copia incluye la fila de B
  (`filas.actividades_cliente = 1`), y no quedó ninguna `actividades_cliente` de la tarea.
- Reversa: deja la huella EXACTA de producción (1049|b63cd6d3…) y retira la tabla vacía; la migración se reaplica idéntica
  (1053|fd70f262…); con un candado cambiado después, la reversa se NIEGA («un candado cambió después de la migración»).

## Diff r1 → r2 de la migración
```diff
--- /private/tmp/claude-501/-Users-usuario-Desktop-DESARROLLO-DESARROLLO-AVANCECORP-desktop-CRM-Avance-Corp/4a61db6e-962d-4064-b09d-4e141f11b367/scratchpad/migracion-r1.sql	2026-10-15 00:26:50
+++ /Users/usuario/dev/avancecorp-crm-eliminar-lead/CRM-Avance-Corp/supabase/migrations/20261015044917_crm_eliminar_lead_error_carga.sql	2026-10-15 00:17:28
@@ -13,8 +13,9 @@
 -- (20261005200945, private.inversion_eliminacion_autoriza).
 --
 -- QUÉ HACE
---   1. crm.leads_eliminados: copia inmutable (UPDATE, DELETE y TRUNCATE prohibidos para todos). RLS: solo SELECT, y solo
---      gerencia del CRM. Nadie la escribe salvo la puerta.
+--   1. crm.leads_eliminados: copia inmutable (UPDATE, DELETE y TRUNCATE prohibidos para todos). RLS sin políticas y sin
+--      grants, como crm.inversiones_eliminadas: la copia lleva filas crudas de tablas cerradas a la API (llamadas del
+--      celular, SLA, ledger). Gerencia la lee por la puerta crm.listar_leads_eliminados() (quién, cuándo, motivo, filas).
 --   2. private.borrado_lead_error_autoriza(tabla, fila): la llave de los candados.
 --   3. Los 8 candados que custodian filas del lead. Cuerpo de producción + 5 líneas al empezar; el postflight prueba que
 --      el resto quedó idéntico byte a byte:
@@ -41,7 +42,14 @@
 --          que crm.cerrar_periodo). Si algo falla → P0409 con TODAS las razones en el mensaje.
 --        · Fail-closed ante tablas nuevas: si aparece una llave foránea hacia el lead o sus filas que esta puerta no
 --          conoce → 55000 (no se borra nada sin copia).
---        · Copia → borra en orden → comprueba que no quedó nada.
+--        · Bloquea el lead y los padres de cada nivel → valida → copia (instantánea posterior a los bloqueos) → borra en
+--          orden → CUADRE: cada DELETE borró exactamente lo copiado; si no, 55000 y no se aplica nada.
+--        · Exige READ COMMITTED (cada sentencia ve lo confirmado tras los bloqueos y un cierre de mes recién sellado).
+-- r2 (auditor-rls y Codex r1, CHANGES_REQUESTED, sin P0): copia sin lectura directa (puerta de lectura); lista de llaves
+--   foráneas por columna y acción ON DELETE; llave por IGUALDAD jsonb (no contención); padres bloqueados antes de la
+--   copia + cuadre por row_count (carrera de un INSERT concurrente); rechazo si otro lead apunta a sus tareas o
+--   llamadas; candado de cierre de mes antes que las filas (mismo orden que crm.cerrar_periodo); INSERT de la copia sin
+--   detalle; pre/postflight de la identidad exacta de los 17 triggers, dueño y ACL de los candados, ACL de las puertas.
 --
 -- LLAVES FORÁNEAS HACIA crm.leads (catálogo de producción del 14/10/2026, recorrido recursivo; no asumidas):
 --   se BORRAN, con copia: tarea_sla_contexto, lead_asignacion_sla_hitos, lead_sla_etapa_ajustes, actividades_cliente (de
@@ -107,8 +115,29 @@
      or to_regprocedure('private.proteger_lead_eliminado()') is not null then
     raise exception 'PREFLIGHT eliminar_lead_error_carga: los objetos nuevos ya existen';
   end if;
-  if (select count(*) from pg_catalog.pg_trigger t
-      where t.tgenabled = 'O' and t.tgfoid in ('private.trg_sla_nucleo_entrada_guard()'::regprocedure, 'private.trg_lead_asignacion_sla_hitos_guard()'::regprocedure, 'private.trg_lead_asignaciones_inmutables()'::regprocedure, 'private.trg_lead_sla_ciclos_guard()'::regprocedure, 'private.trg_lead_sla_etapas_guard()'::regprocedure, 'private.trg_sla_recibo_guard()'::regprocedure, 'private.potencial_evento_inmutable()'::regprocedure, 'private.trg_actividades_no_contactar_solo_puerta()'::regprocedure)) <> 17 then
+  if (select pg_catalog.array_agg(t.tgrelid::regclass::text || ':' || t.tgname::text || ':' || t.tgfoid::regprocedure::text
+                                || ':' || t.tgtype::text || ':' || t.tgenabled::text
+                                order by t.tgrelid::regclass::text, t.tgname)
+      from pg_catalog.pg_trigger t
+      where not t.tgisinternal and t.tgfoid in ('private.trg_sla_nucleo_entrada_guard()'::regprocedure, 'private.trg_lead_asignacion_sla_hitos_guard()'::regprocedure, 'private.trg_lead_asignaciones_inmutables()'::regprocedure, 'private.trg_lead_sla_ciclos_guard()'::regprocedure, 'private.trg_lead_sla_etapas_guard()'::regprocedure, 'private.trg_sla_recibo_guard()'::regprocedure, 'private.potencial_evento_inmutable()'::regprocedure, 'private.trg_actividades_no_contactar_solo_puerta()'::regprocedure)) is distinct from array[
+        'crm.actividades:trg_00_actividades_no_contactar_solo_puerta:private.trg_actividades_no_contactar_solo_puerta():31:O',
+        'crm.lead_asignacion_sla_hitos:trg_lead_asignacion_sla_hitos_guard:private.trg_lead_asignacion_sla_hitos_guard():31:O',
+        'crm.lead_asignaciones:trg_lead_asignaciones_00_inmutables:private.trg_lead_asignaciones_inmutables():31:O',
+        'crm.lead_potencial_eventos:lead_potencial_evento_inmutable:private.potencial_evento_inmutable():27:O',
+        'crm.lead_potencial_eventos:lead_potencial_evento_no_truncate:private.potencial_evento_inmutable():34:O',
+        'crm.lead_sla_ciclos:trg_lead_sla_ciclos_guard:private.trg_lead_sla_ciclos_guard():31:O',
+        'crm.lead_sla_etapa_ajustes:trg_sla_nucleo_guard:private.trg_sla_nucleo_entrada_guard():31:O',
+        'crm.lead_sla_etapa_ajustes:trg_sla_nucleo_no_truncate:private.trg_sla_nucleo_entrada_guard():34:O',
+        'crm.lead_sla_etapas:trg_lead_sla_etapas_guard:private.trg_lead_sla_etapas_guard():31:O',
+        'crm.sla_operacion_control:trg_sla_nucleo_guard:private.trg_sla_nucleo_entrada_guard():31:O',
+        'crm.sla_operacion_control:trg_sla_nucleo_no_truncate:private.trg_sla_nucleo_entrada_guard():34:O',
+        'crm.sla_operacion_recibos:sla_recibo_guard:private.trg_sla_recibo_guard():31:O',
+        'crm.sla_operacion_recibos:sla_recibo_truncate_guard:private.trg_sla_recibo_guard():34:O',
+        'crm.sla_politica_etapas_operacion:trg_sla_nucleo_guard:private.trg_sla_nucleo_entrada_guard():31:O',
+        'crm.sla_politica_etapas_operacion:trg_sla_nucleo_no_truncate:private.trg_sla_nucleo_entrada_guard():34:O',
+        'crm.tarea_sla_contexto:trg_sla_nucleo_guard:private.trg_sla_nucleo_entrada_guard():31:O',
+        'crm.tarea_sla_contexto:trg_sla_nucleo_no_truncate:private.trg_sla_nucleo_entrada_guard():34:O'
+      ]::text[] then
     raise exception 'PREFLIGHT eliminar_lead_error_carga: los triggers de los candados no están en su modo normal';
   end if;
 end
@@ -141,10 +170,6 @@
 create trigger trg_leads_eliminados_no_truncate before truncate on crm.leads_eliminados
   for each statement execute function private.proteger_lead_eliminado();
 
-create policy leads_eliminados_select_gerencia on crm.leads_eliminados
-  for select to authenticated
-  using ((select private.rol_crm((select auth.uid()))) = 'gerencia');
-
 -- ── 2 · Núcleo: la llave única de los 8 candados ───────────────────────────────────────────────────────────────────────
 create function private.borrado_lead_error_autoriza(p_tabla text, p_fila jsonb)
 returns boolean language sql stable set search_path = '' as $$
@@ -155,8 +180,9 @@
       where e.lead_id::text = pg_catalog.current_setting('crm.borrado_lead_error', true)
         and e.transaccion = pg_catalog.pg_current_xact_id_if_assigned()
         and e.eliminado_por = (select auth.uid())
-        and jsonb_typeof(e.copia -> p_tabla) = 'array'
-        and e.copia -> p_tabla @> pg_catalog.jsonb_build_array(p_fila))
+        and case when pg_catalog.jsonb_typeof(e.copia -> p_tabla) = 'array'
+                 then exists (select 1 from pg_catalog.jsonb_array_elements(e.copia -> p_tabla) f(fila) where f.fila = p_fila)
+                 else false end)
 $$;
 
 -- ── 3 · Los 8 candados: idénticos a producción salvo las 5 líneas del DELETE ──────────────────────────────────────────
@@ -492,6 +518,8 @@
   v_copia jsonb;
   v_filas jsonb;
   v_id uuid;
+  v_n bigint;
+  v_cuadre jsonb := '{}'::jsonb;
   v_previa text := pg_catalog.current_setting('crm.borrado_lead_error', true);
 begin
   if v_uid is null then
@@ -510,51 +538,95 @@
   end if;
   if pg_catalog.char_length(v_motivo) > 500 then
     raise exception 'El motivo admite como máximo 500 caracteres' using errcode = '22023';
+  end if;
+  -- Cada sentencia necesita su propia instantánea: la copia tiene que ver lo que existe DESPUÉS de los bloqueos, y la
+  -- comprobación del mes cerrado tiene que ver un cierre recién confirmado.
+  if pg_catalog.current_setting('transaction_isolation') <> 'read committed' then
+    raise exception 'Esta operación necesita aislamiento READ COMMITTED' using errcode = '55000';
   end if;
 
-  -- Fail-closed: toda llave foránea hacia el lead o hacia lo que se borra tiene que estar en esta lista (catálogo de
-  -- producción, 14/10/2026). Una tabla nueva enlazada se revisa antes de poder borrar: sin copia no se borra nada.
-  select pg_catalog.string_agg(distinct c.conrelid::regclass::text || ' → ' || c.confrelid::regclass::text, ', ')
-    into v_nuevas
-  from pg_catalog.pg_constraint c
-  where c.contype = 'f'
-    and c.confrelid in ('crm.leads'::regclass, 'crm.tareas'::regclass, 'crm.actividades'::regclass,
-                        'crm.lead_asignaciones'::regclass, 'crm.lead_sla_ciclos'::regclass, 'crm.lead_sla_etapas'::regclass,
-                        'crm.tarea_sla_contexto'::regclass, 'crm.lead_asignacion_sla_hitos'::regclass,
-                        'crm.lead_sla_etapa_ajustes'::regclass, 'crm.actividades_cliente'::regclass,
-                        'crm.sla_operacion_recibos'::regclass, 'crm.lead_potencial'::regclass,
-                        'crm.lead_potencial_eventos'::regclass, 'crm.base_carga_leads'::regclass,
-                        'crm.llamadas_celular_eventos'::regclass, 'crm.llamadas_celular_enlaces'::regclass,
-                        'private.llamadas_celular_intenciones'::regclass)
-    and (c.conrelid::regclass::text, c.confrelid::regclass::text) not in (
-      ('crm.actividades', 'crm.leads'), ('crm.ajustes_mes_cerrado', 'crm.leads'), ('crm.base_carga_leads', 'crm.leads'),
-      ('crm.busquedas_cliente_existente', 'crm.leads'), ('crm.cierres_avance_anulados', 'crm.leads'),
-      ('crm.cierres_externos', 'crm.leads'), ('crm.conversion_acreditaciones', 'crm.leads'),
-      ('crm.conversion_reservas', 'crm.leads'), ('crm.inversion_solicitudes', 'crm.leads'),
-      ('crm.inversionista_leads', 'crm.leads'), ('crm.inversionista_operaciones', 'crm.leads'),
-      ('crm.lead_asignaciones', 'crm.leads'), ('crm.lead_potencial_eventos', 'crm.leads'),
-      ('crm.lead_potencial', 'crm.leads'), ('crm.lead_sla_ciclos', 'crm.leads'), ('crm.lead_sla_etapas', 'crm.leads'),
-      ('crm.llamadas_celular_enlaces', 'crm.leads'), ('crm.llamadas_celular_eventos', 'crm.leads'),
-      ('private.llamadas_celular_intenciones', 'crm.leads'), ('crm.sla_operacion_recibos', 'crm.leads'),
-      ('crm.solicitudes_tasa', 'crm.leads'), ('crm.tareas', 'crm.leads'),
-      ('crm.actividades_cliente', 'crm.tareas'), ('crm.inversionista_gestiones', 'crm.tareas'),
-      ('crm.tarea_sla_contexto', 'crm.tareas'), ('crm.tareas', 'crm.tareas'),
-      ('crm.lead_sla_etapa_ajustes', 'crm.actividades'), ('crm.llamadas_celular_enlaces', 'crm.actividades'),
-      ('private.llamadas_celular_intenciones', 'crm.actividades'), ('crm.tareas', 'crm.actividades'),
-      ('crm.conversion_acreditaciones', 'crm.lead_asignaciones'), ('crm.lead_asignacion_sla_hitos', 'crm.lead_asignaciones'),
-      ('crm.lead_sla_etapas', 'crm.lead_sla_ciclos'), ('crm.tarea_sla_contexto', 'crm.lead_sla_ciclos'),
-      ('crm.lead_sla_etapa_ajustes', 'crm.lead_sla_etapas'),
-      ('crm.llamadas_celular_enlaces', 'crm.llamadas_celular_eventos'));
+  -- Fail-closed: toda llave foránea hacia el lead o hacia lo que se borra tiene que estar en esta lista, con su
+  -- columna y su acción ON DELETE (catálogo de producción, 14/10/2026). Una tabla o columna nueva enlazada, o una acción
+  -- que cambie (p. ej. a CASCADE), se revisa antes de poder borrar: sin copia no se borra nada.
+  select pg_catalog.string_agg(k.clave, ', ' order by k.clave) into v_nuevas
+  from (
+    select c.conrelid::regclass::text || ':'
+             || (select pg_catalog.string_agg(a.attname::text, ',' order by u.ord)
+                 from pg_catalog.unnest(c.conkey) with ordinality u(attnum, ord)
+                 join pg_catalog.pg_attribute a on a.attrelid = c.conrelid and a.attnum = u.attnum)
+             || ':' || c.confrelid::regclass::text || ':' || c.confdeltype::text as clave
+    from pg_catalog.pg_constraint c
+    where c.contype = 'f'
+      and c.confrelid in ('crm.leads'::regclass, 'crm.tareas'::regclass, 'crm.actividades'::regclass,
+                          'crm.lead_asignaciones'::regclass, 'crm.lead_sla_ciclos'::regclass, 'crm.lead_sla_etapas'::regclass,
+                          'crm.tarea_sla_contexto'::regclass, 'crm.lead_asignacion_sla_hitos'::regclass,
+                          'crm.lead_sla_etapa_ajustes'::regclass, 'crm.actividades_cliente'::regclass,
+                          'crm.sla_operacion_recibos'::regclass, 'crm.lead_potencial'::regclass,
+                          'crm.lead_potencial_eventos'::regclass, 'crm.base_carga_leads'::regclass,
+                          'crm.llamadas_celular_eventos'::regclass, 'crm.llamadas_celular_enlaces'::regclass,
+                          'private.llamadas_celular_intenciones'::regclass)
+  ) k
+  where k.clave <> all (array[
+    'crm.actividades:lead_id:crm.leads:c',
+    'crm.actividades_cliente:tarea_id:crm.tareas:n',
+    'crm.ajustes_mes_cerrado:lead_id:crm.leads:r',
+    'crm.base_carga_leads:lead_id:crm.leads:a',
+    'crm.busquedas_cliente_existente:lead_id:crm.leads:a',
+    'crm.cierres_avance_anulados:lead_id:crm.leads:r',
+    'crm.cierres_externos:lead_id:crm.leads:r',
+    'crm.conversion_acreditaciones:episodio_id:crm.lead_asignaciones:a',
+    'crm.conversion_acreditaciones:lead_id:crm.leads:a',
+    'crm.conversion_reservas:lead_id:crm.leads:r',
+    'crm.inversion_solicitudes:lead_origen_id:crm.leads:a',
+    'crm.inversionista_gestiones:tarea_id:crm.tareas:a',
+    'crm.inversionista_leads:lead_id:crm.leads:a',
+    'crm.inversionista_operaciones:lead_id:crm.leads:a',
+    'crm.lead_asignacion_sla_hitos:lead_asignacion_id:crm.lead_asignaciones:r',
+    'crm.lead_asignaciones:lead_id:crm.leads:r',
+    'crm.lead_potencial:lead_id:crm.leads:a',
+    'crm.lead_potencial_eventos:lead_id:crm.leads:a',
+    'crm.lead_sla_ciclos:lead_id:crm.leads:r',
+    'crm.lead_sla_etapa_ajustes:etapa_sla_id:crm.lead_sla_etapas:r',
+    'crm.lead_sla_etapa_ajustes:origen_actividad_id:crm.actividades:r',
+    'crm.lead_sla_etapas:lead_id,ciclo_n:crm.lead_sla_ciclos:r',
+    'crm.lead_sla_etapas:lead_id:crm.leads:r',
+    'crm.llamadas_celular_enlaces:actividad_id:crm.actividades:n',
+    'crm.llamadas_celular_enlaces:evento_id:crm.llamadas_celular_eventos:c',
+    'crm.llamadas_celular_enlaces:lead_id:crm.leads:c',
+    'crm.llamadas_celular_eventos:lead_id:crm.leads:c',
+    'crm.sla_operacion_recibos:lead_id:crm.leads:a',
+    'crm.solicitudes_tasa:lead_id:crm.leads:r',
+    'crm.tarea_sla_contexto:lead_id,ciclo_n:crm.lead_sla_ciclos:r',
+    'crm.tarea_sla_contexto:tarea_id:crm.tareas:r',
+    'crm.tareas:lead_id:crm.leads:c',
+    'crm.tareas:reagendada_de:crm.tareas:n',
+    'crm.tareas:resultado_actividad_id:crm.actividades:n',
+    'private.llamadas_celular_intenciones:actividad_id:crm.actividades:c',
+    'private.llamadas_celular_intenciones:lead_id:crm.leads:c'
+  ]);
   if v_nuevas is not null then
     raise exception 'Hay tablas nuevas enlazadas al lead que esta eliminación no conoce (%); hay que revisarla antes', v_nuevas
       using errcode = '55000';
   end if;
 
+  -- Mismo candado que crm.cerrar_periodo, tomado ANTES de las filas (mismo orden que el cierre: sin abrazo mortal), para
+  -- que nadie selle un mes entre la comprobación del mes cerrado y el borrado.
+  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados')::bigint);
+
   -- El lead primero (bloquea también toda fila nueva que quiera colgarse de él: su FK necesita KEY SHARE).
   select * into v_lead from crm.leads l where l.id = p_lead_id for update;
   if not found then
     raise exception 'El lead no existe o ya fue eliminado' using errcode = 'P0002';
   end if;
+  -- Los padres de cada nivel, en sentencias ANTERIORES a la copia: desde aquí ninguna fila nueva puede colgarse de ellos
+  -- (su FK necesita KEY SHARE) ni una asignación puede cambiar de resultado, y la copia (otra sentencia, otra
+  -- instantánea) ve todo lo confirmado hasta ahora.
+  perform 1 from crm.lead_asignaciones x where x.lead_id = p_lead_id order by x.id for update;
+  perform 1 from crm.lead_sla_ciclos x where x.lead_id = p_lead_id order by x.id for update;
+  perform 1 from crm.lead_sla_etapas x where x.lead_id = p_lead_id order by x.id for update;
+  perform 1 from crm.tareas x where x.lead_id = p_lead_id order by x.id for update;
+  perform 1 from crm.actividades x where x.lead_id = p_lead_id order by x.id for update;
+  perform 1 from crm.llamadas_celular_eventos x where x.lead_id = p_lead_id order by x.id for update;
 
   if v_lead.contrato_id is not null then v_no := v_no || 'tiene un contrato enlazado'::text; end if;
   if v_lead.perfil_id is not null then v_no := v_no || 'está enlazado a un perfil de cliente'::text; end if;
@@ -584,12 +656,21 @@
     v_no := v_no || 'tiene búsquedas de cliente existente registradas'::text; end if;
   if exists (select 1 from crm.inversionista_gestiones g join crm.tareas t on t.id = g.tarea_id where t.lead_id = p_lead_id) then
     v_no := v_no || 'tiene gestiones de inversionista'::text; end if;
-  if v_lead.creado_en < pg_catalog.now() - pg_catalog.make_interval(days => c_dias_max) then
+  -- Filas de OTROS leads que apuntan a las suyas (su ON DELETE SET NULL las reescribiría sin copia).
+  if exists (select 1 from crm.tareas o
+             where o.lead_id is distinct from p_lead_id
+               and (o.reagendada_de in (select t.id from crm.tareas t where t.lead_id = p_lead_id)
+                    or o.resultado_actividad_id in (select a.id from crm.actividades a where a.lead_id = p_lead_id)))
+     or exists (select 1 from crm.llamadas_celular_enlaces o
+                where o.lead_id is distinct from p_lead_id
+                  and o.actividad_id in (select a.id from crm.actividades a where a.lead_id = p_lead_id)) then
+    v_no := v_no || 'otro lead tiene tareas o llamadas enlazadas a las suyas'::text;
+  end if;
+  if v_lead.creado_en < pg_catalog.clock_timestamp() - pg_catalog.make_interval(days => c_dias_max) then
     v_no := v_no || pg_catalog.format('se creó hace más de %s días (%s)', c_dias_max,
                       pg_catalog.to_char(v_lead.creado_en at time zone 'America/Lima', 'DD/MM/YYYY'));
   end if;
-  -- Mes cerrado: mismo candado que crm.cerrar_periodo, para que nadie selle un mes entre esta lectura y el borrado.
-  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados')::bigint);
+  -- Mes cerrado (el candado de crm.cerrar_periodo ya está tomado arriba).
   select pg_catalog.string_agg(pg_catalog.to_char(pc.periodo, 'MM/YYYY'), ', ' order by pc.periodo) into v_meses
   from crm.periodos_cerrados pc
   where pc.periodo >= pg_catalog.date_trunc('month', v_lead.creado_en at time zone 'America/Lima')::date;
@@ -650,58 +731,108 @@
   select pg_catalog.jsonb_object_agg(e.key, pg_catalog.jsonb_array_length(e.value)) into v_filas
   from pg_catalog.jsonb_each(v_copia) e where pg_catalog.jsonb_typeof(e.value) = 'array';
 
-  insert into crm.leads_eliminados (lead_id, motivo, eliminado_por, rol_actor, copia, filas)
-  values (p_lead_id, v_motivo, v_uid, v_rol, v_copia, v_filas)
-  returning id into v_id;
+  -- Un CHECK fallido devolvería «Failing row contains (…)» con la copia (datos personales): se responde sin detalle.
+  begin
+    insert into crm.leads_eliminados (lead_id, motivo, eliminado_por, rol_actor, copia, filas)
+    values (p_lead_id, v_motivo, v_uid, v_rol, v_copia, v_filas)
+    returning id into v_id;
+  exception when check_violation or not_null_violation or unique_violation then
+    raise exception 'No se pudo guardar la copia del lead; no se eliminó nada' using errcode = '55000';
+  end;
 
   -- Permiso de borrado de ESTE lead, solo en esta transacción; los candados exigen además la fila en la copia.
   perform pg_catalog.set_config('crm.borrado_lead_error', p_lead_id::text, true);
 
   -- Orden por llaves foráneas (RESTRICT/NO ACTION primero; las tareas antes que las actividades para que su
-  -- ON DELETE SET NULL no reescriba tareas que también se van).
+  -- ON DELETE SET NULL no reescriba tareas que también se van). Cada DELETE tiene que borrar EXACTAMENTE lo copiado.
   delete from crm.tarea_sla_contexto x where x.lead_id = p_lead_id;
+  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('tarea_sla_contexto', v_n);
   delete from crm.lead_asignacion_sla_hitos x
   where x.lead_asignacion_id in (select a.id from crm.lead_asignaciones a where a.lead_id = p_lead_id);
+  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('lead_asignacion_sla_hitos', v_n);
   delete from crm.lead_sla_etapa_ajustes x
   where x.etapa_sla_id in (select e.id from crm.lead_sla_etapas e where e.lead_id = p_lead_id);
+  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('lead_sla_etapa_ajustes', v_n);
   delete from crm.actividades_cliente x where x.tarea_id in (select t.id from crm.tareas t where t.lead_id = p_lead_id);
+  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('actividades_cliente', v_n);
   delete from crm.tareas x where x.lead_id = p_lead_id;
+  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('tareas', v_n);
   delete from crm.sla_operacion_recibos x where x.lead_id = p_lead_id;
+  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('sla_operacion_recibos', v_n);
   delete from crm.lead_potencial_eventos x where x.lead_id = p_lead_id;
+  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('lead_potencial_eventos', v_n);
   delete from crm.lead_potencial x where x.lead_id = p_lead_id;
+  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('lead_potencial', v_n);
   delete from crm.base_carga_leads x where x.lead_id = p_lead_id;
+  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('base_carga_leads', v_n);
   delete from crm.actividades x where x.lead_id = p_lead_id;   -- cascada: intenciones; los enlaces quedan sin actividad
+  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('actividades', v_n);
   delete from crm.lead_sla_etapas x where x.lead_id = p_lead_id;
+  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('lead_sla_etapas', v_n);
   delete from crm.lead_sla_ciclos x where x.lead_id = p_lead_id;
+  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('lead_sla_ciclos', v_n);
   delete from crm.lead_asignaciones x where x.lead_id = p_lead_id;
+  get diagnostics v_n = row_count; v_cuadre := v_cuadre || pg_catalog.jsonb_build_object('lead_asignaciones', v_n);
   delete from crm.leads x where x.id = p_lead_id;               -- cascada: llamadas del celular (sus candados la aceptan)
+  get diagnostics v_n = row_count;
 
   perform pg_catalog.set_config('crm.borrado_lead_error', coalesce(v_previa, ''), true);
 
-  if exists (select 1 from crm.leads x where x.id = p_lead_id)
-     or exists (select 1 from crm.lead_asignaciones x where x.lead_id = p_lead_id)
-     or exists (select 1 from crm.lead_sla_ciclos x where x.lead_id = p_lead_id)
-     or exists (select 1 from crm.tareas x where x.lead_id = p_lead_id)
-     or exists (select 1 from crm.actividades x where x.lead_id = p_lead_id) then
-    raise exception 'La eliminación quedó incompleta; no se aplicó nada' using errcode = '55000';
+  -- Cuadre: lo borrado = lo copiado, tabla por tabla; y de las cascadas no queda ninguna fila copiada.
+  if v_n <> 1
+     or exists (select 1 from pg_catalog.jsonb_each(v_cuadre) d
+                where d.value <> v_filas -> d.key)
+     or exists (select 1 from crm.llamadas_celular_eventos x
+                where x.id in (select (e ->> 'id')::uuid from pg_catalog.jsonb_array_elements(v_copia -> 'llamadas_celular_eventos') e))
+     or exists (select 1 from crm.llamadas_celular_enlaces x
+                where x.id in (select (e ->> 'id')::uuid from pg_catalog.jsonb_array_elements(v_copia -> 'llamadas_celular_enlaces') e))
+     or exists (select 1 from private.llamadas_celular_intenciones x
+                where x.id in (select (e ->> 'id')::uuid from pg_catalog.jsonb_array_elements(v_copia -> 'llamadas_celular_intenciones') e)) then
+    raise exception 'La eliminación no cuadró con la copia; no se aplicó nada' using errcode = '55000';
   end if;
 
   return pg_catalog.jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'copia_id', v_id, 'filas', v_filas);
 end $$;
 
+-- Lectura para gerencia, por puerta (la tabla no tiene grants: la copia lleva filas crudas de tablas cerradas a la API,
+-- como las llamadas del celular o el SLA). Devuelve los datos para ubicar cada eliminación, no la copia cruda.
+-- DEFINER: justificación, la tabla no tiene grants; el rol se resuelve con auth.uid().
+create function crm.listar_leads_eliminados()
+returns table (id uuid, lead_id uuid, nombre text, origen text, lead_creado_en timestamptz, motivo text,
+               eliminado_por uuid, eliminado_por_nombre text, rol_actor text, eliminado_en timestamptz, filas jsonb)
+language plpgsql
+stable
+security definer
+set search_path = ''
+as $$
+begin
+  if (select private.rol_crm((select auth.uid()))) is distinct from 'gerencia' then
+    raise exception 'Solo gerencia ve los leads eliminados' using errcode = '42501';
+  end if;
+  return query
+  select e.id, e.lead_id, e.copia -> 'lead' ->> 'nombre_completo', e.copia -> 'lead' ->> 'origen',
+         (e.copia -> 'lead' ->> 'creado_en')::timestamptz, e.motivo, e.eliminado_por, p.nombre_completo, e.rol_actor,
+         e.eliminado_en, e.filas
+  from crm.leads_eliminados e
+  left join public.perfiles p on p.id = e.eliminado_por
+  order by e.eliminado_en desc;
+end $$;
+
 -- ── 5 · Permisos ───────────────────────────────────────────────────────────────────────────────────────────────────────
 revoke all on table crm.leads_eliminados from public, anon, authenticated, service_role;
-grant select on table crm.leads_eliminados to authenticated;
 revoke all on function private.proteger_lead_eliminado() from public, anon, authenticated, service_role;
 revoke all on function private.borrado_lead_error_autoriza(text, jsonb) from public, anon, authenticated, service_role;
 revoke all on function crm.eliminar_lead_error_carga(uuid, text) from public, anon, service_role;
 grant execute on function crm.eliminar_lead_error_carga(uuid, text) to authenticated;
+revoke all on function crm.listar_leads_eliminados() from public, anon, service_role;
+grant execute on function crm.listar_leads_eliminados() to authenticated;
 
 -- ── 6 · Comentarios ────────────────────────────────────────────────────────────────────────────────────────────────────
 comment on table crm.leads_eliminados is
   'Copia inmutable de cada lead eliminado por error de carga (crm.eliminar_lead_error_carga, 14/10/2026): el lead y todas '
-  'sus filas hijas, tal como estaban al borrarlas. Solo lectura y solo para gerencia del CRM (RLS); nadie la modifica ni '
-  'la borra. Contiene datos personales del lead (nombre, teléfono, documento) dentro de la copia.';
+  'sus filas hijas, tal como estaban al borrarlas. RLS sin políticas y sin grants: nadie la modifica ni la borra; '
+  'gerencia la consulta con crm.listar_leads_eliminados(). Contiene datos personales del lead (nombre, teléfono, '
+  'documento) dentro de la copia.';
 comment on column crm.leads_eliminados.id is 'Identificador de la copia.';
 comment on column crm.leads_eliminados.lead_id is 'Lead eliminado (ya no existe en crm.leads; sin llave foránea a propósito).';
 comment on column crm.leads_eliminados.motivo is 'Motivo escrito por quien eliminó (10 a 500 caracteres).';
@@ -722,6 +853,8 @@
   'Elimina un lead cargado por error con todo lo que cuelga de él, dejando antes una copia en crm.leads_eliminados. Solo '
   'gerencia (CRM) o admin/superadmin (portal); motivo obligatorio. Rechaza (P0409) leads con contrato, perfil, '
   'inversionista, conversión o cierre, historia de inversión, más de 30 días o en un mes cerrado.';
+comment on function crm.listar_leads_eliminados() is
+  'Solo gerencia: lista los leads eliminados por error de carga (quién, cuándo, motivo, cuántas filas), sin la copia cruda.';
 
 -- ── 7 · Postflight ─────────────────────────────────────────────────────────────────────────────────────────────────────
 do $postflight$
@@ -757,43 +890,78 @@
   if (select relrowsecurity from pg_catalog.pg_class where oid = 'crm.leads_eliminados'::regclass) is not true then
     raise exception 'POSTFLIGHT: crm.leads_eliminados sin RLS';
   end if;
-  if (select count(*) from pg_catalog.pg_policy where polrelid = 'crm.leads_eliminados'::regclass) <> 1
-     or exists (select 1 from pg_catalog.pg_policy where polrelid = 'crm.leads_eliminados'::regclass and polcmd <> 'r') then
-    raise exception 'POSTFLIGHT: crm.leads_eliminados debe tener una sola política, de lectura';
+  if exists (select 1 from pg_catalog.pg_policy where polrelid = 'crm.leads_eliminados'::regclass) then
+    raise exception 'POSTFLIGHT: crm.leads_eliminados no lleva políticas';
   end if;
-  if not has_table_privilege('authenticated', 'crm.leads_eliminados', 'select')
-     or has_table_privilege('authenticated', 'crm.leads_eliminados', 'insert, update, delete, truncate')
-     or has_table_privilege('anon', 'crm.leads_eliminados', 'select, insert, update, delete, truncate')
-     or has_table_privilege('service_role', 'crm.leads_eliminados', 'select, insert, update, delete, truncate') then
+  if has_table_privilege('authenticated', 'crm.leads_eliminados', 'select, insert, update, delete, truncate, references, trigger')
+     or has_table_privilege('anon', 'crm.leads_eliminados', 'select, insert, update, delete, truncate, references, trigger')
+     or has_table_privilege('service_role', 'crm.leads_eliminados', 'select, insert, update, delete, truncate, references, trigger') then
     raise exception 'POSTFLIGHT: permisos de crm.leads_eliminados';
   end if;
   if (select count(*) from pg_catalog.pg_trigger where tgrelid = 'crm.leads_eliminados'::regclass and not tgisinternal) <> 3 then
     raise exception 'POSTFLIGHT: triggers de crm.leads_eliminados';
   end if;
-  if not has_function_privilege('authenticated', 'crm.eliminar_lead_error_carga(uuid,text)', 'execute')
-     or has_function_privilege('anon', 'crm.eliminar_lead_error_carga(uuid,text)', 'execute')
-     or has_function_privilege('service_role', 'crm.eliminar_lead_error_carga(uuid,text)', 'execute')
-     or has_function_privilege('authenticated', 'private.borrado_lead_error_autoriza(text,jsonb)', 'execute')
-     or has_function_privilege('anon', 'private.borrado_lead_error_autoriza(text,jsonb)', 'execute') then
+  -- Puertas: EXECUTE solo para authenticated (sin PUBLIC, anon ni service_role). Núcleo: sin EXECUTE para nadie de la API.
+  if exists (select 1 from pg_catalog.pg_proc p
+             cross join lateral pg_catalog.aclexplode(coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))) a
+             where p.oid in ('crm.eliminar_lead_error_carga(uuid,text)'::regprocedure,
+                             'crm.listar_leads_eliminados()'::regprocedure)
+               and a.grantee <> p.proowner and a.grantee <> 'authenticated'::regrole)
+     or exists (select 1 from pg_catalog.pg_proc p
+                cross join lateral pg_catalog.aclexplode(coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))) a
+                where p.oid in ('private.borrado_lead_error_autoriza(text,jsonb)'::regprocedure,
+                                'private.proteger_lead_eliminado()'::regprocedure)
+                  and a.grantee <> p.proowner)
+     or not has_function_privilege('authenticated', 'crm.eliminar_lead_error_carga(uuid,text)', 'execute')
+     or not has_function_privilege('authenticated', 'crm.listar_leads_eliminados()', 'execute') then
     raise exception 'POSTFLIGHT: permisos de las funciones nuevas';
   end if;
   if exists (select 1 from pg_catalog.pg_proc p
              where p.oid in ('crm.eliminar_lead_error_carga(uuid,text)'::regprocedure,
+                             'crm.listar_leads_eliminados()'::regprocedure,
                              'private.borrado_lead_error_autoriza(text,jsonb)'::regprocedure,
                              'private.proteger_lead_eliminado()'::regprocedure)
                and p.proowner <> 'postgres'::regrole) then
     raise exception 'POSTFLIGHT: dueño de las funciones nuevas';
   end if;
-  if (select p.prosecdef and p.proconfig @> array['search_path=""'] from pg_catalog.pg_proc p
-      where p.oid = 'crm.eliminar_lead_error_carga(uuid,text)'::regprocedure) is not true then
-    raise exception 'POSTFLIGHT: la puerta debe ser DEFINER con search_path vacío';
+  if (select pg_catalog.bool_and(p.prosecdef and p.proconfig @> array['search_path=""']) from pg_catalog.pg_proc p
+      where p.oid in ('crm.eliminar_lead_error_carga(uuid,text)'::regprocedure, 'crm.listar_leads_eliminados()'::regprocedure))
+     is not true then
+    raise exception 'POSTFLIGHT: las puertas deben ser DEFINER con search_path vacío';
   end if;
+  -- Los 8 candados conservan dueño y permisos (CREATE OR REPLACE no los cambia, pero se comprueba).
+  if exists (select 1 from pg_catalog.pg_proc p
+             where p.oid in ('private.trg_sla_nucleo_entrada_guard()'::regprocedure, 'private.trg_lead_asignacion_sla_hitos_guard()'::regprocedure, 'private.trg_lead_asignaciones_inmutables()'::regprocedure, 'private.trg_lead_sla_ciclos_guard()'::regprocedure, 'private.trg_lead_sla_etapas_guard()'::regprocedure, 'private.trg_sla_recibo_guard()'::regprocedure, 'private.potencial_evento_inmutable()'::regprocedure, 'private.trg_actividades_no_contactar_solo_puerta()'::regprocedure)
+               and (p.proowner <> 'postgres'::regrole or p.proacl is distinct from '{postgres=X/postgres}'::aclitem[])) then
+    raise exception 'POSTFLIGHT: dueño o permisos de un candado';
+  end if;
   if exists (select 1 from private.contadores_crudos_leads_citas() c
              where c.objeto in ('crm.eliminar_lead_error_carga(uuid,text)', 'private.borrado_lead_error_autoriza(text,jsonb)')) then
     raise exception 'POSTFLIGHT: una función nueva entró al censo analítico';
   end if;
-  if (select count(*) from pg_catalog.pg_trigger t
-      where t.tgenabled = 'O' and t.tgfoid in ('private.trg_sla_nucleo_entrada_guard()'::regprocedure, 'private.trg_lead_asignacion_sla_hitos_guard()'::regprocedure, 'private.trg_lead_asignaciones_inmutables()'::regprocedure, 'private.trg_lead_sla_ciclos_guard()'::regprocedure, 'private.trg_lead_sla_etapas_guard()'::regprocedure, 'private.trg_sla_recibo_guard()'::regprocedure, 'private.potencial_evento_inmutable()'::regprocedure, 'private.trg_actividades_no_contactar_solo_puerta()'::regprocedure)) <> 17 then
+  if (select pg_catalog.array_agg(t.tgrelid::regclass::text || ':' || t.tgname::text || ':' || t.tgfoid::regprocedure::text
+                                || ':' || t.tgtype::text || ':' || t.tgenabled::text
+                                order by t.tgrelid::regclass::text, t.tgname)
+      from pg_catalog.pg_trigger t
+      where not t.tgisinternal and t.tgfoid in ('private.trg_sla_nucleo_entrada_guard()'::regprocedure, 'private.trg_lead_asignacion_sla_hitos_guard()'::regprocedure, 'private.trg_lead_asignaciones_inmutables()'::regprocedure, 'private.trg_lead_sla_ciclos_guard()'::regprocedure, 'private.trg_lead_sla_etapas_guard()'::regprocedure, 'private.trg_sla_recibo_guard()'::regprocedure, 'private.potencial_evento_inmutable()'::regprocedure, 'private.trg_actividades_no_contactar_solo_puerta()'::regprocedure)) is distinct from array[
+        'crm.actividades:trg_00_actividades_no_contactar_solo_puerta:private.trg_actividades_no_contactar_solo_puerta():31:O',
+        'crm.lead_asignacion_sla_hitos:trg_lead_asignacion_sla_hitos_guard:private.trg_lead_asignacion_sla_hitos_guard():31:O',
+        'crm.lead_asignaciones:trg_lead_asignaciones_00_inmutables:private.trg_lead_asignaciones_inmutables():31:O',
+        'crm.lead_potencial_eventos:lead_potencial_evento_inmutable:private.potencial_evento_inmutable():27:O',
+        'crm.lead_potencial_eventos:lead_potencial_evento_no_truncate:private.potencial_evento_inmutable():34:O',
+        'crm.lead_sla_ciclos:trg_lead_sla_ciclos_guard:private.trg_lead_sla_ciclos_guard():31:O',
+        'crm.lead_sla_etapa_ajustes:trg_sla_nucleo_guard:private.trg_sla_nucleo_entrada_guard():31:O',
+        'crm.lead_sla_etapa_ajustes:trg_sla_nucleo_no_truncate:private.trg_sla_nucleo_entrada_guard():34:O',
+        'crm.lead_sla_etapas:trg_lead_sla_etapas_guard:private.trg_lead_sla_etapas_guard():31:O',
+        'crm.sla_operacion_control:trg_sla_nucleo_guard:private.trg_sla_nucleo_entrada_guard():31:O',
+        'crm.sla_operacion_control:trg_sla_nucleo_no_truncate:private.trg_sla_nucleo_entrada_guard():34:O',
+        'crm.sla_operacion_recibos:sla_recibo_guard:private.trg_sla_recibo_guard():31:O',
+        'crm.sla_operacion_recibos:sla_recibo_truncate_guard:private.trg_sla_recibo_guard():34:O',
+        'crm.sla_politica_etapas_operacion:trg_sla_nucleo_guard:private.trg_sla_nucleo_entrada_guard():31:O',
+        'crm.sla_politica_etapas_operacion:trg_sla_nucleo_no_truncate:private.trg_sla_nucleo_entrada_guard():34:O',
+        'crm.tarea_sla_contexto:trg_sla_nucleo_guard:private.trg_sla_nucleo_entrada_guard():31:O',
+        'crm.tarea_sla_contexto:trg_sla_nucleo_no_truncate:private.trg_sla_nucleo_entrada_guard():34:O'
+      ]::text[] then
     raise exception 'POSTFLIGHT: los triggers de los candados no siguen en su modo normal';
   end if;
 end
```

## Protocolo global de revisión
# Protocolo global Codex ↔ Claude Code

Aplica al usuario de esta Mac, en cualquier proyecto, aunque no exista `.ai/`.
Las instrucciones del repositorio definen negocio, arquitectura y comandos;
este protocolo define los roles y el aislamiento de las consultas.

## Roles y autoridad

- PRIMARY: posee la tarea, inspecciona, decide, implementa, ejecuta checks,
  evalúa hallazgos y entrega el resultado. Es el único escritor.
- SECONDARY_REVIEWER: analiza evidencia, bugs, regresiones, seguridad,
  arquitectura, casos límite y pruebas faltantes. No escribe archivos, no
  implementa, no hace commits, no cambia configuración, no ejecuta acciones
  destructivas, no llama al otro agente y no delega ni inicia otro review.
- Una tarea normal del usuario define un PRIMARY. Un prompt que comienza con
  `ROLE: SECONDARY_REVIEWER` define un consultor, aunque existan instrucciones
  generales de autonomía. Si le piden otra opinión, devuelve su propio análisis.
- La única cadena permitida es PRIMARY → SECONDARY_REVIEWER → PRIMARY.
- El reviewer es asesor; el PRIMARY decide con evidencia. Un PASS de IA no
  significa que la tarea esté terminada.

## Cuándo consultar

- LEVEL 1: formato, documentación sencilla, CSS pequeño, rename o fix obvio:
  cero consultas.
- LEVEL 2: lógica relevante, integración, endpoint, componente importante o
  refactor moderado: normalmente una consulta si aporta valor independiente.
- LEVEL 3: auth, permisos, secretos, seguridad, schemas/migraciones, arquitectura,
  concurrencia, pagos, lógica financiera, APIs importantes o cambios destructivos:
  una consulta cuando sea razonablemente posible.
- Máximo habitual: dos consultas por tarea, contando reviewers especializados.
  La segunda necesita nueva evidencia, discrepancia importante o corrección de
  riesgo que justifique otra verificación. No repetir hasta conseguir un PASS.
- Las instrucciones explícitas del usuario sobre consultas prevalecen. No
  consultar para confirmar trivialidades ni abrir cadenas recursivas.

## Evidence-first y formato

**NO FINDING WITHOUT EVIDENCE.** Citar archivo/líneas, símbolo, diff, test,
error, log o reproducción. Identificar como hipótesis lo no demostrado.
Omitir secciones vacías y recomendaciones genéricas sin relación con la tarea.

```text
VERDICT:
PASS | CHANGES_REQUESTED | BLOCK

SUMMARY:
Conclusión técnica breve.

FINDINGS:
[P0 | P1 | P2 | P3] Título
File:
Lines:
Problem:
Evidence:
Impact:
Recommendation:

TEST GAPS:
- ...
ARCHITECTURE RISKS:
- ...
SECURITY RISKS:
- ...
REGRESSION RISKS:
- ...
RECOMMENDED NEXT ACTIONS:
1. ...
CONFIDENCE:
HIGH | MEDIUM | LOW
```

PASS: sin hallazgos obligatorios en lo revisado. CHANGES_REQUESTED: correcciones
accionables. BLOCK: riesgo crítico o evidencia insuficiente para revisar.
Resolver desacuerdos por requisitos, comportamiento, pruebas y documentación
oficial, no mediante consultas repetitivas.

## Interfaces

Codex PRIMARY usa `~/.local/bin/claude-review`, o el wrapper del repo cuando
sus instrucciones lo requieran. Adjunta código/diff saneado, rutas/líneas,
requisitos y resultados de checks. No enviar secretos. CodeGraph se usa por
el PRIMARY si el proyecto está indexado, nunca se indexa automáticamente.

El wrapper global incorpora este protocolo y, si existe, el protocolo `.ai/`
del proyecto. Claude reviewer tiene todas las herramientas, MCP, hooks y
personalizaciones deshabilitadas; no persiste la sesión. Cinco turnos por
defecto, máximo ocho. Exit 0 indica entrega válida, no necesariamente PASS.
Usa `dontAsk`, sin solicitudes de permiso, y comprueba que el evento de inicio
declare cero herramientas y cero MCP antes de aceptar un resultado único.
Las menciones genéricas a herramientas en el texto del modelo no acreditan
disponibilidad: la comprobación debe usar el inventario efectivo de la CLI.

Claude PRIMARY usa `mcp__codex__codex` con:

```text
sandbox: read-only
approval-policy: never
prompt:
ROLE: SECONDARY_REVIEWER.
Claude is the PRIMARY agent.
Do not modify files.
Do not implement the task.
Do not invoke Claude.
Do not delegate to another coding agent.
Do not create another review chain.
```

Adjuntar el contenido de este protocolo, las reglas relevantes del proyecto y
la evidencia: el reviewer no tiene herramientas para abrirlos. Solo se permite
añadir `model`; no `cwd`, `config` ni overrides de instrucciones. `codex-reply`
está bloqueado; una segunda consulta justificada inicia otro review seguro.

El MCP global usa `~/.local/bin/codex-review-mcp`. Trabaja en una carpeta neutral
de esta instalación para no cargar configuración específica de otros proyectos.
Deshabilita shell, subagentes, apps, hooks, navegador, plugins y cada MCP heredado.
Las tablas vacías TOML se fusionan: no sirven para eliminar los MCP del usuario.
Una entrada MCP local/de proyecto puede tener precedencia; comprobar su
aislamiento antes de usarla. No sustituir una interfaz protegida por una directa.

## Verificación, simultaneidad y límites

Aplicar `~/.config/ai-collaboration/VERIFICATION.md` y los gates concretos del repo.
Dos PRIMARY simultáneos en tareas distintas requieren working trees separados.
No crear worktrees automáticamente; un reviewer read-only no necesita uno.

Los hooks globales de Claude protegen secretos y operaciones peligrosas comunes;
los hooks no analizan los efectos indirectos de scripts arbitrarios. Las reglas
nativas ocultan `.env.*` también en búsquedas; incluyen `.env.example`, que se
gestiona manualmente. El usuario conserva sus modelos, plugins y ajustes normales.

El inventario del MCP se fija al arrancar. No cambiar MCP/plugins/configuración
de agentes durante el review. Tras cambiarlos, reconectar `codex` y ejecutar
`~/.local/bin/codex-review-mcp --check` antes de la siguiente consulta. No se
afirma aislamiento frente a cambios concurrentes de terceros.
