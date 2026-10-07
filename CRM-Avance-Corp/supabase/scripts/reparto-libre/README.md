# Reparto libre de Coordinación

Pedido de Miguel, 07/10/2026: todo el rol Coordinadora puede derivar libremente a supervisores y Gerencia debe tener un botón para activar/desactivar el permiso.

**Estado: implementación local y pruebas terminadas; revisión independiente evaluada y corrección de recarga verificada. No aplicado ni publicado en producción.**

## Comportamiento

- Gerencia real: Configuración → **Reparto libre de Coordinación** → Activar/Desactivar.
- Encendido: todas las cuentas activas del rol Coordinadora eligen cualquier supervisor activo para Landing/Formulario, incluso sin turno guardado.
- Apagado: vuelve el turno obligatorio. Una pantalla vieja no puede saltarlo: el servidor rechaza el intento y la pantalla relee el permiso y la agenda.
- Superadmin conserva su excepción preexistente. Otros roles no reciben el permiso; el control no convierte a Coordinación en administradora.
- Las actividades conservan la identidad real y el destino de la entrega; el reporte conserva `fuera_turno`.
- Una derivación que comenzó antes del cambio conserva la fotografía de su sentencia; las llamadas iniciadas después del commit ven el nuevo estado. Al volver a la ventana se consulta solo el permiso, sin desmontar filas ni sobrescribir selecciones o contadores; no se consulta durante un envío. La recarga completa y el rechazo del servidor también actualizan el permiso.
- La migración arranca el control **encendido**, de acuerdo con el pedido original. La columna tiene default false; una configuración ausente no concede el permiso.
- Solo las RPC de Gerencia modifican el estado. Una revisión obsoleta devuelve `PT409`; el botón relee antes de permitir otro intento. La UI no anuncia éxito antes de recibir confirmación.

## Banco y pruebas

Banco fijo `reparto_libre_20261007` dentro del contenedor local `supabase_db_crm-avance-corp-local`, clonado de la plantilla sintética `base_gestion_20261002`. El comentario obligatorio es `BANCO SINTETICO reparto libre Rosa 20261007 / sin produccion` (el nombre histórico del banco se conserva tras ampliar el pedido a todo el rol). No recibe credenciales ni URL de producción.

```sh
node supabase/scripts/reparto-libre/banco.mjs instalar
node supabase/scripts/reparto-libre/banco.mjs probar
node supabase/scripts/reparto-libre/concurrencia.mjs
```

`instalar` solo sirve una vez sobre el catálogo previo; comprueba las huellas de las dos funciones reemplazadas. `probar` ejecuta y revierte toda la matriz SQL. `concurrencia` usa dos conexiones reales, exige un éxito y un PT409, restaura el control inicial y deja su cuenta sintética inactiva.

**PASS:** matriz SQL con roles `authenticated` reales, dos coordinadoras, ON/OFF, sin agenda, fuera del turno, No Insista, destino inválido, doble derivación, Gerencia sin poderes de portal, revocación de perfil/equipo, ACL, RLS y auditoría. Concurrencia real PASS: una única revisión y actor correcto.

**PASS:** 6.311 pruebas de frontend en 394 archivos, typecheck, lint sin errores (advertencias previas), build, bundle y configuración de release. 34 E2E Docker de `repartir.spec.ts` y `reparto-libre.spec.ts`; recorrido y captura de Configuración verificados. Tipos generados con Supabase CLI desde el banco; solo tres nodos nuevos integrados en `database.types.ts`, conservación y cotejo exacto verificados.

**PASS después de la revisión:** 55 pruebas de `repartir.test.tsx` (incluye tres nuevas sobre foco, conservación de selección/contadores, envío en curso y limpieza); lint de los archivos modificados, typecheck/build final y repetición de los 34 E2E Docker. La matriz SQL ampliada cubre supervisor con perfil o membresía inactivos, ACL de anon/service_role y permiso de Superadmin con el control apagado. No se volvió a ejecutar toda la suite tras ese ajuste acotado.

**PASS:** preflight RLS offline con las variables ficticias del workflow. La matriz HTTP general `test-rls.mjs` incorpora ahora el control, negativas por rol, cambios ON/OFF, conflicto y restauración del estado previo.

**FAIL previo, reproducido sin este cambio:** `npm run check` termina con el gate de duplicación: 57 clones, 1.451 líneas duplicadas (1,06 %) frente al límite 0,8 %. Copiar el árbol, retirar exclusivamente este cambio y ejecutar el mismo detector produce exactamente los mismos 57 clones/1.451 líneas. No se alteraron los duplicados ajenos ni el umbral.

**NOT RUN:** matriz HTTP general sobre una rama hospedada y advisors; pendientes del entorno de instalación. `gate:realidad` no corrió por faltar las credenciales de servicio en el entorno; sí se cotejaron la cuenta, las funciones vivas y su contrato por consultas de solo lectura. No hay funciones productivas que envuelvan `crm.agenda_reparto_diaria`; el frontend usa `v.object` y acepta el campo agregado sin romper el contrato anterior.

Incidencia del banco: PostgreSQL Supabase 17.6.1.105 sufrió `signal 11` al llamar una función sin EXECUTE. Se reprodujo después en un contenedor **aislado, sin red y ya detenido**, con funciones mínimas SQL y PL/pgSQL sin lógica del CRM. Un rol neutro recibe el error normal. La evidencia coincide con el problema reportado al proveedor en [supautils #214](https://github.com/supabase/supautils/issues/214) y [postgres #2112](https://github.com/supabase/postgres/issues/2112). La comprobación local de ACL usa `has_function_privilege`; no se concedió EXECUTE para eludirla. Producción informa PostgreSQL 17.6 y los mismos roles de hint, pero no se probó el fallo allí ni se conoce la revisión exacta de su imagen. La matriz HTTP remota y la verificación del motor en una rama desechable siguen siendo requisitos previos a aplicar. Detalle y decisión del PRIMARY: [REVISION.md](REVISION.md).

## Instalación y recuperación

SQL exacto: `../../migrations/20261007143121_crm_reparto_libre_coordinacion_configurable.sql`. Miguel invocó `$release-crm` el 07/10/2026 y autorizó además probar y aplicar esta migración, incluido el costo de la rama temporal de Supabase (US$0,01344/h), que debe eliminarse al terminar. La autorización está dada; los gates y el postflight siguen siendo obligatorios.

Antes de aplicar: `preflight.sql`, rama autorizada de Supabase, migración exacta, matriz RLS/HTTP y advisors; después, integración/registro por el flujo permitido del repositorio. El frontend debe construirse desde Main local/remoto verificados. No usar `apply_migration` directo a producción.

Recuperación operativa: Gerencia desactiva el control, lo que restablece la obligación del turno conservando auditoría e historial. Una reversión de pantalla debe ir acompañada de esa desactivación. `repartir-anterior.sql` y `agenda-anterior.sql` conservan las definiciones vivas previas para comparar; no son un instalador automático de reversa. No se elimina la tabla ni la auditoría para revertir el permiso.

Evidencia local de esta sesión: `/private/tmp/reparto-libre-check.log`, `/private/tmp/reparto-libre-e2e-final.log`, `/private/tmp/reparto-libre-build-final.log`, `/private/tmp/reparto-libre-sql-final.log`, `/private/tmp/reparto-libre-dup-base.log`. Dictamen conservado en [revision-claude.txt](revision-claude.txt). La captura está en `app/test-results/reparto-libre-gerencia.png` (el siguiente E2E puede reemplazarla).
