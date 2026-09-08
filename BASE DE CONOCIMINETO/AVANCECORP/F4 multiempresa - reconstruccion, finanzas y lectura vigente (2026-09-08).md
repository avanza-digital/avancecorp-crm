# F4 — reconstrucción, finanzas y lectura vigente

Miguel pidió terminar F4 y guardar commits. Codex es PRIMARY; Claude revisó
sin herramientas ni escritura. Trabajo en `/private/tmp/avancecorp-f4-desarrollo`,
rama `codex/f4-cierre`, preservando cambios ajenos del checkout principal.

La candidata completa tiene 48 funciones (18 adaptadas, 30 nuevas), 11 módulos
y siete tablas. Se reconstruyó un segundo banco Supabase independiente
`avancecorp-f4-reconstruccion` (API 57321, PG 57322) desde esquema del 07/09 sin
filas reales. Auth/RPC ficticios antes de instalar; paridad: cuatro contratos,
dos cierres, 52 cuotas, PEN 8000. Corpus original F2: 12 grupos; finanzas: 13;
cotitulares: 16; corrección versionada: 20; permisos: 19; multirrol: 12.

F2 global queda bloqueada 55000 desde instalar F4, incluso apagada. Censo/lote
cerrado sustituye mantenimiento global. El inventario mecánico clasifica 26
consumidores directos, 18 escritores y 97 transitivos entre 546 funciones; la
migración compara las 20 referencias previas y rechaza deriva antes del DDL.

Se corrigieron dos defectos reproducidos: el asesor histórico veía teléfono
vivo tras trasladar la relación, y el parser frontend rechazaba una inversión
sin lead. El teléfono sigue al responsable canónico actual; sin responsable no
se inventa permiso. La pantalla conserva historial y admite fechas comerciales
F4, sin afirmar que toda persona de cooperativa carece de Portal.

Portal ahora limita cuerpo durante su lectura, usa los orígenes publicados y
oculta errores internos conservando token/solicitud. Ocho tests de transporte,
regresiones Auth/Portal/veto/HTTP real y ambas reservas reales de diez minutos
PASS. El PDF muestra el motivo público al impedir borrar una fuente vinculada;
no se tocó plantilla, texto contractual, firma, fondo, fuentes ni renderer.

El ensayo PDF cb86e1fd falló por WORKER_LIMIT tras nueve grupos y se conserva
como FAIL. Tras vencer leases reales y reiniciar solo el runtime local con
per_worker predeterminado, se recuperaron los pendientes. Readback de diez jobs:
mismo snapshot, una fuente/inversión/objeto y bytes verificados. La tanda nueva
56c6b388 pasó 12 grupos/10 contratos; 14 páginas PEN/USD inspeccionadas. No se
certifica carga productiva ni se atribuye una causa raíz definitiva al límite CPU.

Restauración pareada PASS: 133 tablas y 27 archivos hacia DB/volumen nuevos,
seis grupos, datos/cuerpos/privilegios/RLS/bytes iguales. Normalización de ACL
owner explícita vs predeterminada evitó un falso negativo del primer oráculo;
no se cambiaron grants. Se omiten cron/replicación y no se afirma tercera pila HTTP.
La reversa operativa apaga F4 y conserva toda la historia, no borra el modelo.

Verificación: 3050 tests frontend PASS con dos workers, lint/typecheck/build/
bundle/duplicados, cuatro gates backend, 43 tests PDF Deno y 17 nodos de tipos
antes/después sin borrar tipos ajenos. La tanda frontend inicial a máxima
concurrencia tuvo timeouts; se conserva ese antecedente. Claude emitió
CHANGES_REQUESTED; Codex contrastó cada observación, corrigió las confirmadas
y documentó las refutadas. No hubo otra revisión después de los ajustes.

**Actualización posterior — G4 cerrado:** Miguel confirmó que las comisiones se
calculan fuera del sistema y no quiere ese módulo. Se retira el único pendiente
externo del alcance de F4; no se afirma haber verificado pagos. Decisión vigente:
[[F4 cerrada - comisiones fuera del sistema (2026-09-08)]]. El resto de la evidencia técnica se conserva.

La candidata queda versionada como preparada, no aplicada. No hubo push,
publicación ni cambio de banderas productivas. 14 resueltos + 1 faltante sigue
siendo el censo observado el 07/09 11:32; no es un dato productivo actualizado.

Detalle y evidencia: [matriz F4](../../CRM-Avance-Corp/supabase/scripts/f4/ESTADO-ACEPTACION.md),
[reconstrucción/restauración](../../CRM-Avance-Corp/supabase/scripts/f4/RECONSTRUCCION-Y-RESTAURACION.md).
Relacionadas: [[F4 multiempresa - cotitulares y correccion versionada (2026-09-08)]],
[[F4 multiempresa - historicos recuperables y commits (2026-09-08)]],
[[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]].
