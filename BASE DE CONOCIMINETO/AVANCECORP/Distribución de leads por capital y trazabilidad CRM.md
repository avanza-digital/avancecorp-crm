---
tags: [crm, gerencia, leads, asignacion, capital, trazabilidad]
actualizado: 2026-07-18
estado: v2-implementado-pendiente-validacion
---

# Distribución de leads por capital y trazabilidad CRM

Decisión comercial: Gerencia necesita comprobar si los leads se reparten de
forma equilibrada por monto estimado, capacidad y calidad operativa. La primera
versión será descriptiva; no mostrará `Priorizar`, `Pausar` ni otra recomendación
imperativa hasta acumular cierres suficientes y validar que la regla sea estable.

Relacionadas: [[F0 Cimientos BD del CRM]] · [[CRM conexión a datos reales]] ·
[[Acceso y roles del CRM]] · [[Canales de origen de leads CRM]].

## Secuencia aprobada

1. **0A — Reproducibilidad:** llevar al repositorio, sin ampliar su conducta, el
   trigger de reasignación que ya vive en producción.
2. **0B — Semántica:** esta nota congela las reglas antes del ledger.
3. **0C — Trazabilidad:** registrar episodios analíticos desde el primer lead.
4. **V1 descriptiva:** matriz PEN por analista y rango, capacidad y SLA.
5. **Inteligencia diferida:** cohortes, confianza y recomendaciones solo después
   del gate de suficiencia y estabilidad.

Al 2026-07-17 producción tiene `0` filas en `crm.leads`: no hay backfill que
reconstruir. Antes de desplegar 0C se vuelve a comprobar el conteo; si aparecieron
leads, sus episodios iniciales se marcan como aproximados.

## Línea base 0A: comportamiento vivo, no comportamiento deseado

`private.trg_leads_reasignacion()` es `BEFORE UPDATE`, observa solamente
`vendedor_id` y emite una actividad `reasignacion` cuando ese campo cambia.

- Un lead que nace asignado no genera esa actividad.
- Un cambio exclusivo de `asignado_supervisor_id` no genera esa actividad.
- Un `UPDATE` sin cambio de `vendedor_id` no genera esa actividad.
- `crm.actividades` sigue siendo el timeline humano; no es un modelo de
  intervalos.

0A reproduce exactamente esta línea base. El cambio de semántica pertenece a 0C.

## Tenencia comercial

La tenencia observable de un lead es el par:

`(vendedor_id, asignado_supervisor_id)`

Reglas:

- `vendedor_id` no nulo: existe responsabilidad analítica del analista.
- `vendedor_id` nulo y `asignado_supervisor_id` no nulo: el lead está parqueado
  en la bandeja de ese supervisor; no existe episodio de analista abierto.
- Ambos nulos: el lead está sin analista y sin bandeja específica; tampoco existe
  episodio de analista abierto.
- Ambos no nulos es un estado inválido: cuando existe `vendedor_id`,
  `asignado_supervisor_id` debe ser nulo. 0C aplica esta invariante después de
  verificar todos los escritores.
- El supervisor que custodia una bandeja no recibe conversión ni penalización
  del analista.
- `vendedor` es el nombre técnico vigente en la BD; la interfaz comercial usa
  **Analista**.

### Un solo clasificador

La evolución del timeline y el ledger debe llamar a una única función `private`
que clasifique el movimiento desde los cuatro valores `OLD/NEW`. No se duplica
la lógica en dos triggers.

Precedencia total para un `UPDATE` que cambie ambos campos:

1. Si cambia `vendedor_id`, el movimiento principal es asignación,
   reasignación o salida a parqueo/sin asignar, según sus valores anterior y
   nuevo. El cambio de supervisor viaja como destino/metadato del mismo
   movimiento.
2. Si no cambia `vendedor_id` pero cambia `asignado_supervisor_id`, es un cambio
   de custodia/parqueo.
3. Si no cambia ninguno, no hay movimiento de tenencia.

Cada cambio del par produce exactamente **una** actividad humana de movimiento.
Si había episodio de analista, se cierra una vez; si el estado nuevo tiene
analista **y la etapa es activa**, se abre una vez. Nunca se abren dos episodios
por un `UPDATE` compuesto.

Un mismo `UPDATE` no puede cambiar propietario y entrar en `convertido` o
`descartado`. El responsable debe existir antes del cierre; esta separación evita
reasignar en el mismo instante para mover el crédito comercial.

## Ciclo de los episodios

- **INSERT asignado:** abre un episodio desde el ingreso.
- **INSERT parqueado/sin asignar:** no abre episodio de analista.
- **Parqueo → analista:** abre un episodio nuevo; comienzan SLA y maduración
  propios del nuevo responsable.
- **Analista A → analista B:** cierra A por `transferido` y abre B en el mismo
  instante lógico. B inicia su reloj operativo de tramo, pero el SLA global del
  ciclo conserva el ingreso original y no se reinicia.
- **Analista → parqueo:** cierra el episodio por `parqueado`, conserva el
  supervisor destino y deja cero episodios de analista abiertos.
- **Convertido o descartado:** son resultados terminales y cierran el episodio
  vigente, atribuyendo el resultado al analista que lo tenía en ese instante.
- **Reapertura:** la operación vigente es exclusivamente `descartado → nuevo`;
  no se crea una etapa nueva y un convertido no se reabre. Si hay analista, abre
  un episodio nuevo y reinicia SLA/maduración sin borrar el descarte anterior.
- **Lead terminal:** nunca conserva ni abre un episodio operativo, aunque después
  se cambie su propietario. Primero debe ocurrir una reapertura válida.
- **Soft-delete (`activo=false`):** cierra el episodio abierto por `desactivado`.
  La historia y sus incumplimientos siguen en las métricas; inactivar no permite
  borrar un mal resultado. Una reactivación activa con analista abre otro episodio.

El ledger registra al actor de la operación por separado del analista responsable.
El monto, moneda, origen y categoría se fotografían al abrir el episodio para que
una edición posterior no reescriba la historia comercial.

Cada reapertura incrementa `ciclo_n` para distinguir intentos sobre el mismo lead.
La conversión descriptiva se calcula por ciclo resuelto y muestra también leads
únicos, de modo que reaperturas repetidas sean visibles y no inflen una tasa en
silencio.

## Invariantes de 0C

- El trigger del ledger es `AFTER INSERT OR UPDATE` sobre `crm.leads`, para leer
  la fila ya asentada por los triggers `BEFORE` existentes.
- Como máximo hay un episodio de analista abierto por lead; durante el parqueo
  hay cero.
- El cierre bloquea el episodio con `FOR UPDATE` antes de abrir el siguiente.
- Un episodio cerrado es inmutable, incluso para el escritor privilegiado del
  trigger. En un episodio abierto tampoco cambian sus fotografías.
- El inicio del SLA global se fotografía en el ledger; el primer contacto y los
  tiempos siguen siendo derivados desde actividades, sin almacenar resultados.
- `crm.actividades` conserva el timeline humano. El ledger conserva intervalos
  analíticos; ninguno reemplaza al otro y no se duplican emisores.

El ledger es deliberadamente un **ledger de episodios de analista**, no de
custodia. Los movimientos de parqueo, cambio de bandeja y salida de bandeja quedan
como actividades estructuradas con supervisor anterior/nuevo; el episodio cerrado
conserva su destino. Así se respeta la decisión de tener cero episodios de analista
abiertos durante el parqueo sin perder el timeline del par completo.

## SLA de gestión

Desde V2 existen dos relojes deliberadamente distintos. El principal es el SLA
global del ciclo, iniciado al ingresar o reabrir y sin descuento por parqueo o
transferencia. El segundo es el SLA operativo del tramo, útil para medir cuánto
tarda cada responsable desde que recibe el lead.

El reloj operativo empieza en `episodio.asignado_en`. El primer contacto del episodio es la
primera actividad dentro de su ventana con:

`crm.actividades.creado_por = episodio.analista_id`

Tipos significativos:

- `llamada_realizada`
- `llamada_no_contestada`
- `whatsapp_enviado`
- `whatsapp_recibido`
- `reunion_realizada`

Notas, reasignaciones y cambios de etapa no acreditan contacto. El SLA inicial es
24 horas. Un lead tibio reasignado exige que el nuevo analista vuelva a
contactarlo para cumplir su tramo. Ese reinicio no afecta el SLA global que
representa la espera real del cliente.

La ventana del episodio es semiabierta: `[asignado_en, finalizado_en)`. Una
actividad en el instante exacto de la transferencia pertenece solo al episodio
nuevo. En el denominador de contacto 24 h entran los episodios que ya tuvieron
contacto o que ya cumplieron 24 horas; un episodio reciente aún no vencido no se
marca como incumplido.

Para el indicador descriptivo **estancado**, solo una actividad significativa
reinicia el reloj. Umbrales iniciales:

- `nuevo`: 1 día sin contacto;
- `contactado` o `reunion_agendada`: 3 días sin actividad significativa;
- `propuesta_enviada`: 5 días sin actividad significativa.

## Riesgo de incentivo conocido y aceptado

Una transferencia o parqueo cierra el episodio anterior como no terminal y ese
episodio no queda contando como `abierto maduro`. Esto evita penalizar a quien ya
no controla el lead, pero permite intentar sacar cartera estancada antes de que
madure.

Mitigaciones obligatorias:

- V1 muestra tasa/cantidad de transferencias y parqueos por analista.
- El episodio y su SLA incumplido no se borran: si ya era evaluable, sigue en la
  tasa histórica aunque termine por transferencia o parqueo.
- La fase posterior medirá también efectividad de la asignación original a lo
  largo de la vida del lead.
- Las recomendaciones no se habilitan hasta backtestear esta conducta.

## Contrato de la V1 de Gerencia

La pantalla reemplaza **Altas por analista** por **Distribución de leads por
capital** y muestra, sin voz de oráculo:

- cantidad y capital por analista;
- capacidad objetivo como `carga/capacidad` cuando esté definida;
- por repartir;
- contacto dentro de 24 h, mediana de primer contacto, sin tocar, estancados y
  transferidos;
- convertidos, descartados, conversión resuelta `C/(C+D)`, evidencia `C de N` y
  el estado `Sin muestra` cuando `C+D=0`.

**Analista** agrupa a cualquier miembro comercial que haya sido `vendedor_id` de
un episodio, incluidos supervisores con cartera propia. Los miembros inactivos
conservan su historia, pero no aparecen como receptores disponibles. Gerencia no
es candidata a recibir cartera nueva.

**Por repartir** incluye tanto las bandejas de supervisor como los leads con ambos
IDs nulos; estos últimos quedan bajo responsabilidad operativa de Gerencia.

La distribución recibida y el rendimiento por rango usan el monto/moneda
fotografiados al abrir el episodio. Los leads aún por repartir usan el monto actual
del lead. Una recalificación posterior no cambia retroactivamente el rango que un
analista recibió.

Rangos PEN exactos, sin solapamiento:

- `(0, 1 000]`
- `(1 000, 5 000]`
- `(5 000, 10 000]`
- `(10 000, 20 000]`
- `(20 000, 50 000]`
- `(50 000, 100 000]`
- `> 100 000`
- `sin_monto`, solo como alerta transitoria de calidad

PEN y USD nunca se suman. V1 comienza en PEN; si aparecen leads USD, se muestra
un aviso hasta aprobar sus rangos. La UI no muestra Wilson, ranking predictivo ni
verbos `Priorizar/Pausar`.

## Gate para inteligencia posterior

La recomendación solo se publica cuando existan cierres reales suficientes para:

- intervalos de confianza con anchura aceptable por rango;
- backtest contra resultados posteriores;
- estabilidad semanal sin cambios frecuentes de veredicto;
- umbrales de maduración y SLA calibrados con el ciclo real;
- revisión comercial de sesgo y concentración.

Hasta entonces el sistema presenta evidencia y el gerente decide.

## Estado de implementación 0C — 2026-07-17

La trazabilidad base quedó implementada y validada en el branch Supabase
`crm-distribucion-capital-20260717`:

- migración remota `20260717212639_crm_lead_asignaciones_ledger`;
- Edge Function `crm-convertir-lead` v2, versión histórica desplegada en esa fase
  del branch antes del DDL: exige dueño y
  que convierta su propio analista antes de deduplicar, crear Auth/perfil o enviar correo;
- `INSERT` asignado abre ledger pero no inventa una actividad de reasignación;
- descarte parqueado queda sin atribución; conversión parqueada se bloquea;
- en una transición compuesta domina reapertura, luego reactivación y después
  el movimiento ordinario de tenencia;
- `ciclo_actual` es estado técnico controlado por servidor;
- `creado_en`/`actualizado_en` del lead se fijan en servidor para proteger el reloj SLA;
- un lead con dueño no puede desactivarse: primero debe parquearse o cerrar su tenencia;
- leads, analistas, actores y supervisores con historia no se borran físicamente;
  el proceso operativo es desactivación conservando auditoría;
- dos reasignaciones concurrentes produjeron una secuencia íntegra de tres episodios,
  con dos cerrados, uno abierto y ningún solape.

La frontera acordada permanece explícita: esta iniciativa modifica únicamente el
[[CRM comercial]] del equipo. `public_html`, la interfaz del portal de clientes y su
comportamiento no forman parte del cambio.

## Estado de implementación 4A — capacidad objetivo

La migración branch `20260717215535_crm_capacidad_leads_objetivo` incorporó el dato
manual que Gerencia necesita para leer carga como `actual/objetivo`:

- unidad: cantidad objetivo de leads activos simultáneos;
- `NULL`: capacidad todavía no configurada; no se interpreta como cero;
- rango permitido: `1..1000`, solo para vendedor o supervisor con cartera;
- únicamente una Gerencia activa en `crm.equipo` y `public.perfiles` puede cambiarlo;
- analistas desactivados en cualquiera de ambos registros no son configurables;
- `authenticated` no recibió escritura directa sobre `crm.equipo`; la mutación es una
  RPC estrecha y auditada.

El oráculo transaccional devolvió `CAPACIDAD_TX_OK`, incluida la denegación de una
Gerencia cuyo perfil general fue desactivado, y no dejó fixtures. Esta expansión es
compatible y no toca el portal de clientes.

## Estado de implementación 4B — capital obligatorio

La migración branch `20260717222018_crm_monto_estimado_obligatorio` cerró la
calidad del dato actual sin inventar ningún monto:

- el guard aborta si existe un lead nulo o fuera de rango;
- `monto_estimado` es `NOT NULL`, mayor que cero, máximo `9999999999.99` y admite
  hasta dos decimales;
- la columna usa `numeric` sin typmod y un CHECK explícito para rechazar
  `5000.999`, evitando que PostgreSQL lo redondee silenciosamente a `5001.00` y
  cambie el bucket comercial;
- el frontend CRM exige y valida capital/moneda tanto al crear como al editar;
- PEN y USD se conservan juntos en el snapshot; editar el lead no reescribe el
  episodio ya abierto;
- `crm.lead_asignaciones` permanece compatible con historia legada nullable:
  `sin_monto` solo sobrevive como bucket defensivo de calidad histórica, nunca
  como una captura nueva válida.

El oráculo persistente devolvió `MONTO_TX_OK` con los bordes exactos `0.01 PEN` y
`9999999999.99 USD`; el oráculo 0C volvió a pasar y no quedaron fixtures. En
producción el orden obligatorio es frontend compatible primero y 4B después.

## Estado de implementación 4C — fotografía gerencial

La migración productiva `20260717224252_crm_metricas_distribucion_leads` implementó
una sola fotografía JSON atómica para Gerencia. El período es inclusivo en fechas
de Lima y pertenece a la cohorte por `episodio.asignado_en`; cartera y colas son el
estado actual. La lectura incluye:

- carga/capacidad actuales en todas las monedas;
- matriz PEN por los siete rangos comerciales y el bucket defensivo `sin_monto`;
- USD como resumen separado, nunca sumado a PEN;
- ciclos convertidos/descartados, episodios y leads únicos;
- SLA evaluable, contacto en hasta 24 horas, mediana, transferencias, parqueos,
  desactivaciones, sin tocar y estancados por etapa;
- cola global de Gerencia y bandejas de supervisor usando el monto actual.

La RPC devuelve contadores crudos. La interfaz deriva `C/(C+D)`, SLA y ocupación;
si no existe denominador muestra **Sin muestra**. No devuelve un score, Wilson,
ranking ni recomendación de ruteo.

El oráculo transaccional fijo devolvió `METRICAS_DISTRIBUCION_TX_OK`: concilió
7 episodios de cohorte, una transferencia A→B, dos ciclos D→C del mismo lead,
contacto exactamente a 24 h, contacto tardío, cartera anterior al período,
snapshot frente a recalificación, PEN/USD, analista inactivo, capacidad y tres
leads por repartir. Los fixtures volvieron a cero por `ROLLBACK`.

Acceso: el wrapper `SECURITY DEFINER` permite solo Gerencia activa o el predicado
global existente (`directorio/admin/superadmin`). `anon`, vendedores, el core
`private` y la tabla del ledger permanecen inaccesibles directamente. El WARN del
advisor por función definer ejecutable es deliberado y está cubierto por ese gate.

La frontera sigue intacta: solo se agregaron objetos `crm/private` y código del CRM
del equipo. El portal de clientes y `public_html` no se modifican.

## Estado de implementación V1 — interfaz de Gerencia

La vista **Hoy · Gerencia** ya integra la matriz descriptiva y sustituye el
gráfico ambiguo **Altas por analista**. La lectura visible distingue:

- episodios recibidos, leads únicos y cartera actual por rango PEN;
- ciclos convertidos/descartados y conversión `C/(C+D)`;
- carga contra capacidad, con capacidad editable únicamente por Gerencia;
- SLA total PEN + USD, sin tocar, estancados y tasa de salidas no terminales;
- cola por repartir separada de la cartera asignada;
- capital PEN y USD sin sumarlos ni aplicarles rangos compartidos.

Las cifras grandes de cada banda representan **episodios recibidos en la
cohorte**; la cartera que sigue actualmente con el analista aparece debajo. Esto
evita que una transferencia borre visualmente que el lead sí fue recibido. La
interfaz diferencia **Sin muestra** de conversión (`C+D=0`) del SLA aún no
evaluable, y no expone mensajes técnicos crudos cuando falla una mutación.

La demo no fabrica episodios ni distribución histórica: explica que esa lectura
solo existe con datos reales. La revisión visual se hizo en escritorio y móvil;
las tarjetas de gráficos no desbordan el ancho de 390 px.

Gates cerrados el 2026-07-17:

- lint global: aprobado;
- TypeScript: aprobado;
- Vitest: `39` archivos y `380/380` pruebas aprobadas;
- Playwright: `57` aprobadas, `11` omitidas por gates reales existentes y `0`
  fallos;
- build de producción: aprobado.

## Deploy V1 completado — 2026-07-17

La salida se hizo con un artefacto aislado, no con el `dist` del worktree
concurrente. Primero se reconstruyó `HEAD 0b681f6` más los cinco cambios de
orígenes ya desplegados: su payload de 39 archivos coincidió byte a byte con el
ZIP productivo anterior. Sobre esa base se aplicaron únicamente capital
obligatorio, distribución, capacidad, trazabilidad y los guards operativos
asociados; avatar/género, timeline, sidebar y otras vistas concurrentes quedaron
fuera.

Validación del release aislado:

- lint y build: aprobados;
- Vitest de regresión aislada: `318/318`;
- E2E dirigidas sobre el servidor aislado: `5/5`;
- ZIP: `crm-distribucion-capital.zip`, SHA-256
  `2ac1ebfb4293adc22bb2dc24ed205021de9a02de286f7dda495661f12f8029e4`.

El frontend se desplegó exclusivamente en `crm.miavance.com` con:

- principal `index-BLE2aLAQ.js`;
- estilos `index-DQW10zlJ.css`;
- API `crm-api-BEDEBmrq.js`;
- vista Hoy `hoy-CL74qkg7.js`;
- gráficas `graficas-gerencia-cRf1-F6d.js`.

HTML y esos cinco assets quedaron idénticos byte a byte entre el build aislado
y producción; todos respondieron HTTP 200. El ZIP remoto respondió 404 tanto en
`crm.miavance.com` como en `miavance.com`.

Después del frontend se fusionó el branch Supabase. Producción contiene las seis
migraciones `20260717202053` a `20260717224435`, el ledger, la RPC V1, capacidad
y capital obligatorio. `crm-convertir-lead` quedó activo en producción en versión 4. Un smoke
con identidad de Gerencia devolvió JSON V1 válido, 18 analistas y 0 por repartir;
producción seguía con `0` leads y `0` actividades, así que el ledger nació sin
backfill. Los avisos del advisor son los deliberados: ledger fail-closed sin
policy, wrappers definer con gate interno e índices nuevos aún sin uso.

El branch temporal se eliminó tras el merge para detener el costo. Solo quedó
`main` en estado `FUNCTIONS_DEPLOYED` y `ACTIVE_HEALTHY`. Una sesión autenticada
de vendedor cargó el CRM y sus datos reales después del deploy. El portal de
clientes y `public_html` no se desplegaron ni modificaron como parte de esta
iniciativa.

## V2 de hardening — 2026-07-18

La migración local `20260718152741_crm_inteligencia_gerencial_hardening` corrige
el incentivo pendiente sin romper el rollback de V1:

- `crm.leads` conserva el inicio global del ciclo desde ingreso o reapertura;
- cada episodio fotografía ese mismo inicio y una transferencia no lo modifica;
- la cabecera gerencial usa SLA global, mientras cada analista conserva su SLA
  operativo de tramo con una etiqueta explícita;
- ciclos sin analista también entran al vencimiento global;
- parqueos y transferencias no descuentan tiempo y sus cantidades siguen visibles;
- el contrato V2 declara `SEPARADOS_SIN_CONVERSION` para PEN/USD;
- V1 y V2 quedan detrás de `crm_metricas_bridge`, rol sin login, privilegios de
  sistema ni acceso a tablas; la función `private` revalida identidad y rol;
- V1 permanece disponible para volver al frontend anterior sin borrar historia;
- el nuevo generador de release conserva ZIP, manifiesto, hashes por archivo y
  SHA-256 del paquete fuera del web root.

Estado: implementado en el repositorio, todavía no aplicado a producción. Debe
pasar branch, oráculo SQL V2, pruebas de frontend, advisors y build antes del
deploy. Ver [[Deploy a Hostinger]].
