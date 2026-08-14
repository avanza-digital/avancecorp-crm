# Anulación de cierres de Avance

**Estado: ✅ Fase 1 (servidor) EN PRODUCCIÓN 2026-08-14. 🟡 Fase 2 (el botón) CONSTRUIDA Y EN
VERDE, pendiente de aplicar su migración de lectura y de publicar el front.**

Migración `20260813235119_crm_anulacion_cierre_avance`, aplicada directo con
`supabase/scripts/aplicar-anulacion-avance-prod.sh` (el merge de branches de Supabase sigue roto;
ver [[Cierres en cooperativas Qorilazo y Prodelco - plan]]). Verificación en vivo: tabla creada,
4 funciones nuevas, la cadena de neutralización dentro de la cuota, DEFINER 167 → 169 exacto,
migración registrada y advisors 0 ERROR.

## La regla de negocio

Miguel, 2026-08-13: «si gerencia anula un cierre tiene que afectar en la conversión sí o sí,
porque gerencia hará eso cuando haya errores de gestión o malas prácticas». Y la aclaración que
fija el alcance: lo que baja **«no significa dinero real, solo baja para el vendedor»**.

Es el gemelo, para la línea Avance, de la decisión 4 de cooperativas. Aquí se cerró en su propio
ciclo porque toca el mundo del portal ([[crm-portal-separados]]).

## Qué arregla

Hasta el 2026-08-14 **no existía ninguna forma** de que un cierre de Avance dejara de contarle a
un vendedor. La práctica era borrar al cliente, y eso arregla solo la mitad:

- el **capital** sale de `public.contratos` y se va con el contrato;
- pero la **conversión** sale del LEDGER, donde el episodio quedó sellado como `convertido` y es
  inmutable por diseño.

Resultado: el vendedor perdía el dinero y **conservaba el cierre**, con su porcentaje inflado
para siempre. Ver [[Como se mide la conversion del asesor]].

## Qué NO toca

**Ni una fila de `public`.** El contrato, el cliente y la caja siguen igual. Lo único que cambia
es a quién se le acredita el mérito. Es exactamente el alcance que puso Miguel.

## Las tres decisiones de diseño que costaron rondas de revisión

**1. Solo se le puede quitar el mérito a quien lo tiene.** La clave con la que se EXCLUYE (el
cliente) no es la clave con la que se ATRIBUYE (el autor del contrato). Sin esa comprobación, si
el cliente renovaba meses después con **otro** vendedor, anular el cierre viejo le borraba a ese
otro su venta legítima, en un mes ya cerrado. Por eso la anulación se aplica **después** de
atribuir, poniendo a NULL el vendedor del contrato solo si es la persona acreditada del cierre
anulado — y no filtrando el contrato antes, que además lo hacía caer al AUTOR y convertía anular
en **regalar** el cierre.

**2. El ledger manda; `crm.leads.vendedor_id` es solo respaldo del legado.** Esa columna es
mutable (gerencia puede reasignar un lead ya convertido) mientras la conversión descuenta al
`analista_id` del ledger, que es inmutable. Si la cuota mirara primero la columna mutable,
bastaría una reasignación para que las dos mitades castigaran a **personas distintas**. Y la
anulación además **fotografía** al acreditado (`acreditado_a`), porque un hecho histórico no se
recalcula en cada consulta.

**3. El enlace que de verdad existe es el CLIENTE, no `contrato_id`.** El primer predicado
buscaba el contrato por `crm.leads.contrato_id`, columna que **no rellena nadie**: producción
tiene 371 contratos y CERO enlazados. Habría bajado la conversión dejando el capital intacto —
justo la divergencia que esta migración existe para cerrar. La correlación real es
`crm.leads.perfil_id = public.contratos.cliente_id`, con **suelo** (un contrato anterior a la
conversión no lo produjo ese cierre) y **techo** (deja de reclamar en cuanto el cliente vuelve a
cerrarse). Ver [[ejecutar-contra-la-forma-real]].

## Cómo queda montado

- `crm.cierres_avance_anulados` — deny-by-default absoluto (RLS ON, cero policies, cero grants),
  append-only por trigger, auditada. Se escribe SOLO vía la RPC.
- `crm.anular_cierre_avance(uuid, text)` — solo gerencia, motivo obligatorio, de una sola
  dirección. Devuelve `contratos_afectados` y `afecta_cuota` para que la primera anulación real
  sea verificable en vez de un acto de fe.
- `private.cierre_anulado(uuid)` — la pregunta «¿fue anulado?» escrita **una** vez, respondiendo
  por los dos canales (cooperativa y Avance). `private.cierre_externo_anulado` queda como
  delegado de una línea porque el núcleo de conversión la invoca por ese nombre.
- `private.contratos_afectados_por_anulacion(uuid)` — la regla de qué deja de acreditar, también
  escrita una vez: la consultan la cuota y la RPC. Escrita dos veces, divergen (ya pasó).

## Fase 2 — el botón de gerencia (2026-08-14)

Decisiones de Miguel: se anula **desde la ficha del cliente** (Leads → filtro «Convertidos» →
abrir la fila), y la marca se ve **en la ficha y en la lista de leads**.

**El hallazgo que cambió el alcance**: la anulación era **invisible para la aplicación**. La
tabla es deny-by-default y el gate comprueba que no se lee desde la Data API, así que gerencia
habría anulado, recargado y visto el lead exactamente igual — con el segundo intento muriendo
en «ese cierre ya estaba anulado». Por eso la Fase 2 no es solo front: lleva
`crm.cierres_estado_fn(uuid[])` (migración `20260814100746`, **pendiente de aplicar**), que
responde por lote qué leads tienen cierre en cooperativa o anulación, con canal, fecha y motivo.

Tres cosas que conviene tener escritas:

- **El `canal` no es adorno.** Es lo que impide ofrecer el botón sobre un cierre en cooperativa,
  que la RPC rechaza — y hoy ese es el único lead convertido de producción. Sin él, el primer
  botón que gerencia vería sería el que no funciona.
- **La función es `SECURITY DEFINER` y por eso espeja el ámbito de `leads_select`.** La regla de
  la casa es INVOKER («el alcance lo pone la RLS»), pero aquí es imposible: las tablas de
  anulación no tienen ni una policy. El precio es un predicado copiado, y por eso el preflight
  ancla el md5 de la policy y el gate compara **conjuntos** (el mismo lead pedido por su dueño y
  por un ajeno), no ejemplos.
- **En la ficha el botón se llama «Anular el cierre», no «Anular».** Esa misma ficha ya tiene
  botones «Anular» que quitan una TAREA; con el mismo rótulo serían indistinguibles en un lector
  de pantalla, además de invitar a confundir quitar un recordatorio con quitarle el mérito a una
  persona.

El toast dice lo que de verdad se movió (los contratos que dejan de contar), porque **cero
contratos con la conversión bajando igual es un resultado correcto** —el mérito sale del ledger
y el dinero de los contratos— que sin explicar parecería un fallo.

## Lo que hay que saber antes de usarla

⚠️ **Hoy no hay nada que anular por esta vía.** El único lead en etapa `convertido` de producción
cerró en cooperativa — su dinero vive en `crm.cierres_externos`, no en `public.contratos` — y la
RPC lo rechaza a propósito, mandándolo a `crm.anular_cierre_externo`. La primera anulación de
Avance real será también la primera prueba de esta cadena con datos vivos.

⚠️ **Es retroactiva y es irreversible.** Anular en septiembre un cierre de agosto recalcula la
cuota y la conversión de agosto, que pudo estar liquidado. Es lo que Miguel pidió, pero choca con
el congelado de meses liquidados, que sigue diferido.

⚠️ **Deuda que esta migración vuelve visible, sin introducirla**: los tiles y rankings que cuentan
`etapa = 'convertido'` en crudo seguirán pintando el lead anulado como convertido y con su monto.

**Vuelta atrás**: `supabase/scripts/rollback-anulacion-avance.sql`. Devuelve la cuota al cuerpo
post-B y el delegado a mirar solo cooperativas. **No borra la tabla ni la RPC a propósito**: si
gerencia ya anuló algo, esa fila es la razón escrita que se le dio a una persona.

Ver también [[Conversion mensual - definicion cerrada]] · [[Conversion mensual - plan de implementacion]].
