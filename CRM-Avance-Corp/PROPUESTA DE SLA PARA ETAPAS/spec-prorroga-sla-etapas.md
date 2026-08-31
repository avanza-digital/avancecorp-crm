# Prórroga y pausa de SLA por etapa — Especificación de desarrollo

**Proyecto:** CRM Comercial · Avance Corp
**Producción:** `dctqcbznekcyxhjujuci` · **Branch:** `irzyttvonpboyaxyuxvc`
**Prompts:** P-050 a P-054
**Estado de partida:** política SLA v5 vigente · 277 etapas abiertas vencidas

---

## 1. Problema

Un solo reloj responde dos preguntas distintas y por eso falla en ambas:

| Pregunta | Métrica correcta | Quién la consume |
|---|---|---|
| ¿El asesor está trabajando el lead? | Tiempo desde la última gestión | Asesor |
| ¿El lead está avanzando en el pipeline? | Tiempo en la etapa, sin reinicios | Supervisor / Gerencia |

Hoy `crm.lead_sla_etapas.limite_en` intenta responder las dos. El resultado medido en producción:

| Etapa | Vencidas | Con gestión efectiva posterior | Solo intentos | Con tarea pendiente |
|---|---|---|---|---|
| contactado | 162 | 132 | 17 | 143 |
| nuevo | 96 | 0 | 81 | 81 |
| reunion_agendada | 16 | 5 | 2 | 15 |
| propuesta_enviada | 3 | 1 | 1 | 3 |
| **Total** | **277** | **138** | **101** | **242** |

Dos lecturas que dirigen el diseño:

1. **En `contactado`, 132 de 162 tienen gestión efectiva posterior al inicio de la etapa.** Es el falso positivo que reporta el equipo.
2. **En `nuevo`, cero tienen gestión efectiva** — por definición, porque un contacto efectivo dispara `trg_zz_actividades_avance_etapa` y avanza la etapa. Los 81 son `llamada_no_contestada` y `whatsapp_enviado`. Si esos prorrogaran, el SLA deja de medir: `llamada_no_contestada` es el tipo de actividad con más volumen del sistema (656 registros contra 563 de `llamada_realizada`).
3. **242 de 277 tienen tarea pendiente.** La pausa por compromiso agendado cubre el 87% del problema sin necesidad de prórroga.

---

## 2. Restricciones verificadas en producción

Estas son hechos del esquema actual, no supuestos. El diseño se construye alrededor de ellas.

### R1 — `crm.lead_sla_etapas` es inmutable salvo para cerrar

`private.trg_lead_sla_etapas_guard` bloquea `DELETE`, y en `UPDATE` solo permite escribir `finalizado_en` + `motivo_cierre` sobre una fila abierta. `limite_en`, `iniciado_en`, `etapa`, `politica_id` y `episodio_n` son inmutables.

**Consecuencia: no se puede modificar `limite_en`.** El nuevo límite se calcula, no se escribe. No hay que tocar el guard.

### R2 — Solo `crm.leads` escribe en las tablas SLA

El guard exige `current_setting('crm.sla_writer')='on'` **y** `pg_trigger_depth()>=2`. El único writer es `private.trg_leads_sla_versionado`, disparado por `trg_leads_02_sla_versionado` sobre `crm.leads`.

**Consecuencia:** la tabla nueva de ajustes replica ese patrón con su propio guard, y se escribe desde un trigger sobre `crm.actividades`.

### R3 — Las tablas SLA son deny-all bajo RLS

`lead_sla_etapas`, `lead_sla_ciclos` y `lead_asignacion_sla_hitos` tienen `relrowsecurity = true` y **cero policies**. Se leen exclusivamente por RPC `SECURITY DEFINER` (`crm.estado_sla_leads_fn`).

**Consecuencia:** la tabla nueva va igual — RLS activo, sin policies. Nada la lee directo desde el cliente.

### R4 — `crm.publicar_politica_sla` valida con lista blanca estricta

```sql
or (p_config - array['zona_horaria','tipo_reloj','primera_gestion_minutos',
                     'primer_contacto_minutos','etapas']) <> '{}'::jsonb
```

Cualquier clave nueva en `p_config` levanta excepción. Lo mismo por etapa: solo se aceptan `etapa` y `maximo_minutos`. Además hardcodea `tipo_reloj <> 'corrido'` → error, y `jsonb_array_length(etapas) <> 4` → error.

**Consecuencia: sin modificar este RPC no se puede publicar una política con parámetros de prórroga.** Es bloqueante y va en P-052.

### R5 — La gestión por lead ya está serializada

`private.trg_gestion_lead_serializada` (BEFORE INSERT en `crm.actividades`) toma `FOR UPDATE` sobre la fila de `crm.leads`. Dos actividades simultáneas sobre el mismo lead se serializan.

**Consecuencia:** el conteo de prórrogas consumidas no necesita advisory lock propio. La unicidad se refuerza igual con constraint por defensa en profundidad.

### R6 — Orden de triggers AFTER INSERT en `crm.actividades`

Postgres los dispara alfabéticamente:

```
trg_audit_actividades
trg_zy_actividades_sla_versionado
trg_zz_actividades_avance_etapa      ← puede avanzar nuevo → contactado
```

**Consecuencia:** el trigger de prórroga debe llamarse `trg_zzz_actividades_prorroga_sla` para correr al final. Si corriera antes, prorrogaría una etapa `nuevo` que el trigger siguiente va a cerrar.

---

## 3. Decisión de arquitectura

| Mecanismo | Se almacena | Motivo |
|---|---|---|
| **Prórroga** | Sí, tabla append-only | Consume presupuesto finito. Debe ser contable, idempotente y auditable. |
| **Pausa** | No, se calcula al leer | Es un estado derivado de `crm.tareas`, que ya está auditada por `trg_audit_tareas`. Materializarla crea una segunda fuente de verdad que se desincroniza al reprogramar. |

**`iniciado_en` nunca se toca.** La métrica de estancamiento (`now() - iniciado_en` contra `maximo_minutos` crudo) sobrevive intacta. Prórroga y pausa afectan solo la alerta del asesor, nunca la salud del pipeline.

---

## 4. Fórmula del límite efectivo

```
limite_prorrogado = e.limite_en + coalesce(sum(ajustes.minutos), 0)

limite_pausa      = case when pausa_habilitada and existe tarea pendiente futura
                         then max(t.vence_en) + pausa_margen_minutos
                         else null end

techo             = e.iniciado_en + tope_absoluto_minutos

limite_efectivo   = least(
                      greatest(limite_prorrogado, coalesce(limite_pausa, limite_prorrogado)),
                      techo
                    )

vencida_efectiva  = now() > limite_efectivo
estancada         = now() > e.iniciado_en + maximo_minutos     -- sin prórroga ni pausa
```

El `least(..., techo)` es lo que impide que una tarea agendada a 60 días congele el reloj. Nada cruza el techo absoluto.

**Tarea pendiente futura** se define como: `activo = true` y `estado = 'pendiente'` y `vence_en > now()` y `lead_id = e.lead_id`.

---

## 5. Reglas de negocio

### Qué prorroga

Solo tipos que prueban respuesta del cliente:

- `llamada_realizada`
- `whatsapp_recibido`
- `reunion_realizada`

### Qué NO prorroga

- `llamada_no_contestada` — demuestra esfuerzo, no interés. 656 registros. Si contara, cualquier lead muerto se sostiene marcando tres veces por semana.
- `whatsapp_enviado` — mismo caso.
- `cambio_etapa`, `reasignacion`, `conversion`, `nota` — eventos de sistema o notas, no gestión con el cliente.

### Cuándo no se aplica prórroga aunque el tipo califique

1. `prorroga_max = 0` para esa etapa en la política de la etapa.
2. Ya se consumieron `prorroga_max` prórrogas en esa fila de etapa.
3. `e.iniciado_en >= creado_en de la actividad` — la etapa nació después de la actividad (caso `nuevo → contactado`: la actividad ya avanzó la etapa, la fila nueva viene con reloj limpio).
4. La actividad ya generó un ajuste sobre esa etapa (unicidad).
5. No hay etapa abierta para el lead.

### Parámetros propuestos para política v6

| Etapa | maximo | prórroga | máx. | techo | pausa | margen |
|---|---|---|---|---|---|---|
| nuevo | 1440 (1d) | — | 0 | 4320 (3d) | sí | 240 (4h) |
| contactado | 11520 (8d) | 5760 (4d) | 2 | 23040 (16d) | sí | 1440 (1d) |
| reunion_agendada | 21600 (15d) | — | 0 | 25920 (18d) | sí | 2880 (2d) |
| propuesta_enviada | 28800 (20d) | 10080 (7d) | 1 | 38880 (27d) | sí | 1440 (1d) |

`nuevo` no lleva prórroga porque un contacto efectivo ya avanza la etapa solo; si el cliente no contesta, el camino correcto es agendar el reintento y que la pausa lo cubra.

`reunion_agendada` tampoco: la reunión ya tiene fecha, para eso está la pausa. El techo de 18 días le da margen a una reprogramación.

---

## 6. Cambios por objeto

### 6.1 Columnas nuevas en `crm.sla_politica_etapas`

```sql
prorroga_minutos        integer   not null default 0
prorroga_max            smallint  not null default 0
tope_absoluto_minutos   integer   not null default 0
tipos_gestion_prorroga  text[]    not null default '{}'::text[]
pausa_habilitada        boolean   not null default false
pausa_margen_minutos    integer   not null default 0
```

Constraints:

- `prorroga_minutos between 0 and 43200`
- `prorroga_max between 0 and 5`
- `tope_absoluto_minutos >= maximo_minutos`
- `(prorroga_max = 0) = (prorroga_minutos = 0)` — coherencia
- `(prorroga_max = 0) or (cardinality(tipos_gestion_prorroga) > 0)`
- `tipos_gestion_prorroga <@ array['llamada_realizada','whatsapp_recibido','reunion_realizada']`
- `pausa_margen_minutos between 0 and 10080`
- `(pausa_habilitada) or (pausa_margen_minutos = 0)`

**Backfill obligatorio de las 5 versiones existentes:** `tope_absoluto_minutos := maximo_minutos`, resto en default. Con eso las políticas v1–v5 reproducen exactamente el comportamiento actual y **no se reescribe historia**. El cambio de conducta llega únicamente al publicar v6.

### 6.2 Tabla nueva `crm.lead_sla_etapa_ajustes`

```sql
create table crm.lead_sla_etapa_ajustes (
  id                  uuid primary key default gen_random_uuid(),
  etapa_sla_id        uuid not null references crm.lead_sla_etapas(id),
  lead_id             uuid not null references crm.leads(id),
  tipo                text not null,
  origen_actividad_id uuid references crm.actividades(id),
  minutos             integer not null,
  limite_antes        timestamptz not null,
  limite_despues      timestamptz not null,
  politica_id         uuid not null references crm.sla_politicas(id),
  secuencia           smallint not null,
  creado_por          uuid,
  creado_en           timestamptz not null default statement_timestamp()
);

alter table crm.lead_sla_etapa_ajustes enable row level security;
-- sin policies: deny-all, se lee solo por RPC SECURITY DEFINER (R3)
```

Constraints e índices:

- `check (tipo = 'prorroga')` — se deja el campo para admitir tipos futuros sin migración de esquema
- `check (minutos > 0)`
- `check (limite_despues > limite_antes)`
- `check (secuencia >= 1)`
- `unique (etapa_sla_id, origen_actividad_id)` — idempotencia por actividad
- `unique (etapa_sla_id, secuencia)`
- `index on (etapa_sla_id)`
- `index on (lead_id)`

`lead_id` está desnormalizado a propósito: la RPC de lectura agrega por lead y evitar el join a `lead_sla_etapas` en el agregado importa con 1.258 filas y creciendo.

### 6.3 Guard `private.trg_lead_sla_etapa_ajustes_guard`

Espeja `trg_lead_sla_etapas_guard`:

- `DELETE` → excepción `55000`
- `UPDATE` → excepción `55000` (append-only puro, ni siquiera cierre)
- `INSERT` → exige `current_setting('crm.sla_writer','on')` y `pg_trigger_depth() >= 2`

Trigger: `BEFORE INSERT OR UPDATE OR DELETE ... FOR EACH ROW`.

Añadir también `trg_audit_lead_sla_etapa_ajustes AFTER INSERT ... EXECUTE FUNCTION private.log_audit_crm()` para consistencia con el resto del esquema SLA.

### 6.4 Trigger `private.trg_actividades_prorroga_sla`

```
CREATE TRIGGER trg_zzz_actividades_prorroga_sla
AFTER INSERT ON crm.actividades
FOR EACH ROW
WHEN (new.tipo = ANY (ARRAY['llamada_realizada','whatsapp_recibido','reunion_realizada']))
EXECUTE FUNCTION private.trg_actividades_prorroga_sla();
```

Nombre `zzz` obligatorio por R6. Función `SECURITY DEFINER`, `SET search_path TO 'pg_catalog'`, retorna `null`.

Lógica:

1. Guarda de reentrada: si `current_setting('crm.avance_auto') = 'on'`, salir. Mismo patrón que `trg_actividades_avance_etapa`.
2. Salir si `new.lead_id is null`.
3. Defensa repetida del filtro de tipos (por si alguien recrea el trigger sin el `WHEN`).
4. Localizar la etapa abierta: `lead_sla_etapas` donde `lead_id = new.lead_id`, `ciclo_n = leads.ciclo_actual`, `finalizado_en is null`. Si no hay, salir.
5. Salir si `e.iniciado_en >= new.creado_en` (regla 3 de §5).
6. Leer la regla desde `crm.sla_politica_etapas` con `politica_id = e.politica_id` y `etapa = e.etapa`. **La política de la etapa, no la vigente** — así una etapa abierta bajo v5 no cambia de reglas a mitad de camino cuando se publique v6.
7. Salir si `prorroga_max = 0` o `new.tipo <> all(tipos_gestion_prorroga)`.
8. Contar ajustes existentes de esa etapa. Salir si `>= prorroga_max`.
9. Calcular `limite_antes` (límite prorrogado actual) y `limite_despues = least(limite_antes + prorroga_minutos, e.iniciado_en + tope_absoluto_minutos)`. Salir si no hay ganancia (`limite_despues <= limite_antes`) — el techo ya está tocado.
10. `set_config('crm.sla_writer','on',true)` → insert → `set_config('crm.sla_writer','off',true)`.
11. `creado_por := new.creado_por`.

El `set_config` en `true` es local a la transacción, igual que en el resto del esquema.

### 6.5 Función de lectura `private.sla_estado_etapa_efectivo`

`STABLE`, `SECURITY DEFINER`, `search_path` vacío. Recibe `p_lead_ids uuid[]` y devuelve por lead:

```
lead_id, etapa_sla_id, limite_base, minutos_prorrogados, prorrogas_usadas,
prorrogas_disponibles, pausado_hasta, limite_efectivo, techo,
vencida_efectiva, estancada, minutos_sin_gestion
```

`minutos_sin_gestion` = minutos desde la última actividad de cualquier tipo de gestión (los 5, incluidos intentos) sobre el lead. Es la métrica que alimenta la alerta del asesor y no requiere tabla nueva.

### 6.6 `crm.estado_sla_leads_fn` v2

**Cambia el tipo de retorno, así que requiere `DROP FUNCTION` + `CREATE FUNCTION`, no `CREATE OR REPLACE`.** Este es exactamente el patrón que rompe el diff de Supabase al mergear branch. Ver §8.

Campos nuevos a añadir al `RETURNS TABLE` existente:

```
etapa_limite_efectivo_en     timestamptz
etapa_minutos_prorrogados    integer
etapa_prorrogas_usadas       smallint
etapa_prorrogas_disponibles  smallint
etapa_pausado_hasta          timestamptz
etapa_techo_en               timestamptz
etapa_vencida_efectiva       boolean
etapa_estancada              boolean
lead_minutos_sin_gestion     integer
```

Se conserva `etapa_limite_en` sin cambios para no romper el frontend actual durante el despliegue.

### 6.7 `crm.publicar_politica_sla` v2

Bloqueante por R4. Cambios:

- Ampliar la lista blanca de `p_config` — sin claves nuevas de nivel raíz por ahora.
- Ampliar la lista blanca por etapa a: `etapa`, `maximo_minutos`, `prorroga_minutos`, `prorroga_max`, `tope_absoluto_minutos`, `tipos_gestion_prorroga`, `pausa_habilitada`, `pausa_margen_minutos`.
- Todas las claves nuevas **opcionales** con default neutro, para que un payload viejo siga publicando una política válida de comportamiento actual.
- Validar rangos en el RPC, no solo por constraint: mismo criterio defensivo del resto de la función.
- Validar `tipos_gestion_prorroga` como array de strings dentro del conjunto permitido.
- Mantener intacto el control de concurrencia (`pg_advisory_xact_lock` + `expected_version`).

**No tocar** la restricción `tipo_reloj = 'corrido'` en este alcance. El reloj hábil es una decisión aparte (§9).

### 6.8 `crm.configuracion_sla_fn` v2

Subir el envelope de `'version', 1` a `'version', 2` y agregar los seis campos nuevos por etapa. El frontend de gerencia debe leer la versión del envelope antes de renderizar el formulario.

### 6.9 Frontend

Reemplazar el badge único de vencimiento por dos indicadores con audiencias separadas:

| Indicador | Fuente | Se ve en |
|---|---|---|
| **Sin gestión** | `lead_minutos_sin_gestion` contra `limite_efectivo` | Bandeja del asesor |
| **Estancado** | `etapa_estancada` | Tablero de supervisor y gerencia |

En la ficha del lead, cuando hay prórroga o pausa activa, mostrar el motivo: *"Plazo extendido por gestión del 14/08 · 1 de 2 disponibles"* o *"En pausa hasta el 20/08 por reunión agendada"*. Sin ese texto el asesor no entiende por qué el plazo se movió y pierde confianza en el indicador.

---

## 7. Fases

Todo en branch `irzyttvonpboyaxyuxvc`. Nada directo a producción. Merge manual desde el dashboard.

### P-050 — Modelo

**Alcance:** columnas en `sla_politica_etapas` + backfill neutro de v1–v5 + tabla `lead_sla_etapa_ajustes` + guard + trigger de auditoría.

**Verificación previa a declarar:** listado de constraints creados y su definición.

**Aceptación:**
- `select count(*) from crm.sla_politica_etapas where tope_absoluto_minutos < maximo_minutos` → 0
- Insert directo en `lead_sla_etapa_ajustes` desde `execute_sql` → excepción `42501`
- `delete` sobre la tabla → excepción `55000`
- `update` sobre la tabla → excepción `55000`
- `crm.estado_sla_leads_fn()` devuelve exactamente los mismos valores que antes de la migración

### P-051 — Motor

**Alcance:** `private.trg_actividades_prorroga_sla` + trigger `trg_zzz_...` + `private.sla_estado_etapa_efectivo`.

**Verificación previa a declarar:** confirmar por `pg_trigger` que el orden de disparo AFTER INSERT en `crm.actividades` queda `audit → zy → zz → zzz`.

**Aceptación** (con política de prueba en el branch: `contactado` con prórroga 5760 / máx 2 / techo 23040):
- Lead en `contactado`, insertar `llamada_realizada` → 1 ajuste, `limite_efectivo = limite_en + 4d`
- Repetir → 2 ajustes
- Repetir una tercera vez → 0 ajustes nuevos, presupuesto agotado
- Insertar `llamada_no_contestada` → 0 ajustes
- Insertar `whatsapp_enviado` → 0 ajustes
- Lead en `nuevo`, insertar `llamada_realizada` → avanza a `contactado`, se cierra la fila `nuevo`, **0 ajustes** sobre la fila nueva
- Etapa con techo ya alcanzado → 0 ajustes, sin error
- Reintentar la misma `actividad_id` → violación de unicidad, no fila duplicada

Para datos de prueba con timestamps retrocedidos: insertar en estado inicial válido y luego actualizar, con `SET LOCAL session_replication_role = replica` dentro de transacción. Solo en branch.

### P-052 — Lectura y publicación

**Alcance:** `estado_sla_leads_fn` v2 (drop + create), `configuracion_sla_fn` v2, `publicar_politica_sla` v2.

**Aceptación:**
- Publicar con payload viejo (sin claves nuevas) → política válida, comportamiento idéntico al actual
- Publicar con clave desconocida → excepción `22023`
- Publicar con `prorroga_max = 3` y `tipos_gestion_prorroga = ['llamada_no_contestada']` → excepción
- `expected_version` desactualizado → excepción `40001`
- `configuracion_sla_fn` devuelve `version = 2` con los seis campos por etapa

### P-053 — Frontend

**Alcance:** separación de indicadores, texto explicativo de prórroga y pausa, formulario de gerencia para los parámetros nuevos.

**Aceptación:** con la política v5 sin prórrogas, la bandeja muestra exactamente los mismos 277 casos que hoy. El cambio visual no altera datos.

### P-054 — Publicación de v6 y verificación

**Alcance:** publicar la política v6 con los números de §5 y medir el efecto real.

**Aceptación:** consulta comparativa antes/después sobre las etapas abiertas:

```sql
-- vencidas efectivas por etapa, contra el baseline de 277
select etapa,
       count(*) filter (where vencida_efectiva) as vencidas_efectivas,
       count(*) filter (where estancada)        as estancadas
from ... group by etapa;
```

**Importante:** v6 solo rige para etapas que **inicien** después de `vigente_desde`. Las 277 abiertas siguen bajo la política con la que nacieron (§6.4 punto 6). El efecto se ve conforme rotan las etapas, no de golpe. Si se quisiera efecto inmediato haría falta un recálculo explícito, que **no está en este alcance** y reescribiría el criterio de evaluación de gestiones ya hechas.

---

## 8. Riesgos y trampas de este esquema

| # | Riesgo | Mitigación |
|---|---|---|
| 1 | `estado_sla_leads_fn` cambia firma → el diff de Supabase genera `CREATE FUNCTION` sin `OR REPLACE` y el merge falla | Patrón conocido: aplicar por `apply_migration` directo con el project_id de producción y borrar el branch. Dejar P-052 aislado en su propia migración para acotar el blast radius. |
| 2 | El trigger de prórroga corre antes que `avance_etapa` y prorroga una etapa condenada | Nombre `trg_zzz_` verificado contra `pg_trigger` en P-051 |
| 3 | Leer la política vigente en vez de la política de la etapa cambia las reglas a mitad de etapa | §6.4 punto 6: siempre `e.politica_id` |
| 4 | La pausa se calcula sobre `crm.tareas` y un asesor reprograma indefinidamente | El techo absoluto en `least()` corta. Además `tareas.reprogramaciones` ya cuenta; considerar alerta de supervisor a partir de 3. |
| 5 | Dos actividades simultáneas consumen la misma prórroga | Serialización por `FOR UPDATE` en R5 + `unique (etapa_sla_id, secuencia)` |
| 6 | El backfill de v1–v5 con `tope = maximo` deja pausa deshabilitada, y una etapa abierta bajo v5 nunca pausa | Correcto y buscado: sin reescritura de historia. Se acepta que el alivio llegue con la rotación. |
| 7 | `estado_sla_leads_fn` hace `left join lead_sla_etapas ... finalizado_en is null` sin filtrar `episodio_n`; dos filas abiertas duplicarían el lead | El invariante lo sostiene `trg_leads_sla_versionado`, que cierra todas las abiertas antes de insertar. Añadir en P-052 un `select` de verificación: cero leads con más de una etapa abierta. |

---

## 9. Decisiones pendientes

1. **Números finales de §5.** Los propuestos son una base razonable; el que manda es el criterio comercial.
2. **Reloj hábil.** `sla_politicas.tipo_reloj` existe pero las 5 versiones están en `corrido`, y `publicar_politica_sla` lo hardcodea. Con `nuevo` en 24 horas corridas, un lead que entra viernes 6pm vence el sábado. Cambiarlo eliminaría un bloque de vencimientos falsos sin lógica de prórroga de por medio, pero implica calendario laboral, feriados peruanos y reescribir todos los cálculos de límite. **Alcance propio, no entra aquí.** Vale evaluarlo antes de invertir en afinar los números de prórroga.
3. **Umbral de reprogramaciones** que dispara alerta de supervisor (riesgo 4).
4. **Qué pasa al agotar el presupuesto.** La propuesta es que el lead entre al tablero del supervisor como decisión: liberar a bolsa, reasignar o descartar. Eso conecta con P-049, que ya está en cola. Conviene definir si es la misma bandeja o una distinta.
