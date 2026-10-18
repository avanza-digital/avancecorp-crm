# Referidos propios de supervisores — verificación

16/10/2026. Codex PRIMARY. Cambio LEVEL 3 por autorización de alta.
Base de trabajo: `82a995b4e8fedfe4d737a348907a9719638962fe` de `avancecorp/main`.

Actualización de cierre: **PUBLICADO Y VERIFICADO**. Ver [PUBLICACION.md](PUBLICACION.md)
para commit, artefacto, controles productivos y eliminación de la rama temporal.
El resto de esta nota conserva la evidencia previa a promoción.

## Decisión y alcance

Miguel pidió habilitar Referido para Supervisión y respondió «Siempre a cargo
del supervisor» al preguntar quién queda como responsable al registrarlo.
En Nuevo lead → Referido, el responsable queda fijado al supervisor autenticado.
El backend normaliza el destino omitido al actor y rechaza todo destino ajeno,
incluido un analista de su equipo. El alta de analistas conserva su regla propia.

No cambia la gestión posterior del lead, las reglas de los otros orígenes,
pesos de conversión, metas, ranking ni periodos sellados. Las ventas propias
conservan el aporte al equipo ya publicado. No se abre Referido a Gerencia.
La API, firma, tipos de retorno, ACL, SECURITY DEFINER y search_path no cambian;
por ello no corresponde regenerar tipos.

## Evidencia ejecutada

| Gate | Resultado | Evidencia |
|---|---|---|
| Frontend `npm run check` | PASS: 434 archivos, 6994 tests, lint, tipos, build, cobertura, bundle y duplicación | [frontend.log](frontend.log) |
| E2E completo en Docker, 2 workers | PASS: 439 passed / 26 skipped / 0 failed | [e2e.log](e2e.log) |
| SQL local con estructura productiva | PASS: 67 aserciones, reversa, reaplicación y rollback total | [sql-local.log](sql-local.log) |
| SQL en rama Supabase | PASS: las mismas 67 aserciones, transacción revertida | [sql-cloud.log](sql-cloud.log) |
| Auth/PostgREST antes | PASS: sesiones reales y rechazo previo de Supervisor/Gerencia | [http-antes.json](http-antes.json) |
| Auth/PostgREST después | PASS: 28 comprobaciones con 11 JWT reales | [http-despues.json](http-despues.json) |
| Scripts y mutantes | PASS | [scripts.log](scripts.log) |
| Seed y RLS preflight offline | PASS con entorno ficticio local; no reemplazan la matriz real | Ejecución local del PRIMARY |
| Edge preflight | PASS; no se despliegan funciones | [edge.log](edge.log) |
| Gate realidad productivo, solo lectura | PASS: 10 mediciones, 0 errores; 2 desvíos previos | [realidad.json](realidad.json) |
| Catálogo de rama | PASS: 1110 funciones, una definición modificada, ningún owner/ACL cambiado, historial 485 → 486 | [catalogo-rama.json](catalogo-rama.json) |
| Advisors | Sin nuevas advertencias de SQL/RLS/permisos atribuibles al cambio | [advisors-rama.json](advisors-rama.json) |

Los desvíos del gate realidad son 45 contratos de personal retirado y 273 clientes
sin domicilio; este cambio no depende de corregirlos. Las pruebas del formulario
incluyen supervisor fuera del roster, dueño de un origen anterior, rechazo del
servidor y persistencia confirmada antes de mostrar éxito.

## Rama y paridad

Rama temporal autorizada `supervisores-referidos-20261016`, ref
`xniiuzkqssqnabkluusv`, ID `e2f383bf-1c87-48f7-befd-d1396fbd5973`.
El replay antiguo de Supabase falló antes de alcanzar el esquema vigente. Se
restauró solo la estructura productiva y su historial exacto de 485 migraciones,
sin copiar datos personales. Se desactivaron sus dos cron antes del fixture.
Se cotejaron las 1110 funciones, owner/ACL, roles, membresías y triggers de Auth.
La calificación de `public.contratos` depende del search_path del lector; esa
diferencia de representación se normalizó solo en las firmas, nunca en cuerpos.
Las 23 Edge Functions tienen los mismos hashes y verify_jwt que producción.

La rama usa 11 identidades sintéticas, dos equipos y flags equivalentes al vivo.
Todas las operaciones comerciales se ejecutan como authenticated o por JWT real.
El administrador solo prepara fixtures, esquema y metadatos sintéticos de un
comprobante; no se probó una subida real de archivos ni se creó un lead de prueba
en producción. No se reprodujeron los default privileges administrados por
Supabase ni se usa este banco para certificar las policies ajenas de Storage.

Migración registrada `20261016183308_crm_supervisores_referidos_propios.sql`:
el SQL registrado coincide byte a byte con el archivo. Preflight de cuerpo
`b6ec8dddaa8ab81b9248a79f4de3a51f`; postflight
`145b30a30e69807a1838c1b960a0675d`. La reversa restaura la huella anterior y
conserva los datos. No se aplica directamente a producción.

Advisors: seguridad 379 → 380 en rama porque, tras activar los ensayos de Auth,
se informó `auth_leaked_password_protection`, ya presente en el baseline
productivo. No se cambió Auth; [documentación de esa configuración](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).
Rendimiento 350 → 317: 33 índices dejaron de figurar como no usados después del
fixture. No se considera esto una optimización productiva.

## Revisión independiente y respuesta del PRIMARY

Claude revisó evidencia saneada por `scripts/claude-review`, sin herramientas ni
escritura. [Encargo](CLAUDE-ENCARGO.md) y [dictamen](claude-review.txt).
JEV ordenó contexto técnico mediante TypeSafe; [entrada](jev-extractos.json) y
[salida](jev-contexto.json). Ninguno sustituye los controles ejecutados.

El dictamen fue CHANGES_REQUESTED; no se solicitó otra opinión para obtener PASS.
Los hallazgos se resolvieron y verificaron así:

1. P2, postflight ausente: añadido dentro de migración y reversa; ambas ensayadas
   de nuevo, con reversión si la huella no coincide.
2. P2, falta matriz JWT: añadido `test-rls.mjs --supervisores-referidos` y ejecutado
   antes/después en la rama. Dueño omitido/propio, terceros, otros roles, privacidad,
   otros orígenes, DNI/CE/pasaporte, INSERT directo y revocaciones con JWT emitido.
3. P2, hipótesis de consumidores: inventariadas las 37 funciones pertinentes en
   [CONSUMIDORES.md](CONSUMIDORES.md). Añadidas aserciones del núcleo de conversión,
   total de empresa, roster de analistas y reporte filtrado por Referido; PASS.
4. P3, sesión redundante: retirada del fixture.
5. P3, orden de publicación: backend por merge primero; frontend después desde
   main limpio, verificado y coincidente con `avancecorp/main`.

También se añadió el caso simétrico de idempotencia (alta explícita, reintento
sin destino). El encargo y dictamen conservan el nombre provisional de migración
`20261016174128`; Supabase le asignó `20261016183308` al aplicarla a la rama.

## Promoción

Al redactar esta evidencia, backend y frontend están validados pero aún no
publicados. Integrar el PR con los controles automáticos aprobados; promover la
migración por merge de la rama, comprobar huella/ACL e historial productivo y
publicar después el artefacto de main. Eliminar la rama temporal al terminar.
La constancia final debe identificar commit, ZIP, SHA-256, smoke y limpieza.
