# F4 · Etapa 1 — Vista del equipo

Estado al 21/09/2026: **ETAPA 1 PUBLICADA**, con SQL instalado y registrado.
Fuente `526e728e31ff64adaf9b737fa5e408ebe32005a2`, PR #62, release
`crm-20260921T170501Z-526e728e31ff`. Preparada en un taller aislado y publicada
desde Main sincronizado y fuente limpia, conservando los trabajos ajenos.
Acta vigente: [PUBLICACION-2026-09-21.md](PUBLICACION-2026-09-21.md).
F4 completa no está cerrada; faltan etapas 2–6 y el recorrido humano de etapa 1.

## Objetivo y límites

Mostrar a todos los analistas activos del equipo autorizado, aunque no tengan
cartera, llamadas o actividad. Distinguir actividad registrada, pendientes y
motivos concretos para intervenir. No inferir presencia ni causas de ausencia.

Se reutiliza el núcleo de llamadas de F3. El roster y los agregados son completos
y proceden del servidor; la caché parcial del navegador no decide los pendientes.
Los primeros intentos vencidos se componen desde el núcleo autorizado existente.
Los pendientes son actuales, aunque se consulte actividad de una fecha anterior.
Los cortes, avisos emergentes, configuración gerencial y TypeSafe son entregas
posteriores; esta etapa no los simula ni los activa.

## Diseño revisado contra el plan

Paleta existente: navy #111e3d, azul #2563eb, fondo #f8fafc, papel #ffffff,
ámbar #92400e para atención y rojo oscuro #991b1b sólo para plazos vencidos. Se usan los
tokens del CRM, Plus Jakarta Sans y texto de al menos 16 px. Sin verde.

La comparación por analista manda: una tabla, alineación izquierda para nombres
y motivos, números alineados a la derecha. El resumen es una frase operativa,
no una colección de tarjetas. Búsqueda y filtro a la misma altura. Las métricas
secundarias se despliegan, sin encoger el texto. El registro existente se abre
con el analista seleccionado. En móvil el desplazamiento queda dentro de la tabla.

```text
Mi equipo hoy                          Actualizar
Personas con actividad / pendientes / atención
Buscar analista                 Con problema hoy
Analista | Llamadas | Contacto | Pendientes | Atención
         Detalle desplegable y acceso al registro
```

## Qué permite esta entrega

El supervisor ve el equipo activo completo, incluidos los analistas sin cartera,
llamadas ni gestiones. Las relaciones jerárquicas atraviesan miembros intermedios
inactivos sin perder descendientes autorizados. Los ciclos accidentales no hacen
infinita la consulta y nunca se incorporan miembros de un equipo ajeno.

Cada fila distingue actividad registrada, llamadas y contacto, tareas pendientes
y vencidas, primeros intentos fuera de plazo y motivos concretos de atención.
El detalle muestra llamadas útiles, leads distintos, llamadas por lead, citas
pendientes del día, primera/última llamada y última gestión. Buscar, ordenar y
filtrar «Con problema hoy» no cambia el resumen de todo el equipo. Una tasa sin
muestra suficiente queda al final en ambos sentidos de ordenación.

La actividad humana incluye llamadas, WhatsApp enviado, citas realizadas, notas
y conversiones. Los WhatsApp recibidos, cambios de etapa y reasignaciones no se
atribuyen como trabajo humano. Esto es distinto del registro crudo de F1, que
conserva también esos sucesos. El oráculo detecta tipos nuevos sin clasificar.

El registro de F1 se abre por analista o por equipo. El foco va a su encabezado y
vuelve al botón al cerrar. Las filas tienen cabeceras y grupos semánticos para
lectores de pantalla. La tabla desplaza horizontalmente en móvil sin ensanchar
la página; las cifras principales mantienen al menos 16 px.

La consulta se actualiza cada minuto, al recuperar conexión y al volver a la
ventana. Un error o una revocación oculta los datos anteriores; no los convierte
en cero. Demo y sesión ausente no llaman al servidor al pulsar Actualizar.

## Servidor y reversibilidad

Migración instalada y registrada el 21/09 con autorización expresa:
`supabase/migrations/20260921040335_crm_gestion_diaria_equipo_vista.sql`.
La puerta y el núcleo son INVOKER. El adaptador privado de pendientes usa el
núcleo SLA autorizado sin recibir identificadores arbitrarios. Los cuerpos y
permisos están sellados; no se crean tablas, políticas ni escrituras de negocio,
ni se modifican objetos del portal. Se mantiene el censo analítico anterior.

Destino de ensayo exclusivo: `gestion_diaria_f4_vista_chvrqh` dentro de
`supabase_db_avancecorp-f5-bank`. Los fixtures se revierten mediante ROLLBACK.
La reversa restaura exactamente el gate F3 anterior y retira sólo los objetos
nuevos de F4; la reinstalación produce las mismas huellas.

## Revisión independiente y decisiones

Claude revisó la candidata mediante `scripts/claude-review`, sin herramientas
ni escritura. La primera consulta no produjo un dictamen válido. La segunda
devolvió `CHANGES_REQUESTED`; no se presenta como una aprobación final.

Se reprodujo y corrigió su hallazgo de pérdida de descendientes activos bajo un
puente inactivo: la versión anterior falla `test-jerarquia.sql` y la corregida
pasa. También se aplicaron la asociación semántica de las filas y la gestión de
foco. El marcador devuelve campos enumerados explícitamente, y la política de
umbrales se consulta después de autorizar al actor.

La hipótesis de ceros falsos en SLA se contrastó con las definiciones instaladas
de `sla_operacion_autorizada`, `vendedor_ids_visibles` y `es_lector_global` y con
un oráculo por supervisor, gerencia y lector global. Los agregados coinciden con
el núcleo completo bajo la misma identidad; cuando no hay evaluación se entrega
NULL. No se duplica el cálculo SLA en el navegador. La clasificación de actividad
es intencional y queda comprobada; no se exige igualdad con el registro crudo.

## Evidencia de verificación local, anterior a publicación

PASS: `node supabase/scripts/gestion-diaria-equipo/ensayar.mjs` desde el CRM.
Ensaya tres oráculos SQL con `SET ROLE authenticated`: equipo completo, equipos
ajenos, vendedor/coordinador denegados, revocación, 31 llamadas/29 útiles/13
contestadas, nivel calculado sin redondeo, 270 tareas sin truncar, acciones
humanas frente a sucesos automáticos, puente inactivo y ciclos, selección de
equipo por gerencia/lector global y fechas hasta 365 días. Comprueba nueve
mutaciones de permisos, censo intacto, reversa y reinstalación.

El oráculo de calendario copia el cuerpo SQL instalado a una función temporal
y sustituye únicamente el reloj: prueba cero actividad y cartera vacía, límite
exacto de dos horas, 09:00/18:00, sábado 13:00, domingo y medianoche de Lima.
No modifica el reloj ni la función desplegable. También prueba modo observación.

PASS: 48 mutantes existentes de F1–F3 y gate paraguas después de instalar F4.
PASS: `node scripts/verificar-equipo-local.mjs` desde `app`: el JSON real de
PostgreSQL, consultado como authenticated, pasa el validador del frontend.
PASS: firma cotejada con `supabase gen types` en la copia local mediante
`verificar-tipos.mjs`. PASS: advisors de seguridad sobre esa misma copia, sin
incidencias. El log «remote database» del CLI no cambia el destino loopback.

PASS: 39 pruebas focalizadas de contrato, demo, consultas, pantalla y selección
por rol. PASS: `npm run check` (lint, tipos, pruebas con cobertura, configuración,
build, bundle y duplicación 0,50 %). Conserva cuatro advertencias previas de
accesibilidad en `coverflow-carousel.tsx`, ajeno a esta entrega.

PASS: suite completa de navegador (`npm run test:e2e -- --workers=4`):
224 aprobadas, 26 omisiones preexistentes, cero fallos. Incluye los 15 recorridos
focalizados de Gestión Diaria, con foco de teclado,
Jakarta cargada, tamaño de texto, datos completos con store vacío y revocación.
Capturas revisadas de escritorio y móvil en `evidencia-f4-vista/`; el menú se
pliega con su control existente en móvil y el scroll horizontal queda en la tabla.
PASS: `npm run check:scripts`, sintaxis de los cuatro scripts propios y
`git diff --check`.

En estos ensayos locales, instalación/publicación y recorrido humano eran NOT RUN.
La instalación y publicación se completaron después, según el acta vigente; el
recorrido humano sigue pendiente.
La matriz HTTP general del CRM no se ejecutó contra esta copia; los oráculos de
esta entrega sí ejercen roles reales y permisos en PostgreSQL. No confundir
los mocks HTTP del navegador ni los preflights offline con una prueba remota.

## Próximo paso

La aprobación del SQL exacto y `$release-crm`, instalación, registro y despliegue
ya están completados. La puerta productiva devolvió el roster autorizado de cinco
identidades (18/18/10/0/8 analistas), sin crear datos de negocio. Completar el
recorrido humano del supervisor y continuar F4 etapa 2 conforme al plan.
No activar cortes ni TypeSafe como parte de esta entrega.

## Historial: integración con el taller autorizada el 21/09

Las siguientes notas describen el momento anterior a la autorización productiva;
el estado de publicación vigente es el del encabezado y su acta enlazada.

Miguel autorizó reconciliar Main `40f2501b` con la candidata `997e1290`, conservando
las dos líneas. Los nueve conflictos están resueltos. El remoto se comprobó en
`37a936c7`; no hubo push ni publicación. El commit de integración mantiene ambos
padres y la ancestría de lo publicado, sin squash ni reemplazo del historial.

Se conserva el diseño local de «Mi día»: Ahora y cola en dos columnas, nombre
enfocable, acciones secundarias en menú y registro/detalles plegados. Se mantienen
los arreglos publicados de cuatro pestañas incluso vacías, paginación, caché
parcial, tarea autoritativa, resultados concurrentes y estado desconocido distinto
de cero. El nivel Bajo sigue ámbar y el texto conserva 16 px, incluido el menú.

«Llamar» y el menú usan el mismo panel y la misma tarea autoritativa. La validación
tardía de un contacto desmontado no abre el resultado del lead anterior. El foco
anuncia la ficha del lead, se conserva la posición dentro del grupo y Tab sale del
menú sin caer al body. En móvil las pestañas se desplazan sin solapar etiquetas.
Dos componentes duplicados y sin consumidores (`MiActividad`, `TarjetaAhora`) se
retiran de runtime; pueden recuperarse del commit padre `997e1290`. Las pruebas
ejercen la pantalla realmente conectada, no esas variantes retiradas.

La vista de supervisor, el SQL F4 y `lead-drawer.tsx`/`sla-operacion.tsx` mantienen
su contenido de `997e1290`: la reconciliación no revierte el bloqueo de creación de
actividad desde avisos de supervisión. No se modifica ninguna migración versionada.

### Review de integración y criterio del PRIMARY

Una revisión nueva mediante `scripts/claude-review`, sin herramientas ni escritura,
devolvió `CHANGES_REQUESTED` (confianza media) sobre el primer diff. Se atendieron
la resolución común de tarea, cobertura del contacto real, componentes duplicados,
posición del lead, etiqueta de acción, tipografía del menú y foco/navegación.

La tarea por caché del camino primario ya existía antes; no se atribuye falsamente
a esta fusión, pero queda resuelta para «Mi día». La hipótesis de desmontaje en cada
refetch no se reprodujo: `colaCargando` requiere ausencia de datos, no `isFetching`.
Una prueba con datos presentes y refetch activo conserva el contacto sin remontar.

WhatsApp mantiene su flujo previo: el avance solicitado es por resultado de llamada;
no se equiparan ambos canales ni se cambian sus reglas. El registro histórico es
un detalle optativo: su fallo se ve al abrirlo; los errores que impiden decidir la
cola siguen visibles fuera de los plegables. El foco al elegir fila no compite con
ningún diálogo y pasa el recorrido real. `idBase` sólo se usa para la cola: no queda
una referencia a `id-dia`. «Mi actividad» abre y enfoca el detalle; su resumen
nativo permite cerrarlo. No se realizó otra consulta para obtener un PASS.

### Verificación de la integración

PASS: `npm run check`: 270 archivos / 3.991 pruebas, lint, tipos, cobertura,
configuración, build, bundle y duplicación 0,50 %. Sólo persisten cuatro avisos de
accesibilidad preexistentes en `coverflow-carousel.tsx`. Lint final repetido PASS.
PASS: 12 recorridos focalizados de analista/supervisor después de las correcciones,
incluyendo menú por teclado, contacto, 16 px, dos columnas y móvil sin solapamiento.
Las capturas `evidencia-f4-vista/analista-integracion-*.png` se inspeccionaron.
PASS: suite completa final de navegador, 225 aprobadas, 26 omisiones preexistentes
y cero fallos (251 casos, 2,4 minutos). Sustituye para esta integración el ensayo
anterior de 224 aprobadas: se añadió la comprobación de diseño móvil/escritorio.

PASS: tres oráculos SQL repetidos en la base local exclusiva y contrato real
PostgreSQL authenticated → validador del frontend. Se conservan los ensayos anteriores
de reversa, tipos, advisors y mutantes de F1–F3; no se presentan como repetidos aquí.
La matriz HTTP general, instalación SQL, publicación y validación humana productiva
siguen NOT RUN. La aprobación de integración no autoriza ninguna de esas acciones.

### Incorporación a Main local

Main avanzó por fast-forward a `03249ba904bbdb49f02b0a108a436fc17aa941ec`, merge
con padres `997e1290` y `40f2501b`. El código incorporado es el mismo que pasó los
gates anteriores en el worktree aislado. No hubo push ni despliegue.

Los 22 archivos ajenos a la reconciliación conservaron sus huellas y estado. Las
101 líneas pendientes del ledger de temperatura se restituyeron exactamente y
siguen sin commitear. Los cinco archivos que se cruzaban tienen respaldo recuperable
en el stash `1af9b3b15b41e1d705593c331506c6533b0d52db`; no aplicar ese stash entero
sobre la integración, porque también conserva versiones anteriores de los documentos
ya reconciliados. La conciliación está cerrada: el objetivo continúa con aprobación
del SQL exacto, instalación autorizada y validación del recorrido del supervisor.
La publicación requiere su autorización separada y el mecanismo de release vigente.
