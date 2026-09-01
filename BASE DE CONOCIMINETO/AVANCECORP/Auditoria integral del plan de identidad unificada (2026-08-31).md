---
tags: [crm, identidad, auditoria, arquitectura, leads, cartera]
fecha: 2026-08-31
estado: auditoria-concluida-f1-bloqueada
precedencia: corrige el diagnóstico del plan y del HTML; no autoriza implementación
---

# Auditoría integral del plan de identidad unificada — 2026-08-31

## 0. Veredicto y límite

La dirección comercial es correcta, pero el contrato y el HTML actuales **no son todavía un diseño implementable**. F1 queda bloqueada hasta reconciliar identidad, cardinalidad del lead, inversiones externas, personas sin documento, roles/perfiles, demos y métricas.

> **Regla comercial confirmada:** una persona tiene una identidad neutral y un solo lead total. Puede tener múltiples roles y múltiples inversiones. El lead conserva la captación; contratos, cierres y operaciones conservan las inversiones; la postventa no reabre el pipeline.

Esta auditoría fue de solo lectura. No autoriza migraciones, limpieza, fusiones, backfills, cambios de permisos ni modificación de datos.

## 1. Evidencia revisada

- [[Contrato arquitectonico consolidado - identidad unificada de inversionistas (F0 2026-08-31)]]
- [[Censo F0 de identidad unificada - resultado de solo lectura (2026-08-31)]]
- [[Cola F0.5 de identidad unificada - resultado de solo lectura (2026-08-31)]]
- [[Identidad unificada de inversionistas - plan pendiente]]
- [[Ficha comercial 360 de clientes - plan]]
- [[Gestión comercial de clientes - renovaciones y upgrades]]
- [[Contrato de la atribucion por cadena de upgrade (2026-08-30)]]
- [[Contrato de la sancion de anulacion (ATR-4, 2026-08-31)]]
- `artifacts/Plan principal - Identidad unificada de inversionistas.html`
- migraciones, RPC, funciones de importación y núcleos semánticos del repositorio.
- cinco revisiones independientes de solo lectura, reconciliadas por Camila.

## 2. Fotografía adicional de leads — solo lectura

Sonda agregada contra la base enlazada, dentro de `READ ONLY` y `ROLLBACK`, observada el 31/08/2026 aproximadamente a las 19:46 Lima:

- 831 leads totales;
- 628 vivos;
- 178 descartados;
- 25 convertidos;
- 15 con `perfil_id` y 816 sin `perfil_id`;
- cero grupos repetidos por `perfil_id`;
- cero grupos repetidos por DNI válido;
- un grupo con teléfono repetido en dos filas: una `contactado` y una `convertido`;
- cero grupos con más de un lead vivo por teléfono.

La coincidencia telefónica no autoriza fusión automática. Es una señal débil que debe revisarse de forma pseudonimizada.

La base vigente solo tiene unicidad parcial por teléfono/DNI para leads vivos (`uq_leads_telefono_vivo`, `uq_leads_dni_vivo`). No existe identidad neutral ni unicidad total por persona.

## 3. Bloqueantes P0

### P0-1 — El contrato se contradice sobre el número de leads

El mismo contrato afirma «varios leads» en el invariante 1 y «exactamente un solo lead total» en el invariante 6 (`Contrato…:532-537`). También conserva «una oportunidad viva» en el gate de F2 y en la decisión final (`:493`, `:574`).

**Corrección:** una persona tiene como máximo un lead total, no solo uno vivo. Un lead convertido queda como historia de captación; no se reabre para simular postventa y no se crea otro.

### P0-2 — El modelo real permite duplicados terminales

Los índices actuales excluyen convertidos y descartados (`20260709000001_cimientos_crm.sql:189-193`). La toma reutiliza ciertos descartados, pero el importador con service role conserva excepciones y puede duplicar un descartado vencido (`20260817164745_crm_lead_libre_f2_tomar.sql:36-41`). El modelo histórico también permite alta nueva para estados no cubiertos.

**Consecuencia:** el plan no puede prometer unicidad total sin adaptar todas las puertas: alta manual, importador, toma, reapertura, edición de identificadores y conversiones.

### P0-3 — “Un lead” bloquea hoy múltiples inversiones cooperativas

`crm.cierres_externos` impone `UNIQUE(lead_id)` (`20260812000259_crm_cierres_externos.sql:104-175`). `crm.convertir_lead_externo` inserta el cierre y convierte el lead (`:849-888`). No existe una puerta postventa para una segunda inversión cooperativa de la misma persona sin volver a convertir o crear otro lead.

**Corrección:** separar la primera conversión del registro de inversiones externas posteriores. Una persona y su lead pueden relacionarse con 0:N hechos económicos externos, cada uno con transacción, empresa, moneda, atribución y snapshot propios.

### P0-4 — Personas sin documento: el objetivo y el contrato no pueden cumplirse a la vez

El contrato prohíbe identidades provisionales y permite lead sin `inversionista_id` (`Contrato…:138-146`). La fotografía tiene 806 leads sin DNI y Miguel confirmó que esa ausencia es normal.

Sin documento, nombre/teléfono/correo no pueden demostrar que dos altas son la misma persona. Por tanto, una unicidad física absoluta por persona es imposible antes de identificarla.

**Decisión requerida:**

- opción recomendada: ancla interna provisional, claramente no verificada, 1:1 con el lead; nunca fusiona automáticamente y se consolida solo con documento o revisión humana; o
- mantener el contrato sin provisionales y declarar honestamente que la unicidad solo es garantizable para identidades fuertes, con alertas/manual para el resto.

### P0-5 — El vínculo 0:1 a `public.perfiles` no admite múltiples roles

El contrato propone `crm.inversionistas.perfil_id` opcional y único (`Contrato…:82-90`, `:100-114`). Una persona puede tener un perfil cliente y otro perfil interno; Rosa confirmó un caso legítimo.

**Corrección:** la identidad neutral necesita 0:N perfiles mediante puente auditado o enlace equivalente. Auth y cada perfil conservan sus permisos; el vínculo de identidad no concede acceso.

### P0-6 — Demos no están modelados de forma uniforme

`crm.cierres_externos` no tiene `es_demo`. Hay dos contratos de Prueba Cliente aún no marcados como demo y el cierre Qorilazo de desarrollo tiene un depósito relacionado. ATR-4 busca conservar capital anulado; sin clasificación demo explícita, podría hacer reaparecer el cierre Qorilazo de prueba como capital.

**Corrección:** antes de modificar núcleos o ejecutar identidad, definir una clasificación durable de datos demo y filtros únicos consumidos por capital, conversión, cartera, rankings y backfill. La clasificación no equivale a borrar.

## 4. Contradicciones P1

### P1-1 — “El mismo lead conserva toda gestión” mezcla captación y postventa

La Ficha 360 vigente usa `crm.actividades_cliente`, tareas de cliente, contratos y `crm.operaciones_cartera`; expresamente no devuelve al cliente al pipeline (`Ficha comercial 360…:28-42`, `:173-180`).

**Regla correcta:** no crear otro lead. La captación permanece en el lead histórico; la postventa permanece en sus entidades postventa.

### P1-2 — Katherine está “incluida manualmente” pero el contrato no permite crearle identidad

Katherine es cliente real y se conserva. Sin documento confirmado no entra al backfill automático. Bajo el contrato vigente tampoco recibe una identidad operativa manual.

**Corrección:** rotularla como “persona real en alcance, vínculo pendiente; sin identidad creada hasta resolver documento”, salvo que Miguel apruebe el modelo provisional de P0-4.

### P1-3 — La derivación 405 → 403 → 402 está mal explicada

El artefacto reproducible reporta:

- clase A: 393;
- clase B: 10;
- A+B: 403 identidades automáticas técnicas;
- clase E por cruce con otro rol: 2.

La reconstrucción posterior de 402 es:

```text
393 A + 10 B - 1 perfil demo - 1 cierre Qorilazo demo + 1 Rosa confirmada = 402
402 + Katherine pendiente = 403 personas reales estimadas en alcance
```

Esta reconstrucción mezcla resultado SQL y decisiones manuales; todavía no es una métrica emitida por una consulta reproducible. Debe codificarse en el recenso final.

### P1-4 — “403 clientes reales” usa una etiqueta incorrecta

Las 402 incluyen fuentes de perfil cliente, cierre externo y un caso colaborador–inversionista. No todas significan “clientes Portal”.

**Corrección:** usar “personas/inversionistas reales en alcance” y separar: perfiles Avance, externos, colaboradores-inversionistas, demos, pendientes documentales y episodios sin identidad.

### P1-5 — Los 16 grupos no son 16 decisiones abiertas actuales

Son grupos de la cola F0.5 en una fotografía histórica y varias filas se solapan. Después de decisiones de Miguel, algunos quedaron resueltos o excluidos.

**Corrección:** el HTML debe distinguir “16 grupos observados en F0.5” de “pendientes abiertos tras decisiones”.

### P1-6 — F0.5 no está “lista para cierre”

La regla de un lead total se confirmó después del censo original. La cola no censó de forma concluyente duplicidad total por persona y quedan abiertos P0-3, P0-4, P0-5 y P0-6.

**Estado correcto:** F0 de datos ejecutado; contrato arquitectónico reabierto; F0.5 pendiente de reconciliación; F1 bloqueada.

### P1-7 — Ficha 360 aparece como futura aunque ya está desplegada

La Ficha 360 Avance está publicada/restaurada, pero la nota conserva secciones históricas que aún dicen preview pendiente (`Ficha comercial 360…:10-26` frente a `:151-171`). El HTML de identidad llama F4 “futura”.

**Corrección:** F4 no crea una Ficha 360 desde cero; amplía la Ficha 360 existente para consultar identidad neutral y cooperativas sin romper la rama Avance ni banca.

### P1-8 — Responsable nulo y permisos actuales no son equivalentes

Varias políticas actuales usan `creado_por` cuando `asesor_perfil_id` es nulo, por ejemplo `20260830090000_crm_f5_a_una_sola_pregunta_analista.sql:521-546` y cuentas bancarias `20260803221622…:277-282`.

**Corrección:** no usar `creado_por` como responsable neutral. Conservar el comportamiento Avance existente hasta una decisión explícita, pero las nuevas acciones neutrales deben depender del responsable vigente o de un rol global autorizado.

### P1-9 — La regla “una conversión por persona/mes” todavía cambia semántica futura

Hoy la deduplicación de cartera es por `cliente_id + periodo`; no unifica necesariamente conversión inicial, cierres cooperativos y operaciones de cartera bajo una persona. El F0 observó delta cero en esa fotografía, pero eso no demuestra que nunca habrá delta.

**Corrección:** Miguel debe aprobar expresamente si la primera inversión/operación elegible de la persona en el mes gana entre todos los canales. Los hechos económicos perdedores conservan capital, atribución e historial.

### P1-10 — El rollback está descrito de forma insuficiente

El plan debe especificar mapa fuente→persona, reversión de enlaces nullable, fusiones, reservas, efectos Auth y qué no puede deshacerse. Auth y PostgreSQL no comparten transacción.

**Corrección:** el rollback no puede significar borrar personas o hechos; debe desconectar enlaces nuevos, conservar el mapa y dejar hechos históricos intactos.

## 5. Matriz objetivo de cardinalidades

| Relación | Cardinalidad propuesta | Regla |
|---|---:|---|
| Persona ↔ identificadores | 1:N | varios documentos históricos/vigentes; cada identificador vigente resuelve una sola persona |
| Persona ↔ perfiles/Auth | 1:N | varios roles/perfiles posibles; ningún permiso se hereda por identidad |
| Persona ↔ lead | 0:1 total | un solo lead durante toda la relación; NULL solo mientras la persona no sea resoluble según el modelo aprobado |
| Lead ↔ actividades de captación | 1:N | historia de preventa, reasignaciones y conversión |
| Persona/perfil ↔ actividades postventa | 1:N | no reabre ni duplica el lead |
| Persona ↔ contratos Avance | 1:N | por perfil cliente y titularidad legal existente |
| Persona ↔ inversiones/cierres externos | 1:N | empresa, documento snapshot, transacción y atribución propios |
| Persona ↔ operaciones de cartera | 1:N | renovaciones/upgrades preservan contratos y cadena |
| Persona ↔ responsable vigente | 0:1 | puede quedar nulo; historial de responsables 1:N |
| Persona ↔ empresas | N:M | a través de inversiones; no como rol o permiso |
| Persona ↔ conversión acreditada mensual | 0:1 | solo si Miguel aprueba la regla transversal; no limita hechos económicos |

## 6. Plan consolidado antes de diseñar F1

### F0-R1 — Rectificación contractual

**Objetivo comercial:** que todos los documentos respondan igual qué es persona, lead, postventa e inversión.

**Resultado visible:** contrato con un solo invariante de lead, Ficha 360 existente correctamente rotulada y estados actuales honestos.

**Riesgo evitado:** construir constraints incompatibles.

**Gate:** cero contradicciones entre contrato, censo, F0.5, HTML y decisiones de Miguel.

### F0-R2 — Decidir identidad sin documento

**Objetivo comercial:** mantener operables los leads normalmente indocumentados sin fusionar personas inseguras.

**Resultado visible:** regla explícita para ancla provisional o para alcance limitado de unicidad fuerte; tratamiento de Katherine coherente.

**Riesgo evitado:** duplicar personas o bloquear captación.

**Gate:** decisión de Miguel y escenarios concurrentes definidos.

### F0-R3 — Diseñar múltiples inversiones externas

**Objetivo comercial:** que un cliente reinvierta en Qorilazo/Prodelco sin otro lead.

**Resultado visible:** primera conversión separada de inversiones externas posteriores; 0:N hechos por persona.

**Riesgo evitado:** violar `UNIQUE(lead_id)`, duplicar leads o perder capital.

**Gate:** contratos, transacciones, atribución, anulación y postventa externa definidos.

### F0-R4 — Clasificación demo durable

**Objetivo comercial:** que ninguna prueba afecte cartera, capital, conversiones, rankings o backfill.

**Resultado visible:** clasificación y dependencias de demos reproducibles; Qorilazo y depósito tratados juntos; contratos demo pendientes identificados.

**Riesgo evitado:** que ATR-4 o identidad hagan reaparecer datos de desarrollo.

**Gate:** consulta de paridad real/sin-demo y autorización separada para cualquier escritura.

### F0-R5 — Recenso ampliado y reproducible

**Objetivo comercial:** conocer el universo exacto inmediatamente antes del diseño final.

**Resultado visible:** desglose de automáticos, manuales, demos, leads duplicados potenciales, múltiples perfiles, episodios sin identidad y responsables nulos.

**Riesgo evitado:** usar 402/403 como constantes históricas.

**Gate:** timestamp único, definiciones etiquetadas y conteos reconciliados mecánicamente.

### F0-R6 — Aprobar semántica de conversión y permisos

**Objetivo comercial:** decidir quién recibe crédito sin mover dinero ni dar acceso indebido.

**Resultado visible:** regla persona/mes aprobada o rechazada; responsable neutral separado de `creado_por`, atribución de venta y permisos Auth.

**Riesgo evitado:** alterar rankings, pagos o visibilidad.

**Gate:** simulación por mes abierto/sellado, roles y atribución; delta aprobado expresamente.

### Gate para recién diseñar F1

Solo después de F0-R1…R6 se prepara F1. Preparar F1 tampoco autoriza ejecutarla.

F1 deberá incluir:

1. modelo de persona neutral y puente 1:N a perfiles;
2. identificadores fuertes e historia;
3. vínculo 0:1 persona–lead con tratamiento de no identificados;
4. enlaces 1:N a inversiones externas;
5. backfill nullable y mapa auditable;
6. RLS deny-by-default;
7. puertas canónicas para todas las altas/ediciones/importaciones;
8. clasificación demo consumida por los núcleos;
9. pruebas de concurrencia, paridad y meses sellados;
10. rollback de enlaces sin borrar hechos.

## 7. Decisiones que deben volver a Miguel

1. **Identidad sin documento:** provisional interna no verificada, o unicidad garantizada solo desde documento/revisión humana.
2. **Conversión transversal:** confirmar o rechazar máximo una conversión por persona y mes entre Avance, cooperativas y cartera.
3. **Acceso cuando no hay responsable:** las nuevas superficies neutrales quedan solo para Gerencia hasta asignación, o mantienen alguna regla explícita distinta; nunca se hereda silenciosamente de `creado_por`.

## 8. Estado corregido

- F0 censo de datos: ejecutado en solo lectura.
- Contrato F0: reabierto por contradicciones.
- F0.5: evidencia útil, no cerrada.
- F1: no diseñada definitivamente y no autorizada.
- Limpieza demo: no autorizada.
- Datos productivos: no modificados por esta auditoría.
