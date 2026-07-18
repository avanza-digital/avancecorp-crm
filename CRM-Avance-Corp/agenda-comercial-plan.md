# Agenda del vendedor — Investigación + Plan de diseño (fase por fase)

CRM multi-vendedor para pymes · WhatsApp-first · Supabase + React
Complementa el apartado **HOY** sin duplicarlo.

---

## 0. Idea central (léela primero)

Una agenda comercial fuerte **no es un calendario**. Es un **motor de "próxima acción"**.
La regla de oro de los vendedores que cierran: **ningún prospecto activo puede quedar sin una acción futura agendada.** Todo lo demás (vistas bonitas, colores, sincronización) es secundario a esto.

Los datos lo respaldan: la mayoría de vendedores abandona un lead tras 1-2 intentos, pero cerrar suele exigir **5 a 8 toques**. El vendedor que tiene su agenda llena de seguimientos programados le gana al que "se acuerda" de hacerlos. Tu agenda tiene que forzar ese hábito, no solo mostrar horas.

Segundo dato incómodo: el vendedor gasta cerca del **60% de su tiempo en tareas que no son vender**. Cada clic que le ahorres (llamar, escribir por WhatsApp, agendar el siguiente paso) es tiempo de venta recuperado. La agenda se diseña para **reducir fricción**, no para lucir completa.

---

## 1. Mejores prácticas (lo que la investigación confirma)

**Venta basada en actividad.** No controlas el resultado de una venta, sí controlas cuántas actividades haces. Pipedrive construyó todo su CRM sobre esto: cada trato debe tener siempre una actividad pendiente. Copiá ese principio.

**Cadencia de seguimiento (números concretos):**

| Momento | Espaciado entre toques |
|---|---|
| Lead entrante | Responder en < 1 hora (mismo día como mínimo) |
| Inicio del ciclo | Cada 2-3 días |
| Ciclo avanzado | Cada 4-7 días |
| Después de una reunión | Resumen + siguiente paso en < 24 h |
| Total antes de dar por perdido | 5-8 toques mínimo |

**Cerrar toda interacción con la siguiente acción agendada.** Nunca cuelgues una llamada ni cierres un chat sin fecha y hora del próximo contacto ya metida en la agenda. Este es el comportamiento que tu producto debe volver casi obligatorio.

**Time-blocking (bloques de tiempo).** Los mejores vendedores no agendan tareas sueltas, agendan **bloques por categoría** de 60-90 min: "prospección 8:30-10", "seguimientos 11-12", "admin/CRM al final del día". La mañana se protege "como si fuera facturación": es cuando ubicas a la gente antes de que se les llene el día.

**Ritmo semanal.** Martes a jueves por la mañana concentran la mayoría de reuniones agendadas. El viernes rinde poco para prospectar: se usa para limpiar pipeline y planificar la semana siguiente. Tu agenda puede sugerir esto.

**Anti no-show.** Los recordatorios multi-toque (al vendedor y al cliente) reducen las citas caídas. En Perú eso significa recordatorio por **WhatsApp** al cliente, no email.

**WhatsApp-first (Perú/LATAM).** El vendedor peruano vende por WhatsApp y llamada, casi nunca por correo frío. La agenda debe tener el WhatsApp del prospecto a un toque de distancia (click-to-chat con plantilla), no escondido en la ficha.

---

## 2. HOY vs. AGENDA — cómo se dividen sin pisarse

Ya tenés **HOY**. La clave para que no choque con Agenda es que **compartan una sola fuente de datos** (una tabla de actividades) y sean **dos vistas distintas de lo mismo**:

| | **HOY** (ya lo tenés) | **AGENDA** (lo que vas a construir) |
|---|---|---|
| Pregunta que responde | "¿Qué hago **ahora**?" | "¿Cómo está mi tiempo **en el tiempo**?" |
| Enfoque | Foco, cero distracción | Planificación y visión general |
| Contenido | Tareas y seguimientos con fecha = hoy + vencidos | Todo: pasado, hoy y futuro, en calendario |
| Acción típica | Ejecutar y marcar hecho | Programar, reprogramar, ver huecos, ligar al pipeline |
| Horizonte | El día de hoy | Día / semana / mes |

**Regla de oro técnica:** una sola tabla `actividades` es la fuente de verdad. HOY es un filtro (`fecha = hoy OR vencida`). Agenda es la misma data en formato calendario. Si cambiás algo en Agenda, HOY se actualiza solo, y viceversa. Nunca dos tablas paralelas.

Dicho de otra forma: **la Agenda alimenta a HOY.** El vendedor planifica en Agenda (o agenda seguimientos sobre la marcha), y HOY le sirve el resultado ya priorizado cada mañana.

---

## 3. Qué debe mostrar el apartado de Agenda (estructura y componentes)

### 3.1 Barra superior (siempre visible)
- **Selector de vista:** Día · Semana · Mes · Lista (Agenda cronológica).
- **Navegación de fecha:** botón "Hoy", flechas ← →, selector de fecha.
- **Buscador** (prospecto, empresa, título de actividad).
- **Filtros:** por tipo de actividad, por estado, por prospecto/etapa del pipeline.
- **Botón primario "+ Nueva actividad"** (destacado, siempre a la mano).
- **(Solo manager)** selector de vendedor / vista de equipo.

### 3.2 Zona principal — las 4 vistas
- **Lista (Agenda):** cronológica, agrupada por día. **Es la vista por defecto en móvil** y probablemente la más usada por tus vendedores.
- **Día:** línea de tiempo por horas con bloques; se ven los huecos libres.
- **Semana:** 7 columnas; ideal para planificar la prospección de la semana.
- **Mes:** vista de densidad con puntos de color por tipo; para tener panorama.

### 3.3 Panel lateral / de contexto
- **Mini-calendario** mensual para saltar de fecha.
- **Resumen del día:** N° de actividades, cuántas vencidas, próxima cita.
- **⚠️ "Leads sin próxima acción":** lista de prospectos activos que **no tienen** ninguna actividad futura. Este es el componente que convierte la agenda en un motor de ventas. Es lo que ningún calendario común tiene.
- **Filtros rápidos** por tipo (Llamada, WhatsApp, Reunión…).

### 3.4 Tarjeta de actividad (el bloque individual)
Cada actividad muestra:
- **Tipo** con ícono y color: Llamada · WhatsApp · Reunión/Visita · Demo · Tarea · Cobranza.
- **Hora y duración.**
- **Prospecto/cliente ligado** + su etapa en el pipeline (ej. "Distribuidora Sur — Propuesta enviada").
- **Título/nota corta.**
- **Estado:** pendiente · hecha · vencida · reprogramada · no-show.
- **Acciones rápidas (1 toque):** ✓ Completar · Reprogramar · 💬 WhatsApp · 📞 Llamar · Abrir ficha.

### 3.5 Tipos de actividad (arrancá con pocos)
Empezá con: **Llamada, WhatsApp, Reunión/Visita, Tarea.** Después sumás Demo, Email y Cobranza/Recordatorio de pago. Menos tipos al inicio = adopción más rápida.

### 3.6 Estados de actividad
`Pendiente · Completada · Vencida · Reprogramada · Cancelada · No-show`. Los estados alimentan las métricas del vendedor y el aviso de vencidos.

---

## 4. Accesos directos (los que de verdad mueven la aguja)

Ordenados por impacto, no por dificultad:

1. **"Completar y agendar siguiente" en un solo paso.** Al marcar una actividad como hecha, el sistema pregunta de una vez cuál es la próxima acción y la agenda. Esto vuelve la regla de oro casi automática. **Es el atajo más importante de todos.**
2. **"Agendar seguimiento" desde cualquier lugar** — desde la ficha del prospecto, desde el pipeline, desde el chat. El vendedor nunca debería tener que "ir a la agenda" para programar algo.
3. **Botón WhatsApp directo** (link `wa.me` + plantilla de mensaje pre-armada según la etapa del pipeline).
4. **Botón Llamar** (`tel:`) que además abre el registro de resultado al colgar.
5. **Reprogramar rápido:** "posponer 1 día / 3 días / 1 semana" y arrastrar-y-soltar en las vistas de calendario.
6. **Filtro "solo vencidas"** y **"leads sin próxima acción"** con un toque.
7. **Registrar resultado tras la actividad:** contactó / no contestó / interesado / agendó reunión / cerró / descartó. Un tap, no un formulario.
8. **(Desktop) atajos de teclado:** `N` nueva actividad, `T` ir a hoy, `D/S/M/L` cambiar vista, `/` buscar.

---

## 5. Lo que la vuelve "de las mejores" (diferenciadores)

Estos son los que separan una agenda buena de una excelente. No todos van en la v1, pero decidí cuáles sí:

- **Motor de próxima acción + alerta de leads huérfanos** (§3.3). El corazón del sistema.
- **Completar → siguiente en un paso** (§4.1).
- **Plantillas de cadencia:** al crear un seguimiento, sugerir el patrón día 1 → 3 → 5 → 7 automáticamente.
- **Recordatorio al cliente por WhatsApp** antes de la cita (anti no-show).
- **Registro de resultado rápido** tras cada toque, que a su vez dispara la siguiente acción sugerida.
- **Vista de carga / huecos libres** para que el vendedor (o el manager) vea disponibilidad real.
- **Métricas de actividad del vendedor:** toques por día, % de actividades completadas, seguimientos vencidos, reuniones agendadas por semana. Es lo que el manager mira.
- **Sincronización con Google Calendar** (bidireccional) para no pelear con la agenda personal.
- **Móvil-first y offline (PWA).** El vendedor está en la calle; que funcione sin señal y cargue rápido. (Acá se conecta con tu enfoque PWA.)

---

## 6. Modelo de datos (conceptual — para que las fases calcen)

No es el SQL final (eso lo armás vos por fase), pero el diseño entero se apoya en **una tabla central**:

**`actividades`** (fuente única de HOY y Agenda):
`id · vendedor_id · prospecto_id (o cliente_id) · tipo · titulo · nota · fecha_hora_inicio · duracion_min · estado · resultado · canal · recordatorio_at · creada_por · created_at · updated_at`

Puntos clave para tu stack:
- **RLS por `vendedor_id`:** cada vendedor ve y edita solo sus actividades; el manager ve las de su equipo. (Es exactamente el patrón de roles que ya manejás en el portal interno.)
- **HOY** = `SELECT ... WHERE vendedor_id = auth.uid() AND (fecha::date = today OR (estado='pendiente' AND fecha < now()))`.
- **Agenda** = la misma tabla, filtrada por rango de fechas de la vista.
- **Leads sin próxima acción** = prospectos activos que **no** tienen ninguna fila en `actividades` con `estado='pendiente' AND fecha_hora >= now()`.

---

## 7. Plan fase por fase (para que lo construyas tú)

Cada fase deja algo **usable** antes de pasar a la siguiente. No saltes fases.

### Fase A — Cimiento: la tabla `actividades` como fuente única
**Objetivo:** que HOY y Agenda beban del mismo lugar.
Construir la tabla `actividades` con RLS por vendedor, y **reconectar HOY** para que lea de ahí (si hoy lee de otra estructura, migrar).
**Listo cuando:** creás una actividad para hoy y aparece tanto en HOY como (más adelante) en Agenda, sin duplicar datos.

### Fase B — Vista Agenda base (Lista + Día)
**Objetivo:** ver y operar la agenda en móvil.
Vista Lista cronológica (por defecto) + vista Día. Tarjeta de actividad con estado. Crear / editar / completar.
**Listo cuando:** un vendedor puede ver su día, crear una actividad y marcarla hecha desde el celular.

### Fase C — Vistas Semana y Mes + navegación + filtros
**Objetivo:** planificación y panorama.
Semana, Mes, mini-calendario, navegación de fechas, filtros por tipo/estado y buscador.
**Listo cuando:** el vendedor cambia entre las 4 vistas y filtra sin recargar.

### Fase D — Motor de próxima acción (el diferenciador)
**Objetivo:** que ningún lead quede huérfano.
Panel "Leads sin próxima acción" + flujo **"Completar y agendar siguiente"** en un paso + plantillas de cadencia (día 1/3/5/7).
**Listo cuando:** al completar una actividad, el sistema te obliga/invita a agendar la siguiente, y ves la lista de leads sin seguimiento.

### Fase E — Acciones de canal + registro de resultado
**Objetivo:** vender con menos clics.
Botón WhatsApp (`wa.me` + plantilla por etapa), botón Llamar (`tel:`), y registro de resultado rápido tras cada toque.
**Listo cuando:** desde una tarjeta abrís WhatsApp con el mensaje listo y registrás el resultado en un tap.

### Fase F — Recordatorios y anti no-show
**Objetivo:** que no se caigan las citas ni los seguimientos.
Notificación push al vendedor + recordatorio al cliente por WhatsApp antes de la cita + snooze/reprogramar.
**Listo cuando:** una cita de mañana dispara aviso al vendedor y (opcional) al cliente.

### Fase G — Manager y equipo + métricas
**Objetivo:** visibilidad para quien dirige.
Vista de equipo, filtro por vendedor, y métricas: toques/día, % completadas, vencidos, reuniones/semana.
**Listo cuando:** el manager ve la carga y el ritmo de cada vendedor.

### Fase H — Premium (opcional, cuando el resto esté sólido)
Sync con Google Calendar, time-blocking por bloques, vista de huecos/disponibilidad, arrastrar-para-reprogramar, y modo offline PWA.

---

## 8. Errores a evitar

- **Dos fuentes de verdad.** Si HOY y Agenda guardan en tablas distintas, vas a vivir sincronizando bugs. Una sola tabla.
- **Calendario desconectado del pipeline.** Una actividad que no está ligada a un prospecto no sirve para vender.
- **Sin próxima acción obligatoria.** Si el sistema deja cerrar sin agendar el siguiente paso, perdés el diferenciador.
- **Desktop-first.** Tu vendedor vive en el celular; diseñá para el pulgar primero.
- **Demasiados tipos de actividad al inicio.** Arrancá con 4. Sumás después.
- **Recordatorios por email.** En Perú es WhatsApp.

---

## Próximo paso concreto

Arrancá por la **Fase A** (tabla `actividades` como fuente única y reconectar HOY). Es la que sostiene todo lo demás y evita el peor error del §8.

Cuando la tengas clara, decime y te genero el **prompt de ingeniería para Claude Code** de la Fase A (con tu skill de prompter), listo para ejecutar sobre tu stack Supabase + React.
