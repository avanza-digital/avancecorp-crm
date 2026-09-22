# F4 — ejecución del cierre, 22/09/2026

**Decisión vigente de Miguel, 22/09:** mantener la alerta de tasa muy baja apagada
hasta F5. No se compara aún con la tasa del equipo ni se permite activarla rellenando
la diferencia. El campo reservado conserva NULL; la publicación de F4 rechaza un
valor distinto. Esta decisión sustituye la opción anterior de activarla al rellenarlo.


## Objetivo y taller

Completar etapas 4–6 y primera jornada operativa, sin TypeSafe/F5.
Taller aislado existente: `/private/tmp/avancecorp-release.hvdub4/repo`, rama
`codex/gestion-diaria-f4-cierre`, base `e22c0cab`. Miguel confirmó que otra sesión
sigue escribiendo en el taller principal: no se cambian allí ramas ni archivos.
La conciliación final con Main se hará conservando ese trabajo.

## Avance comprobado (actualizado durante el cierre)

- Tres candidatos SQL: avisos persistentes, configuración y grupos diarios.
  Instalados solo en `gestion-diaria-f4-http`, con respaldo privado anterior.
  Ensayo previo reversible PASS: cinco gates antes/después, 21 mutantes,
  roles, reloj Lima, sábado/domingo, entrega/reintento, reconocer/posponer,
  sello del POST, cierre y siguiente día, configuración estricta y futura.
- Grupos diarios sobre el núcleo SLA, ids y cantidades cotejados con casos
  sintéticos no vacíos. Contexto de llamadas bajo RLS; inactividad >2 h en
  jornada y sin duplicar miembros de cortes. Tasa baja permanece OFF hasta F5.
- Frontend integra popup/lista/campana/registro/editor. Comparte el libro anterior
  para tareas y reparto; los otros problemas se retiran al resolverse.
- `npm run check` PASS: **4.150 pruebas, 277 archivos**, cobertura, release-config,
  service worker, build, verify:bundle y duplicación 0,50 %. Lint conserva solo
  cuatro avisos anteriores del coverflow. Log: `/private/tmp/gd-f4-check-final-20260922.log`.
- HTTP/Auth **PASS**: seis roles, contexto completo y paridad de dos equipos,
  anonimato/privados denegados, gerencia escribe y directorio lee, tasa baja no
  activable. La primera corrida detectó un parámetro mal nombrado en el arnés;
  corregido de `p_configuracion` a `p_config`; segunda corrida PASS.
- Concurrencia HTTP **PASS**: dos sesiones Auth distintas por actor. Una conexión
  PostgreSQL retiene el lock y se comprueba que DOS solicitudes están esperando
  antes de liberarlo. Publicación: una confirma y otra 40001. Presentación: una
  entrega y reintento idempotente. Aplazamiento: una fila de una hora y otra 22023.
  Reconocimiento compartido entre sesiones PASS. No se sustituyeron relojes de RPC.
- Para esas pruebas se sembró **solo en el banco** una política de la víspera;
  el trigger se restituyó en la misma transacción y todos los gates pasaron.
  El banco tiene v2 activa hoy y v3 OFF desde mañana, con historia sintética
  conservada. Producción sigue v1 OFF; esta preparación no es activación productiva.
- Jev `jev-1.13.0`: 13 clasificaciones en 2.191 ms; 2.747 tokens de entrada y
  753 de salida. Se aceptó el orden de trabajo y se resolvió con el plan una
  categoría dudosa; no se tomó como veredicto técnico. [Evidencia](F4-CIERRE-JEV-2026-09-22.md).
- Claude: primer dictamen de este objetivo recuperado, CHANGES_REQUESTED;
  hallazgos atendidos, revisión final del alcance completo pendiente.
  [Dictamen](F4-CIERRE-REVISION-SQL-2026-09-22.md).
- Docker: se reanudaron solo los seis servicios propios tras la autorización de
  Miguel. Red sin egreso externo IPv4/IPv6, puertos loopback, restart=no. No se
  tocaron servicios de la otra sesión ni el taller principal.

Evidencias privadas del banco: `gd-f4-etapa4-instalacion.json`,
`gd-f4-http-permisos.json`, `gd-f4-concurrencia-http.json` bajo
`/private/tmp/gestion-diaria-f4-http.WQNCJc`. Respaldo: `gd-f4-antes-etapa4-20260922.dump`.
El ensayo transaccional previo queda en `/private/tmp/gd-f4-ultimo-ensayo-sql.txt`.
Navegador real PASS: foco al escribir, popup, registro, reconocimiento y
aplazamiento, segunda sesión móvil. Capturas revisadas: texto mínimo 16 px,
botones mínimos 44 px y nombres completos sin recorte. Configuración real de
gerencia con confirmación cancelada. Evidencia: `gd-f4-navegador.json` y
`gd-f4-capturas.json` en la misma carpeta privada.

Regresión Playwright nativa: **232 PASS, 26 SKIPPED**, cero fallos. Las 26
omitidas corresponden a Clientes/Contratos retirados, según sus specs. La
corrida anterior tuvo 231 PASS, 26 SKIPPED y un fallo por mock ausente de la
nueva RPC; corregido. No registrar 257/258 como pruebas aprobadas. Main agregó
la obligación de E2E local en Docker durante el trabajo: ese gate sigue pendiente.

Tipos oficiales locales generados y diez contratos de F4 cotejados PASS.
Se preserva la versión PostgREST productiva y los tipos ajenos. Check:scripts
PASS tras autorizar el servidor loopback que el sandbox bloqueaba. Cambio
posterior al check: retirar popup al cierre de jornada o después de 90 s sin
foto fresca; diez pruebas del provider, lint/typecheck y build PASS.

## Decisiones sobre la revisión

Aceptado: conservar RLS en el cálculo mediante rol puente NOLOGIN/NOBYPASSRLS,
propietario solo del lector; authenticated no recibe membresía del puente.
Los índices, permisos, rol, funciones y triggers nuevos deben quedar sellados con
asserts/mutantes (implementados y probados, 21 mutantes). Paridad del ámbito de llamadas con dos equipos por HTTP y de pendientes con el núcleo SLA por SQL PASS. Las huellas del catálogo se midieron con el mismo search_path vacío del gate; los nombres cualificados cambian respecto de psql.

Aceptado: id ISO independiente de DateStyle, boolean de permiso siempre boolean,
conversión de cantidades 3.0 válida, distinción entre aviso ajeno y resuelto,
prefijo literal sin comodín y precedencia explícita. Programación acotada a 90 días
para impedir que un error de año bloquee el historial inmutable hasta ese año.

No se adopta un segundo bloqueo de activación: la política futura publicada por
gerencia es la activación aprobada en el plan. La migración no crea dicha política;
el canal de emergencia no cambia cálculos y no activa por sí solo los cortes.
La interfaz requerirá confirmación de versión, reglas y jornada antes de publicar.

Los cortes conservan la regla aprobada de una presentación por supervisor/día/corte.
Miembros que cambian actualizan la lista; no reabren automáticamente un popup
reconocido. El comportamiento legacy de empeoramiento se conserva para sus alertas.
Posponer fuera del límite de reaviso mantiene la hora real y muestra explícitamente
que no habrá reaviso; no se convierte el pendiente en resuelto.

Entregas: traza mínima sin datos comerciales ni fotografía de rendimiento, máximo
cuatro por supervisor/día; conservación inmutable con auditoría. No se usa para
reproducir equipo/jerarquía históricos. Retención documentada aparte del ledger
legacy de 90 días, cuya caducidad se conserva.

## Índices INFO evaluados

Advisors productivos consultados el 22/09 19:01 UTC: siguen los dos INFO sobre
`politica_gestion_diaria_creado_por_fkey` y
`politica_gestion_diaria_version_anterior_id_fkey`. Producción tiene una sola fila.
El lector resuelve por `(vigente_desde DESC, version DESC)`, índice existente;
ninguna lectura de F4 necesita buscar políticas por autor o por referencia anterior.
Las políticas son inmutables y los perfiles se desactivan, no se eliminan.
Decisión: diferir esos índices hasta medir crecimiento o una consulta que los use;
no añadir cambios de esquema solo para vaciar avisos informativos. No son avisos
de seguridad ni un bloqueo de F4. Referencia:
https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys

## Historial SQL

Lectura remota confirmó versión `20260922164159`, nombre `crm_gestion_diaria_cortes`,
33 sentencias, política v1 OFF. El archivo `20260921214018` ya está instalado: no
reejecutarlo. La reparación de historial está pendiente, previa comparación/resguardo
y siguiendo el procedimiento de publicación; no se ha mutado la base productiva.

## Pendientes reales

1. Evaluar el segundo y último dictamen de Claude (revisión completa en curso),
   corregir con evidencia y verificar los cambios pertinentes.
2. Integrar avancecorp/main, conservando cambios de la otra sesión. Ejecutar
   E2E dentro de un contenedor Docker identificado como Gestión Diaria y los
   gates del código final integrado. No repetir sobre el banco los pasos de
   instalación/concurrencia que ya consumieron entregas inmutables.
3. Conciliar el ledger instalado sin reinstalar etapa 3, preparar SQL exacto,
   respaldo/recuperación y artefacto desde Main/remoto coincidentes. Publicar
   mediante el procedimiento autorizado (rama Supabase y release CRM).
4. Programar cortes para una jornada futura y verificar su primera jornada real.
   No marcar F4 completa por haber cerrado pruebas locales.
