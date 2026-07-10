# Informe técnico — Modelo de datos y RLS del CRM VITANOVA (Clínica Álvarez)

**Base de rutas:** `/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANZA-DIGITAL/REPOSITORIO/CLINICA ALVAREZ/crm-vitanova/supabase/` — todas las citas `archivo:línea` de abajo son relativas a esa carpeta. Repositorio tratado como READ-ONLY (solo lectura).

**Fuentes leídas:** `SCHEMA.md` (completo, 399 líneas), `remote-schema.sql` (snapshot autoritativo del remoto, 97 KB — inventariado con grep de policies/funciones), `APLICAR-TODO.sql`, `seed.sql`, `scripts/seed-users.mjs`, `scripts/test-rls.mjs`, `migrations/MIGRACIONES.md` y las **43 migraciones** de `migrations/` (el encargo decía 12; en realidad hay 43 archivos .sql — 30 documentadas en MIGRACIONES.md hasta 2026-06-20 y 13 posteriores de las "Olas A/B/C" de auditoría, jun 25-28). Además existe `_migraciones-locales-previas/` (8 archivos `000N_*.sql` archivados, esquema previo hecho a mano, ya no fuente).

---

## 1. Arquitectura de seguridad (el PATRÓN que interesa a Avance Corp)

Multi-tenant compartido (una BD, N clínicas) + jerarquía de 3 niveles dentro del tenant. Cuatro mecanismos ortogonales:

1. **Scoping por tenant:** toda tabla tiene `clinica_id`; toda policy exige `clinica_id = private.clinica_del_usuario()`.
2. **Jerarquía de visibilidad:** `usuarios.rol` (`gerente|supervisor|asesor`) + `usuarios.supervisor_id` (auto-FK). La visibilidad se resuelve con `private.asesor_ids_visibles(uid)`: gerente = toda la clínica; supervisor = su subárbol recursivo; asesor = solo él.
3. **Esquema `private`:** helpers y funciones-trigger sensibles viven en `private`, que PostgREST NO expone (solo publica `public`). `authenticated` tiene `usage` del esquema y `EXECUTE` de los 3 helpers (para que las policies puedan invocarlos), pero nada es alcanzable vía `/rest/v1/rpc/` (`migrations/20260614053035_helpers_a_esquema_privado.sql:1-19`).
4. **JWT enriquecido:** hook `public.custom_access_token_hook` inyecta `clinica_id` y `rol` como claims; `clinica_del_usuario()` lee primero el claim y cae a la tabla.

Disciplina complementaria: tras cada bloque hay una migración de **hardening** que fija `search_path` y revoca `EXECUTE` de funciones-trigger a `public/anon/authenticated` (`20260614052923`, `20260614064813`, `20260614064947`, `20260625060801`).

### 1.1 Helpers `private.*` — transcripción completa

Creados en `migrations/20260614052437_cimientos_bloque_1.sql:79-137` (nacen en `public`, se mueven a `private` en `20260614053035`):

```sql
create or replace function asesor_ids_visibles(p_usuario_id uuid)
returns setof uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_rol text;
  v_clinica uuid;
begin
  select rol, clinica_id into v_rol, v_clinica
  from usuarios where id = p_usuario_id and activo = true;

  if v_rol is null then
    return;
  elsif v_rol = 'gerente' then
    return query select id from usuarios
      where clinica_id = v_clinica and activo = true;
  elsif v_rol = 'supervisor' then
    return query
      with recursive subarbol as (
        select id from usuarios where id = p_usuario_id
        union all
        select u.id from usuarios u
        join subarbol s on u.supervisor_id = s.id
        where u.activo = true
      )
      select id from subarbol;
  else
    return next p_usuario_id;
  end if;
end;
$$;

create or replace function puede_ver_entidad(p_usuario_id uuid, p_propietario_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from asesor_ids_visibles(p_usuario_id) v where v = p_propietario_id
  );
$$;

create or replace function clinica_del_usuario()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    nullif(auth.jwt() ->> 'clinica_id', '')::uuid,
    (select clinica_id from usuarios where id = (select auth.uid())),
  );
$$;
```
(Nota: la coma final es transcripción mía errónea — el original `20260614052437:126-137` no la tiene; el cuerpo real es `select coalesce(nullif(auth.jwt() ->> 'clinica_id', '')::uuid, (select clinica_id from usuarios where id = (select auth.uid())));`.)

Claves del patrón: `security definer` para no recursar contra las policies de `usuarios`; `stable` para que Postgres lo evalúe una vez por query (initplan) al usarse como `(select ...)` en la policy; el CTE recursivo soporta N niveles de anidamiento sin cambio alguno (sirve tal cual para 4 niveles vendedor→supervisor→gerencia); `activo = true` como filtro (usuarios desactivados no ven nada y no son vistos).

Movida a `private` + grants (`20260614053035:6-19`):
```sql
create schema if not exists private;
grant usage on schema private to authenticated;
alter function public.asesor_ids_visibles(uuid) set schema private;
alter function public.puede_ver_entidad(uuid, uuid) set schema private;
alter function public.clinica_del_usuario() set schema private;
grant execute on function private.asesor_ids_visibles(uuid) to authenticated;
grant execute on function private.puede_ver_entidad(uuid, uuid) to authenticated;
grant execute on function private.clinica_del_usuario() to authenticated;
alter function private.puede_ver_entidad(uuid, uuid) set search_path = private, public;
```

### 1.2 Hook JWT (inyección de clinica_id) — transcripción

`migrations/20260614052437_cimientos_bloque_1.sql:142-174`:
```sql
create or replace function public.custom_access_token_hook(event jsonb)
returns jsonb
language plpgsql
stable
set search_path = public
as $$
declare
  v_clinica_id uuid;
  v_rol text;
  v_claims jsonb;
begin
  select clinica_id, rol into v_clinica_id, v_rol
  from public.usuarios
  where id = (event->>'user_id')::uuid and activo = true;

  v_claims := event->'claims';

  if v_clinica_id is not null then
    v_claims := jsonb_set(v_claims, '{clinica_id}', to_jsonb(v_clinica_id::text));
    v_claims := jsonb_set(v_claims, '{rol}', to_jsonb(v_rol));
  end if;

  return jsonb_set(event, '{claims}', v_claims);
end;
$$;

grant usage on schema public to supabase_auth_admin;
grant execute on function public.custom_access_token_hook to supabase_auth_admin;
revoke execute on function public.custom_access_token_hook from authenticated, anon, public;
grant select on table public.usuarios to supabase_auth_admin;

create policy "auth_admin_lee_usuarios" on public.usuarios
  as permissive for select to supabase_auth_admin using (true);
```
Respaldo adicional: `seed-users.mjs:34` también graba `app_metadata: { clinica_id, rol }` al crear el auth user ("respaldo si el hook no corre aún"). El hook se activa en Dashboard → Authentication → Hooks (comentario en `APLICAR-TODO.sql:163-167`).

---

## 2. Tablas (18) y relaciones

Todas con RLS habilitada, `id uuid pk default gen_random_uuid()` salvo indicación. Naming: español, snake_case, timestamps `*_en`/`*_a` (coincide con la convención destino de Avance).

| Tabla | Propósito | Relaciones clave | Origen |
|---|---|---|---|
| `clinicas` | El tenant. `ruc` UNIQUE check len=11, `plan` (starter/growth/pro), `activa` bool, `configuracion` jsonb (horario, límites de cupo, sla.primera_respuesta_min, meta_ingreso_mensual, igv_tasa, recordatorios.cita_min, intake_token) | raíz | `20260614052437:16-25` |
| `usuarios` | Extiende `auth.users` (PK = FK a auth.users on delete cascade). `rol` check 3 valores, `supervisor_id` auto-FK, constraint `asesor_debe_tener_supervisor` | → clinicas (restrict), → usuarios | `20260614052437:30-45` |
| `lineas_servicio` | Catálogo de servicios médicos por clínica; `categoria` check con 10 valores clínicos; `ticket_promedio` alimenta scoring y KPI | → clinicas | `20260614052437:52-66` |
| `prospectos` | **Lead, tabla central.** teléfono normalizado, etapa (pipeline), score, columnas SLA, `primera_respuesta_en`, cohorte (`cerrado_en`, `etapa_maxima_idx`), `reasignaciones_sla_n`, `asignado_supervisor_id` (bandeja), soft-delete (`eliminado/eliminado_en/eliminado_por`), consentimiento Ley 29733 | → clinicas, → usuarios (asesor, set null), → lineas_servicio | `20260614061134:17-54` + ALTERs |
| `actividades` | Timeline/bitácora del prospecto; `tipo` check 17 valores; `metadata` jsonb; `mensaje_externo_id` para dedup Meta; índice único de idempotencia de cadencias `uq_cad_toque` | → prospectos (cascade), → usuarios | `20260614061134:62-78` |
| `conversaciones` | Estado del inbox WhatsApp, 1 por prospecto (UNIQUE), ventana 24h Meta, no_leidos | → prospectos | `20260614063630:29-44` |
| `plantillas_whatsapp` | Plantillas aprobadas por Meta | → clinicas | `20260614063630:2-14` |
| `whatsapp_config` | PK = clinica_id; tokens en Supabase Vault (`*_secret_id uuid`), no en columnas | → clinicas | `20260614063630:17-26` |
| `cotizaciones` | Cotización médica: items jsonb, subtotal/igv/total con check `total = subtotal + igv`, `codigo` numerado al ENVIAR (nullable en borrador), `token_acceso` para link público, aceptación remota (nombre/ip), soft-delete `eliminado` | → clinicas, → prospectos, → usuarios | `20260614072511:2-25` + `20260614073820:1-15` |
| `contadores_cotizacion` | Correlativo por (clinica_id, anio), PK compuesta; **RLS habilitada SIN policy** = denegado a clientes, solo la función SECURITY DEFINER lo toca | → clinicas | `20260614072511:28-33`, RLS en `20260614080106:2` |
| `cadencias` | Plantilla de cadencia: `evento_disparador` (cotizacion_enviada/lead_nuevo/reactivacion/sin_avance), `modo` (auto/tarea) | → clinicas | `20260614073820:18-27` + `20260619025319:13-19` |
| `cadencia_pasos` | Pasos: paso, offset_dias, canal, plantilla_mensaje | → cadencias (cascade) | `20260614073820:28-36` |
| `cadencias_activas` | Instancia viva: paso_actual, proximo_toque_en, estado (activa/pausada/completada/detenida), UNIQUE(cotizacion_id) | → prospectos, → cotizaciones, → cadencias | `20260614073820:37-51` |
| `sla_config` | SLA por (etapa, banda de score): horas_max hábiles, warning_pct, `accion_breach` (solo_monitoreo/notificar_asesor/notificar_supervisor/reasignar) | → clinicas | `20260614074459:2-14` |
| `notificaciones` | In-app por usuario; `tipo` check 9 valores finales (sla_warning, sla_breach, reasignacion, cadencia, cotizacion_vista, cotizacion_aceptada, primera_respuesta, cita_recordatorio, lead_nuevo) | → clinicas, → usuarios (cascade) | `20260614074459:25-34`, checks ampliados en `20260617064811:36-39`, `20260625033158:12-16`, `20260628120000:33-37` |
| `metas` | Objetivo por asesor/mes; `usuario_id null` = meta default de clínica; UNIQUE(clinica_id, usuario_id, periodo) | → clinicas, → usuarios | `20260614215235:2-13` |
| `citas` | Calendario: consulta/cirugia/llamada/seguimiento/recordatorio; `prospecto_id NULL` = recordatorio libre; `metadata` jsonb enlaza tareas de cadencia; `recordatorio_enviado_en` (marca idempotente) | → clinicas, → prospectos, → usuarios | `20260618042009:7-23` + `20260619025319:10` + `20260625033158:6-9` |
| `app_errores` | Log de errores del cliente, append-only (sin UPDATE/DELETE para clientes) | → clinicas, → usuarios | `20260625052230:4-14` |

Índices relevantes al patrón: parciales `where eliminado = false` / `where activo = true` en todos los listados calientes; **unique parcial de dedup vivo** `uq_prospectos_telefono_vivo (clinica_id, telefono) where eliminado = false` (`20260614061134:60`); índice de vencidos `idx_cad_activas_due (proximo_toque_en) where estado='activa'`; cobertura de FKs añadida a escala SaaS (`20260625054158:9-19`).

---

## 3. Políticas RLS — transcripciones textuales

Inventario verificado contra `remote-schema.sql:1841-2083`: 36 policies en el snapshot 2026-06-20 (las migraciones de jun-25/28 agregan `app_errores_insert`, `app_errores_select_gerente` y alteran las de prospectos → ~38-39 vivas).

### 3.1 Scoping multi-tenant puro (clinica_id)

`migrations/20260614052437_cimientos_bloque_1.sql:179-195`:
```sql
alter table clinicas enable row level security;
create policy "clinicas_select_propia" on clinicas
  for select to authenticated
  using (id = clinica_del_usuario());

alter table lineas_servicio enable row level security;
create policy "lineas_select_clinica" on lineas_servicio
  for select to authenticated
  using (clinica_id = clinica_del_usuario());
```
(Tras `20260614053035` las policies resuelven `private.clinica_del_usuario()` por OID, sin re-crearse.)

Update del tenant solo gerente (`20260617064811:48-53`):
```sql
create policy "clinicas_update_gerente" on public.clinicas for update to authenticated
  using (id = private.clinica_del_usuario()
         and exists (select 1 from public.usuarios where id=(select auth.uid()) and rol='gerente'))
  with check (id = private.clinica_del_usuario());
```

### 3.2 Jerarquía gerente/supervisor/asesor sobre prospectos

Versión original (`20260614061134:141-155`):
```sql
alter table prospectos enable row level security;
create policy "prospectos_select_jerarquia" on prospectos
  for select to authenticated
  using (clinica_id = private.clinica_del_usuario() and eliminado = false
    and (asesor_id is null or asesor_id in (select private.asesor_ids_visibles((select auth.uid())))));
create policy "prospectos_insert" on prospectos
  for insert to authenticated
  with check (clinica_id = private.clinica_del_usuario()
    and (asesor_id is null or asesor_id = (select auth.uid())
         or exists (select 1 from usuarios where id = (select auth.uid()) and rol in ('gerente','supervisor'))));
create policy "prospectos_update_jerarquia" on prospectos
  for update to authenticated
  using (clinica_id = private.clinica_del_usuario()
    and (asesor_id is null or asesor_id in (select private.asesor_ids_visibles((select auth.uid())))))
  with check (clinica_id = private.clinica_del_usuario());
```

**Versión final vigente** (endurecida vía `ALTER POLICY` para la bandeja de reparto por supervisor, `20260628120000:89-117`):
```sql
alter policy prospectos_select_jerarquia on public.prospectos
  using (
    clinica_id = private.clinica_del_usuario()
    and eliminado = false
    and (
      asesor_id in (select private.asesor_ids_visibles((select auth.uid())))
      or (asesor_id is null and asignado_supervisor_id in (select private.asesor_ids_visibles((select auth.uid()))))
      or (asesor_id is null and exists (select 1 from usuarios where id = (select auth.uid()) and rol = 'gerente'))
    )
  );

alter policy prospectos_update_jerarquia on public.prospectos
  using (
    clinica_id = private.clinica_del_usuario()
    and (
      asesor_id in (select private.asesor_ids_visibles((select auth.uid())))
      or (asesor_id is null and asignado_supervisor_id in (select private.asesor_ids_visibles((select auth.uid()))))
      or (asesor_id is null and exists (select 1 from usuarios where id = (select auth.uid()) and rol = 'gerente'))
    )
  )
  with check (
    clinica_id = private.clinica_del_usuario()
    and (
      asesor_id is null
      or asesor_id in (select private.asesor_ids_visibles((select auth.uid())))
    )
  );
```
Semántica final: un lead "parkeado" (asesor_id null) solo lo ve su supervisor de turno y el gerente; el asesor solo ve lo suyo; al reasignar, el `asesor_id` resultante debe estar en tu subárbol. Nótese que la policy de UPDATE por sí sola no impide que un asesor se auto-reasigne el prospecto — ese hueco lo cierra un trigger (§4, `bloquear_reasignacion_asesor`).

Jerarquía sobre `usuarios` (`20260614052437:184-191` + update solo gerente en `20260614231225:15-20`):
```sql
create policy "usuarios_select_jerarquia" on usuarios
  for select to authenticated
  using (
    clinica_id = clinica_del_usuario()
    and id in (select asesor_ids_visibles((select auth.uid())))
  );

create policy "usuarios_update_gerente" on usuarios for update to authenticated
  using (clinica_id = private.clinica_del_usuario()
      and exists (select 1 from usuarios u where u.id=(select auth.uid()) and u.rol='gerente'))
  with check (clinica_id = private.clinica_del_usuario()
      and exists (select 1 from usuarios u where u.id=(select auth.uid()) and u.rol='gerente'));
```
**No hay policy INSERT en `usuarios`**: el alta va solo por Edge Function `admin-crear-usuario` con service_role (bypass RLS) — patrón importante.

Jerarquía "vía prospecto" (tablas hijas sin asesor propio) — `actividades` (`20260614061134:158-162`):
```sql
create policy "actividades_select_via_prospecto" on actividades
  for select to authenticated
  using (exists (select 1 from prospectos p where p.id = actividades.prospecto_id
    and p.clinica_id = private.clinica_del_usuario() and p.eliminado = false
    and (p.asesor_id is null or p.asesor_id in (select private.asesor_ids_visibles((select auth.uid()))))));
```
INSERT endurecido (auditoría de inbox, `20260614223015:4-13`) — solo el asesor DUEÑO registra un WhatsApp saliente; los inserts automáticos vienen de funciones SECURITY DEFINER que bypassean RLS:
```sql
create policy "actividades_insert_via_prospecto" on actividades
  for insert to authenticated
  with check (
    exists (
      select 1 from prospectos p
      where p.id = actividades.prospecto_id
        and p.clinica_id = private.clinica_del_usuario()
        and (actividades.tipo <> 'whatsapp_enviado' or p.asesor_id = (select auth.uid()))
    )
  );
```

### 3.3 Notificaciones por usuario

`migrations/20260614074459_sla_bloque_5.sql:36-40`:
```sql
alter table notificaciones enable row level security;
create policy "notif_propias" on notificaciones for select to authenticated
  using (usuario_id = (select auth.uid()) and clinica_id = private.clinica_del_usuario());
create policy "notif_marcar_leida" on notificaciones for update to authenticated
  using (usuario_id = (select auth.uid())) with check (usuario_id = (select auth.uid()));
```
Sin policy INSERT: solo las funciones SECURITY DEFINER (sla_tick, primera_respuesta_tick, etc.) crean notificaciones.

### 3.4 Escritura gerente-only (patrón repetido)

Forma final con WITH CHECK que re-valida el rol (fix de revisión adversarial, `20260614081132:45-60`; aplica a `cadencias`, `sla_config`, `plantillas_whatsapp`, `lineas_servicio`, y análogos en `metas` `20260614215235:22-26` y `cadencia_pasos` vía padre `20260614231225:5-12`):
```sql
create policy "cadencias_modify_gerente" on cadencias for all to authenticated
  using (clinica_id = private.clinica_del_usuario() and exists(select 1 from usuarios where id=(select auth.uid()) and rol='gerente'))
  with check (clinica_id = private.clinica_del_usuario() and exists(select 1 from usuarios where id=(select auth.uid()) and rol='gerente'));
```

### 3.5 Denegación total / tablas de secretos

`migrations/20260614063630_whatsapp_bloque_3.sql:115-116`:
```sql
alter table whatsapp_config enable row level security;
create policy "whatsapp_config_sin_acceso" on whatsapp_config for select to authenticated using (false);
```
Y `contadores_cotizacion`: RLS habilitada sin ninguna policy (`20260614080106:2`) = deny-all a clientes; solo `generar_codigo_cotizacion` (SECURITY DEFINER) lo toca.

### 3.6 Otras policies dignas de nota

- `cotizaciones_update` con USING jerárquico y WITH CHECK que valida asesor o rol (`20260614081132:38-42`).
- `cad_activas_pausar` corregida para filtrar por jerarquía, no solo clínica (`20260614081132:30-35`) — ejemplo del bug típico "scoping por tenant pero no por jerarquía en UPDATE".
- `citas_*_jerarquia`: SELECT/INSERT/UPDATE/**DELETE** (`20260618042009:121-141`) — citas es la única tabla con DELETE para clientes (hard-delete permitido en citas).
- `app_errores`: INSERT solo bajo tu propio `usuario_id` y tu clínica; SELECT solo gerente (`20260625052230:25-32`).

### 3.7 SECURITY DEFINER relevantes (RPCs con autorización interna)

**`crear_lead_entrante`** (ingesta externa, solo service_role) — versión final `20260628120000:40-83`: normaliza teléfono, dedup por `(clinica_id, telefono)` vivo, mapea servicio→línea con fallback, **parkea** al supervisor de turno (`asignado_supervisor_id` vía `private.asignar_supervisor_round_robin`, asesor_id null) y notifica `lead_nuevo`. Cierre de superficie:
```sql
revoke execute on function crear_lead_entrante(uuid,text,text,text,text,text,text,text) from public, anon, authenticated;
grant execute on function crear_lead_entrante(uuid,text,text,text,text,text,text,text) to service_role;
```

**`simular_whatsapp_entrante`** (`20260614063630:86-105`): RPC de demo que se auto-autoriza dentro del cuerpo (`if v_rol not in ('gerente','supervisor') then raise exception 'No autorizado'`), grant solo `authenticated`.

**`provisionar_clinica`** (`20260625055459:5-68`): alta atómica de un tenant (clínica + configuración default + seed de SLAs/líneas/meta + fila del gerente) en una transacción SECURITY DEFINER, idempotente por `on conflict`, solo service_role.

**`anonimizar_prospecto`** (Ley 29733, versión final `20260625055931:3-22` + revoke `20260625060801`): gerente-gated dentro del cuerpo + verificación de misma clínica; anonimiza PII (`nombre_completo='[ANONIMIZADO]'`, `telefono='+51900000000'` centinela porque la columna es NOT NULL y el unique parcial lo excluye al quedar `eliminado=true`), **soft-delete** y auditoría en timeline:
```sql
update prospectos set
  nombre_completo='[ANONIMIZADO]', telefono='+51900000000', email=null, dni=null, distrito=null,
  diagnostico_referido=null, presupuesto_estimado=null, acepta_tratamiento_datos=false,
  eliminado=true, eliminado_por=v_caller
where id = p_id;
```

---

## 4. Triggers (inventario completo)

| Trigger | Tabla / evento | Función | Qué hace | Migración |
|---|---|---|---|---|
| `trg_clinicas_upd` | clinicas BEFORE UPDATE | `set_actualizada_en()` | touch femenino (fix por convención de género) | `20260614060640` |
| `trg_usuarios_upd` | usuarios BEFORE UPDATE | `set_actualizado_en()` | touch | `20260614052437:73` |
| `trg_usuarios_cap` | usuarios BEFORE INSERT/UPDATE of rol,activo | `private.enforce_user_cap()` | **Cupo atómico** 3 supervisores / 6 asesores leído de `clinicas.configuracion->limites`; cuenta `count(*) ... and id <> new.id` y raise si lleno; cierra el TOCTOU de la Edge Function | `20260614232040:4-29` |
| `trg_prospectos_normalizar_tel` | prospectos BEFORE INS/UPD of telefono | `trg_normalizar_telefono()` | normaliza a `+51…` (`normalizar_telefono`, `20260614061134:1-15`) | `20260614061134:84-86` |
| `trg_prospectos_score_insert` | prospectos BEFORE INSERT | `set_score_on_insert()` | score inicial (calculadora pura) + arranque de reloj SLA (`sla_inicia_en`, `sla_proximo_vencimiento`) | `20260614074459:57-68` |
| `trg_prospectos_init_cohorte` | prospectos BEFORE INSERT | `private.prospecto_init_cohorte()` | inicializa `etapa_maxima_idx` y `cerrado_en` en alta directa | `20260626120000:68-85` |
| `trg_prospectos_cambio_etapa` | prospectos BEFORE UPDATE | `registrar_cambio_etapa()` | si cambia `etapa`: logea actividad `cambio_etapa` con metadata etapa_anterior/nueva, re-scorea INLINE (sin UPDATE re-entrante), resetea reloj y flags SLA, **sella `cerrado_en` una sola vez** y mantiene `etapa_maxima_idx` (cohorte estable) | versión final `20260626120000:35-65` |
| `trg_prospectos_bloquear_reasignacion` | prospectos BEFORE UPDATE | `private.bloquear_reasignacion_asesor()` | si `asesor_id` cambia y el caller es rol asesor → `raise exception` (cierra el hueco que la policy de UPDATE no cubre) | `20260614215235:34-50` |
| `trg_actividades_score` | actividades AFTER INSERT | `trg_actividad_recalcular_score()` | recalcula score del prospecto salvo tipo `cambio_etapa` (anti-reentrancy) | `20260614062237:54-59` |
| `trg_actividades_conversacion` | actividades AFTER INSERT | `trg_actividad_conversacion()` | upsert de `conversaciones` on conflict (prospecto_id): último mensaje, no_leidos, ventana 24h | `20260614063630:47-68` |
| `trg_actividades_cadencia_stop` | actividades AFTER INSERT | `private.trg_cadencia_stop()` | detiene cadencias si el prospecto responde/avanza; además cancela tareas `seguimiento` pendientes | versión final `20260619025319:93-107` |
| `trg_sellar_primera_respuesta` | actividades AFTER INSERT | `private.sellar_primera_respuesta()` | **sellado 1ª respuesta**: si tipo ∈ (whatsapp_enviado, llamada_realizada, llamada_no_contestada) → `update prospectos set primera_respuesta_en = new.creada_en where ... primera_respuesta_en is null` (idempotente) | `20260617064811:13-33` |
| `trg_actividades_cadencia_sin_avance` | actividades AFTER INSERT | `private.trg_cadencia_sin_avance()` | **motor 3-3-7-7 dirigido por eventos** (no cron): sobre cada gestión saliente — si hay cadencia sin_avance activa la avanza (cierra tarea, programa la siguiente o la de "¿descartar?" con `cadencia_fin:true`); si el toque es anticipado reprograma sin avanzar conteo; si no existe, arranca en el 1er contacto salvo que el prospecto ya haya avanzado de etapa; nunca reinicia una completada/detenida; guarda `metadata.mensaje` del paso para prefill de WhatsApp | `20260619025319:114-196`, final `20260619031613:5-81` |
| `trg_cotizaciones_before` | cotizaciones BEFORE INS/UPD | `trg_cotizacion_before()` | numera al ENVIAR (no en borrador, no quema correlativo), fija `vence_en`, re-envío solo desde borrador, prohíbe aceptar vencida | final `20260614081132:107-130` |
| `trg_cotizaciones_after` | cotizaciones AFTER INS/UPD | `trg_cotizacion_after()` | al enviar: actividad `cotizacion_enviada`, mueve `prospectos.etapa` a cotizacion_enviada (guardado contra retrocesos), arranca cadencia; al aceptar/rechazar/vencer: detiene cadencia | final `20260614081132:131-154` (split BEFORE/AFTER por error de FK, `20260614074116`) |
| `trg_citas_defaults` | citas BEFORE INS/UPD | `private.citas_defaults()` | hereda clinica/asesor del prospecto (valida existencia), fallback a usuario actual, autocompleta título, y re-arma recordatorio si cambia `inicia_en` (resetea `recordatorio_enviado_en`) | `20260618042009:35-76`, final `20260625033158:48-89` |
| `trg_citas_a_timeline` | citas AFTER INS/UPD | `private.citas_a_timeline()` | **citas → timeline**: INSERT→`cita_agendada`; cambio de estado→`cita_realizada/cancelada/no_show`; omite recordatorios libres (sin prospecto) y `tipo='seguimiento'` (tareas internas de cadencia, para no auto-detener la cadencia ni meter ruido) | `20260618042009:81-117`, final `20260619025319:64-89` |

Todas las funciones-trigger: `security definer set search_path = ...` fijo + `revoke execute from public, anon, authenticated`.

## 5. Detectores por cron (pg_cron) — 5 jobs

| Job | Frecuencia | Función | Detalle |
|---|---|---|---|
| `sla-15min` | */15 | `private.sla_tick()` | Versión final (`20260625032857:18-84`): warning al `warning_pct` del reloj y breach al vencimiento, destinatario según `accion_breach` (notificar_asesor→asesor; resto→supervisor con fallback asesor; mensaje distinto para staff); **rama `reasignar` = escala el prospecto al supervisor** con guard anti-bucle (`reasignaciones_sla_n < 1`), auditoría en timeline y notificación a ambos. Flags `sla_notif_warning/breach` garantizan una sola notificación. Solo dentro de `en_horario_habil`. |
| `cadencias-15min` | */15 | `private.cadencias_ejecutar()` | Solo cadencias `modo='auto'`; reemplaza `{nombre}/{codigo}/{total}` en la plantilla; registra el toque como actividad con `on conflict do nothing` (idempotencia por `uq_cad_toque`); avanza paso o completa. |
| `cotizaciones-vencer` | 0 * * * * | UPDATE inline | marca `vencida` las enviadas/vistas pasadas de `vence_en` (`20260614081132:157`). |
| `primera-respuesta-2min` | */2 | `private.primera_respuesta_tick()` | notifica lead sin 1ª respuesta pasado el umbral (`configuracion->sla->primera_respuesta_min`, default 5 min); versión final incluye leads parkeados → notifica al supervisor de turno (`20260628120000:121-146`). Reprogramación idempotente del job (`20260617065259:32-37`). |
| `recordatorios-citas` | */5 | `private.enviar_recordatorios_citas()` | recordatorio X min antes (default 60, configurable); idempotente en UNA sentencia: `with due as (update ... returning ...) insert into notificaciones ...` (`20260625033158:19-44`). |

Cadencia de horas hábiles: helpers `private.en_horario_habil / proximo_slot_habil / sumar_horas_habiles` (`20260614073648:4-39`) leen `clinicas.configuracion->horario` (tz America/Lima, bandas lun_vie/sab); default seguro 09-19/09-13 si no hay config (fix `20260614081132:63-76`). `sumar_horas_habiles` avanza en pasos de 15 min contando solo tiempo hábil — así "2 horas hábiles" un sábado 12:50 vence el lunes.

## 6. Enums / estados (todos como CHECK constraints de text, no tipos enum)

- **Pipeline `prospectos.etapa` (7):** `nuevo → contacto_inicial → consulta_agendada → cotizacion_enviada → cirugia_agendada → cerrado_ganado | cerrado_perdido`. Constraint `perdido_requiere_motivo`. La UI relabeló `cirugia_agendada` como "Venta cerrada" sin tocar BD (SCHEMA.md:280-284). Ordinal para cohortes: `private.etapa_idx()` (`20260626120000:20-31`).
- `usuarios.rol` (3), `clinicas.plan` (3), `prospectos.origen` (6), `prospectos.motivo_perdida` (6), `prospectos.sla_estado` (5), `actividades.tipo` (17 final, incl. `reasignacion`), `actividades.origen` (5), `cotizaciones.estado` (6: borrador/enviada/vista/aceptada/rechazada/vencida), `cadencias.evento_disparador` (4), `cadencias.modo` (2), `cadencias_activas.estado` (4), `sla_config.accion_breach` (4), `notificaciones.tipo` (9 final), `citas.tipo` (5), `citas.estado` (4), `lineas_servicio.categoria` (10, clínicas). Patrón de evolución: `drop constraint if exists` + `add constraint` con la lista ampliada.

## 7. Soft-delete vs hard-delete (dato crítico para el destino)

- **Prospectos: soft-delete estricto** — `eliminado boolean default false` + `eliminado_en` + `eliminado_por` (`20260614061134:48-50`). No existe policy DELETE en prospectos (imposible hard-delete desde el cliente). Todas las policies SELECT y los índices filtran `eliminado = false`. La anonimización Ley 29733 también es soft (`eliminado=true`).
- **Cotizaciones: soft-delete** (`eliminado`), sin policy DELETE.
- **Usuarios / clínicas / líneas / cadencias / plantillas: desactivación** `activo/activa = false` (¡la misma convención `activo=false` que exige Avance!).
- **Excepciones**: `citas` SÍ tiene `citas_delete_jerarquia` (hard-delete permitido para clientes, `20260618042009:138-141`); y hubo un hard-delete puntual de datos de prueba (`delete from cotizaciones where eliminado = true`, `20260614072706:16`). Para el CRM Avance: replicar el modelo de prospectos/cotizaciones (sin policy DELETE + flag), no el de citas.
- Convención mixta: VITANOVA usa `eliminado=true` para borrado lógico Y `activo=false` para desactivación. Avance exige unificar en `activo=false`.

## 8. Cómo se inyecta `clinica_id` (resumen del flujo)

1. Alta de usuario → Edge Function `admin-crear-usuario` (service_role) fuerza el `clinica_id` del gerente que llama; o `provisionar_clinica` para el gerente fundador. `seed-users.mjs` además lo respalda en `app_metadata`.
2. Login → hook `custom_access_token_hook` lee `public.usuarios` (con la policy dedicada `auth_admin_lee_usuarios` para `supabase_auth_admin`) e inyecta claims `clinica_id` y `rol`.
3. Query → policies llaman `private.clinica_del_usuario()` que lee el claim (rápido, sin I/O) con fallback a la tabla.
4. Escritura → el cliente DEBE mandar `clinica_id` correcto (WITH CHECK lo valida); en tablas con herencia (citas) el trigger `citas_defaults` lo autocompleta server-side; en ingesta externa lo fija la RPC service_role.

## 9. Patrón de seed y scripts

- `seed.sql` (39 líneas): datos base idempotentes (`on conflict do nothing`) — 1 clínica con UUID fijo `1111...` y configuración jsonb completa + 11 líneas de servicio con tickets del modelo financiero real. Los usuarios NO van por SQL (viven en auth.users).
- `scripts/seed-users.mjs`: crea 7 usuarios demo vía `supabase.auth.admin.createUser` (service_role) + upsert de la fila de perfil `usuarios`; jerarquía demo: 1 gerente, 2 supervisores, 4 asesores (2 por supervisor); password compartida demo.
- `scripts/test-rls.mjs`: **test automatizado de RLS con logins reales por rol usando la ANON key** (no service_role): verifica que gerente ve 7, supervisor ve 3 (él+2), asesor ve 1, y aislamiento entre subárboles de supervisores ("Ana NO ve al equipo de Luis"). Pieza pequeña y muy valiosa.
- Seeds embebidos en migraciones: cadencia default 4 pasos 1/3/7/14 (`20260614073820:140-152`), cadencia sin-avance 3-3-7-7 (`20260619025319:200-213`), SLAs por etapa 2/8/24/48/72h (`20260614074459:136-144`), meta default (`20260614215235:29-31`), límites de cupo (`20260614231225:23-26`) — siempre `insert ... select ... from clinicas on conflict do nothing` (se auto-aplican a cada tenant, patrón per-tenant seeding).
- `APLICAR-TODO.sql`: artefacto legado "pegar en SQL Editor" (solo bloque 1 + seed); superado por las migraciones — NO usar como referencia de estado.

## 10. Migraciones como proceso (metodología transferible)

- Formato `<AAAAMMDDHHMMSS>_<nombre>.sql`, orden ascendente, mismo formato que `supabase db pull`; ledger canónico = `supabase_migrations.schema_migrations` del proyecto.
- `MIGRACIONES.md` = tabla nº/version/nombre/qué-hace de las 30 primeras + instrucciones de sincronización (`supabase migration list` / `db pull`) + deuda técnica anotada.
- Ritmo observable: bloque funcional → hardening (search_path + revokes) → fix de revisión adversarial (p.ej. `20260614081132` corrige WITH CHECK sin rol, doble conteo de KPI, horario default inseguro). Siempre fix-forward, nunca editar migraciones aplicadas. Cambios de policy en caliente vía `ALTER POLICY` (conserva rol/cmd, sin ventana de drop, `20260628120000:85-88`).
- Drift resuelto sin escribir en prod: dump read-only del ledger, renombrado de 8 archivos a su version real, recuperación de 1 migración solo-remoto, snapshot `remote-schema.sql` como referencia autoritativa (SCHEMA.md:350-394). Verificación: 36 policies, 39+ funciones, checks — todo cotejado.
- `remote-schema.sql` no incluye `CREATE TRIGGER` ni cron jobs (limitación de `supabase db dump`) — documentados desde migraciones.

## 11. Otros elementos

- **KPIs** como funciones `SECURITY INVOKER` (RLS scopea solo por rol): `kpi_conversion_cohorte`, `kpi_no_show`, `kpi_tiempo_etapas`, `kpi_ingreso_mes` (`20260614074857`, fix doble conteo `20260614081132:2-17`); grants solo `authenticated`.
- **Realtime**: `alter publication supabase_realtime add table citas / cotizaciones` (`20260625045028`, `20260625050216`) — realtime + RLS jerárquica.
- **Round-robin**: `private.asignar_asesor_round_robin` (menor carga de prospectos abiertos, `20260614063630:71-83`) y espejo `asignar_supervisor_round_robin` (menos parkeados, `20260628120000:15-30`).
- **Correlativo atómico**: `generar_codigo_cotizacion` = upsert `on conflict ... do update set ultimo = ultimo + 1 returning` sobre PK (clinica_id, anio) → `COT-<PREFIJO 3 letras sin acentos>-<año>-<00001>` (`20260614072706:2-13`). UNIQUE ya corregido a `(clinica_id, codigo)` (`20260625054158:5-6`).
- **Edge Functions** (`functions/`): `admin-crear-usuario` (gerente-gated server-side, fuerza clinica_id, prohíbe crear gerente, valida supervisor misma clínica, cuota, rollback), `admin-provisionar-clinica`, `whatsapp-webhook`, `whatsapp-enviar` (staged, pendiente Meta). No se leyeron los cuerpos TS (fuera del alcance de esta tarea: modelo de datos + RLS).

## 12. Mapeo a Avance Corp (síntesis para el sintetizador)

**Transfiere el PATRÓN, no el modelo.** El "esqueleto de seguridad" (helpers private, RLS jerárquica, hook JWT, SECURITY DEFINER + revokes, triggers de negocio en BD, crons idempotentes, migraciones disciplinadas) es 100% backend SQL/Supabase: **React Native/Expo no cambia nada de esto** — supabase-js consume igual desde Expo que desde web (auth, PostgREST, realtime). Lo que NO transfiere por RN es la UI (fuera del alcance de este informe).

**No transfiere el modelo de datos**: prospectos clínicos (dni, diagnostico_referido, consentimiento de tratamiento de datos médicos), lineas_servicio médicas, citas de consulta/cirugía, cotizaciones con IGV, todo el stack WhatsApp/Meta. Avance ya tiene en su portal `clientes`, `contratos`, `cronograma_pagos` — el CRM debe montarse sobre ese dominio.

**Adaptaciones estructurales necesarias:**
1. **Jerarquía 3→4 niveles**: VITANOVA = gerente>supervisor>asesor. Avance = vendedor→supervisor→gerencia→directorio/auditoría. El CTE recursivo de `asesor_ids_visibles` ya soporta cadenas de N niveles sin cambios; lo que falta es el rol `directorio` con visibilidad global READ-ONLY (patrón: rama tipo gerente en el helper para SELECT, pero excluido de todas las policies de INSERT/UPDATE, o policies SELECT dedicadas por rol).
2. **Tenant**: Avance es una sola empresa (no SaaS multi-clínica). Opciones: mantener `empresa_id` por robustez (costo mínimo, el patrón ya está) o simplificar. `provisionar_clinica` y `clinicas.plan` sobran.
3. **Soft-delete**: unificar en `activo=false` (VITANOVA mezcla `eliminado=true` y `activo=false`); replicar "sin policy DELETE" en clientes; NO replicar el DELETE de citas.
4. **Moneda**: VITANOVA es mono-moneda S/ con IGV — Avance necesita PEN/USD por contrato (FALTA).
5. **Escala**: ~5,000 clientes es trivial para este esquema; los índices parciales y de FK ya modelan la práctica correcta.
6. **Notificaciones**: la tabla + RLS por usuario + realtime transfiere; en móvil hay que sumar push Expo (el portal Avance ya tiene `notificar-pagos` y `diagnostico-push` como base) — el detector cron insertando en `notificaciones` puede además disparar push vía webhook/edge.

**Deuda técnica del origen (no copiar):** `APLICAR-TODO.sql` y `_migraciones-locales-previas/` (legados); mezcla de convenciones `actualizado_en`/`actualizada_en` que obligó a dos funciones touch (`20260614060640`) — en Avance definir UNA convención de género desde el día 1; `kpi_ingreso_mes` con `from clinicas limit 1` original (bug multi-tenant, ya corregido) ilustra el riesgo de asumir single-tenant en código multi-tenant.

