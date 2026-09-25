# Venta cruzada — servidor probado en banco y P1 del PDF

Miguel pidió que un analista B registre una inversión **nueva o upgrade** de un
cliente cuyo responsable es A, sin lead nuevo, sin reabrir descartes, sin otro
perfil ni otra persona y sin cambiar al responsable. La venta queda a nombre de
quien la registra (`analista_cierre_id = creado_por = B`); la relación sigue con A.
Las transferencias siguen siendo de Gerencia.

Tablero de avance: https://www.figma.com/board/rD4CaZo3wL199yPMdNcErn

## Decisiones de Miguel (23/09)

- **D1.** Vendedor y supervisor; motivo corto obligatorio; A lo ve en su ficha.
- **D2.** B lee el PDF de todo lo que cerró, también lo antiguo.
- **D3.** Cuentas enmascaradas (banco y 4 últimos dígitos) o una cuenta nueva.
- **D4.** Se mantiene el freno del lead canónico sin convertir (0 casos en prod).
- **D5.** Nueva y upgrade; la renovación es del responsable. Las renovaciones
  futuras de un upgrade de B cuentan para B (adopción por línea).
- **D6.** Una venta cruzada pendiente por cliente y empresa.
- **D7.** Un cambio de responsable no detiene a B, salvo con el acceso Avance
  pendiente: eso lo resuelve quien opera la venta, revisando el responsable.

## Decisiones de Miguel (24/09, tras las auditorías)

- La venta pendiente de B la operan B, su cadena y Gerencia. A la ve, pero no la
  corrige, cancela ni confirma; una venta abandonada la cancela Gerencia.
- B también crea el acceso Avance del cliente (el correo con el que entra).
- La bitácora de búsquedas se conserva **sin plazo** (Ley 29733: decisión expresa).
- La puerta vieja `public.crear_contrato` (abierta a cualquier vendedor) se
  cierra en una **tarea aparte**.

## Estado al 24/09 (tarde)

**El servidor está EN PRODUCCIÓN desde el 24/09** (fases 1–4, con el OK de Miguel). Antes de
escribir se ensayó contra la producción real en una transacción que siempre se deshace: las 5
migraciones aplicaron y ningún guardián empeoró. Después se aplicaron una a una y se registraron.
Verificado: 5 versiones, 6 puertas, bitácora vacía; advisors sin errores. **El frente también
está publicado** (24/09, 20:12 Lima): release `build-20260925T011258009Z` desde `a1bbe24d` (PR #93),
con el preflight en verde y lo servido idéntico al ZIP. Detalle y evidencia en
`CRM-Avance-Corp/supabase/migrations/MIGRACIONES.md`; pruebas, reversas, concurrencia y
mutantes en `CRM-Avance-Corp/supabase/scripts/venta-cruzada/`.

1. Bitácora inmutable de búsquedas y atribución congelada en la solicitud.
2. Regla de permisos separada por dentro, con una llave: la búsqueda propia por
   documento o la solicitud de esa misma persona. Paridad: 1.090 casos idénticos.
3. La confirmación atribuye a B sin tocar al responsable.
4. Puertas nuevas:
   - búsqueda exacta, con rastro y tope de 30 por hora;
   - contexto, cuentas enmascaradas y datos legales;
   - preparación con motivo;
   - D6 simétrico en el núcleo de siempre.
5. **Frente:** diálogo «Cliente de otra cartera» con cuatro entradas:
   - la Cartera (botón, y el vacío de una búsqueda por documento o teléfono);
   - el buscador de arriba (vacío + Enter);
   - «Nuevo lead», cuando el contacto ya es cliente;
   - «Reabrir» un descarte que resulta ser cliente: se muestra la tarjeta, no se reabre nada.

   La venta reutiliza la «Nueva inversión» y el contrato de siempre.
6. **Pruebas de punta a punta (fase 6):**
   - el gate de RLS entero, antes y después, desde la misma foto del banco: 2231 → 2272
     aserciones, **cero regresiones**;
   - la forma real de cada respuesta del servidor, pasada por los esquemas del frente;
   - `npm run check` completo (4343 pruebas) y e2e en Docker en un contenedor dedicado: 249 de 249.

## Lecciones que quedan

- **Leer no es crear.** La auditoría de la fase 3 encontró un hueco serio (P1).
  La regla D2 («quien cerró lee el PDF») era también el único candado de cartera
  del alta Avance directa, y el propio llamador fija `analista_cierre_id`. Así,
  cualquier analista podía crear un contrato completo para un cliente ajeno.
  Corregido: crear el PDF de un contrato **nuevo** exige cartera (P04) o la
  confirmación en curso de **esa** venta cruzada. La confirmación publica la
  solicitud en un GUC transaccional que se contrasta con la tabla. Se probó antes
  y después en el banco.
- **Una compuerta se pone donde nace la escritura, no donde suele pasar.** La
  segunda auditoría encontró otra vía para el mismo hueco. Un contrato con fecha de
  inicio anterior al 19/08 es de régimen documental «anterior», no crea PDF y
  salía antes de la compuerta. Ahora la compuerta vive también en el alta misma
  (`crm.crear_contrato_con_cuenta_pdf_v2`), sea cual sea la fecha.
- **Una llave que no caduca es un permiso para siempre.** La solicitud de una venta
  cruzada abre las lecturas del cliente (cuentas, datos legales, contratos) solo
  mientras está en preparación. Confirmada o cancelada, ya no abre nada vivo.
- **El historial de responsables es joven.** `crm.inversionista_responsables`
  empieza el 03/09/2026: solo 124 de 629 contratos tienen tramo al cerrar. Ninguna
  regla puede apoyarse en «era su responsable cuando cerró».
- **El vigía de analítica** marca toda función que nombre `crm.leads` y use
  `count(`. Si se puede, se separa el conteo en otra función en vez de declarar
  una exención.

- **Un reabrir optimista desmonta a quien espera la respuesta.** La tarjeta «ya es
  cliente» vivía en el banner del descarte. El store pasa el lead a «Nuevo» en el mismo clic,
  el banner desaparece y la respuesta del servidor llegaba a un componente muerto: en
  producción nunca se habría visto. El test pasaba porque su store no cambiaba la etapa.
  Regla: el estado que espera al servidor vive por encima de lo que el cambio optimista
  sustituye, y el arnés del test imita al store real.
- **El submit de un portal viaja por el árbol de React, no por el del DOM.** La búsqueda
  vivía dentro del `<form>` del alta del lead. Cada «Buscar» enviaba también el alta de
  detrás: validaciones, otro precheck y, degradado, un lead nuevo. Un diálogo con formulario
  propio no se monta dentro de otro formulario.
- **En un modal apilado, `autoFocus` no basta.** La trampa de foco del modal de abajo lo
  roba antes de que la del nuevo se registre. Para eso nació `focoInicial` en `ui/dialog.tsx`.
- **El volcado de esquema no trae Storage.** El gate de RLS necesita los buckets y las
  políticas F4. Se copian de las migraciones YA aplicadas, sin leer producción.
- **Un A/B vale si las dos pasadas parten de la MISMA base.** El banco se fotografía con una
  copia del volumen de Postgres y se restaura antes de cada pasada: así la única diferencia
  es la migración.
- **Dos e2e a la vez en Docker se ahogan, y otro agente puede detener el tuyo.** Docker
  Desktop reparte ~6 GB entre bancos y navegadores: con otra corrida en paralelo la página ni
  cargaba. Y una sesión de Codex detuvo el contenedor de esta al lanzar el suyo. Antes de culpar
  al código, `docker events` dice quién paró qué; se corre solo, con 1 worker.
- **Un gate que dice «llave ajena» y usa una llave inexistente es un falso verde** (Codex).
  Lo que un gate sin escrituras no puede probar se rotula como lo que es, y la propiedad se
  prueba donde sí se escribe (los `.sql` del banco).

## Pendiente

- 🔑 Para la próxima publicación: esta sesión no puede escribir en producción (lo bloquea el
  clasificador de permisos, ni siquiera deja escribir el guion). Funciona así: yo preparo y
  valido en el banco el ensayo que nunca escribe; Miguel lo lanza con `!`; si dice OK, lanza la
  aplicación y el registro.
- Tarea aparte: cerrar `public.crear_contrato` a la puerta con cuenta y PDF.
- Abiertas: métricas del upgrade cruzado (la operación de cartera queda a nombre de A) y la
  cuenta que solo vive en el perfil (no se ofrece enmascarada).
- No corrió: la sonda de `Prefer: tx=rollback` contra producción (sin acceso a producción desde
  esta sesión; el banco no la aplica).
