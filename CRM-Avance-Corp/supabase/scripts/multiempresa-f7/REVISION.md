# Evaluación del PRIMARY — F7 multiempresa

Codex implementa y verifica. Claude Code actúa exclusivamente como
SECONDARY_REVIEWER mediante `scripts/claude-review`, sin herramientas,
escrituras ni delegación. Tarea de nivel 3 por métricas financieras, acceso
global de Gerencia y nuevas funciones SQL. Máximo dos consultas.

## Revisión de arquitectura

[Dictamen original](evidencias/claude-arquitectura.md): CHANGES_REQUESTED.
Evaluación contra esquema real y pruebas, antes de cerrar la candidata:

| Observación | Decisión del PRIMARY y evidencia |
|---|---|
| Cotitulares imposibles con el lector F5 | Se rechaza esa premisa. Existe `crm.inversion_titulares`; los cotitulares no son perfiles duplicados. F7 usa esta tabla solo para participantes. Prueba SQL: un mismo cotitular en dos inversiones añade una persona sin añadir dinero, operación o contradicción. No se cambió el lector F5. |
| Elección arbitraria de persona contradictoria | Aceptada. `metricas_f7_fuentes` devuelve NULL salvo identidad coherente; la prueba de contradicción conserva capital y no crea una persona. |
| NULL de identidad omitido | Aceptada. Se distinguen coherente, contradictoria y ausente; advertencia de cobertura y pruebas de historia sin enlace. |
| Empresa ausente en el núcleo / posible multiplicación | Empresa por PK de fuente, Avance o `ce.cooperativa`. Se verificaron restricciones únicas de `crm.inversiones` para contrato/cierre. La prueba coteja grupos contra el núcleo, unicidad y atribución. |
| Vencimientos fuera del mes y desgloses duplicados | Aceptada. Historia completa con `medida='stock'`, ventana independiente de hoy a 30 días, estados propios de cada fuente. No sumar `desglose_*`. |
| Factor de conversión y meses sellados | Se mantiene la llamada exacta del informe publicado y el peso mensual versionado actual, devuelto en JSON. Se identifica consulta en sombra actual; no se presenta como foto congelada. El núcleo y las fotos no cambian. Paridad de numerador/divisor probada. |
| RPC de datos necesita bandera y membresía | Aceptada. Verificación dentro de la RPC, sin parámetro de ámbito. Estado retorna OFF por diseño; se rechaza la sugerencia de hacer fallar también la consulta de estado cuando está apagada. |
| Límites UTC/Lima y ajustes | Aceptada. Prueba de 04:59:59/05:00:00 UTC en cambio de mes y fecha comercial anterior con imputación actual; se conservan céntimos. |
| Tres conceptos de primera inversión | Se distingue «Primera registrada» y posterior del titular principal; no se usa `es_inicial` ni se cambia conversión por lead/perfil. |
| Renovaciones con capital completo | Aceptada. Título «Capital de las inversiones del mes», explicación y desglose de contratos nuevos/renovaciones/upgrades. |
| Demos y estados heterogéneos | Se reutilizan los lectores publicados, sin añadir otra lista demo por UUID. Exclusión y paridad probadas; fecha de vencimiento y estado específico por fuente. |
| Actualidad/reproducibilidad | Se devuelve `generado_en`, hoy, bandera y factor. Dos consultas sobre estado invariable coinciden salvo instante de generación; no prometen reconstrucción de una foto histórica. |
| No contactar solo mencionado | Aceptada. SQL excluye veto canónico y legado, mediante `leads_de_persona_veto`, además de exigir persona activa. Ambos casos tienen prueba de comportamiento. |

## Corrección de Escape encontrada por la verificación

La prueba F6 falló 3/8 y luego 2/3 veces. La traza mostró cierre del Sheet
inferior con el foco en `select#pv-retiro-estado` del Dialog superior, ambos
con `data-state=open`. No fue un cambio de datos ni una navegación de F7.

El `DismissableLayer` instalado (1.1.15; Dialog 1.1.19) registra el listener
de Escape en un efecto pasivo. Durante una reapertura rápida podía conservar
brevemente el listener inferior. Se ensayó una solución local `useDialogLayer`
que redirigía ese cierre al panel superior; la propuesta y sus trazas quedan
en el respaldo privado. No forma parte de la entrega final.

La misma prueba E2E sin esperas añadidas pasó 8/8; cuatro pruebas de Dialog
verifican foco, cierre sucesivo de capas y botón desaparecido/deshabilitado.
El gate completo posterior pasó 3.285 pruebas y 164 E2E, con 26 SKIP existentes.
Al integrar `avancecorp/main` hasta `5d49bcf`, se recibió `e01aea1`, que corrige
el mismo problema mediante `escape-dialogo.ts`: protege la capa inferior y
recupera Escape en el diálogo donde nació la tecla. Se conservan esa solución
y sus pruebas modales/no modales sin modificarlas; no se instalan dos sistemas
de cierre. La integración se verifica de nuevo y se registra en la aceptación.

## Revisión final

[Dictamen original](evidencias/claude-final.md): CHANGES_REQUESTED. No se
presenta como PASS de Claude. Se evaluó y corrigió con evidencia, sin una tercera
consulta ni un ciclo de confirmaciones entre agentes.

| Observación | Resolución del PRIMARY |
|---|---|
| P1 hipotético: JWT de Gerencia demo | No confirmado; la premisa no corresponde al sistema. `auth.tsx:252` crea una identidad local mediante `DEMO_YO` y `guardarSesionDemo`, sin Auth/login/JWT. `public.perfiles` no tiene columna demo. `DEMO_HABILITADO` requiere DEV. Una cuenta real de Gerencia conserva su autoridad real; elegir una demostración no fabrica esa autoridad. HTTP anónimo rechaza 42501. No se añadió una columna o permiso ficticio. |
| P1 hipotético: varios stock del mismo contrato | El núcleo publicado emite una fila de stock por contrato/cierre; los desgloses usan otra medida. Renovación/upgrade es categoría de esa fila, no otro stock simultáneo. Se simplificó además la ordenación con una ventana sobre las propias filas, eliminando el segundo join. Un test inyecta deliberadamente una duplicación solo en el auxiliar F7 y prueba que no se amplifica a N×N, queda señalada y no obtiene aceptación. |
| Demos asimétricos | El booleano `true` del núcleo significa ámbito global, no incluir/excluir demos. Los lectores actuales coinciden en clasificación y los tests comprueban exclusión. Se conserva la comparación independiente con el núcleo: aplicar el mismo filtro F5 al comparador ocultaría una divergencia futura. Una pérdida completa de grupo se ensaya y permanece como diferencia visible. |
| FULL JOIN rechazado por el validador | Corregido. Un grupo solo en el núcleo conserva cero explícito en el informe y diferencias verificadas; no se confunde con respuesta incompleta. Pruebas unitaria y de PostgreSQL real pasando por el mismo validador. |
| Contrato real SQL → frontend no probado | Corregido. `contrato-cliente.mjs` importa el esquema TypeScript y Valibot usados por el consumidor. Las pruebas SQL y HTTP reales ejecutan esquema e integridad sobre sus respuestas, incluida zona horaria y microsegundos. |
| Divisor posiblemente fraccionario | No confirmado: `private.conversion_episodios` declara `aporte_divisor integer`; el peso corresponde al numerador. Se conserva `Cantidad`, con paridad de la RPC publicada. No se relajó el contrato ante una hipótesis contraria a la firma. |
| Reversa no observaba objetos F7 | Corregido: se comparan también los cuatro cuerpos F7, sus ACL y propietarios. La reversa apaga; no desinstala. No se vuelve idempotente una migración que debe ejecutarse una sola vez por el ledger. |
| Costo de consulta repetida | Se retiró el polling del informe completo y su refresco al volver a la ventana; el botón Actualizar conserva control explícito. La consulta ligera de estado verifica cada 15 s cuando está activa y cada 5 min cuando no está disponible. Medición de volumen real pendiente del ciclo de instalación/G6. |
| Empresa/moneda cerradas en TypeScript | Se conserva el contrato de las tres empresas y PEN/USD del maestro. Hay CHECK de moneda PEN/USD en contratos y Qorilazo/Prodelco y PEN en cierres externos. Agregar otra empresa/moneda requiere ampliar el producto y sus contratos; no se oculta ni se acepta silenciosamente una clave desconocida. |
| Detalle de discrepancias y duplicados ausente | Corregido: tabla de comparación por empresa/moneda con capital CRM/informe, diferencias de capital, cantidad y atribución; alerta de inversiones repetidas. Prueba de presentación incluida. |
| P0409 se describía como falta de permiso | Corregido. Apagado durante una consulta muestra «Informe en preparación»; 42501 conserva denegación. |
| Mes inválido en controles sin soporte nativo | Corregido: regex con meses 01–12 y límites de 2000 al mes corriente, además de la validación del servidor. |
| Orden DOM de capas | No hubo defecto demostrado en la propuesta revisada. Esa propuesta local se retiró al recibir la corrección equivalente `e01aea1` desde Main. Se preservan los componentes y pruebas de Main, con verificación conjunta posterior. |
| Tipos integrados parcialmente | Documentado. Son exactamente las dos firmas introspectadas; se conserva el resto de los contratos de Main ausentes en el banco. `Args: never` viene del generador actual y typecheck valida ambas llamadas. |

El límite superior de mes también se comprueba: la sonda de septiembre a las
05:00 UTC debe quedar fuera de agosto, incluyendo la conciliación de ese mes.
La identidad principal ya sale canónica del lector F5; los cotitulares se
canonizan al leer su relación explícita.

Las observaciones de mejora futura (escala productiva, otra empresa/moneda,
otras combinaciones de capas o estados vacíos de tablas secundarias) no se
presentan como casos ensayados. No hay P0/P1 confirmado sin resolver en la
candidata; los gates de instalación, revisión humana y G6 siguen abiertos.
