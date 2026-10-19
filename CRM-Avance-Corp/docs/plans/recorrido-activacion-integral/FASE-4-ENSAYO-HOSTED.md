# Fase 4 — Ensayo en Supabase

**PASS, 6/6 subfases. Producción sin instalar ni activar.** Rama exclusiva `recorrido-integral-20261019`, ref `zwnecxkwsxzybefmdrut`, creada con autorización de gasto hasta 24 horas. Eliminar antes del 20/10/2026 a las 06:29 UTC, o al terminar si ocurre antes.

## Instalación y paridad

El replay automático se detuvo en 86/509 migraciones por el postflight histórico que requiere un miembro real de `crm.equipo`. Se recuperó la rama con el procedimiento de paridad manual elegido previamente por Miguel, sin alterar migraciones históricas ni copiar clientes. No se declara que el replay vacío haya pasado; la etiqueta `MIGRATIONS_FAILED` conserva ese fallo histórico.

Se capturó el esquema vigente, se restauró exclusivamente en la rama vacía y se verificaron 1.168 funciones, 161 relaciones, permisos de 62 columnas, roles, membresías, policies Storage, triggers Auth, permisos por defecto y publicaciones. Se corrigieron los permisos adicionales que heredaba la rama y los comentarios que el volcado había quitado de dos funciones. Solo quedan tres diferencias de paréntesis en CHECK de conjunciones AND: mismas condiciones, tipos y validación. PostgreSQL del banco es 17.11 y producción 17.6; pg_net conserva la versión administrada de cada plataforma. Ningún cron queda activo en la rama.

Después de acreditar paridad se restauraron allí las 509 filas exactas del historial. Huella de esa base: `8fe3fd28649301bac91ed91973d1dc8c`. No se ejecutaron sus backfills históricos. Se aplicaron mediante la CLI las 13 migraciones candidatas del manifiesto: historial final 522, base anterior intacta. La instalación dejó el control en observación, revisión 1 y fecha NULL, antes de los ensayos.

Las 24 Edge Functions coinciden por hash y configuración con producción; el candidato no modifica ninguna. El catálogo final tiene 12 funciones nuevas y cinco cuerpos anteriores modificados, sin cambios de propietarios ni ACL previas. Las dos tablas nuevas y los triggers/columna de evidencia son los previstos. Esquema `public`, Storage, Auth y núcleo SLA conservados.

## Pruebas y correcciones

- **SQL hosted PASS:** atención de oficina, permisos, atomicidad; borrador antiguo bloqueado sin perder datos, evidencia anterior válida, confirmación y reintento único; inicio futuro coherente con el servidor. El fixture de ciclo corrupto requiere superusuario: ese caso no se ejecutó hosted y conserva su PASS local. El SQL exacto del subconjunto remoto está adjunto.
- **HTTP/Auth/RLS hosted: 81 PASS**, 123 peticiones. JWT emitidos por Auth real y llamadas a PostgREST real. Misma matriz versionada que el banco local; el handler oficial de acceso al portal se ejecutó en proceso contra ambos servicios remotos, sin redesplegar Edge. Actores, leads, comprobantes y conversiones exclusivamente ficticios.
- **Hallazgo corregido:** dos intentos de la matriz quedaron esperando el conflicto de revisión del control. El `40001` intencional desencadenaba el bucle de reintentos de PostgREST 14. Se conservaron los diagnósticos, se detuvieron solo los backends de ese ensayo y se añadieron 61003/61004 para responder `PT409`. El ensayo final devolvió **HTTP 409 en 170 ms**, sin sobrescribir el control. [Causa documentada por Supabase](https://supabase.com/docs/guides/troubleshooting/high-cpu-and-infinite-transaction-retries-when-using-custom-error-codes-in-rpc-functions-77326b).
- **Regresión local final PASS:** evaluación SQL, replay de las correcciones y hardening, carreras financieras y matriz HTTP 81/81; `check:scripts` PASS. Los 42 E2E Docker de fase 3 siguen siendo la evidencia de interfaz; no hubo cambios de frontend.
- **Reversión hosted PASS:** observación, apagado y regreso a exigencia conservan la fecha inmutable y el comportamiento esperado del servidor. ROLLBACK deja idénticas las huellas del control, evidencia y confirmaciones.

## Advisors y revisión Codex

No se omiten avisos. Los nuevos avisos fueron revisados contra el baseline productivo y las pruebas:

- Dos tablas con RLS sin policies: cierre deliberado de acceso directo; solo RPC autorizadas. Matriz de anon, service_role, analistas, supervisores, gerencia, coordinación, directorio y membresías inactivas PASS. [Regla del advisor](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy).
- Tres RPC SECURITY DEFINER accesibles a authenticated: exposición deliberada con ámbito y rol comprobados, search_path vacío y helpers privados. Ninguna nueva RPC anónima. [Regla del advisor](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).
- FK de la cita sin índice: corregida por 61002; el aviso desapareció. La FK de `recorrido_control.actualizado_por` no lleva índice adicional porque el control admite una sola fila. [Regla del advisor](https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys).
- El índice recién creado figura todavía sin uso en este banco pequeño. Los demás avisos son previos, incluyendo la configuración Auth de contraseñas filtradas; no se modificó configuración externa ajena al candidato.

Codex verificó alcance, catálogo, permisos, triggers activos, historial, reversión y ausencia de procesos del control atascados. Los hallazgos del ensayo quedaron corregidos y revalidados antes de abrir la fase 5. La revisión independiente de Claude pertenece a esa fase y no se presume aprobada.

## Evidencia

Archivos `evidencia/fase4-*`: paridad base, rama, manifiesto de 13 SQL, postflight, matriz HTTP, SQL remoto, diagnóstico/latencia del conflicto, reversión, advisors y regresiones locales finales. Capturas completas, credenciales y configuraciones originales permanecen privadas fuera del repositorio. No se versionan secretos ni usuarios productivos.
