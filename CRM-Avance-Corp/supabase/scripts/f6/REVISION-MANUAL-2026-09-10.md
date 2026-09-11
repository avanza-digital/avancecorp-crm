# F6 — avance de revisión manual del 10/09/2026

Estado: **EN CURSO; aceptación completa pendiente**.
Revisor humano: Miguel. Recorrido guiado con roles vendedor/Gerencia y banco local sintético.
Referencia de código F6: `b54fe94219fa516ab3824ec1be9ae756fc3144e1`.

## Confirmaciones recibidas

| Comprobación | Resultado | Evidencia humana |
|---|---|---|
| Crear una llamada y verla en la ficha | PASS | «si aparecio!!» |
| Visualizarla en Hoy | PASS | «OKOK YA REVISE SII SALE EN LA PANTALLA DE HOY» |
| Localizarla en Agenda, una sola vez | PASS | «funciona. aprobado», respondiendo a los tres pasos de Agenda |
| Abrirla desde Agenda y conservar la misma ficha al recargar | PASS | Misma aprobación explícita de los tres pasos |
| Completar la llamada con detalle y conservarla en el historial | PASS | «funciona», tras la instrucción de cerrar la llamada y revisar el historial |
| Programar el siguiente contacto, una sola vez y con la fecha elegida | PASS | Misma confirmación del cierre con siguiente contacto |
| Cambiar la hora de la reunión y verla actualizada en Agenda | PASS | «le puse un nueva hora sii, y ahora me figura en mi agente con ese horario cambiado» |
| Confirmar la cita | PASS | «y confirme la cita», tras preguntar expresamente por la confirmación de asistencia |
| Identificar el selector de archivo como botón del CRM | PASS | «perfecto ahora si», tras el ajuste visual `513effa` |
| Qorilazo: seleccionar comprobante, revisar y confirmar; tres inversiones y S/ 3.250 | PASS | «tal cual todo sale como tu me dices», respondiendo al recorrido completo y su resultado esperado |
| Prodelco: mismo recorrido, tres inversiones y S/ 3.800 | PASS | «perfecto», tras la guía; Codex observó después la inversión nueva y los dos antecedentes en la ficha |

El visto bueno de llamadas y reuniones no se atribuye a una tarea
o identidad concreta: Miguel no confirmó su título ni su identificador. El banco
se preparó con una persona Qorilazo sin perfil Avance; esa condición del caso
exacto utilizado no se da por ratificada solo con la aprobación de navegación.

## Siguiente paso y pendientes

El punto 2 de [la guía](REVISION-MANUAL.md) tiene aceptación humana: cierre con
detalle e historial, siguiente contacto con fecha y sin duplicación, cambio de
hora visible en Agenda y confirmación de la reunión. Miguel confirmó por separado
el cambio guardado y la confirmación; no se dedujo de la mera apertura del formulario.

El 10/09 Miguel delegó expresamente el punto 3: «esta prueba puedes hcaerla tu
por favor». Codex ejecutó la reasignación por UI y verificó el acceso con ambos
asesores. Después, ante «ok sigamos con eso como lo haras?», Codex explicó y
ejecutó la prueba No contactar del punto 4. Ante «ok hazlo», Codex avanzó el punto 5
con confirmaciones de reinversión desde el CRM y verificaciones de integridad.
Miguel completó después la selección, revisión y confirmación visual de ambas
cooperativas. Codex comprobó las fichas y la integridad posterior en el banco.
El punto 5 queda **PASS** dentro del alcance de la guía.
Miguel autorizó después todas las pruebas necesarias y pidió consultar siempre
a Claude. Codex completó los puntos 6 y 8; el punto 7 tiene prueba de móvil,
teclado y estabilidad, pero falta confirmar la lectura con VoiceOver.

## Punto 3 — ejecución delegada a Codex

**PASS funcional**, ejecutado en el banco sintético con sesiones autenticadas.
La demo general sigue habilitada como opción local, pero este caso se realizó
con las cuentas de prueba porque la demo no contiene el recorrido F6.

- Persona usada por Codex: `6e81c382-127d-4594-84ec-f05e3c886991`, Qorilazo.
  Gerencia cambió el responsable de PRUEBA F4 VENDEDOR a PRUEBA F4 AJENO desde
  el formulario visible. La ficha mostró el nuevo responsable.
- El nuevo asesor vio la persona y las dos tareas pendientes. Se conservaron
  los mismos IDs, títulos, tipos, estados y horarios, sin duplicación.
- El asesor anterior perdió ficha y agenda incluso reutilizando el JWT obtenido
  antes de reasignar. F5 devuelve HTTP 200 con `null`; F6 devuelve HTTP 403/42501;
  la lectura directa de tareas bajo RLS devuelve cero filas. Por UI, el enlace
  directo vuelve a Cartera con «El acceso cambió. La cartera se volverá a consultar.»
- La información de inversiones devuelta por la ficha no cambió. El analista
  histórico de la operación sigue siendo PRUEBA F4 VENDEDOR.
- Caso sin responsable: fixture independiente en transacción, con rollback.
  Se bloqueó agendar sin responsable (P0409), Gerencia conservó el pendiente en
  su cola y los vendedores no lo vieron; al asignarlo llegó la misma tarea al
  nuevo asesor. Al terminar se verificaron tareas previas y banderas intactas,
  y ausencia de la persona temporal.

Evidencia: [reasignación](manual-2026-09-10/reasignacion-evidencia.json) y
[cola sin responsable](manual-2026-09-10/cola-evidencia.json).
La reasignación queda aplicada en el banco a PRUEBA F4 AJENO. No hubo cambios de
producto ni de producción. El tramo de cola fue una prueba funcional de servidor,
no un recorrido visual de una cola con datos persistentes ni una aprobación humana.

El arnés inicial esperaba por error HTTP 403 para la ficha F5 oculta y PT409 para
la ausencia de responsable. Se ajustó al contrato comprobado en código/catálogo
(HTTP 200/null y P0409) antes de completar las comprobaciones. No se modificó el
producto para acomodarlo al arnés; las ejecuciones finales pasaron.

## Punto 4 — No contactar, ejecutado por Codex

**PASS funcional** en la misma persona sintética, con PRUEBA F4 AJENO como
responsable. Gerencia marcó y levantó el veto desde el formulario del CRM.

- Al marcarlo con motivo, la ficha mostró No contactar y deshabilitó Agendar
  gestión. Los dos pendientes anteriores quedaron cancelados y la agenda vacía.
- Un intento directo de agendar con el JWT del asesor actual fue rechazado con
  P0429 («Esta persona pidió no ser contactada»; HTTP 500 del contrato vigente).
  No creó tareas. El mismo asesor no pudo levantar el veto: HTTP 403/42501.
- Gerencia levantó el bloqueo con un motivo. Agendar volvió a habilitarse y las
  dos tareas canceladas permanecieron canceladas, sin reaparecer.
- Se programó después una única llamada nueva por la RPC del asesor actual,
  titulada «Seguimiento posterior a No contactar F6». Se verificó que su ID era
  nuevo y que los dos anteriores seguían cancelados. La ficha tras recargar
  conserva este contacto como único pendiente.
- Las inversiones, tareas ya cerradas antes del caso y banderas conservaron sus
  datos. El motivo de prueba y su levantamiento quedan en la historia.

Estado final local: No contactar desactivado, PRUEBA F4 AJENO como responsable,
dos tareas originales canceladas y un contacto nuevo pendiente. No se restauran
las tareas canceladas porque precisamente se verificó que levantar el veto no
las revive. [Evidencia del recorrido](manual-2026-09-10/veto-evidencia.json).

No hubo cambios de código ni de producción. Es una verificación de Codex; no se
atribuye a Miguel una aprobación visual de los casos que no ejecutó.

## Punto 5 — vencimientos y reinversión, ejecución parcial de Codex

**PASS funcional con recorrido UI parcial**. La falta del permiso de archivo
en la extensión de Chrome impidió completar el envío inicial desde el formulario.
No se presenta este tramo como aceptación visual completa ni aprobación humana.

- Se crearon dos antecedentes cooperativos nuevos mediante la conversión canónica,
  con persona, documento, lead y depósito sintéticos únicos. Ambos son de S/ 1.000
  y vencen el 17/09/2026. Aparecieron en Vencimientos y abrieron la persona,
  empresa y referencia de origen correctas en Reinvertir desde esta inversión.
- El selector de comprobante fue bloqueado por Chrome: `fileChooser.setFiles`
  devolvió `Not allowed`. Se indicó cómo habilitar el acceso a URLs de archivo;
  no se cambió ese permiso automáticamente. Para continuar se prepararon las dos
  solicitudes con `preparar_reinversion_fn` y se cargaron los PNG ficticios por
  la API local de Storage. La descarga autenticada devolvió exactamente esos bytes.
- Se retomó cada solicitud por su referencia desde el CRM. Se revisaron persona,
  empresa, capital, fechas y depósito, y se pulsó Confirmar inversión por UI.
  Qorilazo añadió S/ 1.500 y Prodelco S/ 2.000. Ambas fichas mostraron dos
  inversiones: original de S/ 1.000 y nueva inversión, con comprobante disponible.
- Repetir la confirmación mediante la RPC devolvió el mismo ID. Cada solicitud
  tiene una inversión nueva, un vínculo de origen y una gestión de reinversión.
  Los registros completos de los dos orígenes y las 87 inversiones del snapshot
  anterior se conservaron. La reinversión no creó otra persona, lead ni Auth;
  se compararon los IDs de personas/leads y los IDs/correos de Auth, no todos
  los campos de sesión. Las banderas tampoco cambiaron.
- Avance: Aumentar inversión abrió con F4-BASE-UPGRADE-ELEGIBLE. Como no había
  contratos vencidos en el banco, se añadió un antecedente nuevo de S/ 1.000 al
  cliente ficticio existente, mediante la RPC contractual canónica y cuenta
  existente. Se ensayó primero con rollback y restricciones diferidas forzadas.
  Su vencimiento 01/09/2026 habilitó Renovar contrato, mostrando origen, PEN y
  capital anterior correctos. Ambos diálogos se cancelaron sin revisar ni crear
  solicitudes. Los 48 contratos anteriores permanecieron idénticos; el nuevo
  antecedente también se conservó tras abrir y cerrar el formulario.

[Evidencia de reinversión y acciones Avance](manual-2026-09-10/reinversion-evidencia.json).
En ese primer ensayo quedó **NOT RUN** el recorrido completo de carga de archivo
y envío inicial de Revisar inversión por UI. No hubo cambio de producto ni de
producción. Los casos ficticios quedaron disponibles para retomar la prueba.

En el reintento del 10/09, Miguel indicó que ya había habilitado el permiso.
La carga automática volvió a responder `Not allowed`; no se pudo completar
por el selector nativo y la política del navegador rechazó abrir la configuración
de extensiones. Por tanto, el permiso efectivo no quedó verificado. Se dejó
un formulario Qorilazo completo, con capital ficticio nuevo de S/ 750 y depósito
único, pendiente de que Miguel seleccione el PNG preparado. No se pulsó Revisar
inversión ni Confirmar en este intento. Un snapshot nuevo confirmó inversiones,
cierres, solicitudes y banderas sin cambios. El punto 5 continúa pendiente de
este tramo; no se sustituye la evidencia parcial anterior por un PASS visual.

Después, Miguel confirmó que seleccionar el archivo sí funciona en la pestaña
del Chrome habitual. Señaló que el control no parecía un botón. Se ajustó el
`Input` de tipo archivo para mostrar el botón nativo con fondo navy, texto blanco,
bordes redondeados y estados de hover, foco y deshabilitado del CRM. El cambio
alcanza la selección inicial y la recuperación del comprobante en revisión.
Codex verificó el aspecto en Chrome, el nombre `COMPROBANTE F6.png` junto al botón
y el foco visible al llegar con Tab. Miguel aprobó después el aspecto corregido.

**Qorilazo: PASS con aceptación humana del recorrido visual completo.** Miguel
confirmó seleccionar el comprobante, pulsar Revisar inversión y Confirmar
inversión. Codex observó después la misma ficha (`b2aa2e53-227c-41de-96a6-fee6d4cf130f`)
con tres inversiones y S/ 3.250: nueva inversión COMPROBANTE VISUAL F6 QORILAZO de
S/ 750, reinversión anterior de S/ 1.500 y origen de S/ 1.000. La nueva inversión
muestra el depósito `F6-UI-785E5D3B-0014-4A6A-8221-91E38235B936`, vencimiento
10/09/2027 y botón de comprobante. Esta aceptación acredita el recorrido y el
resultado visible; no constituye una nueva comparación de filas o hashes en DB.

Prodelco se preparó en el banco para el mismo recorrido: capital S/ 800,
depósito `F6-UI-433D3487-B7E4-4884-B16C-4BD73AA892CD`, vencimiento 10/09/2027 y
referencia COMPROBANTE VISUAL F6 PRODELCO. El comprobante ficticio correspondiente
se copió al Escritorio como `COMPROBANTE F6 PRODELCO.png`. Miguel respondió
«perfecto» tras las instrucciones. Codex observó después la ficha con tres
inversiones y S/ 3.800: nueva de S/ 800 y antecedentes de S/ 2.000 y S/ 1.000,
con el depósito previsto y botón de comprobante. **PASS del recorrido visual.**

La comprobación funcional posterior de ambos casos encontró una solicitud
confirmada, una inversión, un vínculo al origen y una gestión por cada operación.
Los dos archivos almacenados coinciden byte a byte con los PNG ficticios
preparados. Se conservaron las 90 inversiones y los 47 cierres previos íntegros,
los 49 contratos, las identidades Auth por id/email, los IDs de personas/leads y
las banderas. Solo se añadieron las dos solicitudes/inversiones/cierres esperados.
La comprobación fue de lectura; no se reenviaron confirmaciones de estos dos casos.
La prueba de idempotencia anterior conserva su evidencia independiente.

[Evidencia del recorrido visual completo](manual-2026-09-10/reinversion-ui-completa-evidencia.json).

El primer snapshot del arnés de reinversión usó por error `crm.contratos`; la tabla
correcta es `public.contratos`. Se corrigió antes de operar las reinversiones.
No fue un fallo del CRM.

## Punto 6 — retiro administrativo y permisos

**PASS delegado a Codex, banco sintético.** Desde la ficha Prodelco se registró
la solicitud `2c2ba07a-da70-4cc4-acb6-9c0022e1733d` sobre el origen de S/ 1.000.
Gerencia la llevó por UI de solicitada/1 a en_revision/2 y revisada/3, con detalle
y resolución visibles. Los 49 contratos, 637 cuotas, 92 inversiones, 49 cierres,
49 depósitos reclamados y ocho retiros anteriores conservaron sus filas completas
tras cada etapa. Las banderas se conservaron; la ficha siguió con tres inversiones
y S/ 3.800. Hubo exactamente tres gestiones para este nuevo retiro.

Directorio abrió una ficha Avance autorizada sin botones de agendar, solicitar
ni revisar retiro; la persona Prodelco del ensayo no estaba en su cartera. Su
agenda neutral fue vacía. Tres escrituras RPC como Directorio y una revisión
como vendedor devolvieron 42501. Gerencia tampoco pudo reabrir el retiro terminal.
Las sondas rechazadas conservaron todas las tablas comparadas sin cambios.

Se añadió un segundo retiro sintético para aislar la concurrencia: estando en
revisión/2, una petición con revisión/1 recibió P0409 sin modificar tablas.
Después se canceló correctamente con revisión/2. Esta sonda fue por RPC real;
no se presenta como un recorrido visual de dos ventanas simultáneas.

Evidencia: [retiro por UI](manual-2026-09-10/retiro-ui-evidencia.json),
[permisos y terminal](manual-2026-09-10/retiro-permisos-evidencia.json),
[revisión obsoleta en trámite abierto](manual-2026-09-10/retiro-concurrencia-evidencia.json).
El JSON de permisos conserva su límite temporal original de UI pendiente;
la observación visual posterior está en el JSON de retiro por UI.

## Punto 7 — móvil, teclado y lectura

**PARCIAL: VoiceOver pendiente.** En Chrome a 390 × 844 píxeles CSS, la ficha y
su diálogo no desbordan horizontalmente. Tab/Shift+Tab recorren los controles;
Tab desde Agendar vuelve al primer control del diálogo. Escape vuelve al botón
Agendar gestión de la ficha. Se observó el historial desplegado y el mismo scroll
durante más de 75 segundos, cubriendo los refrescos periódicos.

Se reprodujo un defecto real: cerrar el diálogo controlado dejaba el foco en
BODY, también al terminar un retiro cuyo botón desaparece. Se corrigió en el
componente común: recuerda el origen, vuelve a él si sigue disponible y usa la
ficha como destino cuando la acción desaparece o no admite foco. Los dos tests
iniciales fallaron antes del arreglo y pasaron después; se añadió el caso del
botón deshabilitado y el E2E de retiro terminal, con apertura por ratón y teclado.

VoiceOver no queda aprobado: su control nativo no permitió verificar la salida
del lector. Se intentó desde Accesibilidad; el estado final observado quedó
apagado, igual que al inicio. Se recuperó Chrome en una pestaña nueva tras perder
el enlace de depuración de las pestañas anteriores. No se sustituyó la prueba del
lector por una captura ni por el árbol de accesibilidad. Safari tampoco fue probado.

## Punto 8 — recuperación con interrupción controlada

**PASS delegado a Codex.** Proxy exclusivamente local entre la app y el banco,
sin cortar el servicio productivo. Se comprobó la recarga y la recuperación en
el mismo origen de navegador, con el título guardado y sin formulario editable.

- Respuesta perdida después del commit: una tarea creada; Verificar envío guardado
  consultó `registrada:true` y no volvió a ejecutar la escritura.
- Petición interrumpida antes de llegar a la RPC: `registrada:false`; se reenvió
  exactamente el mismo UUID, título, nota y horario y quedó una sola tarea.
- La primera calibración cortó TCP demasiado pronto y Chrome reintentó por su
  cuenta con el mismo UUID/contenido. Quedó una tarea; se conserva como caso separado.

El snapshot conserva todas las filas anteriores: 49 contratos, 637 cuotas,
92 inversiones, 49 cierres, 49 depósitos, nueve retiros, 60 tareas, 125 operaciones,
176 gestiones y cuatro banderas. Solo añadió tres tareas/operaciones/gestiones,
incluida la calibración. El segundo retiro de concurrencia se ejecutó después
de esta comparación y tiene su propia evidencia.
[Evidencia de recuperación](manual-2026-09-10/perdida-evidencia.json).

El corte reveló un mensaje crudo en inglés. Los errores de transporte sin código
se muestran ahora en español, sin convertirlos en rechazo SQL ni borrar el envío
pendiente. Los once tests existentes de recuperación cubren además doble envío,
cambio de contenido/actor, fallos de almacenamiento y rechazos SQL explícitos.

## Preparación del banco y alcance

Durante la revisión se detectó que faltaba la fila de configuración de
`crm.sla_operacion_control` en el banco local. Se restituyó su semilla en modo
`legado`, con la guarda restaurada en la misma transacción. El RPC de seguimiento
respondió HTTP 200 después del ajuste; la huella de tareas permaneció idéntica y
los tres triggers de esa tabla quedaron habilitados. Fue una corrección de la
preparación local; no hubo cambios de código de producto ni de producción.

Las comprobaciones de este registro no cierran F6 ni firman G6/G7/G8. Se conserva
el estado publicado F4/F5/F6 apagadas en producción. Las comisiones son externas.

Validación del ajuste visual: `npm run check` **PASS** (lint, typecheck, 3.182 tests
con cobertura, cuatro pruebas de configuración de release, build, bundle y
duplicación), `git diff --check` y enlaces locales. No se añadieron tests de clases
CSS. E2E y `gate:realidad`: **NOT RUN** en este ajuste de apariencia, que conserva
el control nativo y no depende de datos productivos. El cambio está en el banco
local de revisión; no se publicó un nuevo artefacto.

## Cierre de verificaciones de esta sesión

`npm run check:all`: **PASS** después del último ajuste: lint, typecheck,
3.188 tests en 227 archivos, cobertura, cuatro tests de configuración de release,
build, bundle, duplicación y 159 E2E PASS; 26 E2E omitidas por su configuración
existente. El primer intento del E2E ampliado usó una etiqueta incorrecta
(`Estado`); se corrigió a `Estado de la revisión` y el gate completo pasó.
Los tests E2E usan su servidor/fixtures propios; no sustituyen la evidencia del
banco real local. La matriz remota general y `gate:realidad`: **NOT RUN** en estos
ajustes de UI, sin cambios de esquema, roles ni publicación; sus observaciones
previas siguen vigentes.

La observación móvil de Agenda se repitió después de una recarga de Vite causada
por editar Dialog. Con el código estable, las siete filas conservaron posiciones
y scroll durante 132 segundos; la ficha conservó el historial y su scroll durante
87 segundos. [Móvil y teclado](manual-2026-09-10/movil-teclado-evidencia.json).
Viewport temporal retirado; VoiceOver observado apagado al terminar. El arnés de
cortes quedó desactivado. La ficha del banco habitual sigue disponible en el
puerto 5216. Los tres casos de recuperación y el retiro concurrente cancelado
se conservan como evidencia sintética; no se borraron para ocultar calibraciones.

Se consultó Claude dos veces mediante el wrapper del repositorio. Sus dictámenes
fueron CHANGES_REQUESTED y se evaluaron con evidencia; no se atribuye un PASS a
Claude. [Evaluación del PRIMARY](manual-2026-09-10/revision-claude-evaluada.json).
Los ajustes de producto están en el commit local `d586b66`; esta documentación
se guarda por separado. El selector de archivos está en `513effa`.
F4/F5/F6 siguen apagadas en producción. **Falta la comprobación de VoiceOver
para cerrar la aceptación manual F6.** F7, F8 y F9 no se dan por completadas.
