ROLE: SECONDARY_REVIEWER.
Claude is the PRIMARY agent.

Do not modify files. Do not implement the task. Do not invoke Claude.
Do not delegate to another coding agent. Do not create another review chain.
Follow .ai/REVIEW_PROTOCOL.md (its content is transcribed at the end).

Responde en español. No tienes shell, red ni base de datos: todo lo que debes juzgar está
transcrito aquí. Formato obligatorio: VERDICT (PASS / CHANGES_REQUESTED / BLOCK), SUMMARY,
FINDINGS P0–P3 con evidencia (archivo:línea o fragmento citado de este encargo), TEST GAPS,
REGRESSION RISKS, RECOMMENDED NEXT ACTIONS, CONFIDENCE. Sin hallazgo sin evidencia; marca como
hipótesis lo no demostrado. Omite secciones vacías.

# Encargo: REFUTAR el plan de rediseño de la pantalla del analista («Mi día») — LEVEL 2
(la etapa A3 toca el camino de escritura del resultado de llamada: trátala con rigor LEVEL 3)

Todavía NO hay código: se revisa el PLAN antes de que el dueño (Miguel, no desarrollador) lo
apruebe. Tu trabajo es encontrar lo que el plan rompe, olvida o subestima: funciones en
producción que se perderían, regresiones de accesibilidad, carreras (resultado escrito sobre el
lead equivocado), foco, atajos de teclado, flujo del celular (`tel:` y vuelta), paginación y
selección con el nuevo filtro «Todo», estados vacíos/caídos, pruebas faltantes, riesgos de
publicación y si el corte A2/A3 es sano. Si el plan es correcto en un punto, no lo menciones.

## Contexto

CRM interno (React 19 + Vite + Tailwind 4 + Supabase) de una empresa de inversiones en Lima.
~18 analistas llaman leads todo el día desde la pantalla «Gestión Diaria → ¿A quién llamo ahora?».
Miguel trajo un diseño hecho en Claude Design para un proyecto hermano (VitaNova, clínica) cuya
vista «asesora» se inspiró en esta misma pantalla, y pidió aplicarlo manteniendo los colores del CRM
(navy #111e3d + azul #2563eb, Plus Jakarta Sans, SIN verde). Se hará un plan por pantalla; esta es
la primera. Las otras dos (supervisor, gerencia) vendrán después y reutilizarán las piezas de A1.

### Qué dibuja el diseño para la asesora (1440×1000, altura fija, scroll interno)
- Cabecera: «¿A quién llamo ahora?» + «Llama, guarda el resultado y pasas a la siguiente. Corte
  16:30 · se actualiza cada minuto.» + fecha + botón «Mi Hoy completo ›».
- Franja (tarjeta) de 4 cifras: LLAMADAS 18 hoy · CONTESTARON 11 de 18 · CONTACTO 69 % [Bien · de
  16 útiles] · CITAS AGENDADAS 3 hoy.
- Izquierda (430 px): tarjeta «Ahora» con aire de celular (radio 32 px, cabecera oscura con barrita
  de altavoz, «Ahora · 1 de 6», barra de inicio abajo): nombre 24 px, etapa, recuadro con chip de
  tiempo («Se pasó hace 1 día» rojo / «Quedan 40 min» ámbar / «Hoy 17:00» gris) + detalle,
  teléfono 24 px centrado, «Llamar» píldora 52 px, «WhatsApp» píldora y «···» redondo.
  Al pulsar «Llamar»: toast «Copia +51… para marcar; al colgar eliges qué pasó» y la tarjeta muestra
  «¿Qué pasó con la llamada?» con 7 botones numerados (1 No contestó · 2 Contestó · volver a llamar ·
  3 Contestó · agendó consulta · 4 Contestó · no le interesa · 5 Número errado · 6 No es la persona ·
  7 Pide otro servicio) + «Cerrar sin registrar». Elegir uno GUARDA directo y pasa al siguiente
  (el diseño NO dibuja submotivos, fechas ni decisiones: el toast dice «con su próxima acción
  agendada»).
- Derecha: pestañas «Cola de hoy · 6 | Mi actividad». Cola: chips Todo 6 / Nuevos 2 / Vencidas 1 /
  Para hoy 3 + «El orden lo pone la base»; filas 62 px con avatar de iniciales, nombre 14 px, línea
  «grupo · detalle» 12 px y chip de tiempo a la derecha; fila elegida resaltada; pie «6 de 6
  pendientes · Elegir una fila la pone en «Ahora»». Mi actividad: barras por hora grandes
  (contestaron oscuro / no contestaron claro, número encima, 08–19) + «Tu supervisora ve esto mismo
  de ti» + «Qué hice hoy» con chips Todo/Llamadas/WhatsApp/Notas y filas (hora, chip de resultado,
  lead, nota, pie) + «Ver más».

## Decisiones del dueño (NO son hallazgos)
1. Aplicar el diseño con los colores del CRM; menú lateral navy sin cambios; sin verde.
2. Un plan por pantalla; la del analista va PRIMERO.
3. El resultado de la llamada se registra DENTRO de la tarjeta «Ahora» (reemplaza su decisión del
   21/09 de tenerlo tras «···»), conservando los pasos que exige cada resultado.
4. Nada se programa ni se publica sin su OK; publica él con `/release-crm`.

## Reglas vigentes del proyecto que el plan debe respetar
- Comodidad del analista (queja real, 20/09): nombre ≥16 px, detalle nunca <14 px, UNA línea de apoyo
  por fila, controles ≥44 px. Nada de la sigla «SLA» en pantalla: se dice el tiempo («Quedan 40 min»,
  «Se pasó hace 45 min»).
- Horizontal, nunca apilado en vertical (Miguel «odia» la pila). Composición aprobada el 20/09: panel
  «Ahora» fijo a la izquierda + cola en pestañas a la derecha.
- Presupuesto de color: rojo solo para «requiere intervención hoy» (lo vencido); máx. 2 grupos ámbar
  visibles; violeta es categórico, jamás severidad; el color nunca va solo (texto + forma). Nivel
  «Bien» en navy sobre fondo tenue; «Bajo» y «Atención» en ámbar (decisión 21/09, blindada por tests).
  Tokens de TEXTO para chips (`--accent-press`, `--destructive-text`, `--warning-text`): el color puro
  sobre su tinte al 12 % no pasa 4.5:1.
- Caché parcial: el store NO carga todos los leads ni todas las tareas; «desconocido» no es «no
  existe» (el teléfono no viaja en la cola; `tarea_id` de la cola es autoritativo y se pide por id).
- Accesibilidad: `role="menu"` exige el patrón APG completo; anillo de foco de la casa con
  `outline-2 outline-offset-2 outline-ring` (reglas globales en index.css); `aria-disabled` y no
  `disabled` en un botón que puede tener el foco (si no, el foco cae al body); anuncios `role=status`
  al paginar (WCAG 4.1.3); atajos de un carácter acotados al componente (WCAG 2.1.4).
- Gate de realidad: probar también en el ESTADO DE PRODUCCIÓN (cola vacía/caída, sin metas), no solo
  con el fixture lleno. E2E SIEMPRE en local con Docker (`npm run test:e2e:docker`), nunca en CI.
- Verificación por fase: `npm run check` (oxlint + typecheck + vitest con cobertura), E2E Docker,
  subagente `revisor-a11y`, review Codex. Implementar ≠ verificar; reportar PASS/FAIL/NOT RUN.
- Antecedente: esta pantalla ya se construyó DOS VECES por no mirar el remoto; y un bug real de
  producción (20/09): con una sola caja de contacto que cambia de lead, el refresco de cada minuto
  podía escribir el resultado sobre la persona equivocada → se arregló con `key={lead.id}`.

## EL PLAN A REVISAR (texto que verá el dueño, más anclas técnicas)

Objetivo: que el analista trabaje su día como en el diseño: todo a la vista sin bajar, la tarjeta
«Ahora» como su teléfono y el resultado sin ventanas encima. Mismas reglas y cifras; sin base de datos.

A1 · Piezas comunes (preparación): cuadro de cifra y franja, etiquetas (tiempo, nivel, resultado),
avatar de iniciales, barras por hora (contestaron / no contestaron, número encima, 08–20), pestañas
subrayadas y filtros en pastilla. Una sola vez, con tokens del CRM; luego las usan supervisor y gerencia.

A2 · Aspecto y orden (publicable sola):
- Arriba: franja de 4 cifras (Llamadas; Contestaron «de N»; Contacto % + nivel, o «se juzga desde 5
  útiles» si no hay nivel; Citas agendadas). Reemplaza el botón-resumen «Mi actividad» de la cabecera.
- Izquierda: tarjeta «Ahora» con aire de celular (cabecera navy «Ahora · 1 de N», nombre grande que
  abre la ficha, etapa, tiempo en palabras —rojo solo si ya se pasó—, teléfono grande, «Llamar»
  grande y redondo, WhatsApp y «···» con «Registrar resultado» y «Ver la ficha completa»).
- Derecha: pestañas «Cola de hoy · N», «Mi actividad» (barras por hora + «¿Qué hice hoy?» —hoy es
  un plegable fuera de esta pantalla, en el contenedor— + «Descartados hoy» con su «Deshacer» de
  24 h) y «Mi seguimiento» (compromisos desde mañana).
- Cola: filtros en pastilla Todo / Sin primer intento / Vencidas / Hoy / Sin conversación con su
  número («?» si la cola está caída; «N+» si hay más); filas con iniciales, nombre ≥16 px, UNA línea
  de apoyo (grupo · detalle) y chip de tiempo; fila elegida resaltada; 8 por página (hoy 5) con
  «Anterior/Siguiente»; pie con rango y «Elegir una fila la pone en «Ahora»».
- «Todo» (nuevo, por defecto): concatena los cuatro grupos en el orden actual del servidor
  (primer intento → vencidas → hoy → sin conversación); «Ahora · k de N» cuenta sobre la vista activa.
- Se van los plegables de abajo; la pantalla cabe sin bajar a 1440×900; en pantallas angostas se
  apila como hoy (Ahora arriba, cola abajo).
- «Seguimiento completo» (hoy un enlace-pestaña encima de la pantalla) pasa a botón de la cabecera.
- El resultado se sigue registrando como hoy (diálogo `RegistrarResultado`).

A3 · Resultado dentro de «Ahora» (publicable aparte de A2):
- Se añade a `RegistrarResultado` un modo «tarjeta» (misma lógica, validaciones, toasts con
  «Deshacer» 15 s y `sinConfirmar`), montado dentro de la tarjeta «Ahora» en vez del `Dialog`.
  Los demás lugares (ficha del lead, Hoy, colas, composer) siguen con el diálogo.
- Laptop: «Llamar» copia el número (como hoy) y la tarjeta pasa a «¿Qué pasó con la llamada?» con los
  7 resultados (atajos 1–7 acotados a la tarjeta). Celular: `tel:` abre el marcador y, al volver
  (≥4 s, mecanismo actual), la tarjeta muestra lo mismo.
- Al elegir: en la tarjeta aparece solo el paso que ese resultado exige (cuándo volver a llamar; la
  cita con fecha, hora y modalidad; el submotivo; la decisión ante número errado; «marcar perdido»
  al 6.º intento), nota opcional y «Guardar». Al guardar: toast con «Deshacer» y la tarjeta pasa sola
  al siguiente. «Cerrar sin registrar» vuelve a la tarjeta normal.
- Mientras se registra, la tarjeta NO cambia de persona aunque la cola se refresque (se congela la
  selección hasta guardar o cerrar).
- WhatsApp sigue como hoy (su propio diálogo al volver de wa.me).

Comprobación (cada etapa): pruebas unitarias de la pantalla (41) y del resultado (14) actualizadas;
E2E Docker `gestion-diaria-analista`, `gestion-diaria-cola`, `gestion-diaria-resultado`,
`gestion-diaria`; accesibilidad (teclado, lector, foco) con `revisor-a11y`; Codex (reforzado en A3);
prueba con el día vacío/cola caída; recorrido real tras publicar.
Publicación: A2 y A3 por separado.
Qué NO cambia: la cola y su orden (servidor), las cifras (contacto = contestaron ÷ útiles, nivel
desde 5 útiles), los 7 resultados y lo que guarda cada uno, el «Deshacer» de 24 h, la ventana legal
(lun–sáb 07–20), los avisos de corte, «Hoy», la ficha del lead y el menú.
Defaults del PRIMARY: Descartados dentro de «Mi actividad»; 8 filas por página; «Seguimiento
completo» en la cabecera; WhatsApp sin cambios.

## Preguntas concretas (además de lo que encuentres)
1. ¿Qué función viva se pierde o se esconde con A2 (p. ej., avisos `role=alert` de cola caída,
   `cartera_truncada`, «Ver todas las oportunidades», estado «Buscando su número…», «Elegido»)?
2. ¿«Todo» por defecto rompe la lógica actual de `activa`/`pestanaPedida`/`elegido`/paginación
   derivada, o el salto al siguiente tras guardar (`cerrados`, `setPestanaPedida(null)`)?
3. A3: ¿congelar la selección basta contra la escritura sobre otra persona? ¿Qué pasa con
   `key={lead.id}` de `AccionesContacto`, con el refresco de `dia`/`cola`, con dos guardados seguidos,
   con `sinConfirmar`, con el atajo 1–7 fuera de un `[role=dialog]`, con el foco al guardar/cerrar,
   con Escape (hoy lo cierra el Dialog) y con el flujo del celular que depende de `visibilitychange`?
4. ¿El modo tarjeta de un componente compartido es preferible a extraer su lógica en un hook? ¿Qué
   riesgo tiene para las otras superficies que lo usan?
5. ¿Mover «¿Qué hice hoy?» (hoy en el contenedor `gestion-diaria.tsx`) y «Descartados» a pestañas
   cambia algo que los E2E o los analistas den por supuesto?
6. ¿Faltan pruebas en el plan (p. ej., 1440×900, zoom 200 %, celular, estado de producción)?

## CÓDIGO ACTUAL EN PRODUCCIÓN (transcrito; numeración real del archivo)

### `CRM-Avance-Corp/app/src/screens/gestion-diaria.tsx` (líneas 1,106)
```tsx
   1  // Gestión Diaria — wrapper que enruta por rol (mismo molde que screens/hoy.tsx).
   2  // Fase 1 (19/09/2026): las tres vistas comparten la sección «Registro» del día;
   3  // el analista ve el suyo, el supervisor su equipo y gerencia todo, con día a
   4  // elegir y exportación. «Mi día», «Mi equipo hoy» y el pulso llegan en las
   5  // fases 4–5 del plan (docs/gestion-diaria/GESTION-DIARIA.md).
   6  // Fase 3 (20/09/2026): el analista abre con «Mi día» — la cola completa, su
   7  // marcador, sus compromisos y sus descartes — y conserva el registro debajo.
   8  // Densidad (20/09/2026): el registro del propio analista («¿Qué hice hoy?») se
   9  // pliega. Es memoria, no trabajo pendiente: releer el log propio no cambia a
  10  // quién hay que llamar, y abierto duplicaba el largo de la pantalla.
  11  import { useState, useSyncExternalStore, type JSX, type ReactNode } from 'react'
  12  import { useAuth } from '@/lib/auth-context'
  13  import { useAhora } from '@/lib/ahora'
  14  import { fechaLima } from '@/lib/agenda-derivada'
  15  import { RegistroActividad } from '@/components/gestion-diaria/registro-actividad'
  16  import { GestionDiariaAnalista } from '@/screens/gestion-diaria/analista'
  17  import { GestionDiariaSupervisor } from '@/screens/gestion-diaria/supervisor'
  18  import { GestionDiariaGerencia } from '@/screens/gestion-diaria/gerencia'
  19  import { Plegable } from '@/components/gestion-diaria/plegable'
  20  import { PanelVacio } from '@/components/common/estado-panel'
  21  import { Input } from '@/components/ui/input'
  22  import { CalendarCheck2 } from 'lucide-react'
  23  import { ColaSeguimiento } from '@/components/app/cola-seguimiento'
  24  import { hashDe, leerHash } from '@/lib/router'
  25  
  26  const suscribirRuta = (cambio: () => void) => { window.addEventListener('hashchange', cambio); return () => window.removeEventListener('hashchange', cambio) }
  27  const fotoRuta = () => window.location.hash
  28  
  29  /** Ambos accesos siguen vigentes hasta completar la observación productiva de F6. */
  30  export function GestionDiaria(): JSX.Element {
  31    const { yo } = useAuth()
  32    useSyncExternalStore(suscribirRuta, fotoRuta)
  33    if (!yo) return <PanelVacio icono={CalendarCheck2} titulo="Sin sesión" detalle="Vuelve a entrar para ver la gestión del día." />
  34    if (yo.rol !== 'vendedor' && yo.rol !== 'supervisor' && yo.rol !== 'gerencia') {
  35      return <PanelVacio icono={CalendarCheck2} titulo="Gestión Diaria no está disponible para tu rol" detalle="Este módulo es para analistas, supervisores y gerencia." />
  36    }
  37    const cola = leerHash().detalleGestion?.tipo === 'cola'
  38    const cabeceraIntegrada = (yo.rol === 'supervisor' || (yo.rol === 'gerencia' && !yo.demo)) && !cola
  39    const enlace = 'inline-flex min-h-11 items-center rounded-lg border px-4 py-2 text-base font-semibold focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring'
  40    const accesoCola = <a href={hashDe('gestion-diaria', null, undefined, undefined, { tipo: 'cola' })} aria-current={cola ? 'page' : undefined} className={`${enlace} ${cola ? 'border-primary bg-primary text-primary-foreground' : 'border-border-strong bg-card text-primary'}`}>Seguimiento completo</a>
  41    return <div key={`${yo.id}:${yo.rol}:${yo.demo}`} className="mx-auto w-full max-w-[1640px] space-y-5">
  42      {!cabeceraIntegrada && <nav aria-label="Secciones de Gestión Diaria" className="flex flex-wrap gap-3">
  43        <a href={hashDe('gestion-diaria')} aria-current={!cola ? 'page' : undefined} className={`${enlace} ${!cola ? 'border-primary bg-primary text-primary-foreground' : 'border-border-strong bg-card text-primary'}`}>Resumen del día</a>
  44        {accesoCola}
  45      </nav>}
  46      {cola ? <>
  47        <p className="text-base text-[var(--muted-foreground-strong)]">Pendientes actuales de tu ámbito. La fecha del resumen no cambia esta cola.</p>
  48        <ColaSeguimiento />
  49      </> : <ResumenGestionDiaria accesoSeguimiento={cabeceraIntegrada ? <nav aria-label="Secciones de Gestión Diaria">{accesoCola}</nav> : undefined} />}
  50    </div>
  51  }
  52  
  53  function Cabecera({ pregunta, detalle, children }: { pregunta: string; detalle: string; children?: JSX.Element | undefined }) {
  54    return (
  55      <header className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
  56        <div>
  57          <h2 className="text-xl font-bold leading-tight text-primary">{pregunta}</h2>
  58          <p className="mt-1 text-sm text-[var(--muted-foreground-strong)]">{detalle}</p>
  59        </div>
  60        {children}
  61      </header>
  62    )
  63  }
  64  
  65  function ResumenGestionDiaria({ accesoSeguimiento }: { accesoSeguimiento?: ReactNode }): JSX.Element {
  66    const { yo } = useAuth()
  67    const hoy = fechaLima(useAhora())
  68    const [dia, setDia] = useState(hoy)
  69    const [registroAbierto, setRegistroAbierto] = useState(false)
  70    const diaValido = /^\d{4}-\d{2}-\d{2}$/.test(dia) && dia <= hoy ? dia : hoy
  71  
  72    if (!yo) return <PanelVacio icono={CalendarCheck2} titulo="Sin sesión" detalle="Vuelve a entrar para ver la gestión del día." />
  73  
  74    switch (yo.rol) {
  75      case 'vendedor':
  76        // Fase 3: el analista entra a «Mi día» (cola, marcador, compromisos y
  77        // descartes). Su registro crudo sigue debajo, plegado.
  78        return (
  79          <div className="mx-auto w-full max-w-[1440px] space-y-6">
  80            <GestionDiariaAnalista />
  81            <Plegable titulo="¿Qué hice hoy?" resumen="tu registro del día" abierto={registroAbierto} onAbrir={setRegistroAbierto}>
  82              <RegistroActividad dia={hoy} analistaIds={[yo.id]} mostrarAnalista={false} permitirExportar={false} />
  83            </Plegable>
  84          </div>
  85        )
  86      case 'supervisor':
  87        return <GestionDiariaSupervisor accesoSeguimiento={accesoSeguimiento} />
  88      case 'gerencia':
  89        if (!yo.demo) return <GestionDiariaGerencia accesoSeguimiento={accesoSeguimiento} />
  90        return (
  91          <div className="mx-auto w-full max-w-[1640px] space-y-6">
  92            <Cabecera pregunta="¿Qué está pasando hoy?" detalle="Registro con datos ficticios del modo demo. El tablero completo y los hábitos consultan la operación desde una sesión real de gerencia.">
  93              <label className="flex items-center gap-2 text-xs font-semibold text-[var(--muted-foreground-strong)]">
  94                Día
  95                <Input type="date" value={dia} max={hoy} onChange={(e) => setDia(e.target.value)} className="w-auto" aria-label="Día del registro" />
  96              </label>
  97            </Cabecera>
  98            <RegistroActividad dia={diaValido} analistaIds={null} mostrarAnalista permitirEquipo permitirExportar />
  99          </div>
 100        )
 101      default:
 102        // Directorio y coordinador no entran (vistas.ts lo impide); si llegan por
 103        // una sesión rara, se dice y no se fabrica nada.
 104        return <PanelVacio icono={CalendarCheck2} titulo="Gestión Diaria no está disponible para tu rol" detalle="Este módulo es para analistas, supervisores y gerencia." />
 105    }
 106  }
```

### `CRM-Avance-Corp/app/src/screens/gestion-diaria/analista.tsx` (líneas 1,638)
```tsx
   1  // Gestión Diaria · Fase 3 — «Mi día» del analista. Responde una sola pregunta:
   2  // ¿a quién llamo AHORA? La cola sale de `crm.cola_accion_v2_fn` (la misma del
   3  // mundo SLA) y el resto del día —marcador, compromisos, señales por lead y los
   4  // descartes con su «Deshacer»— de `crm.gestion_diaria_analista_fn`. Aquí no se
   5  // calcula negocio: se ORDENA (`ordenarColaDiaria`, función pura probada) y se
   6  // presenta. Al guardar un resultado, la pantalla salta a la fila siguiente.
   7  //
   8  // «Hoy» NO cambia: sigue siendo «las 3 cosas de ahora» (decisión de Miguel).
   9  // Esta pantalla es la cola COMPLETA del día, y las dos comparten el primer
  10  // ítem: el lead sin primer intento manda en ambas (test compartido).
  11  //
  12  // DENSIDAD (20/09/2026, queja de los analistas: «demasiada información, muchas
  13  // letras pequeñas»). Lo metodológico, el seguimiento y los descartes viven en
  14  // desplegables con su conteo a la vista. Piso tipográfico 16 px en el cuerpo de
  15  // la cola. Nunca se pliega lo que cambia la decisión de marcar ni un aviso de
  16  // fallo (`role="alert"`).
  17  //
  18  // HORIZONTAL (20/09/2026, Miguel: «esa orientación vertical la odio»). La
  19  // pantalla son DOS paneles hermanos, no una pila:
  20  //   · «Ahora» (izquierda, fijo): el ÚNICO lead que toca, con su nombre grande,
  21  //     el tiempo que le queda EN PALABRAS y la acción primaria — «Llamar».
  22  //     Se queda pegado (`sticky`) mientras la cola se recorre.
  23  //   · «Cola de hoy» (derecha): los cuatro grupos en PESTAÑAS, no apilados; una
  24  //     lista visible a la vez. Cada fila lleva DOS datos —nombre y tiempo— y
  25  //     NINGÚN botón: la fila ES el selector, y quien actúa es el panel «Ahora».
  26  // Un solo rojo: el rojo queda reservado a lo vencido («Se pasó hace 45 min»);
  27  // la severidad se DICE con esas mismas palabras, nunca solo con el color.
  28  // Integración F4 (21/09): conserva el layout local y los arreglos publicados
  29  // de caché parcial, tarea autoritativa, cuatro pestañas, paginación y carreras.
  30  import { useEffect, useId, useMemo, useRef, useState, type JSX, type Ref } from 'react'
  31  import { CalendarClock, ChevronRight, ClipboardList, MoreHorizontal, Phone, RefreshCw, RotateCcw } from 'lucide-react'
  32  import { toast } from 'sonner'
  33  import { useAuth } from '@/lib/auth-context'
  34  import { useAhora } from '@/lib/ahora'
  35  import { useCRMData, usePanelesActions } from '@/lib/store-context'
  36  import { ETAPA_INFO, type Etapa, type Lead, type Tarea } from '@/lib/tipos'
  37  import { tareaQueCierra } from '@/lib/contacto-tarea'
  38  import { presentarCitas } from '@/lib/terminologia'
  39  import {
  40    ETIQUETA_NIVEL, barrasPorHora, cuandoLimaDe, detalleDeFila, filasDiariasDemo,
  41    horaLimaDe, llamadasFueraDeFranja, ordenarColaDiaria, paginaDeFilas, pestanasDiarias, resumenMarcador, textoTasa, tiempoDeFila,
  42    type Descartado, type DiaAnalista, type FilaDiaria, type GrupoDia,
  43  } from '@/lib/gestion-diaria-analista'
  44  import { useDiaAnalista } from '@/data/gestion-diaria-queries'
  45  import { useColaSlaPagina } from '@/data/sla-operacion-queries'
  46  import { AccionesContacto } from '@/components/app/contacto'
  47  import { RegistrarResultado } from '@/components/gestion-diaria/registrar-resultado'
  48  import { PanelCargando, PanelError, PanelVacio } from '@/components/common/estado-panel'
  49  import { Plegable } from '@/components/gestion-diaria/plegable'
  50  import { Badge } from '@/components/ui/badge'
  51  import { Button } from '@/components/ui/button'
  52  import { DropdownItem, DropdownMenu } from '@/components/ui/dropdown-menu'
  53  import { ColaDeHoy, FILAS_POR_PAGINA } from '@/components/gestion-diaria/cola-de-hoy'
  54  
  55  const LIMITE_COLA = 100
  56  // Verde NO (decisión #3 de Miguel): «Bien» va en navy sobre fondo tenue. Y los
  57  // tokens de TEXTO, no los saturados: el chip `soft` pinta el color puro sobre un
  58  // tinte al 12 %, donde `--warning` da ~3:1 y `--destructive` ~4:1 (index.css).
  59  const COLOR_NIVEL: Record<'bien' | 'atencion' | 'bajo', string> = {
  60    bien: 'var(--primary)',
  61    atencion: 'var(--warning-text)',
  62    bajo: 'var(--warning-text)',
  63  }
  64  const TONO_NIVEL: Record<'bien' | 'atencion' | 'bajo', string> = {
  65    bien: 'text-primary',
  66    atencion: 'text-[var(--warning-text)]',
  67    bajo: 'text-[var(--warning-text)]',
  68  }
  69  export function GestionDiariaAnalista(): JSX.Element {
  70    const { yo } = useAuth()
  71    const ahora = useAhora()
  72    const { ambito, tareasDe, asegurarLead, obtenerTareaParaRevision } = useCRMData()
  73    const { abrirLead } = usePanelesActions()
  74    const id = useId()
  75  
  76    // TODO el estado vive AQUÍ, por encima de la cascada de carga/error: el hook
  77    // del día es fail-closed (un refetch fallido devuelve `null`) y, si la
  78    // pestaña o la persona elegida colgaran del subárbol, un parpadeo de red le
  79    // borraría al analista dónde estaba.
  80    const [panel, setPanel] = useState<{ lead: Lead; tarea: Tarea | null } | null>(null)
  81    const [deshaciendo, setDeshaciendo] = useState<string | null>(null)
  82    const [elegido, setElegido] = useState<string | null>(null)
  83    const [pestanaPedida, setPestanaPedida] = useState<GrupoDia | null>(null)
  84    const [pagina, setPagina] = useState(0)
  85    // Los leads cuyo resultado se acaba de guardar: siguen en la cola hasta que el
  86    // servidor conteste, y sin esto «Ahora» volvería a proponer al que ya cerraste.
  87    // Es un CONJUNTO y no un solo id: registrar dos seguidos antes de que vuelva
  88    // el primero hacía que el `finally` de uno destapara al otro.
  89    const [cerrados, setCerrados] = useState<readonly string[]>([])
  90    const [abiertos, setAbiertos] = useState<Record<string, boolean>>({})
  91    const abrir = (clave: string) => (v: boolean) => setAbiertos((a) => ({ ...a, [clave]: v }))
  92    const nombreAhora = useRef<HTMLButtonElement>(null)
  93    const tituloDescartes = useRef<HTMLElement>(null)
  94    const tituloActividad = useRef<HTMLElement>(null)
  95    const panelAhora = useRef<HTMLElement>(null)
  96    const encabezado = useRef<HTMLHeadingElement>(null)
  97    // Leads que ya se pidieron al servidor: `asegurarLead` no está deduplicado y
  98    // la fila elegida se recalcula con el reloj de cada minuto.
  99    const pedidos = useRef(new Set<string>())
 100    const [cargandoLead, setCargandoLead] = useState<string | null>(null)
 101    const [abriendoPanel, setAbriendoPanel] = useState(false)
 102  
 103    const dia = useDiaAnalista(null, null)
 104    // La cola del día: la misma fuente que «Seguimiento comercial», sin filtros.
 105    const cola = useColaSlaPagina({ senal: 'todas', etapa: null, analista_id: null }, null, LIMITE_COLA, !yo?.demo)
 106    const paginaCola = cola.error ? undefined : cola.data
 107    // La cola y el día son DOS consultas: mientras la cola no ha llegado, decir
 108    // «no tienes nada pendiente» sería mentir (solo estarían los sin conversación).
 109    const colaCargando = !yo?.demo && cola.error == null && paginaCola === undefined
 110    const colaCaida = !yo?.demo && cola.error != null
 111  
 112    const leadsPorId = useMemo(() => new Map(ambito.leads.map((l) => [l.id, l])), [ambito.leads])
 113    const filas = useMemo<FilaDiaria[]>(() => {
 114      if (dia.dia === null) return []
 115      const todas = yo?.demo
 116        ? filasDiariasDemo(dia.dia.cartera, ahora, dia.dia.dia)
 117        : ordenarColaDiaria(paginaCola?.items ?? [], dia.dia.cartera)
 118      return cerrados.length === 0 ? todas : todas.filter((f) => !cerrados.includes(f.lead_id))
 119    }, [ahora, cerrados, dia.dia, paginaCola?.items, yo?.demo])
 120  
 121    const pestanas = useMemo(() => pestanasDiarias(filas), [filas])
 122    // El elegido se busca en TODAS las filas, no solo en la pestaña abierta: un
 123    // refetch puede moverlo de grupo (de «Hoy» a «Vencidas» al dar la hora) y la
 124    // pantalla no puede perderlo de vista ni dejar un id fantasma guardado.
 125    const elegida = elegido === null ? null : filas.find((f) => f.lead_id === elegido) ?? null
 126    // Quién manda sobre la pestaña, en orden: el lead elegido (la pestaña LO
 127    // SIGUE), luego la que pidió el analista —AUNQUE ESTÉ VACÍA, porque pulsar un
 128    // grupo y que no se abra es peor que verlo vacío: su conteo ya está a la
 129    // vista—, y solo si nunca pidió ninguna, la primera con gente. Al registrar
 130    // un resultado se borra la petición, así que la cola sigue sola al siguiente
 131    // grupo en vez de dejarte mirando el que acabas de vaciar.
 132    const activa: GrupoDia = elegida !== null
 133      ? elegida.grupo
 134      : pestanaPedida ?? pestanas.find((p) => p.total > 0)?.clave ?? 'primera_atencion'
 135  
 136    const delGrupo = pestanas.find((p) => p.clave === activa)?.filas ?? []
 137    // La página se deriva del elegido: si lo eligió, se ve; si no, la que pidió.
 138    const indiceElegida = elegida === null ? -1 : delGrupo.findIndex((f) => f.lead_id === elegida.lead_id)
 139    const paginaPedida = indiceElegida >= 0 ? Math.floor(indiceElegida / FILAS_POR_PAGINA) : pagina
 140    const vista = paginaDeFilas(delGrupo, paginaPedida, FILAS_POR_PAGINA)
 141    // Sin elección explícita, «Ahora» es el primero de la página: el orden del
 142    // servidor ya dice quién urge más.
 143    const fila = elegida ?? vista.filas[0] ?? null
 144    const posicion = fila === null ? 0 : delGrupo.findIndex((f) => f.lead_id === fila.lead_id) + 1
 145  
 146    // EL TELÉFONO NO VIAJA EN LA COLA. `cola_accion_v2_fn` devuelve del lead solo
 147    // id, nombre, etapa y analista; el número vive en el ámbito del store, que
 148    // desde la Fase 4e «sin topes» ya NO carga todos los leads: los trae por
 149    // demanda. Por eso en «Vencidas» —cuyos leads rara vez están cargados— no
 150    // salía «Llamar» hasta abrir la ficha, que es quien los traía (bug reportado
 151    // en producción el 20/09/2026). Aquí se piden en cuanto se eligen, sin
 152    // obligar al analista a dar un rodeo por la ficha.
 153    useEffect(() => {
 154      const id = fila?.lead_id
 155      if (id === undefined || leadsPorId.has(id) || pedidos.current.has(id)) return
 156      pedidos.current.add(id)
 157      setCargandoLead(id)
 158      let vigente = true
 159      void asegurarLead(id)
 160        .catch(() => {
 161          // Si falló, que se pueda reintentar al volver a elegirlo: si no, el
 162          // lead se quedaría sin número para siempre en esta sesión.
 163          pedidos.current.delete(id)
 164        })
 165        .finally(() => { if (vigente) setCargandoLead((c) => (c === id ? null : c)) })
 166      // Cambiar de fila antes de que conteste no debe dejar el «cargando» pegado
 167      // ni pisar el estado de la fila nueva.
 168      return () => { vigente = false }
 169    }, [asegurarLead, fila?.lead_id, leadsPorId])
 170  
 171    function elegir(f: FilaDiaria) {
 172      setElegido(f.lead_id)
 173      requestAnimationFrame(() => {
 174        panelAhora.current?.scrollIntoView?.({ block: 'nearest' })
 175        nombreAhora.current?.focus()
 176      })
 177    }
 178    function cambiarPestana(grupo: GrupoDia) {
 179      setPestanaPedida(grupo)
 180      setPagina(0)
 181      setElegido(null)
 182    }
 183    /** Se guarda ya acotada: si la lista encoge y vuelve a crecer, no salta sola. */
 184    function irAPagina(p: number) {
 185      setPagina(Math.min(Math.max(p, 0), vista.paginas - 1))
 186    }
 187    async function abrirPanel() {
 188      if (fila === null || abriendoPanel) return
 189      const suyo = leadsPorId.get(fila.lead_id)
 190      if (suyo === undefined) { void abrirLead(fila.lead_id); return }
 191      // `tarea_id` viene de la cola del SERVIDOR y es autoritativa: ese id viaja
 192      // de vuelta para cerrar la tarea. Las tareas del store son una colección
 193      // PARCIAL igual que los leads, así que no encontrarla ahí no significa que
 194      // no exista — se pide por id. Caer al cálculo de siempre cerraría otra
 195      // tarea telefónica, o ninguna (Codex, 20/09).
 196      const pendientes = tareasDe(suyo.id)
 197      if (fila.tarea_id !== null) {
 198        const local = pendientes.find((x) => x.id === fila.tarea_id)
 199        if (local !== undefined) { setPanel({ lead: suyo, tarea: local }); return }
 200        setAbriendoPanel(true)
 201        try {
 202          const traida = await obtenerTareaParaRevision(suyo.id, fila.tarea_id)
 203          // Si el servidor tampoco la da, se abre SIN tarea: mejor no cerrar
 204          // ninguna que cerrar la que no era.
 205          setPanel({ lead: suyo, tarea: traida })
 206        } catch {
 207          setPanel({ lead: suyo, tarea: null })
 208        } finally {
 209          setAbriendoPanel(false)
 210        }
 211        return
 212      }
 213      setPanel({ lead: suyo, tarea: tareaQueCierra(pendientes, 'tel', yo?.id, ahora) ?? null })
 214    }
 215    /** Al guardar, «Ahora» pasa al siguiente y el foco vuelve al encabezado. */
 216    async function alGuardar(leadId: string) {
 217      setCerrados((c) => (c.includes(leadId) ? c : [...c, leadId]))
 218      setElegido(null)
 219      // Registrar es «dame el siguiente»: se suelta la pestaña pedida para que la
 220      // cola avance sola al grupo que todavía tenga gente.
 221      setPestanaPedida(null)
 222      // Dos cuadros: el diálogo restaura primero su foco. Si quedó suelto o
 223      // en las acciones que acaban de guardar, anunciar el siguiente lead.
 224      requestAnimationFrame(() => requestAnimationFrame(() => {
 225        const activo = document.activeElement
 226        const suelto = activo === null || activo === document.body || activo === document.documentElement
 227          || (activo instanceof HTMLElement && activo.closest('[data-accion-panel]') !== null)
 228        if (suelto) (nombreAhora.current ?? encabezado.current)?.focus()
 229      }))
 230      // `allSettled` y no `all`: si una de las dos lecturas falla, la otra sigue
 231      // su curso y aquí no queda un rechazo sin capturar. Y se destapa SOLO este
 232      // lead, no el de un guardado que todavía esté en vuelo.
 233      await Promise.allSettled([dia.recargar(), ...(yo?.demo ? [] : [cola.refetch()])])
 234      setCerrados((c) => c.filter((x) => x !== leadId))
 235    }
 236    async function deshacer(d: Descartado) {
 237      if (deshaciendo !== null) return
 238      setDeshaciendo(d.actividad_id)
 239      try {
 240        const { deshacerResultadoLlamada } = await import('@/data/gestion-diaria-api')
 241        await deshacerResultadoLlamada(d.actividad_id)
 242        // El lead vuelve a la cartera: si estaba tapado por un guardado propio,
 243        // se destapa — pero solo ese, no los de otros guardados en vuelo.
 244        setCerrados((c) => c.filter((x) => x !== d.lead_id))
 245        await dia.recargar()
 246        toast.success(`Deshecho: ${d.lead_nombre} vuelve a tu cartera`)
 247        requestAnimationFrame(() => {
 248          const activo = document.activeElement
 249          if (activo === null || activo === document.body) (tituloDescartes.current ?? encabezado.current)?.focus()
 250        })
 251      } catch (causa) {
 252        const { mensajeDeError } = await import('@/data/crm-api')
 253        toast.error(mensajeDeError(causa, 'No se pudo deshacer el descarte.'))
 254      } finally {
 255        setDeshaciendo(null)
 256      }
 257    }
 258  
 259    /** El marcador de la cabecera abre su propio detalle y lleva el foco allí. */
 260    function verActividad() {
 261      setAbiertos((a) => ({ ...a, detalle: true }))
 262      requestAnimationFrame(() => {
 263        tituloActividad.current?.focus()
 264        tituloActividad.current?.scrollIntoView?.({ block: 'nearest' })
 265      })
 266    }
 267  
 268    const corte = dia.dia ? horaLimaDe(dia.dia.generado_en) : null
 269    const filaActiva = colaCargando ? null : fila
 270  
 271    return (
 272      <div className="mx-auto w-full max-w-[1440px] space-y-6">
 273        <header className="flex flex-wrap items-center justify-between gap-x-6 gap-y-4">
 274          <div className="min-w-0 flex-1 basis-80">
 275            <h2 ref={encabezado} tabIndex={-1} className="text-2xl font-bold leading-tight tracking-tight text-primary sm:text-[28px]">¿A quién llamo ahora?</h2>
 276            <p className="mt-2 text-base text-[var(--muted-foreground-strong)]">
 277              {corte ? `Corte ${corte} (Lima)` : 'Sin corte confirmado'} · actualización cada minuto.
 278            </p>
 279          </div>
 280          <div className="flex w-full min-w-0 max-w-full items-center gap-3 sm:w-auto">
 281            {/* El marcador es CONTEXTO, no trabajo pendiente: una línea en la
 282                cabecera y el detalle a un clic. Antes era una tarjeta entera
 283                debajo de la cola, que es donde el analista tiene que mirar. */}
 284            {dia.dia !== null && (
 285              <button type="button" onClick={verActividad} aria-expanded={abiertos['detalle'] ?? false} aria-controls={`${id}-actividad`}
 286                className="flex min-h-11 min-w-0 max-w-full flex-1 items-center gap-3 rounded-xl border border-border bg-card px-4 py-3 text-left transition-colors hover:border-accent/40 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring focus-visible:ring-[3px] focus-visible:ring-accent/40 sm:flex-none">
 287                <span className="min-w-0 space-y-1">
 288                  <span className="block text-base text-[var(--muted-foreground-strong)]">Mi actividad</span>
 289                  <span className="block text-base font-semibold tabular-nums text-primary">{resumenMarcador(dia.dia)}</span>
 290                </span>
 291                {dia.dia.marcador.nivel !== null && (
 292                  <Badge className="shrink-0 text-base" color={COLOR_NIVEL[dia.dia.marcador.nivel]} dot>{ETIQUETA_NIVEL[dia.dia.marcador.nivel]}</Badge>
 293                )}
 294                <ChevronRight aria-hidden className="size-5 shrink-0 text-[var(--muted-foreground-strong)]" />
 295              </button>
 296            )}
 297            <Button variant="outline" size="sm" className="h-11 w-11 shrink-0 text-base sm:w-auto" aria-disabled={dia.enVuelo} aria-busy={dia.enVuelo}
 298              onClick={() => { if (dia.enVuelo) return; void dia.recargar(); if (!yo?.demo) void cola.refetch() }}>
 299              <RefreshCw aria-hidden className={dia.enVuelo ? 'motion-safe:animate-spin' : ''} /><span className="sr-only sm:not-sr-only">Actualizar</span>
 300            </Button>
 301          </div>
 302        </header>
 303  
 304        {dia.error != null && dia.dia === null ? (
 305          <PanelError mensaje="No se pudo cargar tu día. Lo que ves no está confirmado." onReintentar={() => { void dia.recargar() }} reintentando={dia.enVuelo} />
 306        ) : dia.dia === null && dia.cargando ? (
 307          <PanelCargando filas={6} />
 308        ) : dia.dia === null ? (
 309          <PanelVacio icono={ClipboardList} titulo="Tu día no está disponible" detalle="No hay conexión con el CRM. Se cargará solo cuando vuelva." />
 310        ) : (
 311          <>
 312            {colaCaida && (
 313              <p role="alert" className="rounded-xl border border-destructive/30 bg-destructive/5 px-4 py-3 text-base font-semibold text-[var(--destructive-text)]">
 314                No se pudo leer la cola del servidor: solo se muestran los leads sin conversación. Reintenta para verla completa.
 315              </p>
 316            )}
 317            {dia.dia.cartera_truncada && (
 318              <p role="status" className="text-base font-semibold text-[var(--muted-foreground-strong)]">
 319                Tu cartera abierta pasa de 500 leads: las señales muestran los 500 que llevan más tiempo sin conversación.
 320              </p>
 321            )}
 322  
 323            {/* DOS PANELES HERMANOS, no una pila: el que actúa y el que elige. */}
 324            <div className="flex flex-col gap-6 lg:flex-row lg:items-start">
 325              <PanelAhora fila={filaActiva} lead={filaActiva ? leadsPorId.get(filaActiva.lead_id) ?? null : null}
 326                sinConversacionDias={dia.dia.sin_conversacion_dias} ahora={ahora} cargando={colaCargando} colaCaida={colaCaida}
 327                seccionRef={panelAhora} nombreRef={nombreAhora}
 328                posicion={posicion} total={delGrupo.length}
 329                cargandoLead={filaActiva !== null && cargandoLead === filaActiva.lead_id} abriendoPanel={abriendoPanel}
 330                onRegistrar={() => { if (filaActiva) void abrirPanel() }}
 331                onAbrirFicha={() => { if (filaActiva) void abrirLead(filaActiva.lead_id) }} />
 332  
 333              <ColaDeHoy
 334                idBase={id} pestanas={pestanas} activa={activa} onPestana={cambiarPestana}
 335                pagina={vista.pagina} onPagina={irAPagina}
 336                elegido={filaActiva?.lead_id ?? null} onElegir={elegir}
 337                ahora={ahora} cargando={colaCargando} hayMas={paginaCola?.hay_mas === true} colaCaida={colaCaida}
 338              />
 339            </div>
 340  
 341            <Actividad id={`${id}-actividad`} dia={dia.dia} abierto={abiertos['detalle'] ?? false} onAbrir={abrir('detalle')} summaryRef={tituloActividad} />
 342            <Compromisos dia={dia.dia} abierto={abiertos['compromisos'] ?? false} onAbrir={abrir('compromisos')}
 343              onAbrirFicha={(leadId) => { void abrirLead(leadId) }} />
 344            <Descartados dia={dia.dia} deshaciendo={deshaciendo} onDeshacer={(d) => { void deshacer(d) }}
 345              abierto={abiertos['descartados'] ?? false} onAbrir={abrir('descartados')} summaryRef={tituloDescartes}
 346              onAbrirFicha={(leadId) => { void abrirLead(leadId) }} />
 347            {yo?.demo && <p className="text-base text-muted-foreground">Datos de ejemplo: en la sesión real tu día sale del servidor.</p>}
 348          </>
 349        )}
 350  
 351        {panel !== null && (
 352          <RegistrarResultado lead={panel.lead} tarea={panel.tarea} onClose={() => setPanel(null)}
 353            onGuardado={() => void alGuardar(panel.lead.id)} />
 354        )}
 355      </div>
 356    )
 357  }
 358  
 359  /**
 360   * El panel «Ahora»: UN lead, UNA acción primaria. Se queda pegado arriba
 361   * mientras la cola se recorre, para que el analista nunca pierda de vista a
 362   * quién está llamando. Lo secundario —WhatsApp aparte, que trae su propio
 363   * diálogo de resultado— vive detrás de «···» (ley de Hick).
 364   */
 365  function PanelAhora({ fila, lead, sinConversacionDias, ahora, cargando, colaCaida, onRegistrar, onAbrirFicha, seccionRef, nombreRef, cargandoLead, abriendoPanel, posicion, total }: {
 366    fila: FilaDiaria | null
 367    lead: Lead | null
 368    sinConversacionDias: number
 369    ahora: number
 370    cargando: boolean
 371    colaCaida: boolean
 372    cargandoLead: boolean
 373    abriendoPanel: boolean
 374    posicion: number
 375    total: number
 376    onRegistrar: () => void
 377    onAbrirFicha: () => void
 378    seccionRef: Ref<HTMLElement>
 379    nombreRef: Ref<HTMLButtonElement>
 380  }): JSX.Element {
 381    const id = useId()
 382    const etapa = fila === null ? null : ETAPA_INFO[fila.etapa as Etapa]?.label ?? fila.etapa
 383    const tiempo = fila === null ? null : tiempoDeFila(fila, ahora)
 384    return (
 385      <section ref={seccionRef} aria-labelledby={`${id}-ahora`}
 386        className="w-full rounded-xl border border-border bg-card shadow-[var(--shadow-card)] lg:sticky lg:top-4 lg:w-[36%] lg:min-w-[320px] lg:max-w-[420px] lg:shrink-0">
 387        <div className="flex items-center gap-3 rounded-t-xl bg-primary px-6 py-4 text-primary-foreground">
 388          <Phone aria-hidden className="size-5" />
 389          <h3 id={`${id}-ahora`} className="text-xl font-semibold">Ahora</h3>
 390          {fila !== null && total > 0 && <span className="ml-auto text-base tabular-nums text-primary-foreground/80"><span className="sr-only">Contacto </span>{posicion} de {total}<span className="sr-only"> en este grupo</span></span>}
 391        </div>
 392        {fila === null ? (
 393          <p className="p-6 text-base leading-relaxed text-[var(--muted-foreground-strong)]">
 394            {cargando ? 'Buscando a quién llamar…'
 395              : colaCaida ? 'No se pudo leer tu cola: no sabemos a quién te toca llamar. Pulsa «Actualizar».'
 396                : 'Nada pendiente ahora. Cuando entre un lead nuevo aparecerá aquí.'}
 397          </p>
 398        ) : (
 399          <>
 400            <div className="space-y-4 p-4 sm:p-6">
 401              <div className="min-w-0 space-y-1">
 402                <button ref={nombreRef} type="button" onClick={onAbrirFicha}
 403                  aria-label={`Abrir la ficha de ${fila.nombre_completo}`}
 404                  className="inline-flex min-h-11 items-start rounded-md text-left text-xl font-bold leading-7 tracking-tight text-primary underline-offset-4 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring focus-visible:ring-[3px] focus-visible:ring-accent/40 sm:text-2xl sm:leading-8">
 405                  {fila.nombre_completo}
 406                </button>
 407                <p className="text-base text-[var(--muted-foreground-strong)]">{etapa}</p>
 408              </div>
 409              <div className="space-y-3 rounded-lg bg-muted/60 p-4">
 410                {tiempo !== null && (
 411                  <Badge className="self-start text-base" color={tiempo.vencido ? 'var(--destructive-text)' : 'var(--accent-press)'}>{tiempo.texto}</Badge>
 412                )}
 413                <p className="text-base leading-relaxed text-[var(--muted-foreground-strong)]">
 414                  {fila.senal === null ? 'Historial no cargado. Ábrelo en la ficha antes de llamar.' : detalleDeFila(fila, sinConversacionDias)}
 415                </p>
 416              </div>
 417            </div>
 418            <div className="space-y-3 rounded-b-xl border-t border-border bg-muted/30 p-4 sm:px-6">
 419              {lead !== null && <p className="text-xl font-bold tabular-nums text-primary">{lead.telefono}</p>}
 420              <div className="flex items-start gap-2">
 421                {lead !== null ? (
 422                  // `key={lead.id}`: UNA instancia por lead. Antes las acciones
 423                  // vivían dentro de cada fila y se desmontaban con ella; aquí hay
 424                  // una sola caja que cambia de lead, y si el refresco de cada
 425                  // minuto cambiaba el lead con el diálogo de resultado ABIERTO, el
 426                  // resultado se escribía sobre el lead equivocado. La clave fuerza
 427                  // el remontaje: el contacto a medias se cae a la vista, que es
 428                  // reparable — atribuirlo a otra persona, no (hallazgo de Codex).
 429                  <div className="min-w-0 flex-1 [&>div]:flex-col [&>div]:items-stretch [&>div>a]:justify-center [&>div>button]:justify-center" data-accion-panel="si">
 430                    <AccionesContacto key={lead.id} lead={lead} destacada grande onRegistrarLlamada={onRegistrar} />
 431                  </div>
 432                ) : (
 433                  <p role="status" className="min-w-0 flex-1 text-base text-[var(--muted-foreground-strong)]">
 434                    {cargandoLead ? 'Buscando su número…' : 'No se pudo traer su número. Abre la ficha para llamar.'}
 435                  </p>
 436                )}
 437                <DropdownMenu
 438                  trigger={
 439                    <button type="button" data-accion-panel="si"
 440                      aria-label={`Más acciones para ${fila.nombre_completo}: registrar resultado y ver la ficha`}
 441                      className="grid size-12 shrink-0 cursor-pointer place-items-center rounded-xl border border-border-strong bg-card text-foreground transition-colors hover:bg-muted focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring focus-visible:ring-[3px] focus-visible:ring-accent/40">
 442                      <MoreHorizontal aria-hidden className="size-5" />
 443                    </button>
 444                  }>
 445                  <DropdownItem className="min-h-11 text-base" disabled={abriendoPanel} onSelect={() => { if (!abriendoPanel) onRegistrar() }}>Registrar resultado</DropdownItem>
 446                  <DropdownItem className="min-h-11 text-base" onSelect={onAbrirFicha}>Ver la ficha completa</DropdownItem>
 447                </DropdownMenu>
 448              </div>
 449            </div>
 450          </>
 451        )}
 452      </section>
 453    )
 454  }
 455  
 456  /** Una métrica del marcador: etiqueta arriba, número grande, apoyo debajo. */
 457  function Metrica({ etiqueta, valor, valorAccesible, apoyo, tono }: {
 458    etiqueta: string
 459    valor: string
 460    /** Qué debe OÍR un lector de pantalla cuando el valor es un símbolo mudo. */
 461    valorAccesible?: string | undefined
 462    apoyo?: string | undefined
 463    tono?: string | undefined
 464  }): JSX.Element {
 465    return (
 466      <li className="min-w-0">
 467        <p className="text-base font-semibold text-[var(--muted-foreground-strong)]">{etiqueta}</p>
 468        <p className={`text-2xl font-extrabold leading-tight tabular-nums ${tono ?? 'text-foreground'}`}>
 469          {valorAccesible !== undefined ? (
 470            <>
 471              <span aria-hidden="true">{valor}</span>
 472              <span className="sr-only">{valorAccesible}</span>
 473            </>
 474          ) : valor}
 475        </p>
 476        {apoyo !== undefined && <p className="mt-0.5 text-base text-[var(--muted-foreground-strong)]">{apoyo}</p>}
 477      </li>
 478    )
 479  }
 480  
 481  /**
 482   * «Mi actividad de hoy»: el marcador completo, plegado. Su línea de titulares
 483   * vive arriba, en la cabecera (`resumenMarcador`), así que aquí no se esconde
 484   * ningún dato que el analista necesite de un vistazo — solo el detalle: cómo se
 485   * cuentan las llamadas, primera y última, y el reparto por hora (decisión #8).
 486   * La decisión #7 se respeta en los dos sitios: el % SIEMPRE con su conteo.
 487   */
 488  function Actividad({ id: idBloque, dia, abierto, onAbrir, summaryRef }: {
 489    id: string
 490    dia: DiaAnalista
 491    abierto: boolean
 492    onAbrir: (v: boolean) => void
 493    summaryRef: Ref<HTMLElement>
 494  }): JSX.Element {
 495    const id = useId()
 496    const m = dia.marcador
 497    const barras = barrasPorHora(m)
 498    const fuera = llamadasFueraDeFranja(m)
 499    return (
 500      <Plegable id={idBloque} titulo="Mi actividad de hoy" resumen="cómo se cuenta y las llamadas por hora" abierto={abierto} onAbrir={onAbrir} summaryRef={summaryRef}>
 501        <div className="space-y-4">
 502          {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
 503          <ul role="list" aria-label="Marcador de hoy" className="flex flex-wrap items-start gap-x-10 gap-y-4">
 504            <Metrica etiqueta="Llamadas" valor={String(m.llamadas)} apoyo={`${m.contestadas} contestadas`} tono="text-primary" />
 505            <Metrica etiqueta="Tasa de contacto" valor={textoTasa(m)}
 506              // El «—» de la tasa sin llamadas útiles no lo pronuncia un lector de
 507              // pantalla: se dice «sin dato» para que no suene a cero.
 508              {...(m.tasa_contacto_pct === null ? { valorAccesible: 'sin dato' } : {})}
 509              apoyo={m.nivel === null ? `Se juzga desde ${dia.umbrales.minimo_llamadas_utiles} llamadas útiles` : ETIQUETA_NIVEL[m.nivel]}
 510              tono={m.nivel === null ? 'text-foreground' : TONO_NIVEL[m.nivel]} />
 511            <Metrica etiqueta={presentarCitas('Citas agendadas')} valor={String(m.citas_agendadas)} />
 512          </ul>
 513          <p className="text-base text-[var(--muted-foreground-strong)]">
 514            Tocaste {m.leads_tocados} {m.leads_tocados === 1 ? 'lead' : 'leads'}. Llamadas = marcadas + no contestadas.
 515            No incluye WhatsApp ni citas. Un número errado no entra en la tasa.
 516            {m.primera_llamada_en !== null && ` Primera ${horaLimaDe(m.primera_llamada_en)}, última ${horaLimaDe(m.ultima_llamada_en)} (Lima).`}
 517          </p>
 518          {m.llamadas > 0 ? (
 519            <div>
 520              <h4 id={`${id}-horas`} className="text-base font-semibold text-[var(--muted-foreground-strong)]">Llamadas por hora (08–20, Lima)</h4>
 521              {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
 522              <ul role="list" className="mt-2 flex items-end gap-1.5" aria-labelledby={`${id}-horas`}>
 523                {barras.map((b) => (
 524                  <li key={b.hora} className="flex min-w-0 flex-1 flex-col items-center gap-1">
 525                    <span className="w-full rounded-t bg-primary/80" style={{ height: `${Math.round((b.llamadas / b.maximo) * 56) + 2}px` }}
 526                      aria-hidden />
 527                    <span className="sr-only">
 528                      {b.hora}:00 — {b.llamadas} {b.llamadas === 1 ? 'llamada' : 'llamadas'}, {b.contestadas} {b.contestadas === 1 ? 'contestada' : 'contestadas'}
 529                    </span>
 530                    <span aria-hidden className="text-base tabular-nums text-[var(--muted-foreground-strong)]">{b.hora}</span>
 531                  </li>
 532                ))}
 533              </ul>
 534              {fuera > 0 && <p className="mt-2 text-base text-[var(--muted-foreground-strong)]">{fuera} fuera de la franja 08–20.</p>}
 535            </div>
 536          ) : (
 537            <p className="text-base text-[var(--muted-foreground-strong)]">Todavía no has marcado hoy.</p>
 538          )}
 539        </div>
 540      </Plegable>
 541    )
 542  }
 543  
 544  /**
 545   * Compromisos: SOLO de mañana en adelante — el servidor los devuelve desde
 546   * mañana 00:00 Lima (`gestion_diaria_analista_fn`, `v_manana`), y lo de hoy y
 547   * lo vencido ya está en la cola de arriba. Por eso se puede plegar sin
 548   * esconder nada accionable hoy; el conteo queda a la vista en el resumen.
 549   */
 550  function Compromisos({ dia, abierto, onAbrir, onAbrirFicha }: {
 551    dia: DiaAnalista
 552    abierto: boolean
 553    onAbrir: (v: boolean) => void
 554    onAbrirFicha: (leadId: string) => void
 555  }): JSX.Element {
 556    return (
 557      <Plegable titulo="Mi seguimiento" abierto={abierto} onAbrir={onAbrir}
 558        resumen={`${dia.compromisos_total} ${dia.compromisos_total === 1 ? 'compromiso' : 'compromisos'} desde mañana`}>
 559        {dia.compromisos.length === 0 ? (
 560          <PanelVacio icono={CalendarClock} titulo="Sin compromisos a partir de mañana" detalle="Lo de hoy y lo vencido ya está en tu cola." />
 561        ) : (
 562          <>
 563            {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
 564            <ol role="list" aria-label="Mis compromisos" className="divide-y divide-border">
 565              {dia.compromisos.map((c) => (
 566                <li key={c.tarea_id} className="flex flex-wrap items-center justify-between gap-2 py-3 first:pt-0 last:pb-0">
 567                  <div className="min-w-0">
 568                    <button type="button" onClick={() => onAbrirFicha(c.lead_id)}
 569                      className="inline-flex min-h-9 items-center rounded-md text-base font-semibold text-primary underline-offset-2 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring focus-visible:ring-[3px] focus-visible:ring-accent/40">
 570                      {c.lead_nombre}
 571                    </button>
 572                    <p className="text-base text-[var(--muted-foreground-strong)]">
 573                      {c.tipo === 'reunion' ? presentarCitas('Reunión') : 'Llamada'} · {presentarCitas(c.titulo)}
 574                      {c.modalidad_reunion !== null ? ` · ${c.modalidad_reunion}` : ''}
 575                    </p>
 576                  </div>
 577                  <span className="text-base font-semibold tabular-nums text-foreground">{cuandoLimaDe(c.vence_en)}</span>
 578                </li>
 579              ))}
 580            </ol>
 581            {dia.compromisos_total > dia.compromisos.length && (
 582              <p className="mt-3 text-base text-[var(--muted-foreground-strong)]">
 583                Se muestran los {dia.compromisos.length} más próximos de {dia.compromisos_total}. El resto está en Agenda.
 584              </p>
 585            )}
 586          </>
 587        )}
 588      </Plegable>
 589    )
 590  }
 591  
 592  function Descartados({ dia, deshaciendo, onDeshacer, onAbrirFicha, abierto, onAbrir, summaryRef }: {
 593    dia: DiaAnalista
 594    deshaciendo: string | null
 595    onDeshacer: (d: Descartado) => void
 596    onAbrirFicha: (leadId: string) => void
 597    abierto: boolean
 598    onAbrir: (v: boolean) => void
 599    summaryRef: Ref<HTMLElement>
 600  }): JSX.Element | null {
 601    if (dia.descartados.length === 0) return null
 602    return (
 603      <Plegable titulo="Descartados hoy" resumen={`${dia.descartados.length} · se pueden deshacer 24 h`}
 604        abierto={abierto} onAbrir={onAbrir} summaryRef={summaryRef}>
 605        <p className="text-base text-[var(--muted-foreground-strong)]">
 606          Están en el Centro de rescate con su motivo. Puedes deshacer el descarte durante 24 horas; el lead vuelve a tu cartera con un ciclo nuevo.
 607        </p>
 608        {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
 609        <ol role="list" aria-label="Descartados hoy" className="mt-3 divide-y divide-border">
 610          {dia.descartados.map((d) => (
 611            <li key={d.actividad_id} className="flex flex-wrap items-center justify-between gap-2 py-3 first:pt-0 last:pb-0">
 612              <div className="min-w-0">
 613                <button type="button" onClick={() => onAbrirFicha(d.lead_id)}
 614                  className="inline-flex min-h-9 items-center rounded-md text-base font-semibold text-primary underline-offset-2 hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ring focus-visible:ring-[3px] focus-visible:ring-accent/40">
 615                  {d.lead_nombre}
 616                </button>
 617                <p className="text-base text-[var(--muted-foreground-strong)]">
 618                  {horaLimaDe(d.creado_en)} · {(d.submotivo ?? d.resultado ?? '').replaceAll('_', ' ')}
 619                  {d.deshecho ? ' · ya deshecho' : d.no_insista ? ' · pidió no ser contactado' : !d.vigente ? ' · el descarte ya no está vigente' : ''}
 620                </p>
 621              </div>
 622              {d.puede_deshacer ? (
 623                // `aria-disabled` y no `disabled`: deshabilitar el botón enfocado
 624                // manda el foco al body (regla de la casa, boton-guardar.tsx).
 625                <Button variant="outline" size="sm" className="h-11 text-base" aria-disabled={deshaciendo !== null}
 626                  aria-label={`Deshacer el descarte de ${d.lead_nombre}`}
 627                  onClick={() => { if (deshaciendo === null) onDeshacer(d) }}>
 628                  <RotateCcw aria-hidden /> {deshaciendo === d.actividad_id ? 'Deshaciendo…' : 'Deshacer'}
 629                </Button>
 630              ) : (
 631                <span className="text-base text-[var(--muted-foreground-strong)]">Sin deshacer</span>
 632              )}
 633            </li>
 634          ))}
 635        </ol>
 636      </Plegable>
 637    )
 638  }
```

### `CRM-Avance-Corp/app/src/components/gestion-diaria/cola-de-hoy.tsx` (líneas 1,158)
```tsx
   1  // La cola del día: cuatro grupos en PESTAÑAS, una sola lista a la vista.
   2  //
   3  // Antes se pintaban los cuatro bloques uno debajo de otro y había que
   4  // desplazarse para ver la mitad. Ahora el conteo de cada pestaña deja ver el
   5  // volumen sin ocupar la pantalla, y solo se lee lo que toca. Cada fila tiene
   6  // DOS líneas —nombre y tiempo— porque el contexto largo se mudó a «Ahora»:
   7  // elegir una fila la lleva allí.
   8  //
   9  // La fila es un `<button>` real con `aria-current`, no un `div` con onClick ni
  10  // un `aria-pressed`: esto es una selección única dentro de una lista, y así el
  11  // tabulador y el lector de pantalla la entienden sin inventar teclado propio.
  12  import type { JSX } from 'react'
  13  import { Check, ChevronLeft, ChevronRight, PhoneCall } from 'lucide-react'
  14  import { ChipTiempo } from '@/components/gestion-diaria/chip-tiempo'
  15  import { PanelCargando, PanelVacio } from '@/components/common/estado-panel'
  16  import { Button } from '@/components/ui/button'
  17  import { Tabs } from '@/components/ui/tabs'
  18  import { cn } from '@/lib/utils'
  19  import { paginaDeFilas, type FilaDiaria, type GrupoDia } from '@/lib/gestion-diaria-analista'
  20  import { hashDe } from '@/lib/router'
  21  
  22  export const FILAS_POR_PAGINA = 5
  23  
  24  export interface PestanaCola {
  25    clave: GrupoDia
  26    etiqueta: string
  27    ayuda: string
  28    total: number
  29    filas: FilaDiaria[]
  30  }
  31  
  32  export function ColaDeHoy({
  33    idBase, pestanas, activa, onPestana, pagina, onPagina, elegido, onElegir, ahora, cargando, hayMas, colaCaida,
  34  }: {
  35    /** Base de `useId()` de la pantalla: dos instancias no pueden compartir id. */
  36    idBase: string
  37    pestanas: readonly PestanaCola[]
  38    activa: GrupoDia
  39    onPestana: (grupo: GrupoDia) => void
  40    pagina: number
  41    onPagina: (pagina: number) => void
  42    elegido: string | null
  43    onElegir: (fila: FilaDiaria) => void
  44    ahora: number
  45    cargando: boolean
  46    /** El servidor dice que hay más de lo que cabe en esta lectura. */
  47    hayMas: boolean
  48    /**
  49     * La cola del servidor no llegó. Los tres primeros grupos SALEN de ella, así
  50     * que sus conteos no son ceros: son desconocidos. Decir «Vencidas (0)» haría
  51     * que el analista se fuera a casa creyendo que no debía nada (Codex, 20/09).
  52     */
  53    colaCaida: boolean
  54  }): JSX.Element {
  55    const grupo = pestanas.find((p) => p.clave === activa) ?? pestanas[0]
  56    const vista = paginaDeFilas(grupo?.filas ?? [], pagina, FILAS_POR_PAGINA)
  57    const sinAnterior = vista.pagina === 0
  58    const sinSiguiente = vista.pagina >= vista.paginas - 1
  59    const vacioTodo = pestanas.every((p) => p.total === 0)
  60  
  61    return (
  62      <section aria-labelledby={`${idBase}-cola`} className="flex min-w-0 flex-1 flex-col gap-5 rounded-xl border border-border bg-card p-4 shadow-[var(--shadow-card)] sm:p-6">
  63        <div className="space-y-1">
  64          <h3 id={`${idBase}-cola`} className="text-xl font-semibold text-primary">Cola de hoy</h3>
  65          <p className="text-base text-[var(--muted-foreground-strong)]">Elige un contacto para ver su contexto y actuar.</p>
  66        </div>
  67  
  68        {cargando ? (
  69          <PanelCargando filas={FILAS_POR_PAGINA} />
  70        ) : vacioTodo && !colaCaida ? (
  71          <PanelVacio
  72            icono={PhoneCall}
  73            titulo="No tienes nada pendiente ahora"
  74            detalle="Ningún lead sin primer intento, ninguna tarea vencida ni de hoy, y toda tu cartera tuvo conversación esta semana."
  75            tamano="grande"
  76          />
  77        ) : (
  78          <Tabs
  79            etiqueta="Grupos de la cola"
  80            tamano="grande"
  81            valor={activa}
  82            onCambio={onPestana}
  83            pestanas={pestanas.map((p) => ({
  84              valor: p.clave,
  85              etiqueta: p.etiqueta,
  86              // Con la cola caída, los grupos que salen de ella no tienen conteo
  87              // conocido: «?» y no «0». Con `hayMas` el conteo es un MÍNIMO.
  88              extra: colaCaida && p.clave !== 'sin_conversacion'
  89                ? '?'
  90                : hayMas ? `${p.total}+` : String(p.total),
  91            }))}
  92            className="flex min-h-0 flex-1 flex-col [&>[role=tablist]]:max-w-full [&>[role=tablist]]:flex-row [&>[role=tablist]]:overflow-x-auto [&_[role=tab]]:flex-none [&_[role=tab]]:whitespace-nowrap [&_[role=tab][aria-selected=true]]:font-semibold [&>[role=tabpanel]]:flex [&>[role=tabpanel]]:min-h-0 [&>[role=tabpanel]]:flex-1 [&>[role=tabpanel]]:flex-col [&>[role=tabpanel]]:gap-4"
  93          >
  94            <p className="text-base text-[var(--muted-foreground-strong)]">{grupo?.ayuda}</p>
  95  
  96            {vista.total === 0 ? (
  97              <p role="status" className="text-base text-[var(--muted-foreground-strong)]">
  98                {colaCaida && grupo?.clave !== 'sin_conversacion'
  99                  ? 'No se pudo leer este grupo del servidor. No está vacío: no se sabe. Actualiza para verlo.'
 100                  : 'Nada en este grupo. Mira las otras pestañas: su número está al lado del nombre.'}
 101              </p>
 102            ) : (
 103              <>
 104                {/* oxlint-disable-next-line jsx-a11y/no-redundant-roles */}
 105                <ol role="list" aria-label={`${grupo?.etiqueta} (${vista.rango})`} className="flex min-h-0 flex-1 flex-col gap-2">
 106                  {vista.filas.map((fila) => {
 107                    const seleccionada = fila.lead_id === elegido
 108                    return (
 109                      <li key={fila.lead_id} className="flex flex-1">
 110                        <button
 111                          type="button"
 112                          {...(seleccionada ? { 'aria-current': true as const } : {})}
 113                          onClick={() => onElegir(fila)}
 114                          className={cn(
 115                            'flex w-full min-h-[5.5rem] cursor-pointer items-center justify-between gap-4 rounded-xl border-2 px-4 py-4 text-left transition-colors sm:px-5',
 116                            'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent focus-visible:ring-offset-2 focus-visible:ring-offset-card',
 117                            seleccionada
 118                              ? 'border-primary bg-primary/[0.03]'
 119                              : 'border-transparent bg-muted/50 hover:border-border-strong hover:bg-muted',
 120                          )}
 121                        >
 122                          <span className="flex min-w-0 flex-col gap-1">
 123                            <span className="truncate text-lg font-semibold leading-7 text-primary">{fila.nombre_completo}</span>
 124                            <ChipTiempo fila={fila} ahora={ahora} className="self-start" />
 125                          </span>
 126                          {seleccionada && (
 127                            <span className="flex shrink-0 items-center gap-2 text-base font-semibold text-primary"><Check aria-hidden className="size-5" /><span className="sr-only sm:not-sr-only">Elegido</span></span>
 128                          )}
 129                        </button>
 130                      </li>
 131                    )
 132                  })}
 133                </ol>
 134  
 135                <div className="flex flex-wrap items-center justify-between gap-3 border-t border-border pt-4">
 136                  {/* Se ANUNCIA: al pasar de página cambian las cinco filas y sin
 137                      esto el lector de pantalla no diría nada (WCAG 4.1.3). */}
 138                  <p role="status" aria-live="polite" className="text-base text-[var(--muted-foreground-strong)]">
 139                    {vista.rango}{hayMas && <> de los cargados · <a className="font-semibold text-primary underline underline-offset-4" href={hashDe('gestion-diaria', null, undefined, undefined, { tipo: 'cola' })}>Ver todas las oportunidades</a></>}
 140                  </p>
 141                  <div className="flex gap-2">
 142                    {/* `aria-disabled` y no `disabled`, con la guarda en el handler:
 143                        el botón se deshabilita a sí mismo al pulsarse (última página)
 144                        y un `disabled` sobre el elemento enfocado manda el foco al
 145                        body — la misma regla de la casa que «Deshacer». */}
 146                    <Button variant="outline" className="h-12 text-base font-normal aria-disabled:opacity-50 aria-disabled:cursor-default"
 147                      aria-disabled={sinAnterior} onClick={() => { if (!sinAnterior) onPagina(vista.pagina - 1) }}><ChevronLeft aria-hidden />Anterior</Button>
 148                    <Button variant="outline" className="h-12 text-base font-normal aria-disabled:opacity-50 aria-disabled:cursor-default"
 149                      aria-disabled={sinSiguiente} onClick={() => { if (!sinSiguiente) onPagina(vista.pagina + 1) }}>Siguiente<ChevronRight aria-hidden /></Button>
 150                  </div>
 151                </div>
 152              </>
 153            )}
 154          </Tabs>
 155        )}
 156      </section>
 157    )
 158  }
```

### `CRM-Avance-Corp/app/src/components/gestion-diaria/chip-tiempo.tsx` (líneas 1,36)
```tsx
   1  // El tiempo de una fila del día, dicho en palabras y con su tono.
   2  //
   3  // Reemplaza al chip «Crítica» y a toda mención de «SLA» en pantalla: el analista
   4  // lee «Quedan 40 min» o «Se pasó hace 2 días», no una sigla (regla de Miguel,
   5  // 20/09/2026). El estado NO viaja solo en el color — el texto ya lo dice —, así
   6  // que cumple la regla de la casa por construcción.
   7  //
   8  // Tamaño: 16 px, el piso de la pantalla del analista. `Badge` nace a 11 px para
   9  // los chips de ficha, así que aquí se sube explícitamente; el color va por la
  10  // variante «-text» (oscura) porque `soft` pinta sobre un tinte al 12 % y los
  11  // tonos puros no llegan al contraste de texto (está escrito en `index.css`).
  12  import type { JSX } from 'react'
  13  import { Badge } from '@/components/ui/badge'
  14  import { textoTiempoDeFila, type FilaDiaria } from '@/lib/gestion-diaria-analista'
  15  
  16  const COLOR_TONO = {
  17    vencido: 'var(--destructive-text)',
  18    pendiente: 'var(--accent-press)',
  19    neutro: 'var(--muted-foreground-strong)',
  20  } as const
  21  
  22  export function ChipTiempo({ fila, ahora, className }: {
  23    fila: FilaDiaria
  24    ahora: number
  25    className?: string | undefined
  26  }): JSX.Element {
  27    const { texto, tono } = textoTiempoDeFila(fila, ahora)
  28    return (
  29      <Badge
  30        color={COLOR_TONO[tono]}
  31        className={`px-3 py-0.5 text-base font-normal leading-6 ${className ?? ''}`}
  32      >
  33        {texto}
  34      </Badge>
  35    )
  36  }
```

### `CRM-Avance-Corp/app/src/components/app/contacto.tsx` (líneas 1,15)
```tsx
   1  // Acciones de contacto — Sprint A (F1d), ajustado 2026-07-17. Un solo
   2  // componente para las 3 superficies: header del lead-drawer (completo) y colas
   3  // de hoy/vendedor y hoy/supervisor (compacto).
   4  //   · Llamar: DEPENDE DEL APARATO. En el CELULAR es un enlace `tel:` que abre
   5  //     el marcador, y el resultado se pregunta AL VOLVER — mismo mecanismo que
   6  //     wa.me. En la LAPTOP no hay radio (un `tel:` ahí no marca nada), así que
   7  //     se conserva COPIAR el número al portapapeles y abrir el diálogo de una:
   8  //     en las colas no existe el composer del timeline, este es el único
   9  //     registro de la llamada. La detección es por INTERACCIÓN (`usePuedeMarcar`:
  10  //     hover:none + pointer:coarse), NUNCA por user-agent ni por ancho a secas.
  11  //   · WhatsApp (wa.me) abre WhatsApp Web en otra pestaña; al volver ≥4 s después
  12  //     un dialog pregunta el resultado y lo registra vía registrarActividad.
  13  // Directorio (solo lectura) copia/abre pero NO registra (sin seguimiento).
  14  // El contenedor corta la propagación: viven dentro de filas clicables (colas)
  15  // y no deben abrir la ficha al contactar.
```

### `CRM-Avance-Corp/app/src/components/app/contacto.tsx` (líneas 79,177)
```tsx
  79  export function AccionesContacto({
  80    lead,
  81    compacto,
  82    soloIcono,
  83    conAgendar,
  84    destacada,
  85    grande,
  86    onGuardado,
  87    onRegistrarLlamada,
  88  }: {
  89    lead: LeadContactable
  90    compacto?: boolean
  91    /** Oculta las etiquetas SIEMPRE (columnas angostas, p. ej. la cola en 2/5). */
  92    soloIcono?: boolean
  93    /**
  94     * Añade "Agendar": crea el siguiente toque por defecto SIN abrir la ficha.
  95     * Vive aquí y no en la fila a propósito — este contenedor ya tiene el escudo
  96     * de propagación, y un `<button>` pelado dentro de la fila haría que Enter
  97     * abriera la ficha en vez de agendar.
  98     */
  99    conAgendar?: boolean
 100    /** Targets táctiles de 44 px para la franja primaria «Ahora» (Ley de Fitts). */
 101    destacada?: boolean
 102    /**
 103     * 48 px y 18 px para «Mi día», donde «Llamar» es la ÚNICA acción primaria de
 104     * la pantalla y el piso tipográfico es 16 px (queja de los analistas del
 105     * 20/09/2026). Se apoya en `destacada`, que ya tiñe el primer hijo de azul.
 106     */
 107    grande?: boolean
 108    /**
 109     * Aviso de que la LLAMADA quedó registrada. Lo usa «Mi día» para pasar al
 110     * siguiente lead de la cola desde la acción primaria, igual que ya hacía al
 111     * registrar desde el panel: sin esto, el camino principal —Llamar— dejaba la
 112     * cola parada en el lead recién atendido (hallazgo de Codex, 20/09/2026).
 113     */
 114    onGuardado?: (() => void) | undefined
 115    /** «Mi día» resuelve su tarea de servidor y usa el mismo panel desde ambos accesos. */
 116    onRegistrarLlamada?: (() => void) | undefined
 117  }): JSX.Element {
 118    const { yo } = useAuth()
 119    const escribe = puedeEscribir(yo?.rol)
 120    // Escritorio y celular NO comparten camino de "Llamar" — ver la cabecera.
 121    const puedeMarcar = usePuedeMarcar()
 122    // Contacto pendiente de ESTA instancia (canal + cuándo se hizo click).
 123    const pendiente = useRef<{ canal: Canal; ts: number } | null>(null)
 124    const [dialogo, setDialogo] = useState<Canal | null>(null)
 125    const vigente = useRef(true)
 126    useEffect(() => {
 127      vigente.current = true
 128      return () => { vigente.current = false }
 129    }, [])
 130    // Fase 4e «sin topes»: antes de registrar un contacto el store tiene que
 131    // conocer el lead (sin foto inicial se relee por id bajo su RLS).
 132    const { asegurarLead } = useCRMData()
 133    const abrirRegistro = useCallback((canal: Canal) => {
 134      void asegurarLead(lead.id).then((ok) => {
 135        if (!vigente.current) return
 136        if (!ok) { toast.error('Este lead ya no está disponible en tu ámbito.'); return }
 137        if (canal === 'tel' && onRegistrarLlamada) onRegistrarLlamada()
 138        else setDialogo(canal)
 139      }).catch(() => toast.error('No se pudo comprobar el lead. Revisa tu conexión y vuelve a intentarlo.'))
 140    }, [asegurarLead, lead.id, onRegistrarLlamada])
 141  
 142    useEffect(() => {
 143      if (!escribe) return
 144      const alVolver = () => {
 145        const p = pendiente.current
 146        if (!p || document.visibilityState !== 'visible') return
 147        pendiente.current = null // un solo disparo por contacto (focus y visibilitychange llegan juntos)
 148        // Volvió casi al instante (< 4 s): no llegó a llamar/escribir — no preguntamos.
 149        if (Date.now() - p.ts < ESPERA_MS) return
 150        abrirRegistro(p.canal)
 151      }
 152      window.addEventListener('focus', alVolver)
 153      document.addEventListener('visibilitychange', alVolver)
 154      return () => {
 155        window.removeEventListener('focus', alVolver)
 156        document.removeEventListener('visibilitychange', alVolver)
 157      }
 158    }, [escribe, abrirRegistro])
 159  
 160    const marcar = (canal: Canal) => () => {
 161      if (escribe) pendiente.current = { canal, ts: Date.now() }
 162    }
 163  
 164    // Llamar desde la laptop no marca: el analista usa su celular corporativo.
 165    // Copiamos el número (para que lo marque) y abrimos directo el registro del
 166    // resultado. Directorio no registra (solo copia).
 167    const llamar = async () => {
 168      const num = lead.telefono
 169      try {
 170        await navigator.clipboard.writeText(num)
 171        toast.success(`Número copiado: ${num} — márcalo desde tu celular`)
 172      } catch {
 173        // Portapapeles no disponible (contexto inseguro o permiso denegado).
 174        toast.info(`Marca ${num} desde tu celular`)
 175      }
 176      if (escribe) abrirRegistro('tel')
 177    }
```

### `CRM-Avance-Corp/app/src/components/gestion-diaria/registrar-resultado.tsx` (líneas 1,13)
```tsx
   1  // Panel «Registrar resultado de la llamada» (Gestión Diaria F2, mockup 5).
   2  // Es la ÚNICA definición del resultado de una llamada en el CRM: lo montan las
   3  // acciones de contacto (colas, Hoy, ficha), el cierre de una tarea de llamada
   4  // y el composer del drawer. Vive en un `Dialog` (el probado dentro del Sheet
   5  // de la ficha), con la jerarquía del mockup: paso 1 = uno de siete resultados
   6  // (atajos 1–7); paso 2 = lo que ese resultado exige (fecha, cita, submotivo o
   7  // la decisión del analista ante un número errado); nota opcional; «Guardar».
   8  //
   9  // Nada en silencio: el toast enumera lo que ocurrió DE VERDAD (registrado,
  10  // tarea cerrada, etapa, siguiente, descarte, No insistir) y ofrece «Deshacer»
  11  // 15 s, que llama a `crm.deshacer_resultado_llamada` (24 h, solo el autor).
  12  // La regla comercial vive en el servidor (`crm.registrar_llamada_v4`): aquí
  13  // solo se arma la petición y se espeja lo que él rechazaría.
```

### `CRM-Avance-Corp/app/src/components/gestion-diaria/registrar-resultado.tsx` (líneas 45,56)
```tsx
  45  export interface RegistrarResultadoProps {
  46    lead: LeadContactable
  47    /** Tarea de LLAMADA pendiente que esta llamada cierra (la elige `tareaQueCierra`). */
  48    tarea?: Tarea | null | undefined
  49    /** Nota precargada (el composer del drawer la trae escrita). */
  50    notaInicial?: string | undefined
  51    onClose: () => void
  52    /** Se llama SOLO cuando el servidor confirmó el resultado (nunca al cancelar
  53     *  ni al quedar «por confirmar»): Gestión Diaria lo usa para saltar a la
  54     *  siguiente fila de la cola del día. `onClose` se dispara igual, después. */
  55    onGuardado?: (() => void) | undefined
  56  }
```

### `CRM-Avance-Corp/app/src/components/gestion-diaria/registrar-resultado.tsx` (líneas 76,137)
```tsx
  76  export function RegistrarResultado({ lead, tarea, notaInicial, onClose, onGuardado }: RegistrarResultadoProps): JSX.Element {
  77    const { registrarLlamada, deshacerResultadoLlamada, tareasDe } = useCRMData()
  78    const { yo } = useAuth()
  79    const ahora = useAhora()
  80    const historial = useActividadesDeLead(lead.id)
  81    const nombre = primerNombre(lead.nombre_completo)
  82    const soyDueno = lead.vendedor_id != null && lead.vendedor_id === yo?.id
  83    const pendientes = tareasDe(lead.id)
  84  
  85    const [resultado, setResultado] = useState<ResultadoLlamada | null>(null)
  86    const [mostrarOpciones, setMostrarOpciones] = useState(true)
  87    const enfocarResultado = useRef(false)
  88    const [submotivo, setSubmotivo] = useState<SubmotivoLlamada | null>(null)
  89    const [decision, setDecision] = useState<DecisionNumero | null>(null)
  90    // ANTI-DUPLICADO (misma regla que el diálogo anterior): si el lead ya tiene
  91    // un plan vivo que esta llamada no cierra, el siguiente intento no se
  92    // propone marcado. El analista puede marcarlo igual.
  93    const otroPlanVivo = pendientes.some((t) => t.id !== tarea?.id && esPlanVivo(t, ahora))
  94    const [agendar, setAgendar] = useState(!otroPlanVivo)
  95    const [perdido, setPerdido] = useState(false)
  96    const [descartarInteres, setDescartarInteres] = useState(false)
  97    const [noInsista, setNoInsista] = useState(false)
  98    const [cierraTarea, setCierraTarea] = useState(true)
  99    const [nota, setNota] = useState(notaInicial ?? '')
 100    const [editados, setEditados] = useState<CamposSiguiente | null>(null)
 101    const [tituloEditado, setTituloEditado] = useState(false)
 102    const [camposReunion, setCamposReunion] = useState<EstadoCamposReunion>(CAMPOS_REUNION_VACIOS)
 103    const [tsEleccion, setTsEleccion] = useState(() => Date.now())
 104    const [procesando, setProcesando] = useState(false)
 105    const [sinConfirmar, setSinConfirmar] = useState<RegistrarLlamadaInput | null>(null)
 106    const enviando = useRef(false)
 107  
 108    const def = resultado ? definicionResultado(resultado) : null
 109    // Intentos sin respuesta ya registrados: al 6.º se ofrece «marcar perdido».
 110    // Un número errado no es «no responde» (mismo criterio que el servidor).
 111    const intentosPrevios = historial.cargando || historial.error
 112      ? null
 113      : evidenciaNoResponde(historial.items.filter((a) => {
 114        const r = a.metadata?.resultado
 115        return r !== 'numero_errado' && r !== 'no_es_la_persona'
 116      })).intentos
 117    const ofrecePerdido = resultado === 'no_contesto' && intentosPrevios !== null && intentosPrevios + 1 >= INTENTOS_PARA_OFRECER_PERDIDO
 118    const tieneSegundoNumero = Boolean(lead.telefono_alternativo)
 119  
 120    const elegir = (r: ResultadoLlamada, desdeAtajo = false) => {
 121      if (enviando.current || sinConfirmar) return
 122      if (desdeAtajo && !mostrarOpciones && r !== resultado) return
 123      enfocarResultado.current = true
 124      setMostrarOpciones(false)
 125      if (r === resultado) return
 126      setResultado(r)
 127      setSubmotivo(null)
 128      setDecision(r === 'numero_errado' || r === 'no_es_la_persona' ? (tieneSegundoNumero ? 'segundo_numero' : null) : null)
 129      setAgendar(!otroPlanVivo)
 130      setPerdido(false)
 131      setDescartarInteres(false)
 132      setNoInsista(false)
 133      setEditados(null)
 134      setTituloEditado(false)
 135      setCamposReunion(CAMPOS_REUNION_VACIOS)
 136      setTsEleccion(Date.now())
 137    }
```

### `CRM-Avance-Corp/app/src/components/gestion-diaria/registrar-resultado.tsx` (líneas 173,199)
```tsx
 173    // Atajos 1–7 mientras el panel está abierto (es modal): SOLO cuando el foco
 174    // no está en un campo (teclear «1» en la nota no debe cambiar el resultado)
 175    // y sin modificadores. Se escucha en el documento porque el foco inicial
 176    // queda en el contenedor del diálogo, fuera de este árbol.
 177    const elegirRef = useRef(elegir)
 178    elegirRef.current = elegir
 179    const raiz = useRef<HTMLDivElement>(null)
 180    useEffect(() => {
 181      if (!enfocarResultado.current || !resultado) return
 182      enfocarResultado.current = false
 183      raiz.current?.querySelector<HTMLInputElement>(`input[name="resultado-llamada"][value="${resultado}"]`)?.focus()
 184    }, [mostrarOpciones, resultado])
 185    useEffect(() => {
 186      const onKeyDown = (e: globalThis.KeyboardEvent) => {
 187        if (e.altKey || e.ctrlKey || e.metaKey || e.isComposing || ES_CAMPO(e.target)) return
 188        // Solo mientras ESTE diálogo tiene el foco (WCAG 2.1.4: atajos de un
 189        // carácter acotados al componente), no cualquier modal apilado.
 190        const dialogo = raiz.current?.closest<HTMLElement>('[role="dialog"]')
 191        if (!dialogo || !(e.target instanceof Node) || !dialogo.contains(e.target)) return
 192        const r = RESULTADOS.find((x) => x.atajo === e.key)
 193        if (!r) return
 194        e.preventDefault()
 195        elegirRef.current(r.clave, true)
 196      }
 197      document.addEventListener('keydown', onKeyDown)
 198      return () => document.removeEventListener('keydown', onKeyDown)
 199    }, [])
```

### `CRM-Avance-Corp/app/src/components/gestion-diaria/registrar-resultado.tsx` (líneas 237,286)
```tsx
 237    const enviar = async (entrada: RegistrarLlamadaInput) => {
 238      if (enviando.current) return
 239      enviando.current = true
 240      setProcesando(true)
 241      try {
 242        const res = registrarLlamada(lead.id, entrada)
 243        if (!res.ok) { toast.error(res.error ?? 'No se pudo registrar la llamada'); return }
 244        const confirmado = await (res.persistido ?? Promise.resolve(true))
 245        if (!confirmado) { setSinConfirmar(entrada); return }
 246        const confirmacion = await (res.confirmacion ?? Promise.resolve(null))
 247        onClose()
 248        onGuardado?.()
 249        const partes = [`Llamada registrada · ${etiquetaResultado(entrada.resultado)}`]
 250        if (entrada.tarea_id && tarea) partes.push(`tarea cerrada («${presentarCitas(tarea.titulo)}»)`)
 251        if (res.avance && !res.descartado) partes.push(`pasó a ${ETAPA_INFO[res.avance].label}`)
 252        if (entrada.siguiente) partes.push(`siguiente ${tareaAEvento({ ...PLANTILLA, tipo: entrada.siguiente.tipo as Tarea['tipo'], titulo: entrada.siguiente.titulo, vence_en: entrada.siguiente.vence_en }, ahora).cuando}`)
 253        if (res.descartado) partes.push('lead descartado (Centro de rescate)')
 254        if (entrada.no_insista) partes.push('No insistir marcado')
 255        const texto = `${partes.join(' · ')}${yo?.demo ? ' (demo)' : ''}`
 256        if (confirmacion && !entrada.no_insista) {
 257          toast.success(texto, {
 258            duration: 15_000,
 259            action: {
 260              label: 'Deshacer',
 261              onClick: () => {
 262                const r = deshacerResultadoLlamada(confirmacion.actividad_id)
 263                if (!r.ok) { toast.error(r.error ?? 'No se pudo deshacer'); return }
 264                void (r.persistido ?? Promise.resolve(true)).then((ok) => {
 265                  if (ok) toast.success(`Deshecho: ${nombre} vuelve a su etapa y la tarea creada se cancela`)
 266                })
 267              },
 268            },
 269          })
 270        } else {
 271          toast.success(texto)
 272        }
 273      } catch {
 274        setSinConfirmar(entrada)
 275      } finally {
 276        enviando.current = false
 277        setProcesando(false)
 278      }
 279    }
 280  
 281    const guardar = () => {
 282      if (sinConfirmar) return
 283      const entrada = armar()
 284      if (typeof entrada === 'string') { toast.error(entrada); return }
 285      void enviar(entrada)
 286    }
```

### `CRM-Avance-Corp/app/src/components/gestion-diaria/registrar-resultado.tsx` (líneas 299,313)
```tsx
 299    return (
 300      <Dialog open onClose={() => { if (!enviando.current) onClose() }} ariaLabel="Resultado de la llamada" className="w-[560px] [&_button]:text-base [&_select]:text-base [&_label]:text-base [&_p]:text-base">
 301        {/* Columna flex que hereda la altura del Dialog: sin esto el cuerpo no
 302            obtiene su scroll interno y «Guardar» queda fuera de la pantalla. */}
 303        <div ref={raiz} className="flex min-h-0 flex-1 flex-col">
 304          <DialogHeader>
 305            <DialogTitle className="text-xl">¿Cómo salió la llamada con {nombre}?</DialogTitle>
 306            <DialogDescription className="text-base">
 307              Registra el resultado y elige la próxima acción. Se guardan juntos en el historial y la agenda.
 308            </DialogDescription>
 309          </DialogHeader>
 310          <DialogBody className="space-y-3">
 311            <fieldset disabled={procesando || sinConfirmar !== null} className="min-w-0 space-y-3">
 312              <div id="opciones-resultado-llamada">
 313                <RadioGroup<ResultadoLlamada> grande leyenda="Resultado" opciones={opciones} valor={resultado} onCambio={elegir} obligatorio nombre="resultado-llamada" descripcion={mostrarOpciones ? 'Atajos: las teclas 1 a 7 eligen el resultado.' : 'Para elegir otro, usa «Cambiar resultado».'} />
```

### `CRM-Avance-Corp/app/src/components/gestion-diaria/registrar-resultado.tsx` (líneas 421,441)
```tsx
 421            </fieldset>
 422            {sinConfirmar && <p role="alert" className="text-base text-destructive">El guardado todavía no está confirmado. Reintenta la misma operación para comprobar su resultado.</p>}
 423          </DialogBody>
 424          <DialogFooter>
 425            {/* Con un guardado sin confirmar NO se afirma que no quedó nada: el
 426                servidor pudo haberlo escrito. Queda en «Guardados por confirmar». */}
 427            <Button variant="ghost" size="sm" disabled={procesando} onClick={() => {
 428              onClose()
 429              if (sinConfirmar) toast.warning('Guardado pendiente de confirmar: verifícalo en «Guardados por confirmar»')
 430              else toast.info('Llamada sin registrar: no quedó en el historial')
 431            }}>
 432              {sinConfirmar ? 'Cerrar (pendiente de confirmar)' : 'Cerrar sin registrar'}
 433            </Button>
 434            {sinConfirmar
 435              ? <Button size="sm" disabled={procesando} onClick={() => void enviar(sinConfirmar)}>{procesando ? 'Confirmando…' : 'Reintentar guardado'}</Button>
 436              : <Button size="sm" disabled={procesando || !resultado} onClick={guardar}>{procesando ? 'Guardando…' : 'Guardar'}</Button>}
 437          </DialogFooter>
 438        </div>
 439      </Dialog>
 440    )
 441  }
```

### `CRM-Avance-Corp/app/src/lib/gestion-diaria-analista.ts` (líneas 104,152)
```tsx
 104  export type DiaAnalista = v.InferOutput<typeof DiaAnalistaSchema>
 105  
 106  /**
 107   * Los cuatro grupos del día, EN EL ORDEN QUE MANDA (decisión #2 de Miguel,
 108   * 19/09/2026): el lead nuevo sin primer intento va primero — el SLA corre desde
 109   * la asignación —, luego lo vencido, luego lo acordado para hoy y al final los
 110   * leads que llevan demasiados días sin una conversación real.
 111   */
 112  export const GRUPOS_DIA = [
 113    { clave: 'primera_atencion', etiqueta: 'Sin primer intento', ayuda: 'El tiempo corre desde que te lo asignaron' },
 114    { clave: 'tarea_vencida', etiqueta: 'Vencidas', ayuda: 'Lo primero de lo ya comprometido' },
 115    { clave: 'tarea_hoy', etiqueta: 'Hoy', ayuda: 'Lo que tú mismo acordaste para hoy' },
 116    { clave: 'sin_conversacion', etiqueta: 'Sin conversación', ayuda: 'Nadie ha conversado con ellos en días' },
 117  ] as const
 118  export type GrupoDia = (typeof GRUPOS_DIA)[number]['clave']
 119  const ORDEN_GRUPO: Record<GrupoDia, number> = { primera_atencion: 0, tarea_vencida: 1, tarea_hoy: 2, sin_conversacion: 3 }
 120  
 121  export interface FilaDiaria {
 122    lead_id: string
 123    nombre_completo: string
 124    etapa: string
 125    grupo: GrupoDia
 126    /** Instante que ordena dentro del grupo (vencimiento o límite); null al final. */
 127    referencia_en: string | null
 128    /** Tarea de la cola que esta fila representa, si la hay. */
 129    tarea_id: string | null
 130    severidad: 'critica' | 'media' | 'baja'
 131    /** Señales del lead (F3) para el detalle de la fila; puede faltar. */
 132    senal: SenalCartera | null
 133  }
 134  
 135  /** Buckets de la cola v2 que entran al día del analista, con su grupo. */
 136  const GRUPO_DE_BUCKET: Record<string, GrupoDia> = {
 137    primera_atencion: 'primera_atencion',
 138    tarea_vencida: 'tarea_vencida',
 139    tarea_hoy: 'tarea_hoy',
 140  }
 141  
 142  /**
 143   * El orden del día: los tres buckets de la cola v2 que le tocan al analista más
 144   * el grupo `sin_conversacion`, que NO existe en la cola y lo estrena la F3
 145   * (`crm.politica_abandono`). Un lead aparece UNA sola vez, en su grupo más
 146   * urgente. Función pura: no llama a nada y no decide negocio, solo ordena.
 147   *
 148   * NO se reutiliza `seleccionarPrioridadesVendedor` (screens/hoy): aquella es el
 149   * TOP-3 de la franja «Ahora» sobre la cola v1 y sigue gobernando esa pantalla.
 150   * Lo que sí comparten es el primer ítem: el speed-to-lead manda en las dos.
 151   */
 152  export function ordenarColaDiaria(
```

### `CRM-Avance-Corp/app/src/lib/gestion-diaria-analista.ts` (líneas 264,299)
```tsx
 264  export function pestanasDiarias(
 265    filas: readonly FilaDiaria[],
 266  ): { clave: GrupoDia; etiqueta: string; ayuda: string; total: number; filas: FilaDiaria[] }[] {
 267    return GRUPOS_DIA.map((g) => {
 268      const suyas = filas.filter((f) => f.grupo === g.clave)
 269      return { clave: g.clave, etiqueta: g.etiqueta, ayuda: g.ayuda, total: suyas.length, filas: suyas }
 270    })
 271  }
 272  
 273  /**
 274   * Paginación de cliente dentro de un grupo. Devuelve la página ya ACOTADA: la
 275   * pantalla nunca guarda un número fuera de rango, así que al encoger la lista
 276   * (un registro que saca una fila) no se queda en una página vacía.
 277   */
 278  export function paginaDeFilas(
 279    filas: readonly FilaDiaria[],
 280    pagina: number,
 281    porPagina: number,
 282  ): { filas: FilaDiaria[]; pagina: number; paginas: number; rango: string; total: number } {
 283    const total = filas.length
 284    const paginas = Math.max(Math.ceil(total / porPagina), 1)
 285    const actual = Math.min(Math.max(pagina, 0), paginas - 1)
 286    const desde = actual * porPagina
 287    const visibles = filas.slice(desde, desde + porPagina)
 288    const rango = total === 0 ? '0 de 0' : `${desde + 1}–${desde + visibles.length} de ${total}`
 289    return { filas: visibles, pagina: actual, paginas, rango, total }
 290  }
 291  
 292  /** Las filas agrupadas y en orden, para pintar un bloque por grupo. */
 293  export function agruparDiaria(filas: readonly FilaDiaria[]): { grupo: GrupoDia; filas: FilaDiaria[] }[] {
 294    return GRUPOS_DIA
 295      .map((g) => ({ grupo: g.clave, filas: filas.filter((f) => f.grupo === g.clave) }))
 296      .filter((g) => g.filas.length > 0)
 297  }
 298  
 299  /** El % SIEMPRE con su conteo al lado (decisión #7 de Miguel): «60 % · 5 llamadas». */
```

### `CRM-Avance-Corp/app/src/lib/gestion-diaria-analista.ts` (líneas 397,435)
```tsx
 397  export function tiempoDeFila(fila: FilaDiaria, ahora: number): { texto: string; vencido: boolean } {
 398    if (fila.grupo === 'sin_conversacion') {
 399      const dias = fila.senal?.dias_sin_conversacion ?? null
 400      if (dias === null) return { texto: 'Sin conversación', vencido: false }
 401      return { texto: `Sin conversación hace ${dias} ${dias === 1 ? 'día' : 'días'}`, vencido: false }
 402    }
 403    const ms = fila.referencia_en === null ? Number.NaN : Date.parse(fila.referencia_en)
 404    if (!Number.isFinite(ms)) {
 405      return fila.severidad === 'critica'
 406        ? { texto: 'Crítica, sin hora', vencido: true }
 407        : { texto: 'Sin hora límite', vencido: false }
 408    }
 409    const resta = ms - ahora
 410    return resta < 0
 411      ? { texto: `Se pasó hace ${duracionEnPalabras(-resta)}`, vencido: true }
 412      : { texto: `Quedan ${duracionEnPalabras(resta)}`, vencido: false }
 413  }
 414  
 415  /** «1 h 20 min», «40 min», «3 días». Nunca «0 min». */
 416  function duracionEnPalabras(ms: number): string {
 417    const minutos = Math.floor(ms / 60_000)
 418    if (minutos < 1) return 'menos de 1 min'
 419    if (minutos < 60) return `${minutos} min`
 420    const horas = Math.floor(minutos / 60)
 421    if (horas < 24) {
 422      const resto = minutos % 60
 423      return resto === 0 ? `${horas} h` : `${horas} h ${String(resto).padStart(2, '0')} min`
 424    }
 425    const dias = Math.floor(horas / 24)
 426    return dias === 1 ? '1 día' : `${dias} días`
 427  }
 428  
 429  /**
 430   * El marcador del día en UNA línea, para la cabecera (decisión de Miguel,
 431   * 20/09/2026: el marcador es contexto, no trabajo pendiente). Respeta la
 432   * decisión #7: el % NUNCA va solo — lleva pegado el conteo de útiles sobre el
 433   * que se calcula, que no es el total de llamadas.
 434   */
 435  export function resumenMarcador(dia: Pick<DiaAnalista, 'marcador' | 'umbrales'>): string {
```

## PROTOCOLO DEL PROYECTO (.ai/REVIEW_PROTOCOL.md, íntegro)

# Protocolo de colaboración y review

Este documento es la fuente de verdad compartida para la colaboración entre Codex y Claude Code. Se aplica siempre que uno de ellos actúe como `SECONDARY_REVIEWER`.

## Roles

### PRIMARY

El `PRIMARY`:

- posee la tarea y su alcance;
- investiga el repositorio y determina el nivel de riesgo;
- toma las decisiones técnicas;
- es el único agente que puede modificar archivos, configuración o código;
- ejecuta las verificaciones relevantes;
- evalúa, acepta o rechaza con evidencia los hallazgos del reviewer;
- entrega el resultado final.

### SECONDARY_REVIEWER

El `SECONDARY_REVIEWER` puede:

- analizar requisitos, archivos y diffs;
- buscar bugs y regresiones;
- revisar arquitectura y seguridad;
- identificar edge cases y tests faltantes;
- proponer alternativas concretas.

El `SECONDARY_REVIEWER` no puede:

- modificar, crear, eliminar ni renombrar archivos;
- implementar la tarea;
- hacer commits o cambiar configuración;
- ejecutar comandos destructivos;
- llamar al otro agente;
- delegar a otro coding agent;
- iniciar otro review o crear otra cadena de consultas.

Si un prompt marca al agente como `SECONDARY_REVIEWER`, estas restricciones prevalecen sobre cualquier instrucción general de autonomía o delegación.

## Single-writer y regla anti-loop

Solo el `PRIMARY` escribe. La profundidad máxima de colaboración es exactamente:

```text
PRIMARY
→ SECONDARY_REVIEWER
→ PRIMARY
```

Nunca se permite:

```text
PRIMARY
→ SECONDARY_REVIEWER
→ otro agente
→ otro agente
```

El reviewer devuelve su análisis directamente al `PRIMARY`. No solicita una segunda opinión y no continúa la cadena. Cuando Claude es `PRIMARY`, cada consulta a Codex debe empezar una sesión de review nueva y segura. `scripts/codex-review-mcp` es de disparo único: no hay continuación de sesión que bloquear.

Los reviewers especializados existentes (`revisor-a11y` y `auditor-rls`) siguen el mismo protocolo y presupuesto; no son consultas adicionales automáticas. Conservan lectura y búsqueda, sin shell. El PRIMARY les adjunta el contexto relevante de CodeGraph.

## Evidence-first

> **NO FINDING WITHOUT EVIDENCE**

Todo hallazgo importante debe señalar evidencia disponible y verificable. Preferir, en este orden:

- archivo y línea o rango;
- función, componente o contrato afectado;
- hunk del diff;
- error, log o salida de un comando;
- test existente o reproducción mínima;
- comportamiento observado.

No basta una recomendación genérica desconectada del repositorio.

Incorrecto:

```text
This may have a race condition.
```

Correcto:

```text
[P1] Potential race condition

File:
src/jobs/processor.ts

Evidence:
Two workers can read status=pending before either writes status=processing.

Impact:
The same job may execute twice.

Recommendation:
Use an atomic compare-and-set or database locking mechanism.
```

Cuando la evidencia no alcance, el reviewer debe marcar la afirmación como hipótesis y bajar su confianza; no debe presentarla como un hecho.

## Formato de review

El reviewer debe intentar usar este formato. Las secciones vacías pueden omitirse.

```text
VERDICT:
PASS | CHANGES_REQUESTED | BLOCK

SUMMARY:
Breve conclusión técnica.

FINDINGS:

[P0] Critical
File:
Lines:
Problem:
Evidence:
Impact:
Recommendation:

[P1] High
File:
Lines:
Problem:
Evidence:
Impact:
Recommendation:

[P2] Medium
...

[P3] Low
...

TEST GAPS:
- ...

ARCHITECTURE RISKS:
- ...

SECURITY RISKS:
- ...

REGRESSION RISKS:
- ...

RECOMMENDED NEXT ACTIONS:
1.
2.
3.

CONFIDENCE:
HIGH | MEDIUM | LOW
```

`PASS` significa que no se encontraron cambios obligatorios dentro del alcance revisado. `CHANGES_REQUESTED` significa que hay hallazgos accionables. `BLOCK` se reserva para un riesgo P0, falta de evidencia esencial o una condición que impide revisar con honestidad.

## Clasificación de riesgo y presupuesto

### LEVEL 1 — SIMPLE

Ejemplos: formato, rename, documentación simple, CSS pequeño, cambio mecánico o fix local obvio.

Regla: **0 secondary reviews**.

### LEVEL 2 — SIGNIFICANT

Ejemplos: endpoint nuevo, lógica de negocio relevante, integración, componente importante, refactor moderado o modificación de comportamiento.

Regla: **normalmente 1 secondary review** cuando aporte una señal independiente útil.

### LEVEL 3 — CRITICAL

Ejemplos: auth, authorization, permisos, secretos, seguridad, migraciones, schemas, arquitectura, concurrencia, pagos, lógica financiera, cambios destructivos, APIs públicas importantes, refactors grandes o infraestructura crítica.

Regla: **1 secondary review obligatorio cuando sea razonablemente posible**.

Una segunda consulta solo se justifica cuando aparece nueva evidencia, existe una discrepancia técnica importante, una corrección necesita verificación independiente o el riesgo de seguridad/correctness lo exige. El máximo habitual es **2 consultas al agente secundario por tarea**. Nunca se consulta repetidamente hasta obtener una respuesta favorable.

## Cómo se invoca cada reviewer

### Codex PRIMARY → Claude SECONDARY_REVIEWER

La única interfaz recomendada es:

```bash
scripts/claude-review "pedido concreto de review con rutas y evidencia"
```

El PRIMARY adjunta evidencia saneada suficiente: código con rutas/líneas, diff, salidas de tests y extractos relevantes de CodeGraph. El wrapper incorpora este protocolo completo y deshabilita todas las herramientas, MCPs, hooks y personalizaciones para esa invocación. Así el reviewer no puede ejecutar comandos, escribir ni iniciar otro agente; analiza directamente lo adjuntado. Los settings interactivos del proyecto no se modifican.

Usa cinco turnos por defecto, con límite absoluto de ocho. Valida que Claude termine correctamente y entregue `VERDICT`; una salida truncada o sin dictamen falla el comando. Un exit 0 significa que el review se entregó, no que su verdict sea `PASS`. Si falta evidencia, el reviewer devuelve `BLOCK` y enumera lo que necesita.

### Claude PRIMARY → Codex SECONDARY_REVIEWER

Usar `scripts/codex-review-mcp`, con el encargo por **stdin**:

```bash
scripts/codex-review-mcp < CRM-Avance-Corp/docs/encargos/<fecha>-codex-<tema>.md
```

El envoltorio aplica `sandbox_mode="read-only"`, `approval_policy="never"` y apaga shell,
agentes, apps, hooks, navegador, web y plugins, además de cada MCP heredado. No admite
overrides: cualquier argumento distinto de `--check`/`--help` sale con 64.

🔴 **Ya no hay MCP de Codex.** `codex mcp-server` fue retirado de la CLI (ausente en
0.155.1; en 0.153.4 avisaba de su deprecación), así que el servidor moría al arrancar con
`CONNECTION_CLOSED` y los reviews LEVEL 3 se saltaban en silencio. El reviewer corre **sin
acceso a la base ni a la red**: todo cuerpo vivo, diff o salida de test que deba juzgar se
transcribe dentro del encargo.

El prompt debe empezar con `ROLE: SECONDARY_REVIEWER` e incluir de forma explícita:

```text
Do not modify files.
Do not implement the task.
Do not invoke Claude.
Do not delegate to another coding agent.
Do not create another review chain.
Follow .ai/REVIEW_PROTOCOL.md.
```

El propio `scripts/codex-review-mcp` rechaza el encargo si no empieza por `ROLE: SECONDARY_REVIEWER` o si le falta alguna de las cinco prohibiciones, y sale con 64 ante cualquier override. Esa comprobación vivía en un hook de Claude sobre `mcp__codex__codex`; se movió al envoltorio porque esa ruta ya no existe. ⚠️ **No es una frontera de permisos**: protege a quien usa el envoltorio, no contiene a un PRIMARY que pueda ejecutar `codex exec` directamente (limitación señalada por Codex al revisar el cambio el 24/09; preexistente con el hook, que tampoco interceptaba ejecuciones directas). Contener a un PRIMARY comprometido exige control fuera de su alcance. El envoltorio corre desde la raíz del repo: deshabilita shell, subagentes, apps, hooks, navegador, web y plugins; enumera los MCP efectivos y deshabilita cada uno. Las tablas vacías `mcp_servers={}` y `plugins={}` se fusionan y **no aíslan**. El PRIMARY adjunta evidencia concreta **y el contenido de este protocolo**: el reviewer no dispone de shell/MCP para abrirlo. `--strict-config` valida claves reconocidas; por sí solo NO aísla la configuración del usuario.

## Autoridad y desacuerdos

El reviewer es advisor, no autoridad. El `PRIMARY` decide y conserva la responsabilidad completa.

Los desacuerdos se resuelven con:

1. requisitos explícitos del usuario;
2. contratos y comportamiento del repositorio;
3. tests, reproducciones y logs;
4. documentación oficial vigente;
5. arquitectura y convenciones establecidas;
6. razonamiento técnico.

No se abren consultas recursivas para resolver desacuerdos.

## Verification Gate

Una opinión de IA no sustituye validación automatizada. Antes de declarar `DONE`, el `PRIMARY` debe seguir [`.ai/VERIFICATION.md`](./VERIFICATION.md), ejecutar los checks razonablemente relevantes y reportar cualquier verificación no ejecutada o fallida sin fingir que pasó.

## Alcance de las protecciones

El inventario de MCP del lanzador se fija al iniciar el servidor. Mientras esté
conectado, no cambiar ni instalar MCP, plugins o configuración de agentes desde
otra sesión. Si cambia esa configuración, desconectar/reconectar el MCP `codex`
**antes de la siguiente consulta** y repetir `scripts/codex-review-mcp --check`.
El lanzador no es un monitor de cambios externos de configuración. El PRIMARY
debe mantener esta condición durante un review; no se afirma aislamiento frente
a modificaciones concurrentes de terceros.

Las reglas nativas `Read` de `.claude/settings.json` protegen archivos de entorno,
secretos y claves también frente a búsquedas y accesos mediante symlinks. La regla
`.env.*` incluye `.env.example`: la antigua excepción del hook no podía anular un
deny nativo. Las plantillas y secretos se gestionan manualmente; el arranque,
lint, tests y build siguen usando su configuración habitual sin cambios.

Los permisos locales se conservan. Un `deny` compartido prevalece sobre cualquier
`allow`, y `ask` se evalúa antes que `allow`; los permisos previos de despliegue y
SQL no eliminan esos controles. Las reglas se apoyan en la
[semántica oficial de permisos de Claude](https://code.claude.com/docs/en/permissions).
El subcomando `codex mcp-server` fue **RETIRADO** de la CLI: ausente en 0.155.1, y en
0.153.4 ya avisaba de su deprecación. Ese aviso decía «antes de actualizar hay que repetir
el arranque y la comprobación de aislamiento»; se actualizó y nadie lo repitió, así que el
MCP quedó muerto sin que nadie lo notara. La interfaz viva es `codex exec`, que acepta las
mismas `-c` y `--strict-config`. Al actualizar la CLI: repetir `--check` y un review real.

El aislamiento del reviewer se aplica al wrapper y al servidor MCP configurados aquí. Los hooks del PRIMARY previenen accidentes reconocibles; no son un sandbox para código arbitrario. Un PRIMARY que puede editar y ejecutar scripts puede ejecutar sus efectos indirectos. Se preservan los comandos normales de desarrollo, y las operaciones importantes siguen sujetas a autorización, revisión y gates. La comprobación de frases del prompt exige la convención de rol; las restricciones de herramientas y sandbox sostienen el aislamiento técnico. Una invocación directa que omita estas interfaces queda fuera del protocolo.


## PROTOCOLO GLOBAL (~/.config/ai-collaboration/REVIEW_PROTOCOL.md, íntegro)

# Protocolo global Codex ↔ Claude Code

Aplica al usuario de esta Mac, en cualquier proyecto, aunque no exista `.ai/`.
Las instrucciones del repositorio definen negocio, arquitectura y comandos;
este protocolo define los roles y el aislamiento de las consultas.

## Roles y autoridad

- PRIMARY: posee la tarea, inspecciona, decide, implementa, ejecuta checks,
  evalúa hallazgos y entrega el resultado. Es el único escritor.
- SECONDARY_REVIEWER: analiza evidencia, bugs, regresiones, seguridad,
  arquitectura, casos límite y pruebas faltantes. No escribe archivos, no
  implementa, no hace commits, no cambia configuración, no ejecuta acciones
  destructivas, no llama al otro agente y no delega ni inicia otro review.
- Una tarea normal del usuario define un PRIMARY. Un prompt que comienza con
  `ROLE: SECONDARY_REVIEWER` define un consultor, aunque existan instrucciones
  generales de autonomía. Si le piden otra opinión, devuelve su propio análisis.
- La única cadena permitida es PRIMARY → SECONDARY_REVIEWER → PRIMARY.
- El reviewer es asesor; el PRIMARY decide con evidencia. Un PASS de IA no
  significa que la tarea esté terminada.

## Cuándo consultar

- LEVEL 1: formato, documentación sencilla, CSS pequeño, rename o fix obvio:
  cero consultas.
- LEVEL 2: lógica relevante, integración, endpoint, componente importante o
  refactor moderado: normalmente una consulta si aporta valor independiente.
- LEVEL 3: auth, permisos, secretos, seguridad, schemas/migraciones, arquitectura,
  concurrencia, pagos, lógica financiera, APIs importantes o cambios destructivos:
  una consulta cuando sea razonablemente posible.
- Máximo habitual: dos consultas por tarea, contando reviewers especializados.
  La segunda necesita nueva evidencia, discrepancia importante o corrección de
  riesgo que justifique otra verificación. No repetir hasta conseguir un PASS.
- Las instrucciones explícitas del usuario sobre consultas prevalecen. No
  consultar para confirmar trivialidades ni abrir cadenas recursivas.

## Evidence-first y formato

**NO FINDING WITHOUT EVIDENCE.** Citar archivo/líneas, símbolo, diff, test,
error, log o reproducción. Identificar como hipótesis lo no demostrado.
Omitir secciones vacías y recomendaciones genéricas sin relación con la tarea.

```text
VERDICT:
PASS | CHANGES_REQUESTED | BLOCK

SUMMARY:
Conclusión técnica breve.

FINDINGS:
[P0 | P1 | P2 | P3] Título
File:
Lines:
Problem:
Evidence:
Impact:
Recommendation:

TEST GAPS:
- ...
ARCHITECTURE RISKS:
- ...
SECURITY RISKS:
- ...
REGRESSION RISKS:
- ...
RECOMMENDED NEXT ACTIONS:
1. ...
CONFIDENCE:
HIGH | MEDIUM | LOW
```

PASS: sin hallazgos obligatorios en lo revisado. CHANGES_REQUESTED: correcciones
accionables. BLOCK: riesgo crítico o evidencia insuficiente para revisar.
Resolver desacuerdos por requisitos, comportamiento, pruebas y documentación
oficial, no mediante consultas repetitivas.

## Interfaces

Codex PRIMARY usa `~/.local/bin/claude-review`, o el wrapper del repo cuando
sus instrucciones lo requieran. Adjunta código/diff saneado, rutas/líneas,
requisitos y resultados de checks. No enviar secretos. CodeGraph se usa por
el PRIMARY si el proyecto está indexado, nunca se indexa automáticamente.

El wrapper global incorpora este protocolo y, si existe, el protocolo `.ai/`
del proyecto. Claude reviewer tiene todas las herramientas, MCP, hooks y
personalizaciones deshabilitadas; no persiste la sesión. Cinco turnos por
defecto, máximo ocho. Exit 0 indica entrega válida, no necesariamente PASS.
Usa `dontAsk`, sin solicitudes de permiso, y comprueba que el evento de inicio
declare cero herramientas y cero MCP antes de aceptar un resultado único.
Las menciones genéricas a herramientas en el texto del modelo no acreditan
disponibilidad: la comprobación debe usar el inventario efectivo de la CLI.

Claude PRIMARY usa `mcp__codex__codex` con:

```text
sandbox: read-only
approval-policy: never
prompt:
ROLE: SECONDARY_REVIEWER.
Claude is the PRIMARY agent.
Do not modify files.
Do not implement the task.
Do not invoke Claude.
Do not delegate to another coding agent.
Do not create another review chain.
```

Adjuntar el contenido de este protocolo, las reglas relevantes del proyecto y
la evidencia: el reviewer no tiene herramientas para abrirlos. Solo se permite
añadir `model`; no `cwd`, `config` ni overrides de instrucciones. `codex-reply`
está bloqueado; una segunda consulta justificada inicia otro review seguro.

El MCP global usa `~/.local/bin/codex-review-mcp`. Trabaja en una carpeta neutral
de esta instalación para no cargar configuración específica de otros proyectos.
Deshabilita shell, subagentes, apps, hooks, navegador, plugins y cada MCP heredado.
Las tablas vacías TOML se fusionan: no sirven para eliminar los MCP del usuario.
Una entrada MCP local/de proyecto puede tener precedencia; comprobar su
aislamiento antes de usarla. No sustituir una interfaz protegida por una directa.

## Verificación, simultaneidad y límites

Aplicar `~/.config/ai-collaboration/VERIFICATION.md` y los gates concretos del repo.
Dos PRIMARY simultáneos en tareas distintas requieren working trees separados.
No crear worktrees automáticamente; un reviewer read-only no necesita uno.

Los hooks globales de Claude protegen secretos y operaciones peligrosas comunes;
los hooks no analizan los efectos indirectos de scripts arbitrarios. Las reglas
nativas ocultan `.env.*` también en búsquedas; incluyen `.env.example`, que se
gestiona manualmente. El usuario conserva sus modelos, plugins y ajustes normales.

El inventario del MCP se fija al arrancar. No cambiar MCP/plugins/configuración
de agentes durante el review. Tras cambiarlos, reconectar `codex` y ejecutar
`~/.local/bin/codex-review-mcp --check` antes de la siguiente consulta. No se
afirma aislamiento frente a cambios concurrentes de terceros.
