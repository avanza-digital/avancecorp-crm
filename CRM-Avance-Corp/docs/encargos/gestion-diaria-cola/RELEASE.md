# Gestión diaria — validación de release (30/09/2026)

Frontend integrado en Main con `avancecorp/main` (`350eb39e`) y con el commit
realmente publicado (`6600af0a163a`). La copia limpia conserva ambos historiales.
El trabajo ajeno del checkout original se mantiene sin cambios.

## Gates

- `npm run check`: PASS, 320 archivos y 4.945 pruebas; lint, tipos, cobertura y build.
- E2E completo en Docker: PASS, 289 aprobadas y 26 omitidas (11,1 minutos).
- `npm run check:scripts`: PASS sobre la copia integrada.
- Matriz remota de cola: PASS con 530 leads, escritor real, paginación, reintentos,
  deshacer y día de Lima. Roles PASS y diez denegaciones reales PASS.
- `test-rls.mjs --contratos`: PASS, 287 aserciones con sesiones Auth sintéticas.
- `assert_cola_v3` y `assert_sla_nucleo`: PASS.
- Tipos generados por CLI desde la rama remota: la firma de la nueva RPC coincide.
- EXPLAIN ANALYZE remoto con 530 leads sintéticos: 228,075 ms de ejecución
  (no se presenta como una medición con datos de producción).

## Banco remoto

Rama autorizada `gestion-diaria-cola-20260930`, referencia `mnqyfcqrhcqerwjzwnpp`.
El replay histórico de Supabase falló antes de la candidata. Se reconstruyó
exclusivamente este banco con el esquema actual y fixtures sintéticos. Catálogo
completo, dueños, ACL, políticas, triggers e índices iguales a producción antes
de la candidata; 398 migraciones previas con contenido idéntico y 22 Edge Functions
con los mismos paquetes y verificación JWT.

La candidata quedó registrada por Supabase como `20260930190028`; el archivo local
adopta esa versión. El SQL coincide con la candidata local `20260930160812` ya
ensayada. Sólo se agregan tres funciones; ninguna función anterior cambia.
`RAMA.json` conserva las huellas y el alcance.

El primer ejecutor remoto agrupaba todo el ensayo en un único statement, fijando
`statement_timestamp()` antes de los eventos escritos. Se corrigió el ejecutor para
usar sentencias independientes como psql local y las peticiones HTTP reales. Los
ensayos finales pasaron sin modificar el SQL del producto ni sus aserciones.

Advisors: el único aviso nuevo de seguridad es el esperado para la RPC DEFINER
accesible a authenticated. Es la puerta intencionada; exige sesión, rol operativo
y ámbito propio, comprobados en la matriz. No se habilitan ayudantes privados,
anon ni service_role. Referencia: https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable
Los demás avisos de seguridad son previos; rendimiento no señala los objetos nuevos.

## Gate de realidad

El gate HTTP general conservó dos fallos de medición: lectura de `periodos_cerrados`
denegada a service_role y timeout de conciliación. Se completaron los mismos
oráculos por SQL de sólo lectura: cero revisiones fuera de sello y cinco caminos
de conversión concordantes (divisor 1.655, numerador 115,15, 6,96 %). No se cambiaron
permisos para hacer pasar el script. Se conserva el aviso previo de domicilios.

## Publicación

Migración promovida mediante `merge_branch` y verificada en producción:
399 migraciones, última `20260930190028`; catálogo completo idéntico al banco
validado y 22 Edge Functions sin cambios de paquete ni verificación JWT.
Lectura productiva con rol authenticated: ocho filas de 111 en la cola personal,
día 2026-09-30, sin escrituras de prueba. Banco temporal eliminado al terminar.

Frontend pendiente de empaquetar/publicar desde el commit de esta evidencia.
