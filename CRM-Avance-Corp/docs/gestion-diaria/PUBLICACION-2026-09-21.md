# Gestión Diaria — publicación del 21/09/2026

## Resultado y autorización

**PUBLICADO en https://crm.miavance.com/.** Incluye F4 etapa 1, «Mi equipo hoy»,
y la ampliación F2/F3 que pliega los resultados de llamada y separa resultado,
próxima acción y descarte. No activa cortes, pop-ups, configuración gerencial,
TypeSafe ni las etapas 2–6 de F4. La fase F4 completa no está terminada.

Miguel autorizó expresamente instalar las dos SQL exactas en producción y ejecutar
`$release-crm` si pasaban las verificaciones. Después aprobó e integró el
[PR #62](https://github.com/avanza-digital/avancecorp-crm/pull/62) como `miguejbs98`.
No se eludió el requisito de aprobación, no hubo push forzado ni rama de release.

## Fuente y artefacto

Main local y `avancecorp/main` coincidieron antes de construir y antes de subir:
`526e728e31ff64adaf9b737fa5e408ebe32005a2`. Su árbol es idéntico al candidato
aprobado `c237dc071f4fd3337e6e0bf3a3b227619e4a047f` y al código probado de
`9c402974`. Se construyó con HEAD separado en el taller existente
`/private/tmp/avancecorp-gd-f4-vista.chvRqh`, limpio, sin `--allow-dirty`.

Los 36 archivos ajenos del taller principal conservaron su contenido. Las 101
líneas pendientes del ledger de temperatura se respaldaron, apartaron únicamente
para el fast-forward y restituyeron byte a byte; siguen sin incluirse en el release.
No se publicó la migración de temperatura `20260921034748` ni su Edge Function.

- Release: `crm-20260921T170501Z-526e728e31ff`.
- Build servido: `build-20260921T170500239Z`.
- ZIP: `crm-20260921T170501Z-526e728e31ff.zip`, 2.266.530 bytes.
- SHA-256: `15c7ff107559e80f6064cd545b7906e19a94a75bb2e82ab2be7feeb1e326dc7d`.
- Destino del manifiesto: `crm.miavance.com`; `worktree_sucio=false`.

ZIP y manifiesto están conservados en `CRM-Avance-Corp/releases/` del taller
principal y del taller aislado. `release:crm:verify` PASS antes de subir; la
huella del ZIP siguió idéntica después del despliegue. Estas actas son posteriores
y locales: no atribuirlas al commit del manifiesto ni reconstruir por documentarlas.

El primer intento de empaquetado se detuvo correctamente por falta de variables
públicas en la copia limpia; no produjo un release ni se publicó. Se reconstruyó
con la configuración pública existente del CRM, comprobando el proyecto, la clave
anon/publishable y demo desactivado. No se copiaron secretos al artefacto.

## SQL productivo: instalado y registrado

Destino único: Supabase `dctqcbznekcyxhjujuci`. Se usó `supabase db query --linked
--project-ref dctqcbznekcyxhjujuci --file <archivo-exacto>`, primero F4 y después v4.
No se usaron `db push`, `apply_migration`, SQL ajeno ni reversas productivas.

**F4: `20260921040335_crm_gestion_diaria_equipo_vista.sql`.**
SHA-256 `f9a9aad16a683e1b87118fe03976cb206d752f0f375c93b4dc375e044c49af02`.
Puerta INVOKER `crm.gestion_diaria_equipo_fn(date,uuid)`:
md5 `6fee13c7191e5fc17647f9b684a3630c`.
Núcleo INVOKER: `70d6b23ee4d9f1f397ccfbae8f1dee5a`.
Adaptador privado autorizado de pendientes: `6de28503dd0a32bd98de95d1f5de3532`.

**Resultado: `20260921153654_crm_resultado_llamada_seguimiento.sql`.**
SHA-256 `d863988a96bba84482b1ee0b387d5218dce44b896e69abfb6f2d1479778d8fc8`.
Puerta v4: md5 `cbd0a3da63397507c2312d0cf15c0b8c`.
Núcleo v4: `d6c4407c92e7f38c055653b4a4ead538`.
Gate F2 extendido: `2c7eccd6443a2eb78eefc8e0c196da15`.

Ambas versiones se registraron en `supabase_migrations.schema_migrations` con su
nombre original y un único `statement` igual al archivo completo. El registro
comprueba gates y SHA, rechaza cualquier fila previa diferente y relee el contenido
exacto. No se sustituyeron timestamps ni se registraron cuerpos vacíos.

## Verificación y límites

**PASS — código y ensayos.** `npm run check` repetido sobre el árbol aprobado:
lint, tipos, 4.016 pruebas en 270 archivos, cobertura, build, configuración,
bundle y duplicación 0,50 %. Runner SQL local repetido: 17 grupos, regresiones
F2/F3/F4, 48 mutantes F1–F3, nueve F4 y cinco v4; replay, permisos y reversa con
datos conservados. Ensayo adicional local de descarte junto con veto de contacto
para ambos resultados, cancelación de tareas y replay exacto PASS; fixture en
ROLLBACK, sin modificar los tests versionados ni datos productivos.

**PASS — GitHub.** [CI del PR](https://github.com/avanza-digital/avancecorp-crm/actions/runs/35627252670)
y [CI del commit publicado](https://github.com/avanza-digital/avancecorp-crm/actions/runs/35628873907):
`app-check`, E2E y `verify` aprobados; 231 recorridos aprobados, 26 omisiones de la
suite, cero fallos. Preflight RLS offline aprobado tanto en PR como en Main
([Main](https://github.com/avanza-digital/avancecorp-crm/actions/runs/35628873942)).
Los avisos previos de accesibilidad/React y limpieza de Git en CI no se ocultan
ni se atribuyen a una aprobación del recorrido humano.

**PASS — producción, solo lectura.** Gates Gestión Diaria F1–F4/v4 y los cuatro
gates SLA antes/después. Cinco identidades reales bajo `SET LOCAL ROLE authenticated`:
dos Gerencia ven 18 analistas cada una; tres Supervisores ven 10, 0 y 8. La puerta
F4 devuelve exactamente el roster autorizado, incluyendo cero actividad. Ventana
de 365 días, rechazo de día 366 y equipo ajeno, y entradas v4 vacías comprobados.
Sin identidad y anon rechazados. Se usaron claims de sesión SQL, **no JWT de Auth**;
no presentar esto como una prueba HTTP autenticada. No se crearon llamadas, tareas,
descartes ni otras operaciones de negocio en producción para probar.

**PASS — HTTP anónimo:** ambas RPC por PostgREST con la configuración pública
productiva responden 401 / SQLSTATE 42501. v4 recibió IDs/resultado nulos;
no hubo ninguna intención de negocio ni JWT de una cuenta humana.

Catálogo anterior y posterior idéntico en tablas/ACL/RLS, policies, objetos de
`public`, censo analítico y v3. Huellas: tablas `eafbde1bcb1cce9d9a1f69429eb14f82`,
policies `40d89ca9389bfbab0899cbef71b0c1dc`, funciones públicas
`7373b6c15e5cbd111382a1ddfbc9696f`, censo `e413408ae306ec8a086bf205384c4102`.
V3 `92d2dcfb4cc03c158a42292980226ba2` y núcleo v3
`fec6bfd18b0ca26623f84b55daddef64` intactos.

**Advisors:** rendimiento sin delta. Seguridad añade solamente el aviso esperado
de `crm.registrar_llamada_v4` como DEFINER ejecutable por `authenticated` (213 →
214 de esa categoría). Es intencional: admisión por rol, ámbito y writers sellados;
anon y acceso directo al núcleo están denegados. No se amplían permisos para
silenciarlo. [Descripción del aviso](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).
Los avisos anteriores siguen siendo deuda previa, no «cero avisos».

**PASS — publicación y recursos ejecutables.** Preflight de ancestría y artefacto
anterior; operación oficial Hostinger `hosting_deployStaticWebsite` aceptada.
Portada, `index.html`, `version.json` y los 68 JS/CSS servidos con HTTP 200 y
SHA exacto. Los 106 recursos públicos responden 200; 95 coinciden byte a byte.
`.htaccess` devuelve 403, como corresponde.

**Comprobación ampliada de imágenes, no confundir con igualdad total:** de los
11 PNG con bytes distintos, seis conservan dimensiones y píxeles RGBA exactos
(difieren metadatos/compresión). Cinco logos de aliados se sirven a 1600×1484
frente a 3508×3253 del ZIP. Las once fuentes son idénticas a las del release
anterior; no las modificó esta entrega. Respuestas `server: hcdn`, reducción
proporcional y PNG válidos son compatibles con la optimización documentada por
[Hostinger](https://www.hostinger.com/support/7935917-hostinger-cdn-website-optimization/);
es una inferencia, no una lectura de su configuración interna. No se desactivó CDN
ni se revirtió código por exigir hashes de imágenes transformadas. La comparación
estricta de esos cinco PNG NO pasa y queda separada del smoke del código.

**FAIL previo:** el oráculo histórico F1, caso J, conserva la whitelist anterior
a F3. Reproducido también sin v4; el gate F1 y sus diez mutantes sí pasan. No
se cambió el oráculo para ocultarlo.

**NOT RUN:** matriz general Auth/HTTP remota, recorrido de negocio con analista
y supervisor, e inspección visual de la web productiva: Browser no tenía ninguna
instancia conectada. Los E2E de CI usan fixtures/mocks; no sustituyen esos recorridos.

## Claude y decisión del PRIMARY

Revisión de publicación LEVEL 3 mediante `scripts/claude-review`, solo lectura,
sin herramientas/MCP del reviewer. Dictamen `CHANGES_REQUESTED`, confianza MEDIA;
no se anuncia un PASS de Claude. El PRIMARY lo contrastó con evidencia:

- Posible pérdida de analistas sin llamadas: el núcleo parte de los IDs, agrega
  con LEFT JOIN y devuelve ceros; oráculo y cinco lecturas productivas lo confirman.
- Acceso a `crm.equipo` bajo INVOKER: grants/RLS y recorrido jerárquico contrastados;
  la nueva puerta se ejerció después de instalar bajo las cinco identidades.
- Posible ampliación por el adaptador SLA: el núcleo autorizado ya deriva ámbito
  desde la identidad; oráculos de jerarquía comparan la misma autoridad.
- Replay con tarea/payload diferente: el writer sellado compara la intención y
  rechaza cambios; pruebas de tarea cambiada y cambio de comando PASS.
- Descarte más veto: ensayo local adicional de ambos resultados y replay PASS.

No se repitió la consulta para conseguir un dictamen favorable. Se conservan las
decisiones y correcciones de las revisiones anteriores en las actas de implementación.

## Recuperación y continuación

### Checkpoint y conformidad posterior

Tras la publicación, Miguel respondió «perfecto ahora si me gusta mas, guarda
todo el progreso hasta ahora». Su conformidad con la mejora visible se registra
sin atribuirle recorridos o pruebas que no detalló. Se conserva la evidencia
anterior y el punto de retoma en el plan principal y en el vault mediante un
commit documental local. No incluye los trabajos de temperatura, auditorías u
otras sesiones, ni modifica la versión productiva `526e728e`.

Esta solicitud de guardar no ejecuta otro release, no repite SQL y no inicia F4
etapa 2. El código publicado ya está en GitHub; este checkpoint documental queda
local, pendiente de sincronización por el procedimiento protegido del repositorio.

### Recuperación

Release anterior conservado: `crm-20260920T223427Z-8b3252b48455`, SHA-256
`6e6fe08a71d620aebe6c37ca6811b4f7bc17b1c0a4e49a1c057a6f828c30759d`.
ZIP/manifiesto verificados; sus 67 recursos de código/configuración se comprobaron
contra la web antes del despliegue. Sigue disponible en `CRM-Avance-Corp/releases/`.

V3 permanece operativa para pestañas y recibos antiguos. No retirar v4 ni sus
recibos para resolver un problema visual. Antes de recuperar un frontend anterior,
coordinar los guardados v4 inciertos: una versión antigua puede no entenderlos.
Las reversas SQL son operaciones separadas, no autorizadas automáticamente por
este release; conservan la historia y requieren verificar estado/cuerpos actuales.
La reversa F4 no tiene pin propio: no ejecutarla a ciegas sobre un gate posterior.

Retomar desde [GESTION-DIARIA.md](GESTION-DIARIA.md): recorrido de negocio de
etapa 1 y detalle/registro del analista (etapa 2), sin duplicar lo que ya existe.
No activar cortes ni TypeSafe por esta publicación.
