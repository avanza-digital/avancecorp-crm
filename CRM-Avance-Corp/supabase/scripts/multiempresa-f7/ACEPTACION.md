# Aceptación técnica local — F7 multiempresa

Fecha: 11/09/2026. Codex PRIMARY. **Candidata local; no instalada ni publicada.**
La aceptación humana y financiera [G6](ACTA-G6.md) sigue pendiente.

## Alcance comprobado

- Consulta de Gerencia por empresa y moneda, reutilizando los núcleos de
  capital, conversión y atribución. Cotitulares sin multiplicar dinero.
- Identidades coherentes, ausentes y contradictorias; veto No contactar
  canónico y legado; vencimientos; límites de mes Lima y precisión de céntimos.
- RPC autorizadas en servidor, pertenencia vigente y bandera OFF; revocación
  oculta los datos. El JSON de PostgreSQL y HTTP pasa por el validador real
  del frontend. Un grupo perdido se presenta como diferencia, no como éxito.
- Migración aditiva con guardas de cuatro núcleos y reversa que conserva
  objetos, ACL y propietarios. Comisiones fuera del CRM.

## Gates

| Verificación | Estado | Evidencia / alcance |
|---|---|---|
| Banco PostgreSQL F7 | PASS | 16 pruebas, copia sintética propia; instalación, permisos, paridad y reversa |
| Auth y PostgREST locales | PASS | 9 pruebas HTTP reales, incluidas denegaciones y contrato del cliente |
| Scripts y preflights offline | PASS | `check:scripts`, `seed:preflight`, `test:rls:preflight`, `test:edge-preflight` |
| Frontend integrado | PASS | Lint, typecheck, 3.329 pruebas en 233 archivos con cobertura, release, service worker, build, bundle y duplicación |
| Navegación integrada | PASS | 168 E2E aprobados; 26 SKIP preexistentes. Incluye F7, F6 y las nuevas notificaciones recibidas desde Main |
| Integración de Main | PASS | Base `5d49bcf`, código F7 `2a9ff19`; se preservaron los cambios ajenos. Los nueve pasos equivalentes de `check:all` pasaron con concurrencia acotada |
| Advisors del banco F7 | PASS de comparación | Cinco WARN ya presentes en la base original; cero nuevos. No significa que el proyecto carezca de advertencias |
| Claude | CHANGES_REQUESTED, evaluado | Dos revisiones; decisiones y evidencia en [REVISION.md](REVISION.md). No es un PASS del reviewer |
| Inspección visual automatizada | PASS | Escritorio y 320 px; tablas con desplazamiento interno, capturas ficticias en `evidencias/` |
| Instalación y gates en rama Supabase remota | NOT RUN | Pendiente aprobación del SQL concreto y ensayo autorizado |
| Matriz RLS general real en esta fase | NOT RUN | El preflight no la sustituye; matriz específica F7 sí ensayada |
| Rendimiento con volumen productivo | NOT RUN | La medición local de 98 fuentes no permite extrapolar |
| Revisión manual F7 / conciliación firmada G6 | NOT RUN | No se infiere de los tests ni de las aprobaciones históricas F6 |
| VoiceOver F6 | NOT RUN | Omitido por decisión explícita de Miguel; no se presenta como verificado |
| Piloto económico F8 / operación mensual F9 | NOT RUN | Fases posteriores, sujetas a sus puertas |

## Incidencias de verificación, conservadas sin ocultarlas

Una ejecución de `check:all` agotó 5 s en un caso antiguo de conversión de lead.
El mismo caso sin cambios pasó aislado en 588 ms; la ejecución siguiente pasó
las 3.308 pruebas completas. No se aumentaron límites ni se retiró el caso.

En esa ejecución posterior, Playwright con siete workers pasó 163 casos,
omitió los 26 ya condicionados por la suite y falló al esperar la tabla Leads.
La captura mostraba la navegación correcta y el encabezado Leads, sin el
contenido de la pantalla. Los cuatro casos de ese archivo pasaron al reproducir
con dos workers y trazas, sin cambiar aserciones, reintentos ni tiempos.
Esto es compatible con demora de carga bajo concurrencia; no demuestra una
causa definitiva. La suite completa con dos workers pasó 164 casos y mantuvo
los 26 SKIP existentes, incluida la nueva comprobación visual de diferencias.

El problema distinto y reproducible de Escape de F6 se diagnosticó con trazas.
La solución local pasó la misma secuencia 8/8 veces. Al integrar Main hasta
`5d49bcf` se cotejó la corrección recibida en `e01aea1`: se conservan intactos
sus componentes y pruebas, retirando la propuesta local. La entrega contiene
una sola implementación, verificada de nuevo en el conjunto integrado.

La primera ejecución tras integrar `5d49bcf`, con la concurrencia automática
de Vitest, terminó con 13 fallos en ocho archivos y dos rechazos sin manejar.
Predominaron límites de 5 s en pantallas distintas; en `lead-nuevo.test.tsx`
los siguientes casos fallaron después del primer timeout. Se conserva ese
resultado como FAIL. El cierre ejecuta todos los pasos del gate en serie,
limitando Vitest a dos workers y Playwright a dos, sin cambiar código de
producto, cobertura, casos, aserciones, reintentos ni tiempos permitidos.
Los nueve pasos terminaron con código de salida cero: 3.329 pruebas unitarias,
168 E2E y 26 SKIP. La causa exacta de las demoras de las ejecuciones previas
no se da por demostrada; no se ocultan aquellos FAIL ni se atribuyen a un
cambio de comportamiento de F7.

Los logs originales de intentos y diagnósticos permanecen en el respaldo
privado. [verificacion.json](evidencias/verificacion.json) identifica los
resultados finales y sus huellas, sin credenciales ni datos personales.

## Entrega y siguiente paso

El [SQL propuesto](../../migrations/20260911163243_crm_multiempresa_f7_metricas_sombra.sql)
y su [reversa](reversa-operativa.sql) se identifican en
[SHA256SUMS](evidencias/SHA256SUMS). Instalación pendiente de aprobación.
El consumidor puede publicarse antes del SQL porque contempla RPC ausente/OFF.
No se habilitan las banderas de escritura F4, ficha F5 ni postventa F6.

Antes de publicar, integrar `avancecorp/main` sin sobrescribir cambios ajenos,
verificar que Main y remoto comparten commit y construir desde ese commit.
El ciclo remoto, los datos reales y G6 siguen los pasos del [README](README.md).
