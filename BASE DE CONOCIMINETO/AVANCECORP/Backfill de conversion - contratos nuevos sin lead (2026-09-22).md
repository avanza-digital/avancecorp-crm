# Backfill de conversión: contratos «nuevo» de setiembre sin lead (2026-09-22)

Investigación con solo lecturas en producción. Pendiente la decisión de Miguel.

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

Relacionado: [[Alta directa de clientes cerrada al analista (2026-09-15)]]
