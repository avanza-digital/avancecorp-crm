---
tags: [gestion-diaria, diseno, ux, plan]
actualizado: 2026-09-27
estado: analista PUBLICADA 27/09 (último build-20260927T191408274Z, commit 8d4be227 — «Llamar» 44 px y «Lo último con este lead») · supervisor y gerencia esperan su plan
---

# Gestión Diaria — diseño VitaNova con los colores del CRM (27/09/2026)

Miguel pidió analizar `CRM-Avance-Corp/GESTION DIARIA/Gestión diaria pantallas.html` y aplicar
ese diseño al CRM **manteniendo los colores del CRM**.

## Qué es el archivo

- Exportación de Claude Design (formato «bundler»: páginas anidadas, comprimidas y en base64).
  Se desempaqueta con `GESTION DIARIA/vista-previa/unpack.mjs`.
- Es **un solo componente** (`Gestion-Diaria`, prop `rol`) con tres vistas de 1440×1000:
  supervisora «Mi equipo hoy», gerente «Toda la clínica hoy» y asesora «¿A quién llamo ahora?».
- Viene de **VitaNova (Clínica Álvarez)**, el proyecto hermano del que el CRM ya heredó su pulido
  (ver cabecera de `app/src/index.css`). Paleta magenta `#9c1a84`, letra Figtree.
- El propio diseño se inspiró en nuestro Gestión Diaria: la vista de asesora dice «el “Mi día” de
  Avance» y sus 7 resultados son los mismos de `lib/resultado-llamada.ts`.

## Conclusión del análisis

La **estructura ya es la misma** que tiene el CRM en producción (tabla + panel del analista con
Resumen/Registro/Pendientes; gerencia que baja de la operación al equipo y al analista; «Ahora» +
«Cola de hoy»). El diseño cambia sobre todo **la presentación y el orden**, no el negocio. Todo se
puede hacer **solo en pantalla, con las consultas que ya existen** (sin migraciones).

Lo que el diseño mejora frente a hoy:

| Vista | Hoy en el CRM | En el diseño |
|---|---|---|
| Supervisor | En pantalla ancha el panel espera «Selecciona un analista»; en laptop (1440 px con menú) el detalle se abre en ventana encima; cifras en texto corrido; barras navy/azul difíciles de leer | Panel ya abierto con quien más atención necesita; 4 cuadros de cifras; barras «contestaron / no contestaron» con número encima; «Últimas gestiones» con chips; avatares con iniciales y chip de nivel en la tabla |
| Gerencia | 8 cifras sueltas; «ayer» y «7 días» escondidos en «Comparar días» | 4 cifras grandes con «Ayer X · 7 días Y» debajo; tabla de equipos «el que más necesita atención primero»; panel del equipo con barras por hora y «Necesitan atención» que lleva directo al analista |
| Analista | «Mi actividad», «Mi seguimiento» y «¿Qué hice hoy?» apilados abajo (vertical) | Franja de 4 cifras arriba; «Ahora» con aire de celular; «Cola de hoy» y «Mi actividad» como pestañas a la derecha (todo en horizontal, sin bajar) |

## Colores y letra (regla de Miguel: los del CRM)

- Magenta → azul de acción `#2563eb` (hover `#1d4ed8`); fondo tenue → `#eaf1ff`.
- Oscuro del «Ahora» y avisos → navy `#111e3d`. Menú lateral: **se queda el navy del CRM**.
- **Sin verde**: «Agendó cita» azul; WhatsApp cian (`#0e7490`); «Volver a llamar» violeta (categoría).
- Nivel «Bien» = navy sobre fondo tenue; «Bajo» = ámbar (decisión del 21/09); rojo solo para lo vencido.
- Letra Plus Jakarta Sans. Palabras del CRM: analista, supervisor, gerencia, cita, lead, producto,
  «primer intento fuera de plazo».
- ~~Adaptación obligatoria a nombre ≥16 px, detalle ≥14 px y controles de 44 px~~ — **REEMPLAZADA
  el 27/09 por Miguel** («hay demasiada letra, no está respetando el diseño, la proximidad está
  mal»): en Gestión Diaria rige la **escala y el aire del diseño** (título 26 px, nombre en «Ahora»
  24 px, filas 14/12 px, cifras 28 px, etiquetas 11 px; piso 11 px). Los controles son compactos
  en escritorio y **crecen a 44 px en pantallas táctiles** (`pointer-coarse`). El piso de 16/14 px
  del 20/09 sigue en las demás pantallas.

Vista previa ya recoloreada (clicable, datos ficticios):
`GESTION DIARIA/Gestión diaria pantallas - colores del CRM.html` · capturas y script en
`GESTION DIARIA/vista-previa/` (`recolor.mjs` la regenera si llega otra versión del diseño).

## Lo que el diseño no dibuja y se conserva

Selector de fecha (hasta 365 días), franja «Cortes y avisos», «Seguimiento completo», pestaña
«Hábitos del equipo», «Registro general», «Comparar días», grupo «Sin conversación», paginación
de la cola con «Siguiente», «Mi seguimiento» y los descartes del analista, avisos de corte.

## Huecos de datos (resueltos sin tocar el servidor)

- Cuadro «WhatsApp» del panel: no hay conteo por tipo en el resumen → se usa «Pendientes».
- Filtros del registro con número: el registro es paginado y no trae totales → chips sin número.
- Gerencia, barras por hora y «Necesitan atención» del equipo: salen de la consulta de detalle
  que ya existe (hoy se carga al abrir un equipo; en F2 también al elegirlo en la tabla).
- Columna «Citas» del supervisor: existe por analista (`marcador.citas_agendadas`, agendadas hoy);
  no confundir con `citas_hoy` (citas programadas para hoy). El nivel también viene del servidor
  (`marcador.nivel`).

## Plan detallado (propuesto 27/09 — el de analista ya está aprobado e implementado)

Reglas de todas las fases: solo pantalla (sin migraciones ni permisos), mismas consultas y cifras;
escala de letra y aire del diseño (decisión del 27/09; 44 px en pantallas táctiles); colores del CRM sin verde; piezas comunes hechas una sola vez;
Miguel lo ve en su computadora antes de publicar; publica con `/release-crm` (lo lanza él); una fase
a la vez, aprox. una sesión de trabajo cada una.

1. **Base visual + Supervisor «Mi equipo hoy».** Piezas comunes (franja de cifras, cuadro de cifra,
   etiquetas de nivel/resultado/tiempo/tipo, iniciales, barras por hora 08–20 con número encima,
   pestañas subrayadas, filtros en pastilla, avisos rojo/ámbar, pie de tabla). Cabecera con
   «Actualizado HH:MM» conservando fecha, «Hoy», «Seguimiento completo», «Actualizar» e «i». Franja de
   5 cifras. Tabla: iniciales, Llamadas, Contacto + nivel, **Citas agendadas** (sustituye a
   «Pendientes», que queda en la franja y el panel), Vencidas en rojo, Atención con el motivo en
   palabras; «Registro del equipo» pasa a la barra de la tabla. Panel abierto solo con quien más
   atención necesita (pantalla ancha, sin mover el foco): avisos → Pendientes, 4 cuadros (Llamadas,
   Contacto, Citas, Pendientes), barras, últimas 3 gestiones, «Ver el registro del día». Registro,
   Pendientes, «Registro del equipo» y «Cortes y avisos» con el estilo nuevo. Meta: panel al lado a
   1440 px con menú abierto; si con 16 px no cabe, se abre encima como hoy. **Gerencia y analista no
   cambian.** Lo ve en modo demo.
2. **Gerencia «Toda la operación».** 4 cifras con «Ayer · 7 días»; «Comparar días» conserva las 8.
   Tabla de equipos (iniciales, «N analistas · N sin registro», Llamadas, Contacto + nivel, Citas,
   Vencidas, Atención = cuántos analistas la necesitan), ordenada por atención. Panel del equipo: 4
   cuadros, barras del equipo, «Necesitan atención» (cada persona abre el equipo con ella elegida),
   primer intento y dispersión, «Ver el equipo». Dentro del equipo, la vista de F1 con la ruta
   «Toda la operación / Equipo». Se quedan fecha, «Consultar», «Hoy», «Registro general» y «Hábitos
   del equipo». El modo demo no tiene tablero de gerencia: lo ve con su cuenta en la copia local
   (solo lectura) o tras publicar.
3. **Analista «¿A quién llamo ahora?» (aspecto y orden).** Franja de 4 cifras en lugar del recuadro
   «Mi actividad»; «Ahora» con aire de celular; a la derecha pestañas «Cola de hoy · N», «Mi
   actividad» y «Mi seguimiento». Cola con filtros en pastilla (Todo, Sin primer intento, Vencidas,
   Hoy, Sin conversación) y paginación con «Siguiente». Se van los plegables de abajo. El resultado se
   sigue registrando como hoy. Lo ve en modo demo.
4. **Resultado dentro de «Ahora».** Tras «Llamar», los 7 resultados en la tarjeta; al elegir uno, en
   la misma tarjeta los pasos que ya existen (motivo, próxima acción con fecha y hora, 2.º número /
   descartar / reintentar); al guardar pasa sola al siguiente; «Cerrar sin registrar». Lo que se
   guarda no cambia (misma función, mismo deshacer). Codex nivel 3 y prueba de «guardar sobre la
   persona correcta» cuando la cola se refresca con la tarjeta abierta.

Al cerrar: retirar estilos que ya nadie use; vault y el **mismo tablero de Figma** de Gestión Diaria
al día.

Comprobación de cada fase: `npm run check`, E2E en Docker, `revisor-a11y`, Codex (nivel 2; nivel 3 en
F4), prueba en el estado de producción vacío/degradado (gate de realidad) y recorrido tras publicar.

**Qué NO cambia:** base de datos, cálculos y reglas (contacto = contestaron ÷ útiles, nivel desde 5
útiles, «vencida» la decide el servidor), permisos, menú navy y barra superior, otros módulos, lo que
se guarda al registrar una llamada.

## Decisiones de Miguel (27/09, cerradas — no volver a preguntar)

- **Orden (cambiado por Miguel el 27/09):** **analista primero**, con **un plan por pantalla**
  (analista → supervisor → gerencia). Las piezas visuales comunes nacen en el plan del analista.
  Nada se empieza sin su OK explícito a cada plan, y **Codex revisa cada plan antes** («recuerda
  siempre usar a codex»).
- **Gerencia:** 4 cifras como el diseño (Llamadas, Contacto, Citas, Sin actividad) con «Ayer · 7 días»;
  útiles, contestadas, leads distintos y llamadas por lead quedan en «Comparar días».
- **Analista:** el resultado se registra **dentro de «Ahora»** (los 7 tras «Llamar»), con los mismos
  pasos de motivo y fecha. Reemplaza la decisión del 21/09 («Registrar resultado» tras «···»).

## Plan de la pantalla del analista — v2 tras Codex (27/09, APROBADO e IMPLEMENTADO en local)

Base técnica: `screens/gestion-diaria/analista.tsx` (PanelAhora, Actividad, Compromisos,
Descartados), `components/gestion-diaria/cola-de-hoy.tsx` (4 grupos en Tabs, 5 filas/página),
`registrar-resultado.tsx` (Dialog; también lo usan ficha, Hoy, colas y composer),
`components/app/contacto.tsx` (laptop: «Llamar» copia el número y abre el registro; celular: `tel:`
y pregunta al volver ≥4 s). Pruebas: `analista.test.tsx` (41), `registrar-resultado.test.tsx` (14),
E2E `gestion-diaria-analista`, `-cola`, `-resultado`, `gestion-diaria`.

**Revisión Codex del plan v1** (encargo `docs/encargos/2026-09-27-codex-plan-analista-diseno.md`):
**BLOCK**, confianza HIGH, 6 hallazgos — **todos aceptados** tras verificarlos en el código:
1. **P0** A3 no fijaba la identidad de la escritura: «congelar la selección» no basta porque `fila`
   se recalcula con reloj/día/cola (`analista.tsx:113-143`); hoy el diálogo se salva porque `panel`
   guarda `{lead, tarea}` (`:80`, `:351`). En celular el pendiente vive en la instancia de
   `AccionesContacto` (`contacto.tsx:122-158`): si la tarjeta cambia de lead durante la llamada,
   `key={lead.id}` lo desmonta y se pierde la pregunta (riesgo que YA existe hoy con la fila
   autoelegida). → **Sesión de llamada inmutable** creada al pulsar «Llamar».
2. **P1** «Todo» choca con `activa = elegida.grupo` (`:132-144`) y el salto tras guardar
   (`:215-221`). → `FiltroCola = 'todo' | GrupoDia` separado de `fila.grupo` + regla del siguiente.
3. **P1** A2 no listaba los estados vivos (alert de cola caída `:312-315`, `cartera_truncada`
   `:317-320`, «?» y «N+» `cola-de-hoy.tsx:86-100`, «Ver todas las oportunidades» `:135-140`,
   «Buscando su número…» `:433-435`, `aria-current`/«Elegido» `:107-128`). → lista explícita.
4. **P1** El modo tarjeta pierde el contrato de teclado/foco del Dialog (atajos acotados a
   `[role=dialog]`, `registrar-resultado.tsx:173-198`). → contrato propio sin fingir un diálogo.
5. **P2** Destino de «¿Qué hice hoy?» (`gestion-diaria.tsx:80-84`, fuera de la pantalla),
   `Actividad`, Descartados, Compromisos y «Seguimiento completo» sin especificar. → matriz.
6. **P2** «Se apila como hoy» contradecía «horizontal» y faltaba criterio para 1440×900/zoom. →
   horizontal desde `lg` (1024 px) como hoy; una columna solo bajo `lg` (reflujo WCAG 1.4.10).
Arquitectura (aceptado): extraer la lógica de `RegistrarResultado` a un hook/controlador probado;
el Dialog queda como adaptador SIN cambiar su contrato y la tarjeta es un segundo adaptador.

- **A1 · Piezas comunes:** cuadro de cifra y franja, etiquetas (tiempo, nivel, resultado),
  iniciales, barras por hora (contestaron/no contestaron, número encima, 08–20), pestañas
  subrayadas y grupos en pastilla (siguen siendo `tablist`/`tab` para lector y E2E).
- **A2 · Aspecto y orden (publicable sola; el Dialog de resultado intacto):**
  - Cabecera: título, corte, **fecha**, «Actualizar»; navegación «Resumen del día / Seguimiento
    completo» integrada en la cabecera con la MISMA ruta hash y `aria-current` (patrón
    `cabeceraIntegrada` que ya usan supervisor y gerencia).
  - Franja de 4 cifras (Llamadas; Contestaron de N; Contacto + nivel o «se juzga desde N útiles»;
    Citas agendadas). Matriz de destino: `Actividad` → cifras a la franja + barras y «cómo se
    cuenta» a la pestaña «Mi actividad»; `RegistroActividad` («¿Qué hice hoy?», hoy en el
    contenedor) → pestaña «Mi actividad» bajo las barras, SIN duplicarlo en el contenedor;
    `Descartados` → «Mi actividad», solo si hay, foco tras «Deshacer» al título de la sección;
    `Compromisos` → pestaña «Mi seguimiento».
  - Cola: `FiltroCola` con «Todo» por defecto. Elegir desde «Todo» NO cambia el filtro; con un
    filtro de grupo se conserva lo de hoy (el filtro sigue al lead si cambia de grupo). Regla del
    siguiente: al guardar, «Ahora» pasa a la fila que ocupa el lugar del guardado en la lista
    activa (o la última si era el final). «Ahora · k de N» sobre la lista activa; «N+» si `hay_mas`.
  - Se conservan (criterios de aceptación): alert de cola caída fuera de las pestañas; aviso de
    `cartera_truncada`; conteos «?» (desconocido ≠ 0) y «N+»; «Ver todas las oportunidades»;
    «Buscando su número…» y su error; `aria-current` + «Elegido» visible; `role=status` al paginar;
    vacíos que encaminan a la acción.
  - Arreglo incluido: al pulsar «Llamar», la tarjeta **se fija en esa persona** (`elegido`) para que
    la vuelta del celular no pierda la pregunta.
  - Disposición: horizontal desde `lg` (1024 px), una columna solo por debajo (celular, zoom
    200 %). A 1440×900 sin scroll de página: si una lista no cabe, se desplaza dentro de su tarjeta.
    8 filas por página.
- **A3 · Resultado dentro de «Ahora» (publicable aparte; no sale sin cumplir la invariante):**
  - **Sesión de llamada inmutable** creada al pulsar «Llamar», antes de copiar o de salir a `tel:`:
    `{sesionId, leadId, snapshot del lead, tareaId autoritativo (resuelto por id si no está en el
    store)}`. Tarjeta, guardado, reintento `sinConfirmar` y salto operan SOLO sobre la sesión; se
    ignoran completados asíncronos de sesiones cerradas; se libera solo al cancelar o con la
    confirmación real del servidor. La instancia de `AccionesContacto` de la sesión no se desmonta
    mientras dura.
  - Contrato de teclado/foco: atajos 1–7 escuchados en el `ref` de la tarjeta, solo con el foco
    dentro, excluyendo campos, modificadores e IME (`ES_CAMPO`); sin `role=dialog` falso; Escape =
    «Cerrar sin registrar» salvo durante el envío; foco inicial a los resultados; al cancelar vuelve
    a «Llamar»; al confirmar va al nombre del siguiente; `aria-disabled` en controles con foco.
  - Arquitectura: hook/controlador común + dos adaptadores (Dialog sin cambios, tarjeta nueva).
  - WhatsApp sin cambios. Codex nivel 3 sobre el código antes de publicar.
- **Pruebas nuevas (criterios de aceptación):** «Todo» (selección, páginas de 8, «N+», «?», cola
  caída, truncada, lead que cambia de grupo, salto tras guardar desde cada página); A3 (refetch de
  día/cola con la tarjeta abierta, tarea autoritativa no cargada, dos guardados rápidos, respuesta
  tardía de sesión cerrada, `sinConfirmar` sin salto y reintento exacto); celular (vuelta antes y
  después de 4 s, refresco con el marcador abierto, WhatsApp sin regresión); teclado y lector
  (1–7 dentro/fuera, nota, Escape, foco al abrir/cancelar/guardar, anuncio al paginar); estado de
  producción (día vacío, cola caída con y sin «sin conversación», `cartera_truncada`, `hay_mas`,
  teléfono ausente/fallido, métricas sin datos); visual (1440×900, 1440×1000, zoom 200 %, móvil).
- **Publicación:** antes de cada etapa, preflight del proyecto (integrar remoto, `main` =
  `avancecorp/main`, construir desde ese commit).

## Estado de la pantalla del analista (27/09 — PUBLICADA en crm.miavance.com)

- **Commits en `main` local:** `160fdd00` (A1 + A2: piezas comunes, franja, cola «Todo» de 8 filas,
  pestañas a la derecha), `28cf6438` (A3: resultado dentro de «Ahora» con sesión de llamada
  inmutable), `dd5acb5e` (arreglos de las revisiones).
- **Publicada el 27/09 a las 13:05 Lima** por `/release-crm` de Miguel: artefacto
  `crm-20260927T180506Z-db29ecdd96cf`, build `build-20260927T180505461Z`, commit `db29ecdd`
  (contiene el vivo anterior `88db9ebf`, #113; frente a él solo cambian los 3 commits de arriba).
  Construida en un worktree limpio: el trabajo sin commitear de la otra sesión (citas por equipo)
  quedó fuera. Check sobre ese árbol PASS (4512 pruebas), manifiesto `ARTEFACTO_OK`, preflight OK.
  Humo: inicio 200, `version.json` nuevo, `index-hlHxLrnn.js` igual al del build y **104/117
  archivos idénticos byte a byte**; los 12 PNG distintos son la recompresión de la CDN
  (`server: hcdn`, `-imm-edge5`; iguales en el release anterior y en este). Huellas de la
  configuración (URL de Supabase, clave pública y DSN de Sentry) idénticas al build anterior.
- **Paso 1 del release:** `main` local iba 73 commits por delante de `avancecorp/main` (lo de
  Gloria, que se queda solo en local, más notas y estos commits) y 0 por detrás. Miguel siguió
  tras el aviso. A GitHub va por la **PR #115** (rama `integra/gestion-diaria-analista-20260927`,
  commit `d3064076` sobre `avancecorp/main`): solo los 29 archivos de este trabajo, `app/`
  idéntico byte a byte al publicado, sin lo de Gloria ni las citas por equipo de otra sesión;
  pre-push 4512/4512. Al fusionarla (squash): traer `avancecorp/main` al `main` local y borrar la rama.
- **Segundo ajuste, publicado el 27/09 a las 13:39 Lima — el teléfono a todo el alto.** Miguel:
  «que el módulo del teléfono sea más largo… ese pequeño dash se corre a la derecha y el teléfono
  sube hasta donde dice ¿a quién llamo ahora?». Desde `lg`, el teléfono ocupa la columna izquierda
  en todo el alto (≈530 → ≈700 px a 1446×818); título, avisos, franja de cifras y pestañas a la
  derecha, con el MISMO orden del DOM (grid). Cabecera: título en la fila de la fecha y los botones,
  subtítulo debajo (`order-last`). En reposo, número y acciones al pie del teléfono (pantalla de
  llamada); con el resultado abierto caben las 7 opciones. Celular sin cambios.
  Commit `4396acfc` sobre el vivo `db29ecdd` (rama de publicación, ya fusionada en `main` con
  `d53df94d` y borrada): **no se publicó la punta de `main`** porque llevaba trabajo de otras
  sesiones sin publicar — `3e6c3587` (citas por equipo, migración `20260927172931` NO aplicada) y el
  «Hoy del supervisor» F1–F3 «sin conectar». Artefacto `crm-20260927T183849Z-4396acfcb46d`, build
  `build-20260927T183847624Z`; check PASS (4512) sobre ese árbol, manifiesto OK, preflight OK contra
  `db29ecdd`, configuración idéntica; humo 200, índice `index-Br7FaJ8z.js` = build, 104/117 byte a
  byte + 12 PNG de la CDN (iguales al release anterior).
- **Tercer ajuste, publicado el 27/09 a las 14:14 Lima — «Llamar» de 44 px y «Lo último con este
  lead».** Miguel: «el botón de llamar está muy grande» y «hay espacio en blanco… poner información
  relevante para el seguimiento, la última actividad o el último seguimiento». «Llamar» pasó de
  52 a 44 px de alto (la altura de WhatsApp; 44 es el mínimo táctil). En el aire del teléfono, «Lo
  último con este lead»: las **2** últimas gestiones (tipo, resultado, nota y hace cuánto), sin
  movimientos del sistema, con «Ver todo» a la ficha; sale del historial por lead de la ficha
  (`useActividadesDeLead`, sin consultas nuevas). Con 3 no cabía junto a «Correo». Estados: cargando,
  fallo con «Reintentar», vacío («esta llamada será la primera»); nunca «sin gestiones» por no
  saberlo. Se oculta con el resultado abierto; acciones `sticky` al pie en pantallas bajas. Los
  iconos de las gestiones y el «hace X» se unificaron en `components/app/actividad-visual.ts` (había
  dos copias: ficha y directorio). Commit `8d4be227` sobre el vivo `4396acfc` (fusionado en `main`
  con `9b060fba`); check PASS (4516, 4 pruebas nuevas); E2E dirigida en Docker 88 PASS / 13 saltadas
  / 1 FALLO: `gestion-diaria-horizontal-h5` (supervisor, `resumen_cartera_fn` 2 vs 1 con 32
  analistas) en el taller compartido con cambios SIN COMMITEAR de la sesión del supervisor; sobre el
  árbol exacto del release (`8d4be227`) pasa 2/2. Artefacto `crm-20260927T191408Z-8d4be227d676`,
  build `build-20260927T191408274Z`; manifiesto OK, preflight OK, configuración idéntica; humo 200,
  índice `index-DjRxOV9u.js` = build, 104/117 byte a byte + 12 PNG de la CDN.
- 🔴 **Docker E2E compartido:** dos corridas de la suite completa murieron con código 143 (parada
  desde fuera) mientras otras dos sesiones corrían las suyas: mi contenedor llevaba la etiqueta
  genérica `crm-e2e`. Correr con `CRM_E2E_TASK=<propia>` y, con Docker ocupado, specs dirigidos.
- 🔴 **Lección: el primer rediseño rompió `e2e/foco-alto-contraste.spec.ts`**, que buscaba las filas
  por la estructura vieja de la cola (listas por grupo). Yo solo había corrido los specs de Gestión
  Diaria + SLA; otra sesión lo ajustó a la pestaña «Cola de hoy» (`59fceade`). No era un fallo de
  la pantalla, pero sí un hueco de verificación: **al cambiar la estructura de una pantalla, correr
  la suite E2E completa** (o buscar en TODOS los specs los selectores que cambian).
- ⚠️ **Para el próximo `/release-crm`:** el `main` local ya lleva trabajo de otras sesiones SIN
  publicar: `3e6c3587` (citas para supervisores por equipo, que depende de la migración
  `20260927172931`, NO aplicada) y el «Hoy del supervisor» F1–F4 (`b862ac80` lo CONECTA). Un build
  desde `main` los publicaría: la migración va ANTES (orden de despliegue por dirección) y conviene
  que esa sesión confirme H5 (arriba). Mis tres releases de hoy se construyeron sobre el vivo, no
  sobre la punta de `main`.
- **Revisiones:** Codex del plan (BLOCK, 6 hallazgos, todos aceptados) y del código
  (CHANGES_REQUESTED: P1 Escape durante el envío → guardia síncrona `estaEnviando`; P2 cerrar
  sin registrar con un grupo filtrado → «Ahora» vuelve a la persona llamada; ambos con prueba
  mutante que los atrapa). `revisor-a11y`: grupos con nombre, radios con nombre por instancia,
  `aria-disabled` en controles con foco, scroll dentro del panel de la pestaña, 44 px táctiles.
- **Verificación:** `npm run check` PASS (303 archivos, 4513 pruebas, sin avisos nuevos); E2E en
  Docker de Gestión Diaria + SLA **62/62 PASS** (incluye 1440×900 sin scroll de página y celular).
- **Cómo verlo:** en producción, entrando como analista → Gestión Diaria; en local, `npm run dev` en
  `app/` → «Explorar en modo demo» → Analista → Gestión Diaria.
- **Diferido (menor, ya existía o no bloquea):** el nombre accesible de «Llamar» sigue siendo
  «Copiar el número de X y registrar la llamada» (cambiarlo toca muchos specs); el lector lee
  raro «1–8 de 23»; «Ver más» del registro en modo normal tiene el mismo detalle de foco que se
  arregló en el compacto; sumar `@axe-core/playwright`; actualizar el tablero de Figma.
- **Siguiente:** Miguel la mira en producción y fusiona la PR #115; traerla al `main` local. Después, plan de **supervisor** (revisado por Codex antes de tocar código) y luego gerencia.

## Plan de la pantalla del SUPERVISOR — v2 tras Codex (27/09, ESPERANDO OK de Miguel)

Base: `screens/gestion-diaria/supervisor.tsx` (+ `supervisor.css`, compartido con gerencia vía
`gerencia.tsx:22`), `tabla-equipo-diaria.tsx`, `panel-analista-supervisor.tsx`,
`panel-supervisor-adaptable.tsx` (portal en línea ↔ ventana; hoy ventana si `clientWidth < 1236`),
`detalle-analista.tsx` (8 métricas + gráfico propio), `ultimas-gestiones-supervisor.tsx` (pide 25,
muestra 3). Datos: una foto `gestion_diaria_equipo_fn` (`useDiaEquipo`); registro, pendientes y avisos
con sus consultas propias. **Solape con el «Hoy del supervisor» de otra sesión (`#/hoy`,
`supervisor-mando.tsx`): ningún archivo en común; el mando no muestra la actividad del día y enlaza a
`#/gestion-diaria` «Mi equipo hoy» (su test lo exige) → mantener ruta y nombre; no tocar `screens/hoy/*`,
`lib/senal-equipo.ts`, `lib/cola-supervision.ts`, `lib/tres-cosas.ts` ni la API de `Avatar`.**

**Revisión Codex del plan v1** (encargo `docs/encargos/2026-09-27-codex-plan-supervisor-diseno.md`):
CHANGES_REQUESTED, confianza HIGH, 7 P1 + 3 P2 — **todos aceptados**:
1. P1 Selección automática sin máquina de estados (`seleccion === null` significa cierre, cambio de
   fecha, fuera de ámbito o transición de `registroPedido`; `modal = seleccion && (estrecho||ampliado)`
   → abriría una ventana y movería el foco al estrecharse). → Origen de la selección
   (`automatica`/`usuario`/`aviso`), `registroPedido` manda, nada automático con carga/error/42501/
   petición pendiente/`dia ≠ fecha`, cierre voluntario o salida de ámbito lo inhiben, una automática
   que pasa a estrecho se CIERRA sin ventana, solo filas visibles con los filtros, sin reutilizar un
   `origen` viejo.
2. P1 El umbral ~1100 choca con la cuadrícula (840 tabla + 380 panel + 16 = 1236; `@container
   max-width:1235px`; tarjetas por debajo de 839; gerencia comparte clases). → Cuadrícula nueva SOLO
   del supervisor (clases/contenedor propios) con anchos exactos; umbral = mínimo real de tabla +
   panel; gerencia conserva los suyos. Verificar 1440 y 1280 con menú abierto/cerrado, 1366, 1512,
   zoom 200 %, con barra de scroll y al cambiar de ancho con el foco dentro.
3. P1 La reutilización rígida quitaba funciones a GERENCIA (compara Pendientes por analista; su
   panel solo tiene Resumen y Registro; `DetalleAnalista` muestra `citas_hoy` «Citas pendientes del
   día», ≠ `citas_agendadas`; su registro abre filtrado a llamadas). → **Gerencia NO cambia en este
   plan**: tabla con columnas por contexto (`supervisor`: Citas; `gerencia`: Pendientes, como hoy),
   resumen nuevo SOLO en el supervisor, acciones inyectadas; `DetalleAnalista` sigue en gerencia
   hasta su plan (entonces se unifica).
4. P1 «Atención»: prioridad y color sin contrato (el orden actual cuenta motivos antes que
   gravedad; `primer_intento_vencido`/`datos_incompletos` son `null` sin SLA activo). → Matriz
   (fuente · disponible · texto · color · prioridad): tareas vencidas (rojo, 1) → primer intento
   fuera de plazo (ámbar, 2; solo con SLA activo) → cortes pendientes (ámbar, 3; solo hoy) → más de
   2 h sin llamar (ámbar, 4) → datos por revisar (ámbar, 5). El total «Necesitan atención» de la
   franja va en ÁMBAR (mezcla señales; el rojo queda para lo vencido); el orden «Atención» y la
   selección automática del supervisor usan esa prioridad.
5. P1 «Sin muestra» ambiguo. → Tres estados: 0 útiles «— · Sin llamadas útiles»; insuficiente
   «Sin muestra suficiente · N útiles; mínimo M»; evaluado «% · nivel · N útiles».
6. P1 Contratos de a11y. → `aria-sort` y nombre de la tabla; scroll de tabla y panel alcanzable y
   con nombre; anillo de la casa y prueba en `forced-colors`; `aria-disabled` + guarda en «Hoy» y
   «Actualizar»; `role=status` en conteos; `panelEnfocable` decidido por pestaña.
7. P2 «Registro del equipo» desaparecía con el equipo vacío. → La barra existe con foto válida
   aunque haya 0 analistas; los filtros solo con filas; la acción siempre (habilitada con foto y
   permiso).
8. P2 Estados de S3. → Tabla de estados: carga inicial, recarga fallida con datos previos, error sin
   datos, 42501 (retira datos), equipo vacío, actividad cero, cortes ausentes/desactivados/día no
   laborable, fecha histórica («Cortes del día»); los textos de la «i» se conservan.
9. P2 Cifras que no cuadran. → Nota compacta junto a las barras (incluyen contestaciones no útiles) y
   al registro (solo leads visibles hoy); `horarioConfirmado` antes de `BarrasPorHora`.
10. P1 Pruebas. → Migración por fase con cobertura equivalente: S1 tipografía (piso 11 px como el
    analista), alto de fila, columnas, `aria-sort`; S2 barras nuevas, foco del panel adaptable y
    selección automática; S3 suite completa tras retirar CSS. `gestion-diaria-horizontal-h5` se
    estabiliza (medir tras asentarse las consultas) o se reporta FAIL: el historial no lo convierte
    en PASS.

**Fases (v2):**
- **S1 · Cabecera, cifras y tabla** (solo supervisor): cabecera del diseño conservando fecha (365
  días), «Hoy», «Seguimiento completo», «Actualizar» e «i»; franja de 5 cifras (`FranjaCifras`,
  atención en ámbar); barra siempre presente con «Registro del equipo»; tabla con iniciales, Llamadas,
  Contacto (3 estados), **Citas** (`marcador.citas_agendadas`), Vencidas (rojo), **Atención en
  palabras** (matriz) y orden por gravedad; pie «N de N · Actualizado» + «La actividad registrada no
  acredita presencia». Pruebas migradas; H5 estabilizada o FAIL.
- **S2 · Panel al lado**: cuadrícula propia con umbral exacto; selección automática con su máquina
  de estados; cabecera con iniciales; pestañas subrayadas; Resumen con aviso de vencidas, 4 cuadros
  (Llamadas, Contacto, Citas agendadas, Pendientes — no WhatsApp: no existe por analista),
  `BarrasPorHora` con guarda y nota, línea compacta de las métricas que hoy da `DetalleAnalista`,
  últimas 3 gestiones con chip de resultado, «Ver el registro del día».
- **S3 · El resto + limpieza**: registro (modo normal, conserva el filtro de etapa), pendientes,
  «Registro del equipo», cortes y avisos, «i» y la tabla de estados; retirar solo el CSS que ya no
  use nadie (gerencia incluida).

**Diferidos:** unificar gerencia con estas piezas (su plan); enlace «Ver su día» del Hoy del
supervisor que abra al analista directo (archivo de esa sesión; el router ya admite
`{tipo:'analista', id}`); alinear el vocabulario de atención con el mando («Primera gestión vencida»).

Relacionado: [[Gestion Diaria - UX gerencial publicada y verificada (2026-09-25)]],
[[Mi dia del analista - dos columnas y foco accesible (2026-09-21)]],
[[Gestion Diaria - supervisor horizontal aprobado (2026-09-23)]], [[Fundamentos UX del CRM]].
