# Verificación — Coordinación, cartera y categoría

15/10/2026. **Implementación validada localmente; producción sin cambios.**
Trabajo en copia aislada autorizada por Miguel, integrado sobre `avancecorp/main` `9bb58ec1`,
con los cambios Formulario 3 publicados durante el desarrollo conservados. El working tree
original no se modificó. No se ejecutó publicación ni ninguna migración remota.

## Resultado de los checks

| Verificación | Resultado | Evidencia y alcance |
|---|---|---|
| Frontend `npm run check` | PASS | Lint, TypeScript, cobertura: 430 archivos / 6.928 tests; configuración de release, push, build y bundle; duplicación 0,42 %. |
| E2E `npm run test:e2e:docker` | PASS | Suite completa después de integrar F3: 422 aprobados, 26 omitidos, 0 fallidos, 16,6 min, 2 workers. Incluye Coordinación, Leads, corrección en escritorio/móvil y reparto. Transporte API simulado. |
| `npm run check:scripts` | PASS | Gate de scripts completo. El primer intento fue bloqueado por el sandbox al abrir un puerto local; la repetición autorizada pasó. |
| `npm run seed:preflight` | PASS | Fixtures y entorno offline; sin abrir conexión. |
| `npm run test:rls:preflight` | PASS | Matriz de 13 sesiones, Coordinación con 7 leads y 5 tareas. Repetido después de actualizar expectativas y huella de potencial. No acredita HTTP/Auth. |
| `npm run test:edge-preflight` | PASS | 96 pruebas Node, 12 de moneda y 15 de push Deno. Ejecutado antes de integrar F3; este cambio no modifica Edge Functions. |
| SQL `prueba.sql` / `replay.sql` | PASS | 93 comprobaciones en PostgreSQL 17, roles authenticated reales, fixtures sintéticos y ROLLBACK. Reversa de las tres migraciones y reaplicación: mismas definiciones. Banco final sin contratos, equipo ni auditorías. |
| Variante previa a F3 | PASS | Aplicación, reversa y reaplicación más 87 comprobaciones de la versión anterior del banco. Las seis pruebas añadidas al final se ejecutaron en F3. |
| `concurrencia.py` | PASS | Dos conexiones reales: revocación de membresía y sello concurrentes. Espera bloqueo y rechaza sin categoría/auditoría parcial. |
| `sello.py` | PASS | `crm.cerrar_periodo` real, seis transiciones, conteos/foto/capital coherentes y dos eventos comerciales sintéticos incluidos. No sustituye reloj ni funciones del cierre. ROLLBACK. |
| `rendimiento.sql` | PASS | 3.000 contratos/operaciones adicionales: ranking 110,425 ms y conversión 7,265 ms, EXPLAIN ANALYZE local. No equivale a rendimiento en producción. |
| Advisors locales | PASS | 7 avisos preexistentes antes y después; 0 nuevos tras consolidar las policies SELECT. |
| Tipos | PASS | Generados desde el banco local; incorporada únicamente la nueva tabla de auditoría al archivo versionado, conservando el enum F3 remoto. |
| Preflight remoto de solo lectura | PASS | 29 funciones compatibles con las huellas admitidas y tres policies originales compatibles. No modifica producción ni sustituye el preflight al publicar. |
| Inspección visual | PASS | Modal y navegación comprobados en escritorio y móvil; controles de nueva inversión ausentes para Coordinación. |
| Matriz general `test-rls.mjs` por HTTP/Auth | NOT RUN | El banco ofrece PostgreSQL, sin Auth/PostgREST. Se actualizaron los oráculos afectados y se comprobó sintaxis/preflight; no se declara que la matriz completa pasó. |
| `gate:realidad` | NOT RUN | Falta entorno Supabase de ensayo con su configuración/credenciales. |
| Aplicación y publicación | NOT RUN | No se invocó el flujo humano `$release-crm` / `/release-crm`. |

## Qué acredita el banco SQL

Consulta global de Leads y cartera para Coordinación activa; filtros de equipo, buscador,
resumen, potencial, ficha y estados. Permite consultar sin ampliar UPDATE/INSERT, edición
de DNI/contactos, actividad, bancos, archivos, postventa ni creación de inversiones.

Las seis direcciones de cambio entre Nuevo/Renovación/Upgrade funcionan para los roles
solicitados. Admin/Superadmin, Gerencia y Coordinación autorizados; vendedor, supervisor,
Directorio, clientes y perfiles/membresías inactivos denegados. Motivo requerido, auditoría
inmutable, idempotencia y guardias de transacción, revocación y meses sellados ejercitados.

Se comprueban dinero, tasas, fechas, operador y relojes intactos; paridad histórica sin
corrección (incluidos demo y categoría NULL), conversión/ranking sin duplicar hechos,
plazo vencido, primer mes de Upgrade, identidad previamente acreditada y producto archivado.
No crea una operación financiera para corregir una clasificación comercial.

## Revisión y límites

Dos consultas independientes por `scripts/claude-review`, con Codex como único escritor.
El dictamen final fue **CHANGES_REQUESTED**; no se presenta como PASS del reviewer. El PRIMARY
corrigió los hallazgos aceptados y resolvió las hipótesis con evidencia. Ver [REVISION.md](REVISION.md).

El esquema de ensayo incluye F3 pero no se afirma que reproduzca todo producción. Antes de
aplicar quedan la matriz pertinente con Auth/PostgREST, el gate de realidad y los preflights
actualizados del flujo de publicación. Las 26 omisiones de Playwright no cuentan como pruebas
aprobadas. Las escrituras de ensayo fueron únicamente en bancos sintéticos locales.

Para repetir los ensayos y revisar la reversa protegida: [LEEME.md](LEEME.md).
