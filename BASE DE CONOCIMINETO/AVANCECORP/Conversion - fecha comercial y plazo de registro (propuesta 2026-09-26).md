---
tags: [crm, conversion, backend, cierre-mes, propuesta]
fecha: 2026-09-26
estado: publicada y verificada el 27/09/2026; ver acta productiva
---

# Conversión — fecha comercial y plazo de registro

## Estado vigente — publicada 27/09/2026

[[Conversion - publicacion verificada (2026-09-27)]] es el estado vigente:
PR #113 integrada, dos SQL por merge nativo, conciliación activa desde septiembre
y frontend `88db9ebf` publicado. 97 acreditaciones, 9 fuera de plazo, 2 pendientes;
contratos/cuotas e histórico conservados. Matriz final 2268/0 y 80 archivos HTTP
verificados. Los apartados de preparación inferiores son historial, no bloqueos
actuales. El acta detalla las limitaciones reales y la recuperación.

## Objetivo del plan

Implementar y verificar una única regla de atribución temporal de conversión
en el backend del CRM: cada captación elegible cuenta en el mes de cierre
comercial de la operación que la sustenta, solo si se acredita dentro del plazo
del día 10 del mes siguiente, completo, en America/Lima, y antes de su sello.
Los registros tardíos quedan trazables sin crédito en el mes original ni en el
de carga. Preservar inversiones, capital, identidades, auditoría, fotos selladas,
atribución del analista y reglas de cartera. Todas las superficies afectadas
deben consumir la decisión común y la entrega debe superar los controles reales
del proyecto antes de publicarse con autorización.

Miguel ratificó el ejemplo: contrato con cierre comercial de enero cargado el
26 de septiembre como Formulario NO acredita conversión en enero ni septiembre,
incluso con Cron apagado. El canal no amplía el plazo. Se aplica a la decisión
nueva/tardía, no borra un crédito histórico válidamente registrado a tiempo.

## Encargo copiable para /goal

```text
Implementa y verifica la conversión por fecha de cierre comercial y plazo de
registro siguiendo las fases F0–F5 de la nota «Conversion - fecha comercial y
plazo de registro (propuesta 2026-09-26)» del vault AVANCECORP.

Reglas aprobadas: mes de cierre comercial; plazo hasta las 00:00 del día 11
del mes siguiente, excluidas, en America/Lima; registros fuera de plazo no
acreditan en ningún otro mes, aunque Cron esté apagado; conservar trazabilidad,
capital y fotos selladas. El contrato de enero cargado el 26 de septiembre
como Formulario debe dar cero crédito tanto en enero como en septiembre.

Empieza por inventario y simulación de impacto de solo lectura. Antes de
implementar la política, verifica las decisiones F1 documentadas y resuelve
las excepciones históricas identificadas en F0. Miguel ya confirmó operación
confirmada y vinculada antes del límite, y vigencia desde septiembre de 2026:
recalcular septiembre y conservar agosto y meses anteriores.

Respeta AGENTS.md y la guía de Supabase, CodeGraph primero, núcleo privado
único, puertas con autorización sin fórmulas y frontend sin recálculos. Solo
Codex PRIMARY escribe; reutiliza la revisión de diseño ya hecha y reserva la
consulta adicional justificada a Claude para el diff implementado y evidencia.
No alteres public, fechas/importes de contratos, políticas de cartera ni meses
históricos sin autorización específica. Preserva trabajos ajenos y no crees
worktrees automáticamente.

Verifica SQL, permisos/RLS, concurrencia, paridad entre consumidores, límites
horarios, anulaciones/deuda, idempotencia, regresiones, calidad de frontend
cuando aplique y E2E locales Docker conforme a las reglas del proyecto.
Registra PASS/FAIL/NOT RUN con evidencia; no cierres fases con pruebas supuestas.

Entrega migración nueva, ledger MIGRACIONES, reversa compatible, tipos si
corresponden, simulación antes/después y documentación. Solicita autorización
para costes/ramas de prueba nuevos. No ejecutes SQL directo en producción,
no actives Cron ni selles históricos. Publicación solo cuando Miguel autorice
el flujo de release y el SQL exacto, con Main igual a avancecorp/main y artefacto
del commit verificado. Mientras falte esa autorización, entrega lista para
publicar e indica que F5 permanece pendiente; no afirmes publicación ni objetivo
productivo completado. Tras publicación autorizada, verifica el resultado real.
```

## Decisión y alcance

Miguel propone que una conversión pertenezca al mes del contrato y que, si su
mes ya cerró, no gane crédito en el mes de carga. El plazo para registrar es el
día 10 del siguiente mes. Posteriormente eligió explícitamente **fecha de cierre
comercial**, no fecha de inicio contractual, e **incluir todo el día 10 hasta
las 23:59 de Lima**. El límite preciso será las 00:00 del día 11, excluidas.

«Perder la conversión» significa perder el crédito de conversión, no borrar el
lead, contrato, inversión, historial, capital ni trazabilidad. No se traslada
ese crédito al mes siguiente. No confundir una conversión tardía nunca abonada
con una anulación posterior de una conversión que sí fue abonada: esta última
conserva el mecanismo vigente de deuda/ajuste.

Miguel inició el objetivo de ejecución y confirmó continuar este plan, descartando
el adjunto equivocado de F5 de pagos. F0 se contrastó en solo lectura. Esto
no autoriza publicar, activar Cron, cerrar meses históricos, crear una rama de
pago ni tocar objetos de public. Las decisiones F1 ya están aprobadas; la
candidata local no es todavía una autorización de instalación o publicación.

## Hechos contrastados en producción, solo lectura

- `private.conversion_cierres` usa el reloj del episodio convertido
  (`coalesce(resultado_en, finalizado_en)`), no el contrato.
- `private.ranking_conversion_origen_mes` consume esos cierres; el capital usa
  `private.capital_episodios` por período comercial.
- Los dos casos concretos de [[Ranking - conversion sin capital por clientes previos (2026-09-26)]]
  son contratos de diciembre de 2025 y enero de 2026 con leads convertidos en
  septiembre. No deben generar nuevo crédito en septiembre bajo la nueva regla.
- `private.definir_periodo_comercial_contrato` infiere el cierre comercial al
  insertar como el menor entre fecha de inicio y día de registro en Lima. La
  corrección manual tiene RPC auditada de Gerencia.
- El mismo trigger toma candado mensual y **rechaza insertar un contrato nuevo
  en un mes sellado**. Permitir cargas históricas nuevas sin crédito sería otra
  modificación de alcance, en public, que requiere autorización explícita.
- `private.cierre_mes_ventana_desde` habilita sellar desde las 00:00 del día 10.
- El Cron `crm-cierre-mes-diario` tiene horario `20 14 * * *` (09:20 Lima), pero
  **active=false**. `crm.periodos_cerrados` y `crm.cierre_mes_vendedor` tienen
  **cero filas** al consultar. Mes antiguo no equivale a mes efectivamente sellado.
- [[Conversion - una sola pieza para Metas y la oficial (2026-09-23)]] exige
  núcleo común, fotos selladas inmutables y no descontar deuda dos veces al sellar.

## Reglas propuestas

1. El mes de crédito nace del cierre comercial de la operación confirmada que
   sustenta la conversión. En cooperativas se resolverá el equivalente canónico
   vigente, sin sustituirlo por fecha de digitación ni asumir que imputación y
   fecha comercial siempre coinciden.
2. Un único crédito por el evento de captación elegible y la identidad canónica.
   Upgrade, renovación, reinversión y venta cruzada conservan sus reglas propias;
   esta corrección no crea otra primera captación ni cambia su aporte de cartera.
3. Se conserva el analista del cierre acreditado, no se cambia al propietario
   actual del cliente. El origen y los pesos versionados siguen la regla vigente,
   aplicando el peso del mes de crédito, no el mes de digitación.
4. El divisor mantiene su regla actual de asignaciones/llegadas según cada
   indicador; no mover leads recibidos entre meses para acompañar un numerador.
5. Para un crédito nuevo, el destino debe estar sin sellar y dentro del plazo.
   El plazo tiene que funcionar aunque Cron esté apagado o atrasado.
6. El reloj de recepción es del servidor y queda conservado. No recalcular
   elegibilidad con «hoy» en cada consulta: un crédito recibido a tiempo debe
   seguir siendo válido después del día 10.
7. Una incorporación tardía queda trazable como fuera de plazo, sin crédito y
   sin trasladarla. Una foto existente conserva sus cifras y eventos originales.
8. No inferir la operación desde cualquier contrato del mismo perfil. Resolver
   mediante vínculos canónicos deterministas; si falta evidencia o hay ambigüedad,
   informar el caso para conciliación sin fabricar crédito ni multiplicar filas.
9. El corte y la fecha mínima de sello salen de **una sola definición temporal**.
   No mantener dos constantes que puedan divergir. Usar el dominio de candados
   existente `crm.periodos_cerrados` con la misma clave mensual, no otro cerrojo
   independiente del trigger de contratos.
10. No imponer `operacion.creado_en >= lead.creado_en` como descarte universal:
    Miguel autorizó enlaces de leads registrados después de sus contratos.
    Distinguir primera captación registrada tarde de un cliente que ya existía y
    reingresa sin nueva captación. Preservar los casos legítimos antes del límite;
    no inventar elegibilidad por tomar el primer contrato cronológicamente.
11. La ausencia de crédito no borra capital real. Puede existir capital sin
    conversión por registro fuera de plazo, continuidad de cartera u otra
    exclusión válida; alineación de mes no significa igualdad de poblaciones.

## Decisiones de negocio: aprobadas y pendientes

- **Hora límite resuelta:** Miguel aprobó incluir todo el día 10 de Lima, con
  intervalo hasta las 00:00 del 11, extremo final excluido. Exige adaptar el
  momento mínimo del sello; no es lo que hace hoy la función que permite sellar
  desde el 10. La protección del plazo no dependerá de cuándo ejecute Cron.
- **Qué significa «cargado», RESUELTO:** Miguel confirmó explícitamente
  «Sí, confirmada y vinculada a tiempo»: operación confirmada y vínculo de
  conversión acreditado antes del límite. Una solicitud pendiente no reserva
  crédito; un vínculo completado después del límite tampoco. Debe acreditarse
  con reloj del servidor, no por accidente en un JOIN.
- **Vigencia y regularización, RESUELTO:** Miguel eligió explícitamente
  «Sí, desde septiembre de 2026»: recalcular septiembre y aplicar la política
  a los eventos nuevos, conservando agosto y meses anteriores. La aprobación
  se dio tras informar 9 posibles cierres tardíos y otros 7 casos históricos
  pendientes de conciliación. No migrar crédito tardío hacia meses anteriores,
  no crear sellos retroactivos ni cambiar masivamente históricos abiertos.
  Es un cambio visible del numerador de septiembre, no una etiqueta de Ranking.
- **Conciliación F0:** Miguel confirmó que Ricardo Cama, Mónica Vegas,
  Elia Palomino y Tracy Pacual tienen reemplazos por corrección y autorizó
  conciliar esos cuatro vínculos conservando una sola conversión por caso.
  También aprobó dejar a Marco Antonio pendiente sin crédito hasta acreditar
  una inversión. Miguel resolvió Fidel Cuba explícitamente: «conversión solo
  cuenta el de septiembre», contrato 2026-01-001448 (S/20000, 17/09/2026).
  El de mayo 2026-01-000623 (S/50000, 21/05/2026) no genera crédito de septiembre.
  Ambos ingresaron el 21/09 y permanecen intactos, sin reclasificar como upgrade.
  Esta selección explícita no autoriza elegir por cronología en otros casos.
  Ninguna reparación de datos fue ejecutada todavía;
  autorización de negocio no sustituye la aprobación del SQL exacto/release.

Diagnóstico detallado y límites de la simulación:
[[Conversion - F0 impacto y conciliacion pendiente (2026-09-26)]].

## Avance de implementación local

En el clon existente `/private/tmp/ranking-cartera.AfQUSa`, rama
`codex/conversion-fecha-comercial`, se creó por CLI la migración candidata
`20260927035114_crm_conversion_fecha_comercial_plazo.sql`.
Contiene corte común, decisión temporal pura, registro auditado de acreditación,
escritor interno idempotente y lectura comercial del núcleo. Ya están conectadas
confirmaciones Avance/cooperativa, vínculos explícitos, correcciones comerciales
y ajustes por anulación al mes acreditado. La ficha del lead real presenta la
decisión del servidor mediante RPC autorizada separada, sin fórmulas locales ni
ampliar payloads estrictos de Ranking/Metas.

Diez suites SQL y cinco mutantes PASS; once carreras de dos sesiones con bloqueo
real observado PASS. El crédito no caduca al reintentar en 2030. Meses sellados y
capital intactos; anulación con fecha administrativa distinta conserva el mes
comercial y no duplica deuda. Banco sintético Docker, sin datos reales copiados;
pruebas revertidas y bases efímeras de concurrencia retiradas.
Frontend `npm run check` PASS (4468 tests). E2E Docker: 275 passed, 26 skipped,
1 flaky (ancho de Gestión diaria, aprobado al reintentar). No es «todo sin fallos».
Reejecución focal posterior: 11/11 PASS sin reintentos. Gate completo de frontend
repetido PASS; campos nuevos del sello generados por CLI y typecheck PASS.

Manifiesto privado de conciliación: 108 episodios, 106 fuentes exactas sin
repeticiones (97 de septiembre, 9 de meses anteriores), dos sin fuente/crédito.
Fidel conserva la elección septiembre. Revalidación viva 27/09 00:40 Lima: cero
divergencias, identidades canónicas repetidas o episodios nuevos; mes abierto.
Se requiere revalidarlo al aplicar y conservar reloj real, nunca antedatarlo.

Instalación y activación ya separadas: esquema inactivo conserva los resultados
anteriores; activador privado valida el manifiesto y concilia todo atómicamente,
sin antedatar. Reintento, omisión, drift y plazo vencido probados. Reversa exacta
con huellas conserva ledger/auditoría y RPC compatible: PASS.

Claude de implementación devolvió CHANGES_REQUESTED (segunda consulta). PRIMARY
resolvió dos P1 con pruebas: corrección de día dentro del mismo mes conserva el
vínculo recibido a tiempo, y el sello guarda si cada fuente estaba incluida;
una fuente demo excluida antes del sello no genera deuda al anularse después.
Elegibilidad viva compartida por núcleo/estado/sello, sólo triggers CRM. Cambio
operativo de origen posterior no reescribe la atribución congelada. Rechazó
silenciar genéricamente errores de fuente/identidad: puertas oficiales pasan;
fusión conserva filas y no sustituye perfil_id. Evaluación completa en REVISION.md.

Regresiones adicionales PASS: dos contratos reales sintéticos mayo/septiembre,
selección explícita de septiembre, cartera excluida, duplicado canónico, agosto
no vacío idéntico, estado demo, deuda en siguiente mes/saldo único y Metas
frente a oficial tanto fuera_ranking como con roster nominal y cuotas sintéticas
publicadas mediante revisión nueva y guards activos.

Retiro anterior/posterior al sello probado por la puerta auditada oficial:
conserva hechos/fotos y sólo genera deuda si estaba incluido al sellar. Trigger
CRM en la auditoría previa al borrado comparte candado mensual y evita ciclos
con el lead mediante NOWAIT/PT409. No modifica public. Carreras adicionales
corregir/sellar, anular/sellar, corregir/anular y retirar/sellar en ambos órdenes
PASS; reversa y banco SQL completo repetidos después del último ajuste, PASS.

Proyección de sólo lectura 27/09 00:42 Lima: captación ponderada 75,70 → 66,55
(−9,15: nueve fuentes de meses previos y dos pendientes). No es un dato publicado;
mantiene el resto de cartera/divisor/capital. SQL/JSON privados en el directorio
de evidencia. Debe revalidarse antes de activar.

**F4/F5 siguen pendientes**: matriz HTTP/Auth integral, advisors y tipos remotos,
repetición pertinente en ensayo autorizado y puertas de publicación. Retiro,
carreras y cuotas nominales ya probados localmente. No publicar aún. La caída
local quedó aislada al error de
EXECUTE de supautils (issue 214); ACL efectiva verificada, rechazo runtime NOT RUN.
Producción tiene la misma imagen 17.6.1.105: no reproducir allí la caída.
Miguel autorizó el coste US$0,01344/h en AVANCECORP- CRM-PORTAL y se creó
`conversion-fecha-20260927` (`qxpcuctzsnomnipqlrgn`). Baseline remoto: 22 de
2267 aserciones fallaron antes de instalar la candidata. Se corrigieron las
omisiones del banco: herencia/pertenencia del rol lector de Gestión Diaria,
metadatos técnicos de auditoría y política inicial histórica OFF. Verificación
SQL PASS. Repetición HTTP focal detenida por precondición: 16 leads activos
residuales del primer gate, se esperan 7; requiere reconstrucción sintética
limpia de la misma rama. No omitir esa precondición ni afirmar gate PASS.
Publicación solicitada condicionalmente por Miguel; aún faltan gates y
confirmación del SQL exacto/release. Candidata no instalada remotamente.
Detalle vigente en `supabase/scripts/conversion-fecha/ENSAYO-REMOTO.md` del clon.
Estado y próximo trabajo en
`CRM-Avance-Corp/supabase/scripts/conversion-fecha/ESTADO.md` del clon aislado.
No se modificó producción ni código del árbol raíz ajeno. Cron sigue apagado.

## Plan por fases respetando las capas

### F0 — Inventario e impacto, sin escrituras

Contrastar cuerpos vivos con Main, contratos de payload y llamadas directas e
indirectas. Mapear conversiones por mes/rango/origen, oficial, Metas, Ranking,
HOY, Citas cuando corresponda, cierre mensual, anulaciones y deuda. Medir los
casos afectados en todas las empresas, identidades fusionadas, dobles leads y
legados sin enlace directo. No restringir el diagnóstico a Betzabeth.

**Criterio de cierre:** inventario de consumidores y reporte por mes/analista
con entradas, salidas, duplicados, ambigüedades y pruebas reproducibles. No se
alteró producción.

### F1 — Contrato de negocio y calendario

Cerrar las decisiones anteriores. Documentar ejemplos, vigencia, crédito
fuera de plazo, regla de confirmación y tratamiento de casos no conciliados.
Separar autorización de activar el cierre automático y su alcance de meses;
no encenderlo a ciegas ni sellar de golpe meses pasados.

**Criterio de cierre:** política de carga/confirmación/vínculo y alcance temporal
ratificados; ejemplos y exclusiones documentados. No confundir esta aprobación
de negocio con permiso de publicación, creación de ramas de pago o encendido.

### F2 — Núcleo único y trazabilidad

Cambiar la decisión en el núcleo privado compartido, en torno a
`private.conversion_cierres` y sus consumidores, no solo en Ranking. Reutilizar
los eventos y auditoría existentes; añadir persistencia solo si hace falta para
conservar una decisión estable de atribución/plazo y con una fuente única.
No reescribir fechas de auditoría del ledger. Puertas CRM autorizan y arman
respuestas; no recalculan. Pantallas presentan; no deciden el mes.

Confirmación, rectificación y cierre comparten candados en orden determinista,
idempotencia y decisión temporal del servidor. Una corrección que mueve período
debe validar ambos meses; no abrir una puerta retroactiva al cambiar la fecha.
No alterar fechas/importes de contratos, cronogramas, PDFs ni categoría financiera
para hacer cuadrar el indicador. Preservar RLS/grants y autorización del analista.

**Criterio de cierre:** núcleo único implementado; mes y exclusión explicables;
crédito estable después del corte; corte/sello coherentes desde día 11;
confirmación/corrección/cierre con los candados compartidos; sin alterar capital.

### F3 — Pantallas y contratos de respuesta

Mostrar mes acreditado y explicación de exclusión cuando corresponda, sin
inventar un porcentaje alternativo. Identificar primero todos los envoltorios
SQL y validadores estrictos del frontend publicado. Campos nuevos solo mediante
cambio compatible/versionado y pruebas: un JSON aditivo puede romper un esquema
estricto. Si no hace falta UI, no forzar un release de frontend.

**Criterio de cierre:** consumidores compatibles, sin segunda fórmula ni error
de payload; casos tardíos distinguibles de datos pendientes/ambiguos y de cartera.

### F4 — Pruebas y revisión

Banco aislado con fixtures sintéticos fieles al estado real. Matriz: registro
normal, carga del mes anterior a tiempo, tardía, foto sellada, Cron apagado,
fronteras 9/10/11 Lima, lead enlazado tarde, pendiente/confirmado, fecha futura,
reasignación, venta cruzada, dobles leads, fusión, cooperativas, renovación,
upgrade, anulación y deuda. Ensayo real de dos sesiones para confirmar/sellar.
Comprobar idénticas fotos cerradas y que las conversiones a tiempo sobreviven
al avance del reloj. Oráculo independiente, mutantes y comparación por persona
entre oficial/Metas y sus consumidores; diferencias de universos documentadas.

Gates: SQL/RLS/Auth pertinentes, advisors, esquema/tipos si cambian, calidad de
frontend cuando aplique y E2E **locales en Docker**, nunca GitHub. Claude revisa
como SECONDARY_REVIEWER; una opinión no sustituye las pruebas.

**Criterio de cierre:** gates pertinentes PASS con evidencias, observaciones
aceptadas del reviewer resueltas y limitaciones explícitas. Un NOT RUN no se
presenta como PASS ni habilita una publicación que exige ese control.

### F5 — Migración y publicación controladas

Migración nueva, nunca editar una versionada; actualizar MIGRACIONES.md.
Rama Supabase autorizada → ensayos/RLS/advisors → merge aprobado. Main debe
coincidir con avancecorp/main. No aplicar SQL directo en producción. Reversa
compatible con las decisiones ya registradas y fotos existentes: no basta
restaurar el cuerpo anterior si con ello se vuelven a acreditar conversiones.
Verificar los casos reales, cifras por mes/analista y que no cambió el capital.

**Criterio de cierre:** ensayo remoto autorizado, migración y artefacto exactos
publicados tras sus aprobaciones, comprobaciones posteriores satisfactorias y
documentación de recuperación. Si falta autorización, la fase sigue pendiente.
La activación de Cron y el sellado de históricos no son parte automática de F5.

## Verificación histórica de la propuesta, anterior a la implementación

Este apartado registra la revisión inicial del diseño. Los NOT RUN siguientes
son históricos; el estado vigente está en «Avance de implementación local».

- Consultas de diagnóstico de producción: PASS, solo lectura.
- Implementación y pruebas de una solución: NOT RUN; todavía no hay cambio.
- Revisión independiente Claude: **CHANGES_REQUESTED**, confianza MEDIA, sobre
  diseño y extractos saneados; sin código de implementación. Primer intento no
  completó y no cuenta como gate; reintento mediante wrapper aislado entregado.
- PRIMARY incorporó: separar plazo vencido de mes sellado; corte y sello desde
  una fuente; vigencia y simulación explícitas; reloj de vínculo/confirmación;
  posible capital sin crédito; candados compartidos; casos ambiguos trazables.
- PRIMARY rechazó la prohibición universal de operación anterior al lead por
  contradecir los enlaces atípicos expresamente aceptados por Miguel. La fecha
  comercial puede diferir del inicio también por corrección auditada: no asumir
  que la desigualdad del INSERT inicial es un invariante histórico absoluto.
- La vigencia desde septiembre de 2026 fue aprobada por Miguel durante F0;
  todavía no está implementada ni aplicada en producción.
- Fecha comercial y día 10 inclusivo quedaron confirmados por Miguel durante
  la revisión. Las pruebas SQL/RLS/E2E de la solución siguen NOT RUN.

Relacionado: [[Periodo comercial de contratos]] · [[Cierre de mes]] ·
[[Plan por fases - inversion por empresa y ranking de cartera (2026-09-26)]].
