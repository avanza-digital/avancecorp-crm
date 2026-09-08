---
tags: [crm, multiempresa, f4, conversion, decisiones, recenso]
fecha: 2026-09-07
estado: banco-preparado-construccion-pendiente
autoridad: aclaracion-de-Miguel-2026-09-07-y-reglas-vigentes-del-proyecto
---

# F4 multiempresa — reglas vigentes y punto de partida

Miguel pidió corregir las diferencias documentales y continuar el objetivo principal:
una persona puede invertir varias veces en Avance, Qorilazo y Prodelco conservando
su identidad e historial. No pidió rediseñar la conversión comercial existente.

**Continuación del 07/09:** banco local separado preparado; 29 funciones iguales
a producción, 7 Auth ficticios y acceso HTTP verificado. El motor F4 sigue
pendiente. Objetivo de cierre y evidencia: [[F4 multiempresa - objetivo de cierre y banco aislado (2026-09-07)]].

## Decisiones que gobiernan la continuación

1. **Se conserva el trabajo de F2.** F4 no vuelve a migrar los cierres ya vinculados.
   Un faltante demostrado por recenso se atiende por el proceso canónico de
   vinculación, con alcance acotado y sin repetir ni duplicar las operaciones resueltas.
2. **Las fuentes económicas siguen siendo `public.contratos` y
   `crm.cierres_externos`.** `crm.inversiones` es el registro relacional que une
   persona, empresa y fuente. No se crea otra calculadora ni otra fuente de montos.
3. **Se retira la regla general «una conversión en toda la vida».** La identidad
   única y el lead canónico no eliminan los aportes de cartera elegibles que ya
   admite el proyecto. El núcleo existente decide elegibilidad, peso, período,
   deduplicación, atribución y ajustes; una inversión nueva no convierte por el
   solo hecho de registrarse, y tampoco se rechaza su aporte por una prohibición vitalicia.
4. **Anulación comercial:** rige ATR-4; afecta conversión, conserva Capital,
   producción y AUM. Los demos se excluyen por su clasificación técnica. Una
   retirada financiera es otra operación, con sus reglas propias.
5. **F4 y F5 se ensayan con datos sintéticos.** El circuito multiempresa con dinero
   real espera la conciliación de F7/G6 y el piloto F8/G7. El piloto se acepta por
   volumen, conciliación y pruebas; G8 exige además un ciclo operativo mensual completo.

Las reglas 1 y 2 mantienen lo acordado en el maestro. La regla 3 recoge la
corrección explícita de Miguel en esta sesión y tiene precedencia sobre los
pasajes anteriores de conversión vitalicia. Las reglas 4 y 5 conservan ATR-4 y
los requisitos del maestro; no representan una nueva autorización productiva.

## Conversión: fuente vigente y comprobación

Autoridad funcional: [[Nucleo de conversion - diagnostico de llegadas y asignaciones 2026-09-04]]
y [[Gestión comercial de clientes - renovaciones y upgrades]]. El 07/09 se volvió
a leer el código **vivo de producción**, en transacciones de solo lectura:

| Caso | Regla existente que F4 debe conservar |
|---|---|
| Upgrade | Es elegible cuando su período comercial es posterior al mes del primer contrato del cliente; el criterio vivo usa `fecha_cierre_comercial`, no la fecha de digitación. Aporte elegible: 1 al numerador y 0 al divisor. |
| Renovación | Aporta el peso de Referido del período (0,15 en la regla documentada del 04/09) y 0 al divisor. No se fija ese peso en otro cálculo. |
| Varias operaciones de cartera del cliente en un mes | Se elige la primera **elegible** por fecha de operación, creación e id, antes de filtrar rango y ámbito. Como máximo una operación de cartera elegible por cliente/mes aporta. |
| Capital adicional de una renovación | No crea un segundo aporte de conversión. |
| Atribución | El núcleo usa la atribución vigente de la cadena y el responsable registrado, según las reglas ya publicadas. |
| Mes sellado / anulación | Se conserva el tratamiento vigente de fotografías y ajustes. |

La deduplicación por cliente/mes corresponde a la rama de **operaciones de
cartera**. No se convierte en una fórmula nueva que mezcle o limite por su cuenta
los cierres de leads. Tampoco se extiende automáticamente la etiqueta «upgrade»
a cualquier nueva inversión en cooperativa: cada operación debe entrar por el
tipo y la fuente que admite el núcleo canónico.

`es_primera_conversion` de `crm.inversiones` no es una autorización para sustituir
el núcleo por una conversión vitalicia. F4 debe comprobar los consumidores de
esa marca y preservar los aportes de renovaciones/upgrades elegibles.

## Punto de partida verificado en producción

Recenso del **07/09/2026 a las 11:32–11:33 de Lima**:

| Comprobación | Resultado |
|---|---|
| `resolver_en_puertas` | `true` |
| `inversiones_escritura` / `ficha_360_neutral` | `false` / `false` |
| Registro `crm.inversiones` | 14 filas, todas externas; 0 enlaces a contratos Avance |
| Cierres clase B del mapa F2 | 14; los 14 conservan su inversión y titular principal coherentes |
| Cierres no anulados sin inversión enlazada | 1, Qorilazo; creado el 03/09 a las 15:32 Lima; documento de formato válido, sin identidad y sin clasificación en el mapa F2 |
| Restricción de cierres externos | Sigue `cierres_externos_un_cierre_por_lead`: `UNIQUE(lead_id)` |
| Funciones cuyo cuerpo contiene `INSERT INTO crm.inversiones` | `crm.convertir_lead_externo(...)` y `private.backfill_multiempresa_ejecutar()`; este censo textual no sustituye el inventario de escrituras indirectas/dinámicas |

Los 15 cierres mencionados en RETOMAR-62 no son 15 operaciones por migrar otra vez:
**14 ya están vinculadas y 1 necesita revisión y vinculación acotada**. Que el
documento tenga formato válido no demuestra todavía ausencia de conflicto de identidad.

Huellas de `pg_get_functiondef` observadas:

- `private.conversion_episodios(...)`: `8a2549dbfa59c732da04900ed90b6361`.
- `public.crear_contrato(jsonb,jsonb)`: `1cd2730dc75c966cfbd9ea8d95d4d1ed`.
- `private.capital_episodios(...)`: `b8f375fbb377582835f4cfe222240c5b`.
- `crm.convertir_lead_externo(...)`: `aeaead8aad9817e9790f6fc97448d25e`.
- `private.backfill_multiempresa_ejecutar()`: `930acfc792eb4db91df599f26e283f12`.

Evidencia sin nombres ni documentos:
`CRM-Avance-Corp/supabase/scripts/evidencia-f4/2026-09-07-preparacion.json`.
Consultas reproducibles de solo lectura en el archivo adyacente
`2026-09-07-preparacion-consultas.sql`. No se ejecutaron cambios de datos ni de esquema.

## Siguiente trabajo de F4, en orden de dependencia

1. **Conciliar la base y cerrar el diseño del escritor.** Conservar las 14
   inversiones; clasificar el cierre faltante y preparar su vinculación por la
   puerta canónica. Inventariar las lecturas que suponen un cierre por lead antes
   de evolucionar esa restricción. Declarar el alcance de los contratos Avance
   históricos que aún no tienen enlace relacional, sin reescribirlos.
2. **Construir el registro de inversión en cooperativa para persona existente.**
   Autorización por responsable/equipo, empresa, documento, depósito, evidencia,
   fecha comercial y vencimiento. Confirmación atómica de cierre, inversión y
   titular; repetición segura y conflicto ante datos distintos. Registrar otra
   operación no vuelve a ejecutar la conversión inicial del lead.
3. **Integrar Avance por sus puertas existentes.** Reutilizar contrato,
   cronograma, titularidad y recuperación de Auth/Portal. Enlazar la inversión
   sin interferir con las renovaciones/upgrades ni duplicar sus aportes.
4. **Ensayar el conjunto y la reversa.** Avance→Qorilazo, Qorilazo→Prodelco,
   Qorilazo→Avance y segunda inversión en la misma empresa. Depósito repetido,
   dos solicitudes simultáneas, cambio de responsable, veto, permisos, fallo de
   Auth y reglas de conversión/capital. El banco de ensayo debe estar aislado;
   `banco-f7` es compartido y requiere coordinación efectiva antes de usarlo.
5. **Completar G4 y continuar a F5.** Preparar el paquete revisable de SQL,
   pruebas, huellas y reversa antes de su autorización de ejecución. La Ficha
   360 es F5; postventa F6; conciliación F7; piloto F8 y expansión F9.

La captura de DNI en el formulario mejora la cobertura de identidad al ingresar.
Sigue siendo una decisión comercial pendiente; **no impide construir y probar
F4 con personas que ya tienen identidad verificada**.

## Relacionado

- [[RETOMAR-62 - identidad unificada ENCENDIDA, sigue F4 (2026-09-07)]]
- [[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]]
- [[Contrato de la sancion de anulacion (ATR-4, 2026-08-31)]]
- [[Main unico - sincronizacion y publicacion 2026-09-04]]
- [Plan maestro y bitácora](../../PLAN-MAESTRO-MULTIEMPRESA.html)
