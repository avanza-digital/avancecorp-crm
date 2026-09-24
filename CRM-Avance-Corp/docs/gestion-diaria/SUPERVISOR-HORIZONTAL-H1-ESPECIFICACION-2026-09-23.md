# Supervisor horizontal — especificación H1

Fecha: 23/09/2026. Responsable: Codex PRIMARY. Alcance: H1.1–H1.4.
Complementa el [plan canónico](GESTION-DIARIA.md); no sustituye su avance F0–F6.
Referencia: [prototipo aprobado](assets/supervisor-horizontal-aprobado-2026-09-23.png).
Asset inspeccionado: ilustración generada con nombres y cifras ficticias; no es
una captura de producción. SHA-256: `1314891a779085bae9b7a3d5d56374cd24a0e32de6b527d22f33bcbfe073bc51`.

**Resultado:** definición implementable de pantalla, datos, medidas y acciones.
La interfaz se construirá en H2–H4. H1 no modifica código de producto ni instala SQL.
La reducción de scroll descrita abajo es un objetivo de implementación medible,
no una prueba de que la nueva pantalla ya exista.

## H1.1 — Base, alcance y situación inicial

- Base verificada tras `git fetch avancecorp main`: `cf87e8087bf61ea5c58669d924e801526a04c779`,
  Main posterior al PR #85 e incluyendo #86. `HEAD` y `avancecorp/main` coinciden
  al iniciar esta especificación. La base del PR #85 conserva su valor histórico.
- Rama: `codex/gestion-diaria-supervisor-horizontal` en la copia aislada existente
  `/private/tmp/avancecorp-release.hvdub4/repo`. El taller principal conserva los
  cambios de conversión de otra sesión. No se creó otro worktree.
- El plan previo fue respaldado antes de actualizar la base. Ocho archivos se
  conservaron byte a byte; `Inicio.md` incorpora también el contenido de Main.
  Los cambios de #86 no afectan los módulos de Gestión Diaria aquí inventariados.
- CodeGraph se consultó primero; su índice del taller no resuelve estos módulos
  nuevos y la copia aislada no tiene índice. Se completó la investigación con
  lecturas puntuales de los archivos actuales, sin crear ni actualizar índices.
- Solo cambia la vista **supervisor** de `#/gestion-diaria`. Analista, gerencia,
  ficha, agenda y configuración conservan sus capacidades. Los componentes
  compartidos deben recibir opciones con valores predeterminados compatibles.
- No se amplían permisos, se alteran métricas, se activan avisos de tasa baja ni
  se instala TypeSafe/Jev. El shell, menú global y buscador global son existentes.

### Inventario para implementar y comprobar

Rutas relativas a `CRM-Avance-Corp/`. Ninguno de estos archivos de producto fue
modificado durante H1.

| Pieza actual | Uso en el rediseño |
|---|---|
| [supervisor.tsx](../../app/src/screens/gestion-diaria/supervisor.tsx) | Orquestación, identidad, filtros, cinco indicadores, selección y modo equipo. Sustituir el registro inferior por panel hermano de la tabla. |
| [tabla-equipo-diaria.tsx](../../app/src/components/gestion-diaria/tabla-equipo-diaria.tsx) | Seis columnas compactas; retirar expansión vertical; mantener tabla semántica y ordenación. |
| [detalle-analista.tsx](../../app/src/components/gestion-diaria/detalle-analista.tsx) | Conservar ocho métricas, explicación de contacto y desglose horario; adaptar al ancho del panel. |
| [registro-actividad.tsx](../../app/src/components/gestion-diaria/registro-actividad.tsx) | Una fuente paginada, cuatro pestañas internas, filtros, texto íntegro y ficha. Sin CSV para supervisión. |
| [avisos-equipo.tsx](../../app/src/components/gestion-diaria/avisos-equipo.tsx) y [alertas-del-dia.tsx](../../app/src/components/gestion-diaria/alertas-del-dia.tsx) | Presentación compacta y detalle bajo demanda; conservar reconocimiento, aplazamiento y destinos actuales. |
| [gestion-diaria-avisos-provider.tsx](../../app/src/lib/gestion-diaria-avisos-provider.tsx) | Un único proveedor existente para popup, campana y lista; no montarlo dentro del panel. |
| [gestion-diaria-equipo.ts](../../app/src/lib/gestion-diaria-equipo.ts) | Contrato, presentación de motivos de cortes, filtros y orden estable. |
| [gestion-diaria-api.ts](../../app/src/data/gestion-diaria-api.ts) y [gestion-diaria-equipo-queries.ts](../../app/src/data/gestion-diaria-equipo-queries.ts) | Resumen autorizado por actor/día; consulta cada minuto y al recuperar foco/conexión. |
| [gestion-diaria-queries.ts](../../app/src/data/gestion-diaria-queries.ts) | Registro paginado autorizado; reutilizar claves y política de refresco. |
| [gestion-diaria-seguimiento-api.ts](../../app/src/data/gestion-diaria-seguimiento-api.ts) | Consultas y comandos actuales de cortes; no cambiar sus reglas. |

Pruebas existentes a conservar/adaptar: `app/src/screens/gestion-diaria/supervisor.test.tsx`,
`app/src/components/gestion-diaria/{detalle-analista,registro-actividad}.test.tsx`,
`app/src/lib/{gestion-diaria-equipo,gestion-diaria-cortes,gestion-diaria-avisos}.test.ts`,
`app/src/lib/gestion-diaria-avisos-provider.test.tsx`,
`app/src/data/gestion-diaria-equipo-{api,queries}.test.*`,
`app/src/data/gestion-diaria-api-msw.test.ts` y `app/e2e/gestion-diaria-equipo.spec.ts`.
H3 agregará pruebas de la nueva lectura de pendientes y su autorización.

### Medición de la pantalla publicada

Lectura de DOM y captura observadas en Chrome, viewport **1512 × 805**, zoom normal,
menú lateral contraído, pantalla al inicio, registro y detalle de fila cerrados.
Se registran solo medidas; no se copian nombres ni contenido de clientes.

| Elemento | Medida observada |
|---|---|
| Cabecera global | x=64, y=0, ancho=1448, alto=64 |
| Contenido útil | x=88, ancho=1390 |
| Cabecera local | y=88, alto=99 |
| Tabla | y=516, ancho=1388, alto=1550 para diez filas |
| Encabezado de tabla | alto=60,5 |
| Fila típica | alto=149; primera empieza en y=576,5 |
| Detalle expandido observado antes de cerrar | añade una región de 423,5 px |

En esa condición se ve una fila entera y parte de la segunda. La altura es el
problema principal: múltiples métricas, motivos y dos acciones dentro de cada fila.

## H1.2 — Datos, unidades y estados

### Fuentes y reglas que permanecen

El resumen usa `crm.gestion_diaria_equipo_fn(p_dia, p_supervisor_id)` y
`DiaEquipoSchema`. El día se obtiene con `fechaLima(useAhora())`; la ventana de
actividad es 00:00–00:00 del día siguiente en `America/Lima`. El roster válido
es el equipo activo autorizado por servidor, incluidos analistas sin actividad.
Los indicadores superiores siempre describen el **equipo completo**, no el filtro.

| Elemento visible | Campo/fuente | Unidad y definición |
|---|---|---|
| Analistas | `dia.resumen.analistas` | Personas activas del roster. |
| Con registro | `dia.resumen.con_actividad` | Personas con `gestiones_hoy > 0`. |
| Sin registro | `dia.resumen.sin_actividad` | Personas con `gestiones_hoy = 0`; no equivale a ausencia. |
| Con pendientes | `dia.resumen.con_pendientes` | Personas con tareas pendientes o primer intento vencido, según el contrato vigente. No sumar tareas aquí. |
| Necesitan atención | `presentarEquipo(dia).filter(requiere_atencion).length` | Personas; incluye motivos confirmados de cortes. No usar solo `dia.resumen.requieren_atencion`, que no incluye esa presentación. |
| Llamadas | `fila.marcador.llamadas` | Intentos registrados en la ventana, no gestiones de otros tipos. |
| Contacto | `tasa_contacto_pct`, `contestadas`, `utiles`, `nivel` | Porcentaje servido: 100 × contestadas útiles / llamadas útiles, redondeo del servidor. Se excluyen «Número errado» y «No es la persona» del contacto útil. |
| Muestra mínima | `dia.umbrales.minimo_llamadas_utiles` | La clasificación solo existe cuando alcanza ese mínimo. No fijar umbrales nuevos en cliente. |
| Pendientes / Vencidas | `tareas_pendientes` / `tareas_vencidas` | Tareas activas con estado pendiente de ese `vendedor_id`; vencida si `vence_en < pendientes_al`. Foto actual, no histórico del día elegido. |
| Atención por persona | `motivos_atencion` después de `presentarEquipo` | Lista completa: tarea vencida, primer intento, datos incompletos, sin llamar y cortes cuando corresponde; no sustituirla por «vencidas». |
| Gestión total / última | `gestiones_hoy`, `ultima_gestion_en` | Tipos actuales: llamadas, WhatsApp enviado, reunión, nota y conversión. Hora Lima o ausencia explícita. |
| Ocho métricas del detalle | `utiles`, `leads_tocados`, `llamadas_por_lead`, `citas_hoy`, primera/última llamada, `minutos_sin_llamar`, última gestión | Se preservan. «Citas pendientes para hoy» no se sustituye por citas creadas/agendadas durante el día. |
| Primer intento / datos incompletos | `primer_intento_vencido`, `datos_incompletos` | Señales de leads del motor SLA. No son filas de tareas; `null` significa no evaluado. |
| Horas | `marcador.por_hora`, `horarioConfirmado`, `barrasPorHora` | Trece horas 08–20 inclusivas; llamadas y contestadas. Conservar actividad fuera de franja y advertencia de diferencias con contacto útil. |
| Registro / últimas gestiones | `crm.registro_actividad_fn` | Actividades con leads visibles para la sesión. Puede diferir del agregado del equipo por visibilidad actual. |
| Cortes y otros avisos | `useGestionDiariaAvisos`, `useAlertasCRM` | Política, jornada y estados del servidor; no deducir de horas o cifras ilustradas. |

`con_actividad + sin_actividad = analistas`; `vencidas ≤ pendientes`;
`contestadas ≤ utiles ≤ llamadas`. Conservar los validadores existentes que
rechazan incoherencias. No recomputar negocio desde leads/actividades/tareas del store.

### Presentación de estados

| Estado | Texto y comportamiento |
|---|---|
| Cero confirmado | Mostrar `0`; `Sin llamadas registradas` o `Sin tareas pendientes` según su fuente. |
| Sin llamadas útiles | Contacto `—`, explicación `Sin llamadas útiles`; nunca `0 %` de sustitución. |
| Útiles por debajo del mínimo | Fila: `Sin muestra`, sin nivel; tasa disponible, fracción útil y mínimo en el panel y descripción accesible. No marcar rojo por el porcentaje. |
| SLA no evaluado | `Primer intento: no evaluado` / `Datos incompletos: no evaluado`. No convertir null en cero. |
| Carga inicial | Esqueleto/estado `Cargando…`, región ocupada; no cifras ficticias ni ceros. |
| Actualizando | Conservar respuesta confirmada mientras está en vuelo; al fallar, aplicar el estado de error de su fuente. |
| Error del resumen | Ocultar cifras del resumen y tabla; mostrar reintento. Panel permanece montado: Resumen muestra error, Registro/Pendientes siguen su autorización independiente. |
| Error de una lista | Informar fallo y reintento. Datos previos del mismo contexto solo con rótulo de antigüedad; no presentarlos como lista actual completa. |
| Permiso denegado o identidad cambiada | Vaciar memoria, ocultar datos y cerrar ámbito afectado inmediatamente. Sin respaldo de otro usuario. |
| Roster válido vacío / filtro vacío | Diferenciar `No hay analistas activos` de `Nadie coincide con estos filtros`; ofrecer limpiar solo en el segundo. |
| Desglose horario incoherente | Mensaje actual de imposibilidad de confirmar y acceso al Registro; no gráfico de ceros. |

## H1.3 — Medidas y distribución

**Presupuesto a 1512 × 805:** se conserva el shell de 64 px y el margen de
contenido de 24 px. Ancho útil observado 1390 px. Área izquierda 960 px,
separación 16 px y panel 414 px. Es una relación aproximada 70/30, subordinada
a mínimos legibles, nunca porcentajes rígidos.

| Bloque | Y objetivo | Alto objetivo, inclusive |
|---|---:|---:|
| Título, día, actualización y acceso a información | 88 | 44 |
| Separación | 132 | 8 |
| Cinco indicadores en línea | 140 | 44 |
| Separación | 184 | 8 |
| Tabla + panel independiente | 192 | 536 |
| Separación | 728 | 8 |
| Franja de cortes / otros avisos | 736 | 44 |

Fin en y=780: quedan 25 px al borde inferior. Dentro de los 536 px de tabla:
barra de filtros **52**, cabecera **44**, diez filas típicas **44** = **536**.
Bordes/separadores deben estar incluidos en las cajas (o ser interiores), sin
añadir altura oculta. No habrá un pie de tabla adicional: contador de filas en
la barra; hora de consulta e información en la cabecera y su desplegable.

- Tipografía: Plus Jakarta Sans del CRM; contenido, cifras, pestañas y controles
  de **16 px como mínimo**, interlineado legible. Título puede ser mayor.
  Objetivos táctiles de **44 × 44 px como mínimo**. Azul/navy y tonos actuales;
  color acompañado de texto. No verde ni semáforo nuevo de contacto.
- Una fila típica tiene una sola línea, control de selección de 44 px sin
  padding vertical adicional. Nombre largo, muestra insuficiente o texto
  ampliado pueden aumentar altura: **diez es la meta típica, no un recorte**.
  Evitar elipsis obligatoria de nombres y reducción de letra para forzar diez.
- Columnas mínimas, en px: Analista 204, Llamadas 104, Contacto 132,
  Pendientes 120, Vencidas 104, Atención 160 = **824**. Reservar además **16 px**
  para scrollbar interno: tabla exterior mínima840. El nombre recibe el resto.
  «Sin muestra» midió **88,34375 px** en el DOM con Plus Jakarta Sans16/400;
  con padding horizontal16 cabe en132. La tasa sin muestra se explica en el
  panel, sin intentar meter ambos textos en la misma línea.
  Vencidas ordena por `tareas_vencidas`. Atención ordenará por cantidad de
  `motivos_atencion`, después vencidas y nombre/id: se explicita este ajuste
  de presentación respecto al orden actual por booleano/vencidas/llamadas.
  Ascendente invierte la clave elegida; desempates numéricos conservan prioridad
  descendente y nombre/id ascendentes. Contacto sin muestra queda al final
  en ambos sentidos. Cada comparador tiene prueba propia.
- Dos columnas solo con contenedor útil **≥1236 px** (840 + 16 + 380).
  A 1366 × 768, rail contraído: ancho útil aproximado 1244, tabla 848/panel380;
  dentro de848 quedan832 para columnas con scrollbar16, superior al mínimo824.
  Caben nueve filas típicas completas y parte de la siguiente. No exigir diez.
  Si el scrollbar real supera16, el mínimo de dos columnas aumenta en esa
  diferencia; nunca consumir ancho reservado al panel o provocar solapamientos.
- Con menor ancho, sidebar expandido o zoom 200 %, usar tabla de ancho completo
  y detalle en cajón accesible superpuesto. Filtros y KPIs pueden envolver;
  se permite scroll vertical. En móvil presentar las seis celdas como bloques
  con rótulos por persona cuando la tabla no quepa, manteniendo todo el contenido.
  No convertir toda la página en un lienzo con scroll horizontal.
- En escritorio el cuerpo de la tabla y el del panel tienen scroll independiente;
  cabeceras y pestañas permanecen alcanzables. La altura es flexible con el
  viewport y el contenido; pantallas bajas pasan a flujo vertical. No `overflow:hidden`
  que haga inaccesible contenido. El foco desplaza su región hasta el control.
- El panel estrecho distribuye métricas en una o dos columnas según **su propio
  ancho**; no usar el breakpoint del viewport para forzar cuatro columnas.
  El gráfico compacto muestra 08–20 y leyenda; las cifras completas de las trece
  horas están disponibles en `Ver cifras por hora`, dentro del panel, con texto
  accesible. No meter trece columnas de 4,5 rem ni depender de hover para leer datos.
- La descripción del día, hora de consulta, explicación de contacto y «La
  actividad registrada no acredita presencia» estarán en un desplegable
  `Información de esta vista`, de acceso visible y por teclado.

### Matriz de información de fila y panel

| Información | Fila compacta | Panel |
|---|---|---|
| Identidad | Nombre completo como selección, estado accesible | Nombre completo, rol/contexto del día, cerrar y ampliar |
| Actividad | Llamadas totales; si gestiones=0, estado `Sin registro` cuando no haya motivos prioritarios | Gestiones, contestadas, útiles, leads y ocho métricas actuales |
| Contacto | Tasa y nivel con muestra; `Sin muestra` si no alcanza el mínimo; `—` si no hay útiles | Numerador, denominador, umbral dinámico y explicación de exclusiones |
| Pendientes | Total de tareas y columna vencidas separada | Totales, listado paginado, filtro Todas/Vencidas y señales SLA aparte |
| Atención | `N motivos` o `Sin alertas`; nombre accesible con contexto | Todos los motivos en texto, con su fuente y estado |
| Horas y gestiones | Fuera de la fila | Resumen: 13 horas, fuera de franja y últimas tres gestiones autorizadas |
| Acciones | Seleccionar; un único botón `Ir al detalle` junto al nombre, solo en la fila activa | Resumen, Registro, Pendientes, abrir ficha, cargar más, reintentar, cerrar/ampliar |

La selección usa un botón con `aria-current="true"` solo para la persona activa, `aria-controls` y nombre que
incluye a la persona. No es un conmutador: volver a pulsarlo no deselecciona.
Solo la fila activa expone junto al nombre un botón `Ir al detalle`, de icono
con nombre accesible, que enfoca el panel; los otros nueve no duplican paradas
de teclado. Objetivo44px en la misma línea; si un nombre largo exige más altura,
se respeta la excepción de densidad. No se superpone sobre texto.
La tabla conserva encabezados y `aria-sort`. No usar
`aria-selected` sobre un `tr` sin implementar un grid completo.

## H1.4 — Navegación y contratos

### Estado y ciclo de vida

Identidad del contexto: **actor + rol + demo/real + día Lima + modo + analista**.
Modos excluyentes: ninguna selección, analista, registro del equipo.
`pestanaPanel` (`resumen | registro | pendientes`) es independiente de
`pestanaRegistro` (`llamadas | whatsapp | notas | todo`). Guardar además
secuencia de apertura deliberada y control al que devolver el foco.

- Selección nueva de persona empieza en Resumen. Pulsar de nuevo la persona
  seleccionada conserva pestaña/filtros; no reinicia su consulta.
- Tabla y panel son hermanos; un error del resumen no desmonta el panel.
  La persona se resuelve desde todo `equipoPresentado`, no las filas filtradas.
  Guardar también el ID y nombre confirmado de la selección, ligados a su
  identidad. Si falla el resumen, esa instantánea sirve únicamente de título
  con aviso de consulta no confirmada; no conserva métricas como actuales.
  El ID de región/`aria-controls` es estable y no depende de que `dia` exista.
- Registro se monta al visitarlo y queda montado, oculto e inerte al cambiar
  pestaña del mismo contexto. Sus filtros, páginas y scroll se conservan.
  Pendientes tiene la misma regla de contexto. Solo una persona mantiene estado.
- Cambiar persona/modo reinicia las listas del contexto anterior; no mantener
  memorias invisibles de múltiples personas. Cambiar actor, rol, modo demo o día
  limpia todo antes de pintar y cancela/ignora respuestas antiguas.
- Respuesta válida de equipo sin la persona: cerrar. Error de red del equipo:
  no equivale a retirada. `42501` del equipo: cerrar y limpiar todo el panel.
  `42501` de una lista: vaciar esa lista inmediatamente y revalidar el equipo;
  no conservar páginas anteriores mientras se confirma autorización.
- Registro del equipo no tiene pestañas Resumen/Pendientes ni una persona
  implícita. Conserva selectores autorizados de Registro; empieza en Todo,
  aunque el componente actual abre Llamadas por defecto. En modo individual
  empieza Todo; las acciones explícitas de llamadas empiezan Llamadas.
  Individual: `analistaIds=[id]`, `mostrarAnalista=false`, `permitirEquipo=false`,
  sin selectores para otra persona/equipo. Equipo: `analistaIds=null`,
  `mostrarAnalista=true`, `permitirEquipo=false`. Ambos sin exportar.
  No cambiar defaults del componente para analista/gerencia. `pestanaInicial`
  se fija al crear la instancia y no cambia al alternar pestañas del panel.
  Aperturas explícitas Ver llamadas/Ver registro/aviso incrementan `apertura`
  y reinician los filtros/cursor declarados; ese reinicio es intencional.
  La vuelta normal a Registro conserva la misma instancia y no incrementa nada.
- Abrir ficha superpuesta preserva selección, filtros, cursor y scroll. Cambiar
  de ruta hash desmonta la vista y cierra contexto; al volver inicia sin selección.

### Cada control del prototipo y su destino

| Acción | Resultado concreto | Foco / conservación |
|---|---|---|
| Actualizar | Refrescar equipo y avisos; listas abiertas reinician en primera página con sus filtros. Últimas gestiones se invalidan una vez. | Conservar persona y pestaña; no mover foco del botón; anuncio de resultado. |
| Buscar analista | Filtrar nombre sobre roster completo presentado. | No cambia KPI ni persona; contador visibles/total. |
| Desplegable Todos | Opciones Todos, Con registro, Sin registro, Con pendientes con las definiciones H1.2. | Se combina con búsqueda y atención; cambio local, sin RPC por fila. Con pendientes usa `tareas_pendientes>0 || primer_intento_vencido>0`; si tareas=0, Atención señala el motivo SLA y el panel lo explica. |
| Con atención | Alternar filtro de `requiere_atencion` presentado. | Si oculta la selección, mostrar aviso y `Limpiar filtros`; conservar panel. |
| Ordenar columna | Alternar asc/desc de las seis columnas; orden inicial Atención descendente. | Conservar selección; icono y `aria-sort`. |
| Seleccionar nombre | Abrir/actualizar panel de esa persona en Resumen si es nueva. | Mantener foco en tabla y anunciar persona; `Ir al detalle` enfoca encabezado. |
| Pestañas del panel | Cambiar contenido de la misma persona. | Patrón tabs con flechas/Home/End y panel relacionado; no enfocar encabezado en cada render. |
| Banda de tareas vencidas | Abrir Pendientes con filtro Vencidas, cursor inicial. | Foco en encabezado de lista; no altera el filtro de la tabla. |
| Ver pendientes | Abrir Pendientes → Todas del analista seleccionado, cursor inicial. | Encabezado explicita analista y foto actual. No navega a Agenda sin filtro. |
| Ver llamadas del día | Abrir Registro → Llamadas de esa persona y día, reiniciar etapa/cursor. | Foco en encabezado de Registro. |
| Últimas gestiones | Tres primeras de Registro → Todo, misma persona/día; `Ver registro` abre Todo. | Una consulta de página compartida por clave; al filtrar Registro no cambia el resumen de últimas tres. Estados vacíos/error propios. |
| Ficha desde actividad/tarea | `abrirLead` con ID autorizado; lectura de ficha vigente vuelve a validar acceso. | Drawer sobre panel; al cerrar devuelve foco al enlace y scroll previo. Si ya no hay acceso, mensaje, sin reconstruir lead del store. |
| Cargar más (Registro/Pendientes) | Siguiente cursor de la misma identidad y filtros. | Conservar scroll y foco; anunciar filas cargadas y si hay más. |
| Reintentar | Solo fuente que falló; en Pendientes reiniciar primera página para nueva foto. | No tratar error como vacío ni consultar por cada fila. |
| Registro del equipo | Modo equipo, solo Registro → Todo, `analistaIds=null` bajo RLS actual. | Apertura explícita enfoca encabezado. Botón Ampliar para leer texto largo. |
| Menú `…` | Ampliar/Restaurar panel y Cerrar detalle; no acciones de editar al analista. | Mismo estado y listas al ampliar; cerrar devuelve al disparador si existe o al título de vista. |
| Cortes de llamadas | Desplegar detalle de cortes vigente, personas, metas y estados. | Sin desmontar proveedor; cierre devuelve al botón. |
| Aviso de persona | Abrir Registro → Llamadas con actor/día/analista validados, incluso si otra persona estaba abierta. | Enfoque explícito al encabezado; evento consumido una vez. |
| Lo estoy atendiendo / Posponer 1 hora | Comandos y restricciones actuales del servidor, mismo identificador de solicitud e idempotencia. | Mostrar espera/fallo/éxito; no simular reconocimiento local definitivo. |
| Otros pendientes | Desplegar `AlertasDelDia`, con destinos de `a.destino.vista` existentes. | No fingir filtro por analista en esos destinos; navegación a otra vista limpia selección. |
| Buscador global, ayuda, campana, menú y Nuevo lead | Conservar comportamiento/visibilidad por permisos del shell actual. | Son contexto de la ilustración, no nuevas capacidades concedidas al supervisor. |

Panel sin selección: título `Detalle del analista`, mensaje `Selecciona un
analista de la tabla para consultar su día`, sin pestañas activas ni consultas.
Ampliar abre un diálogo sobre la tabla, ancho `min(1200px, viewport - 48px)`,
alto máximo `viewport - 48px`, centrado, con scroll interno. El estado pertenece
al controlador externo: trasladar la presentación no reinicia la lista. Restaurar
vuelve al panel y su control; en móvil ocupa el viewport disponible con margen16.
Información de esta vista es un popover de ancho máximo480 y alto máximo70vh,
con scroll interno y cierre por Escape/clic fuera. Cortes/Otros pendientes usan
un diálogo de ancho máximo960, margen24 (16 móvil) y alto máximo `viewport - 48px`.
Los tres se superponen; no agregan altura a la página ni reinician proveedores.

Al pasar de región escritorio a cajón por resize/zoom, si existe selección se
abre el cajón, se guarda el foco externo y se enfoca su encabezado (o conserva
el control interno enfocado si sigue existiendo); se activa la trampa de foco.
Al volver a escritorio se retiran modal/inert/trampa y se conserva foco interno;
si estaba en un control eliminado, pasa al encabezado. Sin selección no se abre
cajón. Toda transición conserva identidad, pestañas, filtros, páginas y scroll.

En móvil el cajón tiene nombre, cierre, trampa de foco y Escape; en escritorio
el panel es región no modal, sin atrapar el foco. Ampliar conserva contenido y
estado en el mismo propietario. Escape cierra primero un menú/ficha/cajón
superpuesto; no cerrar el panel de fondo al cerrar la ficha.

### Decisión de backend para Pendientes

**Se especifica una consulta nueva y acotada de lectura, a construir en H3.3.**
H2 no depende de que esté instalada. El listado útil de tareas permanece dentro
del alcance aprobado; no se reemplaza por un botón a un destino no filtrado.

Evidencia del contrato actual:

1. [gestion_diaria_equipo_core](../../supabase/migrations/20260921040335_crm_gestion_diaria_equipo_vista.sql),
   bloque de tareas (líneas 129–134): agrega tareas activas pendientes por
   `t.vendedor_id`, incluidas todas sus clases de anclaje, bajo invoker/RLS.
2. [tareas_pendientes_core](../../supabase/migrations/20260920045202_crm_tareas_pendientes_lead_embebido.sql),
   líneas 167–211: pagina por vencimiento/id, pero sin filtro de analista y solo
   tareas con lead o perfil. La puerta actual recibe límite y cursor, no persona.
3. [listarTareasDelAmbito](../../app/src/data/crm-api.ts), líneas 2358–2435:
   descarga todos los lotes del ámbito, descarta filas inválidas con log y combina
   agenda de postventa. No expone completitud estricta al panel. Filtrar ese
   resultado no equivale a una página propia completa del analista.
4. La cola operativa une IDs a leads en memoria y prioriza acciones; no es el
   inventario paginado de tareas. La navegación de Otros pendientes solo lleva
   a una vista hash, sin contrato de selección por analista.

Reutilizar la descarga global sería técnicamente posible con adaptaciones y
limitaciones, pero no es el contrato elegido: carga más datos de los necesarios,
mezcla recorridos y dificulta acreditar completitud y estados. Se conserva
intacto para Agenda y se añade una puerta específica para este panel.

#### Contrato decidido (futuro, no existente)

Nombre propuesto: `crm.gestion_diaria_pendientes_fn`.
Parámetros: `p_analista_id uuid` obligatorio, `p_solo_vencidas boolean=false`,
`p_limite integer=25` (1–100), y cursor opcional compuesto
`p_despues_de timestamptz` + `p_despues_id uuid` (ambos o ninguno).
No admite supervisor enviado como autoridad ni solicita día histórico:
los pendientes son la foto **actual**.

- Puerta autenticada: actor activo con rol supervisor y analista activo dentro
  de su roster canónico visible. Mismo criterio de pertenencia que equipo,
  sin reconstruir jerarquía en el navegador. H3 extraerá la resolución actual
  de roster/autoridad de equipo a un helper privado compartido, usado también
  por el agregado existente, conservando su contrato. Matriz de paridad de
  equipo antes/después obligatoria, incluidos gerencia/global y puentes inactivos;
  no copiar una segunda jerarquía independiente. ID ajeno, inactivo o inexistente
  obtiene la misma denegación `42501`; argumentos inválidos, `22023`.
- Puerta y núcleo separados según arquitectura actual; `SECURITY INVOKER`,
  `search_path=''`, sin `service_role` en cliente. Conservar RLS y grants
  actuales de tablas/columnas; conceder solo ejecución necesaria de la función.
  El guard debe proteger también cualquier núcleo ejecutable por authenticated.
  Con una puerta invoker, su núcleo necesita EXECUTE para el actor: no retirar
  ese grant y cambiar a definer como atajo. Probar invocación directa del núcleo.
- Conjunto: `crm.tareas`, activas, estado pendiente, `vendedor_id=p_analista_id`;
  **no** filtrar por el vendedor actual del lead ni excluir tareas por no tener
  lead. Orden `vence_en ASC, id ASC`. RLS decide cada fila.
- Una respuesta `version:1`, `zona:America/Lima`, `supervisor_id`, `analista_id`,
  `generado_en`, `pendientes_al`, `solo_vencidas`, `limite`,
  `resumen:{tareas_pendientes,tareas_vencidas}`, `items`, `hay_mas` y
  `siguiente_cursor` nullable. El resumen corresponde a todas las tareas de la
  persona antes del filtro Vencidas, en la misma sentencia de esa página.
- Ítem: ID, analista responsable, tipo, título, vencimiento, estado pendiente y
  datos mínimos de referencia. `lead_id/nombre` solo si el join autorizado lo
  permite; referencia sin lead visible muestra `Referencia no disponible` y no
  ofrece abrir ficha. Tareas de perfil/postventa siguen listadas, sin inventar
  una ruta de ficha. No enviar teléfonos, correos, notas completas ni datos
  financieros para una lista que no los utiliza.
  Forma precisa: `id/vendedor_id` UUID no nulos; `tipo/titulo` string no nulos,
  `vence_en` timestamptz no nulo; `estado` literal pendiente; `referencia_tipo`
  enum lead/perfil/postventa; `lead_id` y `lead_nombre` nullable, siempre presentes.
  Los tipos actuales (`app/src/lib/database.types.ts:3959–3989`, `TareaRowSchema`)
  confirman tipo/título/vencimiento no nulos; falta de grant no se trata como null.
  Clases: lead → mostrar nombre y ficha si ambos son visibles; perfil →
  `Tarea de perfil`, sin enlace; inversionista → `Tarea de postventa`, sin enlace.
  Los IDs privados de perfil/inversionista no se envían. Las tres clases tienen
  los mismos campos de tarea obligatorios y referencia de lead nullable.
  El modelo exige un solo sujeto (`tipos.ts`, comentario de `Tarea`): cero o
  varios anclajes se rechazan como error de integridad, no se omiten silenciosamente.
  Un título vacío válido se representa `Sin título`; no se acepta null ni fecha
  inválida en un cursor. El banco H3 confirmará columnas/grants de las tres clases;
  esa prueba pendiente no se presenta como realizada en H1.
- Servidor obtiene límite+1 para `hay_mas`, devuelve hasta límite y cursor de
  última fila entregada. Cliente valida forma, identidad, orden, cursor creciente
  y unicidad; una fila inválida produce error de contrato, no descarte silencioso.
  Dedupe por ID entre páginas por reprogramaciones concurrentes.
- No promete una transacción histórica entre páginas: altas, cierres,
  reasignaciones y reprogramaciones pueden cambiar el conjunto. Mostrar hora de
  consulta y filas cargadas/hay más; Actualizar reinicia la lista. No declarar
  coincidencia exacta con una foto anterior del KPI. Contrastar paridad en un
  fixture estable y tratar desfase de reloj/datos en prueba de concurrencia.
- Query/cache por actor, rol, demo, día de contexto, analista, filtro y cursor.
  Auto-refrescar cada minuto **solo mientras haya una única página cargada**.
  Desde la segunda, congelar todas las páginas (también la primera), mostrar
  antigüedad y ofrecer `Actualizar desde el inicio`. No mezclar página1 nueva
  con cursores antiguos. Reiniciar evita omisiones por inserciones/reprogramaciones
  anteriores al cursor; deduplicar no basta. Ocultar pestaña pausa el refresco
  de Pendientes sin destruir su estado; regresar revalida solo si es página única. No volver a consultar la lista
  al seleccionar cada fila de la tabla; consulta solo al visitar Pendientes.
- PGRST202/función no instalada: `Detalle de tareas no disponible`, con resumen
  confirmado y sin fingir vacío. La fase H3.3 no se acepta hasta que el contrato
  esté instalado y comprobado en el banco autorizado. Publicación aditiva antes
  del cliente; cliente anterior sigue usando sus funciones sin cambios.

La extracción compartida de roster es el único ajuste previsto del agregado
existente y exige paridad de respuesta; no cambia su contrato público.
No se cambian tablas de negocio, políticas RLS, reglas de tareas ni comandos de
edición/cierre. H3 debe añadir migración **nueva**, contrato cliente/tipos y
pruebas de lectura; no editar migraciones versionadas ni instalarla durante H1.
Si el ensayo demuestra que faltan grants o índices, documentar el cambio concreto
antes de ampliar esa entrega; no debilitar RLS para obtener paridad.

## Aceptación que guía H2–H5

1. A 1512 × 805, diez personas sintéticas con nombres típicos: diez filas
   completas, texto ≥16 y controles ≥44; tabla/panel/cortes visibles sin scroll
   de página. A 1366 × 768: nueve filas y acceso al resto. Nombres largos,
   múltiples motivos, 3 dígitos, móvil y zoom 200 % conservan toda la información.
2. Cinco KPI invariantes al buscar/ordenar/filtrar. Filas con cero, muestra
   insuficiente, SLA null y corte confirmado mantienen su significado.
3. Cambiar de persona no roba foco; Registro conserva cuatro pestañas, texto
   completo, filtros, páginas y retorno de ficha. Ocultar persona por filtro no
   revoca; quitarla del roster válido sí. Aviso abre llamadas correctas.
4. Error temporal de equipo no destruye Registro independiente. Cambio de día,
   usuario, modo, permiso y respuestas tardías no cruzan información.
5. Pendientes: más de 1000 tareas mediante páginas pequeñas; solo persona
   elegida, vencidas incluidas en total, todas las clases de anclaje, cursor con
   empates, 0 confirmado, fila inválida, error, falta de función y concurrencia.
   Congelar página1 al cargar página2, insertar/reprogramar antes del cursor y
   actualizar desde cero; tres anclajes con referencias nulas admitidas.
   RLS: equipo propio/ajeno, descendiente activo, actor/miembro inactivo, anon,
   núcleo invocado directamente y pérdida de acceso a la referencia.
6. Cortes: conservar política vigente, reconocer/posponer, campana/lista/popup
   y no duplicados. Sin dependencia nueva de Jev. Regresión de analista/gerencia.
7. Filtro Con pendientes coincide con el KPI, incluyendo tareas0 + señal SLA;
   Atención ordena por motivos con desempate y Vencidas tiene orden propio.
   Diez filas Sin muestra, scrollbar clásico16px, ampliar/restaurar, estado
   inicial y transiciones de breakpoint conservan foco y acceso al contenido.

H3/H5 ejecutarán pruebas de contrato/API, matriz SQL/RLS en entorno autorizado,
gates aplicables de `.ai/VERIFICATION.md` y E2E **local en Docker**. H6 verificará
Main vigente y publicará únicamente su artefacto comprobado. La primera jornada
real de F4 (24/09, 11:30/16:00 Lima; sábado 26/09) conserva su seguimiento separado.

## Evidencia de cierre de H1

**H1 CERRADA: cuatro etapas, doce tareas.** Base/aislamiento, inventario y
medición; diccionario/estados; presupuesto/matriz de información; acciones,
identidad y contrato de lectura resueltos.

- **PASS documental:** JSON, enlaces locales, coincidencia de72 tareas entre
  plan y metadatos, y `git diff --check`.
- **PASS Figma:** lectura de24 bloques confirma12 tareas completas/60 pendientes;
  las76 casillas históricas conservan IDs/textos. Captura final inspeccionada sin
  solapamientos ni recortes; prototipo sintético conservado.
- **Claude: CHANGES_REQUESTED, MEDIUM.** Codex resolvió los puntos con fuentes,
  medida tipográfica y decisiones documentadas. Sin segunda revisión; no afirmar
  PASS de Claude.
- **Producto/SQL/E2E/build: NOT RUN**, por alcance documental; código y servidor
  sin cambios. Las medidas nuevas siguen siendo metas de H2/H5.

[Acta de revisión](SUPERVISOR-HORIZONTAL-H1-REVISION-2026-09-23.md) ·
[Evidencia verificable](SUPERVISOR-HORIZONTAL-H1-EVIDENCIA-2026-09-23.json) ·
[Captura final del tablero](assets/supervisor-horizontal-h1-cerrada-figma-2026-09-23.png).
No se consideran PASS de producto las lecturas de fuentes ni las medidas de la
pantalla anterior. Próximo paso: H2.1; H3.3 contiene el backend acotado.
