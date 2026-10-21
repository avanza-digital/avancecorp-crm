**VERDICT: CHANGES_REQUESTED**

**SUMMARY:** El orden SQL y el cursor compuesto son coherentes para una población estable. No identifico una nueva fuga de autorización en el código mostrado. Los problemas principales están en la compatibilidad de sesiones durante la publicación y la reversa; también hay una laguna concreta en las pruebas del cursor.

**FINDINGS**

**[P1] Revertir el front no retira los bundles v3 que siguen abiertos.**

Evidencia: [reversa.sql](/Users/usuario/dev/avancecorp-crm-orden-pendientes-20261020/CRM-Avance-Corp/supabase/scripts/pendientes-recientes-20261020/reversa.sql) exige revertir primero el front y después ejecuta `drop function crm.gestion_diaria_pendientes_v3_fn(...)`. El nuevo `gestion-diaria-pendientes-api.ts` llama exclusivamente a esa puerta.

Una pestaña que haya cargado el bundle nuevo conserva esa llamada después de republicar el front anterior. Cuando consulte nuevamente, recibirá `PGRST202`. La secuencia documentada no acredita que esas sesiones hayan dejado de utilizar v3.

**Propuesta:** separar la reversión del front de la retirada definitiva de v3/core6. Conservarlos hasta retirar o recargar efectivamente las sesiones nuevas. Probar la reversa manteniendo abierta una pestaña con el bundle v3.

**[P2] La cola cambia de orden sin versionar y puede mezclar paginaciones durante la migración.**

Evidencia: la [migración](/Users/usuario/dev/avancecorp-crm-orden-pendientes-20261020/CRM-Avance-Corp/supabase/migrations/20261020214445_crm_gestion_diaria_pendientes_recientes_primero.sql) reemplaza `crm.gestion_diaria_cola_trabajo_fn`, conserva `'version',1` y pagina mediante `f.n>v_pagina*p_limite`. Con `p_elegido=NULL`, no existe ancla que compense el cambio.

Caso reproducible con cuatro pendientes del mismo grupo:

- Antes de migrar: orden `A,B,C,D`; página 0, límite 2 → `A,B`.
- Después de migrar: orden `D,C,B,A`; página 1 → `B,A`.

El recorrido repite dos filas y omite otras dos. La protección mediante v2/v3 cubre Pendientes del supervisor, pero no esta cola.

**Propuesta:** versionar también la puerta de la cola y conservar el contrato anterior para los bundles publicados, conforme a la regla arquitectónica indicada. Añadir una prueba de convivencia de ambos consumidores.

**[P2] El empate documentado no es un empate y ninguno de los recorridos corta el empate real.**

Evidencia: en [prueba-banco.sql](/Users/usuario/dev/avancecorp-crm-orden-pendientes-20261020/CRM-Avance-Corp/supabase/scripts/pendientes-recientes-20261020/prueba-banco.sql), la siembra asigna `now() + make_interval(hours => i - 15)` a los IDs 21 y 22: vencen dentro de seis y siete horas. Comprobar que 22 precede inmediatamente a 21 no prueba el desempate por ID.

El empate real está en 24 y 25, ambos a `now() - interval '30 hours'`. Quedan juntos en la última página tanto con límite 7 como con límite 5. `estricta` sí verifica su orden dentro de la página, pero no se ejercita el cursor entre filas de igual fecha.

**Propuesta:** comprobar explícitamente la igualdad de fechas de 24/25 y dividirlos entre páginas, por ejemplo con límite 24 en «Todas». Verificar que la segunda página devuelve exactamente la fila restante. Un mutante que elimine el ID de la condición del cursor debe fallar.

**[P3] La garantía de reversa exacta no incluye una línea base de los comentarios.**

Evidencia: el preflight compara `md5(pg_get_functiondef(...))`, dueño y ACL. Esa huella no incluye `COMMENT ON`. La reversa restaura comentarios históricos y comprueba el del núcleo contra un literal, sin haber comprobado que ese literal fuera el comentario vivo anterior.

Si únicamente hubiese cambiado un comentario en producción, las huellas seguirían coincidiendo y la reversa sobrescribiría ese cambio. Esto demuestra una garantía incompleta; no demuestra que el banco observado haya quedado diferente.

**Propuesta:** medir y validar los comentarios originales de núcleo y cola antes de migrar, y comprobar ambos después de revertir.

**RIESGOS / TEST GAPS**

- **La prueba de reprogramación no representa una segunda página válida.** En `gestion-diaria-pendientes.test.ts`, la tarea pasa del 23 al 25 de septiembre y se introduce en la página posterior. Con el cursor descendente, esa tarea quedaría antes del cursor y el servidor no la devolvería allí. El test acredita la unión aislada, no la recuperación de una reprogramación durante el recorrido. Además, `statement_timestamp()` cambia entre peticiones: una tarea recién vencida puede incorporarse por delante del cursor. Hace falta acreditar cómo se reinicia o refresca la lista ante esos cambios.
- **Hipótesis de concurrencia pendiente:** la migración indica que la resolución de identidad bloquea filas. v2 y v3 entregan las mismas tareas en órdenes opuestos. Si los ayudantes adquieren bloqueos incompatibles siguiendo ese orden, podrían producirse interbloqueos. Sus cuerpos no están transcritos: verificar un orden canónico de bloqueo independiente del orden recibido.
- **Verificación aportada:** PASS informado para banco, ciclo de reversa y 207 tests. H3 continúa en FAIL por la causa preexistente descrita. `npm run check` y los cuatro E2E siguen en curso; no se aporta resultado de la matriz RLS modificada. Ejecución independiente por este revisor: **NOT RUN**, conforme al encargo sin herramientas.

**NEXT ACTIONS**

1. Resolver la convivencia de versiones de la cola y la retirada segura de v3 durante la reversa.
2. Corregir la prueba de empate entre páginas y completar la comprobación de comentarios originales.
3. Cerrar los checks pendientes y ejecutar la matriz RLS exigiendo v3 mediante `CRM_RLS_EXIGE_GESTION_DIARIA=1`.

**CONFIDENCE: MEDIUM.** Los hallazgos se derivan del material transcrito; los bloqueos de identidad y los mecanismos globales de actualización de sesiones requieren evidencia adicional.
