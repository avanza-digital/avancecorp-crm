# Plan principal — Llamadas desde el celular al CRM + Jev

Copia de consulta guardada directamente en `GESTION DIARIA`. [Documento canónico](<AUTOMATIZACION DE LLAMADAS/Plan — Llamadas desde el celular al CRM.md>).

29/09/2026 · Versión 3 · Checklist por fases y subfases · Responsable de negocio: Jhosep / Avance Corp

**Estado: planificación consolidada; implementación pendiente.** Incorpora la revisión técnica del proyecto y la propuesta de Jev para ayudar a identificar a qué lead corresponde una llamada. La autorización actual cubre este documento y el tablero; no ejecuta migraciones, activa Jev con datos reales ni publica el CRM.

**Tablero editable:** [Avance Corp · Llamadas al CRM · Plan por fases + Jev](https://www.figma.com/board/39XA8pQGdbXrg8r2UiPhpY?node-id=1-2).

Este archivo es la fuente principal de alcance y criterios. FigJam contiene las mismas ocho fases, 33 subfases y 102 tareas identificadas. Los estados se actualizan manualmente en ambos; no hay sincronización automática. La [revisión técnica](<AUTOMATIZACION DE LLAMADAS/Revision — Oportunidades de mejora del plan (2026-09-29).md>) conserva su valor como diagnóstico; sus referencias de líneas al plan corresponden al [borrador archivado](<AUTOMATIZACION DE LLAMADAS/historial/Plan — Llamadas desde el celular al CRM — borrador previo 2026-09-29.md>).

## 1. Resultado esperado

Cuando el analista termine una llamada en su celular corporativo, el CRM debe facilitar el registro con el lead correcto y la tarea que corresponda. Al guardar, reutiliza la lógica vigente para registrar el resultado, cerrar la tarea elegible y programar la siguiente acción, conservando una asociación verificable con el evento del teléfono.

La experiencia sirve al analista que registra desde el celular y al que vuelve a su computadora. Una llamada capturada que requiere atención permanece visible; cerrar el formulario no la elimina.

La precisión se construye en este orden:

1. **Código:** canonizar el teléfono completo y encontrar coincidencias exactas dentro del ámbito autorizado.
2. **Contexto verificable:** intención de llamada desde el CRM, teléfonos alternativos y asociaciones previamente confirmadas y vigentes.
3. **Jev:** sugerir entre candidatos existentes cuando haya ambigüedad y contexto útil.
4. **Persona:** confirmar los casos dudosos o dejarlos sin identificar.

Jev no conoce al propietario de un número por sus dígitos. No debe corregir un dígito, inventar un teléfono ni adjudicar un lead por semejanza numérica. Su activación queda condicionada a demostrar una mejora frente al sistema exacto en un banco de evaluación reservado.

## 2. Alcance y restricciones

- Piloto con 2–3 celulares Android corporativos. MacroDroid es la primera herramienta a evaluar; se reutiliza la PWA y se incorpora operación desde PC.
- Leads que el actor puede consultar y gestionar, con teléfono principal y alternativo. Los clientes con contrato cuyos teléfonos viven en `public.perfiles` requieren una ampliación independiente.
- El analista elige el resultado comercial. El evento del teléfono y Jev no crean gestiones comerciales automáticamente.
- Cuatro capas: **C1**, tablas privadas con RLS; **C2**, funciones `private.*` y triggers; **C3**, puertas `crm.*` y Edge Functions; **C4**, PWA mediante `app/src/data/crm-api.ts`.
- Reutilizar `RegistrarResultado`, `tareaQueCierra` y el núcleo sellado v4. No registrar llamadas escribiendo directamente en `crm.actividades`.
- Push del backend fuera del alcance base. Una notificación local del celular puede ofrecer acceso alternativo si Android no permite abrir la PWA automáticamente.
- No prometer captura total ni interpretar ausencia de eventos como prueba de inactividad. El token acredita posesión de una credencial, no certifica por sí solo que hubo una llamada física.
- Antes de implementar cambios en C1–C3, concretar sus contratos y aplicar el gate de revisión vigente. La publicación mantiene la invocación humana y el procedimiento de release del proyecto.
- Sin fechas de entrega comprometidas. El piloto inicial propone cinco días; las demás duraciones se estiman con sus resultados.

## 3. Base existente y ajustes necesarios

Revisión sobre la copia local del 29/09/2026, referencia inicial `main` / `f34320db`, seguimiento de `avancecorp/main` y cambios locales previos. No acredita el catálogo productivo.

| Pieza | Evidencia del proyecto | Uso previsto |
| --- | --- | --- |
| Formulario | `app/src/components/gestion-diaria/registrar-resultado.tsx` | Reutilizar siete resultados y siguiente acción; ampliar contrato de confirmación/contexto cuando exista evento |
| Escritor vigente | `crm.registrar_llamada_v4` → `private.llamada_registrar_v4`, migración `20260921153654` | Conservar cuerpo sellado e idempotencia; componer con enlace en F4 |
| Confirmación SLA | `app/src/data/store.tsx` y recibos en `sessionStorage` | La confirmación trae `actividad_id`; `onGuardado` hoy no recibe argumentos |
| Tarea elegible | `app/src/lib/contacto-tarea.ts`, `tareaQueCierra` | Tarea propia, canal exacto, vence hoy o antes y candidata única; supervisor no cierra la del analista |
| Retorno del marcador | `app/src/components/app/contacto.tsx`, `AccionesContacto` | Cambiar coordinación local por instancia por una compartida con el enlace profundo |
| Canonización | `app/src/lib/validacion.ts`; `private.canonizar_contacto`, migración `20260826182000_crm_canonizar_contacto.sql` | Comparar E.164 completo y probar paridad; no usar el normalizador legado como base del nuevo flujo |
| Búsqueda con ámbito | `buscarLeadsGlobal` / `crm.cartera_pagina_fn` | Una página de ocho resultados no demuestra unicidad; completar recuperación o informar búsqueda incompleta |
| Boot y tareas | Store y montaje del workspace en `App.tsx` | Conservar espera existente y probar entrada por hash tras login; no se demostró un fallo actual de boot |
| Rutas PWA | `lib/router.ts`, `App.tsx`, patrón de solicitudes de tasa | Rutas por número temporal y por UUID de evento |
| Gate de tablas | `supabase/scripts/test-rls.mjs` | Añadir cada tabla nueva a la lista y probar puertas privilegiadas |
| Piloto TypeSafe | `scripts/gestion-diaria-typesafe/`, `docs/gestion-diaria/typesafe/EVALUACION-F41-2026-09-24.md` | Reutilizar infraestructura compatible; el juicio nota/resultado no valida identificación telefónica |

El retorno por foco tras cuatro segundos representa una intención de llamada, no evidencia de conexión. «Deshacer» tiene toast de 15 segundos y ventana de servidor de 24 horas; conserva actividad y no reabre la tarea cerrada. Este plan respeta esa semántica.

## 4. Contratos que gobiernan todas las fases

### 4.1 Teléfonos y candidatos

- Canonizar teléfono principal, alternativo y número capturado con reglas compatibles entre cliente y servidor. Mantener ocultos o inválidos como tales.
- Comparar canónicos completos. Una excepción para históricos peruanos debe reconocer el formato local y producir el mismo canónico; nunca recortar nueve dígitos de cualquier país.
- Regresiones sintéticas: `014457890` y `+5114457890` deben converger; `+51987654321` y `+34987654321` no deben fusionarse. Son ejemplos de cadenas, no personas ni líneas asignadas verificadas.
- Contar leads distintos aunque coincidan dos campos. Considerar números compartidos y reciclados.
- Aplicar ámbito y elegibilidad antes de seleccionar. Distinguir `unico`, `ambiguo`, `sin_coincidencia`, `incompleto` y `error`. Acceso denegado no revela candidatos de otro ámbito.
- En F1, recuperar mediante el módulo de datos todas las coincidencias potenciales por la puerta paginada existente, incluyendo variantes históricas reconocidas. Un tope o falta de completitud impide autoselección. Al encontrar dos coincidencias exactas distintas ya se puede declarar ambigüedad.
- F2–F3 incorporan resolución exacta en servidor, con respuesta mínima e indexación justificada. Validar recuperación con datos históricos, no solo con teléfonos recién normalizados.

### 4.2 Identidad, entrega e integridad

- Crear `evento_origen_id` una sola vez y persistirlo con payload inmutable antes del primer envío. Unicidad por asignación de equipo e ID de origen.
- Mismo ID y contenido: mismo evento. Mismo ID con contenido incompatible: conflicto sin sobrescribir evidencia. Correcciones por operación auditada aparte.
- Separar `ocurrio_en` y `recibido_en`; definir si el instante capturado es inicio o fin. No recalcular al reintentar. Registrar desfase y tratar relojes anómalos.
- Cola local persistente, reintentos con espera creciente, manejo de 429 y reanudación tras reinicio. Retirar solo tras confirmación del servidor. Errores permanentes visibles para soporte.
- Dos triggers que generen IDs diferentes para una misma llamada requieren correlación en el adaptador o revisión de duplicidad. La idempotencia de transporte no resuelve ese caso sola.
- Relación evento–actividad uno a uno y validada atómicamente bajo concurrencia. ±10 minutos sirve para sugerir reconciliación, no para enlazar automáticamente la actividad más cercana.
- Nunca repetir el registro comercial ya confirmado para reparar un enlace fallido.

### 4.3 Coordinación de pantalla

Un coordinador compartido controla actor, intención, lead, canal, número marcado, hora, caducidad y formulario abierto. Lo usan `AccionesContacto` y el receptor del hash. Persiste el contexto mínimo, lo elimina al cerrar sesión y evita que otra cuenta consuma una intención anterior.

Debe resolver `focus → hash`, `hash → focus`, remount, arranque en frío y otra pestaña. Otra llamada se encola o aparece en bandeja sin reemplazar la edición actual. La caducidad se fija con el piloto. Sin UUID, la coordinación de intención es provisional y no demuestra identidad del evento.

Ruta temporal propuesta: `#/hoy/llamada/numero/<numero_codificado>`. Codificar solo el segmento del número, preservar `+`, decodificar y validar en CRM; no destruir el hash codificando toda la URL. Ruta estable desde F3: `#/hoy/llamada/evento/<uuid>`, preferida tras confirmación y sin número en el enlace habitual.

### 4.4 Actor, ámbito y credenciales

- Ingestión de servicio: token → asignación activa → actor activo → ámbito. No tratar `auth.uid()` de la credencial de servicio como identidad del analista.
- Operaciones humanas: identidad y capacidades resueltas en servidor; evento accesible, lead gestionable y actividad del mismo autor, lead y tipo permitido.
- Reasignación de lead: revalidar acceso, conservar atribución histórica y permitir derivación autorizada o detalle limitado. No filtrar datos del nuevo ámbito ni enlazar actividad ajena.
- Asignación de equipo inmutable: al cambiar de persona, cerrar la anterior y crear otra. La baja de usuario o celular revoca ingestión. Rotar credenciales con auditoría.
- Tablas privadas con RLS y grants mínimos; cerrar también `EXECUTE`. Puertas DEFINER con `search_path = ''` y nombres calificados.
- Token mostrado una vez, hash en servidor y sin secretos en logs, URL, soporte ni FigJam. Límite de peticiones con estado compartido, no solo memoria de una instancia Edge.

## 5. Hoja de ruta F0–F7

Todas las fases están **pendientes**. Responsables por rol propuestos, sin asignación nominal ni fecha ficticia.

| Fase | Resultado | Dependencia | Capas | Responsable propuesto | Puerta de salida |
| --- | --- | --- | --- | --- | --- |
| F0 · Piloto y línea base | Viabilidad real y lugar de registro | Ninguna | Operación / C4 existente | Negocio + soporte + QA | Cobertura y fallos medidos en 2–3 equipos |
| F1 · Formulario único y match exacto | Retorno sin duplicados ni falsa identidad | F0, viabilidad UX | C4 | Frontend + QA | Rutas, coordinación y teléfonos aprobados |
| F2 · Núcleo confiable | Eventos, estados y permisos consistentes | F0 + contrato conjunto F2–F4 | C1–C2 | Backend + revisión de datos | SQL, RLS, concurrencia y ámbito aprobados |
| F3 · Captura y sincronización | Entrega durable desde Android | F2 | C3 + adaptador Android | Backend + soporte móvil | Recuperación sin pérdida ni duplicado |
| F4 · Pendientes y registro conciliado | Operación completa en celular y PC | F1 + F2 + F3 | C2–C4 | Full stack + QA + negocio | Evento → resultado → enlace verificado |
| F5 · Jev para identificación asistida | Resolver ambigüedad con evidencia | Banco desde F0; integrar tras F4 | C2–C4 | Backend/IA + negocio + QA | Evaluación y piloto humano; puede quedar OFF |
| F6 · Gerencia y calidad de datos | Métricas interpretables y salud | F4; independiente de F5 | C2–C4 | Backend + frontend + gerencia | Cifras reconciliadas y cobertura visible |
| F7 · Despliegue gradual y operación | Uso estable y soporte preparado | F4 + F6; decisión explícita sobre F5 | Operación y capas de correcciones | Release + soporte | Piloto aceptado, reversa y cohortes |

Secuencia base: **F0 → F1/F2 → F3 → F4 → F6 → F7**. F2 puede diseñarse en paralelo con F1 tras cerrar el contrato conjunto. F5 se prepara con sintéticos desde F0 y se evalúa en paralelo con F6 después de F4; no bloquea el sistema determinista.

Correspondencia con el borrador: 0a → F0; 0b → F1; 1 → F2; 2 → F3 y parte de F4; 3 → F4; 4 → F6. F5 explicita Jev y F7 añade la salida operativa.

### 5.1 Seguimiento del avance

Cada tarea tiene un ID estable, por ejemplo `F3.2.1`. Una fase contiene subfases, y cada subfase contiene tareas verificables. Todos los checks comienzan pendientes porque esta entrega prepara el plan, no ejecuta sus fases.

- En Markdown: cambiar `- [ ]` por `- [x]` cuando la tarea esté terminada y verificada. Para en curso o bloqueada, conservar la casilla vacía y añadir el estado y el motivo.
- En FigJam: editar la casilla `☐` a `☑` al completar; usar `◐` para en curso y `!` para bloqueada. Actualizar manualmente el estado y el contador de la subfase/fase.
- Registrar responsable, evidencia y fecha de validación junto a la subfase. Si una prueba corresponde pero no corrió, mantener pendiente o bloqueada, con `NOT RUN` y causa.
- Si una tarea condicional no aplica (por ejemplo asistencia Jev al decidir mantener OFF), dejarla sin marcar, anotar `NO APLICA` con decisión y motivo y excluirla del denominador. No presentarla como ejecutada.
- Cerrar una subfase al verificar sus tareas aplicables. Cerrar una fase solo si además cumple su aceptación y los criterios comunes de la sección 14.
- Mantener los mismos IDs en Figma y Markdown. Los contadores no se recalculan ni sincronizan automáticamente.

| Fase | Subfases | Avance inicial | Estado | Abrir checklist |
| --- | --- | --- | --- | --- |
| F0 · Piloto y línea base | 4 | 1/12 | En curso | [Ver fase](https://www.figma.com/board/39XA8pQGdbXrg8r2UiPhpY?node-id=3-2) |
| F1 · Formulario único y match exacto | 4 | 12/12 | Hecha | [Ver fase](https://www.figma.com/board/39XA8pQGdbXrg8r2UiPhpY?node-id=3-8) |
| F2 · Núcleo confiable | 4 | 12/13 | En curso | [Ver fase](https://www.figma.com/board/39XA8pQGdbXrg8r2UiPhpY?node-id=3-14) |
| F3 · Captura y sincronización | 4 | 6/13 | En curso | [Ver fase](https://www.figma.com/board/39XA8pQGdbXrg8r2UiPhpY?node-id=3-20) |
| F4 · Pendientes y conciliación | 4 | 0/13 | En curso | [Ver fase](https://www.figma.com/board/39XA8pQGdbXrg8r2UiPhpY?node-id=3-66) |
| F5 · Jev para identificación asistida | 5 | 0/15 | Pendiente | [Ver fase](https://www.figma.com/board/39XA8pQGdbXrg8r2UiPhpY?node-id=3-72) |
| F6 · Gerencia y calidad | 4 | 0/12 | Pendiente | [Ver fase](https://www.figma.com/board/39XA8pQGdbXrg8r2UiPhpY?node-id=3-78) |
| F7 · Despliegue y operación | 4 | 0/12 | Pendiente | [Ver fase](https://www.figma.com/board/39XA8pQGdbXrg8r2UiPhpY?node-id=3-84) |

**Total inicial: 0/102 tareas, agrupadas en 33 subfases.** Los ocho checks comunes de la sección 14 son criterios que se aplican al cerrar cada fase; no se suman como otra fase de trabajo.

## 6. F0 · Piloto y línea base

**Objetivo:** medir qué captura cada celular y dónde conviene pedir el resultado.

**Seguimiento de F0:** 1/12 tareas completadas · Estado: en curso · Responsable nominal: por asignar.

### F0.1 · Preparar el piloto

**Estado:** en curso · **Avance:** 0/3 · **Responsable:** Jhosep.

- [ ] **F0.1.1** Seleccionar 2–3 celulares y registrar marca, Android, navegador, automatizador y restricciones de batería. — EN CURSO: C1 registrado: Samsung Galaxy A16 (SM-A165M), Android 16, Chrome predeterminado, MacroDroid 5.67 (Play Store, sep. 2026), batería «No restringido», «Aparecer encima» activado. Faltan 1–2 celulares más. 07/10: #18 aprobada por Miguel; Jhosep compra MacroDroid Pro en C1 (cuenta corporativa, S/ 19, pago único) antes del 09/10 ~15:50 Lima y registra equipo, licencia y fecha.
- [ ] **F0.1.2** Asignar analistas, soporte y responsable del registro de incidencias. — EN CURSO: Jhosep asume analista piloto (C1), soporte y registro de incidencias mientras haya un solo celular.
- [ ] **F0.1.3** Comunicar finalidad y tratamiento de datos; instalar la PWA y configurar permisos del piloto. — EN CURSO: C1 completo: PWA instalada, permisos Teléfono y Registro de llamadas confirmados por evidencia, «Aparecer encima», batería sin restricciones y, desde el 30/09, «Abrir vínculos admitidos» + dominio crm.miavance.com en la app (necesario para que la URL la abra). Aviso: no aplica al propio responsable. Pendiente para los próximos celulares.

**Evidencia / fecha de validación:** pendiente.

### F0.2 · Medir la línea base

**Estado:** pendiente · **Avance:** 0/3 · **Responsable:** por asignar.

- [ ] **F0.2.1** Medir cinco días: llamadas desde CRM, fuera del CRM, entrantes y uso de WhatsApp.
- [ ] **F0.2.2** Anotar si el resultado se registra desde PC o celular y cuánto tarda el analista.
- [ ] **F0.2.3** Comparar las capturas con el registro del teléfono y documentar faltantes o duplicados.

**Evidencia / fecha de validación:** pendiente.

### F0.3 · Probar los equipos

**Estado:** en curso · **Avance:** 0/3 · **Responsable:** Jhosep.

- [ ] **F0.3.1** Probar al menos diez salientes y diez entrantes por equipo, además de atendidas, perdidas, rechazadas y canceladas. — EN CURSO: C1: salientes con número (29/09) y muchas más en las pruebas de C1 (02/10 y 06/10). Las entrantes están bloqueadas por la decisión 2 de Miguel; #16 aprobada (07/10): F0 se acepta con diez salientes por equipo y los casos especiales; las diez entrantes pasan a la aceptación de la #14. Faltan diez salientes con sus casos (atendida, no atendida, rechazada, cancelada) por equipo.
- [ ] **F0.3.2** Validar oculto, fijo, internacional, doble SIM si aplica, enlace con +, login y retorno a PWA. — EN CURSO: C1: notificación con número y nombre PASS; la URL abre la PWA con «Abrir vínculos admitidos» (30/09); el número sobrevive al login (F1.2.2). 07/10 contra el receptor: saliente a un FIJO capturada y mostrada con +51 («ningún lead», correcto: no es lead); saliente a un lead propio con celular → se abrió su encuesta (REGISTRO.md §5h). Faltan oculto, internacional y doble SIM; «lead con fijo» en vivo es opcional (lo cubren las pruebas de F1).
- [ ] **F0.3.3** Probar pantalla bloqueada, batería, tres noches y ensayo sintético de cola, reinicio y respuesta HTTP. — EN CURSO: C1: noche 1 de 3. En C1 contra el receptor: cola sin red (A3), reinicio con aviso pendiente (A6), 503 (A4), 400 (A5), 401 que conserva la cola (P4), 429 (07/10) y PANTALLA BLOQUEADA (07/10: el aviso llegó a los 9 s con la pantalla apagada y al desbloquear la encuesta ya estaba abierta). Faltan dos noches y batería baja.

**Evidencia / fecha de validación:** pendiente.

### F0.4 · Cerrar viabilidad

**Estado:** en curso · **Avance:** 1/3 · **Responsable:** por asignar.

- [ ] **F0.4.1** Entregar REGISTRO.md, guía MacroDroid y matriz de compatibilidad con evidencia por equipo. — EN CURSO: REGISTRO.md, macrodroid.md y compatibilidad.md creados; falta la evidencia por equipo.
- [x] **F0.4.2** Preparar ejemplos sintéticos de teléfonos compartidos, históricos, reciclados y contexto contradictorio.
- [ ] **F0.4.3** Decidir continuar o ajustar, priorizar UX por separado de evidencia y estimar responsables/calendario.

**Evidencia / fecha de validación:** pendiente.

**Entregables al ejecutar:** `docs/gestion-diaria/piloto-telefonia/REGISTRO.md`, guía `macrodroid.md`, compatibilidad por equipo y decisión continuar/ajustar. Estos archivos son entregables futuros.

**Aceptación:** comparar cada prueba con el registro del teléfono; cero pérdidas y duplicados inexplicados en la muestra controlada. Al menos diez salientes y diez entrantes por equipo, además de casos especiales. Número legítimamente oculto se clasifica como oculto. No extrapolar éxito de la muestra a captura universal.

**Dos decisiones separadas:** si casi todo sale del CRM, baja la prioridad de apertura externa de F1, pero la evidencia F2–F4 conserva valor. Si no abre la PWA, evaluar notificación local y PC; eso no significa que falle la entrega de eventos.

## 7. F1 · Formulario único y coincidencia exacta

**Objetivo:** mejorar el retorno usando puertas existentes y mantener resolución manual cuando no haya identidad comprobada.

**Seguimiento de F1:** 12/12 tareas completadas · Estado: hecha · Responsable nominal: por asignar.

### F1.1 · Coordinar la intención

**Estado:** hecha · **Avance:** 3/3 · **Responsable:** Claude (código) · Jhosep (prueba en C1).

- [x] **F1.1.1** Crear coordinador compartido para actor, lead, canal, número, hora, caducidad y formulario abierto.
- [x] **F1.1.2** Integrar AccionesContacto y receptor de enlaces; persistir contexto mínimo y limpiarlo al salir de la cuenta.
- [x] **F1.1.3** Resolver foco/hash en ambos órdenes, recarga, remount y otra pestaña; encolar la siguiente llamada.

**Evidencia / fecha de validación:** 30/09/2026: commits 6a920143, 6ca9944f, e08288ee, 5d9f21c3; tests del coordinador (13) y de AccionesContacto (20); recarga, remount, ambos órdenes, cola y dos pestañas vistos en el navegador..

### F1.2 · Recibir el enlace

**Estado:** hecha · **Avance:** 3/3 · **Responsable:** Claude.

- [x] **F1.2.1** Añadir ruta por número, codificando solo su segmento y preservando +, país y hash.
- [x] **F1.2.2** Propagar ruta en App y recuperarla tras login y carga del workspace.
- [x] **F1.2.3** Montar receptor en Hoy y reutilizar asegurarLead, RegistrarResultado y tareaQueCierra.

**Evidencia / fecha de validación:** 30/09/2026: commits 69b4bdf2 y e08288ee; router 29 tests, App 10, receptor 15; en C1 la URL con número sobrevivió al login..

### F1.3 · Encontrar el lead

**Estado:** hecha · **Avance:** 3/3 · **Responsable:** Claude.

- [x] **F1.3.1** Comparar E.164 completo de principal y alternativo; probar fijo e internacional con reglas compatibles.
- [x] **F1.3.2** Recuperar candidatos paginados y variantes históricas; contar leads distintos y comprobar completitud.
- [x] **F1.3.3** Mostrar único, ambiguo, sin coincidencia, incompleto o error; ofrecer búsqueda manual donde corresponda.

**Evidencia / fecha de validación:** 30/09/2026: commits cd4d31b0 y e08288ee; 24 tests de coincidencia (casos sintéticos A, B, C, E, F, D3), 9 de la capa de datos y 13 del receptor, todos en verde..

### F1.4 · Validar la experiencia

**Estado:** hecha · **Avance:** 3/3 · **Responsable:** Claude (checks, guía) · Jhosep (C1).

- [x] **F1.4.1** Probar roles, tarea propia, otra cuenta, formulario en edición, dos pestañas y limpieza del hash.
- [x] **F1.4.2** Validar retorno real en Android y alternativa de notificación local sin push del backend.
- [x] **F1.4.3** Ejecutar checks frontend, accesibilidad y E2E local pertinentes; documentar guía y reversa.

**Evidencia / fecha de validación:** 30/09/2026: navegador del PC contra la demo (4 caminos, roles, otra cuenta, cola, dos pestañas); C1 con la build de la rama (macro real, login, build real sin guardar); gate del app en verde; E2E Docker 285 passed / 1 flaky ajeno / 0 failed..

**Entregables:** flujo de pantalla, tests de coordinador/router/teléfonos y guía móvil. Puede cambiar `crm-api.ts`; no requiere tablas ni puertas SQL nuevas.

**Aceptación:** ambos órdenes foco/enlace abren una sola vez; no se pierde edición; fijo/internacional correctos; búsqueda incompleta nunca autoselecciona; ningún acceso indebido; tarea propia respetada. Prueba física y E2E local en Docker aplicable.

**Reversa:** desactivar entrada desde MacroDroid y revertir interfaz si hace falta. Continúa el registro habitual.

## 8. F2 · Núcleo confiable y contrato de datos

**Objetivo:** evidencia separada de gestión y contrato completo que F3–F4 puedan consumir. Diseño conceptual, no SQL listo para producción.

| Entidad lógica privada | Datos y restricciones |
| --- | --- |
| Asignaciones de celulares | ID, equipo, actor histórico, etiqueta, vigencia, hash de credencial, alta/baja/rotación; no sobrescribir actor |
| Eventos | ID servidor, asignación, ID origen, número canónico nullable, crudo temporal solo si se justifica, dirección/estado/duración nullable, calidad/origen, semántica de hora, recepción y hash de payload |
| Asociación y atención | Lead nullable, método, actor confirmador, fecha, identificación/atención, motivos auditados y transiciones autorizadas |
| Enlace a actividad | Actividad nullable y única cuando exista, evento único, autor/lead/tipo compatibles y validación atómica |
| Auditoría y salud | Cambios relevantes, sincronización, errores y depuración; mínimos datos y ningún secreto |

La migración puede agrupar campos en una tabla: justificar cada entidad física, índice y FK con el catálogo real. No crear tablas por anticipación sin contrato consumidor.

**Dimensiones separadas:** dirección `entrante/saliente/desconocida`; estado técnico `conectada/no_atendida/rechazada/cancelada/desconocido` solo con evidencia; resultado comercial elegido por persona. Duración desconocida es `null`; cero no prueba universalmente que nadie contestó ni una duración positiva demuestra conversación con el lead.

**Identificación:** `sin_identificar`, `ambiguo`, `identificado`. Errores de consulta/autorización son resultados operativos separados.

**Atención:** `por_revisar`, `requiere_resultado`, `requiere_devolucion`, `registrado`, `descartado_con_motivo`.

| Situación | Tratamiento |
| --- | --- |
| Sin identidad suficiente | Revisar/asociar con permiso; no fabricar gestión |
| Exacto único, lead gestionable y llamada elegible | Requiere resultado |
| Entrante perdida | Pendiente de devolución; no marcar «el lead no contestó» |
| Asociación manual | Guardar método/actor; revalidar ámbito antes de registrar |
| Actividad existente posiblemente relacionada | Proponer y confirmar enlace; no registrar otra vez |
| No comercial/fuera de alcance | Descarte permitido, motivado y auditado; no salida libre para ocultar llamadas identificadas |
| Actividad con efectos deshechos | Evidencia y enlace permanecen; anotar efectos anulados sin exigir automáticamente otro registro |

**Seguimiento de F2:** 12/13 tareas completadas · Estado: en curso · Responsable nominal: por asignar.

### F2.1 · Cerrar el contrato

**Estado:** hecha · **Avance:** 3/3 · **Responsable:** Jhosep (propuso) · Miguel (ratificó).

- [x] **F2.1.1** Definir elegibilidad comercial, identificación, atención, dirección y estado técnico por separado.
- [x] **F2.1.2** Acordar descarte motivado, entrante perdida como devolución y semántica de Deshacer.
- [x] **F2.1.3** Fijar hora de ocurrencia/recepción, retención por estado y atribución tras reasignaciones.

**Evidencia / fecha de validación:** Decisiones ratificadas por Miguel el 03/10 (#175, decisiones 1–7) y vigentes en el código de main (#190, 06/10)..

### F2.2 · Diseñar datos e identidad

**Estado:** hecha · **Avance:** 4/4 · **Responsable:** Claude (construye y prueba) · Miguel (aprueba y aplica).

- [x] **F2.2.1** Modelar asignaciones inmutables de equipo y eventos con ID de origen estable y payload inmutable.
- [x] **F2.2.2** Definir tablas, índices y FK mínimos; conservar actor histórico y número crudo solo si se justifica.
- [x] **F2.2.3** Aplicar unicidad de evento e idempotencia: mismo contenido devuelve mismo ID; distinto contenido genera conflicto.
- [x] **F2.2.4** Restringir enlace evento–actividad a uno a uno, con autor, lead y tipo compatibles.

**Evidencia / fecha de validación:** 01/10/2026: migración de datos 20261001145242 (eb73df1b) y núcleo 20261001160219 (fda9310e) en feat/llamadas-f2; npm run test:llamadas:local 82/82 en banco reducido (57 mutantes cazados). Sin aplicar en ningún entorno compartido..

### F2.3 · Aplicar ámbito y permisos

**Estado:** hecha · **Avance:** 3/3 · **Responsable:** Claude (construye y prueba) · Miguel (aprueba y aplica).

- [x] **F2.3.1** Implementar núcleo de ingesta, match exacto, detalle, listado, asociación, enlace, descarte y gestión de equipos.
- [x] **F2.3.2** Resolver actor activo desde asignación; revalidar ámbito, actividad ajena y lead reasignado.
- [x] **F2.3.3** Cerrar RLS y EXECUTE; documentar excepción single-tenant y contratos de puertas DEFINER.

**Evidencia / fecha de validación:** 01/10/2026: núcleo y 11 puertas (fda9310e); oráculo con actores simulados (43 defensas), 25 mutantes del núcleo cazados, reversa del núcleo en orden y fuera de orden. Sin aplicar en ningún entorno compartido..

### F2.4 · Verificar el núcleo

**Estado:** en curso · **Avance:** 2/3 · **Responsable:** Claude (banco local) · Miguel (banco de producción, revisión y OK).

- [x] **F2.4.1** Probar IDs repetidos, payload incompatible, dos consumidores, llamadas cercanas y bajas de actor/equipo.
- [x] **F2.4.2** Ejecutar SQL y gate RLS ampliado en entorno aislado; revisión LEVEL 3 y advisors aplicables.
- [ ] **F2.4.3** Completar comentarios, ledger de migraciones y evidencia de aceptación antes de habilitar consumidores. — EN CURSO: COMMENT completos (los exige el postflight) y ledger con las doce, todas sin aplicar. Los consumidores siguen cerrados (LLAMADAS_CELULAR_APROBADAS = false). Falta: aplicar, marcar «EN PROD», verificar V1–V5 y recién entonces abrir el interruptor (Miguel).

**Evidencia / fecha de validación:** pendiente.

**Aceptación:** entorno aislado, SQL del núcleo, gate RLS ampliado y unicidad bajo concurrencia; sin privilegios públicos innecesarios. `COMMENT ON`, `MIGRACIONES.md`, advisors y revisión LEVEL 3 con evidencia según gates vigentes.

## 9. F3 · Captura, puertas y sincronización durable

**Objetivo:** cada evento capturado llega una sola vez lógicamente aunque el transporte reintente.

| Puerta propuesta | Consumidor y control |
| --- | --- |
| Ingerir evento | Solo servicio; token → asignación → actor activo → ámbito |
| Listar accionables paginados | Autenticado y ámbito; incluye desconocidos y ambiguos |
| Obtener por UUID | Autorizado; explica «ya registrado» aunque no esté en pendientes |
| Resolver/asociar lead | Ámbito, confirmación, método y auditoría |
| Enlazar actividad existente | Autor/lead/tipo compatibles, uno a uno y transacción |
| Descartar con motivo | Política F2 idéntica en UI y servidor |
| Listar/alta/baja/rotar celular | Capacidad de administración resuelta en servidor |
| Registrar salud | Credencial de equipo, datos mínimos; heartbeat no demuestra captura sana |

**Seguimiento de F3:** 6/13 tareas completadas · Estado: en curso · Responsable nominal: por asignar.

### F3.1 · Publicar el contrato de puertas

**Estado:** hecha · **Avance:** 3/3 · **Responsable:** Jhosep (decisiones provisionales) · Miguel (ratifica) · Claude (construye).

- [x] **F3.1.1** Implementar ingesta, listado paginado, detalle por UUID, asociación, enlace, descarte y salud.
- [x] **F3.1.2** Restringir administración de equipos por capacidad y resolver actor/ámbito en servidor.
- [x] **F3.1.3** Definir respuesta estable y errores distinguibles; generar tipos del contrato para sus consumidores.

**Evidencia / fecha de validación:** 01/10–06/10: ingesta, puertas y salud probadas en banco reducido y en el banco de Miguel; tipos generados en main (5df2764e)..

### F3.2 · Proteger la ingesta

**Estado:** en curso · **Avance:** 1/3 · **Responsable:** Claude (construye) · Miguel (aprueba y aplica).

- [ ] **F3.2.1** Configurar Edge con esquema estricto, tamaño limitado, token propio y autenticación de plataforma verificada. — EN CURSO: Edge crm-llamadas-ingesta en main: esquema estricto, cuerpo ≤ 4 KB, clave en la cabecera, verify_jwt = false documentado; 17 pruebas y 18 mutantes. Falta desplegarla y comprobar en la plataforma que verify_jwt quedó apagado solo ahí (Miguel).
- [x] **F3.2.2** Aplicar rate limit compartido, baja/inactividad y rotación/revocación con auditoría.
- [ ] **F3.2.3** Mostrar token una vez; guardar hash y eliminar secretos de URL, logs y soporte. — EN CURSO: Solo el sha256 en la base; la clave viaja en una cabecera, nunca en la URL; la Edge no escribe registros; la tarjeta de F4-c (#215) la muestra una vez y la saca de los registros (credencial en CLAVES_SENSIBLES); el registro de MacroDroid no la muestra (prueba 6, 02/10). Falta la guía de soporte sin secretos y comprobarlo en el despliegue.

**Evidencia / fecha de validación:** pendiente.

### F3.3 · Persistir y enviar

**Estado:** en curso · **Avance:** 2/4 · **Responsable:** Jhosep (pruebas en C1) · Claude (receptor de pruebas).

- [x] **F3.3.1** Crear ID, hora y payload una vez; guardar en cola local antes del POST.
- [x] **F3.3.2** Reintentar red caída, 429 y reinicio; retirar solo tras confirmación y visibilizar errores permanentes.
- [ ] **F3.3.3** Parsear respuesta y abrir UUID confirmado; mantener fallback manual si falta UUID. — EN CURSO: Resuelta por la vía de la #12: la macro no espera un UUID del servidor; abre la encuesta enseguida con el número y el id de origen (/{lv=id_llamada}, P2 del 06/10 contra el receptor). Respaldo manual: la pestaña «Llamadas del celular». Falta la aceptación contra la Edge (P1–P3 de F4-d).
- [ ] **F3.3.4** Correlacionar doble trigger y validar dirección/duración por evento sin confundir desconocido con cero. — EN CURSO: En C1 (02/10): una sola notificación y un solo aviso por llamada en más de 8 llamadas, incluidas colgar antes de que contesten y sin respuesta (prueba 5). La dirección la marca «Llamadas-Salientes» y las entrantes no generan aviso (A2). La duración no se envía (MacroDroid no la da) y llega null, no 0. Falta: llamada en espera, doble SIM y entrantes si se aprueba la #14.

**Evidencia / fecha de validación:** pendiente.

### F3.4 · Probar recuperación

**Estado:** en curso · **Avance:** 0/3 · **Responsable:** Jhosep (pruebas en C1) · Claude (receptor de pruebas y guía).

- [ ] **F3.4.1** Ensayar respuesta perdida tras commit, ráfagas, bloqueo, batería, desfase y permisos revocados. — EN CURSO: En C1 contra el receptor: sin red (A3), servidor caído (A4), reinicio (A6) y, el 07/10, RÁFAGA de 3 salientes en 48 s: 3 avisos distintos, cada uno con su id, sin repetidos ni rechazos (REGISTRO.md §5h); reloj desfasado visible en la salud (undécima). Faltan respuesta perdida tras guardar, batería baja, desfase de hora en el celular y permisos revocados; repetir contra la Edge.
- [ ] **F3.4.2** Verificar dos llamadas al mismo número, baja/rotación de token y actor inactivo, por equipo piloto. — EN CURSO: Dos llamadas al mismo número → dos eventos, cada uno con su id (prueba 2 en C1). Rotación, cierre de la clave y analista de baja: probados en el banco reducido y escritos en el bloque testLlamadasCelular del gate (sin correr aquí). Falta repetirlo con la Edge desplegada y por equipo piloto.
- [ ] **F3.4.3** Entregar guía de soporte y salud de cola; decidir otro adaptador si MacroDroid no acredita durabilidad. — EN CURSO: Guía de la macro en macrodroid.md §3c; latido cada 6 h probado (P1, 06/10). MacroDroid acredita durabilidad (decisión 5 de F3), pero la versión gratuita se apaga sola al vencer sus días: #18. Falta la guía de soporte.

**Evidencia / fecha de validación:** pendiente.

**Aceptación:** respuesta perdida tras guardar → reenvío devuelve mismo ID; dos llamadas al mismo número siguen siendo dos; equipo/actor inactivo no ingresa; retrasos y errores visibles. Si MacroDroid no conserva cola fiable en las pruebas, documentar el límite y evaluar otro adaptador antes de prometer captura durable.

**Alternativas condicionadas:** Tasker o app específica solo para fallos demostrados. `%CODUR` es la duración de la última llamada saliente; validar correspondencia con el evento y no generalizar a entrantes.

## 10. F4 · Bandeja y registro conciliado en celular y PC

**Objetivo:** cerrar el circuito recuperando fallos sin duplicar gestiones.

**Seguimiento de F4:** 0/13 tareas completadas · Estado: en curso · Responsable nominal: por asignar.

### F4.1 · Construir la bandeja

**Estado:** en curso · **Avance:** 0/3 · **Responsable:** Claude (código) · Miguel (instala) · Jhosep (C1).

- [ ] **F4.1.1** Mostrar pendientes por registrar, identificar y devolver en Hoy/Alertas, con hora y retraso. — EN CURSO: Probada (sin instalar): pestaña «Llamadas del celular» en Gestión Diaria (F4-b, decisión 3 de F4), suite de la app y E2E 17/17 (06/10). Detrás del interruptor. Falta la aceptación en C1 (F4-d); «devolver» llega con la #14.
- [ ] **F4.1.2** Obtener detalle por UUID; explicar ya registrado, inaccesible, depurado o error sin filtrar datos. — EN CURSO: Probada (sin instalar): detalle y motivos de «no se unió» sin datos de terceros (F4-b). Falta la aceptación en C1 y comprobar el caso «depurado».
- [ ] **F4.1.3** Ofrecer el mismo circuito en celular y PC; cerrar el diálogo conserva el pendiente. — EN CURSO: Probada (sin instalar): el mismo circuito en celular y PC (F4-b); la décima une lo registrado desde la pestaña. Falta P6 y P7 de F4-d.

**Evidencia / fecha de validación:** pendiente.

### F4.2 · Registrar y enlazar

**Estado:** en curso · **Avance:** 0/4 · **Responsable:** Claude (código) · Miguel (instala) · Jhosep (C1).

- [ ] **F4.2.1** Propagar contexto del evento y confirmación real de actividad_id mediante formulario/store. — EN CURSO: Probada (sin instalar): el id viaja de la URL a la encuesta y la v5 devuelve el recibo real (5df2764e). Falta P1–P3 de F4-d.
- [ ] **F4.2.2** Componer v4 + enlace en transacción sin alterar núcleo sellado; revisar recibos, replays y locks. — EN CURSO: Probada (sin instalar): crm.registrar_llamada_v5 (F4-a) en una transacción con la v4 sellada; séptima sin ciclo con Deshacer; duodécima con revalidación. Banco reducido 415/415, banco de Miguel 197/197. Falta instalar y confirmar el sello de la v4 (F4.4.3).
- [ ] **F4.2.3** Si la composición no es viable, implementar intención de enlace persistente y conciliación durable con reintentos. — EN CURSO: Probada (sin instalar): la composición resultó viable y además existe la intención durable: si el aviso llega tarde, la ingesta la cumple. Falta instalar y P1 de F4-d.
- [ ] **F4.2.4** Proponer y confirmar enlace para registros previos o desde PC; nunca decidir solo por ±10 minutos. — EN CURSO: Probada (sin instalar): asociación manual a un resultado ya guardado (vía manual); el camino exacto no usa la regla de ±10 minutos. Falta la aceptación en C1.

**Evidencia / fecha de validación:** pendiente.

### F4.3 · Resolver casos operativos

**Estado:** en curso · **Avance:** 0/3 · **Responsable:** Claude (código) · Miguel (revisa e instala) · Jhosep (C1).

- [ ] **F4.3.1** Asociar únicamente a lead visible; crear por flujo existente y reintentar asociación tras alta confirmada. — EN CURSO: Probada en parte (sin instalar): asociar a un lead visible (las ambiguas). Crear el lead y reintentar no aplica mientras los números sin lead no se guarden (decisión 3a; #10). Falta la aceptación en C1.
- [ ] **F4.3.2** Administrar celulares: alta, baja, rotación, salud y atribución histórica, con token mostrado una vez. — EN CURSO: Probada y en main: tarjeta «Celulares» (F4-c, #215, aprobado por Miguel y fusionado el 07/10, 5f42e908): unitarias, MSW y pantalla; E2E Docker 4/4; P2 de la revisión corregido (d7d498d2); validación de cierre de Miguel PASS (6366/6366, E2E 4/4). Falta instalar; después, paso 2 de ACTIVAR-C1.md.
- [ ] **F4.3.3** Conservar evidencia y vínculo al deshacer; mostrar efectos anulados y no fabricar otra gestión. — EN CURSO: Probada (sin instalar): Deshacer mueve el enlace al corregido; efectos_anulados en el detalle; «deshecho» en «Qué pasó hoy». Falta P9 de F4-d.

**Evidencia / fecha de validación:** pendiente.

### F4.4 · Validar el circuito

**Estado:** en curso · **Avance:** 0/3 · **Responsable:** Jhosep (C1) · Claude (guía y registro) · Miguel (consulta sin números).

- [ ] **F4.4.1** Probar evento antes/después, dos llamadas cercanas, guardado confirmado con enlace fallido y dos pestañas.
- [ ] **F4.4.2** Probar edición mientras llega otra llamada, alta/asociación fallida, deshacer y lead reasignado.
- [ ] **F4.4.3** Ejecutar checks, E2E local y prueba física; confirmar sello v4 y ausencia de actividades duplicadas. — EN CURSO: Checks y E2E locales en verde (app 6338; E2E 17/17 y 4/4). Falta la prueba física (F4-d) y la consulta de Miguel sin números: recibidas, guardadas, sin duplicados y sello de la v4 intacto.

**Evidencia / fecha de validación:** pendiente.

**Aceptación:** evento antes/después, PC/celular, dos llamadas en diez minutos, guardado confirmado y enlace fallido, dos pestañas, edición interrumpida por otra llamada, alta de lead con asociación fallida, deshacer y reasignación. Nunca duplicar actividad para reparar un resultado.

Validación de extremo a extremo en Docker local y teléfono físico; v4 conserva su sello y comportamiento probado.

## 11. F5 · Jev para identificación asistida

**Objetivo solicitado:** relacionar mejor el número marcado por el analista con los contactos del CRM cuando las reglas exactas dejan ambigüedad o datos incompletos.

### 11.1 Responsabilidad de cada parte

| Caso | Decisión | Conducta |
| --- | --- | --- |
| Canónico exacto, único y autorizado | Código | Asociación determinista con procedencia |
| Llamada desde ficha CRM | Código + evento real | Conservar lead/número intentados y comparar número capturado; el analista pudo cambiarlo en el marcador |
| Número compartido y contexto útil | Jev propone; persona confirma | Ordenar candidatos existentes mostrando datos verificables |
| Teléfono dentro de una nota | Código extrae; Jev puede elegir rol | Copiar fragmento original, canonizar y verificar; no generar dígitos |
| Un dígito diferente | Código/persona | Tratar como otro número; no «corregir» por parecido |
| Oculto o contexto insuficiente | Abstención | Identificación manual o pendiente |
| Proveedor caído/respuesta inválida | Código | Continuar búsqueda y registro manual |

Recuperar candidatos **antes** de Jev, con permisos y evidencia. Sin match, usar selección manual o contexto verificable para producir candidatos acotados; no recorrer toda la cartera con IA. Si faltan candidatos fundamentados, abstenerse.

### 11.2 Contrato propuesto

Integración en servidor, sin credenciales TypeSafe en PWA. Entrada: identificadores opacos de candidatos y contexto mínimo pertinente, como nombre/alias permitido, relación relevante e historial confirmado. Igualdades y discrepancias de teléfonos se calculan por código; el juicio sobre esos indicadores no requiere enviar dígitos completos.

Salida tipificada, adaptada al SDK vigente: candidato de la lista, `ninguno` o `evidencia_insuficiente`, más scores/probabilidades de la primitiva. Validar pertenencia a lista, ámbito y versión de contexto antes de mostrar. La confianza del modelo no es prueba de identidad ni garantía de exactitud.

Mostrar hechos disponibles, no explicaciones inventadas: «Figura como alternativo», «Compartido con otro lead», «Asociación confirmada en fecha…». Notas y textos son datos, nunca instrucciones para modificar permisos o ejecutar acciones.

### 11.3 Etapas y entregables

**Seguimiento de F5:** 0/15 tareas completadas · Estado: pendiente · Responsable nominal: por asignar.

#### F5.1 · Banco y baseline

**Estado:** pendiente · **Avance:** 0/3 · **Responsable:** por asignar.

- [ ] **F5.1.1** Crear casos sintéticos y luego autorizados/etiquetados: compartidos, reciclados, ocultos y contexto contradictorio.
- [ ] **F5.1.2** Separar familias de teléfonos/leads entre ajuste y evaluación reservada para evitar contaminación.
- [ ] **F5.1.3** Medir reglas exactas y reglas + historial; no reutilizar el 19/20 del juicio nota/resultado.

**Evidencia / fecha de validación:** pendiente.

#### F5.2 · Evaluación fuera de línea

**Estado:** pendiente · **Avance:** 0/3 · **Responsable:** por asignar.

- [ ] **F5.2.1** Recuperar candidatos autorizados antes de Jev y construir contexto mínimo con identificadores opacos.
- [ ] **F5.2.2** Validar salida tipificada, pertenencia a candidatos, abstención, ámbito y vigencia de contexto.
- [ ] **F5.2.3** Comparar reglas + Jev; fijar abstención antes de evaluar y acordar límites de riesgo, coste y latencia.

**Evidencia / fecha de validación:** pendiente.

#### F5.3 · Modo sombra

**Estado:** pendiente · **Avance:** 0/3 · **Responsable:** por asignar.

- [ ] **F5.3.1** Resolver credenciales, tratamiento y retención antes de utilizar datos reales autorizados. — BLOQUEADA: Antes de usar datos reales: rotar la clave de TypeSafe (Jev) pegada en un chat el 20/09 (scripts/jev/README.md:45) y fijar tratamiento y retención (Miguel).
- [ ] **F5.3.2** Calcular propuestas sin modificar asociaciones, tareas ni resultados.
- [ ] **F5.3.3** Registrar discrepancias, errores, cobertura, incertidumbre, coste y latencia con datos mínimos.

**Evidencia / fecha de validación:** pendiente.

#### F5.4 · Asistencia opt-in

**Estado:** pendiente · **Avance:** 0/3 · **Responsable:** por asignar.

- [ ] **F5.4.1** Mostrar hechos verificables y sugerencias; exigir confirmación humana para resolver ambigüedad.
- [ ] **F5.4.2** Auditar propuesta y decisión con versión de modelo/reglas; historial acotado, revocable y con vigencia.
- [ ] **F5.4.3** Probar proveedor caído, candidato inválido y cambio de permisos; continuar por vía determinista/manual.

**Evidencia / fecha de validación:** pendiente.

#### F5.5 · Decidir activación

**Estado:** pendiente · **Avance:** 0/3 · **Responsable:** por asignar.

- [ ] **F5.5.1** Revisar falsos positivos, correcciones, resolución y tiempo de revisión frente al banco reservado.
- [ ] **F5.5.2** Registrar decisión de activar cohorte, ajustar o mantener OFF, con evidencia y responsable.
- [ ] **F5.5.3** Confirmar que F6–F7 funcionan con Jev OFF; no habilitar asociación semántica automática.

**Evidencia / fecha de validación:** pendiente.

**Medición:** precisión de casos resueltos, asociaciones equivocadas, cobertura de ambiguos, abstenciones, correcciones, tiempo de revisión, latencia y coste por caso. Informar tamaño de muestra e incertidumbre; cero fallos observados no equivale a error real cero. Más cobertura no compensa adjudicar llamadas al lead equivocado.

**Puerta de salida:** mejora medida frente al baseline reservado, sin degradar exactos; revisión de falsos positivos; límites de coste/latencia/riesgo acordados antes de piloto; fallback probado y tratamiento autorizado. Sin mejora o evidencia suficiente, F5 queda OFF y F6–F7 continúan.

**Historial confirmado:** guardar ámbito, actor, fecha, procedencia y vencimiento/revisión; permitir revocar. Ayuda a sugerir, pero no cambia automáticamente teléfonos del lead ni convierte un número en identidad global permanente. Revalidar frente a compartidos, reciclados, reasignaciones o contradicciones.

**Piloto existente:** el 19/20 sintético de F4.1 trata contradicción nota/resultado, no identificación. No reutilizarlo como precisión telefónica. Resolver antes de datos reales los pendientes de credenciales/condiciones documentados que continúen vigentes; reutilizar cliente/gates solo si su contrato es compatible.

## 12. F6 · Gerencia y calidad de evidencia

**Objetivo:** cifras interpretables sin alterar las métricas comerciales existentes.

**Seguimiento de F6:** 0/12 tareas completadas · Estado: pendiente · Responsable nominal: por asignar.

### F6.1 · Definir métricas

**Estado:** pendiente · **Avance:** 0/3 · **Responsable:** Claude (contrato) · Miguel (aprueba).

- [ ] **F6.1.1** Separar detectadas, elegibles, enlazadas y pendientes de resultado, identificación o devolución.
- [ ] **F6.1.2** Acordar denominadores y exclusiones para perdidas, no comerciales, desconocidos y efectos deshechos.
- [ ] **F6.1.3** Conservar métricas vigentes de actividades; no sumar eventos y gestiones como si fueran distintos resultados.

**Evidencia / fecha de validación:** pendiente.

### F6.2 · Medir salud y tiempo

**Estado:** en curso · **Avance:** 0/3 · **Responsable:** por asignar.

- [ ] **F6.2.1** Agrupar ocurrencia en America/Lima con intervalos [inicio, fin) y actor/asignación históricos.
- [ ] **F6.2.2** Mostrar retraso de entrega/registro, sincronización confirmada, cola y antigüedad de la señal. — EN CURSO: La tarjeta de F4-c ya muestra la cola y las horas sin latido (sin hora exacta). Falta el retraso de entrega y de registro.
- [ ] **F6.2.3** Distinguir cobertura insuficiente de cero llamadas; heartbeat solo no acredita captura sana.

**Evidencia / fecha de validación:** pendiente.

### F6.3 · Construir reporte e histórico

**Estado:** pendiente · **Avance:** 0/3 · **Responsable:** Claude (construye) · Miguel (aprueba).

- [ ] **F6.3.1** Implementar lecturas y pantalla de gerencia bajo ámbito autorizado con diccionario de métricas.
- [ ] **F6.3.2** Elegir ventana histórica limitada o agregados minimizados con retención propia antes de depurar.
- [ ] **F6.3.3** Actualizar eventos tardíos sin duplicar y mostrar límites de cobertura y retención.

**Evidencia / fecha de validación:** pendiente.

### F6.4 · Reconciliar y aceptar

**Estado:** pendiente · **Avance:** 0/3 · **Responsable:** por asignar.

- [ ] **F6.4.1** Contrastar muestra con registro del teléfono, eventos, enlaces y actividades.
- [ ] **F6.4.2** Probar lunes recibido el martes, reasignación, deshacer, equipo sin señal y efecto de purga.
- [ ] **F6.4.3** Obtener validación de negocio, ejecutar checks de las capas tocadas y documentar evidencia.

**Evidencia / fecha de validación:** pendiente.

**Aceptación:** explicar evento del lunes recibido/registrado martes, cambio de asignación, deshacer, equipo sin sincronizar y efecto de retención. Negocio valida definiciones antes de evaluar desempeño. F6 depende de F4 y puede operar con Jev OFF.

## 13. F7 · Despliegue gradual y operación

**Seguimiento de F7:** 0/12 tareas completadas · Estado: pendiente · Responsable nominal: por asignar.

### F7.1 · Aceptar el piloto

**Estado:** pendiente · **Avance:** 0/3 · **Responsable:** por asignar.

- [ ] **F7.1.1** Completar validación integral en equipos admitidos y documentar limitaciones por marca/Android.
- [ ] **F7.1.2** Revisar evidencias F0–F6 y registrar decisión de Jev; resolver bloqueos o diferidos justificados.
- [ ] **F7.1.3** Asignar responsables operativos y criterios para detener o ampliar cohortes.

**Evidencia / fecha de validación:** pendiente.

### F7.2 · Preparar soporte y reversa

**Estado:** en curso · **Avance:** 0/3 · **Responsable:** Claude.

- [ ] **F7.2.1** Entregar guía de permisos, cola, token perdido, cambio de equipo y baja de analista. — EN CURSO: Borradores: flujos de celular nuevo, pérdida y baja (F4C-F4D-PLAN-CORTO.md), ACTIVAR-C1.md y macrodroid.md §3c. Falta una sola guía de soporte.
- [ ] **F7.2.2** Documentar reasignación, números compartidos y corrección/revocación de asociaciones.
- [ ] **F7.2.3** Probar apagado independiente de captura, apertura y Jev; conservar evidencia y registro manual.

**Evidencia / fecha de validación:** pendiente.

### F7.3 · Publicar por cohortes

**Estado:** pendiente · **Avance:** 0/3 · **Responsable:** por asignar.

- [ ] **F7.3.1** Ejecutar gates y procedimiento humano de release; verificar commit local y avancecorp/main.
- [ ] **F7.3.2** Construir/publicar solo el artefacto del commit verificado conforme a las reglas vigentes.
- [ ] **F7.3.3** Habilitar cohortes pequeñas, observar salud/incidencias y detener o ampliar según los criterios.

**Evidencia / fecha de validación:** pendiente.

### F7.4 · Cerrar y mantener

**Estado:** pendiente · **Avance:** 0/3 · **Responsable:** por asignar.

- [ ] **F7.4.1** Registrar fechas reales, aceptación, incidencias pendientes y responsables de seguimiento.
- [ ] **F7.4.2** Entregar diccionario de métricas y confirmar operación de retención y salud.
- [ ] **F7.4.3** Actualizar plan, FigJam y vault con evidencia y decisiones; no borrar datos como reversa operativa.

**Evidencia / fecha de validación:** pendiente.

**Reversa:** detener captura/ingestión o aperturas por equipo, preservar evidencia y flujo habitual, desactivar Jev y reparar/conciliar. `DROP` solo en pruebas vacías; borrado tras datos reales requiere política y decisión específica.

## 14. Matriz de pruebas y terminado por fase

| Área | Casos mínimos | Fases |
| --- | --- | --- |
| Teléfono | Local/canónico, fijo, internacional, mismo sufijo/diferente país, alternativo, compartido, oculto, inválido, fuera de primera página, incompleto | F0–F2, F5 |
| UX | Foco/hash ambos órdenes, boot/login, remount, pestañas, otra cuenta, llamada durante edición, cierre | F1, F4 |
| Transporte | Offline, reinicio, 429, respuesta perdida tras commit, ID repetido/payload distinto, doble trigger, desfase, permisos revocados | F2–F3 |
| Ámbito | Actor inactivo, token revocado, actividad ajena, lead reasignado, acceso cruzado, rol sin permiso, EXECUTE | F2–F4 |
| Integridad | Evento antes/después, PC/celular, llamadas cercanas, concurrencia, enlace fallido, alta de lead, deshacer, entrante perdida | F2–F4 |
| Jev | Sin candidatos, insuficiente, candidato inválido, contexto vencido, proveedor caído, cambio de permiso, coste/latencia | F5 |
| Métricas | Tardíos, fecha Lima, falta de señal, cambio de asignación, purga y ventana histórica | F6–F7 |

Antes de declarar terminada una fase de código:

- [ ] Aplicar `.ai/REVIEW_PROTOCOL.md`, `.ai/VERIFICATION.md` y reglas vigentes; revisión independiente según riesgo, sin recursión.
- [ ] Ejecutar checks pertinentes y reportar `PASS`, `FAIL` o `NOT RUN` con causa. Dictamen de reviewer no prueba ejecución.
- [ ] Frontend: `npm run check` en `CRM-Avance-Corp/app`, pruebas dirigidas y accesibilidad según alcance.
- [ ] E2E solo Docker local: desde `CRM-Avance-Corp/app`, `npm run test:e2e:docker` con spec pertinente. Nunca E2E en GitHub Actions. Docker apagado: `NOT RUN (Docker off)`.
- [ ] Base: SQL núcleo/puertas, `test-rls.mjs`, advisors, tipos regenerados, permisos y sello v4 verificados.
- [ ] Esquema nuevo con comentarios, índices justificados, ledger y retención operativa.
- [ ] Prueba física cuando dependa del celular; evidencia saneada sin teléfonos reales ni secretos.
- [ ] Plan y FigJam actualizados con estado real y evidencia; pendientes no significan funcionalidad disponible.

## 15. Privacidad, retención y proveedores

Antes de datos reales: finalidad, acceso, comunicación al personal, tratamiento de terceros y condiciones de proveedores. Firma del analista no resuelve por sí sola tratamiento de números ajenos. La revisión correspondiente considera el marco vigente; este plan técnico no determina base legal.

| Datos | Propuesta / decisión pendiente |
| --- | --- |
| Número crudo | Evitar persistencia innecesaria; si diagnóstico lo exige, plazo corto y acceso restringido por fijar en F2 |
| Sin identificar/descartados | Referencia inicial 30 días; validar finalidad, excepciones y depuración antes de capturar |
| Pendientes/identificados/registrados | Plazo propio antes de F2; no indefinido por omisión |
| Historial confirmado | Caducidad, ámbito, revocación y revisión; no libreta global de identidades |
| Logs y contexto/respuestas Jev | Mínimos datos, sin secretos/notas completas innecesarias; plazo propio |
| Métricas agregadas | Ventana e identificación explícitas; retención justificada independiente |

El backend actual ya implica proveedores del CRM. Jev/TypeSafe añade tratamiento: empezar con sintéticos y habilitar reales solo con alcance, condiciones, credenciales, acceso y retención resueltos. No enviar cartera completa, DNI, contratos ni notas sensibles innecesarias.

## 16. Decisiones pendientes

| Decisión | Recomendación inicial | Cierre / responsable |
| --- | --- | --- |
| Apertura y registro PC/celular | Piloto con bandeja y notificación local de respaldo | F0 / negocio y soporte |
| Campos reales por equipo | Duración opcional; desconocido si no acreditado | F0–F3 / soporte y backend |
| Elegibilidad comercial | Salientes a leads y entrantes atendidas; perdidas como devolución; validar excepciones | Antes F2 / negocio |
| Retención/proveedores | Matriz completa y Jev OFF hasta autorizar tratamiento | Antes F2 y F5 real / datos |
| v4 + enlace | Preferir transacción; alternativa durable con pruebas | Antes F4 / backend y reviewer |
| Asociación histórica | Acotada, revocable, vigente; sin cambio automático de teléfonos | Antes F5 / negocio y backend |
| Umbrales Jev | Coste, latencia y riesgo con banco; sin porcentaje inventado | Antes piloto F5 / negocio y QA |
| Histórico gerencia | Ventana limitada o agregado minimizado, cobertura explícita | Antes F6 / gerencia y datos |
| Calendario/nombres | Estimar tras F0; no asignaciones ficticias | Cierre F0 / proyecto |

## 17. Ejecución, repositorio y publicación

Ruta canónica: `CRM-Avance-Corp/GESTION DIARIA/AUTOMATIZACION DE LLAMADAS/Plan — Llamadas desde el celular al CRM.md`. No usar la ruta inexistente del borrador en `docs/plans/`. Esta carpeta está ignorada por Git en la copia revisada: entregar el MD local no implica incluirlo en un commit. Si se requiere versionarlo, acordar ubicación o excepción específica sin añadir todo `GESTION DIARIA` accidentalmente.

Antes de una fase, leer instrucciones, `Inicio.md` y notas del tema; usar CodeGraph primero para navegar código. Preservar cambios ajenos. Un PRIMARY escribe; implementaciones simultáneas independientes necesitan checkouts acordados, no creados automáticamente.

Las ramas de trabajo siguen reglas vigentes. `main` local sigue `avancecorp/main`, no `origin/main` ni `avancecorp/tronco`. Antes de publicar: integrar sin sobrescribir remotos y verificar mismo commit en Main local y `avancecorp/main`; construir desde ese commit y ejecutar release humano/preflight vigente. Respetar solo la excepción de rescate descrita por el proyecto; sin ramas extra de release ni `push --force`.

SQL se valida en entorno aislado y sigue el flujo aprobado de migraciones, nunca producción directa por aprobar este documento.

Prompt sugerido para iniciar una fase autorizada:

```text
Eres PRIMARY. Lee AGENTS.md, CLAUDE.md, .ai/REVIEW_PROTOCOL.md,
.ai/VERIFICATION.md e Inicio.md del vault. Usa CodeGraph primero.
Lee el plan canónico en:
CRM-Avance-Corp/GESTION DIARIA/AUTOMATIZACION DE LLAMADAS/
Plan — Llamadas desde el celular al CRM.md

Ejecuta solo F<N> indicada y autorizada por el usuario.
Contrasta dependencias, contrato y estado del repo antes de escribir.
Preserva cambios ajenos y núcleo sellado v4. No publiques por inferencia.
Si toca C1–C3, concreta diseño y aplica gate de revisión vigente.
Adjunta evidencia saneada; solo PRIMARY implementa.
Corre checks, E2E solo Docker local, reporta PASS/FAIL/NOT RUN.
Actualiza plan, tablero y memoria con evidencia real.
```

## 18. Verificación de esta entrega y referencias

**Verificación documental de la versión 3:** ocho fases F0–F7, 33 subfases y 102 tareas con IDs únicos y casillas. Se conserva la versión 2 en `historial/`. Figma y Markdown usan los mismos IDs, dependencias y textos de tarea; estados y contadores se actualizan manualmente. La validación de esta estructura no marca ninguna tarea de implementación como realizada.

**PASS:** paridad de las 102 tareas entre Markdown y FigJam, IDs sin duplicados, enlaces locales y formato. Revisión visual del tablero completo y del detalle de F5; sin desbordes ni solapamientos de texto en la comprobación estructural.

Consolidación documental. La revisión previa ejecutó **108 tests existentes en cinco archivos, PASS**: `contacto-tarea.test.ts`, `router.test.ts`, `telefono.test.ts`, `sla-operacion-comandos.test.ts` y `registrar-resultado.test.tsx`, mediante `npm run test:run --` y sus rutas de `app/src/`. También reprodujo diferencias de canonización y obtuvo una revisión independiente LEVEL 3 del diseño previo.

Eso no prueba las fases nuevas. **NOT RUN para funcionalidad futura:** Android, E2E de telefonía, SQL/RLS/advisors nuevos y evaluación Jev de identificación. Esta consolidación no activa el modelo ni envía datos de leads.

Fuentes oficiales consultadas en la investigación; confirmar versiones al implementar:

- TypeSafe: [Entity alignment](https://docs.typesafe.ai/cookbooks/entity_alignment), [Choice](https://docs.typesafe.ai/primitives/choice), [Confidence](https://docs.typesafe.ai/concepts/confidence), [candidatos extraídos previamente](https://docs.typesafe.ai/cookbooks/pre_parsed_value_extraction_cookbook). Sustentan juicios tipificados; no prueban mejora en esta cartera.
- MacroDroid: [Call Ended](https://wiki.macrodroid.com/wiki/index.php/Trigger:_Call_Ended), [Call Missed](https://macrodroidforum.com/wiki/index.php?title=Trigger%3A_Call_Missed), [HTTP Request](https://macrodroidforum.com/wiki/index.php/Action%3A_HTTP_Request). Configuración real por equipo requiere piloto.
- Android: [apertura desde segundo plano](https://developer.android.com/guide/components/activities/secure-bal), [CallLog.Calls](https://developer.android.com/reference/android/provider/CallLog.Calls). [Tasker: variables](https://tasker.joaoapps.com/userguide/en/variables.html).
- Supabase: [autorización de Edge Functions](https://supabase.com/docs/guides/functions/auth-headers). PostgreSQL: [UNIQUE](https://www.postgresql.org/docs/15/ddl-constraints.html#DDL-CONSTRAINTS-UNIQUE-CONSTRAINTS).
- ANPD: [DS 016-2024-JUS](https://www.gob.pe/institucion/anpd/normas-legales/6554453-n-016-2024-jus), referencia para revisión de tratamiento, no conclusión legal de este plan.

**Criterio final:** identidad correcta, evidencia recuperable y gestión sencilla. Jev es una asistencia evaluable y opcional; la integridad depende de contratos y validaciones del sistema.
