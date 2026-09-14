# Verificación local — 14/09/2026, sin deploy

> Registro histórico del ensayo local. La pausa fue sustituida por la autorización
> posterior y la publicación del 14/09. Los NOT RUN de esta nota describen aquel
> corte; el alcance vigente está en [PUBLICACION-2026-09-14.md](PUBLICACION-2026-09-14.md).

Implementación y correcciones verificadas en local. Miguel indicó «todavia no
hagas deploy». Se conserva la candidata; **no se declara completado el ciclo
de validación/publicación remoto**.

## Resultados del PRIMARY

| Estado | Verificación y alcance |
| --- | --- |
| PASS | `npm run check` tras integrar Main: 244 archivos, 3.540 pruebas; lint, TypeScript, cobertura, configuración de release, service worker, build, bundle y duplicación. |
| PASS | Playwright completo: 182 aprobados, 26 omitidos preexistentes. Tres nuevos: lead→conversión→contrato a 12,5 % en 1440/390 px y cliente existente→contrato/cronograma a 13,5 %. Capturas inspeccionadas. |
| PASS | Siete E2E de tasas repetidos tras el bloqueo de preselección. Los dos casos posteriores de mensaje carga/error pasan en el gate integral final. |
| PASS | `check:scripts`, seed/RLS preflight offline con valores ficticios y `test:edge-preflight`. Los 14 casos de tasa en VM ejecutan el handler TS real con dobles. |
| PASS | Banco PostgreSQL: instalación, paridad owner/ACL/DEFINER/search_path de cuatro funciones, reversa exacta y reinstalación. |
| PASS | Regresiones de solicitudes pendientes/lead con base 15 y variantes a 12,5; petición concurrente bloquea la reserva inferior. |
| PASS | Altas SQL como analista authenticated: 0,01; 1; 12; 12,5; 13,99; 14,99; 15. Persistencia exacta mediante puerta con PDF y lectura RLS propia. |
| PASS | Rechazo de >base sin aprobación, cero/negativos, 12,345; 0,011; 14,999 antes del redondeo de numeric(5,2), sin contrato parcial. |
| PASS | Ledger con base/tasa/actor sin petición artificial, helper privado, identidad, herencia, PDF congelado y correcciones conservadoras. |
| PASS | Cadena SQL reserva ON→sellado→conversión→contrato a 12,5. Auth/perfil son fixtures locales, sin correos. |
| PASS | Reversa bloqueada con reserva sellada sin contrato, reserva activa OFF concurrente y tras contrato; cuerpos intactos. Reaplicación rechazada por huella. |
| PASS | Carrera inversa: reversa obtiene candados primero; reserva authenticated espera y rechaza 12,5 con P0410 tras restaurar el mínimo anterior. |
| PASS | Lectura productiva: cuatro huellas originales coinciden y helper ausente; inventario de INSERT, RLS y borradores de reservas guardado. Sin escrituras. |
| NOT RUN | Candidata en rama remota, replay desde cero, matriz general Auth/PostgREST de 13 roles y advisors de candidata instalada. Falta completar el ciclo autorizado del destino. |
| NOT RUN | Smoke productivo, Auth/correos reales y publicación. Los E2E con backend simulado no equivalen a integración HTTP productiva. |

No se regeneró `database.types.ts`: no cambian tablas ni firmas RPC expuestas,
solo un helper privado y un campo JSONB. Su interfaz/parser manual se actualizan
en `crm-api.ts` con cobertura MSW. No se tocan tipos pendientes de Citas.

## Evaluación de las dos revisiones de Claude

LEVEL 3 por regla financiera y funciones SQL. Los dos dictámenes originales son
`CHANGES_REQUESTED`, sin P0/P1. No se pidió una tercera confirmación. Codex resolvió
y verificó los hallazgos con evidencia:

1. **Precisión (P2, aceptado).** numeric(5,2) redondea antes del trigger. Se valida
   el JSON en `public.crear_contrato` antes del INSERT, con cuarta huella cotejada
   en producción y tres valores inválidos probados desde la puerta PDF autenticada.
2. **Preselección (P2, aceptado).** Bloqueo por ambos extremos, persistente aunque
   otro estado escriba la tasa. Pruebas de cambio de base, autorización insuficiente
   y escritura externa; se conserva la tasa acordada.
3. **Reversa sin contrato (P2, aceptado).** Guarda condiciones inferiores de reservas
   activas/selladas o leads convertidos, además del ledger. Ensayo sellado ON sin
   contrato y activo OFF con dos sesiones.
4. **Otras puertas (P2, evidencia).** Edge transmite condiciones a SQL con ambas
   banderas. Casos positivos 12,5 en deduplicación OFF y ya_existia ON; pendientes
   rechazan antes de efectos. Auth externo nuevo no está probado; sí la cadena
   completa SQL con fixtures.
5. **Carrera de reversa (P2, hipótesis tratada).** ACCESS EXCLUSIVE incluye leads
   y drena las lecturas previas a validar. Dos sesiones observan bloqueo real en
   ambas órdenes. No se aceptó apagar banderas de negocio: no hace falta y afecta
   otros flujos. Cuerpos intactos si la reversa se rechaza.
6. **Mensaje carga/error (P3, aceptado).** El estado de consulta tiene prioridad:
   17 % con carga/error no ordena cerrar por una supuesta incompatibilidad. Dos
   pruebas y gate final PASS. La tasa superior ofrece revisar o pedir aprobación.
7. **INSERT directo (P3, hipótesis acotada).** El inventario literal de pg_proc solo
   encuentra crear_contrato. Aunque existe GRANT INSERT, RLS está habilitada y la
   única policy INSERT exige es_admin(): perfil activo admin/superadmin. El analista
   no obtiene acceso directo. Los INSERT del fixture propietario no son una puerta
   del analista. Importaciones privilegiadas/SQL de administrador quedan fuera del
   cambio, sin ampliar permisos.
8. **Borrados de reservas (riesgo revisado).** No hay comandos cron que mencionen
   conversion_reservas. La función de borrado encontrada exige Gerencia y una
   conversión abandonable, sin Auth/ficha ni lead convertido. Edge usa RPC.
   No demuestra ausencia universal de SQL dinámico externo; repetir el preflight
   operativo antes de publicar. Evidencia en rutas-vivas-y-rls.json.

Decisiones P3: «Tasa acordada» es correcta también a 15 %; 0,01 representa precisión
positiva, no una política comercial nueva; demo→real y correcciones permanecen
conservadores. El mensaje heredado de una corrección rechazada puede mejorarse
después sin ampliar permisos. El informe distingue «Fuera de la base» y cesión/
retención, sin acusar falta de aprobación.

## Evidencia y retoma

`evidencias-local.json` contiene ejecuciones y rechazos esperados. Las bases
aleatorias se eliminan en finally; el contenedor/template compartidos permanecen.
El paquete y logs finales se respaldan fuera del web root en
`CRM-Avance-Corp/releases/tasas-inferiores-20260914/` del workspace principal.
El código está en el clone aislado `/private/tmp/avancecorp-tasas-bajas-20260913`
y su respaldo duradero, sin incorporar trabajo sin commit de Citas del original.

Se integró sin conflictos `avancecorp/main` en `5ec99db` (ajuste de Facturación y
su nota). El gate frontend integral se repitió después de esa integración. El
commit de preparación queda local: antes de publicar debe sincronizarse el commit
exacto con Main remoto y reconstruirse si hay cambios posteriores.

Antes de publicar: ciclo del banco remoto, controles pendientes, integración de
Main con avancecorp/main, huellas actuales y build desde el commit sincronizado.
No ejecutar db push general. Receta: [README.md](README.md).
