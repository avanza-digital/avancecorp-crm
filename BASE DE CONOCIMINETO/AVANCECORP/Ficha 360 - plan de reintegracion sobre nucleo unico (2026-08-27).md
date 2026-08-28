---
tipo: plan-tecnico
estado: c0-1-reconciliado-local-certificado-servidor-pendiente
fecha: 2026-08-27
actualizado: 2026-08-28
serial_origen: AVC-F41-360-20260825-R2
baseline_revisado: 7c94d77c39f642e27af676dce6178e6b9f64a315
head_canonico_reconciliado: 1f012829f4dbd4b45d8d1615d6a579b730dbfb05
sha_c01_local: a1f7b2ec2608fbbedb6107157fdb7a9033d26a00
sha_c01_reconciliado: 30e95f399c7114c0cad4b725ef07fcd98c081730
sha_f0_frontend: 41987fea08febac7fb67750bc8269b43582c645d
sha_r2_ux: e6129674844ecca12b224690f43bedb436b06006
head_r2_separado: 4f57db1fd0aa0ff886edf1033aed3718f40fdaad
---

# Ficha 360 — plan de reintegración sobre el núcleo único

Checkpoint vigente de continuación: [[Checkpoint C0.1 nucleo unico 2026-08-28 R4]]
(`AVC-F41-360-20260828-R4`).

Este documento adapta [[Ficha comercial 360 de clientes - plan]] después de
la integración de ramas y de la implantación de
[[Conversion unica en todo el CRM - plan de migraciones]]. Conserva R2 como
evidencia funcional y visual; no convierte su rama ni sus migraciones en un
candidato de producción.

Relacionado: [[Dos ramas paralelas del CRM - la integracion pendiente]],
[[Cierre de seguridad Ficha 360 2026-08-26]],
[[Conversion mensual - definicion cerrada]] y
[[Conversion mensual - plan de implementacion]]. La aceptación comercial
ejecutada quedó en [[Ficha 360 R2 - aceptacion UX comercial 2026-08-27]].

## Decisión ejecutiva

**NO-GO** para fusionar, cherry-pickear o aplicar como parche la rama R2
`e01e1fe`.

**GO condicionado** para reconstruir la Ficha 360 de forma aditiva sobre un
descendiente canónico del árbol actual, después de aprobar/aplicar C0.1 y
verificar la paridad viva del frontend ya cerrado.

La preview R2 sigue siendo válida para aceptar la experiencia comercial. Ya no
es válida para aceptar integración, migraciones, RLS, tipos ni producción.

## Estado ejecutado al 2026-08-28

- La divergencia 5/5 quedó reconciliada en el merge local `30e95f3`, con padres
  `1f01282` (canon) y `d35a284` (R3). Los cinco commits canónicos y C0.1 fueron
  conservados, conciliados y probados juntos; R4 es el checkpoint vigente.
- F0 quedó cerrado localmente en
  `41987fea08febac7fb67750bc8269b43582c645d`. El bridge reconoce el contrato
  F2.4b realmente presente, oculta sus exactos legacy y solo publica C0.1
  cuando existen las dos raíces y bundles coherentes de cinco claves. Conserva
  NULL, decimales, cartera y valores mayores a 100 %.
- La propuesta C0.1 del servidor y su banco adversario existen como artefactos
  revisables y contienen 21 placeholders fail-closed: 18 huellas live, un
  fingerprint agregado de catálogo/ACL y dos hashes candidatos. El runner focal
  PG17 aprobó el caso real, los mutantes internos y 17/17 mutantes de cuerpos.
  No se creó migración ni se tocó una base compartida o producción.
- Esta línea conserva la referencia UX `e612967`, pero la rama preview separada
  avanzó limpia hasta `4f57db1`: su aceptación fresca aprobó 176 archivos y
  2.372 pruebas, E2E 18/18 y 17 capturas. Sigue siendo referencia comercial, no
  candidata técnica; sus cambios de memoria aún deben reconciliarse con esta
  línea en vez de asumirse absorbidos.
- La siguiente frontera no es portar Ficha todavía. La reconciliación y sus
  gates ya cerraron localmente. Ahora se autoriza una captura viva de solo
  lectura, la réplica completa de
  migraciones y la prueba de rendimiento. Solo con una aprobación separada se
  crea/aplica servidor, se hace readback y se verifica la paridad PostgREST/JWT
  antes de decidir la publicación del frontend F0.

## Cierre local F0 y plan vigente por fases

- **Fase 0A — cerrada y reconciliada localmente en `30e95f3`:** bridge F2.4b → C0.1, ocultamiento
  fail-closed, paridad de HOY/Ranking/Metas/Gestión/Directorio, alertas con
  sondas actual/anterior y excepción del Coordinador. Check integral R4: 182
  archivos, 2.426 pruebas, cobertura, typecheck, lint, build, bundle y
  duplicación verdes.
- **Fase 0B — pendiente de autorización:** captura viva de solo lectura de los
  18 cuerpos, catálogo/ACL y readbacks. No aplicar SQL.
- **Fase 0C — banco focal cerrado; integración externa pendiente:** el runner
  PG17 materializó los 21 placeholders locales y cazó 17/17 mutantes. Aún falta
  repetir todas las migraciones sobre una base compatible, fijar las capturas
  autorizadas y medir rendimiento. Si esos gates quedan verdes, una aprobación
  separada permite crear/aplicar la migración y verificar readback más paridad
  PostgREST/JWT.
- **Fase 1 — referencia UX aceptada en rama separada:** R2 en `4f57db1` tiene GO
  local fresco con 18/18 E2E y 17 capturas. Sirve para portar requisitos, no
  commits; su evidencia de vault todavía debe reconciliarse con esta línea.
- **Fase 2:** abrir una línea nueva desde el descendiente canónico aprobado.
- **Fase 3:** reemitir el servidor desde el esquema vigente, sin reutilizar las
  migraciones R2 como ejecutables.
- **Fase 4:** portar el frontend aditivamente, reconciliando a mano los puntos
  que se solapan con contratos, cartera, store y capa de datos.
- **Fase 5:** cerrar historial y paginación sin truncamiento silencioso.
- **Fase 6:** ejecutar el gate integrado de esquema, RLS, carreras, conversión,
  PDF, roles, regresiones y datos reales autorizados.
- **Fase 7:** construir y aceptar una preview candidata nueva por cada rol.
- **Fase 8:** publicación aditiva solo con autorización expresa y observación.

El snapshot F0 reconciliado y el banco focal C0.1 tienen GO local ejecutable.
Ese GO incluye `1f01282`, pero no certifica el esquema completo ni producción.

## Foto comprobada al adaptar el plan

- Base común revisada para C0.1: `7c94d77`.
- Candidato R3: `a1f7b2e`; canon reconciliado: `1f01282`; merge R4:
  `30e95f399c7114c0cad4b725ef07fcd98c081730`.
- La divergencia 5/5 con merge-base `7c94d77` quedó cerrada. R4 preserva la
  cosecha bruta y el filtro por origen de Conversiones, terminología,
  compilación histórica, montos compactos y el contador único del Resumen.
- R2 permanece aislada. `e01e1fe` es el prototipo funcional base; la rama de
  evidencia avanzó hasta `4f57db1` y está limpia, diez commits por delante de su
  remoto. Ninguno es candidato técnico ni debe fusionarse en bloque.
- Ancestro común R2 ↔ árbol actual: `b3f6e98`.
- La integración histórica `274f866` ya es ancestro del árbol actual; el
  bloqueo viejo de ramas está resuelto.
- El delta funcional R2 `c9a3675..e01e1fe` toca 83 archivos y solapa 32 con el
  árbol nuevo. La rama completa toca 107 y solapa 56.
- El merge total y el parche funcional fueron simulados sin modificar el
  worktree: ambos producen conflictos en Mi cartera, contratos/PDF, capa de
  datos, store, tipos, pruebas SQL y notas.
- En el snapshot revisado, 5 archivos de pruebas del núcleo suman 72 tests
  verdes. Esto valida los casos cubiertos, no los huecos adversarios descritos
  abajo.

La rama puede seguir avanzando. Al ejecutar este plan se debe fijar de nuevo un
SHA limpio y repetir el diff desde `e01e1fe`; los SHA de esta nota son evidencia
del diagnóstico, no una instrucción de volver atrás.

## Arquitectura que debe quedar intacta

```text
Acción comercial en Ficha 360
        │
        ▼
writers/RPC canónicos de contratos y cartera
        │
        ▼
crm.operaciones_cartera  ── elegible_conversion = candidato, no resultado
        │
        ▼
private.conversion_episodios
  - atribuye al responsable correcto
  - deduplica a una operación elegible por cliente/mes
        │
        ▼
conversion_mensual_fn y consumidores F2/F3
```

Reglas de frontera:

- La Ficha muestra y ejecuta hechos comerciales; no divide, promedia ni decide
  conversiones.
- `elegible_conversion=true` no autoriza a decir que esa operación «cuenta como
  conversión de este mes»: puede perder frente a otra operación del mismo
  cliente/mes. Si se necesita esa atribución, debe servirla el servidor desde
  el núcleo.
- Renovación suma una conversión y no divisor. Upgrade solo es elegible después
  del mes del primer contrato. Nunca más de una conversión por cliente/mes.
- Capital vigente sigue siendo stock de contratos activos, separado en PEN y
  USD; no se obtiene de la conversión mensual.
- La lectura comercial mínima de `crm.cliente_ficha_fn` no sustituye la lectura
  sensible que usa el formulario de corrección. Banca, PDF, hard-delete y
  mutaciones continúan protegidos por RPC/RLS.
- Directorio puede leer la ficha comercial global según su alcance, pero no
  gana banca ni mutaciones.

## Gates de conversiones que preceden a la Ficha

El servidor central ya existe, pero la revisión adversaria encontró cuatro
degradaciones en consumidores. F0 `41987fe` las cerró localmente; se conserva
su definición como contrato de regresión. El banco focal C0.1 y su
reconciliación canónica R4 también quedaron cerrados localmente; continúan
pendientes captura live, réplica integral y aplicación autorizada en servidor.

### C0.1 — eliminar la tercera fórmula en Gestión/Directorio — reconciliado localmente, servidor pendiente

`metricas_vendedores_fn` todavía deriva una lectura con ventana/propietario
distintos y la presenta bajo rótulo de mes calendario. El contrato debe servir
por total, vendedor y equipo el bundle exacto `operaciones_cartera`,
`nucleo_convertidos`, `nucleo_divisor`, `nucleo_numerador` y
`nucleo_conversion_pct`, agregado desde el wrapper canónico — jamás promediando
porcentajes. Las claves viejas pueden permanecer solo por compatibilidad
temporal y no se publican como exactas.

Pruebas: suma de numeradores/divisores, operaciones de cartera, reasignación,
NULL, precisión decimal y valores mayores a 100 %.

### C0.2 — cerrar F3.4 ante cualquier sonda no confiable — cerrada localmente

El ranking de cosecha oculta hoy solo con `cuadra === false`. Acepta
accidentalmente sondas ausentes, `cuadra=null`, `paridad_nucleo=null` o
`cuadra=true` con paridad distinta de cero.

Predicado único de confianza:

```text
sondas presentes && cuadra === true && paridad_nucleo === 0
```

Cualquier otro estado oculta la cifra. El mensaje puede distinguir descuadre de
falta de verificación. La política gobierna HOY, Ranking, Metas, Gestión y
Directorio. La pantalla principal Conversiones conserva deliberadamente la
cosecha bruta del rango; su detalle mensual sí falla cerrado ante cierres sin
episodio.

### C0.3 — conservar el contrato exacto en las filas — cerrada localmente

El RPC ya sirve divisor, numerador, porcentaje nullable y operaciones de
cartera, pero el schema/mapeo de Gestión descarta parte de esos campos, fabrica
cero desde el valor legado y decide la muestra con activos/convertidos. Además,
la barra compartida recorta visualmente valores superiores a 100 %.

Gate: schema real separado del demo, `number | null`, muestra basada en el
divisor, explicación de cartera y visualización de conversión sin cap. Cubrir
divisor 0 con activos, divisor positivo sin activos actuales, 9,3 %, >100 % y
cartera.

### C0.4 — endurecer el agregado de cartera y su explicación — cerrada localmente

En el contrato real, `cartera` no debe degradar silenciosamente a cero si el
servidor la omite. Debe ser obligatoria y fallar cerrada; el demo puede tener un
schema explícito distinto. El texto general de la fórmula también debe decir
que el numerador incluye operaciones elegibles de cartera.

### Salida de C0

- SHA reconciliado local `30e95f3`, posterior a estos cuatro gates.
- Suites actuales completas y matriz adversaria de sondas verdes.
- Paridad local entre HOY, Ranking, Metas, Gestión y Directorio para el mismo mes.
- Release/estado documentado. Hasta verificar C0.1 vivo, no publicar
  `41987fe` ni abrir el portado de Ficha sobre él.

## Plan adaptado de reintegración

### R1 — aceptación comercial del prototipo R2 — GO local en rama separada

Se usó la preview R2 para decidir jerarquía visual, lenguaje, foco, móvil y
variantes por rol. Los requisitos, pruebas, capturas históricas y exclusiones
quedaron en [[Ficha 360 R2 - aceptacion UX comercial 2026-08-27]]. La rama
separada `4f57db1` añadió evidencia fresca reproducible: 2.372 pruebas, 18/18
E2E y 17 capturas. Esa memoria todavía debe reconciliarse aquí; ninguna
aceptación UX autoriza backend, integración ni producción.

### R2 — abrir una línea nueva desde la base canónica

Después de C0, crear un worktree y una rama nuevos desde el SHA fijado. Emitir
un serial nuevo al comenzar la ejecución; `AVC-F41-360-20260825-R2` queda como
identidad del prototipo y su evidencia.

No fusionar ni cherry-pickear el paquete R2. Portar capacidades, no commits:

- archivos nuevos de ficha/modelo/tests: candidatos a traslado controlado;
- Mi cartera, contratos, PDF, `crm-api`, `crm-queries`, tipos y store:
  reconciliación manual y aditiva;
- `database.types.ts`: regeneración al final, nunca copia ni merge manual.

### R3 — reemitir el servidor desde el esquema actual

Las migraciones R2 `20260825214823` y `20260826164831` son material de diseño,
no archivos ejecutables sobre la historia nueva. Crear migraciones posteriores
a la última vigente al momento de ejecución.

Antes de adaptar cada wrapper: registrar cuerpo, firma, OID, owner, ACL y
dependencias canónicas; conservar locks, autoridad, PDF y hard-delete actuales.
No tocar ni reescribir las migraciones F0–F2.6 ya desplegadas.

Entregables:

- frontera mínima de `crm.cliente_ficha_fn`;
- historial por alcance actual y `revision_contrato` aditiva;
- writers de renovación, upgrade y nueva inversión conectados a
  `crm.operaciones_cartera` sin lógica paralela;
- hardening adaptado a los cuerpos actuales.

Sin acceso a una instancia autorizada, esta fase puede diseñarse y reproducirse
localmente, pero no certificarse ni desplegarse contra producción.

### R4 — portar el frontend aditivamente

Incorporar primero `ficha-comercial`, `cliente-ficha`, su modelo y pruebas.
Después integrar puntos concretos en los archivos canónicos. Mantener
`ClienteDetalle` y `useClienteDetalle` mientras el formulario de corrección o
algún consumidor necesite datos sensibles.

Preservar todo lo incorporado después de R2: F3, teléfono alternativo crudo y
rescate, Supervisor, PDF, separación de historias lead/cliente, PEN/USD y
mutaciones actuales.

Corregir además la dependencia de la zona local del dispositivo: los límites
mensuales de cartera deben usar Lima.

### R5 — cerrar el historial sin truncamiento silencioso

R2 filtra en cliente una colección global limitada a 2.000 operaciones y 100
actividades. Sustituirlo por consulta/paginación por cliente o rotular
explícitamente «movimientos recientes». Probar clientes que superen el límite.

### R6 — gate integrado

- Replay desde cero de migraciones actuales más las nuevas.
- Diff de esquema con allowlist y regeneración de tipos.
- Paridad del núcleo antes/después; suites F1–F3 completas.
- RLS por Vendedor, Supervisor, Gerencia y Directorio; reasignación abierta,
  asesor inactivo, revocación y purga de caché.
- Adaptar y ejecutar las 43 carreras R2 y el caso misma transacción; el runner
  viejo referencia migraciones antiguas y no se reutiliza sin modificación.
- PDF read/materialize, actor híbrido Portal/CRM y exclusión bancaria.
- Suite completa actual, tests R2 portados, E2E y regresiones de teléfonos,
  rescate, Mi cartera, contratos y conversión.
- Caso obligatorio: dos operaciones elegibles del mismo cliente/mes producen
  una sola conversión y ninguna pantalla atribuye las dos.
- Casos de renovación, upgrade dentro/fuera del primer mes y nueva inversión;
  atribución al responsable vigente y ninguna división en el navegador.

### R7 — preview candidata nueva

Construir una preview aislada desde la nueva rama. Compararla con los requisitos
UX aceptados de R2 y realizar aceptación técnica autenticada por cada rol. Esta
es la única preview que puede convertirse en candidata de release.

### R8 — publicación, solo con autorización explícita

Orden: backend aditivo → verificación → frontend → observación → limpieza
diferida. No retirar contratos anteriores en la primera salida. La aprobación
de la preview no autoriza por sí sola cambios de servidor o producción.

## Criterio de cierre

La Ficha queda lista solo con dos aprobaciones independientes:

1. **UX/comercial:** requisitos derivados del prototipo R2 aceptados.
2. **Técnica:** candidato nuevo sobre un SHA canónico posterior a C0, con
   migraciones reemitidas, núcleo inalterado y todos los gates integrados
   verdes.

## Próximo movimiento coordinado

1. Revisar y aprobar/rechazar el SQL exacto reconciliado de C0.1.
2. Con autorización, reproducir todas las migraciones, capturar las 18 huellas
   live y el fingerprint de catálogo/ACL, y recalcular los dos cuerpos
   candidatos; mientras exista un placeholder, el SQL aborta.
3. Ejecutar el banco completo y `EXPLAIN (ANALYZE, BUFFERS)` fuera de producción.
4. Con una autorización separada, aplicar servidor primero y leer de vuelta el
   contrato exacto por rol mediante PostgREST/JWT.
5. Verificar paridad HOY/Ranking/Metas/Gestión/Directorio y recién entonces
   autorizar el frontend resultante de la reconciliación.
6. Fijar el nuevo HEAD y abrir una rama nueva para R2/R3; portar capacidades de
   Ficha 360, nunca fusionar la rama preview antigua.
