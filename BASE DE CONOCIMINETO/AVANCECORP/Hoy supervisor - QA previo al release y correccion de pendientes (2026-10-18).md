---
tags: [crm, hoy, supervisor, release, verificacion]
actualizado: 2026-10-18
estado: qa-completo-publicacion-posterior-registrada
---

# Hoy supervisor - QA previo al release y correccion de pendientes (2026-10-18)

**Actualización posterior:** publicado mediante `$release-crm`; versión efectiva y límites en [[Hoy supervisor - publicado y verificado (2026-10-18)]]. Lo siguiente conserva el historial de preparación y revisión anterior al despliegue.

Miguel pidió ejecutar las pruebas pendientes antes de lanzar release. Codex las corrió en Docker local; solo SQL de lectura en producción. No se publicó ni se cambiaron datos reales.

Base: Main 56737bfb. E2E inicial: 463 PASS, 4 FAIL por recorridos anteriores y fixtures incompletos, 26 SKIP. Se actualizó el banco y se recuperó la etiqueta Cliente en el detalle de tareas. No cambian cálculos ni permisos.

Corrección e1ab0ebab29843b8201f6be2f56df4d1a8948092, PR https://github.com/avanza-digital/avancecorp-crm/pull/328. Claude PASS; P3 contrastados por Codex. Verificación final: 467 E2E PASS, 26 SKIP, 7.262 unitarios PASS, lint/tipos/build/bundle/config/SW/duplicación PASS. Un timeout previo en Cargar base pasó aislado (35 tests) y en la repetición completa con dos workers, sin cambios al test.

19 comprobaciones con respuestas reales anonimizadas de cuatro supervisores PASS: capital y operaciones coinciden con Facturación, incluyendo ventas propias, y lecturas operativas/Citas/tareas. SQL bajo rol authenticated rechazó consultar otro equipo con 42501. Reparto confirmado: un ámbito con 1 pendiente y los demás con 0. Cuatro recorridos visuales de escritorio/móvil PASS; 14 capturas conservadas.

Avisos de paridad del banco: 273 clientes sin domicilio legal y 45 ventas de analistas de baja. No se ocultaron ni modificaron estos datos. No se hizo login HTTP productivo ni prueba humana de usabilidad; se usó SQL READ ONLY más replay local con estructura real y nombres anonimizados.

**Actualización de cierre:** PR #328 apareció integrado externamente a las 19:28:47 UTC. Codex comprobó que Main local y remoto son 2686f755fb600fee5c8c659a80cd15d043fa431a y que su árbol completo es idéntico a e1ab0eba probado. Sin bypass de protecciones. ZIP actualizado crm-20261018T193536Z-2686f755fb60.zip, build hoy-supervisor-qa-20261018-2686f755fb60, SHA-256 6ec35d534814705fc6a9c8408f7ec3437b57acbaec5889bcd43fb32dadb7212c, 2.602.701 bytes. Verificación oficial y auditoría de 166 archivos/1.147 referencias PASS. **No publicado:** el siguiente paso es el flujo humano de release. El ZIP anterior se conserva como historial y el taller original sucio no se sobrescribió.

Evidencia estable: CRM-Avance-Corp/releases/hoy-supervisor-2026-10-18/QA-PRE-RELEASE.md y qa-2026-10-18/.

[[Hoy supervisor - ZIP verificado sin publicar (2026-10-18)]] · [[Hoy supervisor - resultados diarios y plan por fases con Claude (2026-10-18)]] · [[Inicio]]

## Revisión de CodeRabbit solicitada después de integrar

Miguel pidió reabrir el PR para CodeRabbit. GitHub rechazó reabrir el #328 por estar fusionado, y CodeRabbit rechazó revisarlo por estar cerrado. Se abrió el [PR #329](https://github.com/avanza-digital/avancecorp-crm/pull/329), **solo para revisión; no fusionar**, con los mismos siete archivos y el mismo commit e1ab0eba. Su base `review/hoy-supervisor-328-base` apunta al estado anterior 56737bfb; la rama de cambios original sigue siendo `fix/hoy-supervisor-qa-20261018`. Main y el ZIP verificado no cambian.

La revisión automática se omitió por usar una base distinta de Main, pero el comando manual `@coderabbitai full review` fue aceptado: [CodeRabbit confirmó «Full review triggered»](https://github.com/avanza-digital/avancecorp-crm/pull/329#issuecomment-6254345945) a las 19:47:04 UTC. Estado al registrar: revisión iniciada, dictamen pendiente. Si hay hallazgos válidos, corregirlos en un cambio posterior contra Main; no volver a integrar el PR de comparación.

**Resultado posterior:** CodeRabbit terminó a las 19:54 UTC sin comentarios accionables; dejó solo una advertencia de cobertura de docstrings (33,33% frente a su 80% predeterminado). A petición de Miguel, Codex contrastó el resultado con Claude mediante el wrapper del repositorio: **PASS** a las 19:57 UTC. Codex confirmó que no hay cambios obligatorios en este diff. Claude propuso como mejoras opcionales hacer deterministas las fechas de los fixtures y añadir una comprobación negativa del badge para leads. La distinta navegación de clientes solo del portal ya estaba documentada/probada en Seguimiento y no se modificó aquí. No se implementaron cambios ni se repitieron pruebas de producto, pues se conserva el mismo árbol ya verificado; los controles actuales del PR pasaron. El #329 sigue abierto solo para revisión, sin fusionarlo ni publicar.

Informe y evidencia independiente de esta consulta: `CRM-Avance-Corp/releases/hoy-supervisor-2026-10-18/revision-pr329-2026-10-18/REVISION-CODERABBIT-CLAUDE.md`, con respuesta de CodeRabbit saneada, diff, encargo/dictamen de Claude, contraste de Codex e índice SHA-256. No altera la evidencia sellada de la QA anterior. [[Hoy supervisor - ZIP verificado sin publicar (2026-10-18)]]
