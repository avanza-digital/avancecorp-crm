# Fase 6 · Validación integral

Estado: **PASS local**, con límites de entorno explícitos. La fase termina con la comprobación integral final y la regresión de los formularios corregidos. No acredita instalación ni exigencia en producción.

## Revisión Codex y correcciones

La prueba Docker de visita sin cita detectó que, al confirmar y retirar su botón de origen, se perdía el foco. La prueba de una cita ya agendada reprodujo el mismo problema. Se separó el cierre por cancelación del cierre tras guardado confirmado: cancelar vuelve al botón; guardar/anular vuelve al encabezado estable de la guía. El formulario habitual, su motor de siguiente acción, validaciones y persistencia se conservan. La corrección pasó los seis E2E nuevos y 87 pruebas unitarias focales.

Los primeros intentos del nuevo runner HTTP detectaron errores de sus fixtures: membresía activa con perfil inactivo (estado que la puerta vigente prohíbe), nombre incorrecto de argumento de confirmación y analista sintético sin datos legales para el contrato. Se corrigieron los datos y las llamadas de prueba, sin debilitar ninguna guarda de producto. La ejecución final completa pasó.

## Matriz de evidencia

| Comprobación | Estado | Evidencia |
|---|---|---|
| `npm run check` integral después de corregir foco | PASS · 456 archivos, 7.314 tests; lint, tipos, cobertura, configuración, build, bundle y duplicación | `evidencia/fase6-check-final.log` |
| Backend offline: scripts, seed preflight, RLS preflight, Edge preflight | PASS | `evidencia/fase6-backend-preflight.log` |
| Sintaxis de los seis runners del recorrido | PASS · `npm run check:recorrido`, incorporado al gate de scripts | `package.json` |
| HTTP/RLS con sesiones Auth y PostgREST reales | PASS · 79 comprobaciones | `evidencia/fase6-http.log` |
| SQL/RLS, replay y concurrencia de los tres bloques | PASS · evidencia de fases 2, 3 y 5; no se sustituyen por mocks | Informes y logs de esas fases |
| Carga de 4.000 leads y 60.000 actividades | PASS · p95 37,60 ms/100 IDs en este banco | `evidencia/fase2-rendimiento.log` |
| Lint SQL de las 17 funciones candidatas | PASS · cero hallazgos | `evidencia/fase6-lint-sql.json` |
| Lint SQL global del banco | FAIL · cinco funciones previas dependen de `cron.job`/`net`, deliberadamente no instalados | `evidencia/fase6-db-lint.log` |
| Docker E2E de los seis recorridos nuevos | PASS · 6/6, sin retries | `evidencia/fase6-e2e-recorrido-final.log` |
| Tipos/lint y unitarias tras corregir foco | PASS · 87 tests | `evidencia/fase6-foco-unit-docker.log` |
| Docker E2E general | PASS · 467 passed, 26 skipped, 0 failed; 18,1 min | `evidencia/fase6-e2e-completo.log` |
| Regresión Docker tras la corrección final de cierres, postventa y seis casos nuevos | PASS · 41/41, sin retries; 1,9 min | `evidencia/fase6-e2e-regresion-cierre.log` |
| Advisors de rama hosted | NOT RUN · no se creó recurso ni se confirmó gasto | Requisito de instalación productiva futura |
| Safari/VoiceOver manual | NOT RUN · sin usar computador/navegador interactivo | Lista semántica y foco cubiertos con componentes reales y Chromium Docker |
| Migración/activación productiva | NOT RUN · fuera de autorización | `INSTALACION-Y-ACTIVACION.md` |

La cobertura integral final fue 82,17% statements, 78,82% branches, 79,32% functions y 85,11% lines. La suite general arrancó antes de la corrección de foco; por eso se repitieron después los seis specs afectados (41 pruebas), además del gate integral. Los avisos de lint en componentes anteriores y de tamaño de chunk no son errores nuevos de este cambio.

## Qué demuestra la prueba HTTP real

`node supabase/scripts/test-rls.mjs --recorrido-lead` crea una base desechable dentro del contenedor propio, copia su esquema y datos sintéticos, completa únicamente autores ficticios de configuración y restaura todas las constraints/triggers. Levanta Auth y PostgREST de las mismas imágenes del banco en puertos loopback asignados por Docker. No usa JWT inventados ni service_role como escritor económico. Al terminar elimina sus contenedores y su base; comprueba que modo/revisión/corte del banco de origen permanecen intactos.

- Lectura exacta por vendedor/supervisor/subárbol, gerencia, coordinación y directorio. Rechazo de anon, service_role sin sesión de usuario, perfiles/membresías inactivos y usuarios sin membresía.
- Activación exclusiva de Gerencia, revisión optimista, corte servido, antiguos no retrobloqueados y conversión nueva rechazada aunque cambie de etapa.
- Oficina con permiso y ámbito actuales, pareja de evidencias válida, respuesta perdida idempotente y rechazo si cambia el capital usando la misma clave.
- Qorilazo y Prodelco: invalidar la entrevista después del borrador impide confirmar; se preservan condiciones y comprobante. Una entrevista válida permite confirmar sin duplicar y deja snapshot de la pareja vigente. El comprobante es un fixture de Storage; esta prueba no valida bytes subidos por interfaz.
- Avance: el handler oficial se ejecuta en proceso y hace sus llamadas reales a Auth/PostgREST de la copia. Sin entrevista no crea Auth; tras corregir los hechos, crea acceso/perfil y confirma el contrato con JWT del analista. Esto no acredita un despliegue Edge.
- No se puede falsificar el snapshot por PATCH ni leer/escribir directamente las tablas cerradas de control/contexto. Se comprueban owner, SECURITY DEFINER, search_path y EXECUTE de helpers.
- Reasignación conserva ciclo/hechos y retira acceso/replay al actor anterior. Una baja real con reemplazo invalida el acceso del JWT anterior sin esperar su expiración.

Los E2E de interfaz usan el transporte simulado del banco habitual del proyecto; las reglas del servidor se acreditan separadamente mediante SQL y HTTP reales. La suite no instala n8n ni activa servicios cron/red para conseguir un PASS artificial.

La política propuesta, corte, modos y reversión están definidos en [INSTALACION-Y-ACTIVACION.md](INSTALACION-Y-ACTIVACION.md). El visto bueno comercial sobre antiguos y cualquier activación son requisitos de una publicación futura, no acciones ejecutadas para construir el ZIP.

Cierre Codex: los hallazgos del alcance aceptados están corregidos y verificados. Se permite avanzar a revisión del PR y entrega del artefacto. El gate hosted/advisors del merge de base y la autorización de activación permanecen como requisitos para una instalación productiva futura, según `LEEME.md`; no son un permiso implícito para desplegar desde este Goal.
