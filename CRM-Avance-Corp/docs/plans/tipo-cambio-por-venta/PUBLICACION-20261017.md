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

Pendiente: delta Advisors sin objetos temporales, fuente
Main/remoto limpia, artefacto/preflight, merge autorizado, backfill real,
publicación frontend y activación con huella fresca. Eliminar esta rama propia
al terminar para detener su coste.
