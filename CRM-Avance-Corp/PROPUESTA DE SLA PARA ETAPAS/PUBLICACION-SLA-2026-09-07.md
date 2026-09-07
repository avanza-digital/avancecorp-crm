# Publicación del núcleo SLA y cola paginada

Autorización de Miguel: «haz los filtros de paginación, evitemos scrolls infinitos, y ya saquemos esto a producción» (06/09/2026, Lima). Las reglas aprobadas se conservan. No se exige un día de observación antes de activar.

## Comportamiento entregable

- Cola de trabajo con 10 registros iniciales; tamaños 10/25/50, Anterior y Siguiente. Filtros por señal, etapa y analista dentro del ámbito autorizado. Los totales abarcan la población completa; las señales se pueden solapar.
- Estado SLA en la ficha; configuración y modo servidos por el mismo núcleo del servidor.
- Actividad, cierre y reprogramación con recibos transaccionales. Un reintento conserva la operación original. El formulario espera la confirmación antes de anunciar éxito. Contacto y siguiente tarea se guardan juntos.
- Los plazos de episodios existentes se conservan. La primera activación fija el inicio del seguimiento y la política de adopción para sus topes. No hay prórrogas retrospectivas ni descarte o reasignación automáticos.

## Orden de instalación

1. Terminar las pruebas e integrar la implementación en Main, incorporando cambios remotos sin sobrescribirlos. Verificar que Main y `avancecorp/main` apuntan al mismo commit y construir desde ese commit en un checkout limpio. Preservar cambios locales ajenos a SLA; no crear ramas de release ni forzar el push. Verificar el ZIP, su manifiesto, proyecto Supabase y ascendencia respecto al release vivo; conservar el ZIP anterior. **El artefacto verificable debe existir antes de modificar la base.**
2. Releer las huellas del esquema vigente. Aplicar el prerrequisito `20260907032338_crm_sla_prerrequisito_gobernanza.sql` y comprobar los cuatro controles de gobernanza. Reparar solo las causas demostradas; no omitir controles ni elevar topes.
3. Aplicar N1 `20260907001024_crm_sla_nucleo_operativo_lectura.sql`, N2 `20260907024903_crm_sla_nucleo_operativo_escritura.sql` y N3 `20260907025220_crm_sla_comandos_recibos.sql`, en ese orden. Leer cada postflight antes de continuar. El modo sigue en `legado`, revisión 0, primera activación y adopción null; estas migraciones no publican reglas ni activan. La interfaz previa continúa operativa.
4. Reconstruir únicamente contextos demostrables de tareas pendientes mediante `private.sla_reconstruir_contextos_lote`, con hasta 200 leads y commit independiente por lote. Establecer `lock_timeout=5s` y `statement_timeout=30s` fuera de la función. Guardar cobertura y motivos ambiguos fuera del repositorio, compararlos con el contraste y revisar cambios reales de cartera. No inventar episodios, autores ni fechas ni cancelar tareas. Un timeout revierte ese lote y exige revisar la causa.
5. Aplicar N4, `20260907031450_crm_sla_cierre_reconstruccion_contextos.sql`, solo después de guardar y revisar los lotes. Retira los helpers transitorios, conserva contextos/captura y comprueba el núcleo.
6. Desplegar el artefacto ya construido exclusivamente en `crm.miavance.com`. Verificar manifiesto, commit y archivos servidos; comprobar las pantallas con las RPC instaladas y el modo todavía en legado. Agenda conserva su consulta actual; la paginación nueva corresponde a la cola operativa y a las confirmaciones pendientes.
7. Desde una sesión real de **Gerencia**, revisar el resumen servido en Configuración y ejecutar `crm.publicar_reglas_sla_aprobadas_v2` con `expected_version` recién leído. No suplantar `auth.uid()` en SQL. La puerta exige última política vigente sin anexo, publica las cuatro reglas de forma atómica y preserva la primera gestión/contacto vigentes. Releer el resultado. No cambia el modo.
8. Activar desde esa sesión con la revisión vigente del control. Releer política, primera activación y adopción; comprobar las pantallas, la cola y los controles de integridad. Registrar los resultados exactos de instalación, artefacto y activación.

El orden de esta entrega es explícito, no el orden lexicográfico de los archivos: **prerrequisito → N1 → N2 → N3 → lotes → N4 → frontend → publicación de reglas → activación**. No aplicar todas las migraciones ciegamente en una sola pasada.

La foto del contraste tenía política v5 con bases 1/8/15/20 días, primera gestión de 120 minutos y primer contacto de 1440. Si esa versión sigue vigente al publicar, el bootstrap creará v6 y el control seguirá en revisión 0; activar lo llevará a revisión 1 y fijará la adopción de v6. Son expectativas verificables, no valores para forzar: una publicación concurrente o futura debe detener la operación mediante sus controles, y obliga a releer.

## Reglas comerciales aprobadas

| Etapa | Seguimiento | Base / tope | Prórroga por conversación | Margen de compromiso |
|---|---:|---:|---:|---:|
| Nuevo | 1 día | 1 / 3 días | Ninguna | 4 horas |
| Contactado | 3 días | 8 / 16 días | 4 días, máximo 2 | 1 día |
| Reunión agendada | 3 días | 15 / 18 días | Ninguna | 2 días |
| Propuesta enviada | 5 días | 20 / 27 días | 7 días, máximo 1 | 1 día |

Reloj corrido. La conversación debe ocurrir en las últimas 24 horas del plazo aplicable y conservar el mismo episodio antes y después del gesto completo. Una tarea pendiente puede cubrir el seguimiento, limitada por su fecha más el margen y por el tope de etapa. Tres reprogramaciones eliminan esa cobertura. Tercer ingreso en la misma etapa/ciclo o vencimiento operativo requieren revisión.

## Estado de validación

Documento de trabajo: aún no acredita publicación. Las evidencias de instalación, activación, commit y artefacto se añadirán después de ejecutarlas.

N2: 23/23 pruebas en banco integral PG17 con funciones, permisos y controles reales; 7,145 s de casos, 8,014 s incluyendo preparación. Incluye concurrencia de publicación y gestión, apagado, reconstrucción idempotente, falta de evidencia, cierre y contingencia. Detalles y alcance en [runbook N2](../supabase/tests/sla-operacion/README.md). Las pruebas de N1, N3 y prerrequisito se registran en sus artefactos de evidencia y en [MIGRACIONES.md](../supabase/migrations/MIGRACIONES.md); una prueba local no acredita uso en producción.

Validación final previa a integrar: N1 47/47, N3 21/21 en instalación fresca (6,296 s), prerrequisito con reversa/reaplicación exactas y cuatro controles verdes sin elevar topes. Frontend: 2895 pruebas en 201 archivos (15,51 s), typecheck correcto y lint sin errores, con cuatro advertencias preexistentes. [Evidencia integral y SHA-256 de los cinco SQL](../supabase/tests/sla-integracion/evidencia-20260907.json). El banco no ejecuta PostgREST, Auth HTTP ni scheduler: el smoke posterior debe comprobar el servicio real. La carrera específica de adquisición de ámbito v1 se cierra con el invariante de bloqueo y huella; no se afirma haber forzado determinísticamente esa intercalación. `npm run gate:sla:produccion` verifica los siete controles y el cierre de los helpers de reconstrucción.

El contraste previo está en [CONTRASTE-CARTERA-2026-09-06.md](CONTRASTE-CARTERA-2026-09-06.md). El contrato técnico está en [CONTRATO-V2.md](auditoria-r2/CONTRATO-V2.md).

## Recuperación

Si la interfaz presenta una regresión, volver al ZIP anterior conservado. Para suspender las señales operativas, usar la puerta de configuración para volver a `legado` con la revisión vigente; esta acción conserva la primera activación, las políticas y los recibos. No borrar el historial, reescribir plazos ni retirar los comandos mientras el frontend publicado los utilice.

Si falla un hook estructural y el modo no basta, la contingencia ensayada [rollback-sla-operacion-hooks.sql](../supabase/scripts/rollback-sla-operacion-hooks.sql) exige legado y retira solo captura/adjudicación, conservando avance automático, autorización, clocks, locks fuertes y las firmas que invocan N3/v1. El gate bloquea reactivar mientras falten esos hooks. Registrar el intervalo sin captura: la recuperación requiere una migración revisada y reconstrucción/verificación de ese intervalo. Los presupuestos consumidos y la primera activación permanecen. La reversa del prerrequisito es distinta: restaura las definiciones previas y sus cuatro controles rojos conocidos; se reserva para una reversa completa revisada, no para apagar SLA.

Una respuesta de red perdida se recupera desde la lista de confirmaciones pendientes: reenvía la misma operación y payload. No crear otro UUID para conseguir un segundo efecto. La memoria del navegador es por actor y pestaña; cerrar sesión o perder ese almacenamiento requiere revisar el historial antes de volver a registrar.
