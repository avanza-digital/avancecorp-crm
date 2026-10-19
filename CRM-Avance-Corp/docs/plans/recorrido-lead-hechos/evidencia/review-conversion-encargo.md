ROLE: SECONDARY_REVIEWER.
Codex is PRIMARY. Independent critical implementation review of phase 5. Do not modify files. Do not implement. Do not invoke Codex. Do not delegate or start another review. Tools disabled; all evidence follows.
Return VERDICT, SUMMARY, evidence-backed P0-P3 FINDINGS, pertinent TEST GAPS, NEXT ACTIONS, CONFIDENCE per protocol.

User goal: first lead conversion MUST have real appointment attendance and explicit commercial interview, tied to the same appointment/current lead cycle. Booking/dragging alone insufficient. Contact before the appointment is not an extra blocker. Additional/renewal/upgrade of existing customers retain their flows. Observation default; enforcement only new cycles from immutable activation cutoff; old leads require later explicit policy, no backfill. Preserve drafts, actual Auth recovery, retry idempotency, concurrency and permissions. No production writes/activation/publish.

Baseline is production-read-only schema copied into isolated own Docker stack, candidate baseline MD5 preflights passed. Existing live 4 function bodies copied exactly with added guard calls (new columns/helpers/triggers are first section). Do not invent tenant columns: singleton installation. Current existing lock paths identity/person -> request -> lead NOWAIT retained, no rewrite of financial or identity engines. Existing evidence invalidation UPDATE/DELETE also locks lead NOWAIT, even auth.uid null. Helper takes lead then control SHARE and evaluates in a SEPARATE statement at READ COMMITTED. No activity/task row lock after lead. No generic context guard because reads/cancel/recovery use it. Actual Auth already created matching request claim+email is recoverable; claim alone is NOT exemption. Final confirmation always rechecks. SQL cannot hold lock across external Auth HTTP; final conversion guard is authority.

PASS local: installation+hardening, SQL actual authenticated roles with all triggers: identity missing/only stage/future/sin_clasificar denied; actual normal appointment+interview without prior call accepted; Qorilazo and Prodelco first conversions; old cohort not retroblocked; invalidated draft recovery preserved but new draft/confirm denied; immutable proof; confirmed retry after invalidation returns old result; additional investment succeeds; access claim without Auth denied, actual Auth with lost reply recovers through registrar_auth/crear_perfil/enlazar while final conversion blocked; reopening starts new cycle requiring new evidence; privileged INSERT converted and direct prepared->confirmed blocked. Entire SQL test ROLLBACK. Auth/Storage rows are explicit synthetic fixtures, not HTTP E2E. Phase 3 office SQL and concurrency passed. Phase4 469 UI tests + typecheck/lint/build. Current NOT RUN: phase5 concurrency/final broader gates and phase6 DockerE2E. Specialized auditor-RLS will review grants before real matrix; this review focus critical business correctness, recoverability/concurrency and bypasses. No CodeGraph in isolated clone; previous CodeGraph attempt unavailable, direct source evidence below.

Question: any actionable bypass or regression introduced by these exact changes? Existing complete flow and failures distinguish from hypothetical generic improvements. Particularly observe control cutoff, replays, actual Auth recovery, relation proof consistency and table guards. Cite source lines. Do not declare full goal complete.


FILE supabase/migrations/20261019001500_crm_recorrido_evaluacion.sql
1: -- Recorrido por hechos. Primera conversión: asistencia + entrevista de la misma cita.
2: -- Instalación en observación. No activa bloqueos ni reconstruye evidencias antiguas.
3: begin;
4: set local search_path='';
5: set local quote_all_identifiers=off;
6: do $$ begin
7:   if md5(pg_get_functiondef('crm.eliminar_lead_error_carga(uuid,text)'::regprocedure))<>'15ce9327e21306ec9682552815936e71' then
8:     raise exception 'La puerta de eliminacion cambio; revisar su version vigente antes de ampliar la copia' using errcode='55000';
9:   end if;
10:   perform private.assert_sla_nucleo();
11: end $$;
12:
13: create table crm.recorrido_control (
14:   id boolean primary key default true check (id),
15:   modo text not null default 'observacion' check (modo in ('apagado','observacion','exigir')),
16:   cohorte_desde timestamptz check (isfinite(cohorte_desde)),
17:   revision integer not null default 1 check (revision > 0),
18:   motivo text not null default 'Instalacion en observacion' check (length(btrim(motivo)) between 8 and 1000),
19:   actualizado_por uuid references public.perfiles(id),
20:   actualizado_en timestamptz not null default clock_timestamp() check (isfinite(actualizado_en)),
21:   check (modo <> 'exigir' or cohorte_desde is not null)
22: );
23: alter table crm.recorrido_control enable row level security;
24: revoke all on crm.recorrido_control from public, anon, authenticated, service_role;
25: create trigger audit_recorrido_control after insert or update or delete on crm.recorrido_control
26:   for each row execute function private.log_audit_crm();
27: insert into crm.recorrido_control(id) values (true);
28: comment on table crm.recorrido_control is 'Estado administrativo de esta instalacion, no un tenant ni una empresa de inversion. Corte inmutable; auditoria before/after existente. Solo puerta gerencial.';
29:
30: create table crm.actividad_ciclo_contexto (
31:   actividad_id uuid primary key references crm.actividades(id) on delete cascade,
32:   lead_id uuid not null references crm.leads(id),
33:   ciclo_n integer check (ciclo_n > 0),
34:   estado_ciclo text not null check (estado_ciclo in ('ciclo','base_sin_ciclo')),
35:   registrado_en timestamptz not null check (isfinite(registrado_en)),
36:   gesto_oficina_id uuid,
37:   oficina_tarea_id uuid references crm.tareas(id),
38:   foreign key (lead_id, ciclo_n) references crm.lead_sla_ciclos(lead_id, ciclo_n),
39:   check ((gesto_oficina_id is null) = (oficina_tarea_id is null)),
40:   check ((estado_ciclo='ciclo' and ciclo_n is not null) or (estado_ciclo='base_sin_ciclo' and ciclo_n is null))
41: );
42: alter table crm.actividad_ciclo_contexto enable row level security;
43: revoke all on crm.actividad_ciclo_contexto from public, anon, authenticated, service_role;
44: create index actividad_ciclo_contexto_lead_ciclo_idx on crm.actividad_ciclo_contexto(lead_id,ciclo_n,registrado_en);
45: create trigger audit_actividad_ciclo_contexto after insert or update or delete on crm.actividad_ciclo_contexto
46:   for each row execute function private.log_audit_crm();
47: comment on table crm.actividad_ciclo_contexto is 'Clave causal inmutable 1:1 de actividades. El hecho sigue en actividades; no se aceptan ciclos, horas ni marcas de oficina desde metadata del cliente.';
48:
49: create function private.recorrido_contexto_guard() returns trigger
50: language plpgsql set search_path='' as $$
51: begin
52:   if tg_op='DELETE' then
53:     -- Misma autorización de copia exacta, actor y transacción de la puerta oficial.
54:     if private.borrado_lead_error_autoriza(tg_table_name,to_jsonb(old)) then
55:       return old;
56:     end if;
57:   end if;
58:   if tg_op<>'INSERT' or pg_trigger_depth()<2
59:     or current_setting('crm.recorrido_contexto_writer',true) is distinct from 'on'
60:     or current_user::regrole::oid<>(select relowner from pg_class where oid=tg_relid) then
61:     raise exception 'El contexto del recorrido solo lo registra el servidor' using errcode='42501';
62:   end if;
63:   if not exists(select 1 from crm.actividades a where a.id=new.actividad_id and a.lead_id=new.lead_id) then
64:     raise exception 'Contexto ajeno a la actividad' using errcode='23514';
65:   end if;
66:   return new;
67: end $$;
68: create trigger recorrido_contexto_guard before insert or update or delete on crm.actividad_ciclo_contexto
69:   for each row execute function private.recorrido_contexto_guard();
70: create trigger recorrido_contexto_no_truncate before truncate on crm.actividad_ciclo_contexto
71:   for each statement execute function private.recorrido_contexto_guard();
72:
73: create function private.recorrido_bloquear_insert() returns trigger
74: language plpgsql security definer set search_path='' as $$
75: begin
76:   -- BEFORE evita subir KEY SHARE de la FK a UPDATE en dos inserts internos
77:   -- concurrentes. El AFTER vuelve a leer bajo el lock ya adquirido.
78:   perform 1 from crm.leads where id=new.lead_id for update;
79:   return new;
80: end $$;
81: create trigger trg_02_recorrido_lock before insert on crm.actividades for each row
82:   when (new.tipo in ('llamada_realizada','llamada_no_contestada','whatsapp_enviado','whatsapp_recibido','reunion_realizada'))
83:   execute function private.recorrido_bloquear_insert();
84:
85: create function private.recorrido_capturar_actividad() returns trigger
86: language plpgsql security definer set search_path='' as $$
87: declare
88:   v_ciclo integer; v_hora timestamptz; v_lead crm.leads%rowtype;
89:   v_writer text:=coalesce(current_setting('crm.recorrido_contexto_writer',true),'off');
90:   v_oficina jsonb; v_gesto uuid; v_tarea uuid;
91: begin
92:   -- Incluso los writers internos se serializan con la reapertura del lead.
93:   select * into strict v_lead from crm.leads where id=new.lead_id for update;
94:   v_ciclo:=v_lead.ciclo_actual;
95:   v_hora:=clock_timestamp();
96:   if not exists(select 1 from crm.lead_sla_ciclos c where c.lead_id=new.lead_id and c.ciclo_n=v_ciclo) then
97:     -- B8: una base cargada nace descartada SIN ciclo SLA. Registrar un intento
98:     -- no la reactiva. Se conserva su recepción real, sin inventar un ciclo.
99:     -- bases_carga_nace_dormido también exige la válvula de CARGA, apagada al
100:     -- gestionar después. Aquí comprobamos su estado persistido y ausencia de
101:     -- ciclos; origen/motivo están protegidos por el guard vigente de bases.
102:     if v_lead.origen='base_cargada' and v_lead.etapa='descartado'
103:       and v_lead.motivo_descarte='base_cargada' and v_lead.activo
104:       and not exists(select 1 from crm.lead_sla_ciclos c where c.lead_id=new.lead_id) then
105:       v_ciclo:=null;
106:     else
107:       raise exception 'Falta el ciclo del recorrido de la actividad' using errcode='23514';
108:     end if;
109:   end if;
110:   v_oficina:=nullif(current_setting('crm.recorrido_oficina',true),'')::jsonb;
111:   if new.tipo='reunion_realizada' and v_oficina->>'lead_id'=new.lead_id::text
112:     and v_oficina->>'tarea_id'=new.metadata->>'tarea_id' then
113:     v_gesto:=(v_oficina->>'operacion_id')::uuid;
114:     v_tarea:=(v_oficina->>'tarea_id')::uuid;
115:   end if;
116:   perform set_config('crm.recorrido_contexto_writer','on',true);
117:   insert into crm.actividad_ciclo_contexto(actividad_id,lead_id,ciclo_n,estado_ciclo,registrado_en,gesto_oficina_id,oficina_tarea_id)
118:     values(new.id,new.lead_id,v_ciclo,case when v_ciclo is null then 'base_sin_ciclo' else 'ciclo' end,v_hora,v_gesto,v_tarea);
119:   perform set_config('crm.recorrido_contexto_writer',v_writer,true);
120:   return null;
121: end $$;
122: create trigger trg_02_recorrido_contexto after insert on crm.actividades for each row
123:   when (new.tipo in ('llamada_realizada','llamada_no_contestada','whatsapp_enviado','whatsapp_recibido','reunion_realizada'))
124:   execute function private.recorrido_capturar_actividad();
125:
126: create function private.recorrido_serializar_invalidacion() returns trigger
127: language plpgsql security definer set search_path='' as $$
128: declare v_lead uuid:=old.lead_id;
129: begin
130:   if v_lead is not null then
131:     -- Las puertas normales ya poseen este lock. NOWAIT impide una espera
132:     -- circular si un writer privilegiado llega primero por tarea/actividad.
133:     perform 1 from crm.leads where id=v_lead for update nowait;
134:     if tg_op='UPDATE' and new.lead_id is distinct from old.lead_id then
135:       raise exception 'La evidencia no cambia de lead' using errcode='23514';
136:     end if;
137:   end if;
138:   return case when tg_op='DELETE' then old else new end;
139: end $$;
140: create trigger trg_00_recorrido_invalidacion before update or delete on crm.actividades for each row
141:   execute function private.recorrido_serializar_invalidacion();
142: create trigger trg_tareas_00_recorrido_invalidacion before update or delete on crm.tareas for each row
143:   execute function private.recorrido_serializar_invalidacion();
144:
145: create function private.recorrido_control_guard() returns trigger
146: language plpgsql set search_path='' as $$
147: begin
148:   if tg_op<>'UPDATE'
149:     or current_user::regrole::oid<>(select relowner from pg_class where oid=tg_relid)
150:     or current_setting('crm.recorrido_control_writer',true) is distinct from 'on' then
151:     raise exception 'El modo cambia solo por la puerta del recorrido' using errcode='42501';
152:   end if;
153:   if new.id is distinct from old.id or new.revision<>old.revision+1
154:     or (old.cohorte_desde is not null and new.cohorte_desde is distinct from old.cohorte_desde)
155:     or (old.cohorte_desde is null and new.cohorte_desde<statement_timestamp()) then
156:     raise exception 'Corte inmutable o revision invalida' using errcode='23514';
157:   end if;
158:   return new;
159: end $$;
160: create trigger recorrido_control_guard before insert or update or delete on crm.recorrido_control
161:   for each row execute function private.recorrido_control_guard();
162: create trigger recorrido_control_no_truncate before truncate on crm.recorrido_control
163:   for each statement execute function private.recorrido_control_guard();
164:
165: create function crm.recorrido_configurar_fn(p_modo text,p_motivo text,p_revision integer,p_cohorte_desde timestamptz default null)
166: returns jsonb language plpgsql security definer set search_path='' as $$
167: declare v_control crm.recorrido_control%rowtype;
168:   v_writer text:=coalesce(current_setting('crm.recorrido_control_writer',true),'off');
169: begin
170:   if not private.es_gerencia_crm_activa() then raise exception 'No autorizado' using errcode='42501'; end if;
171:   if p_modo is null or p_modo not in ('apagado','observacion','exigir')
172:     or p_motivo is null or length(btrim(p_motivo)) not between 8 and 1000
173:     or p_revision is null or (p_cohorte_desde is not null and not isfinite(p_cohorte_desde)) then
174:     raise exception 'Indica modo, motivo y revision validos' using errcode='22023';
175:   end if;
176:   select * into strict v_control from crm.recorrido_control where id for update;
177:   if v_control.revision<>p_revision then raise exception 'El modo cambio; consulta de nuevo' using errcode='40001'; end if;
178:   if v_control.cohorte_desde is not null and p_cohorte_desde is not null and p_cohorte_desde<>v_control.cohorte_desde then
179:     raise exception 'El corte de activacion no se reinicia' using errcode='22023';
180:   end if;
181:   if v_control.cohorte_desde is null and p_cohorte_desde is not null and p_cohorte_desde<clock_timestamp() then
182:     raise exception 'La activacion inicial solo admite ciclos nuevos; antiguos requieren politica explicita' using errcode='22023';
183:   end if;
184:   perform set_config('crm.recorrido_control_writer','on',true);
185:   update crm.recorrido_control set modo=p_modo, motivo=btrim(p_motivo), revision=revision+1,
186:     cohorte_desde=coalesce(cohorte_desde,p_cohorte_desde,case when p_modo='exigir' then clock_timestamp() end),
187:     actualizado_por=(select auth.uid()),actualizado_en=clock_timestamp()
188:     where id returning * into v_control;
189:   perform set_config('crm.recorrido_control_writer',v_writer,true);
190:   return to_jsonb(v_control)-'id';
191: end $$;
192:
193: -- Sin locks de hechos. VOLATILE permite snapshot nuevo cuando el guard llama
194: -- en una sentencia POSTERIOR a adquirir el lock del lead.
195: create function private.recorrido_evaluar(p_lead_ids uuid[])
196: returns table(lead_id uuid,resultado jsonb)
197: language sql volatile set search_path='' as $$
198: with leads as materialized (
199:   select l.id,l.ciclo_actual,l.etapa,l.vendedor_id,l.activo,c.iniciado_en,
200:     (select count(*)=1 and min(h.ciclo_n)=1 from crm.lead_sla_ciclos h where h.lead_id=l.id) unico_ciclo
201:   from crm.leads l left join crm.lead_sla_ciclos c on c.lead_id=l.id and c.ciclo_n=l.ciclo_actual
202:   where l.id=any(p_lead_ids)
203: ), actividades as materialized (
204:   select a.id,a.lead_id,a.tipo,a.metadata,a.creado_en,x.registrado_en,x.gesto_oficina_id,x.oficina_tarea_id,
205:     case when x.actividad_id is not null then x.ciclo_n=l.ciclo_actual
206:       when l.unico_ciclo and l.ciclo_actual=1 then true
207:       when exists(select 1 from crm.tarea_sla_contexto tc where tc.tarea_id::text=a.metadata->>'tarea_id'
208:           and tc.lead_id=a.lead_id and tc.ciclo_n=l.ciclo_actual) then true
209:       when exists(select 1 from crm.lead_sla_etapa_ajustes aj join crm.lead_sla_etapas e on e.id=aj.etapa_sla_id
210:           where aj.origen_actividad_id=a.id and e.lead_id=a.lead_id and e.ciclo_n=l.ciclo_actual) then true
211:       else false end del_ciclo
212:   from leads l join crm.actividades a on a.lead_id=l.id
213:     left join crm.actividad_ciclo_contexto x on x.actividad_id=a.id
214:   where a.tipo in ('llamada_realizada','llamada_no_contestada','whatsapp_enviado','whatsapp_recibido','reunion_realizada')
215:     and not (a.metadata ? 'deshecho_en')
216: ), citas as materialized (
217:   select t.id,t.lead_id,t.estado,t.vence_en,t.resultado_reunion,t.resultado_actividad_id,
218:     tc.ciclo_n=l.ciclo_actual del_ciclo,
219:     a.id asistencia_id,
220:     -- La evidencia nueva tiene hora de recepción real; no confía en backdates.
221:     -- Historia sin sello se conserva como ambigua para la política de antiguos.
222:     a.id is not null and a.registrado_en is not null and t.vence_en<=a.registrado_en asistencia_valida,
223:     a.id is not null and a.registrado_en is not null and t.vence_en<=a.registrado_en
224:       and t.resultado_reunion in ('interesado','seguimiento','propuesta','inicia_registro','no_interesado') entrevista_valida
225:   from leads l join crm.tareas t on t.lead_id=l.id
226:     left join crm.tarea_sla_contexto tc on tc.tarea_id=t.id and tc.lead_id=l.id
227:     left join actividades a on a.id=t.resultado_actividad_id and a.lead_id=l.id and a.del_ciclo
228:       and a.tipo='reunion_realizada' and a.metadata->>'tarea_id'=t.id::text and t.estado='completada'
229:   where t.tipo='reunion' and t.activo and t.estado in ('pendiente','completada')
230: ), hechos as (
231:   select l.*,
232:     (select a.id from actividades a where a.lead_id=l.id and a.del_ciclo order by a.registrado_en nulls last,a.id limit 1) gestion_id,
233:     (select a.id from actividades a where a.lead_id=l.id and a.del_ciclo
234:       and (a.tipo in ('llamada_realizada','whatsapp_recibido') or a.gesto_oficina_id is not null)
235:       order by a.registrado_en nulls last,a.id limit 1) contacto_id,
236:     (select t.id from citas t where t.lead_id=l.id and t.del_ciclo
237:       order by t.entrevista_valida desc nulls last,t.vence_en,t.id limit 1) cita_id,
238:     (select t.id from citas t where t.lead_id=l.id and t.del_ciclo and t.entrevista_valida
239:       order by t.vence_en,t.id limit 1) entrevista_tarea_id,
240:     (select t.id from citas t where t.lead_id=l.id and t.del_ciclo and t.asistencia_valida
241:       order by t.entrevista_valida desc,t.vence_en,t.id limit 1) asistencia_tarea_id,
242:     (select t.id from citas t where t.lead_id=l.id and t.del_ciclo and t.estado='pendiente'
243:       order by t.vence_en,t.id limit 1) pendiente_tarea_id,
244:     exists(select 1 from citas t where t.lead_id=l.id and
245:       (t.del_ciclo is null or (t.del_ciclo and t.estado='completada' and t.asistencia_id is not null
246:          and exists(select 1 from actividades a where a.id=t.asistencia_id and a.registrado_en is null)))) historico_ambiguo
247:   from leads l
248: )
249: select h.id,jsonb_build_object(
250:   'lead_id',h.id,'ciclo_n',h.ciclo_actual,'ciclo_inicio',h.iniciado_en,
251:   'aplica',h.activo and h.etapa not in ('convertido','descartado'),
252:   'estado',case when h.entrevista_tarea_id is not null then 'completo'
253:     when h.iniciado_en is null or h.historico_ambiguo then 'ambiguo' else 'incompleto' end,
254:   'habilita_conversion',h.entrevista_tarea_id is not null,
255:   'pasos',jsonb_build_object('gestionado',h.gestion_id is not null,'contactado',h.contacto_id is not null,
256:     'cita_agendada',h.cita_id is not null,'asistencia',h.asistencia_tarea_id is not null,'entrevista',h.entrevista_tarea_id is not null),
257:   'evidencias',jsonb_build_object('gestion_id',h.gestion_id,'contacto_id',h.contacto_id,'cita_id',h.cita_id,
258:     'entrevista_tarea_id',h.entrevista_tarea_id,
259:     'asistencia_tarea_id',h.asistencia_tarea_id,
260:     'asistencia_id',(select t.asistencia_id from citas t where t.id=h.asistencia_tarea_id)),
261:   'pendiente',case when h.entrevista_tarea_id is not null then 'listo'
262:     when h.vendedor_id is null then 'asignar_analista'
263:     when h.pendiente_tarea_id is not null then case when
264:       (select t.vence_en>clock_timestamp() from citas t where t.id=h.pendiente_tarea_id) then 'esperar_cita' else 'cerrar_entrevista' end
265:     when h.historico_ambiguo or h.iniciado_en is null then 'revisar_historial'
266:     when h.asistencia_tarea_id is not null then 'revisar_entrevista' else 'agendar_cita' end,
267:   'tarea_pendiente_id',h.pendiente_tarea_id,
268:   'cita_pendiente_en',(select t.vence_en from citas t where t.id=h.pendiente_tarea_id)
269: )
270: from hechos h;
271: $$;
272:
273: create function crm.recorrido_leads_fn(p_lead_ids uuid[]) returns jsonb
274: language plpgsql security definer set search_path='' as $$
275: declare v_amb record;v_ids uuid[];v_filas jsonb;v_control crm.recorrido_control%rowtype;
276: begin
277:   select * into strict v_amb from private.sla_operacion_ambito(p_lead_ids,false);
278:   if p_lead_ids is null or cardinality(p_lead_ids)>100 then
279:     raise exception 'Consulta entre cero y cien leads por lote' using errcode='22023';end if;
280:   select array_agg(l.id) into v_ids from crm.leads l where l.id=any(p_lead_ids) and l.activo
281:     and (v_amb.es_global or l.vendedor_id=any(v_amb.visibles)
282:       or (l.vendedor_id is null and l.asignado_supervisor_id=any(v_amb.visibles)));
283:   select * into strict v_control from crm.recorrido_control where id;
284:   select coalesce(jsonb_agg(e.resultado||jsonb_build_object('exigible',coalesce(v_control.modo='exigir'
285:       and (e.resultado->>'ciclo_inicio')::timestamptz>=v_control.cohorte_desde
286:       and (e.resultado->>'aplica')::boolean,false)) order by e.lead_id),'[]'::jsonb)
287:     into v_filas from private.recorrido_evaluar(coalesce(v_ids,'{}'::uuid[])) e;
288:   return jsonb_build_object('version',1,'modo',v_control.modo,'revision',v_control.revision,
289:     'cohorte_desde',v_control.cohorte_desde,'filas',v_filas);
290: end $$;
291:
292: -- Compatibilidad: misma puerta auditada, ahora conoce y conserva la relación causal.
293: CREATE OR REPLACE FUNCTION crm.eliminar_lead_error_carga(p_lead_id uuid, p_motivo text)
294:  RETURNS jsonb

FILE supabase/migrations/20261019001600_crm_recorrido_oficina.sql
1: -- Atención presencial explícita: cita inmediata + asistencia + entrevista.
2: -- Reutiliza el cierre v3 y su próxima acción. No activa exigencia de conversión.
3: begin;
4: set local search_path='';
5: set local quote_all_identifiers=off;
6: do $$ begin
7:   if md5(pg_get_functiondef('private.recorrido_capturar_actividad()'::regprocedure))<>'e51911e9d36bd8d210c90186cae95fbb'
8:     or md5(pg_get_functiondef('crm.cerrar_reunion_v3(uuid,uuid,text,text,text,text,jsonb,numeric,text)'::regprocedure))<>'c0fa9a8ebb04cf84bc41155d4a318e30' then
9:     raise exception 'Cambio el contrato de captura o cierre; revisar antes de instalar oficina' using errcode='55000';
10:   end if;
11:   perform private.assert_sla_nucleo();
12: end $$;
13:
14: -- Una GUC por sí sola no acredita el gesto. Debe corresponder al recibo privado
15: -- pendiente de ESTA transacción, actor y payload íntegro, con tarea/lead enlazados.
16: create or replace function private.recorrido_capturar_actividad() returns trigger
17: language plpgsql security definer set search_path='' as $$
18: declare
19:   v_ciclo integer; v_hora timestamptz; v_lead crm.leads%rowtype;
20:   v_writer text:=coalesce(current_setting('crm.recorrido_contexto_writer',true),'off');
21:   v_oficina jsonb; v_gesto uuid; v_tarea uuid;
22: begin
23:   select * into strict v_lead from crm.leads where id=new.lead_id for update;
24:   v_ciclo:=v_lead.ciclo_actual;
25:   v_hora:=clock_timestamp();
26:   if not exists(select 1 from crm.lead_sla_ciclos c where c.lead_id=new.lead_id and c.ciclo_n=v_ciclo) then
27:     if v_lead.origen='base_cargada' and v_lead.etapa='descartado'
28:       and v_lead.motivo_descarte='base_cargada' and v_lead.activo
29:       and not exists(select 1 from crm.lead_sla_ciclos c where c.lead_id=new.lead_id) then
30:       v_ciclo:=null;
31:     else
32:       raise exception 'Falta el ciclo del recorrido de la actividad' using errcode='23514';
33:     end if;
34:   end if;
35:   v_oficina:=nullif(current_setting('crm.recorrido_oficina',true),'')::jsonb;
36:   if new.tipo='reunion_realizada' and v_oficina#>>'{payload,lead_id}'=new.lead_id::text
37:     and v_oficina#>>'{payload,tarea_id}'=new.metadata->>'tarea_id'
38:     and v_oficina->>'clave'='recorrido_oficina:'||(select auth.uid())::text||':'||(v_oficina->>'operacion_id')
39:     and exists(select 1 from crm.multiempresa_idempotencia m
40:       where m.clave=v_oficina->>'clave' and m.tipo='recorrido_oficina'
41:         and m.creado_por=(select auth.uid()) and m.resultado is null
42:         and m.hash_payload=private.idem_hash(v_oficina->'payload')) then
43:     v_gesto:=(v_oficina->>'operacion_id')::uuid;
44:     v_tarea:=(v_oficina#>>'{payload,tarea_id}')::uuid;
45:   end if;
46:   perform set_config('crm.recorrido_contexto_writer','on',true);
47:   insert into crm.actividad_ciclo_contexto(actividad_id,lead_id,ciclo_n,estado_ciclo,registrado_en,gesto_oficina_id,oficina_tarea_id)
48:     values(new.id,new.lead_id,v_ciclo,case when v_ciclo is null then 'base_sin_ciclo' else 'ciclo' end,v_hora,v_gesto,v_tarea);
49:   perform set_config('crm.recorrido_contexto_writer',v_writer,true);
50:   return null;
51: end $$;
52:
53: create function crm.recorrido_atender_oficina_fn(
54:   p_operacion_id uuid,p_lead_id uuid,p_resultado_reunion text,
55:   p_detalle text default null,p_siguiente jsonb default null,
56:   p_capital_estimado numeric default null,p_moneda text default null,
57:   p_ubicacion text default 'Oficina')
58: returns jsonb language plpgsql security definer set search_path='' as $$
59: declare
60:   v_actor uuid:=(select auth.uid());
61:   v_clave text; v_hash text; v_payload jsonb; v_respuesta jsonb;
62:   v_lead crm.leads%rowtype; v_tarea uuid; v_cierre uuid;
63:   v_anterior text:=coalesce(current_setting('crm.recorrido_oficina',true),'');
64: begin
65:   if v_actor is null or private.rol_crm(v_actor) is null
66:     or private.rol_crm(v_actor) not in ('vendedor','supervisor','gerencia') then
67:     raise exception 'No autorizado' using errcode='42501';
68:   end if;
69:   if p_operacion_id is null or p_lead_id is null
70:     or p_resultado_reunion is null or p_resultado_reunion not in
71:       ('interesado','seguimiento','propuesta','inicia_registro','no_interesado')
72:     or nullif(btrim(p_ubicacion),'') is null or length(btrim(p_ubicacion))>500
73:     or length(coalesce(p_detalle,''))>4000
74:     or (p_siguiente is not null and jsonb_typeof(p_siguiente)<>'object') then
75:     raise exception 'Registra la entrevista, su resultado y la oficina de atencion' using errcode='22023';
76:   end if;
77:   if current_setting('transaction_isolation')<>'read committed' then
78:     raise exception 'La atencion necesita aislamiento READ COMMITTED' using errcode='55000';
79:   end if;
80:   if private.sla_gestion_permitida(v_actor,p_lead_id) is distinct from true then
81:     raise exception 'Gestion no disponible en tu ambito' using errcode='42501';
82:   end if;
83:   v_clave:='recorrido_oficina:'||v_actor::text||':'||p_operacion_id::text;
84:   -- Identificador estable por operación y actor; no acepta IDs de tareas ajenas.
85:   v_tarea:=md5(v_clave)::uuid;
86:   v_payload:=jsonb_build_object('version',1,'lead_id',p_lead_id,'tarea_id',v_tarea,
87:     'resultado_reunion',p_resultado_reunion,'detalle',nullif(btrim(p_detalle),''),
88:     'siguiente',p_siguiente,'capital_estimado',p_capital_estimado,'moneda',p_moneda,
89:     'ubicacion',btrim(p_ubicacion));
90:   v_hash:=private.idem_hash(v_payload);
91:   perform pg_advisory_xact_lock(hashtextextended(v_clave,0));
92:   select * into strict v_lead from crm.leads where id=p_lead_id for update;
93:   if private.sla_gestion_permitida(v_actor,p_lead_id) is distinct from true then
94:     raise exception 'El lead cambio de responsable; recarga la ficha' using errcode='42501';
95:   end if;
96:   v_respuesta:=private.idem_leer(v_clave,v_hash);
97:   if v_respuesta is not null then return v_respuesta;end if;
98:   if v_lead.etapa in ('convertido','descartado') then
99:     raise exception 'El lead esta cerrado: no admite una visita nueva' using errcode='22023';
100:   end if;
101:   if v_lead.vendedor_id is null then
102:     raise exception 'Asigna un analista antes de registrar la visita' using errcode='22023';
103:   end if;
104:   if v_lead.no_contactar or private.persona_vetada(p_lead_id) then
105:     raise exception 'La persona tiene la restriccion No insistir' using errcode='P0429';
106:   end if;
107:
108:   -- El recibo pendiente no se confirma separado del cierre. Todo revierte si
109:   -- falla el capital, la siguiente acción, un permiso o cualquier trigger.
110:   perform private.idem_guardar(v_clave,'recorrido_oficina',v_hash,null,v_actor);
111:   insert into crm.tareas(id,lead_id,tipo,titulo,vence_en,modalidad_reunion,ubicacion_reunion,creado_por)
112:     values(v_tarea,p_lead_id,'reunion','Atencion en oficina',clock_timestamp(),'presencial',btrim(p_ubicacion),v_actor);
113:   perform set_config('crm.recorrido_oficina',jsonb_build_object(
114:     'clave',v_clave,'operacion_id',p_operacion_id,'payload',v_payload)::text,true);
115:   -- El ID interno es del servidor: no puede colisionar con un comando SLA
116:   -- elegido por el llamador que espere el lead en el orden inverso.
117:   v_cierre:=gen_random_uuid();
118:   v_respuesta:=crm.cerrar_reunion_v3(v_cierre,v_tarea,'completada',p_resultado_reunion,
119:     null,nullif(btrim(p_detalle),''),p_siguiente,p_capital_estimado,p_moneda);
120:   perform set_config('crm.recorrido_oficina',v_anterior,true);
121:   if coalesce((v_respuesta->>'ok')::boolean,false) is not true then
122:     raise exception 'El servidor no confirmo la entrevista' using errcode='23514';
123:   end if;
124:   v_respuesta:=v_respuesta||jsonb_build_object('version',1,'operacion_id',p_operacion_id,
125:     'comando','recorrido_atender_oficina','origen','oficina','ciclo_n',v_lead.ciclo_actual);
126:   perform private.idem_guardar(v_clave,'recorrido_oficina',v_hash,v_respuesta,v_actor);
127:   return v_respuesta;
128: end $$;
129:
130: revoke all on function private.recorrido_capturar_actividad() from public,anon,authenticated,service_role;
131: revoke all on function crm.recorrido_atender_oficina_fn(uuid,uuid,text,text,jsonb,numeric,text,text) from public,anon,service_role;
132: grant execute on function crm.recorrido_atender_oficina_fn(uuid,uuid,text,text,jsonb,numeric,text,text) to authenticated;
133: comment on function crm.recorrido_atender_oficina_fn(uuid,uuid,text,text,jsonb,numeric,text,text)
134:   is 'Confirma visita presencial real y entrevista en una transaccion. Cita con hora del servidor; cierre v3 y siguiente accion existentes. Replay por actor/operacion con hash integro. No convierte ni modifica el modo del recorrido.';
135: select private.assert_sla_nucleo();
136: commit;

FILE supabase/migrations/20261019001700_crm_recorrido_conversion.sql
1: -- Primera conversión por hechos. Instala defensas; no cambia el modo ni el corte.
2: begin;
3: set local search_path='';
4: set local quote_all_identifiers=off;
5:
6: do $$
7: declare r record;
8: begin
9:   for r in select * from (values
10:     ('crm.preparar_persona_lead_inversion_fn(uuid,text,text,text)','b40dded8a923dcd02f028b24bc4de94e'),
11:     ('crm.confirmar_inversion_revisada_fn(uuid,integer)','68828d0a443160310a3fb2fd82cd7041'),
12:     ('crm.acceso_inversion_fn(uuid,text,jsonb)','38229cbb9fde4d9b5e23ee55ca6e6784'),
13:     ('private.conversion_lead_con_inversion()','0edf5180578781961aacbf0e78df242e')
14:   ) as expected(firma,huella) loop
15:     if to_regprocedure(r.firma) is null or md5(pg_get_functiondef(to_regprocedure(r.firma)))<>r.huella then
16:       raise exception 'El contrato vivo cambió: revisar % antes de instalar recorrido',r.firma;
17:     end if;
18:   end loop;
19:   perform private.assert_sla_nucleo();
20: end $$;
21:
22: alter table crm.inversion_solicitudes add column recorrido_confirmado jsonb
23:   check (recorrido_confirmado is null or jsonb_typeof(recorrido_confirmado)='object');
24: comment on column crm.inversion_solicitudes.recorrido_confirmado is
25:   'Hechos y revisión de la regla al confirmar la primera conversión. Referencias sin PII, calculadas por trigger e inmutables. No backfill histórico.';
26:
27: create function private.recorrido_exigir(p_lead uuid,p_paso text) returns jsonb
28: language plpgsql volatile security definer set search_path='' as $$
29: declare v_l crm.leads%rowtype;v_c crm.recorrido_control%rowtype;v_r jsonb;v_exigible boolean;
30:   v_tarea uuid;v_asistencia uuid;
31: begin
32:   -- Las operaciones de clientes existentes conservan el contexto canónico actual.
33:   if p_lead is null then return null;end if;
34:   if current_setting('transaction_isolation')<>'read committed' then
35:     raise exception 'Reintenta la operación en una transacción de lectura vigente' using errcode='55000';
36:   end if;
37:   -- Los callers conservan autorización/identidad. NOWAIT evita invertir esperas
38:   -- con las rutas que llegaron por otra fila. El snapshot se toma DESPUÉS.
39:   select * into strict v_l from crm.leads where id=p_lead for update nowait;
40:   if v_l.activo is not true or v_l.etapa in ('convertido','descartado') then
41:     raise exception 'El lead no está disponible para una primera conversión' using errcode='P0409';end if;
42:   select * into strict v_c from crm.recorrido_control where id for share;
43:   select resultado into strict v_r from private.recorrido_evaluar(array[p_lead]);
44:   v_exigible:=coalesce(v_c.modo='exigir'
45:     and (v_r->>'ciclo_inicio')::timestamptz>=v_c.cohorte_desde
46:     and (v_r->>'aplica')::boolean,false);
47:   if v_exigible and not coalesce((v_r->>'habilita_conversion')::boolean,false) then
48:     raise exception using errcode='P0409',
49:       message='Antes de convertir, registra que asistió a su cita y que la entrevista se realizó, con su resultado. Revisa los pasos en la ficha del lead.',
50:       detail=jsonb_build_object('regla','recorrido_lead','paso',p_paso,'lead_id',p_lead,
51:         'ciclo_n',v_l.ciclo_actual,'pendiente',v_r->>'pendiente','revision',v_c.revision)::text;
52:   end if;
53:   -- Fotografía de LA pareja que acreditó la entrevista, no la última asistencia
54:   -- de otra cita del mismo lead. En observación puede quedar incompleta.
55:   v_tarea:=coalesce((v_r#>>'{evidencias,entrevista_tarea_id}')::uuid,
56:     (v_r#>>'{evidencias,asistencia_tarea_id}')::uuid);
57:   if v_tarea is not null then
58:     select resultado_actividad_id into v_asistencia from crm.tareas where id=v_tarea and lead_id=p_lead;
59:   end if;
60:   return jsonb_build_object('version',1,'lead_id',p_lead,'ciclo_n',v_l.ciclo_actual,
61:     'ciclo_inicio',v_r->'ciclo_inicio','modo',v_c.modo,'revision',v_c.revision,
62:     'cohorte_desde',v_c.cohorte_desde,'exigible',v_exigible,'estado',v_r->>'estado',
63:     'verificado_en',clock_timestamp(),'asistencia_tarea_id',v_tarea,'asistencia_id',v_asistencia,
64:     'entrevista_tarea_id',v_r#>'{evidencias,entrevista_tarea_id}');
65: end $$;
66:
67: create function private.recorrido_solicitud_guard() returns trigger
68: language plpgsql security definer set search_path='' as $$
69: begin
70:   if tg_op='INSERT' then
71:     if new.recorrido_confirmado is not null then
72:       raise exception 'El recorrido confirmado lo registra el servidor' using errcode='42501';end if;
73:     if new.lead_origen_id is not null then
74:       if new.estado='confirmada' then
75:         raise exception 'Prepara y confirma la inversión por su flujo de registro' using errcode='P0409';end if;
76:       if new.estado='preparada' then perform private.recorrido_exigir(new.lead_origen_id,'preparar_solicitud');end if;
77:     end if;
78:   else
79:     if new.recorrido_confirmado is distinct from old.recorrido_confirmado then
80:       raise exception 'La evidencia de conversión confirmada es inmutable' using errcode='42501';end if;
81:     if old.estado<>'confirmada' and new.estado='confirmada' and new.lead_origen_id is not null then
82:       new.recorrido_confirmado:=private.recorrido_exigir(new.lead_origen_id,'confirmar_solicitud');
83:     end if;
84:   end if;
85:   return new;
86: end $$;
87: create trigger trg_solicitudes_recorrido before insert or update on crm.inversion_solicitudes
88:   for each row execute function private.recorrido_solicitud_guard();
89:
90: create function private.recorrido_insert_convertido_guard() returns trigger
91: language plpgsql security definer set search_path='' as $$
92: declare v_c crm.recorrido_control%rowtype;
93: begin
94:   select * into strict v_c from crm.recorrido_control where id for share;
95:   -- guard_tenencia ya fijó creado_en con reloj servidor. Un INSERT no puede
96:   -- tener una asistencia previa vinculada a su nuevo ciclo.
97:   if v_c.modo='exigir' and new.creado_en>=v_c.cohorte_desde then
98:     raise exception 'Registra primero el lead, su asistencia y entrevista; después confirma la inversión'
99:       using errcode='P0409';
100:   end if;
101:   return new;
102: end $$;
103: create trigger trg_leads_zzzz_recorrido_insert before insert on crm.leads
104:   for each row when (new.etapa='convertido') execute function private.recorrido_insert_convertido_guard();
105:
106: revoke all on function private.recorrido_exigir(uuid,text),private.recorrido_solicitud_guard(),
107:   private.recorrido_insert_convertido_guard() from public,anon,authenticated,service_role;
108:
109: -- A continuación, cuerpos vigentes íntegros con una llamada puntual al guard.
110:
111: CREATE OR REPLACE FUNCTION crm.preparar_persona_lead_inversion_fn(p_lead uuid, p_tipo_documento text, p_documento text, p_nombre text)
112:  RETURNS jsonb
113:  LANGUAGE plpgsql
114:  SECURITY DEFINER
115:  SET search_path TO ''
116:  SET lock_timeout TO '5s'
117: AS $function$
118: declare
119:   v_uid uuid:=(select auth.uid()); v_rol text;
120:   v_l crm.leads%rowtype; v_pre crm.leads%rowtype; v_i crm.inversionistas%rowtype;
121:   v_persona uuid; v_doc text:=upper(btrim(p_documento));
122:   v_config text:=coalesce(current_setting('crm.op_privilegiada',true),'off');
123: begin
124:   if v_uid is null or not private.puede_gestionar_contratos_crm() then
125:     raise exception 'No autorizado para convertir leads' using errcode='42501';
126:   end if;
127:   if not private.resolver_en_puertas_bajo_candado() or not private.inversiones_escritura_bajo_candado() then
128:     raise exception 'El registro compartido de inversiones no está habilitado' using errcode='P0409';
129:   end if;
130:   perform pg_advisory_xact_lock_shared(hashtextextended('crm.equipo.usuarios_jerarquia',0));
131:   v_rol:=private.rol_crm(v_uid);
132:   select * into v_pre from crm.leads where id=p_lead and activo and
133:     (v_rol='gerencia' or vendedor_id in (select private.vendedor_ids_visibles(v_uid)));
134:   if not found then raise exception 'Lead no encontrado o fuera de tu ámbito' using errcode='42501'; end if;
135:   if length(btrim(coalesce(p_nombre,''))) not between 2 and 180
136:     or p_tipo_documento is null or p_tipo_documento not in ('DNI','CE','PASAPORTE')
137:     or v_doc is null
138:     or (p_tipo_documento='DNI' and v_doc !~ '^[0-9]{8}$')
139:     or (p_tipo_documento='CE' and v_doc !~ '^[0-9]{9,12}$')
140:     or (p_tipo_documento='PASAPORTE' and v_doc !~ '^[A-Z0-9]{6,12}$') then
141:     raise exception 'Completa el nombre y un documento válido' using errcode='22023';
142:   end if;
143:   -- La identidad no se corrige al invertir. Esa operación tiene su propia puerta.
144:   if nullif(btrim(v_pre.dni),'') is not null and v_pre.dni is distinct from v_doc then
145:     raise exception 'El documento no coincide con el lead; corrige su identidad antes de invertir' using errcode='P0409';
146:   end if;
147:   perform private.identidad_bloquear_documento(p_tipo_documento,v_doc);
148:   v_persona:=private.inversionista_resolver(p_tipo_documento,v_doc,true,'conversion_inversion');
149:   perform private.identidad_bloquear_documentos_de(array[v_persona]);
150:   select * into v_i from crm.inversionistas where id=v_persona for update;
151:   -- NOWAIT: una reasignación que tomó antes el lead no invierte el orden de locks.
152:   select * into v_l from crm.leads where id=p_lead for update nowait;
153:   if v_l.activo is not true or not coalesce((v_rol='gerencia' or
154:     v_l.vendedor_id in (select private.vendedor_ids_visibles(v_uid))),false) then
155:     raise exception 'Lead no encontrado o fuera de tu ámbito' using errcode='42501';
156:   end if;
157:   if v_l.dni is distinct from v_pre.dni or v_l.inversionista_id is distinct from v_pre.inversionista_id then
158:     raise exception 'La identidad del lead cambió; vuelve a cargarlo' using errcode='PT409';
159:   end if;
160:   -- También recupera una confirmación cuyo HTTP se perdió: no se vuelve a
161:   -- preparar ni se modifica la persona o el lead ya convertido.
162:   if v_l.etapa='convertido' and v_l.inversionista_id=v_persona and exists(
163:     select 1 from crm.inversion_solicitudes where lead_origen_id=p_lead and estado='confirmada') then
164:     perform private.inversion_persona_autorizada(v_persona);
165:     return jsonb_build_object('inversionista_id',v_persona,'lead_id',p_lead,
166:       'solicitud_id',(select id from crm.inversion_solicitudes where lead_origen_id=p_lead and estado='confirmada'));
167:   end if;
168:   if v_l.etapa in ('convertido','descartado') then
169:     raise exception 'El lead ya está cerrado; consulta su inversión en Cartera' using errcode='P0409';
170:   end if;
171:   perform private.recorrido_exigir(p_lead,'preparar_identidad');
172:   if v_i.estado<>'activo' or v_i.no_contactar then
173:     raise exception 'La persona no permite nuevas inversiones' using errcode='P0429';
174:   end if;
175:   if v_l.no_contactar then raise exception 'El lead tiene No insistir' using errcode='P0429'; end if;
176:   if v_l.vendedor_id is null or not exists(select 1 from crm.equipo e join public.perfiles p on p.id=e.perfil_id
177:     where e.perfil_id=v_l.vendedor_id and e.activo and p.activo and e.rol_crm in ('vendedor','supervisor')) then
178:     raise exception 'Asigna el lead a un analista activo antes de invertir' using errcode='P0409';
179:   end if;
180:   if (v_l.inversionista_id is not null and v_l.inversionista_id is distinct from v_persona)
181:     or exists(select 1 from crm.inversionista_leads il where il.lead_id=p_lead
182:       and private.inversionista_canonica(il.inversionista_id) is distinct from v_persona)
183:     or exists(select 1 from private.leads_de_personas(array[v_persona]) x where x<>p_lead)
184:     or exists(select 1 from private.leads_de_identidades(array[v_persona]) x where x<>p_lead) then
185:     raise exception 'Esta persona ya tiene otra identidad o lead; requiere conciliación' using errcode='P0409';
186:   end if;
187:   if v_i.responsable_relacion_id is not null and v_i.responsable_relacion_id<>v_l.vendedor_id then
188:     raise exception 'El responsable de la persona y el analista del lead deben coincidir antes de invertir' using errcode='P0409';
189:   end if;
190:   if exists(select 1 from crm.conversion_reservas r where
191:     (r.lead_id=p_lead or r.inversionista_id=v_persona) and
192:     (r.efectos_iniciados_en is not null or r.expira_en>now()) for update) then
193:     raise exception 'Hay una conversión anterior pendiente; revisa su acceso antes de iniciar otra solicitud' using errcode='P0409';
194:   end if;
195:   if v_i.responsable_relacion_id is null then
196:     if exists(select 1 from crm.inversionista_responsables where inversionista_id=v_persona and hasta is null) then
197:       raise exception 'La asignación de la persona requiere conciliación' using errcode='P0409';
198:     end if;
199:     insert into crm.inversionista_responsables(inversionista_id,responsable_id,motivo,por)
200:       values(v_persona,v_l.vendedor_id,'preparar_conversion_inversion',v_uid);
201:     update crm.inversionistas set responsable_relacion_id=v_l.vendedor_id where id=v_persona;
202:   end if;
203:   perform set_config('crm.op_privilegiada','on',true);
204:   update crm.leads set inversionista_id=v_persona,nombre_completo=btrim(p_nombre),
205:     dni=case when p_tipo_documento='DNI' then v_doc else dni end where id=p_lead;
206:   perform set_config('crm.op_privilegiada',v_config,true);
207:   -- Además aplica las banderas/membresía de F4 y el ámbito canónico de Cartera.
208:   perform private.inversion_persona_contexto(v_persona,p_lead);
209:   return jsonb_build_object('inversionista_id',v_persona,'lead_id',p_lead,
210:     'solicitud_id',(select id from crm.inversion_solicitudes where lead_origen_id=p_lead
211:       and estado in ('preparada','confirmada')));
212: end $function$;
213:
214:
215: CREATE OR REPLACE FUNCTION crm.confirmar_inversion_revisada_fn(p_solicitud uuid, p_revision_datos_esperada integer)
216:  RETURNS jsonb
217:  LANGUAGE plpgsql
218:  SECURITY DEFINER
219:  SET search_path TO ''
220:  SET lock_timeout TO '5s'
221: AS $function$begin
222:
223: declare
224:   v_uid uuid := (select auth.uid());
225:   v_persona uuid;
226:   v_origen uuid;
227:   v_ctx jsonb;
228:   v_s crm.inversion_solicitudes%rowtype;
229:   v_e crm.empresas%rowtype;
230:   v_obj storage.objects%rowtype;
231:   v_cierre uuid;
232:   v_contrato uuid;
233:   v_inversion uuid;
234:   v_fecha date;
235:   v_imputacion date;
236:   v_periodo date;
237:   v_ahora timestamptz := statement_timestamp();
238:   v_ajuste boolean := false;
239:   v_fuente jsonb;
240:   v_payload_contrato jsonb;
241:   v_condicion uuid;
242:   v_config_producto text := current_setting('crm.producto_condicion_id',true);
243:   v_responsable_inicial uuid;
244:   v_res jsonb;
245:   v_config_conversion text:=coalesce(current_setting('crm.op_privilegiada',true),'off');
246: begin
247:   if v_uid is null or not private.puede_gestionar_contratos_crm() then
248:     raise exception 'No autorizado para registrar inversiones' using errcode='42501';
249:   end if;
250:   select inversionista_id into v_persona from crm.inversion_solicitudes where id=p_solicitud;
251:   if not found then raise exception 'Solicitud no encontrada' using errcode='P0002'; end if;
252:   v_origen := v_persona;
253:   v_ctx := private.inversion_persona_autorizada_para(v_persona,p_solicitud,null::uuid);
254:   perform private.venta_cruzada_exigir_operador(p_solicitud);
255:   v_persona := (v_ctx->>'inversionista_id')::uuid;
256:   select * into v_s from crm.inversion_solicitudes where id=p_solicitud for update;
257:   if not found or v_s.inversionista_id is distinct from v_origen then
258:     raise exception 'La solicitud cambió; vuelve a cargarla' using errcode='PT409';
259:   end if;
260:   if v_s.estado='confirmada' then
261:     v_res:=v_s.resultado;
262:     select contrato_id into v_contrato from crm.inversiones where id=v_s.inversion_id;
263:     if v_contrato is not null then
264:       if private.contrato_en_eliminacion(v_contrato) then
265:         raise exception 'El contrato está en proceso de eliminación; requiere revisión' using errcode='55000';
266:       end if;
267:       v_res:=jsonb_set(v_res,'{fuente,pdf}',private.contrato_pdf_estado_base(v_contrato));
268:     end if;
269:     return v_res||jsonb_build_object('inversionista_id',v_persona,'reintento',true);
270:   end if;
271:   if v_s.estado<>'preparada' then raise exception 'La solicitud está cancelada' using errcode='P0409'; end if;
272:   if p_revision_datos_esperada is distinct from v_s.revision_datos then
273:     raise exception 'Los datos cambiaron; revisa la versión vigente antes de confirmar' using errcode='PT409';
274:   end if;
275:   v_ctx := private.inversion_persona_contexto_para(v_persona,v_s.lead_origen_id,p_solicitud,null::uuid);
276:   -- Confirmadas devolvieron arriba su recibo. Antes de cualquier hecho financiero,
277:   -- lectura nueva bajo los candados existentes; no confía en el borrador.
278:   perform private.recorrido_exigir(v_s.lead_origen_id,'confirmar_inversion');
279:   if v_s.puerta='cliente_existente' then
280:     -- Venta cruzada: la venta es del analista congelado y no depende del responsable (D7),
281:     -- pero ese analista tiene que seguir activo para cerrarla.
282:     if not coalesce(private.rol_crm(v_s.analista_cierre_id) in ('vendedor','supervisor'),false) then
283:       raise exception 'El analista de esta venta ya no está activo como vendedor o supervisor; cancela la solicitud y regístrala de nuevo' using errcode='P0409';
284:     end if;
285:     v_ctx := v_ctx||jsonb_build_object('analista_cierre_id',v_s.analista_cierre_id,'puerta',v_s.puerta);
286:   elsif v_s.responsable_esperado_id is distinct from (v_ctx->>'responsable_id')::uuid then
287:     raise exception 'El responsable cambió; revisa esta misma solicitud antes de confirmarla' using errcode='P0409';
288:   end if;
289:   select * into v_e from crm.empresas where id=v_s.empresa_id and activa for share;
290:   if not found then raise exception 'La empresa ya no está disponible para nuevas inversiones' using errcode='P0409'; end if;
291:   if v_e.fuente_capital='cierres_externos' then
292:     -- Se revalida contra el catálogo VIVO: una solicitud preparada cuando la
293:     -- cooperativa admitía una moneda no se confirma si entretanto se retiró.
294:     -- `coalesce` por el mismo motivo que en private.inversion_validar_datos.
295:     if v_s.datos->>'moneda' is null
296:        or not (v_s.datos->>'moneda'=any(coalesce(v_e.monedas,'{}'::text[]))) then
297:       raise exception 'La moneda ya no está admitida por la cooperativa' using errcode='P0409';
298:     end if;
299:     -- Revalida el contenido guardado, también al retomar una solicitud anterior.
300:     perform private.inversion_validar_datos(v_s.id,v_s.datos,v_ctx);
301:     select * into v_obj from storage.objects
302:     where bucket_id='f4-comprobantes' and name=v_s.datos#>>'{evidencia,ruta}' for key share;
303:     if not found or coalesce((v_obj.metadata->>'size')::bigint,0) not between 1 and 10485760
304:        or coalesce(v_obj.metadata->>'mimetype','') not in ('application/pdf','image/jpeg','image/png') then
305:       raise exception 'Sube el comprobante válido antes de confirmar la inversión' using errcode='P0409';
306:     end if;
307:     v_fecha := (v_s.datos->>'fecha_comercial')::date;
308:     v_periodo := date_trunc('month',v_fecha)::date;
309:     -- Mismo candado que el sello mensual. El sello no puede aparecer entre la
310:     -- decisión y el alta. Un mes sellado recibe un hecho posterior trazable.
311:     perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados'),
312:       (v_periodo-date '2000-01-01')::integer);
313:     v_ajuste := exists(select 1 from crm.periodos_cerrados where periodo=v_periodo);
314:     v_imputacion := case when v_ajuste then (v_ahora at time zone 'America/Lima')::date else v_fecha end;
315:     if v_ajuste then
316:       perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('crm.periodos_cerrados'),
317:         (date_trunc('month',v_imputacion)::date-date '2000-01-01')::integer);
318:       if exists(select 1 from crm.periodos_cerrados where periodo=date_trunc('month',v_imputacion)::date) then
319:         raise exception 'El período de registro también está sellado; corresponde revisión de Gerencia' using errcode='P0409';
320:       end if;
321:     end if;
322:     begin
323:       insert into crm.cierres_externos(lead_id,cooperativa,monto,moneda,documento_tipo,documento,
324:         nombre_completo,numero_transaccion,referencia_externa,vence_en,vendedor_id,creado_por,
325:         inversionista_id,creado_en,es_cierre_inicial,fecha_comercial,fecha_imputacion,comprobante_objeto_id,
326:         plazo_meses,tasa_anual)
327:       values((v_ctx->>'lead_id')::uuid,v_e.clave,(v_s.datos->>'monto')::numeric,v_s.datos->>'moneda',
328:         v_ctx->>'documento_tipo',v_ctx->>'documento',v_ctx->>'nombre',
329:         upper(btrim(v_s.datos->>'numero_transaccion')),btrim(v_s.datos->>'referencia'),
330:         (v_s.datos->>'vence_en')::date,coalesce(v_s.analista_cierre_id,(v_ctx->>'responsable_id')::uuid),v_uid,v_persona,
331:         v_ahora,v_s.lead_origen_id is not null,v_fecha,v_imputacion,v_obj.id,
332:         (v_s.datos->>'plazo_meses')::integer,(v_s.datos->>'tasa_anual')::numeric) returning id into v_cierre;
333:       -- La reclamación histórica del depósito es global para ambas cooperativas.
334:       insert into crm.depositos_reclamados(numero_norm,cierre_id,reclamado_por)
335:       values(upper(btrim(v_s.datos->>'numero_transaccion')),v_cierre,v_uid);
336:     exception when unique_violation then
337:       raise exception 'Ese número de operación del depósito ya está registrado' using errcode='P0409';
338:     end;
339:     v_fuente:=jsonb_build_object('cierre_id',v_cierre,'fecha_comercial',v_fecha,
340:       'fecha_imputacion',v_imputacion,'ajuste_mes_cerrado',v_ajuste,
341:       'plazo_meses',(v_s.datos->>'plazo_meses')::integer,'tasa_anual',(v_s.datos->>'tasa_anual')::numeric,
342:       'vence_en',(v_s.datos->>'vence_en')::date);
343:   elsif v_e.clave='avance' then
344:     if v_ctx->>'perfil_id' is null then
345:       raise exception 'Completa el acceso Avance de esta persona y vuelve a confirmar la misma solicitud' using errcode='P0409';
346:     end if;
347:     v_payload_contrato := v_s.datos->'contrato';
348:     if v_s.puerta='cliente_existente' and coalesce(v_payload_contrato->>'categoria','nuevo') not in ('nuevo','upgrade') then
349:       raise exception 'La venta cruzada registra una inversión nueva o un upgrade; la renovación es del responsable' using errcode='22023';
350:     end if;
351:     if v_s.lead_origen_id is not null then
352:       if coalesce(v_payload_contrato->>'categoria','nuevo')<>'nuevo' then
353:         raise exception 'La conversión inicial registra una inversión nueva' using errcode='22023';
354:       end if;
355:       perform private.validar_tasa_conversion_lead(v_s.lead_origen_id,(v_ctx->>'perfil_id')::uuid,v_payload_contrato);
356:       perform private.enlazar_tasa_lead(v_s.lead_origen_id,(v_ctx->>'perfil_id')::uuid);
357:     end if;
358:     select r.responsable_anterior_id into v_responsable_inicial
359:       from crm.inversion_solicitud_revisiones r where r.solicitud_id=v_s.id order by r.revision limit 1;
360:     v_responsable_inicial:=coalesce(v_responsable_inicial,v_s.responsable_esperado_id);
361:     if v_payload_contrato->>'cliente_id' is not null
362:        and v_payload_contrato->>'cliente_id' is distinct from v_ctx->>'perfil_id' then
363:       raise exception 'El contrato no corresponde a esta persona' using errcode='P0409';
364:     end if;
365:     if v_payload_contrato->>'analista_cierre_id' is not null
366:        and v_payload_contrato->>'analista_cierre_id' is distinct from coalesce(v_s.analista_cierre_id,v_responsable_inicial)::text then
367:       raise exception 'El analista del contenido original no corresponde al responsable con que se preparó la inversión' using errcode='P0409';
368:     end if;
369:     -- El contenido original conserva su huella. Una revisión explícita cambia
370:     -- el responsable con quien se confirma, sin reescribir las condiciones.
371:     v_payload_contrato := v_payload_contrato||jsonb_build_object('cliente_id',v_ctx->>'perfil_id',
372:       'analista_cierre_id',coalesce(v_s.analista_cierre_id::text,v_ctx->>'responsable_id'));
373:     -- La fuente existente conserva producto, tasa, cronograma, cuenta, titularidad
374:     -- documental y operaciones de cartera. Todo participa de esta transacción.
375:     -- Reutiliza además la reserva y el snapshot documentales del alta publicada.
376:     -- Un PDF pendiente no vuelve a crear el contrato cuando se recupera el envío.
377:     -- El flujo Avance vigente es libre y fotografía sus términos. El catálogo
378:     -- sigue siendo opcional: F4 no lo convierte en un requisito comercial nuevo.
379:     perform pg_catalog.set_config('crm.producto_condicion_id',
380:       coalesce((nullif(v_s.datos->>'producto_condicion_id','')::uuid)::text,''),true);
381:     -- Venta cruzada: el alta Avance puede crear el PDF de ESTE contrato aunque el cliente
382:     -- no sea de la cartera de quien confirma (private.venta_cruzada_confirma_contrato).
383:     perform pg_catalog.set_config('crm.venta_cruzada_solicitud',case when v_s.puerta='cliente_existente' then v_s.id::text else '' end,true);
384:     begin
385:       v_fuente := crm.crear_contrato_con_cuenta_pdf_v2(
386:         v_payload_contrato||jsonb_build_object('clave_idempotencia',v_s.id),
387:         v_s.datos->'cronograma',v_s.datos->'cuenta');
388:     exception when others then
389:       perform pg_catalog.set_config('crm.producto_condicion_id',coalesce(v_config_producto,''),true);
390:       perform pg_catalog.set_config('crm.venta_cruzada_solicitud','',true);
391:       raise;
392:     end;
393:     perform pg_catalog.set_config('crm.producto_condicion_id',coalesce(v_config_producto,''),true);
394:     perform pg_catalog.set_config('crm.venta_cruzada_solicitud','',true);
395:     v_contrato := (v_fuente->>'id')::uuid;
396:     if v_contrato is null then raise exception 'El contrato no devolvió su identificador' using errcode='P0001'; end if;
397:     select producto_condicion_id into v_condicion from public.contratos where id=v_contrato;
398:     v_fuente:=v_fuente||private.metadata_condicion_producto(v_condicion);
399:   else
400:     raise exception 'Empresa sin puerta de inversión disponible' using errcode='P0409';
401:   end if;
402:   v_inversion := private.inversion_vincular_fuente(v_persona,v_contrato,v_cierre,v_uid,v_s.lead_origen_id is not null);
403:   if v_ajuste then
404:     insert into crm.inversion_ajustes_mes_cerrado(inversion_id,periodo_origen,fecha_imputacion,creado_por)
405:     values(v_inversion,v_periodo,v_imputacion,v_uid);
406:   end if;
407:   insert into crm.inversion_eventos(inversion_id,tipo,creado_por) values(v_inversion,'registro',v_uid);
408:   v_res := jsonb_build_object('ok',true,'solicitud_id',v_s.id,'inversion_id',v_inversion,
409:     'inversionista_id',v_persona,'lead_id',v_ctx->>'lead_id','empresa',v_e.clave,'fuente',v_fuente,
410:     'revision_datos',v_s.revision_datos);
411:   if v_s.puerta='cliente_existente' then
412:     v_res := v_res||jsonb_build_object('puerta',v_s.puerta,'analista_cierre_id',v_s.analista_cierre_id);
413:   end if;
414:   update crm.inversion_solicitudes set estado='confirmada',inversion_id=v_inversion,
415:     resultado=v_res,confirmado_por=v_uid,actualizado_en=statement_timestamp() where id=v_s.id;
416:   if v_s.lead_origen_id is not null then
417:     -- El escritor contractual puede haber enlazado ya su fuente; se reconoce
418:     -- ESTA inversión como inicial, conservando un único hecho y titular.
419:     update crm.inversiones set es_primera_conversion=true where id=v_inversion;
420:     perform set_config('crm.op_privilegiada','on',true);
421:     update crm.leads set etapa='convertido',convertido_en=statement_timestamp(),
422:       perfil_id=case when v_e.clave='avance' then (v_ctx->>'perfil_id')::uuid else perfil_id end,
423:       contrato_id=coalesce(v_contrato,contrato_id)
424:       where id=v_s.lead_origen_id;
425:     perform set_config('crm.op_privilegiada',v_config_conversion,true);
426:     insert into crm.actividades(lead_id,tipo,detalle,metadata,creado_por)
427:       values(v_s.lead_origen_id,'conversion','Convertido al confirmar su inversión',
428:         jsonb_build_object('solicitud_id',v_s.id,'inversion_id',v_inversion,'empresa',v_e.clave,
429:           'contrato_id',v_contrato,'cierre_externo_id',v_cierre),v_uid);
430:     if v_e.clave='avance' and v_s.auth_claim_id is not null then
431:       update crm.inversion_solicitudes set bienvenida=jsonb_build_object(
432:         'estado','pendiente','correo',v_s.datos->'alta_portal'->>'correo',
433:         'nombre',v_s.datos->'alta_portal'->>'nombre_completo') where id=v_s.id;
434:     end if;
435:   end if;
436:   return v_res;
437: end;
438:
439: exception when serialization_failure or lock_not_available then
440:   if not exists(select 1 from crm.inversion_solicitud_origenes where solicitud_id=p_solicitud) then raise; end if;
441:   raise exception using errcode='PT409', message='La operación coincidió con otro cambio. Vuelve a intentarlo.';
442: end;
443: $function$;
444:
445:
446: CREATE OR REPLACE FUNCTION crm.acceso_inversion_fn(p_solicitud uuid, p_paso text, p_payload jsonb DEFAULT '{}'::jsonb)
447:  RETURNS jsonb
448:  LANGUAGE plpgsql
449:  SECURITY DEFINER
450:  SET search_path TO ''
451:  SET lock_timeout TO '5s'
452: AS $function$
453: declare
454:   v_persona uuid;
455:   v_origen uuid;
456:   v_ctx jsonb;
457:   v_s crm.inversion_solicitudes%rowtype;
458:   v_datos jsonb;
459:   v_auth_ctx jsonb;
460:   v_hash_payload jsonb;
461:   v_saga crm.multiempresa_idempotencia%rowtype;
462:   v_r jsonb;
463:   v_p public.perfiles%rowtype;
464:   v_auth uuid;
465:   v_version integer;
466:   v_token text;
467:   v_otras uuid[];
468: begin
469:   if p_solicitud is null or p_paso is null or p_paso not in ('reclamar','registrar_auth','crear_perfil','enlazar')
470:      or jsonb_typeof(p_payload) is distinct from 'object' then
471:     raise exception 'Solicitud o paso de acceso Avance inválido' using errcode='22023';
472:   end if;
473:   if exists(select 1 from jsonb_object_keys(p_payload) k where
474:     k<>'token' and not (p_paso<>'reclamar' and k='version')
475:     and not (p_paso='registrar_auth' and k='auth_user_id')) then
476:     raise exception 'El paso de acceso contiene campos no admitidos' using errcode='22023';
477:   end if;
478:   v_token:=p_payload->>'token';
479:   if v_token is not null and v_token !~ '^[a-f0-9]{48}$' then
480:     raise exception 'Token de recuperación inválido' using errcode='22023';
481:   end if;
482:   select inversionista_id into v_persona from crm.inversion_solicitudes where id=p_solicitud;
483:   v_origen:=v_persona;
484:   v_ctx:=private.inversion_persona_autorizada_para(v_persona,p_solicitud,null::uuid);
485:   perform private.venta_cruzada_exigir_operador(p_solicitud);
486:   v_persona:=(v_ctx->>'inversionista_id')::uuid;
487:   select * into v_s from crm.inversion_solicitudes where id=p_solicitud for update;
488:   if not found or v_s.inversionista_id is distinct from v_origen then
489:     raise exception 'La solicitud cambió; vuelve a cargarla' using errcode='40001';
490:   end if;
491:   if v_s.estado<>'confirmada' then
492:     v_ctx:=private.inversion_persona_contexto_para(v_persona,(select lead_origen_id from crm.inversion_solicitudes where id=p_solicitud),p_solicitud,null::uuid);
493:   end if;
494:   if not exists(select 1 from crm.empresas e where e.id=v_s.empresa_id and e.clave='avance' and e.activa)
495:      or v_s.estado='cancelada' then
496:     raise exception 'Esta solicitud no permite completar acceso Avance' using errcode='P0409';
497:   end if;
498:   if v_s.estado='preparada' and v_s.responsable_esperado_id is distinct from (v_ctx->>'responsable_id')::uuid then
499:     raise exception 'El responsable cambió; corresponde revisar esta solicitud antes de continuar' using errcode='P0409';
500:   end if;
501:
502:   -- Un claim terminal conserva su clave de origen después de una fusión.
503:   -- Los contextos anteriores a esta ampliación usaban la persona de la solicitud.
504:   select * into v_saga from crm.multiempresa_idempotencia where clave='auth_persona:'||
505:     case when v_s.auth_claim_id is null then v_persona::text
506:       else coalesce(v_s.auth_contexto->>'inversionista_id',v_origen::text) end;
507:   if v_s.auth_claim_id is not null and
508:     (v_saga.clave is null or v_saga.resultado->>'claim_id' is distinct from v_s.auth_claim_id::text) then
509:     raise exception 'El proceso de acceso original requiere conciliación' using errcode='P0409';
510:   end if;
511:   -- Un enlace concluido se devuelve aunque se perdiera su respuesta. No reinicia
512:   -- Auth ni reescribe el perfil, su clave o su responsable.
513:   if v_ctx->>'perfil_id' is not null and
514:      (v_saga.clave is null or v_saga.resultado->>'estado'='enlazado') then
515:     if v_saga.clave is not null and v_saga.resultado->>'perfil_id' is distinct from v_ctx->>'perfil_id' then
516:       raise exception 'El acceso y la identidad requieren conciliación' using errcode='P0409';
517:     end if;
518:     return jsonb_build_object('estado','enlazado','perfil_id',v_ctx->>'perfil_id',
519:       'inversionista_id',v_persona,'solicitud_id',v_s.id,'reanudar',true);
520:   end if;
521:   if v_s.estado='confirmada' then
522:     raise exception 'El acceso de la inversión confirmada requiere conciliación' using errcode='P0409';
523:   end if;
524:   v_datos:=private.inversion_datos_portal(v_s.datos->'alta_portal');
525:   v_auth_ctx:=coalesce(v_s.auth_contexto,jsonb_build_object('documento_tipo',v_ctx->>'documento_tipo',
526:     'documento',v_ctx->>'documento','responsable_id',v_ctx->>'responsable_id','inversionista_id',v_persona));
527:   if v_auth_ctx->>'documento_tipo' is distinct from v_ctx->>'documento_tipo'
528:      or v_auth_ctx->>'documento' is distinct from v_ctx->>'documento' then
529:     raise exception 'El documento cambió durante el alta; corresponde revisar el acceso pendiente' using errcode='P0409';
530:   end if;
531:   -- Misma proyección que alta_cliente_identidad_fn; los bancos pertenecen a la
532:   -- cuenta contractual de esta inversión. El responsable inicial fija la huella.
533:   v_hash_payload:=private.inversion_payload_acceso(v_persona,v_s.datos->'alta_portal',v_auth_ctx->>'responsable_id');
534:
535:   if p_paso='reclamar' then
536:     -- Cubre solicitudes anteriores al arreglo e importaciones sin actor. No
537:     -- cambia una credencial que Auth ya creó aunque se perdiera la respuesta.
538:     if v_s.lead_origen_id is not null and exists(select 1 from crm.leads l where l.id=v_s.lead_origen_id
539:       and private.inversion_correo_normalizado(l.correo) is distinct from private.inversion_correo_normalizado(v_datos->>'correo'))
540:       and v_saga.resultado->>'auth_insertado_id' is null
541:       and v_saga.resultado->>'auth_user_id' is null
542:       and not exists(select 1 from auth.users u where u.raw_app_meta_data->>'claim_id'=v_s.auth_claim_id::text) then
543:       raise exception 'El correo de la ficha cambió; revisa los datos de acceso antes de continuar' using errcode='P0409';
544:     end if;
545:     -- Una segunda solicitud no sustituye un alta pendiente de esta persona.
546:     -- Incluso "reclamado" puede tener Auth creado con respuesta perdida.
547:     if v_saga.clave is not null and v_saga.resultado->>'estado'<>'enlazado' then
548:       if exists(select 1 from crm.inversion_solicitudes s where s.id<>v_s.id
549:         and s.auth_claim_id=(v_saga.resultado->>'claim_id')::uuid) then
550:         raise exception 'Completa el acceso pendiente desde su solicitud original' using errcode='P0409';
551:       end if;
552:       if v_saga.hash_payload is distinct from private.idem_hash(v_hash_payload) then
553:         raise exception 'La persona tiene otro alta pendiente; recupera ese proceso con sus datos originales' using errcode='P0409';
554:       end if;
555:     end if;
556:     if v_saga.clave is null then
557:       select array_agg(p.id order by p.id) into v_otras from public.perfiles p
558:       where p.rol='cliente' and p.tipo_documento=v_ctx->>'documento_tipo'
559:         and upper(regexp_replace(coalesce(p.dni,''),'[^A-Za-z0-9]','','g'))=v_ctx->>'documento';
560:       if coalesce(cardinality(v_otras),0)>1 then
561:         raise exception 'Hay varios perfiles con ese documento; requiere conciliación' using errcode='P0409';
562:       elsif cardinality(v_otras)=1 then
563:         perform private.asegurar_identidad_perfil(v_otras[1],'f4_acceso_portal');
564:         v_ctx:=private.inversion_persona_contexto_para(v_persona,(select lead_origen_id from crm.inversion_solicitudes where id=p_solicitud),p_solicitud,null::uuid);
565:         if v_ctx->>'perfil_id' is distinct from v_otras[1]::text then
566:           raise exception 'El perfil existente no pertenece a esta persona' using errcode='P0409';
567:         end if;
568:         return jsonb_build_object('estado','enlazado','perfil_id',v_otras[1],
569:           'inversionista_id',v_persona,'solicitud_id',v_s.id,'reanudar',true);
570:       end if;
571:     end if;
572:     -- Un claim sin efecto externo no exime. Un Auth ya creado con la marca
573:     -- de ESTA solicitud se recupera sin repetir el alta; confirmar revalida.
574:     if v_s.lead_origen_id is not null and not exists(
575:       select 1 from auth.users u where v_s.auth_claim_id is not null
576:         and u.raw_app_meta_data->>'claim_id'=v_s.auth_claim_id::text
577:         and lower(u.email)=v_datos->>'correo') then
578:       perform private.recorrido_exigir(v_s.lead_origen_id,'crear_acceso');
579:     end if;
580:     v_r:=private.saga_auth_reclamar(v_persona,'alta_cliente',v_hash_payload,null,v_token);
581:     if v_r->>'estado'='enlazado' and (v_ctx->>'perfil_id' is null
582:        or v_r->>'perfil_id' is distinct from v_ctx->>'perfil_id') then
583:       raise exception 'El perfil del acceso requiere conciliación con esta persona' using errcode='P0409';
584:     end if;
585:     if v_s.auth_claim_id is not null and v_s.auth_claim_id is distinct from (v_r->>'claim_id')::uuid then
586:       raise exception 'El proceso de acceso cambió; requiere revisión' using errcode='P0409';
587:     end if;
588:     -- El formulario guarda su token ANTES del primer envío. La saga general
589:     -- emite otro token; aquí conservamos el ya conocido para poder recuperar
590:     -- también una respuesta perdida del primer reclamo (sin esperar el lease).
591:     -- saga_auth_reclamar ya verificó el token vigente al retomar. No se altera
592:     -- el claim, su versión, su dueño ni su huella; las otras puertas no cambian.
593:     if v_token is not null and v_r->>'estado'<>'enlazado' then
594:       update crm.multiempresa_idempotencia set resultado=jsonb_set(resultado,'{token_hash}',
595:         to_jsonb(private.saga_token_hash(v_token)))
596:         where clave='auth_persona:'||(v_r->>'inversionista_id') and resultado->>'claim_id'=v_r->>'claim_id';
597:       if not found then
598:         raise exception 'El proceso de acceso cambió; recupera la solicitud' using errcode='40001';
599:       end if;
600:       v_r:=jsonb_set(v_r,'{token}',to_jsonb(v_token));
601:     end if;
602:     update crm.inversion_solicitudes set auth_claim_id=(v_r->>'claim_id')::uuid,
603:       auth_contexto=v_auth_ctx,actualizado_en=statement_timestamp() where id=v_s.id;
604:     return v_r||jsonb_build_object('solicitud_id',v_s.id,'datos_portal',v_datos,
605:       'documento_tipo',v_auth_ctx->>'documento_tipo','documento',v_auth_ctx->>'documento');
606:   end if;
607:
608:   if v_s.auth_claim_id is null or v_saga.clave is null
609:      or v_saga.resultado->>'claim_id' is distinct from v_s.auth_claim_id::text then
610:     raise exception 'Primero reclama el acceso desde esta solicitud' using errcode='P0409';
611:   end if;
612:   -- El perfil y el avance de estado se confirman juntos. Una versión antigua
613:   -- no puede dejar un perfil insertado ni enlazarlo por fuera de su claim.
614:   select * into v_saga from crm.multiempresa_idempotencia where clave=v_saga.clave for update;
615:   if v_token is null or v_saga.resultado->>'token_hash' is distinct from private.saga_token_hash(v_token) then
616:     raise exception 'Token de recuperación inválido' using errcode='42501';
617:   end if;
618:   begin v_version:=(p_payload->>'version')::integer;
619:   exception when invalid_text_representation or numeric_value_out_of_range then
620:     raise exception 'Versión del acceso inválida' using errcode='22023';
621:   end;
622:   if v_version is null or v_saga.version is distinct from v_version then
623:     raise exception 'El acceso cambió; vuelve a reclamar con tu token' using errcode='40001';
624:   end if;
625:   if p_paso='registrar_auth' then
626:     begin v_auth:=(p_payload->>'auth_user_id')::uuid;
627:     exception when invalid_text_representation then
628:       raise exception 'Identificador de acceso inválido' using errcode='22023';
629:     end;
630:   else
631:     v_auth:=(v_saga.resultado->>'auth_user_id')::uuid;
632:   end if;
633:   if not exists(select 1 from auth.users u where u.id=v_auth
634:     and u.raw_app_meta_data->>'claim_id'=v_s.auth_claim_id::text
635:     and lower(u.email)=v_datos->>'correo') then
636:     raise exception 'El acceso no pertenece a esta solicitud o a su correo' using errcode='P0409';
637:   end if;
638:   if p_paso='registrar_auth' then
639:     return private.saga_auth_avanzar(v_s.auth_claim_id,v_token,'auth_creado',v_auth,null,v_version);
640:   end if;
641:   if v_saga.resultado->>'estado' not in ('auth_creado','perfil_creado') then
642:     raise exception 'El estado del acceso no permite este paso' using errcode='P0409';
643:   end if;
644:   select * into v_p from public.perfiles where id=v_auth for update;
645:   if not found and p_paso='crear_perfil' then
646:     insert into public.perfiles(id,rol,activo,nombre_completo,apellidos,nombres,tipo_documento,dni,
647:       correo,telefono,domicilio,asesor_perfil_id,creado_por,debe_cambiar_password)
648:     values(v_auth,'cliente',true,v_datos->>'nombre_completo',v_datos->>'apellidos',v_datos->>'nombres',
649:       v_auth_ctx->>'documento_tipo',v_auth_ctx->>'documento',v_datos->>'correo',v_datos->>'telefono',
650:       v_datos->>'domicilio',(v_ctx->>'responsable_id')::uuid,(select auth.uid()),true)
651:     returning * into v_p;
652:   end if;
653:   if v_p.id is null or v_p.rol<>'cliente' or v_p.activo is not true
654:      or v_p.tipo_documento is distinct from v_auth_ctx->>'documento_tipo'
655:      or v_p.dni is distinct from v_auth_ctx->>'documento'
656:      or lower(v_p.correo) is distinct from v_datos->>'correo'
657:      or v_p.asesor_perfil_id is distinct from (v_ctx->>'responsable_id')::uuid then
658:     raise exception 'El perfil pendiente requiere conciliación con esta persona y su responsable' using errcode='P0409';
659:   end if;
660:   if p_paso='crear_perfil' then
661:     return private.saga_auth_avanzar(v_s.auth_claim_id,v_token,'perfil_creado',null,v_auth,v_version);
662:   end if;
663:   v_r:=private.asegurar_identidad_perfil(v_auth,'f4_acceso_portal');
664:   if private.inversionista_canonica((v_r->>'inversionista_id')::uuid) is distinct from v_persona then
665:     raise exception 'El perfil no corresponde a la persona de la inversión' using errcode='P0409';
666:   end if;
667:   return private.saga_auth_avanzar(v_s.auth_claim_id,v_token,'enlazado',null,v_auth,v_version)
668:     ||jsonb_build_object('solicitud_id',v_s.id);
669: end;
670: $function$;
671:
672:
673: CREATE OR REPLACE FUNCTION private.conversion_lead_con_inversion()
674:  RETURNS trigger
675:  LANGUAGE plpgsql
676:  SECURITY DEFINER
677:  SET search_path TO ''
678: AS $function$
679: begin
680:   if new.etapa='convertido' and old.etapa<>'convertido' then
681:     if exists(select 1 from crm.inversion_solicitudes where lead_origen_id=new.id and estado='preparada') then
682:       raise exception 'Confirma la solicitud de inversión antes de convertir el lead' using errcode='P0409';
683:     end if;
684:     if not exists(select 1 from crm.inversion_solicitudes s join crm.inversiones i on i.id=s.inversion_id
685:       where s.lead_origen_id=new.id and s.estado='confirmada'
686:         and i.inversionista_id=new.inversionista_id and i.es_primera_conversion and i.estado='vigente') then
687:       raise exception 'Registra y confirma la inversión desde el formulario compartido antes de convertir' using errcode='P0409';
688:     end if;
689:     -- Última defensa también para writers internos; conserva la comprobación
690:     -- anterior de solicitud confirmada e inversión inicial vigente.
691:     perform private.recorrido_exigir(new.id,'convertir_lead');
692:   end if;
693:   return new;
694: end $function$;
695:
696:
697: notify pgrst,'reload schema';
698: commit;

FILE supabase/migrations/20261019001701_crm_recorrido_conversion_hardening.sql
1: begin;
2: set local search_path='';
3: do $$
4: declare v_firma text;v_oid oid;r record;
5: begin
6:   foreach v_firma in array array['private.recorrido_exigir(uuid,text)',
7:     'private.recorrido_solicitud_guard()','private.recorrido_insert_convertido_guard()'] loop
8:     v_oid:=to_regprocedure(v_firma);
9:     select * into strict r from pg_proc where oid=v_oid;
10:     if pg_get_userbyid(r.proowner)<>'postgres' or not r.prosecdef
11:       or not coalesce('search_path=""'=any(r.proconfig),false) then
12:       raise exception 'Owner, definer o search_path de recorrido incorrecto: %',v_firma;end if;
13:     if exists(select 1 from aclexplode(coalesce(r.proacl,acldefault('f',r.proowner))) a
14:       where a.privilege_type='EXECUTE' and (a.grantee=0 or a.grantee in
15:         (select oid from pg_roles where rolname in ('anon','authenticated','service_role')))) then
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
27:   end loop;
28:   if not (select relrowsecurity from pg_class where oid='crm.inversion_solicitudes'::regclass)
29:     or not exists(select 1 from pg_trigger where tgrelid='crm.inversion_solicitudes'::regclass
30:       and tgname='trg_audit_inversion_solicitudes' and tgenabled='O') then
31:     raise exception 'RLS o auditoría de solicitudes ausente';end if;
32:   if has_column_privilege('authenticated','crm.inversion_solicitudes','recorrido_confirmado','UPDATE')
33:     or has_column_privilege('anon','crm.inversion_solicitudes','recorrido_confirmado','UPDATE') then
34:     raise exception 'La evidencia confirmada no admite escritura directa de API';end if;
35:   perform private.assert_sla_nucleo();
36: end $$;
37: notify pgrst,'reload schema';
38: commit;

FILE supabase/scripts/recorrido-lead/test-conversion.sql
1: -- Solo banco sintético propio. RPC como authenticated, triggers reales; rollback total.
2: begin;
3: set local statement_timeout='120s';
4: set local lock_timeout='3s';
5: insert into storage.buckets(id,name,public) values('f4-comprobantes','f4-comprobantes',false) on conflict(id) do nothing;
6: select set_config('banco.revision',(select revision::text from crm.recorrido_control where id),true);
7: create temporary table conversion_casos(nombre text primary key,id uuid default gen_random_uuid(),
8:   documento text,solicitud uuid default gen_random_uuid(),persona uuid,tarea uuid,actividad uuid,datos jsonb,respuesta jsonb,acceso jsonb);
9: grant select,update on conversion_casos to authenticated;
10: create function pg_temp.exigir(p_ok boolean,p_mensaje text) returns void language plpgsql as $$
11: begin if p_ok is not true then raise exception 'CONVERSION: %',p_mensaje;end if;end $$;
12: create function pg_temp.rechaza(p_sql text,p_estado text,p_texto text default null) returns void language plpgsql as $$
13: begin
14:   begin execute p_sql;
15:   exception when others then
16:     if sqlstate=p_estado and (p_texto is null or position(p_texto in sqlerrm)>0) then return;end if;
17:     raise exception 'Esperado % / %, obtenido % (%) en %',p_estado,p_texto,sqlstate,sqlerrm,p_sql;
18:   end;
19:   raise exception 'Debio rechazar con %: %',p_estado,p_sql;
20: end $$;
21: create function pg_temp.preparar_persona(p_nombre text) returns void language plpgsql as $$
22: declare c record;r jsonb;
23: begin
24:   select * into strict c from conversion_casos where nombre=p_nombre;
25:   r:=crm.preparar_persona_lead_inversion_fn(c.id,'DNI',c.documento,'BANCO RECORRIDO '||c.nombre);
26:   update conversion_casos set persona=(r->>'inversionista_id')::uuid where id=c.id;
27: end $$;
28: create function pg_temp.oficina(p_nombre text) returns void language plpgsql as $$
29: declare c record;r jsonb;
30: begin
31:   select * into strict c from conversion_casos where nombre=p_nombre;
32:   r:=crm.recorrido_atender_oficina_fn(gen_random_uuid(),c.id,'interesado','Asistencia y entrevista reales del banco',null,1000,'PEN');
33:   update conversion_casos set tarea=(r->>'tarea_id')::uuid,actividad=(r->>'actividad_id')::uuid where id=c.id;
34: end $$;
35:
36: insert into conversion_casos(nombre,documento) values ('antiguo','98640001'),('observacion','98640002');
37: insert into crm.leads(id,nombre_completo,telefono,origen,monto_estimado,vendedor_id,creado_por)
38: select id,'BANCO RECORRIDO '||nombre,'98764'||lpad(row_number() over(order by nombre)::text,4,'0'),'oficina',1000,
39:  'b0000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000002' from conversion_casos;
40: set local role authenticated;
41: select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
42: select pg_temp.preparar_persona('observacion');
43: select pg_temp.preparar_persona('antiguo');
44: select set_config('request.jwt.claim.sub','bf1c562e-ed08-4cc3-92a8-34f1fa3e9127',true);
45: select crm.recorrido_configurar_fn('exigir','Ensayo local de cohortes y primera conversion',current_setting('banco.revision')::integer+0);
46: reset role;
47: insert into conversion_casos(nombre,documento) values
48:  ('sin_hechos','98640003'),('normal_sin_llamada','98640004'),('anulada','98640005'),
49:  ('sin_resultado','98640006'),('reabierto','98640007'),('acceso','98640008'),('prodelco','98640009'),
50:  ('solo_etapa','98640010'),('confirmado','98640011'),('nueva_solicitud','98640012'),('futura','98640013');
51: insert into crm.leads(id,nombre_completo,telefono,origen,monto_estimado,vendedor_id,creado_por)
52: select id,'BANCO RECORRIDO '||nombre,'98765'||lpad(row_number() over(order by nombre)::text,4,'0'),'oficina',1000,
53:  'b0000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000002'
54:  from conversion_casos where persona is null;
55: select pg_temp.exigir((select bool_and((r.resultado->>'ciclo_inicio')::timestamptz>=ctl.cohorte_desde)
56:  from private.recorrido_evaluar(array(select id from conversion_casos where persona is null)) r
57:  cross join crm.recorrido_control ctl),'los nuevos pertenecen a la cohorte de exigencia');
58: set local role authenticated;
59: select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
60: do $$
61: declare c record;r jsonb;
62: begin
63:   select * into c from conversion_casos where nombre='sin_hechos';
64:   perform pg_temp.rechaza(format('select crm.preparar_persona_lead_inversion_fn(%L,''DNI'',%L,''BANCO SIN HECHOS'')',c.id,c.documento),'P0409','Antes de convertir');
65:   select * into c from conversion_casos where nombre='solo_etapa';
66:   update crm.leads set etapa='propuesta_enviada' where id=c.id;
67:   perform pg_temp.rechaza(format('select crm.preparar_persona_lead_inversion_fn(%L,''DNI'',%L,''BANCO SOLO ETAPA'')',c.id,c.documento),'P0409','Antes de convertir');
68:   for c in select * from conversion_casos where nombre in ('normal_sin_llamada','sin_resultado','futura') loop
69:     insert into crm.tareas(lead_id,tipo,titulo,vence_en,modalidad_reunion,ubicacion_reunion,creado_por)
70:     values(c.id,'reunion','Cita normal del banco',clock_timestamp()+case when c.nombre='futura' then interval '1 day' else interval '-1 minute' end,
71:       'presencial','Oficina banco','b0000000-0000-4000-8000-000000000002') returning id into c.tarea;
72:     if c.nombre='futura' then
73:       update conversion_casos set tarea=c.tarea where id=c.id;
74:       perform pg_temp.rechaza(format('select crm.preparar_persona_lead_inversion_fn(%L,''DNI'',%L,''BANCO CITA FUTURA'')',c.id,c.documento),'P0409','Antes de convertir');
75:       continue;
76:     end if;
77:     if c.nombre='sin_resultado' then
78:       perform pg_temp.rechaza(format('select crm.cerrar_reunion_v3(%L,%L,''completada'',''sin_clasificar'',null,''Sin entrevista'',null,1000,''PEN'')',gen_random_uuid(),c.tarea),'22023','resultado comercial');
79:       update conversion_casos set tarea=c.tarea where id=c.id;
80:     else
81:       r:=crm.cerrar_reunion_v3(gen_random_uuid(),c.tarea,'completada','interesado',null,'Asistio a su cita',null,1000,'PEN');
82:       update conversion_casos set tarea=c.tarea,actividad=(r->>'actividad_id')::uuid where id=c.id;
83:       perform pg_temp.preparar_persona(c.nombre);
84:     end if;
85:   end loop;
86:   for c in select * from conversion_casos where nombre in ('anulada','reabierto','acceso','prodelco','confirmado','nueva_solicitud') loop
87:     perform pg_temp.oficina(c.nombre);perform pg_temp.preparar_persona(c.nombre);
88:   end loop;
89:   raise notice 'PASS: identidad bloqueada sin hechos, solo etapa, futura o asistencia sin resultado; cita e entrevista sin llamada previa aceptadas';
90: end $$;
91: reset role;
92: -- Forma histórica permitida por la tabla, nunca por el formulario actual.
93: select set_config('request.jwt.claim.sub','',true);
94: do $$
95: declare c record;a uuid;
96: begin
97:   select * into c from conversion_casos where nombre='sin_resultado';
98:   insert into crm.actividades(lead_id,tipo,metadata,creado_por)
99:     values(c.id,'reunion_realizada',jsonb_build_object('tarea_id',c.tarea),'b0000000-0000-4000-8000-000000000002') returning id into a;
100:   perform set_config('crm.op_tarea','on',true);
101:   update crm.tareas set estado='completada',resultado_actividad_id=a,resultado_reunion='sin_clasificar' where id=c.tarea;
102:   perform set_config('crm.op_tarea','off',true);
103: end $$;
104: set local role authenticated;
105: select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
106: select pg_temp.rechaza(format('select crm.preparar_persona_lead_inversion_fn(%L,''DNI'',%L,''BANCO SIN ENTREVISTA'')',id,documento),'P0409','Antes de convertir')
107:  from conversion_casos where nombre='sin_resultado';
108: reset role;
109: select pg_temp.exigir(not exists(select 1 from crm.inversionistas i join crm.inversionista_identificadores d on d.inversionista_id=i.id
110:   where d.documento_normalizado in ('98640003','98640006','98640010','98640013')),'los rechazos no dejaron identidades a medias');
111: select pg_temp.exigir((select not (resultado#>>'{pasos,contactado}')::boolean and (resultado->>'habilita_conversion')::boolean
112:  from private.recorrido_evaluar(array[(select id from conversion_casos where nombre='normal_sin_llamada')])),'contacto previo no es requisito adicional');
113:
114: -- Datos cooperativos reales de la puerta vigente; solo los bytes de comprobante son fixture.
115: update conversion_casos set datos=jsonb_build_object('inversionista_id',persona,'lead_id',id,
116:  'empresa',case when nombre='prodelco' then 'prodelco' else 'qorilazo' end,'monto',1000,'moneda','PEN',
117:  'fecha_comercial',(clock_timestamp() at time zone 'America/Lima')::date,
118:  'vence_en',private.coopac_validar_condiciones((clock_timestamp() at time zone 'America/Lima')::date,12,12),
119:  'plazo_meses',12,'tasa_anual',12,'numero_transaccion','RECORRIDO-'||solicitud,'referencia','BANCO SINTETICO',
120:  'evidencia',jsonb_build_object('ruta',persona||'/'||solicitud||'/comprobante.pdf')) where persona is not null and nombre<>'acceso';
121: update conversion_casos set datos=jsonb_build_object('inversionista_id',persona,'lead_id',id,'empresa','avance',
122:  'contrato',jsonb_build_object('moneda','PEN','capital',1000),'cronograma','[]'::jsonb,'cuenta','{}'::jsonb,
123:  'alta_portal',jsonb_build_object('correo','recorrido.'||id||'@example.test','nombre_completo','BANCO ACCESO RECORRIDO',
124:  'telefono','987650099','domicilio','CALLE SINTETICA 123, LIMA')) where nombre='acceso';
125: update crm.leads set correo=c.datos#>>'{alta_portal,correo}' from conversion_casos c where c.id=crm.leads.id and c.nombre='acceso';
126: set local role authenticated;
127: select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
128: do $$
129: declare c record;r jsonb;
130: begin
131:   for c in select * from conversion_casos where persona is not null and nombre<>'nueva_solicitud' loop
132:     r:=crm.preparar_inversion_fn(c.solicitud,c.datos);
133:     update conversion_casos set respuesta=r where id=c.id;
134:   end loop;
135: end $$;
136: reset role;
137: insert into storage.objects(bucket_id,name,metadata)
138: select 'f4-comprobantes',datos#>>'{evidencia,ruta}','{"size":12,"mimetype":"application/pdf"}'::jsonb
139:  from conversion_casos where datos->>'empresa' in ('qorilazo','prodelco') and nombre<>'nueva_solicitud';
140: -- Corrección real posterior del historial: nunca se inventa un registro de contexto.
141: select set_config('request.jwt.claim.sub','',true);
142: update crm.actividades set metadata=metadata||jsonb_build_object('deshecho_en',clock_timestamp())
143:  where id in (select actividad from conversion_casos where nombre in ('anulada','nueva_solicitud'));
144: set local role authenticated;
145: select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
146: do $$
147: declare c record;r jsonb;
148: begin
149:   select * into c from conversion_casos where nombre='nueva_solicitud';
150:   perform pg_temp.rechaza(format('select crm.preparar_inversion_fn(%L,%L)',c.solicitud,c.datos),'P0409','Antes de convertir');
151:   select * into c from conversion_casos where nombre='anulada';
152:   perform pg_temp.rechaza(format('select crm.confirmar_inversion_revisada_fn(%L,0)',c.solicitud),'P0409','Antes de convertir');
153:   r:=crm.preparar_inversion_fn(c.solicitud,c.datos);
154:   perform pg_temp.exigir(r->>'solicitud_id'=c.solicitud::text,'borrador recuperable tras invalidacion');
155:   for c in select * from conversion_casos where nombre in ('antiguo','normal_sin_llamada','prodelco','confirmado') loop
156:     r:=crm.confirmar_inversion_revisada_fn(c.solicitud,0);
157:     update conversion_casos set respuesta=r where id=c.id;
158:   end loop;
159:   raise notice 'PASS: primera conversion de ambas cooperativas, antiguos no retrobloqueados, nueva solicitud y confirmacion protegidas; borrador conservado';
160: end $$;
161: reset role;
162: select pg_temp.exigir((select s.estado='preparada' and s.datos=c.datos and s.inversion_id is null and s.recorrido_confirmado is null
163:  from crm.inversion_solicitudes s join conversion_casos c on c.solicitud=s.id where c.nombre='anulada'),'rechazo atomico preserva condiciones y comprobante');
164: select pg_temp.exigir(not exists(select 1 from crm.inversion_solicitudes s join conversion_casos c on c.solicitud=s.id where c.nombre='nueva_solicitud'),'no solicitud nueva a medias');
165: select pg_temp.exigir((select bool_and(s.recorrido_confirmado->>'modo'='exigir' and (s.recorrido_confirmado->>'exigible')::boolean
166:  and s.recorrido_confirmado->>'asistencia_id'=c.actividad::text and s.recorrido_confirmado->>'entrevista_tarea_id'=c.tarea::text
167:  and l.etapa='convertido') from crm.inversion_solicitudes s join conversion_casos c on c.solicitud=s.id join crm.leads l on l.id=c.id
168:  where c.nombre in ('normal_sin_llamada','prodelco','confirmado')),'snapshot de la misma cita y conversion efectiva');
169: select pg_temp.exigir((select not (s.recorrido_confirmado->>'exigible')::boolean and s.recorrido_confirmado->>'estado'='incompleto'
170:  from crm.inversion_solicitudes s join conversion_casos c on c.solicitud=s.id where c.nombre='antiguo'),'antiguos sin backfill ni falsa evidencia');
171: select set_config('request.jwt.claim.sub','',true);
172: update crm.actividades set metadata=metadata||jsonb_build_object('deshecho_en',clock_timestamp())
173:  where id=(select actividad from conversion_casos where nombre='confirmado');
174: select pg_temp.rechaza(format('update crm.inversion_solicitudes set recorrido_confirmado=''{}'' where id=%L',
175:  (select solicitud from conversion_casos where nombre='confirmado')),'42501','inmutable');
176: set local role authenticated;
177: select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
178: do $$
179: declare c record;r jsonb;
180: begin
181:   select * into c from conversion_casos where nombre='confirmado';
182:   r:=crm.confirmar_inversion_revisada_fn(c.solicitud,0);
183:   perform pg_temp.exigir((r->>'reintento')::boolean and r->>'inversion_id'=c.respuesta->>'inversion_id','confirmacion perdida retorna inversion original tras invalidacion');
184:   r:=crm.preparar_persona_lead_inversion_fn(c.id,'DNI',c.documento,'BANCO RECORRIDO '||c.nombre);
185:   perform pg_temp.exigir(r->>'solicitud_id'=c.solicitud::text,'recuperacion de identidad confirmada no se bloquea');
186:   -- Una segunda inversión conserva el camino de Cartera, sin imponer otra entrevista.
187:   c.solicitud:=gen_random_uuid();
188:   c.datos:=(c.datos-'lead_id')||jsonb_build_object('numero_transaccion','RECORRIDO-'||c.solicitud,
189:     'evidencia',jsonb_build_object('ruta',c.persona||'/'||c.solicitud||'/comprobante.pdf'));
190:   perform crm.preparar_inversion_fn(c.solicitud,c.datos);
191:   update conversion_casos set acceso=jsonb_build_object('adicional',c.solicitud,'datos',c.datos) where nombre='confirmado';
192:   raise notice 'PASS: replay confirmado y fotografia inmutable; inversion adicional sin nueva entrevista';
193: end $$;
194: reset role;
195: insert into storage.objects(bucket_id,name,metadata)
196:  select 'f4-comprobantes',acceso#>>'{datos,evidencia,ruta}','{"size":12,"mimetype":"application/pdf"}'::jsonb
197:  from conversion_casos where nombre='confirmado';
198: set local role authenticated;
199: select crm.confirmar_inversion_revisada_fn((acceso->>'adicional')::uuid,0) from conversion_casos where nombre='confirmado';
200: reset role;
201: select pg_temp.exigir((select s.lead_origen_id is null and s.recorrido_confirmado is null and s.estado='confirmada'
202:  from crm.inversion_solicitudes s join conversion_casos c on s.id=(c.acceso->>'adicional')::uuid where c.nombre='confirmado'),'adicional confirmada sin evidencia inicial inventada');
203:
204: -- Un claim sin Auth no exime. Un alta externa efectivamente creada sí se recupera,
205: -- aunque después se invalide la entrevista; confirmar sigue bloqueado.
206: set local role authenticated;
207: select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
208: update conversion_casos set acceso=crm.acceso_inversion_fn(solicitud,'reclamar',jsonb_build_object('token',repeat('a',48))) where nombre='acceso';
209: reset role;
210: select set_config('request.jwt.claim.sub','',true);
211: update crm.actividades set metadata=metadata||jsonb_build_object('deshecho_en',clock_timestamp())
212:  where id=(select actividad from conversion_casos where nombre='acceso');
213: set local role authenticated;
214: select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
215: select pg_temp.rechaza(format('select crm.acceso_inversion_fn(%L,''reclamar'',%L)',solicitud,jsonb_build_object('token',repeat('a',48))),'P0409','Antes de convertir')
216:  from conversion_casos where nombre='acceso';
217: reset role;
218: -- Fixture explícito de Auth remoto creado con HTTP perdido. Ningún usuario real.
219: insert into auth.users(id,email,raw_app_meta_data)
220:  select gen_random_uuid(),datos#>>'{alta_portal,correo}',jsonb_build_object('provider','email','claim_id',acceso->>'claim_id')
221:  from conversion_casos where nombre='acceso';
222: update conversion_casos set acceso=acceso||jsonb_build_object('auth_user_id',u.id)
223:  from auth.users u where nombre='acceso' and u.raw_app_meta_data->>'claim_id'=acceso->>'claim_id';
224: set local role authenticated;
225: select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
226: do $$
227: declare c record;r jsonb;v_version integer;
228: begin
229:   select * into c from conversion_casos where nombre='acceso';
230:   r:=crm.acceso_inversion_fn(c.solicitud,'reclamar',jsonb_build_object('token',repeat('a',48)));
231:   perform pg_temp.exigir(r->>'claim_id'=c.acceso->>'claim_id','recupera el mismo claim con Auth efectivamente creado');
232:   v_version:=(r->>'version')::integer;
233:   r:=crm.acceso_inversion_fn(c.solicitud,'registrar_auth',jsonb_build_object('token',repeat('a',48),'version',v_version,'auth_user_id',c.acceso->>'auth_user_id'));
234:   r:=crm.acceso_inversion_fn(c.solicitud,'crear_perfil',jsonb_build_object('token',repeat('a',48),'version',(r->>'version')::integer));
235:   r:=crm.acceso_inversion_fn(c.solicitud,'enlazar',jsonb_build_object('token',repeat('a',48),'version',(r->>'version')::integer));
236:   perform pg_temp.exigir(r->>'estado'='enlazado','recuperacion completa sin dejar perfil huerfano');
237:   perform pg_temp.rechaza(format('select crm.confirmar_inversion_revisada_fn(%L,0)',c.solicitud),'P0409','Antes de convertir');
238:   r:=crm.acceso_inversion_fn(c.solicitud,'reclamar',jsonb_build_object('token',repeat('a',48)));
239:   perform pg_temp.exigir(r->>'estado'='enlazado','replay del acceso concluido tampoco recrea Auth');
240:   raise notice 'PASS: claim sin Auth no exime; Auth creado con respuesta perdida se recupera, primera conversion sigue bloqueada';
241: end $$;
242: reset role;
243: select pg_temp.exigir((select s.estado='preparada' and s.datos=c.datos and s.inversion_id is null
244:  from crm.inversion_solicitudes s join conversion_casos c on c.solicitud=s.id where c.nombre='acceso'),'recuperar acceso preserva borrador sin convertir');
245:
246: -- Descartar/reabrir inicia otro ciclo: una solicitud previa no conserva permiso.
247: set local role authenticated;
248: select set_config('request.jwt.claim.sub','bf1c562e-ed08-4cc3-92a8-34f1fa3e9127',true);
249: update crm.leads set etapa='descartado',motivo_descarte='sin_interes' where id=(select id from conversion_casos where nombre='reabierto');
250: select crm.reabrir_lead_fn(id) from conversion_casos where nombre='reabierto';
251: select pg_temp.rechaza(format('select crm.confirmar_inversion_revisada_fn(%L,0)',solicitud),'P0409','Antes de convertir')
252:  from conversion_casos where nombre='reabierto';
253: reset role;
254: select pg_temp.exigir((select ciclo_actual=2 from crm.leads where id=(select id from conversion_casos where nombre='reabierto')),'nuevo ciclo real');
255:
256: -- La defensa de tabla también cubre escritores privilegiados e importaciones.
257: select set_config('request.jwt.claim.sub','',true);
258: select set_config('crm.op_privilegiada','on',true);
259: select pg_temp.rechaza($q$insert into crm.leads(nombre_completo,telefono,origen,monto_estimado,vendedor_id,creado_por,etapa)
260:  values('BANCO INSERT CONVERTIDO','987659999','oficina',1000,'b0000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000002','convertido')$q$,'P0409','Registra primero');
261: select set_config('crm.op_privilegiada','off',true);
262: select pg_temp.rechaza(format('update crm.inversion_solicitudes set estado=''confirmada'' where id=%L',
263:  (select solicitud from conversion_casos where nombre='anulada')),'P0409','Antes de convertir');
264: do $$begin raise notice 'PASS: ciclo reabierto exige nuevos hechos; escrituras internas no saltan la defensa de tabla';end $$;
265:
266: -- Modo observación deja operar y registra su decisión; apagar no reinicia el corte.
267: set local role authenticated;
268: select set_config('request.jwt.claim.sub','bf1c562e-ed08-4cc3-92a8-34f1fa3e9127',true);
269: select crm.recorrido_configurar_fn('observacion','Ensayo observacion sin bloqueo comercial',current_setting('banco.revision')::integer+1);
270: select set_config('request.jwt.claim.sub','b0000000-0000-4000-8000-000000000002',true);
271: select crm.confirmar_inversion_revisada_fn(solicitud,0) from conversion_casos where nombre='observacion';
272: select set_config('request.jwt.claim.sub','bf1c562e-ed08-4cc3-92a8-34f1fa3e9127',true);
273: select crm.recorrido_configurar_fn('apagado','Ensayo de rollback conservando el corte',current_setting('banco.revision')::integer+2);
274: select crm.recorrido_configurar_fn('exigir','Reactivacion del mismo corte sin exenciones',current_setting('banco.revision')::integer+3);
275: reset role;
276: select pg_temp.exigir((select s.recorrido_confirmado->>'modo'='observacion' and not (s.recorrido_confirmado->>'exigible')::boolean
277:  from crm.inversion_solicitudes s join conversion_casos c on c.solicitud=s.id where c.nombre='observacion'),'observacion confirmada con modo real');
278:
279: set local role anon;
280: select pg_temp.rechaza('select crm.confirmar_inversion_revisada_fn(gen_random_uuid(),0)','42501');
281: reset role;
282: set local role service_role;
283: select pg_temp.rechaza('select private.recorrido_exigir(gen_random_uuid(),''forjado'')','42501');
284: reset role;
285: select pg_temp.exigir(private.assert_sla_nucleo() is not null,'nucleo SLA sin cambios');
286: rollback;

FILE docs/plans/recorrido-lead-hechos/evidencia/private.inversion_persona_contexto_para.sql
1: CREATE OR REPLACE FUNCTION private.inversion_persona_contexto_para(p_persona uuid, p_lead uuid, p_solicitud uuid, p_busqueda uuid)
2:  RETURNS jsonb
3:  LANGUAGE plpgsql
4:  SECURITY DEFINER
5:  SET search_path TO ''
6:  SET lock_timeout TO '5s'
7: AS $function$
8: declare
9:   v_i crm.inversionistas%rowtype;
10:   v_p public.perfiles%rowtype;
11:   v_l crm.leads%rowtype;
12:   v_doc crm.inversionista_identificadores%rowtype;
13:   v_leads uuid[];
14:   v_nombre text;
15:   v_persona uuid;
16: begin
17:   v_persona := (private.inversion_persona_autorizada_para(p_persona,p_solicitud,p_busqueda)->>'inversionista_id')::uuid;
18:   select * into v_i from crm.inversionistas where id=v_persona for update;
19:   if v_i.estado <> 'activo' or v_i.no_contactar then
20:     raise exception 'La persona no permite nuevas inversiones: revisa su estado o No insistir' using errcode='P0429';
21:   end if;
22:   if v_i.responsable_relacion_id is null or not exists (
23:     select 1 from crm.equipo e join public.perfiles p on p.id=e.perfil_id
24:     where e.perfil_id=v_i.responsable_relacion_id and e.activo and p.activo
25:       and e.rol_crm in ('vendedor','supervisor')
26:   ) then
27:     raise exception 'Asigna un responsable comercial activo antes de registrar la inversión' using errcode='P0409';
28:   end if;
29:   select * into v_doc from crm.inversionista_identificadores
30:   where inversionista_id=v_persona and estado='vigente' and verificado
31:   order by case tipo_documento when 'DNI' then 1 when 'CE' then 2 else 3 end,id limit 1;
32:   if not found then
33:     raise exception 'La inversión requiere un documento verificado' using errcode='P0409';
34:   end if;
35:   if v_i.perfil_id is not null then
36:     select * into v_p from public.perfiles where id=v_i.perfil_id for share;
37:     if not found or v_p.activo is not true or v_p.rol <> 'cliente' then
38:       raise exception 'El perfil Avance requiere revisión antes de operar' using errcode='P0409';
39:     end if;
40:     if not private.documento_es_de_identidad(v_persona,v_p.tipo_documento,v_p.dni) then
41:       raise exception 'El documento del perfil requiere conciliación con la persona' using errcode='P0409';
42:     end if;
43:   end if;
44:   select array_agg(distinct id order by id) into v_leads from (
45:     select l.id from crm.leads l where l.inversionista_id=v_persona
46:     union select il.lead_id from crm.inversionista_leads il
47:       where il.inversionista_id=v_persona and il.rol='canonico'
48:   ) l;
49:   if coalesce(cardinality(v_leads),0)>1 then
50:     raise exception 'Hay más de un lead canónico; corresponde conciliación de identidad' using errcode='P0409';
51:   end if;
52:   if cardinality(v_leads)=1 then
53:     -- NOWAIT mantiene el orden de la corrección/fusión y evita esperar una reasignación que ya tomó el lead.
54:     select * into v_l from crm.leads where id=v_leads[1] for share nowait;
55:     if v_l.no_contactar then
56:       raise exception 'La persona tiene No insistir en su lead' using errcode='P0429';
57:     end if;
58:     if p_lead is null and v_l.etapa <> 'convertido' then
59:       raise exception 'Completa la conversión inicial antes de registrar otra inversión' using errcode='P0409';
60:     end if;
61:   end if;
62:   if p_lead is not null then
63:     if v_l.id is distinct from p_lead or v_l.activo is not true or
64:       not coalesce((private.rol_crm((select auth.uid()))='gerencia' or
65:         v_l.vendedor_id in (select private.vendedor_ids_visibles((select auth.uid())))),false) then
66:       raise exception 'Lead no encontrado o fuera de tu ámbito' using errcode='42501';
67:     end if;
68:     if v_l.etapa in ('convertido','descartado') then
69:       raise exception 'El lead ya está cerrado; consulta su inversión en Cartera' using errcode='P0409';
70:     end if;
71:     if v_l.vendedor_id is distinct from v_i.responsable_relacion_id then
72:       raise exception 'El responsable de la persona y el analista del lead deben coincidir antes de invertir' using errcode='P0409';
73:     end if;
74:     if exists(select 1 from private.leads_de_personas(array[v_persona]) x where x<>p_lead)
75:       or exists(select 1 from crm.inversiones where inversionista_id=v_persona and es_primera_conversion) then
76:       raise exception 'La persona ya tiene una conversión inicial; requiere conciliación' using errcode='P0409';
77:     end if;
78:     if exists(select 1 from crm.conversion_reservas r where
79:       (r.lead_id=p_lead or r.inversionista_id=v_persona) and
80:       (r.efectos_iniciados_en is not null or r.expira_en>now()) for update nowait) then
81:       raise exception 'Hay una conversión anterior pendiente; revisa su acceso antes de continuar' using errcode='P0409';
82:     end if;
83:   end if;
84:   v_nombre := coalesce(nullif(btrim(v_p.nombre_completo),''),nullif(btrim(v_l.nombre_completo),''),
85:     (select ce.nombre_completo from crm.cierres_externos ce where ce.inversionista_id=v_persona order by ce.creado_en desc,ce.id desc limit 1));
86:   if v_nombre is null then
87:     raise exception 'La persona necesita un antecedente con su nombre completo' using errcode='P0409';
88:   end if;
89:   return jsonb_build_object('inversionista_id',v_i.id,'perfil_id',v_i.perfil_id,
90:     'responsable_id',v_i.responsable_relacion_id,'lead_id',v_l.id,
91:     'documento_tipo',v_doc.tipo_documento,'documento',v_doc.documento_normalizado,'nombre',v_nombre);
92: end;
93: $function$

FILE _supabase_functions/functions/crm-inversion-portal/handler.mjs
1: import { claveTemporalDesdeDocumento } from '../_shared/documento.ts';
2: import { validarDomicilioLegal } from '../_shared/domicilio.mjs';
3: import { authTieneMarca, correoYaRegistrado, interpretarReclamo, statusDeErrorSaga } from '../_shared/saga-auth.mjs';
4:
5: const origenesProduccion = new Set([
6:   'https://crm.miavance.com', 'https://www.crm.miavance.com',
7:   'https://miavance.com', 'https://www.miavance.com',
8: ]);
9: const erroresPublicosRpc = new Set(['P0409', 'P0429', '22023', 'P0002', '42501']);
10: const errorPublico = (message, status) => Object.assign(new Error(message), { status, publico: true });
11:
12: // Mismo límite en bytes con y sin Content-Length; no acumula cuerpos arbitrarios.
13: async function leerSolicitud(req) {
14:   const longitud = req.headers.get('Content-Length');
15:   if (longitud !== null && (!/^\d+$/.test(longitud) || !Number.isSafeInteger(Number(longitud)))) {
16:     throw errorPublico('Envía una solicitud JSON válida.', 400);
17:   }
18:   if (longitud !== null && Number(longitud) > 4096) throw errorPublico('Solicitud demasiado grande.', 400);
19:   if (!req.body) throw errorPublico('Envía una solicitud JSON válida.', 400);
20:   const reader = req.body.getReader(), chunks = [];
21:   let total = 0;
22:   try {
23:     while (true) {
24:       const { value, done } = await reader.read();
25:       if (done) break;
26:       total += value.byteLength;
27:       if (total > 4096) {
28:         await reader.cancel();
29:         throw errorPublico('Solicitud demasiado grande.', 400);
30:       }
31:       chunks.push(value);
32:     }
33:   } finally { reader.releaseLock(); }
34:   const bytes = new Uint8Array(total);
35:   let offset = 0;
36:   for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
37:   try { return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes)); }
38:   catch { throw errorPublico('Envía una solicitud JSON válida.', 400); }
39: }
40: const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
41: /**
42:  * La misma función se usa en Deno y en el oráculo HTTP del banco. fetchImpl solo
43:  * permite observar/pérder respuestas reales en las pruebas; no inventa estados.
44:  * No envía correos. La clave inicial conserva la política actual del Portal.
45:  */
46: export function crearHandlerAccesoInversion({ supabaseUrl, anonKey, serviceKey, fetchImpl = fetch }) {
47:   const base = supabaseUrl.replace(/\/$/, '');
48:   return async function atender(req) {
49:     const origin = req.headers.get('Origin');
50:     const cors = {
51:       'Access-Control-Allow-Origin': origin && origenesProduccion.has(origin) ? origin : 'https://crm.miavance.com',
52:       'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
53:       'Access-Control-Allow-Methods': 'POST, OPTIONS',
54:       'Cache-Control': 'no-store', 'Vary': 'Origin', 'X-Content-Type-Options': 'nosniff',
55:     };
56:     const respuesta = (status, body) => new Response(JSON.stringify(body), {
57:       status, headers: { ...cors, 'Content-Type': 'application/json; charset=utf-8' },
58:     });
59:     if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
60:     if (req.method !== 'POST') return respuesta(405, { error: 'Usa POST para completar el acceso.' });
61:     const authorization = req.headers.get('Authorization');
62:     if (!authorization?.match(/^Bearer \S+$/i)) return respuesta(401, { error: 'Inicia sesión para continuar.' });
63:     let solicitud;
64:     let tokenRecuperacion;
65:     try {
66:       solicitud = await leerSolicitud(req);
67:       if (!solicitud || typeof solicitud !== 'object' || Array.isArray(solicitud)
68:         || Object.keys(solicitud).some(k => !['solicitud_id', 'token'].includes(k))
69:         || typeof solicitud.solicitud_id !== 'string' || !uuid.test(solicitud.solicitud_id)
70:         || (solicitud.token != null && (typeof solicitud.token !== 'string' || !/^[a-f0-9]{48}$/.test(solicitud.token)))) {
71:         return respuesta(400, { error: 'Identificador o token de solicitud inválido.' });
72:       }
73:       tokenRecuperacion = solicitud.token ?? undefined;
74:       async function llamar(ruta, { admin = false, method = 'POST', body, crm = false } = {}) {
75:         const res = await fetchImpl(`${base}${ruta}`, {
76:           method, signal: AbortSignal.timeout(25_000),
77:           headers: {
78:             apikey: admin ? serviceKey : anonKey,
79:             // sb_secret_ se autentica por apikey; no es un JWT para Bearer.
80:             ...(!admin ? { Authorization: authorization }
81:               : serviceKey.startsWith('sb_secret_') ? {} : { Authorization: `Bearer ${serviceKey}` }),
82:             'Content-Type': 'application/json',
83:             ...(crm ? { 'Accept-Profile': 'crm', 'Content-Profile': 'crm' } : {}),
84:           },
85:           ...(body === undefined ? {} : { body: JSON.stringify(body) }),
86:         });
87:         const data = await res.json();
88:         if (!res.ok) {
89:           const error = new Error(data.message ?? data.msg ?? data.error_description ?? 'No se pudo completar el acceso.');
90:           error.code = data.code ?? data.error_code;
91:           error.status = crm ? statusDeErrorSaga(error) : (res.status === 401 || res.status === 403 ? 401 : 409);
92:           error.publico = crm && erroresPublicosRpc.has(error.code);
93:           throw error;
94:         }
95:         return data;
96:       }
97:       const usuario = await llamar('/auth/v1/user', { method: 'GET' });
98:       if (!usuario?.id) return respuesta(401, { error: 'La sesión no está vigente.' });
99:       const paso = (nombre, payload = {}) => llamar('/rest/v1/rpc/acceso_inversion_fn', {
100:         crm: true, body: { p_solicitud: solicitud.solicitud_id, p_paso: nombre, p_payload: payload },
101:       });
102:       let reclamo = await paso('reclamar', tokenRecuperacion ? { token: tokenRecuperacion } : {});
103:       let estado = interpretarReclamo(reclamo);
104:       if (estado.paso === 'listo') return respuesta(200, {
105:         ok: true, solicitud_id: solicitud.solicitud_id, perfil_id: estado.perfilId, reintento: true,
106:       });
107:       if (!estado.claimId || !estado.token || !estado.version || estado.paso === 'desconocido') {
108:         throw new Error('El servidor devolvió un estado de acceso incompleto.');
109:       }
110:       tokenRecuperacion = estado.token;
111:       const datos = reclamo.datos_portal;
112:       const domicilio = validarDomicilioLegal(datos?.domicilio);
113:       if (!domicilio.ok) throw errorPublico(domicilio.error, 400);
114:       const contextoPaso = () => ({ token: tokenRecuperacion, version: estado.version });
115:       const comprobarUsuario = user => {
116:         if (!authTieneMarca(user, estado.claimId) || user.email?.toLowerCase() !== datos.correo) {
117:           throw errorPublico('Ese acceso no pertenece a esta solicitud; requiere revisión.', 409);
118:         }
119:         return user;
120:       };
121:       if (estado.paso === 'crear_auth') {
122:         let auth;
123:         try {
124:           auth = await llamar('/auth/v1/admin/users', {
125:             admin: true, body: {
126:               email: datos.correo, password: claveTemporalDesdeDocumento(reclamo.documento), email_confirm: true,
127:               app_metadata: { claim_id: estado.claimId },
128:             },
129:           });
130:         } catch (error) {
131:           if (error.code !== 'email_exists' && !correoYaRegistrado(error.message)) throw error;
132:           const encontrado = await llamar('/rest/v1/rpc/auth_usuario_por_correo_fn', {
133:             admin: true, crm: true, body: { p_correo: datos.correo },
134:           });
135:           if (!encontrado.id || !authTieneMarca(encontrado, estado.claimId)) {
136:             throw errorPublico('El correo ya pertenece a otro acceso; requiere revisión de Gerencia.', 409);
137:           }
138:           auth = await llamar(`/auth/v1/admin/users/${encontrado.id}`, { admin: true, method: 'GET' });
139:         }
140:         comprobarUsuario(auth);
141:         reclamo = await paso('registrar_auth', { ...contextoPaso(), auth_user_id: auth.id });
142:         estado = interpretarReclamo(reclamo);
143:       }
144:       if (estado.paso === 'crear_perfil') {
145:         const auth = await llamar(`/auth/v1/admin/users/${estado.authUserId}`, { admin: true, method: 'GET' });
146:         comprobarUsuario(auth);
147:         reclamo = await paso('crear_perfil', contextoPaso());
148:         estado = interpretarReclamo(reclamo);
149:       }
150:       if (estado.paso === 'enlazar') {
151:         reclamo = await paso('enlazar', contextoPaso());
152:         estado = interpretarReclamo(reclamo);
153:       }
154:       if (estado.paso !== 'listo' || !estado.perfilId) throw new Error('El acceso sigue pendiente de completar.');
155:       return respuesta(200, { ok: true, solicitud_id: solicitud.solicitud_id, perfil_id: estado.perfilId, reintento: false });
156:     } catch (error) {
157:       return respuesta(error.status ?? 503, {
158:         error: error.publico === true ? error.message : 'No se pudo completar el acceso. Retoma esta misma solicitud.',
159:         ...(solicitud?.solicitud_id ? { solicitud_id: solicitud.solicitud_id } : {}),
160:         ...(tokenRecuperacion ? { token: tokenRecuperacion } : {}),
161:       });
162:     }
163:   };
164: }
