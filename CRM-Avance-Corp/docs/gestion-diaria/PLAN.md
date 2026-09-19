# MÓDULO GESTIÓN DIARIA — Planteamiento funcional

**Proyecto:** Portal Avance Corp / MasCapital — CRM comercial
**Fecha:** 18/09/2026
**Estado:** Planteamiento en discusión. No construir hasta cerrar las decisiones pendientes (§7).

---

## 1. Qué problema resuelve

El módulo **Seguimiento** actual no aporta porque la información que muestra no permite decidir nada. La causa no es el módulo: es que la captura de datos no da para más.

La propuesta es eliminar Seguimiento como módulo independiente y absorberlo dentro de un módulo nuevo, **Gestión Diaria**, donde el seguimiento a leads convive con el resto del trabajo del día y recién ahí adquiere contexto.

### Criterio de corte del módulo

> **Gestión Diaria responde una sola pregunta: ¿qué está pasando hoy y qué hay que hacer al respecto ahora?**

Si una vista necesita un selector de rango de fechas para tener sentido, no pertenece a este módulo. Pertenece a Métricas.

---

## 2. Diagnóstico del estado actual (verificado en producción)

### 2.1 Fuente de verdad de llamadas

Toda llamada vive en `crm.actividades` (log inmutable, sin UPDATE ni DELETE para clientes API). Solo existen dos tipos:

| tipo | registros | desde |
|---|---|---|
| `llamada_no_contestada` | 2,704 | 17/08/2026 |
| `llamada_realizada` | 2,185 | 19/08/2026 |
| **total** | **4,889** | |

Campos disponibles por llamada: `lead_id`, `tipo`, `detalle` (texto libre), `metadata` (jsonb), `creado_por`, `creado_en`.

### 2.2 Volumen operativo (últimos 14 días)

~15 analistas activos por día, entre **8 y 24 llamadas por analista**. Volumen suficiente para que un tablero diario sea útil.

| fecha | contestadas | no contestadas | analistas | prom/analista |
|---|---|---|---|---|
| 17/09 | 77 | 84 | 15 | 10.7 |
| 16/09 | 79 | 98 | 14 | 12.6 |
| 15/09 | 100 | 176 | 15 | 18.4 |
| 14/09 | 111 | 150 | 13 | 20.1 |
| 11/09 | 111 | 118 | 15 | 15.3 |
| 07/09 | 154 | 182 | 14 | 24.0 |

### 2.3 Jerarquía — sirve, pero por la vía correcta

- 18 vendedores activos, 3 supervisores, 2 gerencia, 1 coordinador
- **18 de 18 vendedores tienen `supervisor_id` poblado** en `crm.equipo`
- Ningún autor de llamada está fuera de `crm.equipo`

> ⚠️ **No filtrar por `crm.leads.asignado_supervisor_id`.** Está en null en 1,924 de 1,925 leads. Es un hueco de datos conocido. La jerarquía sale de `crm.equipo.supervisor_id`.

### 2.4 Los cuatro huecos estructurales

| # | Hueco | Consecuencia |
|---|---|---|
| 1 | **No hay duración de llamada** | No se puede medir tiempo en línea, AHT, ni descartar llamadas de 10 segundos |
| 2 | **No hay resultado tipificado** | Una llamada contestada no dice qué pasó |
| 3 | **`metadata` 100% vacío** en llamadas | El contenedor existe, nadie escribe ahí |
| 4 | **Todo es autoreporte manual** | Sin integración con central telefónica; el sistema no sabe si la llamada ocurrió |

**Traducción:** hoy el sistema solo puede responder *cuántas veces alguien dijo que llamó y si contestaron*. Nada más.

### 2.5 Calidad del registro — evidencia real

Muestra de las últimas 12 llamadas registradas:

- Lead "Maya Sagraria": marcada como **`llamada_realizada`**, detalle: *"NC LAS LLAMADAS NI LOS MSJS"*. Se registró como contestada una llamada que nadie contestó. **La tasa de contacto actual está contaminada y no se sabe en qué magnitud.**
- Lead "Martin Muñoz": *"PROX. LLAMADA 21-09 EN SEGUIMIENTI"*. El compromiso existe solo como texto libre. **No hay tarea creada.** Nadie puede darle seguimiento salvo leyendo el párrafo.
- Lead "Esaú Ramos": descartado con detalle *"desea prestamo"*. Motivo de descarte real, enterrado en texto libre, no agregable.
- 2 de 12 llamadas sin ningún detalle.

**Global: 1,530 de 4,889 llamadas (31%) tienen `detalle` vacío.**

### 2.6 Campos tipificados que el equipo no usa

`crm.tareas.resultado_reunion` **sí** está tipificado (`interesado`, `propuesta`, `inicia_registro`, `seguimiento`) pero se usó **32 veces de 4,868 tareas (0.7%)**.

> Lección para el diseño: tipificar un campo no basta. Si no es obligatorio en el flujo de cierre, no se llena.

---

## 3. Vista ANALISTA — "Mi día"

No es un tablero de métricas. Es una cola de trabajo. El analista no necesita analizar, necesita saber a quién llamar ahora.

### Bloque 1 — Lo que debo hacer hoy *(ocupa la pantalla)*

Lista ordenada por urgencia, no por fecha:

1. Tareas vencidas (`estado='pendiente'` y `vence_en < now()`) — en rojo, arriba de todo
2. Tareas de hoy, por hora
3. Leads asignados sin ningún intento, con reloj de SLA corriendo (`lead_asignaciones.primera_gestion_limite_en`)
4. Leads propios sin conversación real hace más de X días (`crm.politica_abandono.dias_abandono`)

Cada fila: nombre, teléfono con clic para marcar, etapa, última actividad y hace cuánto, botón de registrar resultado.

### Bloque 2 — Mi marcador de hoy *(una línea, sin gráficos)*

Llamadas hechas · contestadas · tasa de contacto · leads únicos tocados · reuniones agendadas hoy · pendientes que quedan.

Si se define cuota diaria (ver §7.2), aquí va "18 de 30".

### Bloque 3 — Mi seguimiento *(absorbe el módulo Seguimiento actual)*

Leads propios en etapa `contactado` y `propuesta_enviada` con compromiso futuro.

Hoy esos compromisos viven en texto libre y se pierden. Con resultado tipificado, la opción *"volver a llamar"* crea la tarea automáticamente y esta lista se llena sola.

### Alcance
Solo su propia cartera. **No ve** compañeros, rankings ni nada del equipo.

---

## 4. Vista SUPERVISOR — "Mi equipo hoy"

Su trabajo no es mirar números, es detectar quién se está cayendo antes de que termine el día. El tablero se ordena por problema, no por nombre.

### Bloque 1 — Alertas del día *(lo primero, siempre)*

Lista de excepciones, no de personas:

- Analistas sin ninguna llamada registrada hoy *(a las 11am esto es acción inmediata)*
- Analistas con tasa de contacto muy por debajo del equipo
- Tareas vencidas por analista
- SLA de primer intento o primer contacto incumplidos, con nombre y horas de retraso
- Leads parkeados sin dueño (`crm.leads.vendedor_id is null`)

> **Reusar `crm.alertas_reconocimientos`**, ya construido exactamente para esto: reconocer atenúa y descuenta del badge, posponer oculta hasta 7 días máximo, y ambos ceden si el grupo empeora. No armar otro mecanismo.

### Bloque 2 — Tabla de su equipo

Una fila por analista:

llamadas · contestadas · tasa · leads únicos · **ratio llamadas/lead** · primera y última llamada del día · tareas vencidas · reuniones agendadas hoy

> El **ratio llamadas/lead** es la columna más importante y la que nadie pide: delata al analista que marca seis veces al mismo número para levantar su conteo.

Ordenable por cualquier columna.

### Bloque 3 — Drill-down al registro

Clic en un analista → su registro crudo de llamadas con detalle textual completo.

El supervisor necesita poder leer qué escribió, no solo cuánto marcó. Es donde va a encontrar el *"NC LAS LLAMADAS"* marcado como realizada y corregir a la persona el mismo día.

### Alcance
Solo los vendedores donde `crm.equipo.supervisor_id` = él.

---

## 5. Vista GERENCIA — "Toda la operación"

Cuatro niveles de profundidad, con drill-down progresivo.

### Nivel 1 — Pulso del día *(cero clics)*

Franja de números: llamadas totales · contestadas · tasa de contacto · analistas activos vs analistas en roster · leads únicos tocados · reuniones agendadas · conversiones de hoy.

Cada número contra el dato de ayer y contra el promedio de los últimos 7 días laborables.

> El punto de esta franja es una sola pregunta: **¿hoy es un día normal?**

### Nivel 2 — Por equipo

Una fila por supervisor: llamadas del equipo · tasa de contacto · analistas sin actividad · dispersión entre el mejor y el peor de su equipo · SLA incumplidos.

> Aquí gerencia identifica al **supervisor** con el problema, no al vendedor. Es la capa que hoy no existe en ningún lado.

### Nivel 3 — Por analista

Clic en un supervisor → baja a la tabla de su equipo.

> **Es el mismo componente del Bloque 2 del supervisor.** No construirlo dos veces.

### Nivel 4 — Registro crudo

Clic en un analista → toda su actividad sin agregar: hora exacta, lead, etapa del lead en ese momento, tipo, detalle íntegro.

Filtros: rango de fechas, equipo, analista, tipo, etapa. Exportable.

> Este nivel es el que cumple el requisito de "ver absolutamente todo". También es donde gerencia va a ver por sí misma la calidad real del registro.

### Alcance
Global, sin filtro de jerarquía. Selector de fecha/rango aplicable a los cuatro niveles.

---

## 6. Qué NO entra en este módulo

Va a **Métricas / Reportes**, módulo aparte:

- Embudo del mes y conversión mensual
- Tendencias de semanas o meses
- Comparativos contra meta mensual
- Ranking acumulado de analistas
- Exportables para análisis de período
- Cumplimiento de cuota del período

Ya existen piezas construidas para ese lado: `metricas_agenda_fn`, `metricas_vendedores_fn`, `cierre_mes_vendedor`, `metas_vendedor` / `metas_vendedor_detalle`. No mezclarlas con la operación diaria.

### Componente compartido entre ambos módulos

El **registro crudo de actividad** (hora · lead · analista · tipo · detalle) es la misma tabla `crm.actividades` y debe ser **un solo componente** con dos entradas:

- Desde Gestión Diaria → filtrado a hoy, para actuar
- Desde Métricas → rango libre y exportable, para analizar

> Construirlo dos veces produce dos definiciones de "llamada" — exactamente el problema que se está migrando en el resto del sistema con la capa semántica.

### Estructura resultante

```
GESTIÓN DIARIA  (nuevo)
├── Vista analista    → cola del día + marcador + seguimiento
├── Vista supervisor  → alertas + equipo hoy + drill-down
└── Vista gerencia    → pulso + equipos + analistas + registro crudo

MÉTRICAS  (existente, se ordena después)
└── todo lo que necesita rango de fechas

[componente compartido: registro crudo de actividad]
```

Un módulo, alcance por `rol_crm`, un componente de registro compartido.

---

## 7. Decisiones pendientes — bloquean la construcción

### 7.1 🔴 Lista cerrada de resultados de llamada *(bloqueante)*

Es lo único que convierte los tres tableros de contadores de marcaciones en gestión real. Sin esto, el módulo nuevo repite el problema del módulo viejo.

Propuesta basada en lo que los analistas ya escriben en texto libre:

| Resultado | Efecto en el sistema |
|---|---|
| No contestó | — |
| Contestó, volver a llamar | **Crea tarea con fecha obligatoria** |
| Contestó, agendó reunión | Crea tarea tipo `reunion`, mueve etapa |
| Contestó, no interesado | Requiere submotivo, alimenta descarte |
| Número errado | Marca el teléfono |
| No es la persona | Marca el teléfono |
| Pide otro producto (préstamo, etc.) | Submotivo de descarte agregable |

**Pendiente:** confirmar, quitar o agregar opciones.

> Nota de diseño: hacerlo **obligatorio al cerrar la llamada**, no opcional. `resultado_reunion` demuestra que un campo tipificado opcional se llena el 0.7% de las veces.

### 7.2 🟡 ¿Existe cuota diaria de llamadas por analista?

Si existe, hay que crear dónde guardarla. Hoy no está en el sistema. Sin ella no se puede pintar "meta vs real" en ninguna de las tres vistas.

### 7.3 🟡 ¿El supervisor ve el detalle textual de las llamadas de su equipo?

**Recomendación: sí.** Sin eso no puede corregir calidad de registro. Pero es decisión de negocio y cambia el diseño del Bloque 3 del supervisor.

---

## 8. Límites a comunicar a gerencia antes de entregar

Ser explícito sobre esto ahora evita una conversación incómoda en el mes 2:

| Lo que gerencia va a pedir | Estado real |
|---|---|
| Duración de llamada | ❌ No existe el dato. Requiere central telefónica integrada |
| Grabaciones | ❌ No existen |
| Resultado tipificado | ⚠️ No existe hoy — resoluble esta semana (§7.1) |
| Motivo real del descarte | ⚠️ En texto libre, no agregable |
| Verificación de que la llamada ocurrió | ❌ Todo es autoreporte |

De los cinco, **el único resoluble sin comprar nada es el resultado tipificado**, y es el que desbloquea todo lo demás.

---

## 9. Reglas técnicas que aplican a todo el módulo

- Toda comparación de fecha usa `(columna at time zone 'America/Lima')::date`
- Jerarquía por `crm.equipo.supervisor_id`, nunca por `crm.leads.asignado_supervisor_id`
- Lectura de llamadas contra `crm.actividades`, sin crear una segunda definición
- Alcance por rol resuelto en una única capa de autorización, no repartido por pantalla
- Diseño Avance Corp: navy `#111e3d`, azul `#2563eb`, fondo blanco, Plus Jakarta Sans, tema claro

---

## 10. Próximo paso

Cerrar **§7.1** (lista de resultados de llamada). Con eso definido se arma el planteamiento funcional detallado y recién ahí se pasa a prompt numerado para Claude Code sobre rama de base de datos.

---

## 11. Decisiones cerradas (19/09/2026)

| # | Decisión | Estado |
|---|---|---|
| 7.1 | Lista cerrada de resultados de llamada — la propuesta de §7.1, obligatoria al cerrar la llamada | Aprobada vía mockup `5-analista-registrar-resultado.html` |
| 7.2 | Cuota diaria de llamadas | **Abierta.** Fuera de alcance de la v1; no se construye "meta vs real" |
| 7.3 | El supervisor ve el detalle textual de su equipo | Sí (mockup 3 → registro) |
| — | Alerta de SLA de primer contacto en la vista del supervisor | **Eliminada** por decisión de Miguel |
| — | Playbook UI-UX (`UI-UX-playbook.pdf`) | Norma de diseño del módulo |

## 12. Hallazgo técnico que condiciona §7.1

Verificado en producción el 19/09:

- `crm.actividades.tipo` tiene CHECK con 9 valores. Solo existen `llamada_realizada` y `llamada_no_contestada` para llamadas.
- `llamada_realizada` dispara `trg_zz_actividades_avance_etapa` (avanza la etapa del lead) y `trg_zy_actividades_sla_versionado` (sella primer contacto efectivo).
- Por lo tanto **"Número errado" y "No es la persona" NO pueden grabarse como `llamada_realizada`**: moverían el lead a `contactado` y sellarían un contacto que no ocurrió.
- `crm.registrar_actividad_v2(p_operacion_id, p_lead_id, p_tipo, p_detalle, p_siguiente)` ya acepta `p_siguiente jsonb` para crear la próxima tarea. "Volver a llamar" puede usar ese mecanismo existente.
- `metadata jsonb` existe y está 100% vacío en llamadas: es el lugar natural para el resultado tipificado, sin tocar el CHECK de `tipo`.

## 13. Fidelidad de los datos en los mockups

Reales (producción 18/09, 13:02): llamadas, contestadas, tasas por analista y equipo, leads únicos, ratios, horas de primera y última llamada, analistas sin actividad, textos del registro crudo, 735 tareas vencidas globales, 8 reuniones, 3 conversiones, 3 leads parkeados.

**Ilustrativos (no usar como fixtures ni como verdad):** tareas vencidas por analista y por equipo (31, 18, 112…), "rango normal 42–52 %", "promedio 7 días 47,3 %", "cartera de 47 leads", "11 compromisos", apellidos agregados a leads (Quispe, Malpartida, Salcedo), fechas de "Mi seguimiento", y el toast/alerta de reasignación.
