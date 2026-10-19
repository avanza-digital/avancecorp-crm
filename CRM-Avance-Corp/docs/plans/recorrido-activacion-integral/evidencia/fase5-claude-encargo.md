ROLE: SECONDARY_REVIEWER. Codex is PRIMARY. Independent critical review only. Do not modify files, implement, invoke Codex, delegate, or start another review. No tools; all evidence follows. Return VERDICT, SUMMARY, evidence-backed P0–P3 FINDINGS, relevant TEST GAPS/RISKS, NEXT ACTIONS and CONFIDENCE.

Review LEVEL3: pending first lead conversion must require attendance and interview with commercial result, SAME appointment/current cycle, for ALL old and new pending leads. Management/contact are guidance. Stage changes do not count. Preserve confirmed replays, existing-client investments, renewal/upgrade, permissions, immutable financial snapshots and causal evidence. No invented historical backfill. 78 ambiguous old records remain unresolved. n8n not required.

The frontend from PR331 is already published, backend was absent in prod. This task activates it through approved staged plan. Old 8 migrations are committed and unchanged; current diff adds 61000–61004 (5 files): global scope, hardening, index, HTTP409 fix/hardening. Existing local tests were strengthened and HTTP matrix extracted to reuse identical tests in hosted branch. No frontend/Edge change. No .codegraph directory in isolated clone, so source and call contracts used directly.

A read-only RLS reviewer identified two P2 in earlier candidate: installation preflight did not lock control; hardening missed other grantees. Both fixed and exercised in concurrent/install and unexpected pg_monitor-grant negative tests. Treat that original verdict as CHANGES_REQUESTED, not falsely PASS. You are the requested independent Claude review.

Production remains untouched, 509 migrations, backend0/13, guard off/guide hidden. Temporary paid branch approved by user for max24h (delete by2026-10-20T06:29Z). Automatic old replay failed at86 because historical postflight needs a real team member. Following the user's previously chosen manual-parity procedure: restored fresh production DDL only (no clients), exact1168 function bodies/owners/ACL,161 relations,62 column ACL, roles, membership,Storage/Auth,defaultACL/publications. Three semantically equivalent AND parenthesis CHECK differences recorded. Only after parity restored exact509 ledger rows with digest8fe3fd28649301bac91ed91973d1dc8c, then CLI applied exact13 candidates. Final522 history keeps baselineunchanged;12 new functions,5 modified previous functions,2 new tables,originalACL andpublic intact. 24 Edge Functions same SHA/config. No prod cron copied; all cron off in branch. Seed21configtables plus synthetic actors: disable USER triggers only during initial config insertion inside tx, FK active, all restored before any tests.

PASS local: SQL suites, concurrency/response-loss/rollback/replay,81 Auth/HTTP/RLS,42 Docker E2E, script/seed/RLS/Edge preflights. PASS hosted: 81 same HTTP/Auth/RLS tests using real Auth/PostgREST;123requests,max792ms. Official Edge handler runs in process against hosted Auth/REST, not a deployed Edge test. SQL office/old drafts/future activation PASS; corrupt-cycle synthetic fixture uses superuser and is tested ONLY locally (PASS), not hosted. Hosted observe/off/re-enable preserves evidence/snapshots/cut; ROLLBACK restores exact state.

Material hosted finding: custom SQLSTATE40001 on stale revision caused PostgREST14 infinite retry; two runs timed out, only their hanging backends terminated. Additive61003/4 usesPT409; final stale revision returnedHTTP409/codePT409 in170ms. Do not recommend raising40001 for optimistic business conflicts. Official docs: https://supabase.com/docs/guides/troubleshooting/high-cpu-and-infinite-transaction-retries-when-using-custom-error-codes-in-rpc-functions-77326b . Remaining advisors: intentional RLSdeny-all tables,3 authenticated authorized RPCs; singletoncontrol FK needs no index; new office FK index added. Otherbaselinewarnings not hidden.

Scope for verdict: can this exact candidate proceed to PR/CodeRabbit integration and preparation of concrete SQL approval package? Production install/activation and final business acceptance are still NOT RUN and require exact user-approved SQL first per project. Do not infer commercial completion from tests. Prioritize bypasses, old-cohort scope, caller authorization, concurrency, snapshots/retries, scheduled start, immutable activation/reversal, and whether final hosted evidence supports installation.

### PLAN-Y-ESTADO.md
# Puesta en marcha del recorrido: primeras conversiones pendientes

Plan aprobado por Miguel el 19/10/2026: «ok comienza, y dejame este plan en figma, y que pueda ver el progreso».
Continúa el trabajo integrado en PR #331 / Main `3797e6affbed6e97d7ceae00ce0bdc01ae4f2248`. No confundir el Goal previo hasta ZIP con el objetivo comercial operativo.

## Objetivo y alcance aprobado

Impedir toda primera conversión pendiente, de leads nuevos y antiguos, sin asistencia y entrevista con resultado de la misma cita del ciclo vigente. Reutilizar evaluador, cierres, oficina, borradores y controles financieros actuales. Gestión y contacto orientan; no añaden un bloqueo. Cambiar de columna no acredita hechos.

Inversiones confirmadas conservan sus resultados, auditoría y reintentos. Inversiones adicionales, renovación y upgrade de clientes conservan su flujo. No fabricar datos históricos, no backfill de asistencias y no marcar entrevistas en lote. Los registros anteriores sin evidencia suficiente siguen pendientes de comprobación; instalación no los convierte en cumplidos.

El inicio de exigencia es una fecha de activación del control para toda primera conversión pendiente, no una exención según antigüedad del lead. Se conserva el contrato público vigente y la fecha inmutable de primera activación. Una programación futura no bloquea antes de esa fecha. La reversión cambia modo y conserva evidencia.

## Fases

Cada fase tiene 6 subfases. Se cierra tras revisión Codex, corrección y revalidación; los porcentajes representan subfases acreditadas, no tiempo.
1. Alcance y diagnóstico: política → censo → contratos vivos → rutas → dependencias/entorno → revisión documental.
2. Completar regla: migración aditiva → lectura coherente → borradores/reintentos → activación/reversión → permisos/hardening → revisión y correcciones.
3. Pruebas locales: SQL → Auth/HTTP/RLS → UI/E2E Docker → históricos/ausencias → concurrencia/regresión → revisión y correcciones.
4. Ensayo hosted: costo autorizado → rama propia → instalación → matriz RLS → advisors/reversión → revisión y correcciones.
5. Revisión e integración: Claude crítico → PR → CodeRabbit → corregir/revalidar → Main verificado → paquete exacto.
6. Instalación en observación: paquete productivo autorizado → preflight → merge de base → postflight → guía por roles/capacitación → revisión y correcciones.
7. Exigencia: responsable/motivo → control vigente → activar alcance aprobado → rechazos → camino válido/reversión → revisión y correcciones.
8. Aceptación y cierre: negativo sin hechos → positivo misma cita → antiguos cubiertos → reintento sin duplicado → evidencia/capacitación/Figma → revisión final.

## Estado

- Fase 1: PASS documental / 6 de 6. Ver FASE-1-DIAGNOSTICO.md y evidencia.
- Fase 2: PASS local / 6 de 6. Ver FASE-2-REGLA.md.
- Fase 3: PASS local / 6 de 6. SQL, 81 comprobaciones Auth/HTTP/RLS y 42 E2E Docker; ver FASE-3-PRUEBAS.md.
- Fase 4: PASS / 6 de 6. Instalación de 13 migraciones, 81 HTTP/Auth/RLS hosted, reversión y advisors evaluados; ver FASE-4-ENSAYO-HOSTED.md.
- Fase 5: EN CURSO. Revisión crítica de Claude e integración pendientes.
- Fases 6–8: PENDIENTES.
- Producción: backend ausente (0/13 migraciones del paquete integral), guía oculta, bloqueo inactivo.
- Figma: sección comercial 72:190 del mismo archivo, separada del desarrollo técnico 46:190.
- Rama Git: `feat/recorrido-activacion-integral-20261019`, copia aislada existente. Taller compartido preservado.
- Banco local propio existente disponible: `supabase_db_avancecorp-recorrido-lead-20261018`.
- Organización confirmada por Miguel: `AVANCECORP- CRM-PORTAL`. Cotización: US$0.01344 por hora. Gasto y creación autorizados: «Sí, hasta 24 horas». Rama `recorrido-integral-20261019` creada el 19/10 a las 06:29 UTC; eliminar al terminar y, como máximo, antes del 20/10 a las 06:29 UTC.
- Ningún SQL productivo ni activación se ejecutó en esta fase. El paquete concreto se presentará antes de su instalación conforme a las reglas del proyecto.

## Aceptación final

No se cierra por PR, ZIP o instalación en observación. Se exige evidencia de: sin asistencia/entrevista no convierte; misma cita/ciclo válido permite continuar; antiguos incluidos; permisos conservados; reintentos sin duplicados; guía operativa y protocolo de reversión probado.


### FASE-2-REGLA.md
# Fase 2 — Regla para todas las primeras conversiones pendientes

Estado: **PASS local, 6/6 subfases**. No acredita instalación productiva. Candidato en dos migraciones aditivas, 20261019061000/61001; los ocho archivos anteriores permanecen intactos.

1. **Migración aditiva:** el inicio de exigencia se compara con el reloj del servidor, sin filtrar la antigüedad del lead/ciclo. Preflight de cuatro contratos y del control aún no activado. La prueba nueva falló contra el backend anterior precisamente porque dejaba exentos los tres ciclos antiguos; pasó tras instalar el candidato.
2. **Lectura coherente:** la RPC y los guards comparten fecha de inicio y alcance. Una activación programada no bloquea antes de la hora; al llegar incluye también al antiguo. No cambia la forma de la RPC publicada. `recorrido_confirmado` incorpora el alcance en su JSON interno, sin nuevos campos obligatorios de frontend.
3. **Borradores y reintentos:** un borrador anterior a la activación conserva datos, capital y comprobante; no confirma sin hechos. Al acreditar la misma cita confirma una vez y su reintento devuelve la misma inversión. Un antiguo sin ciclo tampoco queda exento.
4. **Activación y reversión:** se mantienen Gerencia efectiva, revisión optimista, motivo auditado y fecha inmutable. Apagar/observar elimina la exigencia sin borrar hechos; reactivar vuelve a cubrir nuevos y antiguos. Se conserva el flujo de inversiones ya confirmadas, adicionales, renovación y upgrade.
5. **Permisos/hardening:** RPC solo `authenticated`; helpers solo propietario `postgres`, SECURITY DEFINER con search_path vacío; RLS y auditoría conservados. Catálogo real en `evidencia/fase2-catalogo.json`.
6. **Revisión y correcciones Codex:** se aceptaron los dos P2 del auditor RLS. La instalación bloquea el singleton hasta COMMIT y el hardening rechaza cualquier grantee privado distinto del propietario. Ambas regresiones pasan, además del replay íntegro en copia desechable.

## Revisión especializada y resolución

Auditor RLS, SECONDARY_REVIEWER de solo lectura: **CHANGES_REQUESTED** sobre la primera versión. No identificó bypass por antigüedad, fecha programada ni ampliación del ámbito de lectura.

| Hallazgo | Decisión del PRIMARY | Evidencia de corrección |
|---|---|---|
| P2: comprobar control previo sin lock permite activación concurrente | Aceptado. `FOR UPDATE` en el preflight, conservado hasta COMMIT | El ensayo observa espera real de activación hasta terminar instalación; un control previamente activado es rechazado. |
| P2: hardening solo prohíbe cuatro destinatarios de EXECUTE | Aceptado. Rechaza todo grantee distinto del owner | Un grant sintético a `pg_monitor` hace fallar hardening; tras rollback, el archivo completo pasa. No existía ese grant en el banco real. |

El reviewer no ejecutó pruebas. Los resultados anteriores corresponden a verificaciones del PRIMARY; no se transformó su dictamen original en un PASS del reviewer.

## Evidencia

- `evidencia/fase2-test-rojo.log`: fallo de política esperado contra versión anterior (tras corregir un permiso del fixture, sin ampliar permisos de producto).
- `evidencia/fase2-instalacion-local.log`, `fase2-test-todos.log`, `fase2-catalogo.json`.
- `evidencia/fase3-test.log`, `fase3-test-oficina.log`, `fase3-test-conversion.log`, `fase3-test-revision.log`, `fase3-test-todos.log`: SQL real con rollback.
- `evidencia/fase3-concurrencia-conversion.log`: replay del paquete, instalación/activación concurrente, grant inesperado, pérdida de respuesta, rollback, invalidación y cambio de modo.

La comprobación de consumidores encontró solo los cinco callers privados/financieros ya conocidos. El frontend publicado no consume `recorrido_confirmado` como objeto estricto y la RPC de lectura conserva su forma. No cambian tablas, argumentos ni tipos generados en este bloque; la nueva clave queda dentro del tipo `Json` existente.

## Límite histórico

Los 78 registros ambiguos del censo no se convierten automáticamente en cumplidos. No se implementa certificación retrospectiva ni excepción masiva. Se debe registrar una atención real con evidencia trazable; no usar «Llegó sin cita» para inventar una visita anterior. La capacitación y el runbook quedan actualizados con el alcance aprobado.

### FASE-4-ENSAYO-HOSTED.md
# Fase 4 — Ensayo en Supabase

**PASS, 6/6 subfases. Producción sin instalar ni activar.** Rama exclusiva `recorrido-integral-20261019`, ref `zwnecxkwsxzybefmdrut`, creada con autorización de gasto hasta 24 horas. Eliminar antes del 20/10/2026 a las 06:29 UTC, o al terminar si ocurre antes.

## Instalación y paridad

El replay automático se detuvo en 86/509 migraciones por el postflight histórico que requiere un miembro real de `crm.equipo`. Se recuperó la rama con el procedimiento de paridad manual elegido previamente por Miguel, sin alterar migraciones históricas ni copiar clientes. No se declara que el replay vacío haya pasado; la etiqueta `MIGRATIONS_FAILED` conserva ese fallo histórico.

Se capturó el esquema vigente, se restauró exclusivamente en la rama vacía y se verificaron 1.168 funciones, 161 relaciones, permisos de 62 columnas, roles, membresías, policies Storage, triggers Auth, permisos por defecto y publicaciones. Se corrigieron los permisos adicionales que heredaba la rama y los comentarios que el volcado había quitado de dos funciones. Solo quedan tres diferencias de paréntesis en CHECK de conjunciones AND: mismas condiciones, tipos y validación. PostgreSQL del banco es 17.11 y producción 17.6; pg_net conserva la versión administrada de cada plataforma. Ningún cron queda activo en la rama.

Después de acreditar paridad se restauraron allí las 509 filas exactas del historial. Huella de esa base: `8fe3fd28649301bac91ed91973d1dc8c`. No se ejecutaron sus backfills históricos. Se aplicaron mediante la CLI las 13 migraciones candidatas del manifiesto: historial final 522, base anterior intacta. La instalación dejó el control en observación, revisión 1 y fecha NULL, antes de los ensayos.

Las 24 Edge Functions coinciden por hash y configuración con producción; el candidato no modifica ninguna. El catálogo final tiene 12 funciones nuevas y cinco cuerpos anteriores modificados, sin cambios de propietarios ni ACL previas. Las dos tablas nuevas y los triggers/columna de evidencia son los previstos. Esquema `public`, Storage, Auth y núcleo SLA conservados.

## Pruebas y correcciones

- **SQL hosted PASS:** atención de oficina, permisos, atomicidad; borrador antiguo bloqueado sin perder datos, evidencia anterior válida, confirmación y reintento único; inicio futuro coherente con el servidor. El fixture de ciclo corrupto requiere superusuario: ese caso no se ejecutó hosted y conserva su PASS local. El SQL exacto del subconjunto remoto está adjunto.
- **HTTP/Auth/RLS hosted: 81 PASS**, 123 peticiones. JWT emitidos por Auth real y llamadas a PostgREST real. Misma matriz versionada que el banco local; el handler oficial de acceso al portal se ejecutó en proceso contra ambos servicios remotos, sin redesplegar Edge. Actores, leads, comprobantes y conversiones exclusivamente ficticios.
- **Hallazgo corregido:** dos intentos de la matriz quedaron esperando el conflicto de revisión del control. El `40001` intencional desencadenaba el bucle de reintentos de PostgREST 14. Se conservaron los diagnósticos, se detuvieron solo los backends de ese ensayo y se añadieron 61003/61004 para responder `PT409`. El ensayo final devolvió **HTTP 409 en 170 ms**, sin sobrescribir el control. [Causa documentada por Supabase](https://supabase.com/docs/guides/troubleshooting/high-cpu-and-infinite-transaction-retries-when-using-custom-error-codes-in-rpc-functions-77326b).
- **Regresión local final PASS:** evaluación SQL, replay de las correcciones y hardening, carreras financieras y matriz HTTP 81/81; `check:scripts` PASS. Los 42 E2E Docker de fase 3 siguen siendo la evidencia de interfaz; no hubo cambios de frontend.
- **Reversión hosted PASS:** observación, apagado y regreso a exigencia conservan la fecha inmutable y el comportamiento esperado del servidor. ROLLBACK deja idénticas las huellas del control, evidencia y confirmaciones.

## Advisors y revisión Codex

No se omiten avisos. Los nuevos avisos fueron revisados contra el baseline productivo y las pruebas:

- Dos tablas con RLS sin policies: cierre deliberado de acceso directo; solo RPC autorizadas. Matriz de anon, service_role, analistas, supervisores, gerencia, coordinación, directorio y membresías inactivas PASS. [Regla del advisor](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy).
- Tres RPC SECURITY DEFINER accesibles a authenticated: exposición deliberada con ámbito y rol comprobados, search_path vacío y helpers privados. Ninguna nueva RPC anónima. [Regla del advisor](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).
- FK de la cita sin índice: corregida por 61002; el aviso desapareció. La FK de `recorrido_control.actualizado_por` no lleva índice adicional porque el control admite una sola fila. [Regla del advisor](https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys).
- El índice recién creado figura todavía sin uso en este banco pequeño. Los demás avisos son previos, incluyendo la configuración Auth de contraseñas filtradas; no se modificó configuración externa ajena al candidato.

Codex verificó alcance, catálogo, permisos, triggers activos, historial, reversión y ausencia de procesos del control atascados. Los hallazgos del ensayo quedaron corregidos y revalidados antes de abrir la fase 5. La revisión independiente de Claude pertenece a esa fase y no se presume aprobada.

## Evidencia

Archivos `evidencia/fase4-*`: paridad base, rama, manifiesto de 13 SQL, postflight, matriz HTTP, SQL remoto, diagnóstico/latencia del conflicto, reversión, advisors y regresiones locales finales. Capturas completas, credenciales y configuraciones originales permanecen privadas fuera del repositorio. No se versionan secretos ni usuarios productivos.

### CRM-Avance-Corp/supabase/migrations/20261019061000_crm_recorrido_todos_pendientes.sql
1: -- Alcance aprobado: todas las primeras conversiones pendientes, nuevas y antiguas.
2: -- La fecha pública cohorte_desde se conserva por compatibilidad: indica cuándo
3: -- comienza la exigencia global; ya no compara el inicio/creación de un lead.
4: -- Instalación previa a la primera activación. No cambia modo, datos ni evidencia.
5: -- Reversión operativa: RPC gerencial a observacion/apagado, conservando auditoría.
6: begin;
7: set local search_path='';
8: set local quote_all_identifiers=off;
9: do $$
10: declare r record;
11: begin
12:   for r in select * from (values
13:     ('private.recorrido_exigir(uuid,text)','41cbc0745b546990ae97e0e91bfa3fb6'),
14:     ('private.recorrido_insert_convertido_guard()','413d9521ba125ae51714081a2986c151'),
15:     ('crm.recorrido_leads_fn(uuid[])','eebb31ea593b765e464e79d824c65d78'),
16:     ('crm.recorrido_configurar_fn(text,text,integer,timestamptz)','07db736b5d832cecd18952648dcf575d'))
17:     as esperado(firma,huella) loop
18:     if to_regprocedure(r.firma) is null or md5(pg_get_functiondef(to_regprocedure(r.firma)))<>r.huella then
19:       raise exception 'El contrato del recorrido cambio: revisar % antes de ampliar el alcance',r.firma using errcode='55000';
20:     end if;
21:   end loop;
22:   -- Serializa esta instalación con la primera activación de Gerencia. El lock
23:   -- se conserva hasta COMMIT: no cambia el alcance de un control ya activado.
24:   perform 1 from crm.recorrido_control where id for update;
25:   if not exists(select 1 from crm.recorrido_control where id and modo in ('observacion','apagado') and cohorte_desde is null) then
26:     raise exception 'El alcance integral se instala antes de la primera activacion; revisar el estado vigente' using errcode='55000';
27:   end if;
28:   perform private.assert_sla_nucleo();
29: end $$;
30: 
31: create or replace function private.recorrido_exigir(p_lead uuid,p_paso text) returns jsonb
32: language plpgsql volatile security definer set search_path='' as $$
33: declare v_l crm.leads%rowtype;v_c crm.recorrido_control%rowtype;v_r jsonb;v_exigible boolean;
34:   v_tarea uuid;v_asistencia uuid;v_identidad_desde timestamptz;
35: begin
36:   -- Las operaciones de clientes existentes conservan el contexto canónico actual.
37:   if p_lead is null then return null;end if;
38:   -- Los callers conservan autorización/identidad. El lock protege hechos y
39:   -- ciclo sin bloquear FK que solo hacen referencia al lead. NOWAIT evita
40:   -- invertir esperas con rutas que llegaron por otra fila.
41:   select * into strict v_l from crm.leads where id=p_lead for no key update nowait;
42:   select * into strict v_c from crm.recorrido_control where id for share;
43:   if v_c.modo='exigir' and current_setting('transaction_isolation')<>'read committed' then
44:     raise exception 'Reintenta la operación en una transacción de lectura vigente' using errcode='55000';
45:   end if;
46:   select resultado into strict v_r from private.recorrido_evaluar(array[p_lead]);
47:   v_exigible:=coalesce(v_c.modo='exigir'
48:     and clock_timestamp()>=v_c.cohorte_desde
49:     and (v_r->>'aplica')::boolean,false);
50:   if v_exigible and not coalesce((v_r->>'habilita_conversion')::boolean,false) then
51:     raise exception using errcode='P0409',
52:       message='Antes de convertir, registra que asistió a su cita y que la entrevista se realizó, con su resultado. Revisa los pasos en la ficha del lead.',
53:       detail=jsonb_build_object('regla','recorrido_lead','paso',p_paso,'lead_id',p_lead,
54:         'ciclo_n',v_l.ciclo_actual,'pendiente',v_r->>'pendiente','revision',v_c.revision)::text;
55:   end if;
56:   -- Fotografía de LA pareja que acreditó la entrevista, no la última asistencia
57:   -- de otra cita del mismo lead. En observación puede quedar incompleta.
58:   v_tarea:=coalesce((v_r#>>'{evidencias,entrevista_tarea_id}')::uuid,
59:     (v_r#>>'{evidencias,asistencia_tarea_id}')::uuid);
60:   if v_tarea is not null then
61:     select resultado_actividad_id into v_asistencia from crm.tareas where id=v_tarea and lead_id=p_lead;
62:   end if;
63:   select min(creado_en) into v_identidad_desde from crm.inversionista_leads
64:     where lead_id=p_lead and inversionista_id=v_l.inversionista_id and rol='canonico';
65:   return jsonb_build_object('version',1,'lead_id',p_lead,'ciclo_n',v_l.ciclo_actual,
66:     'ciclo_inicio',v_r->'ciclo_inicio','modo',v_c.modo,'revision',v_c.revision,
67:     'cohorte_desde',v_c.cohorte_desde,'alcance','primeras_conversiones_pendientes',
68:     'exigible',v_exigible,'estado',v_r->>'estado',
69:     'verificado_en',clock_timestamp(),'identidad_vinculada_en',v_identidad_desde,
70:     'asistencia_tarea_id',v_tarea,'asistencia_id',v_asistencia,
71:     'entrevista_tarea_id',v_r#>'{evidencias,entrevista_tarea_id}');
72: end $$;
73: 
74: create or replace function private.recorrido_insert_convertido_guard() returns trigger
75: language plpgsql security definer set search_path='' as $$
76: declare v_c crm.recorrido_control%rowtype;
77: begin
78:   select * into strict v_c from crm.recorrido_control where id for share;
79:   -- Un INSERT terminal no puede tener asistencia y entrevista de su nuevo ciclo.
80:   -- La antigüedad declarada nunca excluye una primera conversión pendiente.
81:   if v_c.modo='exigir' and clock_timestamp()>=v_c.cohorte_desde then
82:     raise exception 'Registra primero el lead, su asistencia y entrevista; después confirma la inversión'
83:       using errcode='P0409';
84:   end if;
85:   return new;
86: end $$;
87: 
88: create or replace function crm.recorrido_configurar_fn(p_modo text,p_motivo text,p_revision integer,p_cohorte_desde timestamptz default null)
89: returns jsonb language plpgsql security definer set search_path='' as $$
90: declare v_control crm.recorrido_control%rowtype;
91:   v_writer text:=coalesce(current_setting('crm.recorrido_control_writer',true),'off');
92: begin
93:   if not private.es_gerencia_crm_activa() then raise exception 'No autorizado' using errcode='42501'; end if;
94:   if p_modo is null or p_modo not in ('apagado','observacion','exigir')
95:     or p_motivo is null or length(btrim(p_motivo)) not between 8 and 1000
96:     or p_revision is null or (p_cohorte_desde is not null and not isfinite(p_cohorte_desde)) then
97:     raise exception 'Indica modo, motivo y revision validos' using errcode='22023';
98:   end if;
99:   select * into strict v_control from crm.recorrido_control where id for update;
100:   if v_control.revision<>p_revision then raise exception 'El modo cambio; consulta de nuevo' using errcode='40001'; end if;
101:   if v_control.cohorte_desde is not null and p_cohorte_desde is not null and p_cohorte_desde<>v_control.cohorte_desde then
102:     raise exception 'El corte de activacion no se reinicia' using errcode='22023';
103:   end if;
104:   if v_control.cohorte_desde is null and p_cohorte_desde is not null and p_cohorte_desde<clock_timestamp() then
105:     raise exception 'La fecha inicial de exigencia no puede estar en el pasado' using errcode='22023';
106:   end if;
107:   if v_control.cohorte_desde is null and p_cohorte_desde>clock_timestamp()+interval '24 hours' then
108:     raise exception 'Programa la activacion dentro de las proximas 24 horas' using errcode='22023';
109:   end if;
110:   perform set_config('crm.recorrido_control_writer','on',true);
111:   update crm.recorrido_control set modo=p_modo, motivo=btrim(p_motivo), revision=revision+1,
112:     cohorte_desde=coalesce(cohorte_desde,p_cohorte_desde,case when p_modo='exigir' then clock_timestamp() end),
113:     actualizado_por=(select auth.uid()),actualizado_en=clock_timestamp()
114:     where id returning * into v_control;
115:   perform set_config('crm.recorrido_control_writer',v_writer,true);
116:   return to_jsonb(v_control)-'id';
117: end $$;
118: 
119: create or replace function crm.recorrido_leads_fn(p_lead_ids uuid[]) returns jsonb
120: language plpgsql security definer set search_path='' as $$
121: declare v_amb record;v_ids uuid[];v_filas jsonb;v_control crm.recorrido_control%rowtype;
122: begin
123:   select * into strict v_amb from private.sla_operacion_ambito(p_lead_ids,false);
124:   if p_lead_ids is null or cardinality(p_lead_ids)>100 then
125:     raise exception 'Consulta entre cero y cien leads por lote' using errcode='22023';end if;
126:   select array_agg(l.id) into v_ids from crm.leads l where l.id=any(p_lead_ids) and l.activo
127:     and (v_amb.es_global or l.vendedor_id=any(v_amb.visibles)
128:       or (l.vendedor_id is null and l.asignado_supervisor_id=any(v_amb.visibles)));
129:   select * into strict v_control from crm.recorrido_control where id;
130:   select coalesce(jsonb_agg(e.resultado||jsonb_build_object('exigible',coalesce(v_control.modo='exigir'
131:       and clock_timestamp()>=v_control.cohorte_desde
132:       and (e.resultado->>'aplica')::boolean,false)) order by e.lead_id),'[]'::jsonb)
133:     into v_filas from private.recorrido_evaluar(coalesce(v_ids,'{}'::uuid[])) e join crm.leads l on l.id=e.lead_id;
134:   return jsonb_build_object('version',1,'modo',v_control.modo,'revision',v_control.revision,
135:     'cohorte_desde',v_control.cohorte_desde,'filas',v_filas);
136: end $$;
137: 
138: comment on column crm.recorrido_control.cohorte_desde is 'Inicio inmutable de la primera exigencia global. No exime leads o ciclos anteriores; nombre conservado por compatibilidad con la API publicada.';
139: comment on function private.recorrido_exigir(uuid,text) is 'Revalida asistencia y entrevista de la misma cita y ciclo en toda primera conversion pendiente, sin exencion por antiguedad. Preserva snapshot y locks del flujo financiero.';
140: comment on function private.recorrido_insert_convertido_guard() is 'Impide insertar directamente un convertido durante la exigencia global, sin excepcion por creado_en.';
141: comment on function crm.recorrido_leads_fn(uuid[]) is 'Lectura autorizada de hechos actuales: exigible coincide con el control de todas las primeras conversiones pendientes desde la fecha de activacion.';
142: comment on function crm.recorrido_configurar_fn(text,text,integer,timestamptz) is 'Gerencia activa, observa o apaga la exigencia con revision auditada. La fecha marca inicio global, no antiguedad de leads; no se reinicia.';
143: revoke all on function private.recorrido_exigir(uuid,text),private.recorrido_insert_convertido_guard() from public,anon,authenticated,service_role;
144: revoke all on function crm.recorrido_leads_fn(uuid[]),crm.recorrido_configurar_fn(text,text,integer,timestamptz) from public,anon,authenticated,service_role;
145: grant execute on function crm.recorrido_leads_fn(uuid[]),crm.recorrido_configurar_fn(text,text,integer,timestamptz) to authenticated;
146: select private.assert_sla_nucleo();
147: notify pgrst,'reload schema';
148: commit;
149: 

### CRM-Avance-Corp/supabase/migrations/20261019061001_crm_recorrido_todos_pendientes_hardening.sql
1: -- ACL, funciones y guardianes conservados al ampliar el alcance del recorrido.
2: begin;
3: set local search_path='';
4: do $$
5: declare v_firma text;v_oid oid;r record;
6: begin
7:   foreach v_firma in array array['private.recorrido_exigir(uuid,text)',
8:     'private.recorrido_solicitud_guard()','private.recorrido_insert_convertido_guard()'] loop
9:     v_oid:=to_regprocedure(v_firma);
10:     select * into strict r from pg_proc where oid=v_oid;
11:     if pg_get_userbyid(r.proowner)<>'postgres' or not r.prosecdef
12:       or not coalesce('search_path=""'=any(r.proconfig),false) then
13:       raise exception 'Owner, definer o search_path de recorrido incorrecto: %',v_firma;end if;
14:     if exists(select 1 from aclexplode(coalesce(r.proacl,acldefault('f',r.proowner))) a
15:       where a.grantee<>r.proowner) then
16:       raise exception 'Helper expuesto: %',v_firma;end if;
17:   end loop;
18:   foreach v_firma in array array['crm.preparar_persona_lead_inversion_fn(uuid,text,text,text)',
19:     'crm.confirmar_inversion_revisada_fn(uuid,integer)','crm.acceso_inversion_fn(uuid,text,jsonb)',
20:     'private.conversion_lead_con_inversion()'] loop
21:     v_oid:=to_regprocedure(v_firma);
22:     select * into strict r from pg_proc where oid=v_oid;
23:     if pg_get_userbyid(r.proowner)<>'postgres' or not r.prosecdef
24:       or not coalesce('search_path=""'=any(r.proconfig),false)
25:       or position('private.recorrido_exigir' in r.prosrc)=0 then
26:       raise exception 'Defensa no integrada: %',v_firma;end if;
27:     if exists(select 1 from aclexplode(coalesce(r.proacl,acldefault('f',r.proowner))) a
28:       where a.grantee<>r.proowner and not (r.pronamespace='crm'::regnamespace
29:         and a.grantee='authenticated'::regrole and a.privilege_type='EXECUTE')) then
30:       raise exception 'ACL ampliada al integrar recorrido: %',v_firma;end if;
31:   end loop;
32:   foreach v_firma in array array['crm.recorrido_configurar_fn(text,text,integer,timestamptz)',
33:     'crm.recorrido_leads_fn(uuid[])'] loop
34:     select * into strict r from pg_proc where oid=to_regprocedure(v_firma);
35:     if pg_get_userbyid(r.proowner)<>'postgres' or not r.prosecdef
36:       or not coalesce('search_path=""'=any(r.proconfig),false)
37:       or exists(select 1 from aclexplode(coalesce(r.proacl,acldefault('f',r.proowner))) a
38:         where a.grantee<>r.proowner and a.grantee<>'authenticated'::regrole) then
39:       raise exception 'Lectura o control del recorrido ampliaron permisos: %',v_firma;end if;
40:   end loop;
41:   if not (select relrowsecurity from pg_class where oid='crm.inversion_solicitudes'::regclass)
42:     or not exists(select 1 from pg_trigger where tgrelid='crm.inversion_solicitudes'::regclass
43:       and tgname='trg_audit_inversion_solicitudes' and tgenabled='O') then
44:     raise exception 'RLS o auditoría de solicitudes ausente';end if;
45:   if has_column_privilege('authenticated','crm.inversion_solicitudes','recorrido_confirmado','UPDATE')
46:     or has_column_privilege('anon','crm.inversion_solicitudes','recorrido_confirmado','UPDATE') then
47:     raise exception 'La evidencia confirmada no admite escritura directa de API';end if;
48:   perform private.assert_sla_nucleo();
49: end $$;
50: notify pgrst,'reload schema';
51: commit;
52: 

### CRM-Avance-Corp/supabase/migrations/20261019061002_crm_recorrido_indice_cita.sql
1: -- Advisor del ensayo hosted: cubrir la FK de la cita de oficina cuando crezca
2: -- el historial de actividades. El control administrativo tiene una sola fila.
3: begin;
4: set local search_path='';
5: set local lock_timeout='5s';
6: create index actividad_ciclo_contexto_oficina_tarea_idx
7:   on crm.actividad_ciclo_contexto(oficina_tarea_id);
8: do $$
9: begin
10:   if not exists(select 1 from pg_index i join pg_attribute a
11:       on a.attrelid=i.indrelid and a.attname='oficina_tarea_id'
12:       where i.indexrelid='crm.actividad_ciclo_contexto_oficina_tarea_idx'::regclass
13:         and i.indrelid='crm.actividad_ciclo_contexto'::regclass
14:         and i.indisvalid and i.indisready and i.indkey[0]=a.attnum) then
15:     raise exception 'El indice de la cita del recorrido no quedo operativo';
16:   end if;
17:   perform private.assert_sla_nucleo();
18: end $$;
19: commit;
20: 

### CRM-Avance-Corp/supabase/migrations/20261019061003_crm_recorrido_conflicto_http.sql
1: -- Ensayo hosted: PostgREST 14 reintenta indefinidamente un SQLSTATE 40001
2: -- intencional. Una revisión obsoleta es un conflicto HTTP 409, no una carrera
3: -- de serialización que pueda resolverse repitiendo la misma petición.
4: -- https://supabase.com/docs/guides/troubleshooting/high-cpu-and-infinite-transaction-retries-when-using-custom-error-codes-in-rpc-functions-77326b
5: begin;
6: set local search_path='';
7: set local quote_all_identifiers=off;
8: do $$
9: declare v_def text;
10: begin
11:   v_def:=pg_get_functiondef('crm.recorrido_configurar_fn(text,text,integer,timestamptz)'::regprocedure);
12:   if md5(v_def)<>'37384dfb598340150a5dd7a8025d47c5' then
13:     raise exception 'El contrato de configuracion del recorrido cambio; revisar antes de corregir el conflicto HTTP'
14:       using errcode='55000';
15:   end if;
16:   execute replace(v_def,'errcode=''40001''','errcode=''PT409''');
17: end $$;
18: notify pgrst,'reload schema';
19: commit;
20: 

### CRM-Avance-Corp/supabase/migrations/20261019061004_crm_recorrido_conflicto_http_hardening.sql
1: -- El rechazo HTTP conserva la autorización gerencial y no amplía el acceso.
2: begin;
3: set local search_path='';
4: set local quote_all_identifiers=off;
5: do $$
6: declare r record;
7: begin
8:   select * into strict r from pg_proc
9:     where oid='crm.recorrido_configurar_fn(text,text,integer,timestamptz)'::regprocedure;
10:   if md5(pg_get_functiondef(r.oid))<>'6597bef760830dc37673df68e174cbec'
11:     or r.proowner<>'postgres'::regrole or not r.prosecdef
12:     or not coalesce('search_path=""'=any(r.proconfig),false)
13:     or not has_function_privilege('authenticated',r.oid,'EXECUTE')
14:     or exists(select 1 from aclexplode(coalesce(r.proacl,acldefault('f',r.proowner))) a
15:       where a.grantee<>r.proowner and a.grantee<>'authenticated'::regrole) then
16:     raise exception 'El contrato o los permisos del control del recorrido no coinciden';
17:   end if;
18:   perform private.assert_sla_nucleo();
19: end $$;
20: commit;
21: 

### INSTALLED CONTRACT crm.acceso_inversion_fn(uuid,text,jsonb) md5=282a3e9f27385611c6f4d794f977546e
1: CREATE OR REPLACE FUNCTION crm.acceso_inversion_fn(p_solicitud uuid, p_paso text, p_payload jsonb DEFAULT '{}'::jsonb)
2:  RETURNS jsonb
3:  LANGUAGE plpgsql
4:  SECURITY DEFINER
5:  SET search_path TO ''
6:  SET lock_timeout TO '5s'
7: AS $function$
8: declare
9:   v_persona uuid;
10:   v_origen uuid;
11:   v_ctx jsonb;
12:   v_s crm.inversion_solicitudes%rowtype;
13:   v_datos jsonb;
14:   v_auth_ctx jsonb;
15:   v_hash_payload jsonb;
16:   v_saga crm.multiempresa_idempotencia%rowtype;
17:   v_r jsonb;
18:   v_p public.perfiles%rowtype;
19:   v_auth uuid;
20:   v_version integer;
21:   v_token text;
22:   v_otras uuid[];
23: begin
24:   if p_solicitud is null or p_paso is null or p_paso not in ('reclamar','registrar_auth','crear_perfil','enlazar')
25:      or jsonb_typeof(p_payload) is distinct from 'object' then
26:     raise exception 'Solicitud o paso de acceso Avance inválido' using errcode='22023';
27:   end if;
28:   if exists(select 1 from jsonb_object_keys(p_payload) k where
29:     k<>'token' and not (p_paso<>'reclamar' and k='version')
30:     and not (p_paso='registrar_auth' and k='auth_user_id')) then
31:     raise exception 'El paso de acceso contiene campos no admitidos' using errcode='22023';
32:   end if;
33:   v_token:=p_payload->>'token';
34:   if v_token is not null and v_token !~ '^[a-f0-9]{48}$' then
35:     raise exception 'Token de recuperación inválido' using errcode='22023';
36:   end if;
37:   select inversionista_id into v_persona from crm.inversion_solicitudes where id=p_solicitud;
38:   v_origen:=v_persona;
39:   v_ctx:=private.inversion_persona_autorizada_para(v_persona,p_solicitud,null::uuid);
40:   perform private.venta_cruzada_exigir_operador(p_solicitud);
41:   v_persona:=(v_ctx->>'inversionista_id')::uuid;
42:   select * into v_s from crm.inversion_solicitudes where id=p_solicitud for update;
43:   if not found or v_s.inversionista_id is distinct from v_origen then
44:     raise exception 'La solicitud cambió; vuelve a cargarla' using errcode='40001';
45:   end if;
46:   if v_s.estado<>'confirmada' then
47:     v_ctx:=private.inversion_persona_contexto_para(v_persona,(select lead_origen_id from crm.inversion_solicitudes where id=p_solicitud),p_solicitud,null::uuid);
48:   end if;
49:   if not exists(select 1 from crm.empresas e where e.id=v_s.empresa_id and e.clave='avance' and e.activa)
50:      or v_s.estado='cancelada' then
51:     raise exception 'Esta solicitud no permite completar acceso Avance' using errcode='P0409';
52:   end if;
53:   if v_s.estado='preparada' and v_s.responsable_esperado_id is distinct from (v_ctx->>'responsable_id')::uuid then
54:     raise exception 'El responsable cambió; corresponde revisar esta solicitud antes de continuar' using errcode='P0409';
55:   end if;
56: 
57:   -- Un claim terminal conserva su clave de origen después de una fusión.
58:   -- Los contextos anteriores a esta ampliación usaban la persona de la solicitud.
59:   select * into v_saga from crm.multiempresa_idempotencia where clave='auth_persona:'||
60:     case when v_s.auth_claim_id is null then v_persona::text
61:       else coalesce(v_s.auth_contexto->>'inversionista_id',v_origen::text) end;
62:   if v_s.auth_claim_id is not null and
63:     (v_saga.clave is null or v_saga.resultado->>'claim_id' is distinct from v_s.auth_claim_id::text) then
64:     raise exception 'El proceso de acceso original requiere conciliación' using errcode='P0409';
65:   end if;
66:   -- Un enlace concluido se devuelve aunque se perdiera su respuesta. No reinicia
67:   -- Auth ni reescribe el perfil, su clave o su responsable.
68:   if v_ctx->>'perfil_id' is not null and
69:      (v_saga.clave is null or v_saga.resultado->>'estado'='enlazado') then
70:     if v_saga.clave is not null and v_saga.resultado->>'perfil_id' is distinct from v_ctx->>'perfil_id' then
71:       raise exception 'El acceso y la identidad requieren conciliación' using errcode='P0409';
72:     end if;
73:     return jsonb_build_object('estado','enlazado','perfil_id',v_ctx->>'perfil_id',
74:       'inversionista_id',v_persona,'solicitud_id',v_s.id,'reanudar',true);
75:   end if;
76:   if v_s.estado='confirmada' then
77:     raise exception 'El acceso de la inversión confirmada requiere conciliación' using errcode='P0409';
78:   end if;
79:   v_datos:=private.inversion_datos_portal(v_s.datos->'alta_portal');
80:   v_auth_ctx:=coalesce(v_s.auth_contexto,jsonb_build_object('documento_tipo',v_ctx->>'documento_tipo',
81:     'documento',v_ctx->>'documento','responsable_id',v_ctx->>'responsable_id','inversionista_id',v_persona));
82:   if v_auth_ctx->>'documento_tipo' is distinct from v_ctx->>'documento_tipo'
83:      or v_auth_ctx->>'documento' is distinct from v_ctx->>'documento' then
84:     raise exception 'El documento cambió durante el alta; corresponde revisar el acceso pendiente' using errcode='P0409';
85:   end if;
86:   -- Misma proyección que alta_cliente_identidad_fn; los bancos pertenecen a la
87:   -- cuenta contractual de esta inversión. El responsable inicial fija la huella.
88:   v_hash_payload:=private.inversion_payload_acceso(v_persona,v_s.datos->'alta_portal',v_auth_ctx->>'responsable_id');
89: 
90:   if p_paso='reclamar' then
91:     -- Cubre solicitudes anteriores al arreglo e importaciones sin actor. No
92:     -- cambia una credencial que Auth ya creó aunque se perdiera la respuesta.
93:     if v_s.lead_origen_id is not null and exists(select 1 from crm.leads l where l.id=v_s.lead_origen_id
94:       and private.inversion_correo_normalizado(l.correo) is distinct from private.inversion_correo_normalizado(v_datos->>'correo'))
95:       and v_saga.resultado->>'auth_insertado_id' is null
96:       and v_saga.resultado->>'auth_user_id' is null
97:       and not exists(select 1 from auth.users u where u.raw_app_meta_data->>'claim_id'=v_s.auth_claim_id::text) then
98:       raise exception 'El correo de la ficha cambió; revisa los datos de acceso antes de continuar' using errcode='P0409';
99:     end if;
100:     -- Una segunda solicitud no sustituye un alta pendiente de esta persona.
101:     -- Incluso "reclamado" puede tener Auth creado con respuesta perdida.
102:     if v_saga.clave is not null and v_saga.resultado->>'estado'<>'enlazado' then
103:       if exists(select 1 from crm.inversion_solicitudes s where s.id<>v_s.id
104:         and s.auth_claim_id=(v_saga.resultado->>'claim_id')::uuid) then
105:         raise exception 'Completa el acceso pendiente desde su solicitud original' using errcode='P0409';
106:       end if;
107:       if v_saga.hash_payload is distinct from private.idem_hash(v_hash_payload) then
108:         raise exception 'La persona tiene otro alta pendiente; recupera ese proceso con sus datos originales' using errcode='P0409';
109:       end if;
110:     end if;
111:     if v_saga.clave is null then
112:       select array_agg(p.id order by p.id) into v_otras from public.perfiles p
113:       where p.rol='cliente' and p.tipo_documento=v_ctx->>'documento_tipo'
114:         and upper(regexp_replace(coalesce(p.dni,''),'[^A-Za-z0-9]','','g'))=v_ctx->>'documento';
115:       if coalesce(cardinality(v_otras),0)>1 then
116:         raise exception 'Hay varios perfiles con ese documento; requiere conciliación' using errcode='P0409';
117:       elsif cardinality(v_otras)=1 then
118:         perform private.asegurar_identidad_perfil(v_otras[1],'f4_acceso_portal');
119:         v_ctx:=private.inversion_persona_contexto_para(v_persona,(select lead_origen_id from crm.inversion_solicitudes where id=p_solicitud),p_solicitud,null::uuid);
120:         if v_ctx->>'perfil_id' is distinct from v_otras[1]::text then
121:           raise exception 'El perfil existente no pertenece a esta persona' using errcode='P0409';
122:         end if;
123:         return jsonb_build_object('estado','enlazado','perfil_id',v_otras[1],
124:           'inversionista_id',v_persona,'solicitud_id',v_s.id,'reanudar',true);
125:       end if;
126:     end if;
127:     -- Un claim sin efecto externo no exime. Un Auth ya creado con la marca
128:     -- de ESTA solicitud se recupera sin repetir el alta; confirmar revalida.
129:     if v_s.lead_origen_id is not null and not exists(
130:       select 1 from auth.users u where v_s.auth_claim_id is not null
131:         and u.raw_app_meta_data->>'claim_id'=v_s.auth_claim_id::text
132:         and lower(u.email)=v_datos->>'correo') then
133:       perform private.recorrido_exigir(v_s.lead_origen_id,'crear_acceso');
134:     end if;
135:     v_r:=private.saga_auth_reclamar(v_persona,'alta_cliente',v_hash_payload,null,v_token);
136:     if v_r->>'estado'='enlazado' and (v_ctx->>'perfil_id' is null
137:        or v_r->>'perfil_id' is distinct from v_ctx->>'perfil_id') then
138:       raise exception 'El perfil del acceso requiere conciliación con esta persona' using errcode='P0409';
139:     end if;
140:     if v_s.auth_claim_id is not null and v_s.auth_claim_id is distinct from (v_r->>'claim_id')::uuid then
141:       raise exception 'El proceso de acceso cambió; requiere revisión' using errcode='P0409';
142:     end if;
143:     -- El formulario guarda su token ANTES del primer envío. La saga general
144:     -- emite otro token; aquí conservamos el ya conocido para poder recuperar
145:     -- también una respuesta perdida del primer reclamo (sin esperar el lease).
146:     -- saga_auth_reclamar ya verificó el token vigente al retomar. No se altera
147:     -- el claim, su versión, su dueño ni su huella; las otras puertas no cambian.
148:     if v_token is not null and v_r->>'estado'<>'enlazado' then
149:       update crm.multiempresa_idempotencia set resultado=jsonb_set(resultado,'{token_hash}',
150:         to_jsonb(private.saga_token_hash(v_token)))
151:         where clave='auth_persona:'||(v_r->>'inversionista_id') and resultado->>'claim_id'=v_r->>'claim_id';
152:       if not found then
153:         raise exception 'El proceso de acceso cambió; recupera la solicitud' using errcode='40001';
154:       end if;
155:       v_r:=jsonb_set(v_r,'{token}',to_jsonb(v_token));
156:     end if;
157:     update crm.inversion_solicitudes set auth_claim_id=(v_r->>'claim_id')::uuid,
158:       auth_contexto=v_auth_ctx,actualizado_en=statement_timestamp() where id=v_s.id;
159:     return v_r||jsonb_build_object('solicitud_id',v_s.id,'datos_portal',v_datos,
160:       'documento_tipo',v_auth_ctx->>'documento_tipo','documento',v_auth_ctx->>'documento');
161:   end if;
162: 
163:   if v_s.auth_claim_id is null or v_saga.clave is null
164:      or v_saga.resultado->>'claim_id' is distinct from v_s.auth_claim_id::text then
165:     raise exception 'Primero reclama el acceso desde esta solicitud' using errcode='P0409';
166:   end if;
167:   -- El perfil y el avance de estado se confirman juntos. Una versión antigua
168:   -- no puede dejar un perfil insertado ni enlazarlo por fuera de su claim.
169:   select * into v_saga from crm.multiempresa_idempotencia where clave=v_saga.clave for update;
170:   if v_token is null or v_saga.resultado->>'token_hash' is distinct from private.saga_token_hash(v_token) then
171:     raise exception 'Token de recuperación inválido' using errcode='42501';
172:   end if;
173:   begin v_version:=(p_payload->>'version')::integer;
174:   exception when invalid_text_representation or numeric_value_out_of_range then
175:     raise exception 'Versión del acceso inválida' using errcode='22023';
176:   end;
177:   if v_version is null or v_saga.version is distinct from v_version then
178:     raise exception 'El acceso cambió; vuelve a reclamar con tu token' using errcode='40001';
179:   end if;
180:   if p_paso='registrar_auth' then
181:     begin v_auth:=(p_payload->>'auth_user_id')::uuid;
182:     exception when invalid_text_representation then
183:       raise exception 'Identificador de acceso inválido' using errcode='22023';
184:     end;
185:   else
186:     v_auth:=(v_saga.resultado->>'auth_user_id')::uuid;
187:   end if;
188:   if not exists(select 1 from auth.users u where u.id=v_auth
189:     and u.raw_app_meta_data->>'claim_id'=v_s.auth_claim_id::text
190:     and lower(u.email)=v_datos->>'correo') then
191:     raise exception 'El acceso no pertenece a esta solicitud o a su correo' using errcode='P0409';
192:   end if;
193:   if p_paso='registrar_auth' then
194:     return private.saga_auth_avanzar(v_s.auth_claim_id,v_token,'auth_creado',v_auth,null,v_version);
195:   end if;
196:   if v_saga.resultado->>'estado' not in ('auth_creado','perfil_creado') then
197:     raise exception 'El estado del acceso no permite este paso' using errcode='P0409';
198:   end if;
199:   select * into v_p from public.perfiles where id=v_auth for update;
200:   if not found and p_paso='crear_perfil' then
201:     insert into public.perfiles(id,rol,activo,nombre_completo,apellidos,nombres,tipo_documento,dni,
202:       correo,telefono,domicilio,asesor_perfil_id,creado_por,debe_cambiar_password)
203:     values(v_auth,'cliente',true,v_datos->>'nombre_completo',v_datos->>'apellidos',v_datos->>'nombres',
204:       v_auth_ctx->>'documento_tipo',v_auth_ctx->>'documento',v_datos->>'correo',v_datos->>'telefono',
205:       v_datos->>'domicilio',(v_ctx->>'responsable_id')::uuid,(select auth.uid()),true)
206:     returning * into v_p;
207:   end if;
208:   if v_p.id is null or v_p.rol<>'cliente' or v_p.activo is not true
209:      or v_p.tipo_documento is distinct from v_auth_ctx->>'documento_tipo'
210:      or v_p.dni is distinct from v_auth_ctx->>'documento'
211:      or lower(v_p.correo) is distinct from v_datos->>'correo'
212:      or v_p.asesor_perfil_id is distinct from (v_ctx->>'responsable_id')::uuid then
213:     raise exception 'El perfil pendiente requiere conciliación con esta persona y su responsable' using errcode='P0409';
214:   end if;
215:   if p_paso='crear_perfil' then
216:     return private.saga_auth_avanzar(v_s.auth_claim_id,v_token,'perfil_creado',null,v_auth,v_version);
217:   end if;
218:   v_r:=private.asegurar_identidad_perfil(v_auth,'f4_acceso_portal');
219:   if private.inversionista_canonica((v_r->>'inversionista_id')::uuid) is distinct from v_persona then
220:     raise exception 'El perfil no corresponde a la persona de la inversión' using errcode='P0409';
221:   end if;
222:   return private.saga_auth_avanzar(v_s.auth_claim_id,v_token,'enlazado',null,v_auth,v_version)
223:     ||jsonb_build_object('solicitud_id',v_s.id);
224: end;
225: $function$
226: 

### INSTALLED CONTRACT crm.confirmar_inversion_revisada_fn(uuid,integer) md5=33af606a814c74de5de8a080430bb299
1: CREATE OR REPLACE FUNCTION crm.confirmar_inversion_revisada_fn(p_solicitud uuid, p_revision_datos_esperada integer)
2:  RETURNS jsonb
3:  LANGUAGE plpgsql
4:  SECURITY DEFINER
5:  SET search_path TO ''
6:  SET lock_timeout TO '5s'
7: AS $function$begin
8: 
9: declare
10:   v_uid uuid := (select auth.uid());
11:   v_persona uuid;
12:   v_origen uuid;
13:   v_ctx jsonb;
14:   v_s crm.inversion_solicitudes%rowtype;
15:   v_e crm.empresas%rowtype;
16:   v_obj storage.objects%rowtype;
17:   v_cierre uuid;
18:   v_contrato uuid;
19:   v_inversion uuid;
20:   v_fecha date;
21:   v_imputacion date;
22:   v_periodo date;
23:   v_ahora timestamptz := statement_timestamp();
24:   v_ajuste boolean := false;
25:   v_fuente jsonb;
26:   v_payload_contrato jsonb;
27:   v_condicion uuid;
28:   v_config_producto text := current_setting('crm.producto_condicion_id',true);
29:   v_responsable_inicial uuid;
30:   v_res jsonb;
31:   v_config_conversion text:=coalesce(current_setting('crm.op_privilegiada',true),'off');
32: begin
33:   if v_uid is null or not private.puede_gestionar_contratos_crm() then
34:     raise exception 'No autorizado para registrar inversiones' using errcode='42501';
35:   end if;
36:   select inversionista_id into v_persona from crm.inversion_solicitudes where id=p_solicitud;
37:   if not found then raise exception 'Solicitud no encontrada' using errcode='P0002'; end if;
38:   v_origen := v_persona;
39:   v_ctx := private.inversion_persona_autorizada_para(v_persona,p_solicitud,null::uuid);
40:   perform private.venta_cruzada_exigir_operador(p_solicitud);
41:   v_persona := (v_ctx->>'inversionista_id')::uuid;
42:   select * into v_s from crm.inversion_solicitudes where id=p_solicitud for update;
43:   if not found or v_s.inversionista_id is distinct from v_origen then
44:     raise exception 'La solicitud cambió; vuelve a cargarla' using errcode='PT409';
45:   end if;
46:   if v_s.estado='confirmada' then
47:     v_res:=v_s.resultado;
48:     select contrato_id into v_contrato from crm.inversiones where id=v_s.inversion_id;
49:     if v_contrato is not null then
50:       if private.contrato_en_eliminacion(v_contrato) then
51:         raise exception 'El contrato está en proceso de eliminación; requiere revisión' using errcode='55000';
52:       end if;
53:       v_res:=jsonb_set(v_res,'{fuente,pdf}',private.contrato_pdf_estado_base(v_contrato));
54:     end if;
55:     return v_res||jsonb_build_object('inversionista_id',v_persona,'reintento',true);
56:   end if;
57:   if v_s.estado<>'preparada' then raise exception 'La solicitud está cancelada' using errcode='P0409'; end if;
58:   if p_revision_datos_esperada is distinct from v_s.revision_datos then
59:     raise exception 'Los datos cambiaron; revisa la versión vigente antes de confirmar' using errcode='PT409';
60:   end if;
61:   v_ctx := private.inversion_persona_contexto_para(v_persona,v_s.lead_origen_id,p_solicitud,null::uuid);
62:   -- Confirmadas devolvieron arriba su recibo. Antes de cualquier hecho financiero,
63:   -- lectura nueva bajo los candados existentes; no confía en el borrador.
64:   perform private.recorrido_exigir(v_s.lead_origen_id,'confirmar_inversion');
65:   if v_s.puerta='cliente_existente' then
66:     -- Venta cruzada: la venta es del analista congelado y no depende del responsable (D7),
67:     -- pero ese analista tiene que seguir activo para cerrarla.
68:     if not coalesce(private.rol_crm(v_s.analista_cierre_id) in ('vendedor','supervisor'),false) then
69:       raise exception 'El analista de esta venta ya no está activo como vendedor o supervisor; cancela la solicitud y regístrala de nuevo' using errcode='P0409';
70:     end if;
71:     v_ctx := v_ctx||jsonb_build_object('analista_cierre_id',v_s.analista_cierre_id,'puerta',v_s.puerta);
72:   elsif v_s.responsable_esperado_id is distinct from (v_ctx->>'responsable_id')::uuid then
73:     raise exception 'El responsable cambió; revisa esta misma solicitud antes de confirmarla' using errcode='P0409';
74:   end if;
75:   select * into v_e from crm.empresas where id=v_s.empresa_id and activa for share;
76:   if not found then raise exception 'La empresa ya no está disponible para nuevas inversiones' using errcode='P0409'; end if;
77:   if v_e.fuente_capital='cierres_externos' then
78:     -- Se revalida contra el catálogo VIVO: una solicitud preparada cuando la
79:     -- cooperativa admitía una moneda no se confirma si entretanto se retiró.
80:     -- `coalesce` por el mismo motivo que en private.inversion_validar_datos.
81:     if v_s.datos->>'moneda' is null
82:        or not (v_s.datos->>'moneda'=any(coalesce(v_e.monedas,'{}'::text[]))) then
83:       raise exception 'La moneda ya no está admitida por la cooperativa' using errcode='P0409';
84:     end if;
85:     -- Revalida el contenido guardado, también al retomar una solicitud anterior.
86:     perform private.inversion_validar_datos(v_s.id,v_s.datos,v_ctx);
87:     select * into v_obj from storage.objects
88:     where bucket_id='f4-comprobantes' and name=v_s.datos#>>'{evidencia,ruta}' for key share;
89:     if not found or coalesce((v_obj.metadata->>'size')::bigint,0) not between 1 and 10485760
90:        or coalesce(v_obj.metadata->>'mimetype','') not in ('application/pdf','image/jpeg','image/png') then
91:       raise exception 'Sube el comprobante válido antes de confirmar la inversión' using errcode='P0409';
92:     end if;
93:     v_fecha := (v_s.datos->>'fecha_comercial')::date;
94:     v_periodo := date_trunc('month',v_fecha)::date;
95:     -- Mismo candado que el sello mensual. El sello no puede aparecer entre la
96:     -- decisión y el alta. Un mes sellado recibe un hecho posterior trazable.
97:     perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados'),
98:       (v_periodo-date '2000-01-01')::integer);
99:     v_ajuste := exists(select 1 from crm.periodos_cerrados where periodo=v_periodo);
100:     v_imputacion := case when v_ajuste then (v_ahora at time zone 'America/Lima')::date else v_fecha end;
101:     if v_ajuste then
102:       perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados'),
103:         (date_trunc('month',v_imputacion)::date-date '2000-01-01')::integer);
104:       if exists(select 1 from crm.periodos_cerrados where periodo=date_trunc('month',v_imputacion)::date) then
105:         raise exception 'El período de registro también está sellado; corresponde revisión de Gerencia' using errcode='P0409';
106:       end if;
107:     end if;
108:     begin
109:       insert into crm.cierres_externos(lead_id,cooperativa,monto,moneda,documento_tipo,documento,
110:         nombre_completo,numero_transaccion,referencia_externa,vence_en,vendedor_id,creado_por,
111:         inversionista_id,creado_en,es_cierre_inicial,fecha_comercial,fecha_imputacion,comprobante_objeto_id,
112:         plazo_meses,tasa_anual)
113:       values((v_ctx->>'lead_id')::uuid,v_e.clave,(v_s.datos->>'monto')::numeric,v_s.datos->>'moneda',
114:         v_ctx->>'documento_tipo',v_ctx->>'documento',v_ctx->>'nombre',
115:         upper(btrim(v_s.datos->>'numero_transaccion')),btrim(v_s.datos->>'referencia'),
116:         (v_s.datos->>'vence_en')::date,coalesce(v_s.analista_cierre_id,(v_ctx->>'responsable_id')::uuid),v_uid,v_persona,
117:         v_ahora,v_s.lead_origen_id is not null,v_fecha,v_imputacion,v_obj.id,
118:         (v_s.datos->>'plazo_meses')::integer,(v_s.datos->>'tasa_anual')::numeric) returning id into v_cierre;
119:       -- La reclamación histórica del depósito es global para ambas cooperativas.
120:       insert into crm.depositos_reclamados(numero_norm,cierre_id,reclamado_por)
121:       values(upper(btrim(v_s.datos->>'numero_transaccion')),v_cierre,v_uid);
122:     exception when unique_violation then
123:       raise exception 'Ese número de operación del depósito ya está registrado' using errcode='P0409';
124:     end;
125:     v_fuente:=jsonb_build_object('cierre_id',v_cierre,'fecha_comercial',v_fecha,
126:       'fecha_imputacion',v_imputacion,'ajuste_mes_cerrado',v_ajuste,
127:       'plazo_meses',(v_s.datos->>'plazo_meses')::integer,'tasa_anual',(v_s.datos->>'tasa_anual')::numeric,
128:       'vence_en',(v_s.datos->>'vence_en')::date);
129:   elsif v_e.clave='avance' then
130:     if v_ctx->>'perfil_id' is null then
131:       raise exception 'Completa el acceso Avance de esta persona y vuelve a confirmar la misma solicitud' using errcode='P0409';
132:     end if;
133:     v_payload_contrato := v_s.datos->'contrato';
134:     if v_s.puerta='cliente_existente' and coalesce(v_payload_contrato->>'categoria','nuevo') not in ('nuevo','upgrade') then
135:       raise exception 'La venta cruzada registra una inversión nueva o un upgrade; la renovación es del responsable' using errcode='22023';
136:     end if;
137:     if v_s.lead_origen_id is not null then
138:       if coalesce(v_payload_contrato->>'categoria','nuevo')<>'nuevo' then
139:         raise exception 'La conversión inicial registra una inversión nueva' using errcode='22023';
140:       end if;
141:       perform private.validar_tasa_conversion_lead(v_s.lead_origen_id,(v_ctx->>'perfil_id')::uuid,v_payload_contrato);
142:       perform private.enlazar_tasa_lead(v_s.lead_origen_id,(v_ctx->>'perfil_id')::uuid);
143:     end if;
144:     select r.responsable_anterior_id into v_responsable_inicial
145:       from crm.inversion_solicitud_revisiones r where r.solicitud_id=v_s.id order by r.revision limit 1;
146:     v_responsable_inicial:=coalesce(v_responsable_inicial,v_s.responsable_esperado_id);
147:     if v_payload_contrato->>'cliente_id' is not null
148:        and v_payload_contrato->>'cliente_id' is distinct from v_ctx->>'perfil_id' then
149:       raise exception 'El contrato no corresponde a esta persona' using errcode='P0409';
150:     end if;
151:     if v_payload_contrato->>'analista_cierre_id' is not null
152:        and v_payload_contrato->>'analista_cierre_id' is distinct from coalesce(v_s.analista_cierre_id,v_responsable_inicial)::text then
153:       raise exception 'El analista del contenido original no corresponde al responsable con que se preparó la inversión' using errcode='P0409';
154:     end if;
155:     -- El contenido original conserva su huella. Una revisión explícita cambia
156:     -- el responsable con quien se confirma, sin reescribir las condiciones.
157:     v_payload_contrato := v_payload_contrato||jsonb_build_object('cliente_id',v_ctx->>'perfil_id',
158:       'analista_cierre_id',coalesce(v_s.analista_cierre_id::text,v_ctx->>'responsable_id'));
159:     -- La fuente existente conserva producto, tasa, cronograma, cuenta, titularidad
160:     -- documental y operaciones de cartera. Todo participa de esta transacción.
161:     -- Reutiliza además la reserva y el snapshot documentales del alta publicada.
162:     -- Un PDF pendiente no vuelve a crear el contrato cuando se recupera el envío.
163:     -- El flujo Avance vigente es libre y fotografía sus términos. El catálogo
164:     -- sigue siendo opcional: F4 no lo convierte en un requisito comercial nuevo.
165:     perform pg_catalog.set_config('crm.producto_condicion_id',
166:       coalesce((nullif(v_s.datos->>'producto_condicion_id','')::uuid)::text,''),true);
167:     -- Venta cruzada: el alta Avance puede crear el PDF de ESTE contrato aunque el cliente
168:     -- no sea de la cartera de quien confirma (private.venta_cruzada_confirma_contrato).
169:     perform pg_catalog.set_config('crm.venta_cruzada_solicitud',case when v_s.puerta='cliente_existente' then v_s.id::text else '' end,true);
170:     begin
171:       v_fuente := crm.crear_contrato_con_cuenta_pdf_v2(
172:         v_payload_contrato||jsonb_build_object('clave_idempotencia',v_s.id),
173:         v_s.datos->'cronograma',v_s.datos->'cuenta');
174:     exception when others then
175:       perform pg_catalog.set_config('crm.producto_condicion_id',coalesce(v_config_producto,''),true);
176:       perform pg_catalog.set_config('crm.venta_cruzada_solicitud','',true);
177:       raise;
178:     end;
179:     perform pg_catalog.set_config('crm.producto_condicion_id',coalesce(v_config_producto,''),true);
180:     perform pg_catalog.set_config('crm.venta_cruzada_solicitud','',true);
181:     v_contrato := (v_fuente->>'id')::uuid;
182:     if v_contrato is null then raise exception 'El contrato no devolvió su identificador' using errcode='P0001'; end if;
183:     select producto_condicion_id into v_condicion from public.contratos where id=v_contrato;
184:     v_fuente:=v_fuente||private.metadata_condicion_producto(v_condicion);
185:   else
186:     raise exception 'Empresa sin puerta de inversión disponible' using errcode='P0409';
187:   end if;
188:   v_inversion := private.inversion_vincular_fuente(v_persona,v_contrato,v_cierre,v_uid,v_s.lead_origen_id is not null);
189:   if v_ajuste then
190:     insert into crm.inversion_ajustes_mes_cerrado(inversion_id,periodo_origen,fecha_imputacion,creado_por)
191:     values(v_inversion,v_periodo,v_imputacion,v_uid);
192:   end if;
193:   insert into crm.inversion_eventos(inversion_id,tipo,creado_por) values(v_inversion,'registro',v_uid);
194:   v_res := jsonb_build_object('ok',true,'solicitud_id',v_s.id,'inversion_id',v_inversion,
195:     'inversionista_id',v_persona,'lead_id',v_ctx->>'lead_id','empresa',v_e.clave,'fuente',v_fuente,
196:     'revision_datos',v_s.revision_datos);
197:   if v_s.puerta='cliente_existente' then
198:     v_res := v_res||jsonb_build_object('puerta',v_s.puerta,'analista_cierre_id',v_s.analista_cierre_id);
199:   end if;
200:   update crm.inversion_solicitudes set estado='confirmada',inversion_id=v_inversion,
201:     resultado=v_res,confirmado_por=v_uid,actualizado_en=statement_timestamp() where id=v_s.id;
202:   if v_s.lead_origen_id is not null then
203:     -- El escritor contractual puede haber enlazado ya su fuente; se reconoce
204:     -- ESTA inversión como inicial, conservando un único hecho y titular.
205:     update crm.inversiones set es_primera_conversion=true where id=v_inversion;
206:     perform set_config('crm.op_privilegiada','on',true);
207:     update crm.leads set etapa='convertido',convertido_en=statement_timestamp(),
208:       perfil_id=case when v_e.clave='avance' then (v_ctx->>'perfil_id')::uuid else perfil_id end,
209:       contrato_id=coalesce(v_contrato,contrato_id)
210:       where id=v_s.lead_origen_id;
211:     perform set_config('crm.op_privilegiada',v_config_conversion,true);
212:     insert into crm.actividades(lead_id,tipo,detalle,metadata,creado_por)
213:       values(v_s.lead_origen_id,'conversion','Convertido al confirmar su inversión',
214:         jsonb_build_object('solicitud_id',v_s.id,'inversion_id',v_inversion,'empresa',v_e.clave,
215:           'contrato_id',v_contrato,'cierre_externo_id',v_cierre),v_uid);
216:     if v_e.clave='avance' and v_s.auth_claim_id is not null then
217:       update crm.inversion_solicitudes set bienvenida=jsonb_build_object(
218:         'estado','pendiente','correo',v_s.datos->'alta_portal'->>'correo',
219:         'nombre',v_s.datos->'alta_portal'->>'nombre_completo') where id=v_s.id;
220:     end if;
221:   end if;
222:   return v_res;
223: end;
224: 
225: exception when serialization_failure or lock_not_available then
226:   if not exists(select 1 from crm.inversion_solicitud_origenes where solicitud_id=p_solicitud) then raise; end if;
227:   raise exception using errcode='PT409', message='La operación coincidió con otro cambio. Vuelve a intentarlo.';
228: end;
229: $function$
230: 

### INSTALLED CONTRACT crm.preparar_persona_lead_inversion_fn(uuid,text,text,text) md5=df451bd3cc831e2b47a26eb867c9e65e
1: CREATE OR REPLACE FUNCTION crm.preparar_persona_lead_inversion_fn(p_lead uuid, p_tipo_documento text, p_documento text, p_nombre text)
2:  RETURNS jsonb
3:  LANGUAGE plpgsql
4:  SECURITY DEFINER
5:  SET search_path TO ''
6:  SET lock_timeout TO '5s'
7: AS $function$
8: declare
9:   v_uid uuid:=(select auth.uid()); v_rol text;
10:   v_l crm.leads%rowtype; v_pre crm.leads%rowtype; v_i crm.inversionistas%rowtype;
11:   v_persona uuid; v_doc text:=upper(btrim(p_documento));
12:   v_config text:=coalesce(current_setting('crm.op_privilegiada',true),'off');
13: begin
14:   if v_uid is null or not private.puede_gestionar_contratos_crm() then
15:     raise exception 'No autorizado para convertir leads' using errcode='42501';
16:   end if;
17:   if not private.resolver_en_puertas_bajo_candado() or not private.inversiones_escritura_bajo_candado() then
18:     raise exception 'El registro compartido de inversiones no está habilitado' using errcode='P0409';
19:   end if;
20:   perform pg_advisory_xact_lock_shared(hashtextextended('crm.equipo.usuarios_jerarquia',0));
21:   v_rol:=private.rol_crm(v_uid);
22:   select * into v_pre from crm.leads where id=p_lead and activo and
23:     (v_rol='gerencia' or vendedor_id in (select private.vendedor_ids_visibles(v_uid)));
24:   if not found then raise exception 'Lead no encontrado o fuera de tu ámbito' using errcode='42501'; end if;
25:   if length(btrim(coalesce(p_nombre,''))) not between 2 and 180
26:     or p_tipo_documento is null or p_tipo_documento not in ('DNI','CE','PASAPORTE')
27:     or v_doc is null
28:     or (p_tipo_documento='DNI' and v_doc !~ '^[0-9]{8}$')
29:     or (p_tipo_documento='CE' and v_doc !~ '^[0-9]{9,12}$')
30:     or (p_tipo_documento='PASAPORTE' and v_doc !~ '^[A-Z0-9]{6,12}$') then
31:     raise exception 'Completa el nombre y un documento válido' using errcode='22023';
32:   end if;
33:   -- La identidad no se corrige al invertir. Esa operación tiene su propia puerta.
34:   if nullif(btrim(v_pre.dni),'') is not null and v_pre.dni is distinct from v_doc then
35:     raise exception 'El documento no coincide con el lead; corrige su identidad antes de invertir' using errcode='P0409';
36:   end if;
37:   perform private.identidad_bloquear_documento(p_tipo_documento,v_doc);
38:   v_persona:=private.inversionista_resolver(p_tipo_documento,v_doc,true,'conversion_inversion');
39:   perform private.identidad_bloquear_documentos_de(array[v_persona]);
40:   select * into v_i from crm.inversionistas where id=v_persona for update;
41:   -- NOWAIT: una reasignación que tomó antes el lead no invierte el orden de locks.
42:   select * into v_l from crm.leads where id=p_lead for update nowait;
43:   if v_l.activo is not true or not coalesce((v_rol='gerencia' or
44:     v_l.vendedor_id in (select private.vendedor_ids_visibles(v_uid))),false) then
45:     raise exception 'Lead no encontrado o fuera de tu ámbito' using errcode='42501';
46:   end if;
47:   if v_l.dni is distinct from v_pre.dni or v_l.inversionista_id is distinct from v_pre.inversionista_id then
48:     raise exception 'La identidad del lead cambió; vuelve a cargarlo' using errcode='PT409';
49:   end if;
50:   -- También recupera una confirmación cuyo HTTP se perdió: no se vuelve a
51:   -- preparar ni se modifica la persona o el lead ya convertido.
52:   if v_l.etapa='convertido' and v_l.inversionista_id=v_persona and exists(
53:     select 1 from crm.inversion_solicitudes where lead_origen_id=p_lead and estado='confirmada') then
54:     perform private.inversion_persona_autorizada(v_persona);
55:     return jsonb_build_object('inversionista_id',v_persona,'lead_id',p_lead,
56:       'solicitud_id',(select id from crm.inversion_solicitudes where lead_origen_id=p_lead and estado='confirmada'));
57:   end if;
58:   if v_l.etapa in ('convertido','descartado') then
59:     raise exception 'El lead ya está cerrado; consulta su inversión en Cartera' using errcode='P0409';
60:   end if;
61:   -- Retomar es lectura: conserva borradores desde otra sesión/dispositivo.
62:   -- El contexto vigente sigue verificando actor, identidad y ámbito. Crear
63:   -- acceso o confirmar vuelven a comprobar los hechos en sus propias puertas.
64:   if v_l.inversionista_id=v_persona and exists(select 1 from crm.inversion_solicitudes
65:     where lead_origen_id=p_lead and inversionista_id=v_persona and estado='preparada') then
66:     perform private.inversion_persona_contexto(v_persona,p_lead);
67:     return jsonb_build_object('inversionista_id',v_persona,'lead_id',p_lead,
68:       'solicitud_id',(select id from crm.inversion_solicitudes where lead_origen_id=p_lead
69:         and inversionista_id=v_persona and estado='preparada'));
70:   end if;
71:   perform private.recorrido_exigir(p_lead,'preparar_identidad');
72:   if v_i.estado<>'activo' or v_i.no_contactar then
73:     raise exception 'La persona no permite nuevas inversiones' using errcode='P0429';
74:   end if;
75:   if v_l.no_contactar then raise exception 'El lead tiene No insistir' using errcode='P0429'; end if;
76:   if v_l.vendedor_id is null or not exists(select 1 from crm.equipo e join public.perfiles p on p.id=e.perfil_id
77:     where e.perfil_id=v_l.vendedor_id and e.activo and p.activo and e.rol_crm in ('vendedor','supervisor')) then
78:     raise exception 'Asigna el lead a un analista activo antes de invertir' using errcode='P0409';
79:   end if;
80:   if (v_l.inversionista_id is not null and v_l.inversionista_id is distinct from v_persona)
81:     or exists(select 1 from crm.inversionista_leads il where il.lead_id=p_lead
82:       and private.inversionista_canonica(il.inversionista_id) is distinct from v_persona)
83:     or exists(select 1 from private.leads_de_personas(array[v_persona]) x where x<>p_lead)
84:     or exists(select 1 from private.leads_de_identidades(array[v_persona]) x where x<>p_lead) then
85:     raise exception 'Esta persona ya tiene otra identidad o lead; requiere conciliación' using errcode='P0409';
86:   end if;
87:   if v_i.responsable_relacion_id is not null and v_i.responsable_relacion_id<>v_l.vendedor_id then
88:     raise exception 'El responsable de la persona y el analista del lead deben coincidir antes de invertir' using errcode='P0409';
89:   end if;
90:   if exists(select 1 from crm.conversion_reservas r where
91:     (r.lead_id=p_lead or r.inversionista_id=v_persona) and
92:     (r.efectos_iniciados_en is not null or r.expira_en>now()) for update) then
93:     raise exception 'Hay una conversión anterior pendiente; revisa su acceso antes de iniciar otra solicitud' using errcode='P0409';
94:   end if;
95:   if v_i.responsable_relacion_id is null then
96:     if exists(select 1 from crm.inversionista_responsables where inversionista_id=v_persona and hasta is null) then
97:       raise exception 'La asignación de la persona requiere conciliación' using errcode='P0409';
98:     end if;
99:     insert into crm.inversionista_responsables(inversionista_id,responsable_id,motivo,por)
100:       values(v_persona,v_l.vendedor_id,'preparar_conversion_inversion',v_uid);
101:     update crm.inversionistas set responsable_relacion_id=v_l.vendedor_id where id=v_persona;
102:   end if;
103:   perform set_config('crm.op_privilegiada','on',true);
104:   update crm.leads set inversionista_id=v_persona,nombre_completo=btrim(p_nombre),
105:     dni=case when p_tipo_documento='DNI' then v_doc else dni end where id=p_lead;
106:   perform set_config('crm.op_privilegiada',v_config,true);
107:   -- Además aplica las banderas/membresía de F4 y el ámbito canónico de Cartera.
108:   perform private.inversion_persona_contexto(v_persona,p_lead);
109:   return jsonb_build_object('inversionista_id',v_persona,'lead_id',p_lead,
110:     'solicitud_id',(select id from crm.inversion_solicitudes where lead_origen_id=p_lead
111:       and estado in ('preparada','confirmada')));
112: end $function$
113: 

### INSTALLED CONTRACT crm.recorrido_atender_oficina_fn(uuid,uuid,text,text,jsonb,numeric,text,text) md5=3a5b9b0a233295b4d4fcbdf813a9a465
1: CREATE OR REPLACE FUNCTION crm.recorrido_atender_oficina_fn(p_operacion_id uuid, p_lead_id uuid, p_resultado_reunion text, p_detalle text DEFAULT NULL::text, p_siguiente jsonb DEFAULT NULL::jsonb, p_capital_estimado numeric DEFAULT NULL::numeric, p_moneda text DEFAULT NULL::text, p_ubicacion text DEFAULT 'Oficina'::text)
2:  RETURNS jsonb
3:  LANGUAGE plpgsql
4:  SECURITY DEFINER
5:  SET search_path TO ''
6: AS $function$
7: declare
8:   v_actor uuid:=(select auth.uid());
9:   v_clave text; v_hash text; v_payload jsonb; v_respuesta jsonb;
10:   v_lead crm.leads%rowtype; v_tarea uuid; v_cierre uuid;
11:   v_anterior text:=coalesce(current_setting('crm.recorrido_oficina',true),'');
12: begin
13:   if v_actor is null or private.rol_crm(v_actor) is null
14:     or private.rol_crm(v_actor) not in ('vendedor','supervisor','gerencia') then
15:     raise exception 'No autorizado' using errcode='42501';
16:   end if;
17:   if p_operacion_id is null or p_lead_id is null
18:     or p_resultado_reunion is null or p_resultado_reunion not in
19:       ('interesado','seguimiento','propuesta','inicia_registro','no_interesado')
20:     or nullif(btrim(p_ubicacion),'') is null or length(btrim(p_ubicacion))>500
21:     or length(coalesce(p_detalle,''))>4000
22:     or (p_siguiente is not null and jsonb_typeof(p_siguiente)<>'object') then
23:     raise exception 'Registra la entrevista, su resultado y la oficina de atencion' using errcode='22023';
24:   end if;
25:   if current_setting('transaction_isolation')<>'read committed' then
26:     raise exception 'La atencion necesita aislamiento READ COMMITTED' using errcode='55000';
27:   end if;
28:   if private.sla_gestion_permitida(v_actor,p_lead_id) is distinct from true then
29:     raise exception 'Gestion no disponible en tu ambito' using errcode='42501';
30:   end if;
31:   v_clave:='recorrido_oficina:'||v_actor::text||':'||p_operacion_id::text;
32:   -- Identificador estable por operación y actor; no acepta IDs de tareas ajenas.
33:   v_tarea:=md5(v_clave)::uuid;
34:   v_payload:=jsonb_build_object('version',1,'lead_id',p_lead_id,'tarea_id',v_tarea,
35:     'resultado_reunion',p_resultado_reunion,'detalle',nullif(btrim(p_detalle),''),
36:     'siguiente',p_siguiente,'capital_estimado',p_capital_estimado,'moneda',p_moneda,
37:     'ubicacion',btrim(p_ubicacion));
38:   v_hash:=private.idem_hash(v_payload);
39:   perform pg_advisory_xact_lock(hashtextextended(v_clave,0));
40:   select * into strict v_lead from crm.leads where id=p_lead_id for update;
41:   if private.sla_gestion_permitida(v_actor,p_lead_id) is distinct from true then
42:     raise exception 'El lead cambio de responsable; recarga la ficha' using errcode='42501';
43:   end if;
44:   v_respuesta:=private.idem_leer(v_clave,v_hash);
45:   if v_respuesta is not null then return v_respuesta;end if;
46:   if v_lead.etapa in ('convertido','descartado') then
47:     raise exception 'El lead esta cerrado: no admite una visita nueva' using errcode='22023';
48:   end if;
49:   if v_lead.vendedor_id is null then
50:     raise exception 'Asigna un analista antes de registrar la visita' using errcode='22023';
51:   end if;
52:   if v_lead.no_contactar or private.persona_vetada(p_lead_id) then
53:     raise exception 'La persona tiene la restriccion No insistir' using errcode='P0429';
54:   end if;
55: 
56:   -- El recibo pendiente no se confirma separado del cierre. Todo revierte si
57:   -- falla el capital, la siguiente acción, un permiso o cualquier trigger.
58:   perform private.idem_guardar(v_clave,'recorrido_oficina',v_hash,null,v_actor);
59:   insert into crm.tareas(id,lead_id,tipo,titulo,vence_en,modalidad_reunion,ubicacion_reunion,creado_por)
60:     values(v_tarea,p_lead_id,'reunion','Atencion en oficina',clock_timestamp(),'presencial',btrim(p_ubicacion),v_actor);
61:   perform set_config('crm.recorrido_oficina',jsonb_build_object(
62:     'clave',v_clave,'operacion_id',p_operacion_id,'payload',v_payload)::text,true);
63:   -- El ID interno es del servidor: no puede colisionar con un comando SLA
64:   -- elegido por el llamador que espere el lead en el orden inverso.
65:   v_cierre:=gen_random_uuid();
66:   v_respuesta:=crm.cerrar_reunion_v3(v_cierre,v_tarea,'completada',p_resultado_reunion,
67:     null,nullif(btrim(p_detalle),''),p_siguiente,p_capital_estimado,p_moneda);
68:   perform set_config('crm.recorrido_oficina',v_anterior,true);
69:   if coalesce((v_respuesta->>'ok')::boolean,false) is not true then
70:     raise exception 'El servidor no confirmo la entrevista' using errcode='23514';
71:   end if;
72:   v_respuesta:=v_respuesta||jsonb_build_object('version',1,'operacion_id',p_operacion_id,
73:     'comando','recorrido_atender_oficina','origen','oficina','ciclo_n',v_lead.ciclo_actual);
74:   perform private.idem_guardar(v_clave,'recorrido_oficina',v_hash,v_respuesta,v_actor);
75:   return v_respuesta;
76: end $function$
77: 

### INSTALLED CONTRACT crm.recorrido_configurar_fn(text,text,integer,timestamp with time zone) md5=6597bef760830dc37673df68e174cbec
1: CREATE OR REPLACE FUNCTION crm.recorrido_configurar_fn(p_modo text, p_motivo text, p_revision integer, p_cohorte_desde timestamp with time zone DEFAULT NULL::timestamp with time zone)
2:  RETURNS jsonb
3:  LANGUAGE plpgsql
4:  SECURITY DEFINER
5:  SET search_path TO ''
6: AS $function$
7: declare v_control crm.recorrido_control%rowtype;
8:   v_writer text:=coalesce(current_setting('crm.recorrido_control_writer',true),'off');
9: begin
10:   if not private.es_gerencia_crm_activa() then raise exception 'No autorizado' using errcode='42501'; end if;
11:   if p_modo is null or p_modo not in ('apagado','observacion','exigir')
12:     or p_motivo is null or length(btrim(p_motivo)) not between 8 and 1000
13:     or p_revision is null or (p_cohorte_desde is not null and not isfinite(p_cohorte_desde)) then
14:     raise exception 'Indica modo, motivo y revision validos' using errcode='22023';
15:   end if;
16:   select * into strict v_control from crm.recorrido_control where id for update;
17:   if v_control.revision<>p_revision then raise exception 'El modo cambio; consulta de nuevo' using errcode='PT409'; end if;
18:   if v_control.cohorte_desde is not null and p_cohorte_desde is not null and p_cohorte_desde<>v_control.cohorte_desde then
19:     raise exception 'El corte de activacion no se reinicia' using errcode='22023';
20:   end if;
21:   if v_control.cohorte_desde is null and p_cohorte_desde is not null and p_cohorte_desde<clock_timestamp() then
22:     raise exception 'La fecha inicial de exigencia no puede estar en el pasado' using errcode='22023';
23:   end if;
24:   if v_control.cohorte_desde is null and p_cohorte_desde>clock_timestamp()+interval '24 hours' then
25:     raise exception 'Programa la activacion dentro de las proximas 24 horas' using errcode='22023';
26:   end if;
27:   perform set_config('crm.recorrido_control_writer','on',true);
28:   update crm.recorrido_control set modo=p_modo, motivo=btrim(p_motivo), revision=revision+1,
29:     cohorte_desde=coalesce(cohorte_desde,p_cohorte_desde,case when p_modo='exigir' then clock_timestamp() end),
30:     actualizado_por=(select auth.uid()),actualizado_en=clock_timestamp()
31:     where id returning * into v_control;
32:   perform set_config('crm.recorrido_control_writer',v_writer,true);
33:   return to_jsonb(v_control)-'id';
34: end $function$
35: 

### INSTALLED CONTRACT crm.recorrido_leads_fn(uuid[]) md5=8490c4183e4f7a52753b53bed70b344a
1: CREATE OR REPLACE FUNCTION crm.recorrido_leads_fn(p_lead_ids uuid[])
2:  RETURNS jsonb
3:  LANGUAGE plpgsql
4:  SECURITY DEFINER
5:  SET search_path TO ''
6: AS $function$
7: declare v_amb record;v_ids uuid[];v_filas jsonb;v_control crm.recorrido_control%rowtype;
8: begin
9:   select * into strict v_amb from private.sla_operacion_ambito(p_lead_ids,false);
10:   if p_lead_ids is null or cardinality(p_lead_ids)>100 then
11:     raise exception 'Consulta entre cero y cien leads por lote' using errcode='22023';end if;
12:   select array_agg(l.id) into v_ids from crm.leads l where l.id=any(p_lead_ids) and l.activo
13:     and (v_amb.es_global or l.vendedor_id=any(v_amb.visibles)
14:       or (l.vendedor_id is null and l.asignado_supervisor_id=any(v_amb.visibles)));
15:   select * into strict v_control from crm.recorrido_control where id;
16:   select coalesce(jsonb_agg(e.resultado||jsonb_build_object('exigible',coalesce(v_control.modo='exigir'
17:       and clock_timestamp()>=v_control.cohorte_desde
18:       and (e.resultado->>'aplica')::boolean,false)) order by e.lead_id),'[]'::jsonb)
19:     into v_filas from private.recorrido_evaluar(coalesce(v_ids,'{}'::uuid[])) e join crm.leads l on l.id=e.lead_id;
20:   return jsonb_build_object('version',1,'modo',v_control.modo,'revision',v_control.revision,
21:     'cohorte_desde',v_control.cohorte_desde,'filas',v_filas);
22: end $function$
23: 

### INSTALLED CONTRACT private.conversion_lead_con_inversion() md5=e8c5fff978355f9c78a56cab67a1c65e
1: CREATE OR REPLACE FUNCTION private.conversion_lead_con_inversion()
2:  RETURNS trigger
3:  LANGUAGE plpgsql
4:  SECURITY DEFINER
5:  SET search_path TO ''
6: AS $function$
7: begin
8:   if new.etapa='convertido' and old.etapa<>'convertido' then
9:     if exists(select 1 from crm.inversion_solicitudes where lead_origen_id=new.id and estado='preparada') then
10:       raise exception 'Confirma la solicitud de inversión antes de convertir el lead' using errcode='P0409';
11:     end if;
12:     if not exists(select 1 from crm.inversion_solicitudes s join crm.inversiones i on i.id=s.inversion_id
13:       where s.lead_origen_id=new.id and s.estado='confirmada'
14:         and i.inversionista_id=new.inversionista_id and i.es_primera_conversion and i.estado='vigente') then
15:       raise exception 'Registra y confirma la inversión desde el formulario compartido antes de convertir' using errcode='P0409';
16:     end if;
17:     -- Última defensa también para writers internos; conserva la comprobación
18:     -- anterior de solicitud confirmada e inversión inicial vigente.
19:     perform private.recorrido_exigir(new.id,'convertir_lead');
20:   end if;
21:   return new;
22: end $function$
23: 

### INSTALLED CONTRACT private.recorrido_capturar_actividad() md5=f4cd2764fe29966230687b1b2e250982
1: CREATE OR REPLACE FUNCTION private.recorrido_capturar_actividad()
2:  RETURNS trigger
3:  LANGUAGE plpgsql
4:  SECURITY DEFINER
5:  SET search_path TO ''
6: AS $function$
7: declare
8:   v_estado text:='ciclo'; v_ciclo integer; v_hora timestamptz; v_lead crm.leads%rowtype;
9:   v_writer text:=coalesce(current_setting('crm.recorrido_contexto_writer',true),'off');
10:   v_oficina jsonb; v_gesto uuid; v_tarea uuid;
11: begin
12:   select * into strict v_lead from crm.leads where id=new.lead_id for update;
13:   v_ciclo:=v_lead.ciclo_actual;
14:   v_hora:=clock_timestamp();
15:   if not exists(select 1 from crm.lead_sla_ciclos c where c.lead_id=new.lead_id and c.ciclo_n=v_ciclo) then
16:     if v_lead.origen='base_cargada' and v_lead.etapa='descartado'
17:       and v_lead.motivo_descarte='base_cargada' and v_lead.activo
18:       and not exists(select 1 from crm.lead_sla_ciclos c where c.lead_id=new.lead_id) then
19:       v_estado:='base_sin_ciclo';
20:     else
21:       v_estado:='sin_ciclo';
22:     end if;
23:     v_ciclo:=null;
24:   end if;
25:   v_oficina:=nullif(current_setting('crm.recorrido_oficina',true),'')::jsonb;
26:   if new.tipo='reunion_realizada' and v_oficina#>>'{payload,lead_id}'=new.lead_id::text
27:     and v_oficina#>>'{payload,tarea_id}'=new.metadata->>'tarea_id'
28:     and v_oficina->>'clave'='recorrido_oficina:'||(select auth.uid())::text||':'||(v_oficina->>'operacion_id')
29:     and exists(select 1 from crm.multiempresa_idempotencia m
30:       where m.clave=v_oficina->>'clave' and m.tipo='recorrido_oficina'
31:         and m.creado_por=(select auth.uid()) and m.resultado is null
32:         and m.hash_payload=private.idem_hash(v_oficina->'payload')) then
33:     v_gesto:=(v_oficina->>'operacion_id')::uuid;
34:     v_tarea:=(v_oficina#>>'{payload,tarea_id}')::uuid;
35:   end if;
36:   perform set_config('crm.recorrido_contexto_writer','on',true);
37:   insert into crm.actividad_ciclo_contexto(actividad_id,lead_id,ciclo_n,estado_ciclo,registrado_en,gesto_oficina_id,oficina_tarea_id)
38:     values(new.id,new.lead_id,v_ciclo,v_estado,v_hora,v_gesto,v_tarea);
39:   perform set_config('crm.recorrido_contexto_writer',v_writer,true);
40:   return null;
41: end $function$
42: 

### INSTALLED CONTRACT private.recorrido_contexto_guard() md5=503d0ff5b52825e0a28f03ccde47b552
1: CREATE OR REPLACE FUNCTION private.recorrido_contexto_guard()
2:  RETURNS trigger
3:  LANGUAGE plpgsql
4:  SET search_path TO ''
5: AS $function$
6: begin
7:   if tg_op='DELETE' then
8:     -- Misma autorización de copia exacta, actor y transacción de la puerta oficial.
9:     if private.borrado_lead_error_autoriza(tg_table_name,to_jsonb(old)) then
10:       return old;
11:     end if;
12:   end if;
13:   if tg_op<>'INSERT' or pg_trigger_depth()<2
14:     or current_setting('crm.recorrido_contexto_writer',true) is distinct from 'on'
15:     or current_user::regrole::oid<>(select relowner from pg_class where oid=tg_relid) then
16:     raise exception 'El contexto del recorrido solo lo registra el servidor' using errcode='42501';
17:   end if;
18:   if not exists(select 1 from crm.actividades a where a.id=new.actividad_id and a.lead_id=new.lead_id) then
19:     raise exception 'Contexto ajeno a la actividad' using errcode='23514';
20:   end if;
21:   return new;
22: end $function$
23: 

### INSTALLED CONTRACT private.recorrido_control_guard() md5=14cf400ab3e7b6cb19d84e572570a05a
1: CREATE OR REPLACE FUNCTION private.recorrido_control_guard()
2:  RETURNS trigger
3:  LANGUAGE plpgsql
4:  SET search_path TO ''
5: AS $function$
6: begin
7:   if tg_op<>'UPDATE'
8:     or current_user::regrole::oid<>(select relowner from pg_class where oid=tg_relid)
9:     or current_setting('crm.recorrido_control_writer',true) is distinct from 'on' then
10:     raise exception 'El modo cambia solo por la puerta del recorrido' using errcode='42501';
11:   end if;
12:   if new.id is distinct from old.id or new.revision<>old.revision+1
13:     or (old.cohorte_desde is not null and new.cohorte_desde is distinct from old.cohorte_desde)
14:     or (old.cohorte_desde is null and (new.cohorte_desde<statement_timestamp()
15:       or new.cohorte_desde>clock_timestamp()+interval '24 hours')) then
16:     raise exception 'Corte inmutable o revision invalida' using errcode='23514';
17:   end if;
18:   return new;
19: end $function$
20: 

### INSTALLED CONTRACT private.recorrido_evaluar(uuid[]) md5=5ee9a8d476e315aa8f9b94c4e9c93cad
1: CREATE OR REPLACE FUNCTION private.recorrido_evaluar(p_lead_ids uuid[])
2:  RETURNS TABLE(lead_id uuid, resultado jsonb)
3:  LANGUAGE sql
4:  SET search_path TO ''
5: AS $function$
6: with leads as materialized (
7:   select l.id,l.ciclo_actual,l.etapa,l.vendedor_id,l.activo,c.iniciado_en,
8:     (select count(*)=1 and min(h.ciclo_n)=1 from crm.lead_sla_ciclos h where h.lead_id=l.id) unico_ciclo
9:   from crm.leads l left join crm.lead_sla_ciclos c on c.lead_id=l.id and c.ciclo_n=l.ciclo_actual
10:   where l.id=any(p_lead_ids)
11: ), actividades as materialized (
12:   select a.id,a.lead_id,a.tipo,a.metadata,a.creado_en,x.registrado_en,x.gesto_oficina_id,x.oficina_tarea_id,
13:     case when x.actividad_id is not null then x.ciclo_n=l.ciclo_actual
14:       when l.unico_ciclo and l.ciclo_actual=1 then true
15:       when exists(select 1 from crm.tarea_sla_contexto tc where tc.tarea_id::text=a.metadata->>'tarea_id'
16:           and tc.lead_id=a.lead_id and tc.ciclo_n=l.ciclo_actual) then true
17:       when exists(select 1 from crm.lead_sla_etapa_ajustes aj join crm.lead_sla_etapas e on e.id=aj.etapa_sla_id
18:           where aj.origen_actividad_id=a.id and e.lead_id=a.lead_id and e.ciclo_n=l.ciclo_actual) then true
19:       else false end del_ciclo
20:   from leads l join crm.actividades a on a.lead_id=l.id
21:     left join crm.actividad_ciclo_contexto x on x.actividad_id=a.id
22:   where a.tipo in ('llamada_realizada','llamada_no_contestada','whatsapp_enviado','whatsapp_recibido','reunion_realizada')
23:     and not (a.metadata ? 'deshecho_en')
24: ), citas as materialized (
25:   select t.id,t.lead_id,t.estado,t.vence_en,t.resultado_reunion,t.resultado_actividad_id,
26:     tc.ciclo_n=l.ciclo_actual del_ciclo,
27:     a.id asistencia_id,
28:     -- La evidencia nueva tiene hora de recepción real; no confía en backdates.
29:     -- Historia sin sello se conserva como ambigua para la política de antiguos.
30:     a.id is not null and a.registrado_en is not null and t.vence_en<=a.registrado_en asistencia_valida,
31:     a.id is not null and a.registrado_en is not null and t.vence_en<=a.registrado_en
32:       and t.resultado_reunion in ('interesado','seguimiento','propuesta','inicia_registro','no_interesado') entrevista_valida
33:   from leads l join crm.tareas t on t.lead_id=l.id
34:     left join crm.tarea_sla_contexto tc on tc.tarea_id=t.id and tc.lead_id=l.id
35:     left join actividades a on a.id=t.resultado_actividad_id and a.lead_id=l.id and a.del_ciclo
36:       and a.tipo='reunion_realizada' and a.metadata->>'tarea_id'=t.id::text and t.estado='completada'
37:   where t.tipo='reunion' and t.activo and t.estado in ('pendiente','completada')
38: ), hechos as (
39:   select l.*,
40:     (select a.id from actividades a where a.lead_id=l.id and a.del_ciclo order by a.registrado_en nulls last,a.id limit 1) gestion_id,
41:     (select a.id from actividades a where a.lead_id=l.id and a.del_ciclo
42:       and (a.tipo in ('llamada_realizada','whatsapp_recibido') or a.gesto_oficina_id is not null)
43:       order by a.registrado_en nulls last,a.id limit 1) contacto_id,
44:     (select t.id from citas t where t.lead_id=l.id and t.del_ciclo
45:       order by t.entrevista_valida desc nulls last,t.vence_en,t.id limit 1) cita_id,
46:     (select t.id from citas t where t.lead_id=l.id and t.del_ciclo and t.entrevista_valida
47:       order by t.vence_en,t.id limit 1) entrevista_tarea_id,
48:     (select t.id from citas t where t.lead_id=l.id and t.del_ciclo and t.asistencia_valida
49:       order by t.entrevista_valida desc,t.vence_en,t.id limit 1) asistencia_tarea_id,
50:     (select t.id from citas t where t.lead_id=l.id and t.del_ciclo and t.estado='pendiente'
51:       order by t.vence_en,t.id limit 1) pendiente_tarea_id,
52:     exists(select 1 from citas t where t.lead_id=l.id and
53:       (t.del_ciclo is null or (t.del_ciclo and t.estado='completada' and t.asistencia_id is not null
54:          and exists(select 1 from actividades a where a.id=t.asistencia_id and a.registrado_en is null)))) historico_ambiguo
55:   from leads l
56: )
57: select h.id,jsonb_build_object(
58:   'lead_id',h.id,'ciclo_n',h.ciclo_actual,'ciclo_inicio',h.iniciado_en,
59:   'aplica',h.activo and h.etapa not in ('convertido','descartado'),
60:   'estado',case when h.entrevista_tarea_id is not null then 'completo'
61:     when h.iniciado_en is null or h.historico_ambiguo then 'ambiguo' else 'incompleto' end,
62:   'habilita_conversion',h.entrevista_tarea_id is not null,
63:   'pasos',jsonb_build_object('gestionado',h.gestion_id is not null,'contactado',h.contacto_id is not null,
64:     'cita_agendada',h.cita_id is not null,'asistencia',h.asistencia_tarea_id is not null,'entrevista',h.entrevista_tarea_id is not null),
65:   'evidencias',jsonb_build_object('gestion_id',h.gestion_id,'contacto_id',h.contacto_id,'cita_id',h.cita_id,
66:     'entrevista_tarea_id',h.entrevista_tarea_id,
67:     'asistencia_tarea_id',h.asistencia_tarea_id,
68:     'asistencia_id',(select t.asistencia_id from citas t where t.id=h.asistencia_tarea_id)),
69:   'pendiente',case when h.entrevista_tarea_id is not null then 'listo'
70:     when h.vendedor_id is null then 'asignar_analista'
71:     when h.pendiente_tarea_id is not null then case when
72:       (select t.vence_en>clock_timestamp() from citas t where t.id=h.pendiente_tarea_id) then 'esperar_cita' else 'cerrar_entrevista' end
73:     when h.historico_ambiguo or h.iniciado_en is null then 'revisar_historial'
74:     when h.asistencia_tarea_id is not null then 'revisar_entrevista' else 'agendar_cita' end,
75:   'tarea_pendiente_id',h.pendiente_tarea_id,
76:   'cita_pendiente_en',(select t.vence_en from citas t where t.id=h.pendiente_tarea_id)
77: )
78: from hechos h;
79: $function$
80: 

### INSTALLED CONTRACT private.recorrido_exigir(uuid,text) md5=aa974c790c6e8418968111a496861fc0
1: CREATE OR REPLACE FUNCTION private.recorrido_exigir(p_lead uuid, p_paso text)
2:  RETURNS jsonb
3:  LANGUAGE plpgsql
4:  SECURITY DEFINER
5:  SET search_path TO ''
6: AS $function$
7: declare v_l crm.leads%rowtype;v_c crm.recorrido_control%rowtype;v_r jsonb;v_exigible boolean;
8:   v_tarea uuid;v_asistencia uuid;v_identidad_desde timestamptz;
9: begin
10:   -- Las operaciones de clientes existentes conservan el contexto canónico actual.
11:   if p_lead is null then return null;end if;
12:   -- Los callers conservan autorización/identidad. El lock protege hechos y
13:   -- ciclo sin bloquear FK que solo hacen referencia al lead. NOWAIT evita
14:   -- invertir esperas con rutas que llegaron por otra fila.
15:   select * into strict v_l from crm.leads where id=p_lead for no key update nowait;
16:   select * into strict v_c from crm.recorrido_control where id for share;
17:   if v_c.modo='exigir' and current_setting('transaction_isolation')<>'read committed' then
18:     raise exception 'Reintenta la operación en una transacción de lectura vigente' using errcode='55000';
19:   end if;
20:   select resultado into strict v_r from private.recorrido_evaluar(array[p_lead]);
21:   v_exigible:=coalesce(v_c.modo='exigir'
22:     and clock_timestamp()>=v_c.cohorte_desde
23:     and (v_r->>'aplica')::boolean,false);
24:   if v_exigible and not coalesce((v_r->>'habilita_conversion')::boolean,false) then
25:     raise exception using errcode='P0409',
26:       message='Antes de convertir, registra que asistió a su cita y que la entrevista se realizó, con su resultado. Revisa los pasos en la ficha del lead.',
27:       detail=jsonb_build_object('regla','recorrido_lead','paso',p_paso,'lead_id',p_lead,
28:         'ciclo_n',v_l.ciclo_actual,'pendiente',v_r->>'pendiente','revision',v_c.revision)::text;
29:   end if;
30:   -- Fotografía de LA pareja que acreditó la entrevista, no la última asistencia
31:   -- de otra cita del mismo lead. En observación puede quedar incompleta.
32:   v_tarea:=coalesce((v_r#>>'{evidencias,entrevista_tarea_id}')::uuid,
33:     (v_r#>>'{evidencias,asistencia_tarea_id}')::uuid);
34:   if v_tarea is not null then
35:     select resultado_actividad_id into v_asistencia from crm.tareas where id=v_tarea and lead_id=p_lead;
36:   end if;
37:   select min(creado_en) into v_identidad_desde from crm.inversionista_leads
38:     where lead_id=p_lead and inversionista_id=v_l.inversionista_id and rol='canonico';
39:   return jsonb_build_object('version',1,'lead_id',p_lead,'ciclo_n',v_l.ciclo_actual,
40:     'ciclo_inicio',v_r->'ciclo_inicio','modo',v_c.modo,'revision',v_c.revision,
41:     'cohorte_desde',v_c.cohorte_desde,'alcance','primeras_conversiones_pendientes',
42:     'exigible',v_exigible,'estado',v_r->>'estado',
43:     'verificado_en',clock_timestamp(),'identidad_vinculada_en',v_identidad_desde,
44:     'asistencia_tarea_id',v_tarea,'asistencia_id',v_asistencia,
45:     'entrevista_tarea_id',v_r#>'{evidencias,entrevista_tarea_id}');
46: end $function$
47: 

### INSTALLED CONTRACT private.recorrido_insert_convertido_guard() md5=fb93076ab61b64588264bba57a826f7b
1: CREATE OR REPLACE FUNCTION private.recorrido_insert_convertido_guard()
2:  RETURNS trigger
3:  LANGUAGE plpgsql
4:  SECURITY DEFINER
5:  SET search_path TO ''
6: AS $function$
7: declare v_c crm.recorrido_control%rowtype;
8: begin
9:   select * into strict v_c from crm.recorrido_control where id for share;
10:   -- Un INSERT terminal no puede tener asistencia y entrevista de su nuevo ciclo.
11:   -- La antigüedad declarada nunca excluye una primera conversión pendiente.
12:   if v_c.modo='exigir' and clock_timestamp()>=v_c.cohorte_desde then
13:     raise exception 'Registra primero el lead, su asistencia y entrevista; después confirma la inversión'
14:       using errcode='P0409';
15:   end if;
16:   return new;
17: end $function$
18: 

### INSTALLED CONTRACT private.recorrido_serializar_invalidacion() md5=70e15621fbcf5d8ac38bb524114616e7
1: CREATE OR REPLACE FUNCTION private.recorrido_serializar_invalidacion()
2:  RETURNS trigger
3:  LANGUAGE plpgsql
4:  SECURITY DEFINER
5:  SET search_path TO ''
6: AS $function$
7: declare v_lead uuid:=old.lead_id; v_cambia boolean:=true;
8: begin
9:   if tg_op='UPDATE' then
10:     if new.lead_id is distinct from old.lead_id then
11:       raise exception 'La evidencia no cambia de lead' using errcode='23514';
12:     end if;
13:     -- Incluye TODO campo consumido por el evaluador, también tipo/ID/vence_en.
14:     -- confirmada_en, título o notas no cambian asistencia ni entrevista.
15:     if tg_table_name='tareas' then
16:       v_cambia:=row(new.id,new.tipo,new.estado,new.activo,new.vence_en,new.resultado_actividad_id,new.resultado_reunion)
17:         is distinct from row(old.id,old.tipo,old.estado,old.activo,old.vence_en,old.resultado_actividad_id,old.resultado_reunion);
18:     elsif tg_table_name='actividades' then
19:       v_cambia:=row(new.id,new.tipo,new.metadata,new.creado_en)
20:         is distinct from row(old.id,old.tipo,old.metadata,old.creado_en);
21:     end if;
22:   end if;
23:   if v_lead is not null and v_cambia then
24:     -- DELETE y cambios de evidencia conservan NOWAIT para evitar espera inversa.
25:     perform 1 from crm.leads where id=v_lead for update nowait;
26:   end if;
27:   return case when tg_op='DELETE' then old else new end;
28: end $function$
29: 

### INSTALLED CONTRACT private.recorrido_solicitud_guard() md5=b8706eb77e491f3e9492899633401817
1: CREATE OR REPLACE FUNCTION private.recorrido_solicitud_guard()
2:  RETURNS trigger
3:  LANGUAGE plpgsql
4:  SECURITY DEFINER
5:  SET search_path TO ''
6: AS $function$
7: begin
8:   if tg_op='INSERT' then
9:     if new.recorrido_confirmado is not null then
10:       raise exception 'El recorrido confirmado lo registra el servidor' using errcode='42501';end if;
11:     if new.lead_origen_id is not null then
12:       if new.estado='confirmada' then
13:         new.recorrido_confirmado:=private.recorrido_exigir(new.lead_origen_id,'insertar_confirmada');end if;
14:       if new.estado='preparada' then perform private.recorrido_exigir(new.lead_origen_id,'preparar_solicitud');end if;
15:     end if;
16:   else
17:     if new.recorrido_confirmado is distinct from old.recorrido_confirmado then
18:       raise exception 'La evidencia de conversión confirmada es inmutable' using errcode='42501';end if;
19:     if old.estado<>'confirmada' and new.estado='confirmada' and new.lead_origen_id is not null then
20:       new.recorrido_confirmado:=private.recorrido_exigir(new.lead_origen_id,'confirmar_solicitud');
21:     end if;
22:   end if;
23:   return new;
24: end $function$
25: 

### CRM-Avance-Corp/supabase/scripts/recorrido-lead/test-todos-pendientes.sql
1: -- Banco local sintético. El alcance se prueba con leads/borradores anteriores
2: -- a la activación, cierres normales, roles reales y rollback de todas las filas.
3: begin;
4: set local statement_timeout='90s';
5: set local lock_timeout='3s';
6: create function pg_temp.exigir(p_ok boolean,p_texto text) returns void language plpgsql as $$
7: begin if p_ok is not true then raise exception 'TODOS PENDIENTES: %',p_texto;end if;end $$;
8: create function pg_temp.rechaza(p_sql text,p_codigo text,p_texto text) returns void language plpgsql as $$
9: begin
10:   begin execute p_sql;
11:   exception when others then
12:     if sqlstate=p_codigo and position(p_texto in sqlerrm)>0 then return;end if;
13:     raise exception 'Esperado % / %, obtenido % / %',p_codigo,p_texto,sqlstate,sqlerrm;
14:   end;
15:   raise exception 'La operacion debio rechazarse: %',p_sql;
16: end $$;
17: create temporary table casos_todos(nombre text primary key,id uuid default gen_random_uuid(),
18:   documento text,solicitud uuid default gen_random_uuid(),persona uuid,datos jsonb,tarea uuid,actividad uuid);
19: grant select,update on casos_todos to authenticated;
20: insert into casos_todos(nombre,documento) values
21:  ('borrador_antiguo','98648001'),('sin_persona_antiguo','98648002'),('valido_antes','98648003');
22: insert into crm.leads(id,nombre_completo,telefono,origen,monto_estimado,vendedor_id,creado_por)
23:  select id,'BANCO TODOS '||nombre,'98648'||lpad(row_number() over(order by nombre)::text,4,'0'),'oficina',1000,
24:  'b0000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000002' from casos_todos;
25: insert into storage.buckets(id,name,public) values('f4-comprobantes','f4-comprobantes',false) on conflict(id) do nothing;
26: select set_config('banco.vence_todos',private.coopac_validar_condiciones((clock_timestamp() at time zone 'America/Lima')::date,12,12)::text,true);
27: set local role authenticated;
28: select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
29: do $$
30: declare c record;r jsonb;f date:=(clock_timestamp() at time zone 'America/Lima')::date;
31: begin
32:   select * into c from casos_todos where nombre='borrador_antiguo';
33:   r:=crm.preparar_persona_lead_inversion_fn(c.id,'DNI',c.documento,'BANCO BORRADOR ANTERIOR');
34:   c.persona:=(r->>'inversionista_id')::uuid;
35:   c.datos:=jsonb_build_object('inversionista_id',c.persona,'lead_id',c.id,'empresa','qorilazo','monto',1000,'moneda','PEN',
36:     'fecha_comercial',f,'vence_en',current_setting('banco.vence_todos')::date,'plazo_meses',12,'tasa_anual',12,
37:     'numero_transaccion','TODOS-'||c.solicitud,'referencia','BORRADOR PREVIO',
38:     'evidencia',jsonb_build_object('ruta',c.persona||'/'||c.solicitud||'/comprobante.pdf'));
39:   perform crm.preparar_inversion_fn(c.solicitud,c.datos);
40:   update casos_todos set persona=c.persona,datos=c.datos where id=c.id;
41:   select * into c from casos_todos where nombre='valido_antes';
42:   r:=crm.recorrido_atender_oficina_fn(gen_random_uuid(),c.id,'interesado','Hechos registrados antes de activar',null,1000,'PEN');
43:   update casos_todos set tarea=(r->>'tarea_id')::uuid,actividad=(r->>'actividad_id')::uuid where id=c.id;
44: end $$;
45: reset role;
46: insert into storage.objects(bucket_id,name,metadata)
47:  select 'f4-comprobantes',datos#>>'{evidencia,ruta}','{"size":12,"mimetype":"application/pdf"}'::jsonb
48:  from casos_todos where nombre='borrador_antiguo';
49: set local role authenticated;
50: select set_config('request.jwt.claim.sub','bf1c562e-ed08-4cc3-92a8-34f1fa3e9127',true);
51: reset role;
52: select set_config('banco.revision_todos',(select revision::text from crm.recorrido_control where id),true);
53: set local role authenticated;
54: select crm.recorrido_configurar_fn('exigir','Exigencia de todas las primeras conversiones pendientes',current_setting('banco.revision_todos')::integer);
55: select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
56: select pg_temp.exigir((select bool_and((r->>'exigible')::boolean and
57:  (r->>'ciclo_inicio')::timestamptz<(respuesta->>'cohorte_desde')::timestamptz)
58:  from (select crm.recorrido_leads_fn(array(select id from casos_todos)) respuesta) q,
59:  jsonb_array_elements(respuesta->'filas') r),'los tres ciclos anteriores están incluidos en la exigencia');
60: select pg_temp.exigir((crm.recorrido_leads_fn(array[(select id from casos_todos where nombre='valido_antes')])#>>'{filas,0,habilita_conversion}')::boolean,
61:  'la entrevista anterior a activar es válida si su evidencia del ciclo ya existe');
62: select pg_temp.rechaza(format('select crm.preparar_persona_lead_inversion_fn(%L,''DNI'',%L,''BANCO ANTIGUO SIN HECHOS'')',id,documento),
63:  'P0409','Antes de convertir') from casos_todos where nombre='sin_persona_antiguo';
64: select pg_temp.rechaza(format('select crm.confirmar_inversion_revisada_fn(%L,0)',solicitud),'P0409','Antes de convertir')
65:  from casos_todos where nombre='borrador_antiguo';
66: do $$
67: declare c record;r jsonb;
68: begin
69:   select * into c from casos_todos where nombre='borrador_antiguo';
70:   r:=crm.preparar_persona_lead_inversion_fn(c.id,'DNI',c.documento,'NO CAMBIAR AL RETOMAR');
71:   perform pg_temp.exigir(r->>'solicitud_id'=c.solicitud::text,'retoma conserva la solicitud anterior');
72:   r:=crm.preparar_inversion_fn(c.solicitud,c.datos);
73:   perform pg_temp.exigir(r->>'solicitud_id'=c.solicitud::text,'mismo borrador sigue recuperable');
74: end $$;
75: reset role;
76: select pg_temp.exigir((select s.estado='preparada' and s.inversion_id is null and s.datos=c.datos and s.recorrido_confirmado is null
77:  from crm.inversion_solicitudes s join casos_todos c on c.solicitud=s.id where c.nombre='borrador_antiguo'),
78:  'rechazo de la primera conversión anterior conserva capital, comprobante y estado');
79: -- El writer interno tampoco evita la comprobación por usar la tabla directamente.
80: select set_config('request.jwt.claim.sub','',true);
81: select pg_temp.rechaza(format('update crm.inversion_solicitudes set estado=''confirmada'' where id=%L',solicitud),
82:  'P0409','Antes de convertir') from casos_todos where nombre='borrador_antiguo';
83: do $$begin raise notice 'PASS: antiguos y borrador anterior bloqueados por RPC y tabla; sin pérdida del borrador';end $$;
84: set local role authenticated;
85: select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
86: do $$
87: declare c record;r jsonb;confirmado jsonb;
88: begin
89:   select * into c from casos_todos where nombre='borrador_antiguo';
90:   r:=crm.recorrido_atender_oficina_fn(gen_random_uuid(),c.id,'interesado','Atención real del banco después del rechazo',null,1000,'PEN');
91:   update casos_todos set tarea=(r->>'tarea_id')::uuid,actividad=(r->>'actividad_id')::uuid where id=c.id;
92:   confirmado:=crm.confirmar_inversion_revisada_fn(c.solicitud,0);
93:   r:=crm.confirmar_inversion_revisada_fn(c.solicitud,0);
94:   perform pg_temp.exigir((r->>'reintento')::boolean and r->>'inversion_id'=confirmado->>'inversion_id',
95:     'completar los hechos permite confirmar y el reintento no duplica');
96: end $$;
97: reset role;
98: select pg_temp.exigir((select (s.recorrido_confirmado->>'exigible')::boolean
99:  and s.recorrido_confirmado->>'alcance'='primeras_conversiones_pendientes'
100:  and s.recorrido_confirmado->>'asistencia_id'=c.actividad::text
101:  and s.recorrido_confirmado->>'entrevista_tarea_id'=c.tarea::text
102:  from crm.inversion_solicitudes s join casos_todos c on c.solicitud=s.id where c.nombre='borrador_antiguo'),
103:  'snapshot registra la misma cita y el alcance para el lead anterior');
104: -- Corrupción sintética de un antiguo: un ciclo ausente tampoco crea una exención.
105: set local session_replication_role=replica;
106: delete from crm.lead_sla_ciclos where lead_id=(select id from casos_todos where nombre='sin_persona_antiguo');
107: set local session_replication_role=origin;
108: set local role authenticated;
109: select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
110: select pg_temp.rechaza(format('select crm.preparar_persona_lead_inversion_fn(%L,''DNI'',%L,''BANCO ANTIGUO SIN CICLO'')',id,documento),
111:  'P0409','Antes de convertir') from casos_todos where nombre='sin_persona_antiguo';
112: select pg_temp.exigir((crm.recorrido_leads_fn(array[(select id from casos_todos where nombre='sin_persona_antiguo')])#>>'{filas,0,exigible}')::boolean,
113:  'guía y servidor coinciden también para antiguo sin ciclo');
114: reset role;
115: do $$begin raise notice 'PASS: antiguo corregido confirma una vez; antiguo sin ciclo no queda exento';end $$;
116: rollback;
117: 
118: -- Inicio programado: la fecha regula CUÁNDO se exige, no QUÉ leads se incluyen.
119: begin;
120: set local statement_timeout='20s';
121: create temporary table casos_fecha(id uuid default gen_random_uuid(),documento text);
122: grant select on casos_fecha to authenticated;
123: insert into casos_fecha(documento) values('98648010');
124: insert into crm.leads(id,nombre_completo,telefono,origen,monto_estimado,vendedor_id,creado_por)
125:  select id,'BANCO FECHA FUTURA','986489999','oficina',1000,
126:  'b0000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000002' from casos_fecha;
127: select set_config('banco.revision_todos',(select revision::text from crm.recorrido_control where id),true);
128: set local role authenticated;
129: select set_config('request.jwt.claim.sub','bf1c562e-ed08-4cc3-92a8-34f1fa3e9127',true);
130: select crm.recorrido_configurar_fn('exigir','Inicio programado de la exigencia para todos',current_setting('banco.revision_todos')::integer,
131:  clock_timestamp()+interval '2 seconds');
132: select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
133: do $$begin
134:   if (crm.recorrido_leads_fn(array(select id from casos_fecha))#>>'{filas,0,exigible}')::boolean is distinct from false then
135:     raise exception 'La guía no debe exigir antes de la fecha programada';end if;
136: end $$;
137: reset role;
138: do $$declare r jsonb;begin
139:  select private.recorrido_exigir(id,'prueba_fecha_antes') into r from casos_fecha;
140:  if (r->>'exigible')::boolean is distinct from false then raise exception 'El servidor exige antes de lo programado';end if;
141: end $$;
142: select pg_sleep(2.1);
143: set local role authenticated;
144: select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
145: do $$declare c record;begin
146:   if (crm.recorrido_leads_fn(array(select id from casos_fecha))#>>'{filas,0,exigible}')::boolean is distinct from true then
147:     raise exception 'La guía debe exigir al alcanzar la fecha incluso al antiguo';end if;
148:   select * into c from casos_fecha;
149:   begin
150:     perform crm.preparar_persona_lead_inversion_fn(c.id,'DNI',c.documento,'BANCO FECHA FUTURA');
151:   exception when sqlstate 'P0409' then
152:     if position('Antes de convertir' in sqlerrm)>0 then
153:       raise notice 'PASS: inicio futuro coherente en guía y servidor; antiguo incluido al llegar la fecha';return;
154:     end if;
155:     raise;
156:   end;
157:   raise exception 'La fecha de creación no debe eximir al lead al iniciar el bloqueo';
158: end $$;
159: rollback;
160: 

### CRM-Avance-Corp/supabase/scripts/recorrido-lead/http-matriz.mjs
1: // Matriz focal de recorrido: JWT emitidos por Auth y PostgREST reales.
2: // La preparación SQL solo fabrica datos sintéticos; las acciones se prueban por HTTP.
3: import assert from 'node:assert/strict';
4: import { randomBytes, randomInt, randomUUID } from 'node:crypto';
5: import { literal as q } from './banco.mjs';
6: import { contratoPrueba } from '../f4/operaciones-fixture.mjs';
7: import { crearHandlerAccesoInversion } from '../../../../_supabase_functions/functions/crm-inversion-portal/handler.mjs';
8: 
9: export async function probarRecorridoHttp({ sql, http, apiUrl, fetchApi, anon, servicio }) {
10:   let pruebas = 0;
11:   const ok = (nombre, condicion = true) => { assert(condicion, nombre); pruebas++; console.log('PASS: ' + nombre); };
12:   const exito = (r, nombre) => { assert.equal(r.status, 200, nombre + ': ' + JSON.stringify(r.data)); return r.data; };
13:   const denegado = (r, nombre, code = '42501') => {
14:     assert(r.status >= 400, nombre); assert.equal(r.data.code, code, nombre + ': ' + JSON.stringify(r.data)); ok(nombre);
15:   };
16: 
17: 
18:   const actores = { anon: { token: anon }, servicio: { token: servicio } };
19:   const clave = 'Banco-' + randomBytes(24).toString('base64url');
20:   const ejecucion = randomUUID();
21:   const rpc = (nombre, body, actor = 'vendedor') => http('/rest/v1/rpc/' + nombre,
22:     { body, token: actores[actor].token, schema: 'crm' });
23:   async function usuario(nombre, rolPortal, rolCrm, superior = null, activoPerfil = true, activoCrm = true) {
24:     const email = `recorrido.${ejecucion}.${nombre}@pruebas.example`;
25:     const alta = await http('/auth/v1/admin/users', { token: servicio, body: { email, password: clave, email_confirm: true } });
26:     assert([200, 201].includes(alta.status), 'Crear Auth sintético');
27:     const id = alta.data.id;
28:     sql(`insert into public.perfiles(id,nombre_completo,correo,rol,activo,debe_cambiar_password,tipo_documento,dni,telefono)
29:       values(${q(id)},${q('BANCO HTTP ' + nombre)},${q(email)},${q(rolPortal)},${activoPerfil},false,
30:         'DNI',${q(String(randomInt(94000000, 94999999)))},'999888777');
31:       ${rolCrm ? `insert into crm.equipo(perfil_id,rol_crm,supervisor_id,activo)
32:         values(${q(id)},${q(rolCrm)},${superior ? q(actores[superior].id) : 'null'},${activoCrm});` : ''}`);
33:     const sesion = exito(await http('/auth/v1/token?grant_type=password', { body: { email, password: clave } }), 'Login real');
34:     actores[nombre] = { id, token: sesion.access_token };
35:   }
36:   await usuario('gerencia', 'comercial', 'gerencia');
37:   await usuario('supervisor', 'analista', 'supervisor', 'gerencia');
38:   await usuario('ajenoSupervisor', 'analista', 'supervisor', 'gerencia');
39:   await usuario('vendedor', 'analista', 'vendedor', 'supervisor');
40:   await usuario('reemplazo', 'analista', 'vendedor', 'supervisor');
41:   await usuario('ajeno', 'analista', 'vendedor', 'ajenoSupervisor');
42:   await usuario('coordinacion', 'comercial', 'coordinador');
43:   await usuario('directorio', 'directorio', 'directorio');
44:   await usuario('sinMembresia', 'analista', null);
45:   await usuario('inactivoPerfil', 'comercial', 'gerencia', null, false, false);
46:   await usuario('inactivoCrm', 'comercial', 'gerencia', null, true, false);
47: 
48:   function lead(nombre, actor = 'vendedor') {
49:     const id = randomUUID();
50:     sql(`insert into crm.leads(id,nombre_completo,telefono,origen,monto_estimado,moneda,vendedor_id,creado_por)
51:       values(${q(id)},${q('BANCO HTTP ' + nombre)},${q(String(randomInt(970000000, 979999999)))},'oficina',1000,'PEN',
52:         ${q(actores[actor].id)},${q(actores.gerencia.id)});`);
53:     return id;
54:   }
55:   const propio = lead('PROPIO'), ajeno = lead('AJENO', 'ajeno'), antiguo = lead('ANTIGUO');
56:   const leer = (ids, actor = 'vendedor') => rpc('recorrido_leads_fn', { p_lead_ids: ids }, actor);
57:   const filas = async (ids, actor = 'vendedor') => exito(await leer(ids, actor), 'Leer recorrido').filas;
58:   for (const actor of ['vendedor', 'supervisor', 'ajeno', 'ajenoSupervisor', 'gerencia', 'coordinacion', 'directorio']) {
59:     const visibles = (await filas([propio, ajeno], actor)).map(r => r.lead_id).sort();
60:     const esperados = ['gerencia', 'coordinacion', 'directorio'].includes(actor) ? [propio, ajeno]
61:       : actor.startsWith('ajeno') ? [ajeno] : [propio];
62:     assert.deepEqual(visibles, esperados.sort()); ok(actor + ' obtiene exactamente su ámbito');
63:   }
64:   for (const actor of ['anon', 'servicio', 'sinMembresia', 'inactivoPerfil', 'inactivoCrm']) {
65:     denegado(await leer([propio], actor), actor + ' no puede consultar el recorrido');
66:   }
67:   denegado(await leer(Array.from({ length: 101 }, () => randomUUID())), 'El lote mayor a 100 se rechaza', '22023');
68:   const previo = exito(await rpc('recorrido_leads_fn', { p_lead_ids: [] }, 'gerencia'), 'Control inicial');
69:   assert.equal(previo.modo, 'observacion', 'La matriz comienza en observación');
70:   const config = { p_modo: 'exigir', p_motivo: 'Ensayo de permisos en copia HTTP', p_revision: previo.revision };
71:   for (const actor of Object.keys(actores).filter(a => a !== 'gerencia')) {
72:     denegado(await rpc('recorrido_configurar_fn', config, actor), actor + ' no activa el bloqueo');
73:   }
74:   const control = exito(await rpc('recorrido_configurar_fn', config, 'gerencia'), 'Gerencia configura exigencia');
75:   ok('Solo Gerencia activa exigencia y fija corte del servidor', control.modo === 'exigir' && !!control.cohorte_desde);
76:   const obsoleta = await rpc('recorrido_configurar_fn', config, 'gerencia');
77:   assert.equal(obsoleta.status, 409, 'El conflicto no debe provocar reintentos de serialización en PostgREST');
78:   denegado(obsoleta, 'Revisión obsoleta devuelve HTTP 409 sin sobrescribir el modo', 'PT409');
79: 
80:   const documento = () => String(randomInt(97000000, 97999999));
81:   const identidad = (id, doc = documento(), actor = 'vendedor') => rpc('preparar_persona_lead_inversion_fn', {
82:     p_lead: id, p_tipo_documento: 'DNI', p_documento: doc, p_nombre: 'BANCO HTTP PERSONA',
83:   }, actor);
84:   denegado(await identidad(antiguo), 'El lead anterior al inicio también requiere asistencia y entrevista', 'P0409');
85:   ok('La guía declara exigible al lead antiguo sin hechos', (await filas([antiguo]))[0].exigible);
86:   const nuevo = lead('NUEVO SIN HECHOS'), doc = documento();
87:   const bloqueo = await identidad(nuevo, doc);
88:   denegado(bloqueo, 'Primera conversión sin hechos rechazada por API', 'P0409');
89:   assert.match(bloqueo.data.message, /asistió.*entrevista/i);
90:   assert.equal(sql(`select count(*) from crm.inversionista_identificadores where documento_normalizado=${q(doc)}`), '0');
91:   const cambio = await http(`/rest/v1/leads?id=eq.${nuevo}`, { method: 'PATCH', schema: 'crm',
92:     token: actores.vendedor.token, body: { etapa: 'propuesta_enviada' } });
93:   exito(cambio, 'Cambio de etapa permitido por el contrato vigente');
94:   denegado(await identidad(nuevo, doc), 'Cambiar de etapa no acredita asistencia ni entrevista', 'P0409');
95:   const oficina = id => ({ p_operacion_id: randomUUID(), p_lead_id: id,
96:     p_resultado_reunion: 'interesado', p_detalle: 'Asistió y realizamos la entrevista del banco',
97:     p_capital_estimado: 1000, p_moneda: 'PEN', p_siguiente: null, p_ubicacion: 'Oficina de prueba' });
98:   exito(await rpc('recorrido_atender_oficina_fn', oficina(antiguo)), 'Registrar hechos reales del lead antiguo');
99:   exito(await identidad(antiguo), 'El lead antiguo continúa después de asistencia y entrevista');
100:   ok('Antiguo habilitado por hechos de su cita, sin exención por fecha', (await filas([antiguo]))[0].habilita_conversion);
101:   for (const actor of ['ajeno', 'ajenoSupervisor', 'coordinacion', 'directorio', 'sinMembresia', 'inactivoPerfil', 'inactivoCrm', 'anon', 'servicio']) {
102:     denegado(await rpc('recorrido_atender_oficina_fn', oficina(nuevo), actor), actor + ' no registra visita fuera de su permiso');
103:   }
104:   const peticion = oficina(nuevo);
105:   const visita = exito(await rpc('recorrido_atender_oficina_fn', peticion), 'Atender visita');
106:   assert.deepEqual(exito(await rpc('recorrido_atender_oficina_fn', peticion), 'Reintento de visita'), visita);
107:   denegado(await rpc('recorrido_atender_oficina_fn', { ...peticion, p_capital_estimado: 2000 }), 'Clave repetida con otro capital rechazada', 'P0409');
108:   ok('Oficina crea una sola cita y asistencia ante respuesta perdida', sql(`select count(*) from crm.tareas where lead_id=${q(nuevo)}`) === '1');
109:   const evaluado = (await filas([nuevo]))[0];
110:   ok('La API confirma dos hechos de la misma cita y del ciclo vigente', evaluado.habilita_conversion
111:     && evaluado.exigible && evaluado.pasos.asistencia && evaluado.pasos.entrevista
112:     && evaluado.evidencias.entrevista_tarea_id === visita.tarea_id && evaluado.evidencias.asistencia_id === visita.actividad_id);
113:   const persona = exito(await identidad(nuevo, doc), 'Identidad posterior a entrevista');
114:   ok('Identidad autorizada después de registrar ambos hechos', !!persona.inversionista_id);
115:   for (const actor of ['supervisor', 'gerencia']) {
116:     exito(await rpc('recorrido_atender_oficina_fn', oficina(lead(actor)), actor), actor + ' atiende visita autorizada');
117:     ok(actor + ' puede registrar visita dentro de su ámbito');
118:   }
119: 
120:   sql("insert into storage.buckets(id,name,public) values('f4-comprobantes','f4-comprobantes',false) on conflict(id) do nothing");
121:   for (const empresa of ['qorilazo', 'prodelco']) {
122:     const id = lead('CONVERSION ' + empresa), solicitud = randomUUID();
123:     const primera = exito(await rpc('recorrido_atender_oficina_fn', oficina(id)), 'Visita antes de borrador');
124:     const p = exito(await identidad(id), 'Persona de conversión');
125:     const fecha = sql("select (clock_timestamp() at time zone 'America/Lima')::date");
126:     const datos = { inversionista_id: p.inversionista_id, lead_id: id, empresa, monto: 1000, moneda: 'PEN',
127:       fecha_comercial: fecha, vence_en: sql(`select private.coopac_validar_condiciones(${q(fecha)},12,12)`),
128:       plazo_meses: 12, tasa_anual: 12, numero_transaccion: 'RECORRIDO-HTTP-' + solicitud,
129:       referencia: 'BANCO SINTETICO', evidencia: { ruta: `${p.inversionista_id}/${solicitud}/comprobante.pdf` } };
130:     exito(await rpc('preparar_inversion_fn', { p_clave: solicitud, p_datos: datos }), 'Preparación por HTTP');
131:     // Fixture del documento subido; no simula autorización ni confirmación financiera.
132:     sql(`insert into storage.objects(bucket_id,name,metadata) values('f4-comprobantes',${q(datos.evidencia.ruta)},'{"size":12,"mimetype":"application/pdf"}');
133:       update crm.actividades set metadata=metadata||jsonb_build_object('deshecho_en',clock_timestamp()) where id=${q(primera.actividad_id)};`);
134:     denegado(await rpc('confirmar_inversion_revisada_fn', { p_solicitud: solicitud, p_revision_datos_esperada: 0 }),
135:       empresa + ': invalidar entrevista bloquea la confirmación final', 'P0409');
136:     const conservado = JSON.parse(sql(`select jsonb_build_object('datos',datos,'estado',estado,'inversion_id',inversion_id,'prueba',recorrido_confirmado)
137:       from crm.inversion_solicitudes where id=${q(solicitud)}`));
138:     assert.deepEqual(conservado, { datos, estado: 'preparada', inversion_id: null, prueba: null });
139:     ok(empresa + ': rechazo conserva borrador, condiciones y referencia del comprobante');
140:     for (const actor of ['vendedor', 'servicio']) {
141:       const r = await http(`/rest/v1/inversion_solicitudes?id=eq.${solicitud}`, { method: 'PATCH', schema: 'crm',
142:         token: actores[actor].token, body: { recorrido_confirmado: { version: 1, exigible: false } } });
143:       ok(actor + ': no puede falsificar snapshot de ' + empresa, r.status >= 400);
144:     }
145:     const vigente = exito(await rpc('recorrido_atender_oficina_fn', oficina(id)), 'Nueva entrevista válida');
146:     const confirmada = exito(await rpc('confirmar_inversion_revisada_fn', { p_solicitud: solicitud, p_revision_datos_esperada: 0 }), 'Confirmar tras corregir hechos');
147:     const repetida = exito(await rpc('confirmar_inversion_revisada_fn', { p_solicitud: solicitud, p_revision_datos_esperada: 0 }), 'Reintentar confirmada');
148:     assert.equal(repetida.inversion_id, confirmada.inversion_id);
149:     const prueba = JSON.parse(sql(`select recorrido_confirmado from crm.inversion_solicitudes where id=${q(solicitud)}`));
150:     ok(empresa + ': confirmación guarda pareja vigente y el reintento no duplica', prueba.asistencia_id === vigente.actividad_id
151:       && prueba.entrevista_tarea_id === vigente.tarea_id && prueba.exigible && repetida.reintento);
152:   }
153: 
154:   // Avance: el handler oficial crea Auth/perfil por HTTP real, sin correos ni
155:   // un despliegue Edge. La inversión siempre se confirma con JWT del analista.
156:   {
157:     const id = lead('AVANCE'), solicitud = randomUUID();
158:     const visitaAvance = exito(await rpc('recorrido_atender_oficina_fn', oficina(id)), 'Visita Avance');
159:     const p = exito(await identidad(id), 'Persona Avance');
160:     const datos = { inversionista_id: p.inversionista_id, lead_id: id, empresa: 'avance',
161:       contrato: { moneda: 'PEN' }, cronograma: [], cuenta: {}, alta_portal: {
162:         correo: `avance.${solicitud}@pruebas.example`, nombre_completo: 'PERSONA SINTETICA AVANCE',
163:         nombres: 'PERSONA', apellidos: 'SINTETICA AVANCE', telefono: '999888777', domicilio: 'AVENIDA FICTICIA 123 LIMA',
164:       } };
165:     exito(await rpc('preparar_inversion_fn', { p_clave: solicitud, p_datos: datos }), 'Borrador Avance');
166:     sql(`update crm.actividades set metadata=metadata||jsonb_build_object('deshecho_en',clock_timestamp()) where id=${q(visitaAvance.actividad_id)}`);
167:     const handler = crearHandlerAccesoInversion({ supabaseUrl: apiUrl, anonKey: anon, serviceKey: servicio, fetchImpl: fetchApi });
168:     const token = randomBytes(24).toString('hex');
169:     const acceso = async () => {
170:       const respuesta = await handler(new Request(apiUrl + '/functions/v1/crm-inversion-portal', {
171:         method: 'POST', headers: { Authorization: 'Bearer ' + actores.vendedor.token }, body: JSON.stringify({ solicitud_id: solicitud, token }),
172:       }));
173:       return { status: respuesta.status, data: await respuesta.json() };
174:     };
175:     const nAuth = sql('select count(*) from auth.users');
176:     const rechazo = await acceso();
177:     ok('Avance: falta de entrevista impide crear Auth mediante el handler oficial', rechazo.status === 409
178:       && sql('select count(*) from auth.users') === nAuth && /Antes de convertir/.test(rechazo.data.error));
179:     const vigente = exito(await rpc('recorrido_atender_oficina_fn', oficina(id)), 'Entrevista Avance corregida');
180:     const alta = exito(await acceso(), 'Alta Portal Avance por HTTP real');
181:     const fecha = sql("select to_char(clock_timestamp() at time zone 'America/Lima','YYYY-MM-01')");
182:     const propuesta = contratoPrueba(alta.perfil_id, actores.vendedor.id,
183:       { inicio: fecha, capital: 1000, numero: `${fecha.slice(0, 4)}-01-${randomInt(900000, 999999)}` });
184:     delete propuesta.contrato.cliente_id; delete propuesta.contrato.analista_cierre_id;
185:     exito(await rpc('corregir_solicitud_inversion_fn', { p_solicitud: solicitud, p_clave: randomUUID(),
186:       p_revision_datos_esperada: 0, p_datos: { ...datos, ...propuesta }, p_motivo: 'Completar condiciones ficticias tras alta Portal' }), 'Condiciones Avance');
187:     const confirmada = exito(await rpc('confirmar_inversion_revisada_fn', { p_solicitud: solicitud, p_revision_datos_esperada: 1 }), 'Confirmación Avance');
188:     const prueba = JSON.parse(sql(`select recorrido_confirmado from crm.inversion_solicitudes where id=${q(solicitud)}`));
189:     ok('Avance: primera conversión crea contrato y conserva los hechos vigentes', !!confirmada.inversion_id
190:       && prueba.asistencia_id === vigente.actividad_id && prueba.entrevista_tarea_id === vigente.tarea_id && prueba.exigible);
191:   }
192: 
193:   for (const actor of ['vendedor', 'gerencia', 'servicio', 'anon']) {
194:     for (const tabla of ['recorrido_control', 'actividad_ciclo_contexto']) {
195:       const r = await http(`/rest/v1/${tabla}?select=*`, { method: 'GET', schema: 'crm', token: actores[actor].token });
196:       ok(`${actor} no lee directamente ${tabla}`, r.status >= 400 || (Array.isArray(r.data) && r.data.length === 0));
197:       const w = await http(`/rest/v1/${tabla}`, { body: tabla === 'recorrido_control' ? { id: true, modo: 'apagado' }
198:         : { actividad_id: visita.actividad_id, lead_id: nuevo, ciclo_n: 99 }, schema: 'crm', token: actores[actor].token });
199:       ok(`${actor} no escribe directamente ${tabla}`, w.status >= 400);
200:     }
201:   }
202:   const acl = JSON.parse(sql(`select jsonb_agg(jsonb_build_object('firma',p.oid::regprocedure::text,'segura',
203:     p.prosecdef and p.proowner='postgres'::regrole and p.proconfig @> array['search_path=""']
204:     and not exists(select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
205:       where a.privilege_type='EXECUTE' and a.grantee<>p.proowner)))
206:     from pg_proc p where p.oid in (to_regprocedure('private.recorrido_exigir(uuid,text)'),
207:       to_regprocedure('private.recorrido_solicitud_guard()'),to_regprocedure('private.recorrido_insert_convertido_guard()'))`));
208:   ok('Helpers privados tienen owner, SECURITY DEFINER, search_path y ACL cerrados', acl.length === 3 && acl.every(x => x.segura));
209:   const autorizados = exito(await rpc('recorrido_leads_fn', { p_lead_ids: [nuevo] }), 'Foto antes de reasignar');
210:   exito(await http(`/rest/v1/leads?id=eq.${nuevo}`, { method: 'PATCH', schema: 'crm', token: actores.gerencia.token,
211:     body: { vendedor_id: actores.ajeno.id } }), 'Reasignación por puerta existente');
212:   assert.deepEqual(await filas([nuevo]), []);
213:   denegado(await rpc('recorrido_atender_oficina_fn', peticion), 'Ni un replay permite leer tras perder ámbito');
214:   const reasignado = (await filas([nuevo], 'ajeno'))[0];
215:   ok('Reasignar conserva el ciclo y los hechos', reasignado.habilita_conversion
216:     && reasignado.ciclo_n === autorizados.filas[0].ciclo_n);
217: 
218:   const version = sql(`select actualizado_en from crm.equipo where perfil_id=${q(actores.vendedor.id)}`);
219:   exito(await rpc('fijar_membresia_activa_fn', { p_perfil_id: actores.vendedor.id, p_activo: false,
220:     p_reemplazo_id: actores.reemplazo.id, p_version_equipo: version, p_idempotencia: randomUUID() }, 'gerencia'), 'Baja real con reemplazo');
221:   denegado(await leer([propio]), 'El JWT previo pierde acceso al desactivar la membresía');
222:   denegado(await rpc('recorrido_atender_oficina_fn', oficina(propio)), 'La membresía revocada no puede atender visitas');
223:   ok('El reemplazo conserva acceso al lead transferido', (await filas([propio], 'reemplazo')).length === 1);
224:   console.log(`HTTP/RLS recorrido: ${pruebas} comprobaciones PASS con Auth/PostgREST reales.`);
225:   return pruebas;
226: }
227: 

### CRM-Avance-Corp/supabase/scripts/recorrido-lead/concurrencia-conversion.mjs
1: // Base desechable dentro del stack propio: copia solo sus fixtures sintéticos.
2: // Nunca cambia modo/corte del banco principal ni admite destinos remotos.
3: import assert from 'node:assert/strict';
4: import { randomUUID, randomInt } from 'node:crypto';
5: import { spawn, spawnSync } from 'node:child_process';
6: import { setTimeout as esperar } from 'node:timers/promises';
7: import { contenedor, literal as q, sql as banco, archivo } from './banco.mjs';
8: 
9: const db = `recorrido_carrera_${randomUUID().replaceAll('-', '').slice(0, 12)}`;
10: const gerente = 'bf1c562e-ed08-4cc3-92a8-34f1fa3e9127';
11: const analista = 'b0000000-0000-4000-8000-000000000002';
12: const args = ['exec', '-i', contenedor, 'psql', '-X', '-qAt', '-U', 'supabase_admin', '-d', db, '-v', 'ON_ERROR_STOP=1', '-f', '-'];
13: const cabecera = "\\set VERBOSITY verbose\nset statement_timeout='20s';\n";
14: const sesiones = [];
15: const tx = (s, actor = analista) => `begin; set local role authenticated; set local request.jwt.claim.sub=${q(actor)}; ${s} commit;`;
16: const ejecutar = (s) => spawnSync('docker', args, { input: cabecera + s, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
17: function sql(s) {
18:   const r = ejecutar(s); assert.equal(r.status, 0, r.stderr || r.error?.message); return r.stdout.trim();
19: }
20: function sesion(nombre) {
21:   const app = `${db}_${nombre}`, p = spawn('docker', args);
22:   const s = { app, p, salida: '', error: '', codigo: null };
23:   p.stdout.on('data', d => { s.salida += d; }); p.stderr.on('data', d => { s.error += d; });
24:   p.stdin.on('error', () => {});
25:   s.fin = new Promise(resolve => p.on('close', code => { s.codigo = code; resolve(code); }));
26:   s.enviar = texto => p.stdin.write(texto + '\n');
27:   s.cerrar = async (texto = '') => { p.stdin.end(texto + '\n'); await s.fin; return s; };
28:   s.enviar(cabecera + `set application_name=${q(app)};`); sesiones.push(s); return s;
29: }
30: async function hasta(predicado, mensaje) {
31:   const limite = Date.now() + 8000;
32:   while (Date.now() < limite) { if (predicado()) return; await esperar(25); }
33:   assert.fail(mensaje);
34: }
35: const marcador = s => hasta(() => {
36:   assert.equal(s.codigo, null, s.error); return s.salida.includes('LISTO');
37: }, 'No llegó la barrera SQL');
38: const esperaLock = s => hasta(() => sql(`select exists(select 1 from pg_stat_activity where datname=${q(db)}
39:   and application_name=${q(s.app)} and wait_event_type='Lock')`) === 't', 'No se observó una espera real');
40: const correcto = s => assert.equal(s.codigo, 0, s.error);
41: const respuesta = s => JSON.parse(s.salida.split('\n').find(l => l.startsWith('{')));
42: const inicio = `begin; set local role authenticated; set local request.jwt.claim.sub=${q(analista)};`;
43: const confirmar = f => `select crm.confirmar_inversion_revisada_fn(${q(f.solicitud)},0);`;
44: const invalidar = f => `update crm.actividades set metadata=metadata||jsonb_build_object('deshecho_en',clock_timestamp()) where id=${q(f.actividad)};`;
45: function modo(nuevo) {
46:   const revision = Number(sql('select revision from crm.recorrido_control where id'));
47:   return tx(`select crm.recorrido_configurar_fn(${q(nuevo)},'Ensayo concurrente en base desechable',${revision});`, gerente);
48: }
49: function fixture(nombre) {
50:   const f = { lead: randomUUID(), solicitud: randomUUID(), documento: String(randomInt(97000000, 97999999)) };
51:   sql(`insert into crm.leads(id,nombre_completo,telefono,origen,monto_estimado,vendedor_id,creado_por)
52:     values(${q(f.lead)},${q('BANCO CARRERA ' + nombre)},${q(String(randomInt(970000000, 979999999)))},'oficina',1000,${q(analista)},${q(analista)});`);
53:   const oficina = JSON.parse(sql(tx(`select crm.recorrido_atender_oficina_fn(${q(randomUUID())},${q(f.lead)},'interesado','Entrevista real de banco',null,1000,'PEN');`)));
54:   f.actividad = oficina.actividad_id;
55:   const persona = JSON.parse(sql(tx(`select crm.preparar_persona_lead_inversion_fn(${q(f.lead)},'DNI',${q(f.documento)},${q('BANCO CARRERA ' + nombre)});`)));
56:   const fecha = sql("select (clock_timestamp() at time zone 'America/Lima')::date");
57:   const vence = sql(`select private.coopac_validar_condiciones(${q(fecha)},12,12)`);
58:   f.datos = { inversionista_id: persona.inversionista_id, lead_id: f.lead, empresa: 'qorilazo', monto: 1000,
59:     moneda: 'PEN', fecha_comercial: fecha, vence_en: vence, plazo_meses: 12, tasa_anual: 12,
60:     numero_transaccion: 'CARRERA-' + f.solicitud, referencia: 'BANCO SINTETICO',
61:     evidencia: { ruta: `${persona.inversionista_id}/${f.solicitud}/comprobante.pdf` } };
62:   sql(tx(`select crm.preparar_inversion_fn(${q(f.solicitud)},${q(JSON.stringify(f.datos))});`));
63:   sql(`insert into storage.objects(bucket_id,name,metadata) values('f4-comprobantes',${q(f.datos.evidencia.ruta)},'{"size":12,"mimetype":"application/pdf"}');`);
64:   return f;
65: }
66: let creada = false;
67: try {
68:   banco(`create database ${db} template template0 owner postgres;`); creada = true;
69:   const dump = (...secciones) => {
70:     const r = spawnSync('docker', ['exec', contenedor, 'pg_dump', '-U', 'supabase_admin', '-d', 'postgres', '--no-comments',
71:       ...secciones.map(s => '--section=' + s)], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
72:     assert.equal(r.status, 0, r.stderr); return r.stdout;
73:   };
74:   sql(dump('pre-data', 'data'));
75:   // El banco copió configuraciones públicas sin las personas que las publicaron.
76:   // Completar SOLO en esta copia sus FK con perfiles ficticios e inactivos antes
77:   // de restaurar constraints/triggers. No cambia funciones ni salta checks del ensayo.
78:   const referencias = banco(`select string_agg(format('select %I as id from %s where %I is not null',a.attname,c.conrelid::regclass,a.attname),' union ')
79:     from pg_constraint c join pg_attribute a on a.attrelid=c.conrelid and a.attnum=c.conkey[1]
80:     where c.contype='f' and c.confrelid='public.perfiles'::regclass and cardinality(c.conkey)=1
81:       and c.conrelid::regclass::text like 'crm.%';`);
82:   sql(`create temporary table autores_ficticios as select distinct r.id from (${referencias}) r
83:     where not exists(select 1 from public.perfiles p where p.id=r.id);
84:     insert into auth.users(id) select a.id from autores_ficticios a where not exists(select 1 from auth.users u where u.id=a.id);
85:     insert into public.perfiles(id,nombre_completo,rol,activo,tipo_documento)
86:       select id,'AUTOR FICTICIO DE CONFIGURACION','comercial',false,'DNI' from autores_ficticios;`);
87:   sql(dump('post-data'));
88:   // Replay real de fase 5 desde las definiciones de fase 3, SOLO en esta copia.
89:   // No basta con reemplazar helpers a mano: se ejecutan ambos archivos completos.
90:   const originales = ['crm.preparar_persona_lead_inversion_fn', 'crm.confirmar_inversion_revisada_fn',
91:     'crm.acceso_inversion_fn', 'private.conversion_lead_con_inversion'].map(nombre =>
92:     archivo(`../../../docs/plans/recorrido-lead-hechos/evidencia/${nombre}.sql`).trimEnd() + ';');
93:   const fase2 = archivo('../../migrations/20261019001500_crm_recorrido_evaluacion.sql');
94:   for (const firma of ['private.recorrido_control_guard()', 'crm.recorrido_configurar_fn(', 'crm.recorrido_leads_fn(']) {
95:     const start = fase2.indexOf('create function ' + firma), end = fase2.indexOf('end $$;', start) + 7;
96:     assert(start >= 0 && end > start);
97:     originales.push(fase2.slice(start, end).replace('create function', 'create or replace function'));
98:   }
99:   sql(`begin;set local role postgres;
100:     drop trigger trg_solicitudes_recorrido on crm.inversion_solicitudes;
101:     drop trigger trg_leads_zzzz_recorrido_insert on crm.leads;
102:     drop function private.recorrido_solicitud_guard(),private.recorrido_insert_convertido_guard();
103:     ${originales.join('\n')}
104:     drop function private.recorrido_exigir(uuid,text);
105:     alter table crm.inversion_solicitudes drop column recorrido_confirmado;
106:     commit;`);
107:   sql('set role postgres;\n' + archivo('../../migrations/20261019001700_crm_recorrido_conversion.sql'));
108:   sql('set role postgres;\n' + archivo('../../migrations/20261019001701_crm_recorrido_conversion_hardening.sql'));
109:   console.log('PASS: replay íntegro de fase 5 + hardening desde los contratos previos, en copia desechable.');
110:   const fase3 = archivo('../../migrations/20261019001600_crm_recorrido_oficina.sql');
111:   const extraer = (fuente, prefijo) => {
112:     const a = fuente.indexOf(prefijo), b = fuente.indexOf('end $$;', a) + 7;
113:     assert(a >= 0 && b > a);
114:     return fuente.slice(a, b).replace(/^create function/, 'create or replace function');
115:   };
116:   sql(`begin;set local role postgres;
117:     ${extraer(fase3, 'create or replace function private.recorrido_capturar_actividad()')}
118:     ${extraer(fase2, 'create function private.recorrido_serializar_invalidacion()')}
119:     alter table crm.actividad_ciclo_contexto
120:       drop constraint actividad_ciclo_contexto_estado_ciclo_check,
121:       drop constraint actividad_ciclo_contexto_check1,
122:       add constraint actividad_ciclo_contexto_estado_ciclo_check check (estado_ciclo in ('ciclo','base_sin_ciclo')),
123:       add constraint actividad_ciclo_contexto_check1 check ((estado_ciclo='ciclo' and ciclo_n is not null)
124:         or (estado_ciclo='base_sin_ciclo' and ciclo_n is null));
125:     commit;`);
126:   sql('set role postgres;\n' + archivo('../../migrations/20261019001702_crm_recorrido_revision_pr.sql'));
127:   sql('set role postgres;\n' + archivo('../../migrations/20261019001703_crm_recorrido_revision_pr_hardening.sql'));
128:   console.log('PASS: replay íntegro de correcciones del PR + hardening, sin alterar migraciones anteriores.');
129:   const integral = archivo('../../migrations/20261019061000_crm_recorrido_todos_pendientes.sql');
130:   const finPreflight = integral.indexOf('end $$;') + 'end $$;'.length;
131:   assert(finPreflight > 'end $$;'.length, 'El preflight integral debe existir.');
132:   const preflight = integral.slice(integral.indexOf('do $$'), finPreflight);
133:   const revisionPrevia = Number(sql('select revision from crm.recorrido_control where id'));
134:   const yaActivo = ejecutar(`${inicio} set local request.jwt.claim.sub=${q(gerente)};
135:     select crm.recorrido_configurar_fn('exigir','Activacion previa sintetica',${revisionPrevia});
136:     reset role; set local role postgres; ${preflight} rollback;`);
137:   assert.notEqual(yaActivo.status, 0); assert.match(yaActivo.stderr, /55000: El alcance integral se instala antes/);
138:   assert.equal(sql('select cohorte_desde is null from crm.recorrido_control where id'), 't');
139:   // Pausa entre sentencias reales del archivo, manteniendo su transacción.
140:   // Una activación concurrente debe esperar a que termine la instalación.
141:   const instalar = sesion('instalacion_integral');
142:   instalar.enviar('set role postgres;\n' + integral.slice(0, finPreflight) + '\n\\echo LISTO');
143:   await marcador(instalar);
144:   const activar = sesion('activacion_integral'); activar.enviar(modo('exigir'));
145:   await esperaLock(activar);
146:   correcto(await instalar.cerrar(integral.slice(finPreflight)));
147:   correcto(await activar.cerrar());
148:   console.log('PASS: preflight rechaza un control activado y serializa instalación con activación concurrente.');
149:   const hardeningIntegral = archivo('../../migrations/20261019061001_crm_recorrido_todos_pendientes_hardening.sql');
150:   const grantAjeno = ejecutar(`begin;set local role postgres;
151:     grant execute on function private.recorrido_exigir(uuid,text) to pg_monitor;
152:     ${hardeningIntegral.replace(/^begin;\s*$/m, '').replace(/^commit;\s*$/m, '')}
153:     rollback;`);
154:   assert.notEqual(grantAjeno.status, 0); assert.match(grantAjeno.stderr, /Helper expuesto: private.recorrido_exigir/);
155:   sql('set role postgres;\n' + hardeningIntegral);
156:   console.log('PASS: hardening rechaza también un grant inesperado a un rol fuera de los roles API.');
157:   console.log('PASS: replay íntegro del alcance para todos los pendientes + hardening.');
158:   sql('set role postgres;\n' + archivo('../../migrations/20261019061003_crm_recorrido_conflicto_http.sql'));
159:   sql('set role postgres;\n' + archivo('../../migrations/20261019061004_crm_recorrido_conflicto_http_hardening.sql'));
160:   console.log('PASS: replay de conflicto HTTP 409 + hardening, sin reintentos por SQLSTATE 40001.');
161:   sql("insert into storage.buckets(id,name,public) values('f4-comprobantes','f4-comprobantes',false) on conflict(id) do nothing;");
162:   sql(modo('exigir'));
163:   const a = fixture('CONFIRMAR PRIMERO');
164:   const c1 = sesion('confirmar_a'); c1.enviar(`${inicio}${confirmar(a)}\n\\echo LISTO`); await marcador(c1);
165:   const i1 = sesion('invalidar_b'); await i1.cerrar(`begin;${invalidar(a)}commit;`);
166:   assert.notEqual(i1.codigo, 0); assert.match(i1.error, /55P03/);
167:   correcto(await c1.cerrar('commit;'));
168:   assert.equal(sql(`select metadata ? 'deshecho_en' from crm.actividades where id=${q(a.actividad)}`), 'f');
169:   assert.equal(sql(`select recorrido_confirmado->>'asistencia_id' from crm.inversion_solicitudes where id=${q(a.solicitud)}`), a.actividad);
170:   console.log('PASS: confirmar retiene evidencia; invalidación inversa rechaza sin deadlock ni pérdida.');
171: 
172:   const b = fixture('INVALIDAR PRIMERO');
173:   const i2 = sesion('invalidar_a'); i2.enviar(`begin;${invalidar(b)}\n\\echo LISTO`); await marcador(i2);
174:   const c2 = sesion('confirmar_b'); await c2.cerrar(tx(confirmar(b)));
175:   assert.notEqual(c2.codigo, 0); assert.match(c2.error, /55P03/);
176:   correcto(await i2.cerrar('commit;'));
177:   const rechazo = ejecutar(tx(confirmar(b)));
178:   assert.notEqual(rechazo.status, 0); assert.match(rechazo.stderr, /P0409: Antes de convertir/);
179:   assert.equal(sql(`select estado||':'||(inversion_id is null)::text from crm.inversion_solicitudes where id=${q(b.solicitud)}`), 'preparada:true');
180:   console.log('PASS: invalidación gana; el reintento lee hechos vigentes y conserva el borrador sin inversión.');
181: 
182:   for (const rollback of [false, true]) {
183:     const f = fixture(rollback ? 'ROLLBACK PERDIDO' : 'DOBLE CONFIRMACION');
184:     const primera = sesion(rollback ? 'rollback_a' : 'doble_a');
185:     primera.enviar(`${inicio}${confirmar(f)}\n\\echo LISTO`); await marcador(primera);
186:     const segunda = sesion(rollback ? 'rollback_b' : 'doble_b');
187:     segunda.enviar(`${inicio}${confirmar(f)}\n\\echo LISTO`); await esperaLock(segunda);
188:     correcto(await primera.cerrar(rollback ? 'rollback;' : 'commit;'));
189:     await marcador(segunda); correcto(await segunda.cerrar('commit;'));
190:     const r1 = respuesta(primera), r2 = respuesta(segunda);
191:     if (rollback) assert.notEqual(r1.inversion_id, r2.inversion_id);
192:     else { assert.equal(r1.inversion_id, r2.inversion_id); assert.equal(r2.reintento, true); }
193:     assert.equal(sql(`select count(*) from crm.cierres_externos where numero_transaccion=upper(${q(f.datos.numero_transaccion)})`), '1');
194:     assert.equal(sql(`select count(*) from crm.inversiones where id=${q(r2.inversion_id)}`), '1');
195:     console.log(rollback ? 'PASS: confirmación revertida mientras otro envío espera crea una sola inversión al recuperar.'
196:       : 'PASS: confirmación simultánea con respuesta perdida devuelve la misma inversión, sin duplicar.');
197:   }
198: 
199:   const f = fixture('CAMBIO DE MODO'); sql(invalidar(f));
200:   const revision = Number(sql('select revision from crm.recorrido_control where id'));
201:   const cambiar = sesion('modo_a');
202:   cambiar.enviar(`begin;set local role authenticated;set local request.jwt.claim.sub=${q(gerente)};
203:     select crm.recorrido_configurar_fn('observacion','Rollback comercial concurrente del banco',${revision});\n\\echo LISTO`);
204:   await marcador(cambiar);
205:   const confirmarModo = sesion('modo_b'); confirmarModo.enviar(`${inicio}${confirmar(f)}\n\\echo LISTO`);
206:   await esperaLock(confirmarModo); correcto(await cambiar.cerrar('commit;'));
207:   await marcador(confirmarModo); correcto(await confirmarModo.cerrar('commit;'));
208:   assert.equal(sql(`select recorrido_confirmado->>'modo' from crm.inversion_solicitudes where id=${q(f.solicitud)}`), 'observacion');
209:   assert.equal(sql(`select recorrido_confirmado->>'exigible' from crm.inversion_solicitudes where id=${q(f.solicitud)}`), 'false');
210:   console.log('PASS: cambio de modo concurrente serializado; fotografía refleja la decisión confirmada.');
211: } finally {
212:   for (const s of sesiones) if (s.codigo === null) {
213:     banco(`select pg_terminate_backend(pid) from pg_stat_activity where datname=${q(db)} and application_name=${q(s.app)};`);
214:     await s.cerrar();
215:   }
216:   if (creada) {
217:     assert.match(db, /^recorrido_carrera_[a-f0-9]{12}$/);
218:     banco(`drop database ${db} with (force);`);
219:     console.log('Base desechable eliminada; modo/corte del banco principal intactos.');
220:   }
221: }
222: 

### VERIFIED EVIDENCE fase4-http-rls.log
PASS: vendedor obtiene exactamente su ámbito
PASS: supervisor obtiene exactamente su ámbito
PASS: ajeno obtiene exactamente su ámbito
PASS: ajenoSupervisor obtiene exactamente su ámbito
PASS: gerencia obtiene exactamente su ámbito
PASS: coordinacion obtiene exactamente su ámbito
PASS: directorio obtiene exactamente su ámbito
PASS: anon no puede consultar el recorrido
PASS: servicio no puede consultar el recorrido
PASS: sinMembresia no puede consultar el recorrido
PASS: inactivoPerfil no puede consultar el recorrido
PASS: inactivoCrm no puede consultar el recorrido
PASS: El lote mayor a 100 se rechaza
PASS: anon no activa el bloqueo
PASS: servicio no activa el bloqueo
PASS: supervisor no activa el bloqueo
PASS: ajenoSupervisor no activa el bloqueo
PASS: vendedor no activa el bloqueo
PASS: reemplazo no activa el bloqueo
PASS: ajeno no activa el bloqueo
PASS: coordinacion no activa el bloqueo
PASS: directorio no activa el bloqueo
PASS: sinMembresia no activa el bloqueo
PASS: inactivoPerfil no activa el bloqueo
PASS: inactivoCrm no activa el bloqueo
PASS: Solo Gerencia activa exigencia y fija corte del servidor
PASS: Revisión obsoleta devuelve HTTP 409 sin sobrescribir el modo
PASS: El lead anterior al inicio también requiere asistencia y entrevista
PASS: La guía declara exigible al lead antiguo sin hechos
PASS: Primera conversión sin hechos rechazada por API
PASS: Cambiar de etapa no acredita asistencia ni entrevista
PASS: Antiguo habilitado por hechos de su cita, sin exención por fecha
PASS: ajeno no registra visita fuera de su permiso
PASS: ajenoSupervisor no registra visita fuera de su permiso
PASS: coordinacion no registra visita fuera de su permiso
PASS: directorio no registra visita fuera de su permiso
PASS: sinMembresia no registra visita fuera de su permiso
PASS: inactivoPerfil no registra visita fuera de su permiso
PASS: inactivoCrm no registra visita fuera de su permiso
PASS: anon no registra visita fuera de su permiso
PASS: servicio no registra visita fuera de su permiso
PASS: Clave repetida con otro capital rechazada
PASS: Oficina crea una sola cita y asistencia ante respuesta perdida
PASS: La API confirma dos hechos de la misma cita y del ciclo vigente
PASS: Identidad autorizada después de registrar ambos hechos
PASS: supervisor puede registrar visita dentro de su ámbito
PASS: gerencia puede registrar visita dentro de su ámbito
PASS: qorilazo: invalidar entrevista bloquea la confirmación final
PASS: qorilazo: rechazo conserva borrador, condiciones y referencia del comprobante
PASS: vendedor: no puede falsificar snapshot de qorilazo
PASS: servicio: no puede falsificar snapshot de qorilazo
PASS: qorilazo: confirmación guarda pareja vigente y el reintento no duplica
PASS: prodelco: invalidar entrevista bloquea la confirmación final
PASS: prodelco: rechazo conserva borrador, condiciones y referencia del comprobante
PASS: vendedor: no puede falsificar snapshot de prodelco
PASS: servicio: no puede falsificar snapshot de prodelco
PASS: prodelco: confirmación guarda pareja vigente y el reintento no duplica
PASS: Avance: falta de entrevista impide crear Auth mediante el handler oficial
PASS: Avance: primera conversión crea contrato y conserva los hechos vigentes
PASS: vendedor no lee directamente recorrido_control
PASS: vendedor no escribe directamente recorrido_control
PASS: vendedor no lee directamente actividad_ciclo_contexto
PASS: vendedor no escribe directamente actividad_ciclo_contexto
PASS: gerencia no lee directamente recorrido_control
PASS: gerencia no escribe directamente recorrido_control
PASS: gerencia no lee directamente actividad_ciclo_contexto
PASS: gerencia no escribe directamente actividad_ciclo_contexto
PASS: servicio no lee directamente recorrido_control
PASS: servicio no escribe directamente recorrido_control
PASS: servicio no lee directamente actividad_ciclo_contexto
PASS: servicio no escribe directamente actividad_ciclo_contexto
PASS: anon no lee directamente recorrido_control
PASS: anon no escribe directamente recorrido_control
PASS: anon no lee directamente actividad_ciclo_contexto
PASS: anon no escribe directamente actividad_ciclo_contexto
PASS: Helpers privados tienen owner, SECURITY DEFINER, search_path y ACL cerrados
PASS: Ni un replay permite leer tras perder ámbito
PASS: Reasignar conserva el ciclo y los hechos
PASS: El JWT previo pierde acceso al desactivar la membresía
PASS: La membresía revocada no puede atender visitas
PASS: El reemplazo conserva acceso al lead transferido
HTTP/RLS recorrido: 81 comprobaciones PASS con Auth/PostgREST reales.

### VERIFIED EVIDENCE fase4-concurrencia-local-final.log
PASS: replay íntegro de fase 5 + hardening desde los contratos previos, en copia desechable.
PASS: replay íntegro de correcciones del PR + hardening, sin alterar migraciones anteriores.
PASS: preflight rechaza un control activado y serializa instalación con activación concurrente.
PASS: hardening rechaza también un grant inesperado a un rol fuera de los roles API.
PASS: replay íntegro del alcance para todos los pendientes + hardening.
PASS: replay de conflicto HTTP 409 + hardening, sin reintentos por SQLSTATE 40001.
PASS: confirmar retiene evidencia; invalidación inversa rechaza sin deadlock ni pérdida.
PASS: invalidación gana; el reintento lee hechos vigentes y conserva el borrador sin inversión.
PASS: confirmación simultánea con respuesta perdida devuelve la misma inversión, sin duplicar.
PASS: confirmación revertida mientras otro envío espera crea una sola inversión al recuperar.
PASS: cambio de modo concurrente serializado; fotografía refleja la decisión confirmada.
Base desechable eliminada; modo/corte del banco principal intactos.

### VERIFIED EVIDENCE fase4-postflight.json
{
  "fecha": "2026-10-19T07:10:40.563Z",
  "resultado": "PASS",
  "funciones": 1180,
  "funcionesNuevas": [
    {
      "acl": "{postgres=X/postgres,authenticated=X/postgres}",
      "md5": "3a5b9b0a233295b4d4fcbdf813a9a465",
      "firma": "crm.recorrido_atender_oficina_fn(uuid,uuid,text,text,jsonb,numeric,text,text)",
      "owner": "postgres"
    },
    {
      "acl": "{postgres=X/postgres,authenticated=X/postgres}",
      "md5": "6597bef760830dc37673df68e174cbec",
      "firma": "crm.recorrido_configurar_fn(text,text,integer,timestamp with time zone)",
      "owner": "postgres"
    },
    {
      "acl": "{postgres=X/postgres,authenticated=X/postgres}",
      "md5": "8490c4183e4f7a52753b53bed70b344a",
      "firma": "crm.recorrido_leads_fn(uuid[])",
      "owner": "postgres"
    },
    {
      "acl": "{postgres=X/postgres}",
      "md5": "e8f30dcb71d5a0797e18a167ba64e953",
      "firma": "private.recorrido_bloquear_insert()",
      "owner": "postgres"
    },
    {
      "acl": "{postgres=X/postgres}",
      "md5": "f4cd2764fe29966230687b1b2e250982",
      "firma": "private.recorrido_capturar_actividad()",
      "owner": "postgres"
    },
    {
      "acl": "{postgres=X/postgres}",
      "md5": "503d0ff5b52825e0a28f03ccde47b552",
      "firma": "private.recorrido_contexto_guard()",
      "owner": "postgres"
    },
    {
      "acl": "{postgres=X/postgres}",
      "md5": "14cf400ab3e7b6cb19d84e572570a05a",
      "firma": "private.recorrido_control_guard()",
      "owner": "postgres"
    },
    {
      "acl": "{postgres=X/postgres}",
      "md5": "5ee9a8d476e315aa8f9b94c4e9c93cad",
      "firma": "private.recorrido_evaluar(uuid[])",
      "owner": "postgres"
    },
    {
      "acl": "{postgres=X/postgres}",
      "md5": "aa974c790c6e8418968111a496861fc0",
      "firma": "private.recorrido_exigir(uuid,text)",
      "owner": "postgres"
    },
    {
      "acl": "{postgres=X/postgres}",
      "md5": "fb93076ab61b64588264bba57a826f7b",
      "firma": "private.recorrido_insert_convertido_guard()",
      "owner": "postgres"
    },
    {
      "acl": "{postgres=X/postgres}",
      "md5": "70e15621fbcf5d8ac38bb524114616e7",
      "firma": "private.recorrido_serializar_invalidacion()",
      "owner": "postgres"
    },
    {
      "acl": "{postgres=X/postgres}",
      "md5": "b8706eb77e491f3e9492899633401817",
      "firma": "private.recorrido_solicitud_guard()",
      "owner": "postgres"
    }
  ],
  "funcionesModificadas": [
    {
      "firma": "crm.acceso_inversion_fn(uuid,text,jsonb)",
      "antes": "38229cbb9fde4d9b5e23ee55ca6e6784",
      "despues": "282a3e9f27385611c6f4d794f977546e"
    },
    {
      "firma": "crm.confirmar_inversion_revisada_fn(uuid,integer)",
      "antes": "68828d0a443160310a3fb2fd82cd7041",
      "despues": "33af606a814c74de5de8a080430bb299"
    },
    {
      "firma": "crm.eliminar_lead_error_carga(uuid,text)",
      "antes": "15ce9327e21306ec9682552815936e71",
      "despues": "a83f9db00b71b3efa7114fbced3203bb"
    },
    {
      "firma": "crm.preparar_persona_lead_inversion_fn(uuid,text,text,text)",
      "antes": "b40dded8a923dcd02f028b24bc4de94e",
      "despues": "df451bd3cc831e2b47a26eb867c9e65e"
    },
    {
      "firma": "private.conversion_lead_con_inversion()",
      "antes": "0edf5180578781961aacbf0e78df242e",
      "despues": "e8c5fff978355f9c78a56cab67a1c65e"
    }
  ],
  "tablasModificadas": [
    {
      "nombre": "crm.actividades",
      "campos": [
        "triggers"
      ]
    },
    {
      "nombre": "crm.alertas_reconocimientos",
      "campos": [
        "restricciones"
      ]
    },
    {
      "nombre": "crm.empresas",
      "campos": [
        "restricciones"
      ]
    },
    {
      "nombre": "crm.inversion_solicitudes",
      "campos": [
        "columnas",
        "restricciones",
        "triggers"
      ]
    },
    {
      "nombre": "crm.leads",
      "campos": [
        "triggers"
      ]
    },
    {
      "nombre": "crm.producto_condiciones",
      "campos": [
        "restricciones"
      ]
    },
    {
      "nombre": "crm.tareas",
      "campos": [
        "triggers"
      ]
    }
  ],
  "tablasNuevas": [
    "crm.actividad_ciclo_contexto",
    "crm.recorrido_control"
  ],
  "permisosOriginales": "sin cambios",
  "public": "sin cambios",
  "excepcionesParentesis": 3,
  "historial": {
    "nuevas": [
      {
        "nombre": "crm_recorrido_evaluacion",
        "version": "20261019001500",
        "md5_statements": "4ad66afc274531dac9d8c488dca47034"
      },
      {
        "nombre": "crm_recorrido_evaluacion_hardening",
        "version": "20261019001501",
        "md5_statements": "8535973e1a14efea415de4045a033ca2"
      },
      {
        "nombre": "crm_recorrido_oficina",
        "version": "20261019001600",
        "md5_statements": "8a179542deceff1b66e3cde26172a2aa"
      },
      {
        "nombre": "crm_recorrido_oficina_hardening",
        "version": "20261019001601",
        "md5_statements": "bafbf8f54c1ccb2d4d3c1a8076331cde"
      },
      {
        "nombre": "crm_recorrido_conversion",
        "version": "20261019001700",
        "md5_statements": "464b6c7808b549b980bd9cb695ba4395"
      },
      {
        "nombre": "crm_recorrido_conversion_hardening",
        "version": "20261019001701",
        "md5_statements": "b46941581ac2e1695d2e09601cae566b"
      },
      {
        "nombre": "crm_recorrido_revision_pr",
        "version": "20261019001702",
        "md5_statements": "0b1b1fc3e5ed6f03d3ca302b2309031b"
      },
      {
        "nombre": "crm_recorrido_revision_pr_hardening",
        "version": "20261019001703",
        "md5_statements": "af15dca5751fb54cf3cb43e86db9e3e9"
      },
      {
        "nombre": "crm_recorrido_todos_pendientes",
        "version": "20261019061000",
        "md5_statements": "93efbccf4710936c1f30fc3e290f3804"
      },
      {
        "nombre": "crm_recorrido_todos_pendientes_hardening",
        "version": "20261019061001",
        "md5_statements": "f04e23ea2f809ac62489c841149962b7"
      },
      {
        "nombre": "crm_recorrido_indice_cita",
        "version": "20261019061002",
        "md5_statements": "5bf8249322647d58add23632d2630852"
      },
      {
        "nombre": "crm_recorrido_conflicto_http",
        "version": "20261019061003",
        "md5_statements": "22f3b5a2e6ea8c33e60a88b845340e59"
      },
      {
        "nombre": "crm_recorrido_conflicto_http_hardening",
        "version": "20261019061004",
        "md5_statements": "3db06897cbeab7075858e73876be7fc9"
      }
    ],
    "cantidad": 522,
    "base_digest": "8fe3fd28649301bac91ed91973d1dc8c"
  },
  "runtime": {
    "SLA": "OK: nucleo SLA privado, adaptadores dependientes, entradas cerradas y auditadas",
    "cron_activos": 0,
    "cuelgues_control": 0,
    "triggers_inactivos": 0
  }
}
### VERIFIED EVIDENCE fase4-reversion-resumen.json
{
  "fecha": "2026-10-19T07:09:34.558Z",
  "resultado": "PASS",
  "modos": [
    "observacion",
    "apagado",
    "exigir"
  ],
  "evidenciaYConfirmaciones": "huellas idénticas antes/después",
  "control": "restaurado exactamente por ROLLBACK"
}
### VERIFIED EVIDENCE fase4-http-conflicto.json
{
  "peticiones": 123,
  "maxMs": 792,
  "conflicto": [
    {
      "ruta": "/rest/v1/rpc/recorrido_configurar_fn",
      "method": "POST",
      "status": 409,
      "code": "PT409",
      "ms": 170
    }
  ]
}
