# Frente C — RLS, grants, auditoría y documentación

VERDICT: ATENCIÓN

SUMMARY: Los candados básicos están bien puestos. 150 de 151 tablas tienen RLS, `anon` no tiene ningún permiso en `crm` ni en `private`, ninguna tabla de `private` se abre a `authenticated`, y 117 de las 118 tablas de `crm` tienen bitácora. No encontré ningún rol que hoy vea filas que su ámbito no le permite (sin P0). Lo que falla es más fino:
(1) el DNI, la fecha de nacimiento y el género de `crm.leads` se pueden leer porque hay un permiso de lectura sobre la tabla entera, así que los permisos por columna no recortan nada;
(2) un analista puede reescribir a mano el registro de consentimiento (el de INDECOPI) de sus leads;
(3) cuatro tablas con DNI, documento o domicilio guardan esos datos sin tapar en `public.audit_log`, cuando el DNI del lead sí se tapa.
El resto es deuda: escrituras directas desde la pantalla ya conocidas, tablas de configuración y permisos en `private` sin bitácora, una tabla de respaldo sin RLS, comentarios incompletos y nombres que no siguen la regla.

Fuentes: `resumen-tablas.json`, `catalogo-estructura.sql` (las líneas citadas son de este archivo, salvo que se indique otra cosa), `esquema-prod-20261022.sql` para los cuerpos vivos de las funciones, y las migraciones del repo. No ejecuté nada contra producción.

## FINDINGS

### [P1] C-1 · Los datos personales de `crm.leads` no se recortan por columna: se leen gracias al permiso sobre la tabla entera
- Tabla/grant/policy: `crm.leads` · `GRANT SELECT ON TABLE crm.leads TO authenticated` · policy `leads_select`.
- Evidencia:
  - L7374 `GRANT SELECT ON TABLE "crm"."leads" TO "authenticated";` es una lectura de TABLA, así que cubre las 42 columnas. Por eso `dni`, `fecha_nacimiento` y `genero` se leen por la API directa (`/rest/v1/leads?select=dni,fecha_nacimiento,genero`, esquema `crm` expuesto).
  - L7426/L7430 conceden además `SELECT("genero")` y `SELECT("fecha_nacimiento")` a `authenticated`, lo contrario de restringir. `dni` no tiene permiso propio y vive solo del permiso de tabla.
  - La propia migración `20260919211105_crm_leads_grant_columna_procedencia.sql` (líneas 11-20) lo reconoce: el permiso por columna «NO es una red… Su valor es de convención y de registro».
  - `leads_select` (L7017) abre filas a cinco caminos: vendedor y supervisor por árbol, `gerencia`, `es_lector_global()` (Directorio) y `es_coordinacion_consulta()` (todo lead activo, desde `20261015211217` y unificado en `20261015224848`).
  - La premisa anterior de la cola de Coordinación era «sin teléfono/correo/DNI; private.redactar_pii es la fuente única» (`20260724203052_crm_descartados_coordinador_c1c.sql:28-29`). Con la consulta global del 15/10, Coordinación lee esos campos sin tapar por la API directa y se salta el redactado de las RPC.
- Por qué importa: la casa pide que los datos personales tengan «lectura limitada por rol». Hoy el único límite es por fila. Cualquier rol que ve el lead ve su DNI, su fecha de nacimiento y su género, incluido el rol de consulta que antes los recibía tapados. No lo marco P0 porque cada fila solo la ve quien su ámbito autoriza. Es una HIPÓTESIS que Coordinación no debiera ver el DNI: hay que confirmar con Miguel si la consulta global del 15/10 debía incluirlo.
- Qué haría falta (sin implementar): decidir qué roles ven `dni`, `fecha_nacimiento` y `genero`. Si no son todos, pasar `crm.leads` a privilegios por columna (quitar la lectura de tabla y conceder las columnas una a una) o servir esos campos solo por una RPC que redacte según el rol.
- SQL de comprobación (solo lectura):
  ```sql
  select relacl from pg_class where oid = 'crm.leads'::regclass;  -- esperado: incluye authenticated=r…/postgres (lectura de tabla)
  select a.attname,
         has_column_privilege('authenticated', a.attrelid, a.attnum, 'SELECT') as authenticated_lee,
         a.attacl as acl_propia
  from pg_attribute a
  where a.attrelid = 'crm.leads'::regclass and a.attnum > 0 and not a.attisdropped
    and a.attname in ('dni','fecha_nacimiento','genero','telefono','telefono_alternativo','correo');
  select polname, pg_get_expr(polqual, polrelid) from pg_policy
  where polrelid = 'crm.leads'::regclass and polcmd in ('r','*');
  ```

### [P1] C-2 · Un analista puede reescribir el registro de consentimiento (INDECOPI) de sus leads
- Tabla/grant: `crm.leads.consentimiento_en` y `crm.leads.consentimiento_fuente` · `GRANT … UPDATE(consentimiento_en)` y `UPDATE(consentimiento_fuente)` a `authenticated` (L7438, L7442) · policy `leads_update` (L7019).
- Evidencia:
  - El COMMENT de la columna dice «Cuando el lead consintio ser contactado (registro para INDECOPI)» (`esquema-prod`, L79913).
  - En el volcado vivo ningún trigger de `crm.leads` toca estas columnas. `grep consentimiento` sobre `esquema-prod-20261022.sql` solo devuelve el importador (L17643-17697), el CHECK y los permisos. `private.leads_before_update` (esquema-prod L53100) restaura `id`, `creado_por`, `alta_manual` y `creado_en`, pero no el consentimiento.
  - La pantalla no usa el campo: no hay ninguna aparición de `consentimiento` en `app/src` fuera de los tipos.
  - Aun así, `actualizarLead` envía un `cambios` libre: `cliente().schema('crm').from('leads').update(cambios)` en `app/src/data/crm-api.ts:2939`. `leads_update` deja que el vendedor, el supervisor del árbol o Gerencia actualicen el lead.
- Por qué importa: es la prueba legal de que el lead aceptó que lo contacten. Hoy quien tiene el lead puede cambiar su fecha y su fuente con un PATCH. Queda rastro en `public.audit_log` (`trg_audit_leads` no enmascara estas columnas), pero es un permiso de más sobre la tabla más viva (4 539 filas).
- Qué haría falta (sin implementar): quitar `UPDATE(consentimiento_en, consentimiento_fuente)` a `authenticated`, o restaurarlos desde OLD en `leads_before_update` como ya se hace con `alta_manual`.
- SQL de comprobación (solo lectura):
  ```sql
  select a.attname, has_column_privilege('authenticated', a.attrelid, a.attnum, 'UPDATE') as authenticated_actualiza
  from pg_attribute a where a.attrelid = 'crm.leads'::regclass and a.attname in ('consentimiento_en','consentimiento_fuente');
  select t.tgname, p.proname from pg_trigger t join pg_proc p on p.oid = t.tgfoid
  where t.tgrelid = 'crm.leads'::regclass and not t.tgisinternal and p.prosrc ilike '%consentimiento%';  -- esperado: 0 filas
  -- cuántas veces se movió ya (solo conteo; recorre el rastro de crm.leads, puede tardar):
  select count(*) from public.audit_log
  where tabla = 'crm.leads' and operacion = 'UPDATE'
    and (data_antes->>'consentimiento_en' is distinct from data_despues->>'consentimiento_en'
      or data_antes->>'consentimiento_fuente' is distinct from data_despues->>'consentimiento_fuente');
  ```

### [P1] C-3 · DNI, documento y domicilio sin tapar en la bitácora: cuatro tablas usan `log_audit_crm()` sin enmascarar
- Tablas/triggers:
  - `crm.verificaciones_lead` (1 621 filas; `dni_consultado`, `telefono_consultado`): `trg_audit_verificaciones_lead` → `private.log_audit_crm()` (L5486).
  - `crm.recordatorios_disponibilidad` (1 fila; `dni`, `telefono`): L5458.
  - `crm.solicitudes_tasa` (0 filas; `documento_lead`): L5476.
  - `crm.inversionista_datos_contacto` (0 filas; `domicilio`, `telefono`, `nombre_completo`): L5354.
- Evidencia:
  - El cuerpo vivo de `private.log_audit_crm()` (esquema-prod L55531-55571) solo quita columnas en un caso: `if tg_table_schema = 'crm' and tg_table_name = 'cuentas_bancarias'` (L55559). Las demás tablas pasan `to_jsonb(new/old)` completo a `public.audit_log`.
  - En cambio, `crm.leads` usa `log_audit_sin_secretos('dni','fecha_nacimiento','genero')` (L5392), y `inversionista_identificadores`, `cierres_externos` y `busquedas_cliente_existente` también enmascaran el documento.
  - Los COMMENT de `verificaciones_lead` (L3234) y de `recordatorios_disponibilidad` (L2919) dicen que «su rastro en public.audit_log es legible por admin/superadmin del portal».
- Por qué importa: el DNI que se tapa en el rastro del lead aparece sin tapar en el rastro de la verificación del mismo lead. Quien lee `public.audit_log` lo recupera por ese camino. La regla de la casa es que no haya secretos en la bitácora.
- Qué haría falta (sin implementar): pasar esos cuatro triggers a `log_audit_sin_secretos(...)` con las columnas `dni_consultado`, `telefono_consultado`, `dni`, `documento_lead` y `domicilio`, como ya está hecho en `crm.leads`.
- SQL de comprobación (solo lectura, solo conteos):
  ```sql
  select t.tgrelid::regclass as tabla, t.tgname
  from pg_trigger t
  where not t.tgisinternal and t.tgfoid = 'private.log_audit_crm()'::regprocedure
    and t.tgrelid in ('crm.verificaciones_lead'::regclass, 'crm.recordatorios_disponibilidad'::regclass,
                      'crm.solicitudes_tasa'::regclass, 'crm.inversionista_datos_contacto'::regclass);
  select tabla, count(*) as filas_con_dato_sin_tapar
  from public.audit_log
  where tabla in ('crm.verificaciones_lead','crm.recordatorios_disponibilidad','crm.solicitudes_tasa','crm.inversionista_datos_contacto')
    and (coalesce(data_despues, data_antes)->>'dni_consultado' is not null
      or coalesce(data_despues, data_antes)->>'dni' is not null
      or coalesce(data_despues, data_antes)->>'documento_lead' is not null
      or coalesce(data_despues, data_antes)->>'domicilio' is not null)
  group by tabla;
  select polname, polcmd, pg_get_expr(polqual, polrelid) from pg_policy where polrelid = 'public.audit_log'::regclass;
  ```

### [P2] C-4 · `authenticated` escribe directo en 8 tablas, dos de ellas de configuración que se sobrescriben en sitio
- Grants:
  - `crm.actividades` INSERT (L7332).
  - `crm.agenda_ics` INSERT y UPDATE (L7338).
  - `crm.alertas_reconocimientos` INSERT (L7330).
  - `crm.enfriamiento_politica` INSERT y UPDATE (L7358).
  - `crm.politica_abandono` UPDATE (L7508).
  - `crm.recordatorios_disponibilidad` INSERT, UPDATE y DELETE (L7524).
  - `crm.tareas` INSERT, más `UPDATE(vence_en)` y `UPDATE(confirmada_en)` (L7282-7288).
  - `crm.leads` UPDATE sobre 41 de 42 columnas (L7378-7484; solo falta `campania_origen`).
- Evidencia: las 8 tienen una policy por cada orden concedida y su trigger de bitácora. `enfriamiento_politica` y `politica_abandono` se editan con UPDATE sobre la fila viva (COMMENT L1490 y L2720: «Editable solo por gerencia»). En cambio `sla_politicas`, `politica_gestion_diaria` y `meta_periodos` son versionadas e inmutables (`trg_config_versionada_inmutable`).
- Por qué importa: la regla de capas dice que la pantalla no escribe tablas. Son saltos ya medidos en `PLAN-CIERRE-SALTOS.md` y no abren acceso ajeno (todas filtran por dueño o por rol). Lo que más pesa es que dos políticas de negocio se sobrescriben sin versión. Su historia solo queda en `public.audit_log`.
- Qué haría falta (sin implementar): cerrarlos por el plan de saltos, un paso por PR. Para las dos políticas, valorar el mismo molde versionado que `politica_gestion_diaria`.
- SQL de comprobación (solo lectura):
  ```sql
  select c.oid::regclass as tabla, x.priv
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  cross join (values ('INSERT'),('UPDATE'),('DELETE')) x(priv)
  where n.nspname in ('crm','private') and c.relkind in ('r','p')
    and has_table_privilege('authenticated', c.oid, x.priv)
  order by 1, 2;
  select c.oid::regclass as tabla, count(*) as columnas_con_update
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
  where n.nspname = 'crm' and c.relkind = 'r'
    and not has_table_privilege('authenticated', c.oid, 'UPDATE')
    and has_column_privilege('authenticated', c.oid, a.attnum, 'UPDATE')
  group by 1;
  ```

### [P2] C-5 · Tablas de permisos y configuración en `private` (y una de `crm`) sin bitácora o con bitácora incompleta
- Permisos:
  - `private.pares_autoridad`: decide qué pares de rol Portal↔CRM pueden existir (COMMENT L3789).
  - No tiene trigger de bitácora. Solo bloquea DELETE y TRUNCATE (`trg_pares_autoridad_no_borrar`, L5922). Un INSERT o un UPDATE de un par no deja rastro.
  - No tiene PK.
  - La estadística dice 0 filas, pero `20260830170000_crm_f5_b_una_pregunta_por_capacidad.sql:184` inserta 8 pares: pedir `count(*)`.
- Configuración:
  - `private.agenda_reparto_diaria` (16 filas) y `private.agenda_reparto_destinos` (qué supervisor recibe leads de cada origen y día) no tienen triggers. El historial de `diaria` lo escribe la puerta en `private.agenda_reparto_cambios` (`20261015171407…:936-944`); una escritura por otra vía no deja rastro. `destinos` no tiene ninguno.
  - Las exenciones y topes de los vigías (`private.analista_vigencia_exenciones`, `analista_vigencia_tope`, `analitica_leads_citas_exenciones`, `analitica_leads_citas_tope`) no tienen bitácora. Su hermana `private.auditoria_exenciones` sí la tiene (`trg_audit_auditoria_exenciones`, L5902). Los topes solo pueden bajar (`*_solo_baja`), pero las exenciones se pueden insertar sin rastro.
  - `crm.capital_valoracion_politica` (1 fila, singleton): `trg_audit_capital_valoracion_politica AFTER INSERT OR UPDATE` (L5276). No audita DELETE ni tiene candado de inmutabilidad, así que un DELETE no deja rastro.
- Por qué importa: la casa pide bitácora en permisos y configuración. Una exención nueva puede silenciar un vigía, y un par nuevo cambia quién tiene autoridad. Hoy solo las escribe el dueño, por migración o DEFINER (no hay permisos a API), lo que baja la urgencia.
- Qué haría falta (sin implementar): añadir `trg_audit_*` (INSERT, UPDATE y DELETE) a esas tablas y DELETE al trigger de `capital_valoracion_politica`, o un candado de inmutabilidad equivalente.
- SQL de comprobación (solo lectura; bits de tgtype: 4 = INSERT, 8 = DELETE, 16 = UPDATE):
  ```sql
  select c.oid::regclass as tabla,
    coalesce(bool_or(t.tgtype & 4  > 0) filter (where t.tgfoid in ('private.log_audit_crm()'::regprocedure,'private.log_audit_sin_secretos()'::regprocedure)), false) as audita_insert,
    coalesce(bool_or(t.tgtype & 16 > 0) filter (where t.tgfoid in ('private.log_audit_crm()'::regprocedure,'private.log_audit_sin_secretos()'::regprocedure)), false) as audita_update,
    coalesce(bool_or(t.tgtype & 8  > 0) filter (where t.tgfoid in ('private.log_audit_crm()'::regprocedure,'private.log_audit_sin_secretos()'::regprocedure)), false) as audita_delete
  from pg_class c left join pg_trigger t on t.tgrelid = c.oid and not t.tgisinternal
  where c.oid in ('private.pares_autoridad'::regclass, 'private.agenda_reparto_destinos'::regclass,
                  'private.agenda_reparto_diaria'::regclass, 'crm.capital_valoracion_politica'::regclass,
                  'private.analista_vigencia_exenciones'::regclass, 'private.analitica_leads_citas_exenciones'::regclass,
                  'private.analista_vigencia_tope'::regclass, 'private.analitica_leads_citas_tope'::regclass)
  group by 1;
  select count(*) from private.pares_autoridad;
  ```

### [P2] C-6 · Una tabla sin RLS: `private.respaldo_cierre_agosto_2026` (y qué pasa con FORCE)
- Tabla: `private.respaldo_cierre_agosto_2026` (L3791-3797: `tabla text, fila jsonb, guardado_en`, sin PK).
- Evidencia: es la única de las 151 sin `ENABLE ROW LEVEL SECURITY`. Su gemela `respaldo_cierre_septiembre_2026` sí la tiene (L7252). No tiene ningún permiso en el volcado, así que hoy solo la toca `postgres`. La estadística dice 0 filas, pero el COMMENT dice que se restaura con `03-restaurar.sql`: pedir `count(*)` antes de tocarla.
- Por qué importa: la regla dice RLS en todas las tablas, sin excepción, como segundo candado. Si mañana alguien le concede un permiso, quedaría abierta sin filtro.
- Sobre FORCE: FORCE obliga al dueño de la tabla a pasar por RLS. Aquí las 151 tablas son de `postgres`, y `postgres` tiene BYPASSRLS; lo comprueban `20260905190000…:290-293` y `20260908221500…:73-76`. Por eso FORCE no cambia nada hoy para las funciones DEFINER: no hace falta en las 141 tablas sin FORCE y no añade protección en las 10 que lo tienen. Solo importaría si una tabla pasara a un dueño sin BYPASSRLS; ahí FORCE sin policy dejaría a sus propias funciones sin acceso.
- Qué haría falta (sin implementar): `enable row level security` en ese respaldo (sin policies queda cerrado igual), en una migración propia.
- SQL de comprobación (solo lectura):
  ```sql
  select c.oid::regclass, c.relrowsecurity, c.relforcerowsecurity, c.relacl, pg_get_userbyid(c.relowner) as dueno
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname in ('crm','private') and c.relkind in ('r','p') and not c.relrowsecurity;
  select count(*) from private.respaldo_cierre_agosto_2026;
  select rolname, rolbypassrls from pg_roles where rolname = 'postgres';
  ```

### [P3] C-7 · Registros que se dicen «solo añadir» pero que nada obliga a serlo
- Tablas:
  - `crm.cartera_lecturas` (16 353 filas): audita solo INSERT (L5280) y no tiene candado.
  - `crm.tipo_cambio_trabajos` (12): audita INSERT y UPDATE (L5484), no DELETE.
  - `crm.usuario_eventos`: COMMENT «Append-only y cerrada al Data API» (`20260807203740…:630`), pero no tiene ningún trigger, ni de bitácora ni de inmutabilidad.
  - `private.membresias_purgadas`: sin triggers.
- Evidencia: en el JSON, `triggers: []` para `crm.usuario_eventos` y `private.membresias_purgadas`. Las demás tablas con bitácora solo de INSERT sí tienen su candado `*_inmutable(s)` (por ejemplo `capital_valoraciones`, `inversion_eventos`, `inversiones_eliminadas`).
- Por qué importa: son registros en sí mismos. Un UPDATE o DELETE del dueño o de una DEFINER los altera sin dejar rastro. El riesgo es bajo (no tienen permisos a API).
- Qué haría falta (sin implementar): candado BEFORE UPDATE OR DELETE, como `proteger_usuario_retirado`, en `usuario_eventos` y `membresias_purgadas`; y DELETE en el trigger de bitácora de `cartera_lecturas` y `tipo_cambio_trabajos`, o un candado.
- SQL de comprobación (solo lectura):
  ```sql
  select c.oid::regclass, string_agg(t.tgname || ' tgtype=' || t.tgtype, ', ') as triggers
  from pg_class c left join pg_trigger t on t.tgrelid = c.oid and not t.tgisinternal
  where c.oid in ('crm.cartera_lecturas'::regclass, 'crm.tipo_cambio_trabajos'::regclass,
                  'crm.usuario_eventos'::regclass, 'private.membresias_purgadas'::regclass)
  group by 1;
  ```

### [P3] C-8 · Policy FOR DELETE y permiso de DELETE en `crm.recordatorios_disponibilidad`
- Policy/grant: `recordatorios_disponibilidad_delete FOR DELETE TO authenticated USING (perfil_id = auth.uid() AND rol_crm = 'vendedor')` (L7122) y `GRANT SELECT,INSERT,DELETE,UPDATE … TO authenticated` (L7524).
- Evidencia: es la única policy FOR DELETE de los dos esquemas. El COMMENT de la tabla (L2919) lo declara «excepción documentada (nota personal efímera + minimización)», y el borrado queda en la bitácora (L5458).
- Por qué importa: choca con «sin policy DELETE». Está decidido y acotado al recordatorio propio, así que lo dejo solo como constancia para el inventario de excepciones.
- Qué haría falta (sin implementar): nada técnico. Registrar la excepción en `LEEME.md` de migraciones si no está.
- SQL de comprobación (solo lectura):
  ```sql
  select p.polrelid::regclass, p.polname from pg_policy p
  join pg_class c on c.oid = p.polrelid join pg_namespace n on n.oid = c.relnamespace
  where n.nspname in ('crm','private') and p.polcmd = 'd';
  ```

### [P3] C-9 · El gate RESTRICTIVE está en solo 7 tablas; las demás repiten su lógica dentro de la policy, con una rendija y 17 policies que no tienen efecto
- Evidencia:
  - `crm_actor_activo_gate` existe solo en `actividades`, `agenda_ics`, `enfriamiento_politica`, `equipo`, `lead_asignaciones`, `leads` y `tareas`.
  - Las otras 20 tablas con permiso a `authenticated` repiten la comprobación dentro de la policy: `rol_crm(...) IS NOT NULL`, `es_lector_global()`, `es_gerencia_crm_activa()`, `puede_consultar_cliente_ficha()`. Los cuerpos vivos de `rol_crm` y `cliente_ids_visibles_crm` (esquema-prod) exigen membresía y perfil activos. Es equivalente, salvo en tres casos:
  - `solicitudes_tasa_select` (L7154): la rama `solicitada_por = auth.uid()` no pide CRM activo. Un analista dado de baja sigue leyendo sus solicitudes, con `documento_lead`.
  - `correcciones_correo_acceso_lectura` (L6885) usa `public.es_admin()`, admin del Portal y no rol CRM. Es diseño (`20260915173423`).
  - `reasignaciones_lee_autoridad` (L7118) usa `public.es_gestor_cartera()` y `NOT membresia_crm_revocada()`. Es diseño P04 («revocado vs ajeno al CRM»).
  - 17 tablas tienen policies para `authenticated` pero ningún permiso, así que las policies no hacen nada hoy: `inversiones`, `inversionistas`, `inversion_titulares`, `inversionista_fusiones`, `inversionista_identificadores`, `inversionista_leads`, `inversionista_operaciones`, `inversionista_responsables`, `empresas`, `multiempresa_flags`, `multiempresa_idempotencia`, `backfill_multiempresa_mapa`, `bases_carga`, `base_carga_leads`, `base_carga_operaciones`, `lead_potencial` y `lead_potencial_eventos`.
- Por qué importa: con el gate repetido a mano es más fácil olvidarlo en una tabla nueva. Las policies sin efecto hacen creer que hay un acceso que no existe; si alguien concede el permiso, se abren con la condición que tengan.
- Qué haría falta (sin implementar): añadir `crm_actor_activo_gate` a `solicitudes_tasa` (o `puede_acceder_crm()` en su rama propia). Documentar que las 17 policies son defensa en profundidad y no superficie viva.
- SQL de comprobación (solo lectura):
  ```sql
  select c.oid::regclass as tabla, p.polname, p.polpermissive,
         has_table_privilege('authenticated', c.oid, 'SELECT') as tiene_grant,
         exists (select 1 from pg_policy g where g.polrelid = c.oid and g.polname = 'crm_actor_activo_gate') as tiene_gate
  from pg_policy p join pg_class c on c.oid = p.polrelid join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'crm' and 'authenticated'::regrole = any (p.polroles)
  order by tiene_grant, tiene_gate, 1;
  ```

### [P3] C-10 · Los permisos por columna de `crm.leads` no siguen una regla fija
- Evidencia:
  - Ninguna de las 42 columnas queda invisible: todas se leen por el permiso de tabla (L7374).
  - La convención de la casa desde `20260718000001` es dar permiso propio a cada columna que la pantalla o una RPC invoker necesitan. Cinco columnas posteriores no tienen `SELECT` propio, solo `UPDATE`: `sla_global_iniciado_en` y `sla_global_aproximado` (`20260718152741`), `telefono_alternativo` y `telefono_alternativo_crudo` (`20260826173523`) e `inversionista_id` (`20260903160000`).
  - `authenticated` tiene UPDATE sobre columnas que los triggers revierten en silencio: `id`, `creado_por`, `alta_manual`, `creado_en` y `actualizado_en` (`leads_before_update`, esquema-prod L53100-53113); `perfil_id`, `contrato_id` y `convertido_en` (misma función, sin operación privilegiada); `ciclo_actual` (`trg_leads_guard_tenencia`, esquema-prod L72186), `clasificacion_auto` (`trg_leads_zz_sello_descarte`, L73151) y `sla_global_*` (`trg_leads_sla_global`, L72623-72646).
  - `service_role` tiene permisos por columna redundantes: ya tiene `SELECT,INSERT,DELETE,UPDATE` de tabla (L7376).
- Por qué importa: si algún día se pasa a privilegios por columna (lo que pide C-1), estas cinco columnas desaparecerían de la pantalla en silencio. Los UPDATE que no hacen nada confunden al leer los permisos.
- Qué haría falta (sin implementar): mantener la lista «columnas a reponer» en `MIGRACIONES.md` con estas cinco, y dejar de conceder UPDATE sobre columnas que el núcleo revierte.
- SQL de comprobación (solo lectura):
  ```sql
  select a.attname,
         exists (select 1 from aclexplode(a.attacl) x where x.grantee = 'authenticated'::regrole and x.privilege_type = 'SELECT') as select_propio,
         exists (select 1 from aclexplode(a.attacl) x where x.grantee = 'authenticated'::regrole and x.privilege_type = 'UPDATE') as update_propio
  from pg_attribute a
  where a.attrelid = 'crm.leads'::regclass and a.attnum > 0 and not a.attisdropped
  order by a.attnum;
  ```

### [P3] C-11 · 35 tablas sin `COMMENT ON TABLE` (20 de ellas con filas)
- Con filas:
  - En `crm`: `cartera_lecturas` (16 353), `sla_operacion_recibos` (15 218), `inversionista_gestiones` (502), `inversion_solicitudes` (422), `inversion_eventos` (355), `conversion_acreditaciones` (306), `inversion_solicitud_correcciones` (190), `postventa_operaciones` (162), `correcciones_categoria_contrato` (24), `tipo_cambio_trabajos` (12), `dispositivos_push_tasa` (4), `capital_valoracion_politica` (1), `inversion_cotitular_origenes` (1) e `inversion_solicitud_origenes` (1).
  - En `private`: `agenda_reparto_cambios` (16), `agenda_reparto_diaria` (16) y `ayuda_consultas` (1).
- Sin filas: `crm.control_citas_aplicaciones`, `conversion_politica`, `envios_push_tasa`, `inversion_solicitud_revisiones`, `inversionista_datos_contacto`, `postventa_escrituras`, `postventa_retiros`, `sla_politica_etapas`, y en `private`: `agenda_reparto_destinos`, `analista_vigencia_tope`, `analitica_lc_sello`, `analitica_leads_citas_tope`, `ayuda_expresiones`, `ayuda_intenciones`, `ayuda_reglas_aclaracion`, `backfill_cuentas_p0xx`, `conciliacion_cuentas_p0xx` y `usuarios_retirados`.
- Evidencia: `comentario_tabla: false` en `resumen-tablas.json` (el recuento de `resumen.py` da 35).
- Por qué importa: la regla pide `COMMENT ON` en toda tabla. Varias son de dinero (`inversion_solicitudes`, `conversion_acreditaciones`) o de datos personales (`inversionista_datos_contacto`).
- Qué haría falta (sin implementar): una migración solo de comentarios, empezando por las tablas con filas.
- SQL de comprobación (solo lectura):
  ```sql
  select c.oid::regclass from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname in ('crm','private') and c.relkind = 'r' and obj_description(c.oid, 'pg_class') is null order by 1;
  ```

### [P3] C-12 · Solo el 27 % de las columnas tiene comentario (389 de 1 454); 67 tablas con filas están por debajo del 50 %
- Evidencia:
  - Tablas vivas sin ninguna columna comentada: `actividades` (33 984 filas, 0/7), `cartera_lecturas` (0/5), `sla_operacion_recibos` (0/9), `tarea_sla_contexto` (0/5), `lead_sla_etapas` (0/12), `lead_asignacion_sla_hitos` (0/5), `lead_sla_ciclos` (0/11), `metas_vendedor_detalle` (0/7), `actividad_ciclo_contexto` (0/7), `verificaciones_lead` (0/6), `producto_versiones` (0/17), `contrato_cuentas_pago` (0/5), `inversionistas` (0/12), `inversionista_identificadores` (0/12), `inversionista_responsables` (0/8), `inversion_titulares` (0/6), y en `private`: `contrato_pdf_jobs` (0/20) y `contrato_pdfs` (0/13).
  - `crm.leads` tiene 20/42 (48 %): las 22 columnas originales, incluida `dni`, no tienen comentario.
- Por qué importa: es deuda de documentación. No hay riesgo directo, pero impide marcar los datos sensibles (C-13).
- Qué haría falta (sin implementar): completar los comentarios por tabla viva, empezando por las de datos personales y dinero.
- SQL de comprobación (solo lectura):
  ```sql
  select c.oid::regclass, count(*) filter (where col_description(c.oid, a.attnum) is not null) as comentadas, count(*) as total
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
  where n.nspname in ('crm','private') and c.relkind = 'r'
  group by 1 order by comentadas::numeric / total, 1;
  ```

### [P3] C-13 · Columnas con datos personales sin la marca «DATO PERSONAL» en su comentario
- Evidencia: la casa ya usa la marca en 6 columnas: «DATO(S) PERSONAL(ES)» en `busquedas_cliente_existente.valor_consultado`, `llamadas_celular_eventos.numero_canonico`, `leads_eliminados.copia` e `inversiones_eliminadas.snapshot`, y «DATO SENSIBLE» en `celulares_asignaciones.credencial_hash` y `cuentas_bancarias_retiros.respaldo_ruta`. No la llevan:
  - `crm.leads`: `dni`, `telefono`, `correo` y `nombre_completo` (sin comentario); `fecha_nacimiento` y `genero` (comentadas pero sin marca, L2163/L2165); `telefono_alternativo`.
  - `crm.cuentas_bancarias`: `numero_cuenta`, `cci`, `beneficiario_dni` y `beneficiario_nombre`.
  - `crm.inversionista_identificadores`: `documento_normalizado` y `documento_original`.
  - `crm.inversionista_datos_contacto`: `nombre_completo`, `telefono` y `domicilio`.
  - `crm.verificaciones_lead`: `dni_consultado` y `telefono_consultado`.
  - `crm.recordatorios_disponibilidad`: `dni` y `telefono`.
  - `crm.solicitudes_tasa.documento_lead`.
  - `crm.cierres_externos`: `documento` y `nombre_completo` (L329, sin marca).
  - `crm.correcciones_correo_acceso`: `correo_anterior` y `correo_nuevo`.
  - `crm.contratos_eliminados_auditoria.snapshot`.
  - `private.contrato_pdf_jobs.snapshot` y `private.contrato_pdfs.snapshot`.
- Por qué importa: la regla de migraciones pide marcar los datos personales en el comentario. La marca es lo que permite detectar con una consulta casos como C-3.
- Qué haría falta (sin implementar): añadir «DATO PERSONAL.» al COMMENT de esas columnas en la misma migración de C-11/C-12.
- SQL de comprobación (solo lectura):
  ```sql
  select c.oid::regclass as tabla, a.attname, col_description(c.oid, a.attnum) as comentario
  from pg_attribute a join pg_class c on c.oid = a.attrelid join pg_namespace n on n.oid = c.relnamespace
  where n.nspname in ('crm','private') and c.relkind = 'r' and a.attnum > 0 and not a.attisdropped
    and a.attname ~ '(dni|documento|nacimiento|genero|cci|numero_cuenta|domicilio|telefono|correo|snapshot)'
    and coalesce(col_description(c.oid, a.attnum), '') !~* '(dato personal|datos personales|dato sensible)'
  order by 1, 2;
  ```

### [P3] C-14 · Nombres fuera de la regla
- Evidencia (`resumen-tablas.json`):
  - Tablas en singular con muchas filas: `crm.actividad_ciclo_contexto`, `crm.tarea_sla_contexto`, `crm.cierre_mes_vendedor`, `crm.lead_potencial`, `crm.ledger_rentabilidad`, `crm.tipo_cambio_diario`, `crm.multiempresa_idempotencia`, `crm.backfill_multiempresa_mapa` y `private.auditoria_condicionada`. Las de configuración de una sola fila (`*_politica`, `politica_*`, `*_control`, `*_tope`, `*_sello`, `configuracion_reparto`) se pueden defender en singular.
  - Palabras en inglés: `ledger_*`, `backfill_*`, `singleton` (booleano en 4 tablas), `payload` (2), `hash_*` (6 columnas), `token` / `lease_token`, `storage_bucket` / `storage_path`, `sha256` y `bytes`. `endpoint`, `p256dh` y `auth` son nombres del estándar Web Push y se pueden tolerar.
  - Booleanos sin `es_`/`tiene_` (28 nombres): por ejemplo `alta_manual`, `no_contactar`, `aproximado`, `automatico`, `divergente`, `verificado`, `unica`/`unico`, `titular_distinto`. Tres además están en plural: `habilitados`, `cortes_activos`, `entrantes_activas`.
  - Llaves foráneas sin `_id`: `por` (`inversionista_fusiones`, `inversionista_operaciones`, `inversionista_responsables`, `lead_potencial_eventos`), `actor` (`base_carga_operaciones`), `revisor` (`backfill_multiempresa_mapa`), `analista_a` y `analista_de` (`reasignaciones_analista`), `acreditado_a` (`cierres_avance_anulados`) y `reagendada_de` (`tareas`). Los `*_por` (`creado_por`, `actualizado_por`…) son una convención propia y coherente, así que no los cuento.
  - No hay `created_at`, `updated_at` ni `status`, ni identificadores con tilde o ñ.
- Por qué importa: es cosmético, pero renombrar más tarde es un cambio de contrato.
- Qué haría falta (sin implementar): aplicar la regla solo en tablas nuevas. No renombrar las vivas de paso en otra tarea.
- SQL de comprobación (solo lectura):
  ```sql
  select c.oid::regclass, a.attname
  from pg_attribute a join pg_class c on c.oid = a.attrelid join pg_namespace n on n.oid = c.relnamespace
  where n.nspname in ('crm','private') and c.relkind = 'r' and a.attnum > 0 and not a.attisdropped
    and a.atttypid = 'boolean'::regtype and a.attname !~ '^(es_|tiene_|activo$|activa$)'
  order by 1, 2;
  select k.conrelid::regclass, a.attname
  from pg_constraint k join pg_class c on c.oid = k.conrelid join pg_namespace n on n.oid = c.relnamespace
  join pg_attribute a on a.attrelid = k.conrelid and a.attnum = any (k.conkey)
  where k.contype = 'f' and n.nspname in ('crm','private') and a.attname !~ '(_id|_por|^id)$'
  order by 1, 2;
  ```

## CUBIERTO

| Regla | Estado medido |
|---|---|
| RLS en toda tabla | 150/151. Solo falta `private.respaldo_cierre_agosto_2026` (C-6), que no tiene permisos. |
| `anon` | 0 permisos de tabla y 0 USAGE en `crm` y `private` (no hay ninguna línea `TO "anon"` en el volcado). |
| Tablas de `private` | 0 permisos de tabla a `authenticated` o `anon` (33/33). El USAGE del esquema a `authenticated` solo sirve para que las policies llamen a sus funciones auxiliares. |
| Cerrado por defecto | 124/151 sin permiso a `authenticated` (115 sin ningún permiso); 101 con RLS y sin policies (solo las tocan funciones DEFINER). |
| Dueño y FORCE | 151/151 son de `postgres` (con BYPASSRLS). FORCE en 10 tablas no tiene efecto hoy y no hace falta en otras (C-6). |
| `USING (true)` / `WITH CHECK (true)` | 0 WITH CHECK (true). Un solo USING (true) permisivo, `enfriamiento_select` (catálogo de configuración, con gate RESTRICTIVE): justificado. El otro (`tareas_destino_efectivo_update`) es RESTRICTIVE y no abre nada. |
| Policies peligrosas | 0 permisivas FOR ALL. 1 FOR DELETE, documentada (C-8). Las 2 de `private` son RESTRICTIVE `USING (false)`. |
| Gate de actor activo | 7 tablas con `crm_actor_activo_gate` y 20 con la comprobación equivalente dentro de la policy. Única rendija: la rama propia de `solicitudes_tasa` (C-9). |
| Bitácora en `crm` | 117/118 tablas con `log_audit_*` (falta `usuario_eventos`, que es un registro en sí, C-7). Todas las de la lista PII/dinero/permisos/configuración de `crm` tienen trigger. Las que auditan solo INSERT tienen candado de inmutabilidad, salvo `cartera_lecturas` (C-7). |
| Bitácora sin secretos | `leads` → `log_audit_sin_secretos('dni','fecha_nacimiento','genero')`; `cuentas_bancarias` enmascarada dentro de `log_audit_crm` (numero_cuenta, cci, beneficiario_dni). `inversionista_identificadores`, `cierres_externos`, `busquedas_cliente_existente`, `celulares_asignaciones`, `dispositivos_push_tasa`, `agenda_ics`, `leads_eliminados`, `inversiones_eliminadas`, `inversion_solicitudes` y `llamadas_celular_eventos` enmascaran. Fallan 4 tablas (C-3). |
| Altas de `crm.leads` | `authenticated` no tiene INSERT de tabla ni de columna: el alta va solo por RPC. Las columnas inmutables se restauran desde OLD. Ninguna de las 42 columnas queda invisible a la pantalla. |
| Vistas de `crm` | 3/3 con `security_invoker = true` y COMMENT. |
| Roles puente | `crm_gestion_diaria_lector`: solo SELECT en 2 tablas, cada una con su policy. `crm_metricas_bridge`: sin permisos de tabla. |
| Nombres | Sin tildes ni ñ; sin `created_at`/`updated_at`/`status`. |

Decisiones de diseño que vi y no cuento como hallazgo:
- Consulta global de Coordinación (15/10).
- Lectura de `correcciones_correo_acceso` por admin del Portal.
- Lectura de `reasignaciones_analista` por gestor de cartera.
- Rastro de `crm.*` legible por admin/superadmin en `public.audit_log`, según los COMMENT de las tablas. C-3 no discute esa lectura: discute que el rastro lleve el DNI sin tapar.

## CONFIDENCE: media-alta

- Alta en permisos, policies, RLS y triggers: salen del volcado de producción del 22/10 y de los cuerpos vivos de las funciones (`esquema-prod-20261022.sql`), no de migraciones.
- Media en tres puntos:
  - No vi las policies de `public.audit_log` (el volcado solo cubre `crm` y `private`). Me apoyo en los COMMENT de `verificaciones_lead` y `recordatorios_disponibilidad`, que dicen que lo leen admin/superadmin del Portal.
  - Los recuentos de filas son estimados (`n_live_tup`). Un 0 en `pares_autoridad`, `respaldo_cierre_agosto_2026` o `inversionista_datos_contacto` hay que confirmarlo con `count(*)`.
  - Si C-1 (Coordinación con DNI) y C-2 (consentimiento editable) son errores o decisiones no está confirmado: son hipótesis que debe zanjar Miguel.
- No ejecuté nada contra producción. Todos los SQL de arriba son de solo lectura sobre `pg_catalog` o conteos sin datos personales.
