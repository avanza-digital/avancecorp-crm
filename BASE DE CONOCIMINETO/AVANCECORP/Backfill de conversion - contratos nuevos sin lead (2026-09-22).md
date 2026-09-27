# Backfill de conversión: contratos «nuevo» de setiembre sin lead (2026-09-22)

✅ **Ejecutado en producción el 23/09/2026 a las 18:30 (Lima)**, con el OK de Miguel.

- 32 leads convertidos y 11 operaciones de cartera.
- La conversión de setiembre pasó de 4,32 % a 6,83 %.
- Verificado: el capital no cambió, la alarma cuadra, Metas coincide con la cifra oficial y el sistema
  quedó igual (mismas huellas).

## Qué se encontró
- 44 contratos `categoria='nuevo'` del 1 al 22 de setiembre no tienen lead ni operación de cartera. El cruce por persona, puente, `leads_de_personas`, DNI y teléfono de 9 dígitos **no quitó ninguno**: la sospecha de falsos positivos no se cumplió.
- **31 tipo A**: cliente nuevo, primer contrato. **11 tipo B**: cliente que ya tenía contratos, así que el contrato es un upgrade. **1 histórico** (`2026-01-000670`: inicio 12/01/2026, `fecha_cierre_comercial` = fecha de carga). **1 especial**: su teléfono coincide con un lead de formulario descartado de la misma analista, pero el nombre es totalmente distinto.
- Mismo patrón en meses anteriores, sin corregir: dic 2 · ene 3 · feb 5 · mar 9 · abr 11 · may 17 · jun 69 · jul 106 · ago 72.

## Candados que lo explican (no son bugs)
- `private.trg_leads_zz_enlaza_identidad`: un lead que lleva el DNI de alguien que ya es cliente **no puede nacer** (`ya_es_cliente`). La única excepción es la válvula `crm.op_privilegiada`, que es de las RPC.
- `private.conversion_lead_con_inversion`: para convertir hace falta una solicitud de inversión confirmada ligada al lead, y la solicitud Avance (`confirmar_inversion_revisada_fn`) **siempre crea un contrato nuevo**. **No existe una puerta para enganchar un lead a un contrato que ya existe.**
- `trg_leads_guard_tenencia` fija `creado_en = statement_timestamp()` al insertar, y después es inmutable. Un lead retroactivo **no puede** llevar otra fecha.
- El cierre se cuenta por `lead_asignaciones.resultado_en`, que es el momento en que se ejecuta. Un backfill corrido en octubre cae en octubre.

## Reglas del sistema que se reutilizan
- Elegibilidad de un upgrade (`public.crear_contrato`): el período del upgrade tiene que ser **posterior** al del primer contrato del cliente. Un segundo contrato en el mismo mes del primero nace no elegible: una persona, una conversión.
- Un lead `alta_manual` no entra en el divisor y sí cuenta en el numerador (regla cerrada de Miguel).

## Prueba en Docker (22/09 noche)
Miguel condicionó A1: la solicitud de respaldo no puede aparecer en pantallas ni cambiar el
capital.
- **A1 (la solicitud se queda) no cumple.** El botón «Ver inversión y bienvenida» de un lead
  convertido abre cualquier solicitud confirmada del lead (`contexto_conversion_inversion_fn`).
- **A1′ (andamio transitorio) cumple.** La inversión inicial y la solicitud solo existen dentro
  de la transacción: se usan para cruzar el candado de conversión y se retiran, con copia en
  `audit_log`. El capital total queda idéntico en todas las pantallas medidas, y la pantalla del
  lead muestra «flujo anterior».
- **Dos efectos secundarios pendientes de decisión:** los leads del backfill cuentan como
  «recibidos» el día de ejecución (Leads recibidos, Reparto, Distribución) y como «fuera de
  objetivo» en el SLA de primer contacto y primera gestión.
- Estado, scripts y receta del banco: `CRM-Avance-Corp/supabase/scripts/backfill-conversion-2026-09/LEEME.md`.

## Segundo banco (23/09), contra la producción de ese día
- **Un contrato hecho por el formulario de solicitud SIN partir de un lead ya no se puede
  enganchar a un lead después** (3 casos: `001377`, `001396`, `001416`). Tres candados lo
  impiden:
  - una sola solicitud por inversión;
  - el `lead_origen_id` de una solicitud es inmutable;
  - una inversión tiene una sola fuente (un contrato o un cierre externo).
  Esa conversión se pierde para siempre. Es un argumento para que el formulario exija un lead.
- **El tipo A y el tipo B se cruzan.** Un cliente puede tener su primer contrato de setiembre
  en A y el segundo del mismo mes en B. Tras correr A, ese cliente ya tiene lead, y la guarda
  «sin lead» de B lo descartaba. Corregido en el script, y ensayado en los dos órdenes y dos veces
  seguidas.
- **El efecto sobre el SLA tiene dos caras:** los leads del backfill salen «fuera de objetivo» en
  primer contacto y primera gestión, pero «cumplidos» en la etapa «nuevo».

Relacionado: [[Alta directa de clientes cerrada al analista (2026-09-15)]]

## Lecciones de la ejecución (23/09)
- **Los leads con origen «oficina» (walk-in) no suman a la conversión.** Quedan convertidos, pero el núcleo
  solo cuenta cierres de landing, formulario y referido. Dos ventas walk-in del backfill no movieron el %.
- **En la cartera cuenta una conversión por cliente y mes.** Un segundo upgrade del mismo cliente en el
  mismo mes no suma.
- **Los clientes que la analista marca como «renovación» o «upgrade», pero sin contrato anterior en el
  sistema,** se contaron como clientes nuevos, por decisión de Miguel.
