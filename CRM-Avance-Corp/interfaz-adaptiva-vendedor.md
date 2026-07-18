# Interfaz adaptiva al vendedor — Guía de diseño e implementación

CRM multi-vendedor para pymes · WhatsApp-first · Supabase + React
Encaja sobre la agenda que ya diseñamos (Fases A–H).

---

## 0. Qué significa "adaptiva" acá — son dos capas

Pediste las dos cosas, y están conectadas:

- **Capa 1 — Adaptación:** la interfaz se amolda a cada vendedor (su rol, su experiencia, su forma de trabajar, su preferencia, su dispositivo).
- **Capa 2 — Adopción:** está diseñada para que el vendedor la use sin resistencia desde el primer día.

**La relación entre las dos es la clave:** la adaptación es el medio, la adopción es el fin. Una interfaz que se siente "hecha para mí" se adopta sola. Una que obliga a pelear con ella, se abandona — y un CRM que el vendedor no usa no vale nada, por bien construido que esté.

Dato que lo respalda: el 90% de las empresas dice que mejorar la adopción del CRM subió la productividad de sus vendedores. El problema nunca es que falten funciones; es que el vendedor no las usa.

---

## 1. Principio rector: valor en menos de 60 segundos

**El vendedor tiene que sacar algo útil en el primer minuto, sin configurar nada.**

Este es el principio que manda sobre todos los demás. El error #1 de adopción es pedir configuración *antes* de dar valor: cuando el vendedor entra por primera vez y le pones un formulario de ajustes, ya lo perdiste.

La regla práctica: **defaults inteligentes primero, personalización después.** Que todo funcione bien de fábrica. La personalización es un premio para quien quiere afinar, nunca un peaje para empezar.

Aplicado a tu agenda: el vendedor entra y ve *su* día ya armado, sus vencidos, sus leads sin seguimiento. Cero setup. Recién cuando lleve días usándola le ofreces "¿quieres que abra en vista Semana?".

---

## 2. Las 6 dimensiones de adaptación (qué se adapta y cómo construirlo)

### 2.1 Por ROL — vendedor vs. supervisor
- **Vendedor:** su agenda, sus leads, el flujo "completar y seguir".
- **Supervisor/manager:** vista de equipo, métricas por vendedor, reasignar actividades.
- **Cómo:** un solo componente que recibe el rol como prop/flag. La RLS de Supabase ya separa los datos por `vendedor_id`; la UI solo decide qué módulos muestra. **Un mismo código, dos experiencias** — no construyas dos apps.

### 2.2 Por NIVEL DE EXPERIENCIA — progressive disclosure
Es la técnica más potente para servir al novato y al experto con la misma pantalla: **revelás complejidad de a pocos.**

- **Vendedor nuevo:** más guía visible, "próximo paso sugerido", menos opciones, tooltips de ayuda.
- **Vendedor experto:** vista densa, atajos de teclado, ayudas ocultas, acceso directo a lo avanzado.
- **Cómo:** un flag `modo` (guiado / experto) por usuario. Lo avanzado vive detrás de "Más opciones" (acordeones, menús contextuales), no en la primera capa. **Auto-graduación:** tras X días o X actividades completadas, ofrecés pasar a modo experto. Nunca lo fuerces.
- **Ojo:** esconder una función solo sirve si el vendedor la puede *encontrar* cuando la necesita. Probá la descubribilidad.

### 2.3 Por CONTEXTO — hora, día y lugar
La interfaz se adapta al momento del vendedor:
- **Mañana** → destaca prospección (es cuando ubicas gente).
- **Tarde** → seguimientos y admin.
- **Viernes** → sugiere limpiar pipeline y planificar la semana.
- **En la calle (móvil)** → botones grandes, WhatsApp y Llamar arriba de todo, y la dirección/ruta de la visita a la mano.
- **Cómo:** una "vista por defecto inteligente" que decide con qué abrir según la hora. Simple lógica de reglas, sin nada complejo.

### 2.4 Por PREFERENCIA — personalización explícita (poca y buena)
Deja que el vendedor ajuste **pocas cosas, pero las que importan:**
- Vista por defecto (Lista / Día / Semana).
- Densidad (compacta / cómoda).
- Tema (claro / oscuro).
- Horario laboral (para bloques y recordatorios).
- Orden de los tipos de actividad que más usa.
- **Cómo:** una tabla `preferencias_usuario`. **Regla:** máximo 5-6 ajustes. Más opciones = parálisis. Cada ajuste tiene un default bueno; personalizar es opcional.

### 2.5 Por COMPORTAMIENTO — la interfaz aprende (con reglas, no con IA)
- **"Próxima mejor acción"** sugerida según su cadencia y el resultado del último toque.
- **Accesos directos que se reordenan** según lo que más usa ese vendedor.
- **Plantillas de WhatsApp** que suben las que más manda.
- **Cómo:** arrancá con **reglas simples** (si el lead está en "propuesta enviada" y pasaron 3 días → sugerir seguimiento). Nada de machine learning al inicio; es caro, opaco y no lo necesitas. Las reglas cubren el 90%.

### 2.6 Por DISPOSITIVO — responsive de verdad
- **Móvil-first:** el vendedor vive en el celular. Navegación inferior (bottom nav) al alcance del pulgar, tarjetas grandes, gestos.
- **Desktop:** vista densa, panel lateral, atajos de teclado.
- **Cómo:** no encojas el desktop para el móvil. Son **layouts distintos** del mismo dato, no el mismo layout escalado.

---

## 3. Los 8 drivers de adopción (para que sí la usen todos los días)

1. **Valor en <60 s** (§1) + **estado vacío que enseña** (ver §4).
2. **Móvil-first real.** Si en el celular es incómoda, no la usan. Punto.
3. **Fricción mínima en la captura de datos.** Crear una actividad en 2 taps; "completar y agendar siguiente" en 1. Cada campo de más que pidas es una razón para no registrar. Usá validaciones que guíen (formato de teléfono, fecha), no que estorben.
4. **Familiaridad (Ley de Jakob).** El vendedor ya sabe usar WhatsApp y un calendario. Que tu interfaz se sienta como algo que ya conoce: chips, listas, el verde de WhatsApp, gestos de deslizar. No inventes patrones nuevos.
5. **Onboarding en contexto, no un tour.** Nada de 10 pantallas de bienvenida. Coach marks cortos la primera vez que toca cada zona ("acá agendas tu próximo toque"). Se aprende usando.
6. **Estados vacíos accionables.** "No tienes seguimientos hoy" es un callejón sin salida. Mejor: "Tienes 3 leads sin próxima acción → agéndales uno" con el botón al lado. El vacío se vuelve trabajo.
7. **Feedback y microrrecompensas.** "Mi ritmo" (toques/día, % completadas, racha). Motiva sin ser tóxico. **No** rankings públicos que humillen al que va último.
8. **Rendimiento (PWA / offline).** Si carga lento o se cae sin señal en la calle, la abandonan. Acá se conecta directo con tu enfoque PWA: caché, offline, install prompt.

---

## 4. Componentes de UI que materializan todo esto

Estos son los "ladrillos" que vas a construir sobre la agenda:

- **Switch de rol** (vendedor / supervisor) — decide qué módulos se ven.
- **Toggle de densidad** (compacta / cómoda) y **de tema** (claro / oscuro).
- **Modo guiado / experto** con progressive disclosure (lo avanzado detrás de "Más").
- **Vista por defecto inteligente** (abre según la hora del día).
- **Panel "Próxima mejor acción"** (sugerencia por reglas).
- **Estados vacíos accionables** en cada vista (nunca un vacío muerto).
- **Coach marks / tooltips de primer uso** por zona.
- **Checklist de primeros pasos** (onboarding: "agenda tu primer seguimiento ✓", "registra un resultado ✓") que desaparece al completarse.
- **Pantalla de preferencias mínima** (5-6 ajustes máximo).
- **Bottom nav en móvil / sidebar en desktop.**

---

## 5. Modelo de datos (lo mínimo para soportarlo)

Una tabla nueva, chica:

**`preferencias_usuario`**
`usuario_id · vista_default · densidad · tema · modo (guiado|experto) · horario_inicio · horario_fin · orden_tipos (jsonb) · onboarding_estado (jsonb) · updated_at`

Notas para tu stack:
- **RLS por `usuario_id`:** cada quien lee/escribe solo sus preferencias.
- El **nivel de experiencia** puede derivarse (contar actividades completadas) o guardarse como campo; empezá derivándolo para no pedir nada.
- El **onboarding_estado** (jsonb) guarda qué coach marks ya vio y qué pasos del checklist completó, para no repetirlos.
- Todo tiene **default** en la tabla, así un vendedor sin fila configurada ya funciona bien.

---

## 6. Errores que matan la adopción (evítalos)

- **Pedir configuración antes de dar valor.** El pecado capital.
- **Demasiadas opciones.** La personalización sin límite paraliza. Pocas y buenas.
- **Tours de bienvenida largos.** Nadie los lee. Coach marks en contexto.
- **Personalización sin defaults buenos.** Si el default es malo, obligas a configurar, y volvés al pecado capital.
- **"Adaptar" con IA prematuro.** Reglas simples primero; ML solo si algún día lo justifica el volumen.
- **Gamificación tóxica.** Rankings que humillan bajan la moral y la adopción.
- **Desktop encogido en el móvil.** Layouts distintos, no escala.
- **Estados vacíos muertos.** Cada vacío es una oportunidad de acción desperdiciada.

---

## 7. Plan fase por fase (montado sobre la agenda A–H)

Ordenado por impacto en adopción, no por dificultad. Cada fase deja algo usable.

### Fase 1 — Base de adopción (la que más rinde)
Defaults inteligentes + móvil-first + quick-add en 2 taps + "completar y seguir" en 1 + estados vacíos accionables.
**Va junto con las Fases A–B de la agenda.** No requiere que el vendedor configure nada.
**Listo cuando:** un vendedor nuevo entra, ve su día armado y registra una actividad sin pensar.

### Fase 2 — Adaptación por rol
Vista vendedor vs. supervisor sobre el mismo componente (la RLS ya separa datos).
**Va junto con la Fase G de la agenda.**
**Listo cuando:** un supervisor ve equipo y métricas; un vendedor ve solo lo suyo.

### Fase 3 — Preferencias mínimas
Tabla `preferencias_usuario` + toggles de vista default, densidad y tema.
**Listo cuando:** el vendedor cambia su vista por defecto y se recuerda entre sesiones.

### Fase 4 — Experiencia y progressive disclosure
Modo guiado vs. experto + coach marks de primer uso + checklist de onboarding.
**Listo cuando:** el novato ve guía y el experto ve densidad, con la misma pantalla, y la ayuda no reaparece una vez vista.

### Fase 5 — Adaptación por contexto
Vista por defecto inteligente según la hora + ajustes móvil/calle (WhatsApp y Llamar arriba, ruta a la vista).
**Listo cuando:** al abrir en la mañana destaca prospección; en la tarde, seguimientos.

### Fase 6 — Adaptación por comportamiento
"Próxima mejor acción" por reglas + accesos que se reordenan según uso.
**Listo cuando:** tras completar un toque, el sistema sugiere el siguiente correcto según la etapa del lead.

---

## Próximo paso concreto

Arrancá por la **Fase 1 (Base de adopción)**. Es la que más mueve la aguja y no exige que el vendedor configure nada — puro default inteligente, móvil-first y fricción mínima. Además encaja exactamente con las Fases A–B de la agenda que ya definimos, así que las construyes juntas.

Cuando la tengas clara, decime y te genero el **prompt de ingeniería para Claude Code** de la Fase 1 (con tu skill de prompter), listo para tu stack Supabase + React.
