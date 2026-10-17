# Publicación de tipo de cambio por venta — en preparación

**Producción todavía sin cambios de esta tarea.** Miguel autorizó publicar,
confirmó la organización AVANCECORP- CRM-PORTAL y autorizó US$0,01344/h de
rama temporal. No se enviaron avisos a terceros.

Se preserva el checkout compartido con cambios ajenos. La integración usa el
clon `/private/tmp/avancecorp-tc-publicacion-20261017`, rama Main y remoto
`avancecorp/main`. La base inicial verificada fue `92ae6f94`; durante el gate
avanzó a `e4ded65d` con cooperativas a 360 días, que debe integrarse antes del
artefacto final. No publicar un build que omita ese avance.

## Evidencia de integración y bancos

- App integrada sobre `92ae6f94`: `npm run check` PASS, 438 archivos / 7043
  tests, lint, tipos, cobertura, release, build y bundle; duplicación 0,76 %.
- E2E Docker completo de esa fuente: **444 PASS, 26 skipped, 0 FAIL**, 17,6 min.
  Se descarta una corrida detenida cuya instalación de dependencias enlazada
  producía avisos de Vite; la evidencia aceptada usa dependencias físicas.
- Banco SQL con once migraciones: replay PASS, 89 aserciones de cortes,
  escritores, permisos y cierre; catálogo `public` conservado.
- Censo analítico con configuración nativa sin datos personales: conserva las
  44 declaraciones anteriores, incorpora dos, conserva tope/deuda ajenos;
  sello alterado, declaración desconocida y segunda aplicación rechazan con
  rollback completo.
- Revisión independiente de publicación: dos PASS, sin P0–P3. Ver
  REVISION-PUBLICACION-RLS.md. No se requieren nuevas consultas equivalentes.

## Rama temporal Supabase

Rama propia `tc-venta-publicacion-20261017`, ID
`8ef0f6f1-6d5a-413f-937f-186b53de5a98`, referencia `ezkprhnvgwpjxoybhkxs`.
No se reutilizaron ni eliminaron ramas de otras tareas.

El bootstrap automático del historial antiguo falló antes de completar el
esquema. Se restauró exclusivamente el esquema nativo vacío en esa rama,
con guardas de ausencia de usuarios/contratos/perfiles/leads, propietarios y
roles internos originales, dependencias Auth/Storage y extensiones. Esta
restauración NO es una migración y NO se incorpora al merge productivo.
Se alinearon solo los metadatos de las 487 migraciones productivas de la
captura y las 44 declaraciones analíticas; no se copiaron clientes ni ventas.

Verificación previa: usuarios/perfiles/cron cero; cierre nativo MD5
`3289a365b8d9f4732272bba2a832e6a0`. Las once migraciones se aplicaron por
`apply_migration` únicamente a la rama: 498 entradas, política apagada,
46 declaraciones y sello válido. Edge `crm-capital-valorar` desplegada en
esa rama con `verify_jwt=true`, versión 1.

La matriz de `test-rls.mjs --tipo-cambio-venta-cloud` usa el mismo recorrido
HTTP local con once cuentas ficticias y Auth/PostgREST cloud reales. La
protección safeupdate de cloud exige WHERE: se filtra la escritura prohibida
para acreditar el 403 de permisos, conservando la defensa del servidor.

Gate cloud completo **PASS**: once sesiones reales, ocho ámbitos, PII,
GET/PATCH globales denegados, corrección autorizada/denegada, F4 nativo,
idempotencia y recuperación del pendiente: S/68000 + S/31000 = S/99000.
Las tres migraciones base de cooperativas ya publicadas se reprodujeron
sin cambios en la rama y se identificaron con sus versiones productivas:
490 entradas base más once propias. No se reenviarán como cambios nuevos.

La fuente integrada con `e4ded65d` pasó `npm run check`: **438 archivos / 7047
tests**, lint/tipos/cobertura/release/build/bundle y duplicación 0,76 %.
`check:scripts` PASS; el primer intento tuvo un bloqueo EPERM del sandbox al
abrir el servidor de prueba local y se repitió con permiso. E2E afectados por
la integración: **23 PASS**, sin fallos, en Docker.

Worker cloud final: anónimo/anon JWT/vendedor HTTP401; tasa proporcionada por
el cliente HTTP400; servicio HTTP200, pendientes0 y revisiones nuevas0. La
venta de USD20000 conserva S/68000. Se configuró un secreto propio de JWT:
la variable reservada de esta rama contenía una clave moderna sb_secret,
incompatible con verify_jwt. Se conservan verify_jwt y el check exacto;
no se cambian claves ni autenticación de otras Edge. Deno 30 PASS posterior.

Las once sentencias registradas por MCP coinciden byte a byte con los archivos
revisados, ignorando solo salto de línea final. Se alinearon exclusivamente sus
versiones técnicas con las del repositorio usando guardas de nombre y MD5 de
SQL; no cambió su contenido ni se volvió a ejecutarlo. Base490 + propias11.
Las 23 Edge originales de la rama coinciden con producción en SHA/verify_jwt;
la única nueva es crm-capital-valorar.

Advisors cloud final sin objetos temporales: seguridad379→391 y rendimiento
350→322. Son seis INFO de RLS deny-all de las tablas nuevas, cinco WARN de
RPC SECURITY DEFINER intencionalmente expuestas a authenticated y un aviso de
configuración Auth de la rama. Las cinco RPC mantienen autorización nativa y
matriz HTTP aprobada; no se revocan sus APIs legítimas para silenciar el linter.
No hay nuevos errores, search_path mutable ni FK nueva sin índice. El delta de
producción se mide separadamente, pues configuración y uso de índices difieren.

Censo productivo nuevo 17/10 00:17 Lima: 116 operaciones, objetivos USD0,
ajustes USD0, solo agosto sellado; job3 activo. Historial490. Sigue sin instalarse
este cambio en producción en esta etapa.

Pendiente: fuente
Main/remoto limpia, artefacto/preflight, merge autorizado, backfill real,
publicación frontend y activación con huella fresca. Eliminar esta rama propia
al terminar para detener su coste.
