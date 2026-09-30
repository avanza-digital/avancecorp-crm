# Gestion Diaria - vuelta persistente verificada localmente (2026-09-30)

Estado actualizado: migración validada en rama remota y aplicada a producción
por merge_branch; frontend pendiente de empaquetar/publicar. Banco eliminado.
Evidencia vigente: `CRM-Avance-Corp/docs/encargos/gestion-diaria-cola/RELEASE.md`.

Miguel reportó que un lead al que llamó sin respuesta seguía delante y le obligaba
a buscar dónde iba. Al guardar un resultado confirmado, el lead pasa al final de
la cola completa y «Ahora» propone el siguiente pendiente, incluso entre páginas.
Se muestra resultado y hora; al acabar la vuelta se permite revisar, sin volver
a iniciar llamadas automáticamente.

El avance sale de actividades tipificadas vigentes del día de Lima, autor,
tenencia y ciclo. No existe una marca de gestión paralela. Deshacer recalcula el
avance; una reasignación no hereda la gestión de otro responsable; una próxima
acción posterior a la llamada reactiva el turno a su hora. El grupo del trabajo
terminado conserva el motivo de entrada de su primera gestión del día.

La nueva RPC `crm.gestion_diaria_cola_trabajo_fn` ordena antes de paginar y
devuelve conteos, ancla por clave, siguiente pendiente y próximo cambio.
Es exclusiva del vendedor/supervisor autenticado sobre su cartera propia.
Dos helpers privados INVOKER, sin EXECUTE API; puerta DEFINER con search_path
vacío y actor de auth.uid(). La cola anterior y el núcleo SLA no se modifican.
Las tareas de clientes conservan sus claves distintas por tarea y responsable.

El navegador guarda sólo navegación por actor/día. Una sesión de llamada fija
persona y tarea hasta guardar/cancelar. Tras guardar empieza una consulta nueva
sin reutilizar lecturas anteriores; los leads no quedan ocultos por máscaras
locales. La selección con teclado y el avance conservan el foco.

Verificación: gate frontend PASS (320 archivos, 4945 tests, tipos/lint/build);
E2E Docker 289 passed y 26 skipped, más flujo dirigido final PASS con latencia y
teclado. Banco SQL aislado: 530 leads, escritor real v4, reintentos, Lima,
deshacer, reasignación real, clientes y denegaciones. Dos revisiones Claude
atendidas y decisiones del PRIMARY documentadas. Sin publicación.

Limitación para el release: el gate general de realidad tuvo dos mediciones
fallidas ajenas al cambio (periodos_cerrados sin permiso de lectura y timeout de
conciliación). El flujo humano `$release-crm` debe resolver sus preflights,
verificar rama remota/advisors y publicar desde el commit vigente verificado.

Evidencia: `CRM-Avance-Corp/docs/encargos/gestion-diaria-cola/VERIFICACION.md`.
Migración: `20260930190028_crm_gestion_diaria_cola_trabajo.sql`.
Ensayo: `CRM-Avance-Corp/supabase/scripts/gestion-diaria-cola/ensayar.mjs`;
su README documenta bootstrap sintético, matriz, alcance y reversa.

Relacionadas: [[Gestion Diaria F2 - resultado tipificado de llamada (2026-09-20)]],
[[Gestion Diaria F3 - el dia del analista (2026-09-20)]],
[[Gestion Diaria - cola completa F6 preparada (2026-09-24)]],
[[Cola del dia con clientes - plan (2026-09-28)]].
