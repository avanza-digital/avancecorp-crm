# Evaluación del PRIMARY · 07/10/2026

## Dictamen y alcance

Claude actuó como SECONDARY_REVIEWER, sin herramientas ni escritura, mediante `scripts/claude-review`. El primer intento no produjo un dictamen válido. El segundo devolvió **CHANGES_REQUESTED**, sin P0/P1. No se pidió otra opinión para cambiar ese resultado. El dictamen original queda en `revision-claude.txt`; los cierres siguientes son decisiones verificadas del PRIMARY, no un PASS atribuido a Claude.

## Observaciones evaluadas

| Observación | Decisión y evidencia |
| --- | --- |
| P2: volver al foco recargaba toda la cola | Aceptada y corregida. `useReparto.actualizarPermiso` consulta únicamente la agenda y actualiza el booleano. Agrupa eventos durante 250 ms; evita llamadas durante carga/envío y cancela la lectura al enviar o salir. Tres pruebas nuevas conservan nodo, destino y contadores, prueban activación/revocación y limpieza. 55 pruebas de pantalla y 34 E2E Docker PASS después del cambio. |
| P2: signal 11 del banco | Investigado en un contenedor independiente de la misma imagen. Se reproduce sin lógica del CRM, también con funciones SQL/PLpgSQL que solo devuelven true. Rol `authenticated`: caída; rol neutro: 42501 normal. Coincide con reportes del proveedor. No se cambia el SQL ni se amplían grants para ocultar el defecto. Se exige comprobar las rutas HTTP y el motor en rama desechable antes de aplicar/publicar. |
| P3: FK `actualizado_por ON DELETE RESTRICT` | Se conserva la convención del registro de reparto (`20260819220501_crm_agenda_reparto_diaria.sql`, columnas creado_por/actualizado_por). La baja operativa es por vigencia de perfil/membresía; este control no impide esa baja. Un borrado físico deberá resolver sus dependencias, como ya ocurre con el reparto. |
| P3: posible variable anterior | Cero ocurrencias de `v_es_administrador` en la función instalada. ACL conservada: escritor solo postgres; agenda postgres/authenticated. |
| P3: envío en curso al apagar | Documentado: efectivo para sentencias iniciadas después del commit. No se promete cancelar repartos ya iniciados. |
| P3: etiquetas de administrador/reportes | `excepcion_turno` no tiene consumidores frontend. `fuera_turno` se usa en la agenda con texto neutral sobre turnos y entregas de Coordinación. Actor real confirmado en tres actividades SQL. |
| P3: matriz cambia un control global | La guarda preexistente `validateEnvironment` de `test-rls.mjs` rechaza el project ref productivo antes de conectar. Se documentó junto al test y se conserva el finally que restaura el estado. |
| Gaps: anon/service_role, destino inactivo y Superadmin OFF | ACL SQL ampliada PASS, destino con perfil/membresía inactivos PASS, agenda y reparto del Superadmin en OFF PASS. Negativas HTTP de anon/service_role añadidas; NOT RUN en rama hospedada. |
| Gaps: default del cliente, demo y auditoría | Ya cubiertos: `crm-api-reparto-msw.test.ts` prueba true/false/ausente y payload inválido; `config.test.tsx` cubre rol real y demo; SQL prueba `audit_log` con actor real. `edita` exige `!yo.demo`. |
| Getter STABLE después de UPDATE | Se conserva: matriz SQL y prueba con dos conexiones reales verifican valor/revisión/actor. No se identificó fallo de snapshot en la implementación. |

## Evidencia del motor

- Imagen local: `public.ecr.aws/supabase/postgres:17.6.1.105`, sha256 `a8a67cc80115637d4db0481c6abbc153d20dea12b56d778af48edb83e74f5728`.
- Primer fallo, 07/10/2026 14:38:37 UTC: `select pg_temp.rechaza('select private.reparto_libre_habilitado()','42501');` termina por signal 11 y el motor se recupera automáticamente.
- Diagnóstico posterior: contenedor `reparto-permisos-motor-20261007`, `--network none`, DB `reparto_fallo`, copia solo del banco sintético. La misma llamada y dos funciones triviales reproducen el fallo. El contenedor quedó detenido al terminar; no se detuvieron los contenedores del usuario.
- Parámetros observados: `supautils.hint_roles = anon, authenticated, service_role`. Producción, mediante solo lectura, informa esos mismos roles y PostgreSQL 17.6; eso no demuestra igualdad de binarios ni que el fallo se produzca allí.
- Reportes existentes: [supautils #214](https://github.com/supabase/supautils/issues/214), [postgres #2112](https://github.com/supabase/postgres/issues/2112). No se envió ningún mensaje ni reporte externo en esta tarea.
- Logs locales: `/private/tmp/reparto-libre-motor.log`, `/private/tmp/reparto-libre-motor-aislado.log`; sonda exacta `/private/tmp/reparto-libre-motor-sonda.sql`. No copiar un dump completo al repo.

Reproductor mínimo observado, **solo para un contenedor aislado desechable**; puede provocar recuperación de toda la instancia:

```sql
create schema motor_sonda;
create function motor_sonda.sql_true() returns boolean
language sql stable security definer set search_path='' as 'select true';
revoke all on function motor_sonda.sql_true() from public;
grant usage on schema motor_sonda to authenticated;
set role authenticated;
select motor_sonda.sql_true(); -- signal 11 en la imagen local indicada
```

Control en otra conexión: rol nuevo fuera de `hint_roles`, sin EXECUTE y con USAGE sobre `motor_sonda`; la misma llamada devuelve `permission denied for function sql_true` sin caída. Cambiar la función a PL/pgSQL no evita el fallo para `authenticated`.

## Gate antes de producción

La preparación local está verificada; **no se declara listo el despliegue productivo**. Antes de aplicar: rama Supabase, preflight de huellas, SQL exacto, matriz HTTP/RLS y advisors. Confirmar que las denegaciones HTTP retornan errores de autorización sin reiniciar el motor; si el entorno hospedado reproduce el fallo, detener la instalación productiva y resolver con el proveedor. No llamar la sonda en producción, no retirar REVOKE ni alterar extensiones de producción como atajo.

El preflight productivo de solo lectura del 07/10/2026 dio cinco true: escritor y agenda conservan las huellas esperadas; tabla y RPC nuevas aún no existen. El gate global de duplicación falla con los mismos 57 clones/1.451 líneas con y sin esta tarea. Publicación únicamente tras la invocación humana del flujo `$release-crm` y los gates del repositorio.

## Cierre posterior de publicación · 07/10/2026

Los gates previos se completaron con la autorización humana: rama hospedada, SQL exacto, HTTP de los permisos, advisors y postflight productivo. Se confirmó PostgreSQL 17.6.1.105 y las negativas HTTP respondieron 42501 sin caída. Check limpio PASS (6.333 tests, duplicación 0,44 %) y 49 E2E Docker PASS. Backend aplicado, frontend publicado y rama eliminada. Los incidentes de fixture y sus repeticiones se documentan sin ocultar el primer resultado en [PUBLICACION.md](PUBLICACION.md).
