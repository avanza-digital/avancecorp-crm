---
tags: [crm, cartera, multiempresa, plan, gestion, retoma]
fecha: 2026-09-16
actualizado: 2026-09-16
estado: plan-guardado-trabajo-pausado-sin-implementar
decision_origen: Miguel-pide-concentrar-la-gestion-del-cliente-en-la-ficha-multiempresa
---

# Cartera multiempresa — plan de gestión integral

## Objetivo y decisión de Miguel

La **ficha multiempresa será el lugar desde el que el analista gestione a sus clientes**, con sus inversiones Avance, Qorilazo y Prodelco. Debe reunir las funciones de Gestión Avance que todavía faltan, conservando las reglas comerciales, los núcleos y los permisos de cada rol.

Miguel pidió primero el inventario y después indicó: «ok guarda todo y seguimos mañana, guárdame esto como un plan de implementación». **Se guarda el plan y se pausa la ejecución. No se ha implementado ni publicado esta ampliación.** Al reanudar, comenzar por la etapa 1 y las correcciones de cliente/contrato; el encargo de hoy es guardar el avance.

Este es un plan complementario de F5/F6. La apertura general F9 y las conformidades pendientes G7/G8 conservan su estado y evidencia; este trabajo no las sustituye.

## Estado de partida al pausar

- Multiempresa ya está habilitada para el equipo. Los filtros comerciales y la distribución compacta están publicados: [[Cartera inversionistas - implementacion de filtros comerciales (2026-09-15)]].
- Producto publicado: commit `a09ecad9aaedc99560f46d6bf42a96dc3b90b6ea`, build `build-20260916T035613621Z`. Acta: `CRM-Avance-Corp/supabase/scripts/cartera-filtros/PUBLICACION.md`.
- Antes de guardar este plan, Main local y su referencia `avancecorp/main` estaban en `862aa82448d8ca65eb2dbc043c701eafc6d450aa`. El commit de este plan será posterior y documental.
- El banco temporal de filtros ya fue eliminado; coste estimado US$0,01496. Este diagnóstico no creó bancos ni modificó producción.
- La comparación se hizo leyendo el código vigente, con CodeGraph como primera navegación y lecturas focales cuando el grafo no devolvió los componentes. **No hubo recorrido manual ni pruebas nuevas de ejecución.**
- Se conserva la apariencia de [[F8 - ficha anterior recuperada para multiempresa (2026-09-15)]]. Recuperar esa apariencia no trasladó todas las operaciones de la gestión anterior.

### Precisión corregida durante la conversación

Codex respondió inicialmente que las correcciones de cliente y contrato seguían disponibles en Gestión Avance. La inspección completa corrigió esa afirmación: **los formularios existen, pero el acceso actual desde multiempresa también oculta ambas acciones**.

La cadena está en `CRM-Avance-Corp/app/src/screens/mi-cartera.tsx`: `CarteraSegunBandera` monta `MiCarteraAvance gestionarSolo`; este modo pasa `puedeContratar=false`; `VistaMiCartera` calcula `accionesContractualesHabilitadas = puedeContratar && escrituraHabilitada`, y las correcciones dependen de esa capacidad. Por tanto, hay que recuperar el acceso desde la ficha y comprobar el flujo completo.

## Inventario que debe implementarse

| Pendiente | Resultado esperado | Alcance y reglas |
| --- | --- | --- |
| 1. Corregir cliente | Editar nombres, apellidos, teléfono y domicilio desde Información del cliente. | Analista dentro de las 5 horas del registro que corresponda. Documento y correo conservan su autorización administrativa específica. |
| 2. Corregir datos bancarios | Recuperar la edición bancaria del perfil dentro del flujo del cliente. | Separar PEN/USD y conservar las cuentas ya vinculadas a contratos. La consulta de cuentas ya existe. |
| 3. Corregir contrato | Abrir la corrección de capital, producto, tasa autorizada, plazo, fechas, modalidad, notas y cotitulares. | Ventana de 5 horas y restricciones del servidor. La moneda del contrato está bloqueada en el formulario actual; no ofrecer su cambio por este traslado. Conservar pagos y revisiones documentales. |
| 4. Cronograma completo | Ver todas las cuotas, pendientes, vencidas, pagadas, pagos reales y saldo por pagar. | Consulta Avance desde el detalle de cada contrato, con datos del núcleo. La próxima cuota aislada no sustituye este detalle. |
| 5. Detalle contractual completo | Mostrar producto y versión, fecha de inicio, tipo de interés y notas internas. | Inicio y tipo de interés ya viajan en la ficha, pero falta mostrarlos. Producto/versiones/notas requieren revisar el lector. En interés compuesto, representar correctamente la modalidad aplicable. |
| 6. Ver contrato PDF | Abrir el documento para visualizarlo desde la ficha y conservar sus controles documentales. | Descarga y recuperación ya existen. Mantener revisiones, reglas del formato histórico y bloqueo por integridad cuando corresponda. |
| 7. Tasas y autorizaciones | Mostrar tasa pactada frente a la política y solicitudes vigentes, pendientes o autorizadas. | Reusar el historial de tasas. El formulario de nueva inversión ya usa `ContratoNuevo` y su política; no duplicar esa gestión. |
| 8. Desglose de renovaciones y aumentos | Mostrar capital anterior, renovado, adicional y relación entre contratos. | Mostrar también el efecto comercial confirmado por el núcleo cuando el rol pueda consultarlo. Los históricos sin desglose permanecen identificados como pendientes. |
| 9. De quién es la venta | Consultar quién registró, a quién cuenta efectivamente y su historial de reasignaciones; reasignar con motivo cuando esté autorizado. | Gerencia/Admin según capacidades vigentes. Es distinto del responsable que atiende al cliente, cuyo cambio ya está integrado. Incluir atribución efectiva de la cadena de aumentos. |
| 10. Detalle adicional COOPAC | Mostrar notas de la operación y fecha/motivo de anulación existentes. | Consulta desde sus fuentes propias. El estado anulado ya se muestra; falta completar su contexto. |

**Acción del módulo, fuera de una ficha existente:** recuperar «Nuevo cliente» para Supervisión/Gerencia según sus permisos vigentes. El analista sigue creando clientes al convertir un lead. El modo `gestionarSolo` también oculta actualmente esa puerta.

**Adaptación COOPAC:** las correcciones anteriores están implementadas para perfiles/contratos Avance. Su equivalente sobre una persona o inversión COOPAC requiere adaptar el escritor y su autorización a la identidad y fuente reales. La etapa 1 debe precisar campos corregibles, origen de las 5 horas, autor/responsable habilitado y auditoría. No declarar esta equivalencia resuelta por conectar un botón Avance.

### Funciones existentes que se conservarán

Nuevas inversiones Avance/COOPAC, aumentos, renovaciones y reinversiones; plazo y rentabilidad anual manual COOPAC; contacto y agenda; historial; consulta bancaria; documentos y recuperación de PDF; solicitudes de retiro; No contactar; cambio de responsable de relación; eliminación administrativa de contratos con sus restricciones actuales. También se conservan filtros mensuales/comerciales y separación por empresa/moneda.

## Etapas de implementación

### 1. Cerrar la matriz de funciones, fuentes y permisos

- Mapear cada acción a su componente, lector/escritor del núcleo, identidad y fuente económica. Confirmar la correspondencia `fuente_id`/contrato para Avance y los perfiles vinculados; usar la identidad neutral para la persona.
- Precisar la autoridad para cada campo y rol: analista propio, supervisor, Gerencia, Admin/Superadmin del portal y Directorio. Gerencia y administrador no son sinónimos.
- Confirmar la fecha original que gobierna las 5 horas. La vinculación o fusión de identidades no debe reiniciar la ventana.
- Diseñar las capacidades que devuelve el servidor y los motivos de bloqueo visibles. Reutilizar formularios existentes y mantener la validación del servidor en cada escritura.
- Definir la adaptación COOPAC y la puerta de alta directa de roles autorizados. Preparar SQL exacto y reversa si hacen falta cambios de datos o funciones; su publicación conserva la revisión/autorización que corresponda a ese cambio concreto.

**Salida:** matriz completa por acción/empresa/rol, contrato de datos y lista exacta de cambios. No ampliar permisos por ocultar Gestión Avance.

### 2. Integrar las correcciones de cliente y contrato

- Conectar `ClienteForm` y `ContratoCorregir` desde la ficha multiempresa, con datos precargados y capacidades verificadas.
- Llevar la corrección bancaria y las correcciones administrativas de documento/correo al mismo flujo autorizado.
- Incorporar la operación equivalente COOPAC sobre su núcleo según la matriz de la etapa 1.
- Mostrar tiempo restante/bloqueo, conservar errores y datos escritos, impedir cierres accidentales durante el guardado y volver a la misma ficha tras guardar o cancelar.
- Refrescar ficha, lista, historial, documentos y métricas que cambien mediante sus lectores canónicos. Conservar cuotas pagadas, cuentas vinculadas y revisiones PDF.

**Salida:** un analista puede corregir un registro propio autorizado dentro de su ventana; un intento vencido o ajeno es rechazado también por el servidor. Las excepciones administrativas siguen la regla comprobada.

### 3. Completar detalle financiero y documental

- Integrar cronograma, pagos reales, saldo y términos completos del contrato.
- Completar visualización del PDF junto a las acciones documentales existentes; comprobar formato histórico, revisión vigente, pendiente y bloqueo de integridad.
- Incorporar tasas/autorizaciones, desglose de renovaciones/aumentos y contexto COOPAC.
- Mantener la consulta por persona/contrato: abrir un detalle no debe descargar de nuevo toda la cartera ni perder la mejora de rendimiento publicada.

**Salida:** se consulta el detalle completo desde la ficha, conservando importes, pagos, permisos, formatos y separación por moneda/empresa.

### 4. Completar las acciones por rol y unificar la navegación

- Integrar atribución efectiva y reasignación de la venta con motivo/historial.
- Recuperar el alta directa para los roles autorizados en el módulo; mantener la conversión desde Leads para el analista.
- Verificar que cada recorrido vuelve al cliente y contrato correspondientes, conservando filtros, posición y foco.
- Retirar la necesidad de entrar a Gestión Avance cuando la matriz de equivalencia esté completa y probada. La retirada definitiva de su entrada se hace al final, con reversa preparada.

**Salida:** todas las funciones autorizadas se alcanzan desde Cartera de inversionistas y su ficha.

### 5. Verificar, revisar y preparar la publicación

- Ejecutar los checks aplicables de `.ai/VERIFICATION.md`: frontend, pruebas de dominio y E2E; cuando haya SQL, preflights y matriz real de permisos/HTTP en entorno aislado.
- Revisar el cambio concreto con Claude por `scripts/claude-review`, como SECONDARY_REVIEWER de solo lectura. Codex evalúa los hallazgos, implementa y ejecuta la verificación final.
- Probar corrección antes, en el límite y después de las 5 horas; revocación/cambio de responsable; cliente histórico o fusionado; cliente COOPAC sin perfil Avance; PEN/USD; permisos administrativos y Directorio.
- Probar errores de red, doble envío y guardado concurrente; preservación de cotitulares, cuotas pagadas, cuentas y revisiones PDF; consistencia de Capital/conversión y otros consumidores del núcleo.
- Probar escritorio/móvil, navegación sin saltos y retorno a la misma ficha. Las pruebas automáticas y la revisión manual deben reportar su estado real.
- Preparar SQL/artefacto/reversa y evidencias antes de cualquier autorización final necesaria. Un nuevo banco de pago requiere su presupuesto correspondiente: el banco y la autorización concreta de filtros ya se ejecutaron y cerraron.
- Hacer commits por bloques. Integrar cambios remotos; publicar únicamente desde Main verificado con `avancecorp/main`, siguiendo el procedimiento vigente. Verificar después y cerrar cualquier banco propio.

**Salida:** cambio probado, revisado y publicable con evidencia; después, publicación y comprobación efectivas. Escribir código o recibir un dictamen no equivale a publicar.

## Reglas que debe preservar la implementación

- Una identidad por persona, inversiones separadas por empresa, monedas separadas y datos leídos/escritos por los núcleos existentes. Las extensiones pertenecen a esos núcleos; no crear cálculos paralelos de capital o conversión en la pantalla.
- La ventana se aplica al registro real y la decide el servidor. Conservar la propiedad del registro y los alcances por rol.
- Actualizar datos del perfil no reescribe los PDFs históricos. Las correcciones contractuales conservan la cadena documental y la auditoría.
- Reusar componentes y diseño del CRM: distribución compacta, escritorio horizontal donde ayude y adaptación vertical en móvil.
- Las comisiones continúan fuera del sistema, según [[F4 cerrada - comisiones fuera del sistema (2026-09-08)]].

## Evidencia del diagnóstico y revisión independiente

Rutas principales, relativas a `CRM-Avance-Corp/app/src/`:

- `screens/mi-cartera.tsx`: acceso `gestionarSolo`, permisos de corrección, flujos heredados y desglose económico.
- `screens/cartera-inversionistas.tsx`: navegación actual, documentos, eliminación e invalidaciones.
- `components/app/cliente-form.tsx`, `contrato-corregir.tsx`, `contrato-detalle.tsx`, `cliente-ficha.tsx`: operaciones y detalle que deben recuperarse.
- `components/app/inversionista-ficha.tsx`, `inversion-nueva.tsx`, `postventa-persona.tsx`: capacidades y operaciones ya integradas.
- `components/app/cierres-externos-seccion.tsx`: notas y contexto de anulación en la consulta histórica COOPAC. `RevisionDelMes` es otro flujo; anular cierres no se presentó como una acción existente de esa sección de Gestión.
- `lib/inversionistas.ts`, `lib/ventana.ts`, `lib/roles.ts`: contrato de lectura, ventana y permisos administrativos.

Claude revisó una selección de fragmentos mediante el wrapper y emitió **CHANGES_REQUESTED**, con confianza media. No existe un dictamen PASS del inventario o de una implementación futura. El primer intento restringido no se completó; el reintento del wrapper entregó el dictamen.

Evaluación de Codex:

- Se incorporan a las etapas la revisión de capacidades del servidor, el detalle de interés compuesto, la atribución efectiva y el comportamiento de documentos bloqueados. Este último es una comprobación de interfaz/servidor pendiente, no una vulnerabilidad de descarga demostrada.
- Se distingue información que ya viaja pero no se muestra de campos que requieren ampliar el lector.
- La supuesta falta de identificador de contrato no acredita por sí sola un bloqueo: la ficha ya usa `fuente_id` para recuperar/eliminar contratos Avance. Confirmar su contrato en la etapa 1 antes de conectar nuevos lectores; no inventar otra identidad.
- Las dudas por fragmentos no adjuntados al reviewer se contrastaron localmente: `accionesContractualesHabilitadas`, la constante de cinco horas, los permisos de documento/correo, el reuso de `ContratoNuevo`, el desglose y la mini-ficha COOPAC están en el código leído. No se convierten en nuevas preguntas al usuario por falta de contexto del reviewer.
- Para trasladar correcciones a COOPAC sí queda trabajo de diseño y verificación de sus escritores; el inventario de lectura no lo acredita resuelto.

## Punto exacto de retoma

**Trabajo pausado a petición de Miguel.** La implementación de este plan está pendiente; en esta sesión solo se diagnosticó y documentó.

1. Leer esta nota y `Inicio.md`; comprobar Main, cambios remotos y trabajo ajeno antes de editar.
2. Empezar por la **etapa 1**, cerrando fuentes/capacidades y la ventana original. Priorizar luego **Corregir cliente** y **Corregir contrato**, etapa 2.
3. Conservar los filtros y la publicación actuales. No repetir la apertura F9 ni crear otro piloto para iniciar este trabajo.
4. Completar y revisar cada bloque con sus pruebas; guardar commits y actualizar esta nota con evidencia real.

Al pausar no hay despliegue, migración, banco nuevo ni consulta Claude en curso de esta tarea. Quedaron sin tocar tres archivos previamente ajenos al diagnóstico: `Terminales de AVANCECORP - recuperacion y sesiones.md` y las dos evidencias F7 `2026-09-11T20-20-59-444Z.json` / `2026-09-14T22-20-49-263Z.json`.

Relacionadas: [[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]], [[F9 - apertura general autorizada (2026-09-15)]], [[Gestión comercial de clientes - renovaciones y upgrades]], [[Cartera inversionistas - implementacion de filtros comerciales (2026-09-15)]], [[F8 - ficha anterior recuperada para multiempresa (2026-09-15)]].
