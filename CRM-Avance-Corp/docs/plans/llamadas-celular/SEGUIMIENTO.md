# Seguimiento conciliado — «Llamadas desde el celular» (07/10/2026)

Pedido por Miguel en el #215 (comentario del 07/10, 18:24 UTC). Cada una de las **102 tareas** del plan aprobado
(`PLAN.md`, Versión 3: 8 fases, 33 subfases) con su estado, la evidencia, el siguiente paso, quién lo hace y de qué
depende. Contrastado con `PLAN.md`, `estado.json` (espejo del tablero), los planes cortos, `REGISTRO.md`, el ledger
`MIGRACIONES.md` y los PR #148 a #217. Los IDs y el alcance son los aprobados: lo que cambia el alcance va como
propuesta (`PROPUESTAS-DE-AJUSTE.md`), nunca aquí.

## Cómo se lee

**Estados**, de menos a más:

| Estado | Qué significa |
| --- | --- |
| Pendiente | Sin empezar |
| Bloqueada | Espera una decisión o un paso de otro: la columna «Depende de» dice cuál |
| En curso | Empezada; la columna «Siguiente paso» dice qué falta |
| Escrita | Código, propuesta o documento hecho, sin prueba |
| Probada | Pasó pruebas automáticas: banco reducido local, banco de Miguel a paridad con producción, suite de la app o E2E en Docker. **Sin instalar** |
| Probada en C1 (receptor) | Probada en el celular contra el receptor de pruebas del PC. **No acredita la Edge real** |
| Instalada | Aplicada o desplegada en producción |
| Aceptada | Instalada y probada en el teléfono contra producción; o, si es una decisión, ratificada por Miguel |

**Casillas** (las marca solo Claude, con evidencia ejecutada): una tarea de **construir** se cierra con su prueba (banco
o C1, según lo que pida su texto); una de **probar en el equipo o en producción**, solo con esa prueba; una de
**decidir**, con la ratificación de Miguel. **Una fase no se cierra porque su código esté fusionado:** se cierra con su
aceptación (instalada y probada en el teléfono).

**Responsables:** Miguel (decide, instala, publica), Jhosep (celulares y pruebas físicas), Claude (código, documentos,
tablero).

## Resumen

| Fase | Tareas | Marcadas | Probadas sin instalar | En curso | Pendientes o bloqueadas | Estado de la fase |
| --- | --- | --- | --- | --- | --- | --- |
| F0 · Piloto y línea base | 12 | 1 | — | 7 | 4 | En curso: solo C1 |
| F1 · Formulario único | 12 | 12 | — | — | — | **Aceptada** (en producción desde el 01/10; C1 el 02/10) |
| F2 · Núcleo | 13 | 12 | — | 1 | — | En curso: falta instalar |
| F3 · Captura y sincronización | 13 | 5 | 2 | 6 | — | En curso: falta la Edge real |
| F4 · Bandeja y registro conciliado | 13 | 0 | 10 | 1 | 2 | En curso: falta instalar y F4-d |
| F5 · Jev | 15 | 0 | — | — | 15 | Pendiente |
| F6 · Gerencia y métricas | 12 | 0 | — | 1 | 11 (6 con propuesta escrita) | Bloqueada por decisiones (#17) |
| F7 · Despliegue y operación | 12 | 0 | — | 1 | 11 | Pendiente |
| **Total** | **102** | **30** | **12** | **17** | **43** | |

Antes de este repaso había 25 marcadas; suben 5 con evidencia ya existente (F2.1.1–F2.1.3 ratificadas, F2.4.2 por el
ensayo de Miguel en su banco y F3.1.3 porque los tipos ya están generados).

## Hitos comunes (de qué dependen casi todas las filas de abajo)

| Hito | Qué | Responsable | Estado al 07/10 |
| --- | --- | --- | --- |
| H0 | Las doce migraciones en `main` | Miguel | **Hecho** (#190, `d1f16fea`, 06/10 23:28 UTC) |
| H1 | Ensayo con **SLA activo** y aplicar las doce en producción desde LF, con sus registradores (`t`) y el ledger «EN PROD» | Miguel | Pendiente. Producción: **0/12**, SLA activo (comprobado por Miguel el 07/10). Checklist en el #215 |
| H2 | Edge `crm-llamadas-ingesta` desplegada y comprobada (`verify_jwt` apagado solo en ella; los `curl` dan «No autorizado») | Miguel | Pendiente |
| H3 | Release con `LLAMADAS_CELULAR_APROBADAS = true`: abre la pestaña de F4-b y la tarjeta de F4-c | Miguel | Pendiente. Requiere el #215 fusionado |
| H4 | Activar C1 (F4-d) con `ACTIVAR-C1.md` y correr P1–P15 | Jhosep + gerencia + Claude | Pendiente. La guía está escrita |
| H5 | Los otros equipos del piloto (C2, C3) | Jhosep + Miguel | Pendiente |

## F0 · Piloto y línea base

| ID | Tarea | Estado | Evidencia | Siguiente paso | Responsable | Depende de |
| --- | --- | --- | --- | --- | --- | --- |
| F0.1.1 | Elegir 2–3 celulares y registrar marca, Android, navegador, automatizador y batería | En curso (1 de 2–3) | C1: Samsung Galaxy A16, Android 16, Chrome, MacroDroid 5.67, batería sin restricción (`REGISTRO.md`, `compatibilidad.md`) | Elegir y registrar C2 (y C3) | Jhosep · Miguel elige equipos | Equipos corporativos; #18 (licencia por equipo) |
| F0.1.2 | Asignar analistas, soporte y responsable de incidencias | En curso | Jhosep cubre analista, soporte y registro mientras hay un solo celular | Nombrar los analistas de C2/C3 y el responsable de soporte | Miguel decide · Jhosep | F0.1.1 |
| F0.1.3 | Comunicar finalidad y tratamiento; instalar la PWA; permisos | En curso | C1 completo: PWA, permisos, «Abrir vínculos admitidos» + dominio (30/09) | Comunicar la finalidad a los analistas del piloto; repetir en C2/C3 | Miguel (comunicación) · Jhosep | F0.1.2 |
| F0.2.1 | Medir cinco días: llamadas desde el CRM, fuera del CRM, entrantes y WhatsApp | Pendiente | — | Planilla y cinco días de medición por equipo | Jhosep · analistas del piloto | F0.1.2; #16 para las entrantes |
| F0.2.2 | Anotar si el resultado se registra desde PC o celular y cuánto tarda | Pendiente | — | Dentro de la misma medición | Jhosep | F0.2.1 |
| F0.2.3 | Comparar capturas con el registro del teléfono: faltantes y duplicados | Pendiente | Se contó llamada por llamada en A1–A7 y P1–P5, sin conciliación formal | Conciliar teléfono → evento → actividad, mejor con la Edge real | Jhosep · Claude | F0.2.1; H4 |
| F0.3.1 | Diez salientes y diez entrantes por equipo; atendidas, perdidas, rechazadas y canceladas | En curso | C1: salientes con número (29/09) y en las pruebas de C1; entrantes bloqueadas (decisión 2 de Miguel) | Completar diez salientes con sus casos; entrantes según #16 | Jhosep | #16 |
| F0.3.2 | Oculto, fijo, internacional, doble SIM, enlace con +, login y vuelta a la PWA | En curso | Notificación con número; la URL abre la PWA (30/09); el número sobrevive al login (F1.2.2) | Probar oculto, fijo, internacional y doble SIM | Jhosep | — |
| F0.3.3 | Pantalla bloqueada, batería, tres noches, cola sintética, reinicio y respuesta HTTP | En curso | Noche 1/3; cola sin red (A3), reinicio (A6), 503 (A4), 400 (A5) y 401 (P4) en C1 contra el receptor | Dos noches, pantalla bloqueada y batería baja | Jhosep | — |
| F0.4.1 | `REGISTRO.md`, guía MacroDroid y matriz con evidencia por equipo | En curso | Los tres documentos con la evidencia de C1 (`REGISTRO.md` §5a–§5g) | Evidencia de C2/C3 y cerrar la matriz | Jhosep · Claude | F0.1.1 |
| F0.4.2 | Ejemplos sintéticos de teléfonos | **Hecha** | 23 casos en `ejemplos-sinteticos.md` (29/09), contrastados con la canonización de la base | Reutilizarlos en F5.1.1 | Claude | — |
| F0.4.3 | Decidir continuar o ajustar; responsables y calendario | Pendiente | — | Informe de cierre de F0 con la evidencia por equipo, para que Miguel decida | Claude prepara · Miguel decide | F0.1–F0.3 |

## F1 · Formulario único y coincidencia exacta — aceptada

Las doce tareas están **marcadas y aceptadas**: código en `main` (#148 `6ace8487`, reactivación #160 `20f7deea`),
publicado por Miguel el 01/10 con el #165 (release `crm-20261002T005155Z-4498582850b1`) y probado en C1 contra
producción el 02/10 (`REGISTRO.md` §5c). Evidencia de cada una en `AVANCE.md` y el tablero.

| ID | Siguiente paso | Responsable |
| --- | --- | --- |
| F1.1.1 a F1.4.3 | Conservar sus regresiones con cada ampliación: foco y hash en los dos órdenes, login, remount, dos pestañas, cambio de cuenta y otra llamada durante la edición. El resultado comercial sigue siendo decisión humana | Claude (en cada PR) |

## F2 · Núcleo confiable y contrato de datos

| ID | Tarea | Estado | Evidencia | Siguiente paso | Responsable | Depende de |
| --- | --- | --- | --- | --- | --- | --- |
| F2.1.1 | Elegibilidad, identificación, atención, dirección y estado técnico por separado | **Aceptada** (decisión) | Decisiones provisionales de Jhosep (30/09) ratificadas por Miguel el 03/10 en el #175 (decisiones 1–7) y vigentes en el código de `main` | — | — | — |
| F2.1.2 | Descarte motivado, entrante perdida como devolución y semántica de Deshacer | **Aceptada** (decisión) | Descarte con lista cerrada + «otro» con texto; Deshacer no borra ni desenlaza: el enlace pasa al corregido. La entrante perdida → devolución quedó aprobada con la #14 (02/10) como paso propio | La parte de entrantes se construye con la #14 | — | #14 |
| F2.1.3 | Hora de ocurrencia y recepción, retención por estado y atribución tras reasignaciones | **Aceptada** (decisión) | Hora del celular si llega, si no la del servidor; sin resultado → 30 días desde la recepción, las registradas se conservan (decisión 4 de Miguel); quién ve y trabaja = dueño actual, quién marcó se conserva (decisión 7) | La atribución **para métricas** es A1, aparte (F6) | — | — |
| F2.2.1 | Asignaciones inmutables y eventos con id de origen estable y carga inmutable | Probada · marcada | `20261001145242` y siguientes; banco reducido (415/415 el 06/10) y banco de Miguel | Instalar | Miguel | H1 |
| F2.2.2 | Tablas, índices y FK mínimos; actor histórico; sin número crudo | Probada · marcada | Ídem; el postflight exige índice por FK; sin columna de número crudo (decisión 6) | Instalar | Miguel | H1 |
| F2.2.3 | Unicidad e idempotencia del evento | Probada · marcada | **Contrato vigente (quinta, `20261005143843`):** el mismo id de origen es el mismo evento; el primero no se sobrescribe y el celular recibe el mismo 202 (guardada, repetida o ignorada). **Ya no existe el `P0409` ni el 409** | Instalar | Miguel | H1 |
| F2.2.4 | Enlace evento ↔ actividad uno a uno | Probada · marcada | Oráculo E1–E10 y mutantes; v5 y séptima | Instalar | Miguel | H1 |
| F2.3.1 | Núcleo de ingesta, coincidencia exacta, detalle, listado, asociación, enlace, descarte y celulares | Probada · marcada | Núcleo y puertas (`20261001160219` en adelante); oráculos; banco de Miguel 197/197 (06/10) | Instalar | Miguel | H1 |
| F2.3.2 | Actor activo desde la asignación; revalidar ámbito y lead reasignado | Probada · marcada | Oráculos; revalidación tras reasignación reforzada en la duodécima (`20261006162813`) | Instalar | Miguel | H1 |
| F2.3.3 | RLS y EXECUTE cerrados; excepción single-tenant y contratos DEFINER | Probada · marcada | Tablas sin privilegios para la API, RLS sin policies, puertas DEFINER con `search_path` vacío; advisors del banco de Miguel sin alertas nuevas (06/10) | Instalar; advisors en producción | Miguel | H1 |
| F2.4.1 | IDs repetidos, carga incompatible, dos consumidores, llamadas cercanas y bajas | Probada · marcada | Banco local con dos sesiones reales; banco reducido 415/415 | — | — | — |
| F2.4.2 | SQL y gate RLS ampliado en entorno aislado; revisión LEVEL 3 y advisors | Probada · **marcada ahora** | Banco de Miguel a paridad (06/10, `5df2764e`): bloque de llamadas **197/197**, advisors sin alertas nuevas, `auditor-rls` y Codex r2. El gate global sigue con los 8 fallos de fondo ajenos, en trabajo aparte | Repetir el ensayo con **SLA activo** antes de aplicar | Miguel | H1 |
| F2.4.3 | Comentarios, ledger y evidencia de aceptación antes de habilitar consumidores | En curso | `COMMENT` completos (los exige el postflight); ledger con las doce, todas sin aplicar; los consumidores siguen cerrados (interruptor apagado) | Aplicar, marcar «EN PROD», verificar V1–V5 y recién entonces abrir el interruptor | Miguel | H1, H3 |

## F3 · Captura, puertas y sincronización durable

| ID | Tarea | Estado | Evidencia | Siguiente paso | Responsable | Depende de |
| --- | --- | --- | --- | --- | --- | --- |
| F3.1.1 | Ingesta, listado paginado, detalle, asociación, enlace, descarte y salud | Probada · marcada | F3-a y siguientes; banco reducido; la salud sin hora exacta desde la undécima (`20261006150254`) | Instalar | Miguel | H1 |
| F3.1.2 | Administración de equipos por capacidad; actor y ámbito en el servidor | Probada · marcada | Asignar, rotar y cerrar: solo gerencia; la salud la leen gerencia (todos) y supervisión (su equipo) | Instalar | Miguel | H1 |
| F3.1.3 | Respuesta estable, errores distinguibles y tipos del contrato | Probada · **marcada ahora** | Respuesta uniforme que no revela si el número es de un lead (202 guardada/repetida/ignorada, 200 latido, 400, 401, 413, 415, 429 con `Retry-After`, 503; **sin 409**); la correlación va por `evento_origen_id`. **Los tipos ya están generados** (`database.types.ts`, `5df2764e`) y los usan F4-b y F4-c | Regenerar los tipos desde producción al publicar | Miguel | H1 |
| F3.2.1 | Edge con esquema estricto, tamaño limitado, clave propia y autenticación de plataforma verificada | Probada (sin desplegar) | `crm-llamadas-ingesta`: 17 pruebas y 18 mutantes; `verify_jwt = false` documentado | Desplegar y comprobar en la plataforma que `verify_jwt` quedó apagado solo ahí | Miguel | H2 |
| F3.2.2 | Límite compartido, baja/inactividad y rotación/revocación con auditoría | Probada · marcada | 30 por minuto y 600 al día; «No autorizado» uniforme, también en carrera | Instalar | Miguel | H1 |
| F3.2.3 | Clave visible una vez; solo su huella; nada secreto en URL, registros ni soporte | En curso | Hash sha256 en la base; cabecera, nunca URL; la Edge no escribe registros; la tarjeta de F4-c la muestra una vez (#215); el registro de MacroDroid no muestra la clave (prueba 6, 02/10) | Guía de soporte sin secretos; comprobarlo en el despliegue | Claude (guía) · Miguel (despliegue) | H2; F7.2.1 |
| F3.3.1 | Id, hora y aviso creados una vez y guardados en la cola antes del envío | Probada en C1 (receptor) · marcada | Macro final (02/10 y 06/10): A1, A3, A4, A6 | Repetir contra la Edge (P15) | Jhosep | H4 |
| F3.3.2 | Reintentar red caída, 429 y reinicio; retirar solo con confirmación; errores visibles | En curso | Sin red (A3), 503 (A4), reinicio (A6), 400 → `errores_llamadas` (A5), 401 conserva la cola (P4) | Ensayar un **429 explícito** (el receptor lo fuerza con `/_control?modo=429`); repetir contra la Edge | Jhosep · Claude | — ; H4 |
| F3.3.3 | Abrir lo confirmado y mantener el respaldo manual | Probada en C1 (receptor) | Por la vía decidida en la #12: la macro **no espera un UUID del servidor**; abre la encuesta enseguida con el número y el id de origen (P2, 06/10); el respaldo es la pestaña «Llamadas del celular» | Aceptación contra la Edge (P1–P3 de F4-d) | Jhosep | H4 |
| F3.3.4 | Doble disparo; dirección y duración por evento sin confundir desconocido con cero | En curso | Un solo aviso por llamada (prueba 5); entrantes sin aviso (A2); duración desconocida llega `null`, no 0 | Llamada en espera y doble SIM | Jhosep | — |
| F3.4.1 | Respuesta perdida tras guardar, ráfagas, bloqueo, batería, desfase y permisos revocados | En curso | Sin red, servidor caído y reinicio en C1 (receptor); reloj desfasado visible en la salud (undécima) | Los demás casos, contra la Edge | Jhosep | H4 |
| F3.4.2 | Dos llamadas al mismo número, baja/rotación de la clave y actor inactivo, por equipo | En curso | Dos eventos con su id (prueba 2); rotación, cierre y baja en banco y en el gate | Repetirlo contra la Edge y en cada equipo (P11 de F4-d) | Jhosep | H4, H5 |
| F3.4.3 | Guía de soporte y salud de la cola; otro adaptador si MacroDroid no acredita durabilidad | En curso | Guía de la macro (`macrodroid.md` §3c); latido cada 6 h probado (P1, 06/10); MacroDroid acredita durabilidad (decisión 5 de F3) | Guía de soporte; resolver que la versión gratuita **se apaga sola** | Claude (guía) · Miguel (#18) | #18 |

## F4 · Bandeja y registro conciliado en celular y PC

Todo lo de F4 está en `main` (F4-a y F4-b en el #190) o en revisión (F4-c en el #215), **detrás del interruptor y sin
instalar**. Ninguna casilla se marca hasta la aceptación en C1.

| ID | Tarea | Estado | Evidencia | Siguiente paso | Responsable | Depende de |
| --- | --- | --- | --- | --- | --- | --- |
| F4.1.1 | Pendientes por registrar, identificar y devolver, con hora y retraso | Probada | Pestaña «Llamadas del celular» en Gestión Diaria (F4-b; ubicación de la decisión 3 de F4): suite de la app y E2E 17/17 (06/10) | Aceptación en C1 (F4-d); «devolver» llega con la #14 | Miguel (H1, H3) · Jhosep (H4) | H1, H3, H4; #14 |
| F4.1.2 | Detalle; explicar registrado, inaccesible, depurado o error sin filtrar datos | Probada | Detalle y motivos de «no se unió» sin datos de terceros (F4-b) | Aceptación en C1; comprobar el caso «depurado» | Jhosep · Claude | H4 |
| F4.1.3 | El mismo circuito en celular y PC; cerrar el diálogo conserva el pendiente | Probada | F4-b; la décima (`20261006150154`) une lo registrado desde la pestaña | P6 y P7 de F4-d | Jhosep | H4 |
| F4.2.1 | Contexto del evento y confirmación real de `actividad_id` | Probada | El id viaja de la URL a la encuesta; la v5 devuelve el recibo (`5df2764e`) | P1–P3 de F4-d | Jhosep | H4 |
| F4.2.2 | v4 + enlace en una transacción sin tocar el núcleo sellado; recibos, repeticiones y candados | Probada | `crm.registrar_llamada_v5` (F4-a), séptima (sin ciclo con Deshacer) y duodécima (revalidación); banco 415/415 y 197/197 | Instalar; confirmar el sello de la v4 (F4.4.3) | Miguel | H1 |
| F4.2.3 | Intención de enlace persistente y conciliación durable | Probada | La composición resultó viable **y además** existe la intención durable: si el aviso llega tarde, la ingesta la cumple | Instalar; P1 de F4-d | Miguel · Jhosep | H1, H4 |
| F4.2.4 | Proponer y confirmar enlace para registros previos o desde PC; nunca solo por ±10 minutos | Probada | Asociación manual a un resultado ya guardado (vía `manual`); el camino exacto no usa la regla de 10 minutos | Aceptación en C1 | Jhosep | H4 |
| F4.3.1 | Asociar solo a un lead visible; crear por el flujo existente y reintentar tras el alta | Probada (en parte) | Asociar a un lead visible (las ambiguas). Crear y reintentar **no aplica** mientras los números sin lead no se guarden (decisión 3a, #10) | Aceptación en C1 | Jhosep | H4; #10 |
| F4.3.2 | Administrar celulares: alta, baja, rotación, salud y atribución, con la clave visible una vez | Probada (en revisión) | Tarjeta «Celulares» (F4-c, #215): unitarias, MSW y pantalla; E2E Docker 4/4; `npm run check` 6338/6338; corregido el P2 de la revisión (`d7d498d2`) | Validación de cierre de Miguel y fusión; después, paso 2 de `ACTIVAR-C1.md` | Miguel · Jhosep | #215; H1, H3 |
| F4.3.3 | Conservar evidencia y vínculo al deshacer; mostrar efectos anulados sin fabricar otra gestión | Probada | Deshacer mueve el enlace al corregido; `efectos_anulados` en el detalle; «deshecho» en «Qué pasó hoy» | P9 de F4-d | Jhosep | H4 |
| F4.4.1 | Evento antes/después, dos llamadas cercanas, enlace fallido y dos pestañas | Pendiente (preparada) | Casos P1–P8 en `ACTIVAR-C1.md` | Correrlos el día de la activación | Jhosep · Claude | H1–H4 |
| F4.4.2 | Edición mientras llega otra llamada, alta o asociación fallida, deshacer y lead reasignado | Pendiente (preparada) | Casos P5, P9 y P10 en `ACTIVAR-C1.md` | Ídem | Jhosep · Claude | H1–H4 |
| F4.4.3 | Checks, E2E local y prueba física; sello v4 y sin actividades duplicadas | En curso | Checks y E2E locales en verde (app 6338; E2E 17/17 y 4/4) | Prueba física (F4-d) y consulta de Miguel sin números: recibidas, guardadas, sin duplicados, sello v4 intacto | Jhosep · Miguel | H4 |

## F5 · Jev para identificación asistida

Sin empezar. No es requisito para terminar: si no aporta, se registra «OFF / no aplica» con motivo y se sigue con F6–F7.
Análisis adelantado en `F5-F7-ANALISIS.md` (03/10).

| ID | Tarea | Estado | Siguiente paso | Responsable | Depende de |
| --- | --- | --- | --- | --- | --- |
| F5.1.1 | Casos sintéticos y luego autorizados/etiquetados | Pendiente (base lista) | Ampliar los 23 casos de F0.4.2; preparar el conteo de ambigüedades reales para que Miguel lo autorice | Claude · Miguel autoriza | La política vigente **no guarda números sin lead** y no se cambia para alimentar a Jev (Miguel, 07/10) |
| F5.1.2 | Separar familias entre ajuste y evaluación reservada | Pendiente | Diseñar la partición | Claude | F5.1.1 |
| F5.1.3 | Medir reglas exactas frente a reglas + historial | Pendiente | Medir; no reutilizar el 19/20 del juicio nota/resultado | Claude | F5.1.2 |
| F5.2.1 | Candidatos autorizados antes de Jev; contexto mínimo con ids opacos | Pendiente | Solo si F5.1 lo justifica | Claude | F5.1.3 |
| F5.2.2 | Salida tipificada, pertenencia a candidatos, abstención y vigencia | Pendiente | — | Claude | F5.2.1 |
| F5.2.3 | Reglas + Jev; abstención fijada antes; límites de riesgo, coste y latencia | Pendiente | Acordar los límites con Miguel antes de evaluar | Miguel · Claude | F5.2.2 |
| F5.3.1 | Credenciales, tratamiento y retención antes de usar datos reales | **Bloqueada** | Rotar la clave de TypeSafe (Jev) pegada en un chat el 20/09 (`scripts/jev/README.md:45`) y fijar tratamiento y retención | Miguel | Rotación pendiente |
| F5.3.2 | Propuestas en sombra, sin tocar asociaciones, tareas ni resultados | Pendiente | — | Claude | F5.3.1 |
| F5.3.3 | Discrepancias, errores, cobertura, coste y latencia con datos mínimos | Pendiente | — | Claude | F5.3.2 |
| F5.4.1 | Hechos verificables y sugerencias con confirmación humana | Pendiente | — | Claude | F5.3 |
| F5.4.2 | Auditar propuesta y decisión; historial acotado y revocable | Pendiente | — | Claude | F5.4.1 |
| F5.4.3 | Proveedor caído, candidato inválido y permisos cambiados; vía manual | Pendiente | — | Claude | F5.4.1 |
| F5.5.1 | Revisar contra el banco reservado | Pendiente | — | Claude · Miguel | F5.4 |
| F5.5.2 | Decidir activar una cohorte, ajustar o dejar OFF | Pendiente | — | Miguel | F5.5.1 |
| F5.5.3 | Confirmar que F6–F7 funcionan con Jev OFF; nada de asociación automática | Pendiente | — | Claude | — |

## F6 · Gerencia y calidad de evidencia (incluye F4-e)

F4-e (la vista del día para supervisor y gerencia) adelanta parte de F6.3. **Dónde va (F4 o F6) y su diccionario
(A1–A7) los decide Miguel** (propuesta #17, `F4E-PLAN-CORTO.md`). Hay prototipo aprobado por Jhosep (06/10); el
prototipo **no sustituye** el contrato aprobado. Si F4-e se adelanta, F6 amplía su puerta, no crea otra.

| ID | Tarea | Estado | Evidencia | Siguiente paso | Responsable | Depende de |
| --- | --- | --- | --- | --- | --- | --- |
| F6.1.1 | Separar detectadas, elegibles, enlazadas y pendientes | Bloqueada (propuesta escrita) | Diccionario en `F4E-PLAN-CORTO.md` | Decisión de Miguel | Miguel | #17 |
| F6.1.2 | Denominadores y exclusiones | Bloqueada (propuesta escrita) | Ídem (A2–A5) | Ídem | Miguel | #17 |
| F6.1.3 | Conservar métricas vigentes; no sumar eventos y gestiones | Bloqueada (propuesta escrita) | Regla escrita en el diccionario | Ídem | Miguel | #17 |
| F6.2.1 | Día de Lima `[inicio, fin)` y actor/asignación históricos | Bloqueada (propuesta escrita) | A1 y A3 | Ídem | Miguel | #17 |
| F6.2.2 | Retraso de entrega/registro, sincronización, cola y antigüedad de la señal | En curso | La tarjeta de F4-c ya muestra la cola y las horas sin latido (sin hora exacta) | Retraso de entrega y de registro | Claude | #17 |
| F6.2.3 | Cobertura insuficiente ≠ cero llamadas; el latido solo no acredita captura | Bloqueada (propuesta escrita) | «—» frente a 0 en el prototipo; «La salud es lo que declara el celular» en la tarjeta | Ídem | Miguel | #17 |
| F6.3.1 | Lecturas y pantalla de gerencia con ámbito y diccionario visible | Bloqueada (propuesta escrita) | Prototipo F4-e aprobado por Jhosep; plan corto con la puerta propuesta | Decisión 4 y A1–A7; después plan corto, migración y pantalla | Miguel decide · Claude | #17, decisión 4 |
| F6.3.2 | Ventana histórica limitada o agregados con retención propia | Pendiente | — | Decidir antes de mostrar históricos (sesgo por la purga de 30 días) | Miguel | F6.3.1 |
| F6.3.3 | Eventos tardíos sin duplicar; límites de cobertura y retención visibles | Pendiente | — | — | Claude | F6.3.1 |
| F6.4.1 | Contrastar la muestra con teléfono, eventos, enlaces y actividades | Pendiente | — | — | Jhosep · Claude | H4 |
| F6.4.2 | Ayer recibido hoy, medianoche de Lima, reasignación, deshacer, sin señal y purga | Pendiente | — | Oráculo con mutantes y EXPLAIN | Claude | F6.3.1 |
| F6.4.3 | Validación de negocio y checks de las capas tocadas | Pendiente | — | — | Miguel · Claude | F6.4.1 |

## F7 · Despliegue gradual y operación

| ID | Tarea | Estado | Evidencia | Siguiente paso | Responsable | Depende de |
| --- | --- | --- | --- | --- | --- | --- |
| F7.1.1 | Validación integral en los equipos admitidos; límites por marca y Android | Pendiente | — | — | Jhosep | H4, H5 |
| F7.1.2 | Revisar la evidencia de F0–F6 y la decisión de Jev | Pendiente | — | — | Miguel · Claude | F0–F6 |
| F7.1.3 | Responsables operativos y criterios para parar o ampliar | Pendiente | — | — | Miguel | F7.1.1 |
| F7.2.1 | Guía de permisos, cola, clave perdida, cambio de equipo y baja de analista | En curso | Borradores: flujos de celular nuevo, pérdida y baja (`F4C-F4D-PLAN-CORTO.md`), `ACTIVAR-C1.md`, `macrodroid.md` §3c | Una sola guía de soporte | Claude | — |
| F7.2.2 | Reasignación, números compartidos y corrección/revocación de asociaciones | Pendiente | — | — | Claude | F7.2.1 |
| F7.2.3 | Apagados independientes de captura, apertura y Jev; conservar el registro manual | Pendiente | Tres niveles de vuelta atrás escritos en `ACTIVAR-C1.md` §6 | Probarlos | Jhosep · Miguel | H4 |
| F7.3.1 | Gates y release humano; commit verificado en `avancecorp/main` | Pendiente | — | — | Miguel | H3 |
| F7.3.2 | Publicar solo el artefacto del commit verificado | Pendiente | — | — | Miguel | F7.3.1 |
| F7.3.3 | Cohortes pequeñas: primero C1, luego los demás; parar o ampliar | Pendiente | — | — | Miguel · Jhosep | H4, H5 |
| F7.4.1 | Fechas reales, aceptación, pendientes con dueño | Pendiente | — | — | Claude | F7.3 |
| F7.4.2 | Diccionario entregado; retención (cron) y salud funcionando | Pendiente | — | — | Claude · Miguel | F6 |
| F7.4.3 | Plan, tablero y vault al día; ninguna reversa operativa borra datos | Pendiente | — | — | Claude | F7.4.1 |

## Ampliaciones aprobadas (pasos propios, fuera de las 102)

| # | Qué | Estado | Depende de |
| --- | --- | --- | --- |
| #13 | Clientes: identificar al cliente, abrir postventa y enlazar la llamada con su gestión | Aprobada (02/10); sin empezar | Primero, la gestión de clientes en Gestión Diaria (Miguel). Nunca registrar sobre un lead convertido con la encuesta de leads |
| #14 | Entrantes: atendida → encuesta; perdida → tarea «devolver la llamada»; número ajeno → silencio | Aprobada (02/10); diseño de la macro en `macrodroid.md` §3d, sin armar ni probar | Después de salientes; #18 (MacroDroid Pro); para clientes, #13. No se enciende por estar aprobada: se prueba entera antes |
| #15 | Métricas de entrantes, separadas de las salientes | Aprobada como objetivo; sin diseño | #14, #17. Nunca inflar «llamadas hechas» |

## Decisiones pendientes

| # | Decisión | Quién | Qué cambia según la respuesta |
| --- | --- | --- | --- |
| #16 | F0 solo con salientes (quitar las diez entrantes de F0.3.1) | Miguel | F0.3.1 se puede cerrar sin entrantes o espera a la #14 |
| #17 | Diccionario de métricas A1–A7 y dónde va F4-e (F4 o F6) | Miguel | Desbloquea F6.1–F6.3 (y F4-e) |
| #18 | MacroDroid Pro en producción | Miguel | La versión gratuita se apaga sola al vencer sus días (C1 vence ~**09/10 15:50 Lima**); también la necesita la #14. Claude prepara precio, licencia y cuenta por equipo |
| — | Rotación de la clave de TypeSafe (Jev) | Miguel | Desbloquea F5.3.1 |
| — | Los 8 fallos de fondo del gate global | Miguel | Trabajo aparte; no bloquean llamadas |

## Lo que se corrigió en los documentos con este repaso

- `README.md`: «Estado hoy» al 07/10 y este archivo en la tabla.
- `COORDINACION.md`: regla 1 (ya no hay un solo PR abierto: el #190 está fusionado y el abierto es el #215).
- `F4C-F4D-PLAN-CORTO.md`: el runbook ya no habla de aplicar «el #198» aparte; los tipos ya existen.
- `F4E-PLAN-CORTO.md`: su migración ya no puede ser «la duodécima» (esa posición es la corrección del #190).
- `PUBLICAR-F2-F3.md`: aviso de que la guía es de cuando eran siete; el orden vigente de las doce está en el #215.
- `macrodroid.md`: F4-b ya está en `main`, detrás del interruptor.
- Tablero y `estado.json`: las notas de F2.2.3 (sin `P0409`), F3.1.3 (tipos generados) y F3.3.3 (sin UUID) al día;
  F4 con su evidencia; las cinco casillas nuevas.

## En llano

De las 102 tareas, 30 están cerradas con evidencia; casi todo F1 y F2. Lo construido de F3 y F4 está probado pero no
instalado: el siguiente gran paso es de Miguel —aplicar la base, desplegar la Edge y abrir el interruptor— y después
activamos C1 con la guía ya escrita. F5, F6 y F7 siguen pendientes; F6 espera que Miguel decida el diccionario de
métricas. Nada de esto se marca como hecho por estar fusionado: se marca cuando funciona en el teléfono.
