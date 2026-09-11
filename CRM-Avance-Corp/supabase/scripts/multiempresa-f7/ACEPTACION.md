# Aceptación técnica y publicación — F7 multiempresa

Fecha: 11/09/2026. Codex PRIMARY. **Publicada e instalada OFF; banco temporal cerrado.**
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
| Frontend integrado | PASS | Lint, typecheck, 3.355 pruebas en 235 archivos con cobertura, release, service worker, build, bundle y duplicación |
| Navegación integrada | PASS | 172 E2E aprobados; 26 SKIP preexistentes. Incluye F7, F6 y las nuevas notificaciones recibidas desde Main |
| Integración de Main | PASS | Main `6293d24`, integrado en `92ca108`; cambios ajenos conservados. `check` y E2E completos con dos workers PASS; [evidencia actual](evidencias/preparacion-instalacion-2026-09-11.json) |
| Advisors del banco local F7 | PASS de comparación local | Cinco WARN ya presentes en la base original; cero nuevos. El banco remoto tiene una base distinta, registrada por separado |
| Claude | CHANGES_REQUESTED, evaluado | Dos revisiones; decisiones y evidencia en [REVISION.md](REVISION.md). No es un PASS del reviewer |
| Inspección visual automatizada | PASS | Escritorio y 320 px; tablas con desplazamiento interno, capturas ficticias en `evidencias/` |
| Ensayo específico en Supabase remoto | PASS | SQL y coste aprobados; 16 SQL + 12 HTTP, tipos regenerados y reversa. Repetición final de los doce HTTP PASS. [Ensayo remoto](ENSAYO-REMOTO-2026-09-11.md) |
| Matriz RLS general real en esta fase | FAIL; comparación PASS sin regresiones | Antes y después: 1.772 PASS / 57 FAIL de 1.829 con la misma semilla. Incluye conteos por convivencia de fixtures. No es un PASS global |
| Advisors remotos | Diferencias evaluadas; sin PASS global | Seguridad 259 → 261: solo dos WARN previstos para RPC F7 autenticadas, permisos SQL/HTTP comprobados. Rendimiento 278 → 145, cero nuevas observaciones |
| Publicación del frontend | PASS | Main/remoto/origen del ZIP iguales a `32eae8a`; release correcto, 90 recursos cotejados y portal conservado. [Acta](PUBLICACION-2026-09-11.md) |
| Instalación y verificación productiva OFF | PASS | Registro `20260911212526`; 274 migraciones y 619 funciones previas intactas, cuatro nuevas exactas. Auth, datos financieros, Vault, cron y 19 Edge Functions conservados. OFF/P0409; anon 42501 |
| Cierre del banco propio | PASS | Eliminado y ausencia verificada a las 21:47:18 UTC; banco anterior conservado |
| Rendimiento con volumen productivo | NOT RUN | La medición local de 98 fuentes no permite extrapolar |
| Revisión manual F7 / conciliación firmada G6 | NOT RUN | No se infiere de los tests ni de las aprobaciones históricas F6 |
| Preparación de G6 con cifras reales | PASS técnico, G6 ABIERTO | [Corte del 11/09 a las 17:51 Lima](ACTA-G6.md): 218 operaciones, ocho grupos, sin diferencias de capital/conversión/atribución; diez identidades pendientes, anexo privado listo. Cotitulares/multiempresa/veto sin casos reales en este corte |
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
[SHA256SUMS](evidencias/SHA256SUMS). Miguel aprobó ese SQL y su instalación
inicialmente OFF el 11/09/2026. También autorizó US$0.01344/h para el banco
propio, ya eliminado. La publicación desde el commit común Main/remoto y la
instalación están verificadas en [PUBLICACION-2026-09-11.md](PUBLICACION-2026-09-11.md).
F3 ON; F4/F5/F6/F7 OFF. La lectura real de [G6](ACTA-G6.md) ya está preparada;
sigue la revisión humana y financiera del comparativo. No se autoriza el piloto
F8 ni se adelanta F9.
