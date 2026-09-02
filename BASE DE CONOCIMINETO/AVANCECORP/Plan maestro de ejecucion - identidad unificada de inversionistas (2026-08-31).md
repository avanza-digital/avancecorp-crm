---
tags: [crm, identidad, inversionistas, f1, roadmap, supabase, arquitectura]
fecha: 2026-08-31
ultima_revision: 2026-09-01
version: 2
estado: reemplazado-como-plan-principal-conservado-como-anexo-tecnico
propietario_decisiones: Miguel
alcance: F0-R1-a-F6
meta_comercial: aumentar-capital-recurrente-mediante-retencion-y-reinversion
horizonte_estimado: 12-semanas-mas-seguimiento-30-60-90
reemplazado_por: Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)
---

# Plan maestro de implementación — capital recurrente e identidad unificada de inversionistas

> [!warning] Plan principal reemplazado el 2026-09-01
> Miguel precisó que el objetivo central es permitir que un cliente invierta varias veces en distintas empresas. La fuente vigente es [[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]]. Esta nota se conserva únicamente como anexo técnico de identidad, seguridad y despliegue; su meta provisional de crecimiento no gobierna el proyecto.

> [!warning] Alcance de esta nota
> Este plan autoriza únicamente ordenar y revisar el trabajo. No autoriza ejecutar SQL, hacer backfill, cambiar datos ni desplegar en producción. Cada cambio de base requiere la aprobación separada definida en la sección de gates.

## 1. Meta comercial y objetivo habilitador

### 1.1 Meta comercial

> **Aumentar el capital recurrente de Avance Corp mediante una gestión sistemática de retención y reinversión, evitando que una misma persona quede fragmentada entre varios leads, perfiles, contratos o empresas.**

La identidad unificada no es el fin comercial. Es la infraestructura que permite reconocer la relación completa, anticipar vencimientos, asignar un responsable, ejecutar la siguiente gestión y registrar una nueva inversión sin perder historia.

La cadena de valor del programa es:

> **Identidad confiable → relación completa → oportunidad postventa visible → gestión oportuna → mayor reinversión y capital recurrente.**

### 1.2 Resultado comercial esperado

Al terminar F5, Gerencia debe poder responder y actuar sobre estas preguntas sin armar cruces manuales:

- ¿Quién es realmente cada inversionista y quién lo atiende hoy?
- ¿Cuánto capital vigente e histórico tiene por empresa y moneda?
- ¿Qué inversiones vencen pronto y cuál es la siguiente gestión acordada?
- ¿Quién reinvirtió, quién está por renovar y quién se está perdiendo?
- ¿Qué nueva inversión corresponde a un cliente existente y no a una captación nueva?
- ¿Qué analista originó la relación y quién gestiona actualmente la postventa?
- ¿Qué personas no deben ser contactadas o requieren revisión humana?

### 1.3 Meta cuantitativa propuesta

La línea base comercial todavía debe calcularse. Para no dejar el programa sin dirección, se propone que Miguel ratifique en G0 una meta provisional y la ajuste cuando exista el baseline reproducible:

- **North Star:** capital recurrente confirmado proveniente de inversionistas con una inversión previa elegible, separado por empresa y moneda;
- **propuesta inicial:** aumentar ese capital recurrente **15% durante los seis meses posteriores a F5** frente al periodo comparable anterior;
- **meta complementaria:** aumentar **10 puntos porcentuales** la tasa de reinversión de personas elegibles;
- **cobertura operativa:** al menos 95% de los vencimientos de los siguientes 60 días con responsable y próxima acción vigente;
- **integridad comercial:** cero reinversiones registradas mediante un lead nuevo.

El 15% y los 10 puntos son una hipótesis de gestión, no una cifra histórica demostrada. En la semana 0 se calcula la base por moneda y empresa; Miguel puede ratificarlos o sustituirlos por una meta aprobada. PEN y USD nunca se suman para aparentar crecimiento.

### 1.4 Objetivo técnico habilitador

Construir una identidad neutral y única para cada persona inversionista, separada de sus roles, permisos y operaciones comerciales, bajo esta regla:

> **Una persona confirmada, una identidad neutral y un solo lead total; puede tener múltiples perfiles, contratos e inversiones sin compartir permisos ni reescribir la historia.**

El sistema deberá:

- reconocer a la misma persona en Avance Corp, cierres externos y futuros canales;
- impedir automáticamente un segundo lead cuando la identidad ya está confirmada;
- registrar varias inversiones sin fabricar leads nuevos;
- conservar contratos, cierres, actividades, tareas, atribuciones y PDFs existentes;
- mantener separados los permisos de analista, vendedor, cliente Portal u otros roles;
- contar conversión por persona y capital por hechos económicos reales;
- convertir vencimientos y clientes inactivos en colas comerciales accionables;
- operar con seguridad por defecto, auditoría y reversa comprobada.

## 2. Punto de partida y precedencia

Este plan consolida:

- [[Auditoria integral del plan de identidad unificada (2026-08-31)]];
- [[Contrato arquitectonico consolidado - identidad unificada de inversionistas (F0 2026-08-31)]];
- [[Censo F0 de identidad unificada - resultado de solo lectura (2026-08-31)]];
- [[Cola F0.5 de identidad unificada - resultado de solo lectura (2026-08-31)]];
- [[Identidad unificada de inversionistas - plan pendiente]];
- `artifacts/Auditoria preparacion F1 - Identidad unificada de inversionistas (2026-08-31).html`.

La auditoría vigente da **GO para diseñar** y **NO-GO para aprobar o ejecutar**. Antes de congelar F1 deben cerrarse F0-R1 a F0-R6.

## 3. Cómo se medirá el éxito

F1–F5 solo se considerarán terminadas cuando se pruebe que:

1. un documento fuerte normalizado no puede producir dos identidades activas;
2. una identidad confirmada no puede tener dos leads históricos distintos;
3. una identidad puede tener cero, uno o varios perfiles, sin que esos perfiles hereden permisos entre sí;
4. una identidad puede tener varios contratos, cierres externos y episodios de cartera;
5. nombre, teléfono y correo nunca fusionan personas automáticamente;
6. las candidatas ambiguas quedan fuera del backfill automático;
7. el capital antes y después coincide por moneda y fuente;
8. los meses sellados no cambian;
9. la conversión por persona/mes cumple la regla comercial aprobada;
10. todas las pruebas de acceso por rol pasan y ningún usuario obtiene datos bancarios por la nueva identidad;
11. la migración y su reversa han sido ensayadas desde una base reconstruida;
12. el recenso final termina con cero fusiones ambiguas y todas las diferencias explicadas.

### 3.1 Tablero de éxito comercial

| Indicador | Definición | Línea base | Meta de lanzamiento | Meta de beneficio |
|---|---|---:|---:|---:|
| Capital recurrente confirmado | Suma de inversiones elegibles de personas con inversión previa; por empresa y moneda | Semana 0 | Sin pérdida de paridad | +15% a seis meses, propuesta a ratificar |
| Tasa de reinversión | Personas elegibles que vuelven a invertir / personas elegibles del periodo | Semana 0 | Medición confiable | +10 pp a seis meses, propuesta a ratificar |
| Cobertura de próximos vencimientos | Vencimientos ≤60 días con responsable y próxima acción no vencida | Semana 0 | ≥95% | ≥95% sostenido |
| Reinversiones sobre un nuevo lead | Reinversiones que obligaron a crear otro lead | Semana 0 | 0 | 0 |
| Identidades fuertes duplicadas | Documentos fuertes vigentes asociados a más de una identidad | Censo final | 0 | 0 |
| Identidades con varios leads | Identidades confirmadas ligadas a más de un lead | Censo final | 0 | 0 |
| Casos sin responsable | Identidades reales sin responsable actual | Semana 0 | 100% visibles para Gerencia | Tendencia semanal descendente |
| Oportunidades vencidas sin gestión | Oportunidades postventa con próxima acción vencida | Semana piloto | Medición visible | Tendencia semanal descendente |
| Incidentes de acceso/PII | Accesos fuera de ámbito o propagación de permisos | 0 aceptable | 0 | 0 |

### 3.2 Regla de atribución de beneficios

No se atribuirá todo crecimiento al software. Para considerar que el programa produjo beneficio se exige:

1. baseline congelado antes del piloto;
2. definición estable de “elegible”, “reinversión” y “capital confirmado”;
3. comparación por empresa y moneda, sin conversión cambiaria improvisada;
4. cohortes de inversionistas existentes separadas de captación nueva;
5. registro de responsable, próxima acción y resultado de la gestión;
6. revisión a 30, 60 y 90 días, y una evaluación comercial a seis meses.

## 4. Decisiones que deben quedar en un acta canónica

Las decisiones F0.5 ya confirmadas no se vuelven a debatir: se promueven al contrato canónico. Las dos decisiones comerciales todavía abiertas se ratifican antes de congelar F1.

| ID | Regla a dejar firmada | Recomendación | Estado actual |
|---|---|---|---|
| D1 | Una persona tiene un solo lead total, aunque esté descartado o convertido. | Mantener lo confirmado en D-F05-09. La postventa nunca crea otro lead. | Confirmada; falta consolidarla sin contradicciones. |
| D2 | Un lead sin documento puede seguir operando. | No crear identidad automática hasta documento fuerte o revisión humana. Teléfono, correo y nombre solo producen candidatos. | Confirmada de hecho en D-F05-06; falta promoverla al contrato. |
| D3 | `no_contactar` antes y después de una identidad fuerte. | Sin identidad fuerte, el veto vive en el lead. Al confirmar/fusionar identidad, se eleva a la persona, conserva auditoría y prevalece si cualquier fuente tiene veto. | Falta ADR de transición y pruebas. |
| D4 | Conversión comercial transversal. | Máximo una conversión acreditada por persona y mes; gana la primera inversión confirmada. Una anulación posterior no promueve silenciosamente otra. | Pendiente de ratificación de Miguel. |
| D5 | Identidad válida sin responsable actual. | Solo Gerencia puede verla y administrarla hasta asignación; la atribución histórica no concede acceso vigente. | Responsable nulo ya aceptado; falta ratificar el acceso. |
| D6 | Registros de prueba. | Clasificación técnica durable, auditable y consumida por backfill y métricas; no depender de una lista de nombres. | Personas demo identificadas; falta el mecanismo. |
| D7 | Varias inversiones externas. | Conservar el cierre inicial ligado al único lead y habilitar una puerta postventa idempotente para reinversiones, ligada a la identidad y no a un lead nuevo. | Falta ADR y diseño. |

## 5. Ruta completa

| Etapa | Resultado | Se puede comenzar cuando | Termina cuando |
|---|---|---|---|
| F0-R | Contrato único y decisiones reconciliadas | Miguel acepta este plan como guía | R1–R6 tienen respuesta inequívoca y dueño |
| F1 | Ancla neutral, enlaces y backfill seguro | F0-R permite diseñar | Esquema aditivo, seguridad, backfill y reversa pasan el gate F1 |
| F2 | Todas las escrituras usan la identidad canónica | F1 estabilizada | Ninguna puerta puede crear una segunda persona o un segundo lead |
| F3 | Métricas por identidad | F2 estable | Conversión y capital reconcilian con oráculos y meses sellados |
| F4 | Ficha 360 neutral de solo lectura | F3 estable | Historial completo visible según ámbito, sin ampliar permisos |
| F5 | Operación comercial y UI final | F4 validada | Usuarios completan los recorridos críticos sin regresiones |
| F6 | Transferencias de titularidad | F1–F5 cerradas | Contrato propio, legal y operativo, aprobado aparte |

F6 se mantiene deliberadamente fuera del camino crítico: transferir titularidad no es lo mismo que resolver identidad.

### 5.1 Cronograma de referencia

Estimación: **12 semanas** con una persona de ingeniería dedicada, un revisor independiente disponible en cada gate, decisiones de Miguel en un máximo de 48 horas y usuarios piloto disponibles. Si alguna condición no se cumple, se mueve el calendario; nunca se elimina un gate para recuperar tiempo.

| Tiempo | Frente principal | Resultado visible | Gate |
|---|---|---|---|
| Semana 0 | Meta, baseline y decisiones | North Star, fórmulas, cohortes y D1–D7 firmadas | G0 |
| Semanas 1–2 | F0-R + diseño F1 | Contrato corregido, ADR, modelo, seguridad, backfill y pruebas de diseño | G1 |
| Semanas 3–4 | Construcción F1 en aislamiento | Migración candidata, pgTAP/RLS, backfill y reversa ensayados | Preparación G2 |
| Semana 5 | Recenso y corte F1 | Caparazón aditivo y backfill seguro aceptados | G2/G3 |
| Semanas 6–7 | F2 escrituras canónicas | Altas, conversiones, contratos y reinversiones usan una sola identidad | G4 técnico |
| Semana 8 | F3 métricas | Capital y conversión por identidad reconciliados | Aceptación F3 |
| Semanas 9–10 | F4/F5 producto | Lista postventa, Ficha 360, cola y flujo de reinversión | Piloto |
| Semana 11 | Piloto controlado | Gerencia + usuarios piloto operan casos reales acotados | Go/no-go comercial |
| Semana 12 | Despliegue progresivo | Activación por roles y estabilización | G5 operativo |
| Días 30/60/90 | Beneficios | Adopción, calidad, reinversión y capital recurrente | Revisión de valor |
| Mes 6 | Meta comercial | Comparación contra baseline aprobado | Cierre de beneficio |

### 5.2 Trabajo paralelo permitido

Para reducir tiempo sin aumentar riesgo:

- UX puede diseñar Ficha 360, lista postventa y flujo de reinversión desde la semana 2, pero no conectarlos a producción antes de F1/F2;
- el tablero comercial y sus fórmulas pueden prepararse mientras se construye F1, pero no reemplazan los núcleos vigentes antes de F3;
- pruebas, fixtures y oráculos se escriben junto con cada paquete, no al final;
- capacitación y guías operativas pueden prepararse durante F4/F5;
- los gates, recenso, backfill, seguridad y activación de escritores permanecen secuenciales.

## 6. F0-R — cerrar la base contractual

### F0-R1. Fuente canónica única

- corregir la contradicción entre “varios leads” y “un solo lead total”;
- declarar obsoletas las frases anteriores que permitan varios leads por persona;
- separar expresamente captación, primera conversión y postventa;
- añadir una tabla de precedencia documental: contrato canónico > ADR aprobadas > plan > censos fechados.

**Salida:** contrato F0 corregido, con fecha, estado y aprobación de Miguel.

### F0-R2. Identidad sin documento

- fijar que no existe fusión automática por nombre, teléfono o correo;
- permitir que el lead continúe sin identidad fuerte;
- documentar la vinculación manual cuando una fuente autorizada verifica a la persona;
- declarar con honestidad que la unicidad total solo se garantiza desde documento fuerte o revisión humana.

**Salida:** ADR de identidad provisional/no documental.

### F0-R3. Primera conversión y reinversión externa

- definir el cierre inicial como evento que convierte el único lead;
- definir la reinversión como hecho económico postventa que no altera el lead;
- exigir una clave técnica de idempotencia o transacción externa;
- conservar empresa, moneda, monto, fecha, atribución, snapshot comercial, anulación y trazabilidad;
- mantener `UNIQUE(lead_id)` hasta que exista y se pruebe la nueva puerta postventa.

**Salida:** ADR de inversiones externas 1:N y contrato de la futura RPC.

### F0-R4. Demos durables

- crear una clasificación técnica por identificador, motivo, fuente, autor y fecha;
- propagar su consumo al backfill, capital y conversión;
- no borrar físicamente registros ni dependencias dentro de F1;
- tratar por separado cualquier futura limpieza, con autorización de escritura.

**Salida:** modelo de clasificación demo y lista inicial auditada.

### F0-R5. Recenso reproducible

- versionar consulta, parámetros, timestamp, hash y fuente;
- comparar con la fotografía anterior y explicar cada deriva;
- producir clases automáticas, manuales, no resolubles y demo;
- repetirlo justo antes del backfill.

**Salida:** censo preflight firmado; los conteos 402/403 actuales son orientación, no autorización.

### F0-R6. Reglas comerciales finales

- ratificar D4 sobre conversión por persona/mes;
- ratificar D5 sobre identidades sin responsable;
- incorporarlas al contrato, a la matriz RLS y a los oráculos de métricas.

**Gate de salida F0-R:** no queda ninguna contradicción, alternativa implícita ni decisión sin dueño.

## 7. F1 — identidad neutral y migración segura

F1 se divide en diseño, ensayo, migración vacía, backfill y aceptación. No se mezclan en una sola acción.

### F1-A. Modelo de datos de destino

El diseño debe contemplar, como mínimo:

- `crm.inversionistas`: ancla neutral de la persona, estado y responsable actual opcional;
- `crm.inversionista_identificadores`: identificadores fuertes, normalizados, vigentes/históricos y con fuente;
- `crm.inversionista_perfiles`: puente opcional 0:N hacia perfiles existentes; cada perfil pertenece como máximo a una identidad;
- ledger de responsables: asignaciones con inicio, fin, autor y motivo;
- dimensión o registro durable de datos demo/prueba;
- mapa de backfill y fusiones: origen, destino, clase, regla, ejecución y reversa;
- `crm.leads.inversionista_id` opcional durante la transición y único cuando no es nulo;
- enlace opcional desde cierres/operaciones actuales hacia la identidad;
- auditoría de cambios sensibles y de resoluciones manuales.

Reglas estructurales:

- los enlaces nuevos empiezan opcionales mientras existan escritores antiguos;
- no se eliminan columnas, restricciones o funciones antiguas en F1;
- las restricciones costosas se introducen y validan en pasos separados cuando corresponda;
- toda foreign key y columna usada de forma recurrente por RLS/búsqueda debe tener el índice apropiado;
- la resolución concurrente usa operaciones atómicas, orden de locks consistente y transacciones cortas;
- ninguna tabla nueva queda accesible por cliente hasta tener RLS, políticas y grants mínimos;
- los perfiles/Auth continúan siendo contenedores de acceso, no la identidad comercial;
- los hechos históricos apuntan a la identidad, pero no se reescriben ni se mueven.

**Entregables:** diagrama, diccionario de datos, cardinalidades, estados, restricciones, estrategia de claves y ADR técnicas.

### F1-B. Seguridad y permisos

Preparar una matriz por rol para Gerencia, supervisor, vendedor, analista, cliente Portal, anónimo y service role.

Condiciones obligatorias:

- deny-by-default para tablas nuevas;
- RLS antes de cualquier grant al cliente;
- funciones privilegiadas solo cuando sean necesarias, en schema no expuesto, con `search_path` fijo, comprobación explícita del llamador, `EXECUTE` revocado a `PUBLIC` y grants mínimos;
- vistas con comportamiento invoker cuando deban respetar RLS del llamador;
- ninguna pertenencia a una identidad concede por sí sola acceso a otro perfil o rol;
- una identidad sin responsable solo es visible para Gerencia;
- información bancaria continúa detrás de su autorización actual.

El changelog de Supabase vigente al 2026-09-01 anuncia que las tablas nuevas dejarán de exponerse automáticamente a Data/GraphQL API para todos los proyectos el 2026-10-30. El diseño no dependerá de la exposición implícita: documentará schema expuesto, `GRANT`, `REVOKE`, RLS y `EXECUTE` de cada objeto. Una tabla “no visible” y una tabla “visible pero filtrada por RLS” son controles distintos y ambos deben probarse.

**Entregables:** matriz RLS, inventario de funciones, prueba negativa por rol y revisión independiente.

### F1-C. Backfill clasificado e idempotente

Procesar por clases, nunca mediante una fusión general:

| Clase | Tratamiento |
|---|---|
| Documento fuerte, válido y no ambiguo | Candidato a backfill automático después del recenso |
| Katherine/documento conflictivo | Vinculación manual tras verificar documento; conservar todo el historial |
| Lead sin documento | Mantener sin identidad automática; no bloquear operación |
| Coincidencia solo por teléfono, correo o nombre | Señal para revisión, jamás fusión automática |
| Perfil en varios roles legítimos | Una identidad y varios perfiles; permisos independientes |
| Placeholder o documento compartido no confiable | No fusionar |
| Demo/prueba confirmado | Excluir del universo real y de métricas; no borrar en F1 |
| Responsable desconocido | Crear identidad con responsable nulo y asignar después |

El backfill debe:

- poder ejecutarse más de una vez sin duplicar;
- escribir primero un mapa auditable;
- bloquear o serializar por identificador fuerte durante la resolución;
- detenerse ante cualquier colisión no prevista;
- incluir preflight, transacción por lote controlado y postflight;
- separar automáticamente seguros de manuales y cuarentena;
- nunca deducir un responsable para “completar” datos.

**Entregables:** especificación de clases, borrador de backfill fuera de la carpeta de migraciones, oráculos y runbook de reversa.

### F1-D. Ensayo aislado

Después de aprobar el diseño, pero antes de producción:

1. reconstruir la base local desde todas las migraciones;
2. ejecutar pruebas de base automatizadas;
3. aplicar el esquema F1 vacío;
4. ejecutar el backfill sobre una copia controlada/sanitizada;
5. simular fallos a mitad de lote;
6. ejecutar la reversa ensayada;
7. reconstruir de nuevo desde cero para demostrar reproducibilidad;
8. revisar SQL y seguridad por una segunda persona/agente sin editarlo.

La guía vigente de Supabase respalda probar migraciones mediante reconstrucción local y `supabase test db`; el plan adopta ese criterio como gate, no como verificación opcional.

Matriz mínima de verificación a incorporar al repositorio:

| Capa | Verificación |
|---|---|
| SQL/estructura | Reconstrucción local completa desde migraciones y comparación de objetos esperados |
| Base/pgTAP | `supabase test db`, incorporando nuevas suites de invariantes y RLS |
| Scripts CRM | `npm run check:scripts` desde `CRM-Avance-Corp/` |
| RLS real | `npm run test:rls`, más casos específicos de identidad por rol |
| Edge/importación | `npm run test:edge-preflight` y `npm run test:importar-leads-edge` |
| Frontend | `npm run check` desde `CRM-Avance-Corp/app/` |
| Recorridos | `npm run check:all`, ampliando Playwright para Ficha 360 y reinversión |
| Contratos RPC | Fixtures con forma real anterior y nueva; cliente tolerante desplegado antes del servidor |
| Concurrencia | Pruebas HTTP/SQL simultáneas con documento, lead y transacción repetidos |
| Reversa | Ensayo cronometrado con evidencia de que hechos históricos permanecen intactos |

### F1-E. Pruebas obligatorias

| Caso | Resultado esperado |
|---|---|
| Dos solicitudes simultáneas con el mismo documento | Una identidad; la otra reutiliza o recibe conflicto controlado |
| Dos intentos de crear lead para identidad confirmada | Un único lead total |
| Persona sin documento | El lead opera; no nace una identidad automática |
| Nombre/teléfono iguales entre personas distintas | No hay fusión automática |
| Analista que también invierte | Una identidad, varios perfiles, cero propagación de permisos |
| Identidad sin responsable | Solo Gerencia tiene acceso hasta asignación |
| Uno de varios leads históricos marca `no_contactar` al fusionar | La identidad conserva el veto y su origen auditado |
| Mismo backfill ejecutado dos veces | Mismos resultados y cero duplicados |
| Contrato, cierre o perfil demo | No ingresa a métricas reales |
| Reversa después de enlaces parciales | Se desconectan enlaces nuevos sin borrar hechos históricos |

### F1-F. Despliegue en producción, solo con autorización separada

Este repositorio tiene una regla de despliegue más estricta que la receta general de Supabase:

- **no usar `supabase db push`**: el historial remoto contiene migraciones del Portal que no están en la carpeta CRM y un push intentaría reproducirlas;
- no usar `migration repair` para ocultar la divergencia;
- ejecutar únicamente el archivo aprobado mediante el mecanismo explícito documentado por el proyecto;
- verificar objetos, constraints, grants y funciones vivas: una respuesta “success” o una fila en `schema_migrations` no demuestra que el objeto se creó;
- si una RPC añade campos a su respuesta, desplegar primero un frontend compatible y después el servidor;
- una activación funcional se hace después de comprobar ambas capas, nunca dentro de la misma maniobra irreversible.

Secuencia recomendada:

1. nombrar exactamente la migración y congelar su hash;
2. tomar baseline y respaldo verificable;
3. ejecutar recenso final READ ONLY;
4. abortar si la deriva no está explicada;
5. publicar primero cualquier cliente tolerante que requiera el nuevo contrato;
6. aplicar únicamente el caparazón aditivo y permisos del archivo aprobado;
7. contar y comparar objetos reales, no solo el historial de migraciones;
8. verificar estructura, RLS y salud del CRM antes de poblar;
9. ejecutar backfill automático seguro por lotes controlados;
10. dejar excepciones en cola manual, sin forzarlas;
11. reconciliar conteos, capital, conversión y periodos sellados;
12. mantener consumidores antiguos activos hasta aceptar F1;
13. cerrar evidencia y ventana de observación;
14. autorizar por separado el paso a F2.

**Gate de salida F1:** cero duplicados fuertes, cero fusiones ambiguas, paridad económica, seguridad aprobada, reversa ensayada y evidencia firmada.

## 8. F2 — todas las puertas de escritura canónicas

Inventariar y adaptar, sin excepción:

- creación manual de lead;
- importaciones y cualquier uso de service role;
- toma de lead libre;
- edición de documento o datos identificadores;
- reapertura y descarte;
- conversión Avance;
- conversión externa inicial;
- registro de reinversión externa postventa;
- creación/vinculación de perfil cliente y contrato;
- fusiones o correcciones manuales autorizadas.

Cada puerta debe resolver en una sola transacción:

1. normalizar identificadores;
2. localizar/bloquear la identidad fuerte;
3. crear o reutilizar la identidad según la regla aprobada;
4. localizar/reutilizar el único lead;
5. validar permisos y responsable actual;
6. escribir el hecho económico o comercial;
7. registrar auditoría e idempotencia.

La primera conversión puede cerrar el lead. Las inversiones posteriores no vuelven a convertirlo ni crean otro. `UNIQUE(lead_id)` no se relaja hasta que la puerta postventa esté probada y desplegada.

**Gate de salida F2:** no quedan escrituras directas o rutas paralelas capaces de eludir la identidad; las pruebas de carrera e idempotencia pasan por cada puerta.

## 9. F3 — métricas por identidad

### Conversión

- concentrar la regla persona/mes en un único núcleo semántico;
- contar la primera inversión confirmada según D4;
- no promover otra silenciosamente si la primera se anula;
- mantener trazabilidad al episodio original;
- conservar el valor de meses sellados.

### Capital

- sumar todos los hechos económicos elegibles;
- deduplicar por transacción/operación, no por persona;
- mantener monedas separadas;
- consumir la clasificación demo durable;
- demostrar paridad por fuente, moneda y estado.

**Gate de salida F3:** delta inesperado de conversión = 0; delta inesperado de capital = 0; meses sellados idénticos.

## 10. F4 — Ficha 360 neutral

Crear un modelo de lectura nuevo, no una extensión silenciosa de la ficha Portal actual.

Debe mostrar, según ámbito autorizado:

- identidad y sus identificadores permitidos;
- único lead y todo su historial;
- perfiles/roles relacionados sin mezclar permisos;
- contratos Avance e inversiones externas;
- actividades, tareas, atribuciones y responsable actual/histórico;
- alertas de documento, veto de contacto, demo y calidad de datos.

La información bancaria permanece fuera del agregado general y conserva su autorización específica.

**Gate de salida F4:** pruebas de acceso por rol, exactitud de totales, historial completo y cero filtraciones entre perfiles.

## 11. F5 — experiencia operativa

- búsqueda única por persona con indicadores de coincidencia fuerte/débil;
- aviso y reutilización del lead existente en vez de crear otro;
- flujo separado de “primera inversión” y “nueva inversión”;
- bandeja de excepciones para Gerencia;
- asignación/reasignación con historial;
- explicación visible de por qué una fusión automática fue bloqueada;
- adaptación progresiva de tipos y lecturas para tolerar el despliegue escalonado;
- pruebas funcionales, visuales y responsive de todos los roles.

**Gate de salida F5:** los recorridos reales funcionan en escritorio y móvil, sin regresiones en cartera, cierres, agenda, ficha ni métricas.

## 12. F6 — transferencias, después

Solo comenzar cuando F1–F5 estén estabilizadas. Requiere un contrato separado para:

- titular original y nuevo titular;
- fecha efectiva y soporte legal;
- tratamiento de PDFs y obligaciones existentes;
- métricas, capital, comisiones y atribución;
- reversa, disputa y auditoría.

No se permite implementar una transferencia como “cambiar el inversionista_id” de un hecho histórico.

## 13. Gates de autorización

| Gate | Quién decide | Qué autoriza | Qué no autoriza |
|---|---|---|---|
| G0 — aceptar el plan | Miguel | Usar esta secuencia, medir baseline READ ONLY y preparar documentos | SQL, datos o producción |
| G1 — congelar diseño F1 | Miguel + revisión técnica | Cerrar ADR, esquema, backfill, pruebas y reversa | Ejecutar en producción |
| G2 — aprobar SQL ensayado | Miguel, nombrando archivo y hash | Preparar una ventana concreta | Cambios adicionales no incluidos |
| G3 — ejecutar F1 | Miguel, autorización expresa separada | Aplicar esa migración y backfill exactos | F2 o cambio de métricas |
| G4 — activar escritores F2 | Miguel + aceptación F1 | Encender puertas canónicas | F3/F4/F5 automáticamente |
| G5 — aceptación final | Miguel + usuarios responsables | Declarar objetivo operativo cumplido | F6 transferencias |

## 14. Condiciones de detención inmediata

Se aborta la etapa en curso si ocurre cualquiera de estas condiciones:

- un documento fuerte apunta a más de una identidad;
- una identidad confirmada termina con más de un lead;
- aparece una fusión basada solo en nombre, teléfono o correo;
- el recenso difiere sin explicación;
- una prueba RLS o de separación de permisos falla;
- cambia capital, conversión o un mes sellado sin una causa aprobada;
- una fila demo entra al universo real;
- el backfill deja casos sin mapa o sin reversa;
- existe una puerta de service role no inventariada;
- la migración no puede reconstruirse o revertirse en aislamiento;
- el archivo o hash ejecutable difiere del aprobado.

## 15. Responsables

| Rol | Responsabilidad principal |
|---|---|
| Miguel | Reglas comerciales, alcance, aprobación de gates y autorización de producción |
| Ingeniería | ADR técnicas, modelo, migraciones, backfill, pruebas, observabilidad y reversa |
| Gerencia | Resolver identidades sin responsable, casos manuales y excepciones |
| Supervisores | Asegurar cobertura de vencimientos, disciplina de próxima acción y adopción del equipo |
| Analistas/vendedores | Ejecutar gestiones, registrar resultados y reutilizar siempre la relación existente |
| Revisor independiente | Revisar SQL, RLS, invariantes, concurrencia y evidencia sin ser autor del cambio |
| Usuarios piloto | Validar los recorridos Ficha, cartera, conversión y reinversión antes de ampliar |

## 16. Evidencia mínima por entrega

Cada gate debe conservar:

- commit base y estado Git;
- archivo, tamaño, hash y timestamp de cada artefacto;
- consultas y resultados del preflight/postflight;
- matriz de decisiones y aprobaciones;
- salida de reconstrucción local y pruebas de base;
- resultados de concurrencia, RLS e idempotencia;
- conciliación de capital y conversión;
- baseline y tablero de indicadores comerciales por empresa/moneda;
- capturas visuales cuando haya cambios de UI;
- acta de piloto, adopción, incidentes y feedback;
- runbook y resultado del ensayo de reversa;
- lista explícita de excepciones que quedaron fuera.

## 17. Backlog completo de implementación

Cada fila produce evidencia revisable. “Terminado” significa entregable, pruebas y aceptación; no solo código escrito.

| ID | Ventana | Paquete | Entregable verificable | Responsable | Depende de |
|---|---|---|---|---|---|
| COM-01 | S0 | Baseline comercial | Capital recurrente, reinversión, vencimientos y cobertura por empresa/moneda | Ingeniería + Miguel | G0 |
| COM-02 | S0 | Meta comercial | North Star, meta a seis meses y fórmulas firmadas | Miguel | COM-01 |
| GOV-01 | S1 | Contrato canónico | Contradicciones eliminadas; D1–D7 consolidadas | Ingeniería + Miguel | COM-02 |
| ADR-01 | S1 | Identidad | Documento fuerte, revisión humana, fusión y corrección | Ingeniería | GOV-01 |
| ADR-02 | S1 | Postventa 1:N | Primera conversión, reinversión, idempotencia y anulación | Ingeniería + Gerencia | GOV-01 |
| ADR-03 | S1 | Privacidad y demos | `no_contactar`, clasificación demo y fronteras de PII | Ingeniería + Miguel | GOV-01 |
| UX-01 | S1–S2 | Diseño de flujo | Lista postventa, Ficha 360, reinversión y excepciones | Producto/Ingeniería + usuarios | GOV-01 |
| DATA-01 | S2 | Censo de diseño | Clases, excepciones, oráculos y deriva explicada | Ingeniería | ADR-01/03 |
| DB-01 | S2 | Modelo de datos | ERD, diccionario, constraints, índices y ledger | Ingeniería | ADR-01/02/03 |
| SEC-01 | S2 | Seguridad | Matriz RLS/grants/RPC por rol y pruebas negativas | Ingeniería + revisor | DB-01 |
| BF-01 | S2 | Backfill | Clases, mapa, pre/postflight, cuarentena y reversa | Ingeniería | DATA-01/DB-01 |
| TEST-01 | S2 | Plan de calidad | pgTAP, RLS, concurrencia, contratos RPC, E2E y mutantes | Ingeniería + revisor | SEC-01/BF-01 |
| G1-REV | Fin S2 | Freeze de diseño | Paquete F1 sin P0 y decisiones firmadas | Miguel + revisor | GOV–TEST |
| MIG-01 | S3 | Migración candidata | Archivo generado por CLI, hash y reconstrucción local | Ingeniería | G1 |
| DBTEST-01 | S3 | Pruebas de base | Invariantes, RLS, grants, índices y advisors | Ingeniería | MIG-01 |
| BFTEST-01 | S3–S4 | Ensayo de datos | Backfill doble, fallo parcial, postflight y reversa | Ingeniería + revisor | MIG-01 |
| PERF-01 | S4 | Rendimiento | Planes de consulta, locks cortos y ausencia de scans peligrosos | Ingeniería | DBTEST-01 |
| REL-01 | S4 | Runbook de corte | Backup, recenso, archivo/hash, pasos, abortos y rollback | Ingeniería + revisor | BFTEST/PERF |
| G2-REV | Fin S4 | Aprobación de candidato | Evidencia completa para una migración exacta | Miguel | REL-01 |
| CUT-01 | S5 | F1 producción | Caparazón, objetos verificados, backfill y conciliación | Ingeniería | G3 expreso |
| API-01 | S6 | Resolución canónica | Primitiva única para identificar/crear/reutilizar persona | Ingeniería | F1 aceptada |
| API-02 | S6–S7 | Puertas existentes | Crear/importar/tomar/editar/reabrir/convertir/contratar adaptadas | Ingeniería | API-01 |
| API-03 | S7 | Reinversión | RPC postventa idempotente, sin crear lead ni reconvertir | Ingeniería | ADR-02/API-01 |
| TEST-02 | S7 | Carreras y contratos | Concurrencia, service role, payload viejo/nuevo y E2E | Ingeniería + revisor | API-02/03 |
| MET-01 | S8 | Núcleo de conversión | Una acreditación por persona/mes según D4 | Ingeniería + Miguel | F2 estable |
| MET-02 | S8 | Núcleo de capital | Todos los hechos elegibles, sin doble conteo ni mezcla monetaria | Ingeniería | F2 estable |
| MET-03 | S8 | Tablero comercial | North Star, cohortes y oportunidades postventa | Ingeniería + Gerencia | MET-01/02 |
| READ-01 | S9 | Lista postventa | Búsqueda/filtros por persona, empresa, vencimiento y responsable | Ingeniería | F3 |
| READ-02 | S9 | Ficha 360 | Lead, perfiles, contratos, inversiones, actividades y atribución | Ingeniería | READ-01 |
| UI-01 | S10 | Acciones comerciales | Próxima acción, asignación, primera inversión y reinversión | Ingeniería + usuarios | READ-02 |
| QA-UI-01 | S10 | Calidad visual | Roles, escritorio/móvil, estados vacíos, error y accesibilidad | Ingeniería + usuarios | UI-01 |
| PILOT-01 | S11 | Piloto real | Casos acotados, soporte diario, incidentes y feedback | Gerencia + usuarios piloto | QA-UI-01 |
| ROLL-01 | S12 | Activación progresiva | Gerencia → piloto → fuerza comercial, con llave de reversa | Miguel + Ingeniería | Piloto aprobado |
| BEN-01 | D30/60/90 | Beneficios | Adopción, cobertura, reinversión y capital recurrente | Miguel + Gerencia | ROLL-01 |
| BEN-02 | Mes 6 | Meta | Comparación final contra baseline aprobado | Miguel | BEN-01 |

### 17.1 Entregables de las primeras dos semanas

Antes de construir la migración deben existir:

1. acta de meta comercial y fórmulas;
2. contrato canónico corregido;
3. ADR de identidad, postventa 1:N y privacidad/demos;
4. diagrama y diccionario del modelo;
5. matriz de permisos por rol;
6. especificación de backfill y cola manual;
7. catálogo completo de puertas de escritura y service role;
8. plan de pruebas y oráculos;
9. runbook preliminar de reversa;
10. prototipo de lista postventa, Ficha 360 y reinversión.

Si alguno falta, G1 no se aprueba.

## 18. Modelo operativo comercial que debe habilitar el producto

El software solo genera valor si cambia una rutina comercial concreta.

### 18.1 Segmentos de trabajo

| Segmento | Criterio | Acción comercial |
|---|---|---|
| Próximo a vencer | Inversión elegible con vencimiento ≤60 días | Preparar propuesta y acordar próxima acción |
| Ventana crítica | Vencimiento ≤30 días sin resultado | Prioridad alta y escalamiento al supervisor |
| Vencido sin reinvertir | Venció y no existe nueva inversión confirmada | Recuperación postventa; no crear otro lead |
| Inversionista activo con oportunidad | Tiene capital vigente y capacidad/interés documentado | Upsell o inversión adicional |
| Externo recurrente | Ya tiene cierre externo y vuelve a invertir | Registrar por puerta postventa idempotente |
| Sin responsable | Identidad válida sin dueño actual | Bandeja exclusiva de Gerencia para asignar |
| Identidad incierta | Documento ausente/conflictivo | Continuar lead o revisión humana; no fusionar |
| No contactar | Veto vigente en lead o identidad | Excluir de campañas y bloquear acción de contacto |
| Demo/prueba | Clasificación técnica vigente | Excluir de cartera real, métricas y campañas |

### 18.2 Playbooks comerciales

**Renovación:** aviso 60 días → contacto 30 días → propuesta → decisión → reinversión o cierre con motivo.

**Reinversión inmediata:** desde la Ficha 360 elegir “Nueva inversión”, seleccionar empresa/moneda, registrar transacción y atribución; nunca crear un lead ni convertir de nuevo.

**Recuperación:** si venció sin reinversión, crear una próxima acción con responsable, fecha y resultado; el motivo de pérdida se registra para análisis.

**Cross-company:** mostrar que la persona ya es inversionista, pero mantener separados empresa, contrato, moneda, capital y permisos.

### 18.3 Datos mínimos de una oportunidad postventa

- `inversionista_id`;
- inversión/contrato de origen;
- empresa y moneda objetivo;
- monto estimado sin mezclar monedas;
- tipo: renovación, reinversión, ampliación o recuperación;
- responsable actual;
- próxima acción y fecha;
- etapa y resultado;
- motivo de pérdida/no reinversión;
- fuente y atribución histórica inmutables;
- auditoría de creación, reasignación y cierre.

### 18.4 Cadencia semanal

1. Gerencia revisa identidades sin responsable y excepciones.
2. Supervisores revisan cobertura de vencimientos a 60/30/7 días.
3. Analistas trabajan su cola, registran resultado y dejan próxima acción.
4. Reinversiones se registran sobre la misma persona y el mismo lead histórico.
5. Viernes: revisión de cobertura, oportunidades vencidas, tasa de reinversión y capital recurrente por moneda/empresa.

## 19. Piloto, lanzamiento y adopción

### 19.1 Piloto controlado

Alcance recomendado:

- Gerencia, un supervisor y dos usuarios comerciales;
- 20–30 identidades reales con documento fuerte y sin ambigüedad;
- al menos un caso Avance, uno externo, uno multirrol, uno sin responsable y una reinversión;
- identidades ambiguas y transferencias fuera del piloto.

Escenarios que deben completarse de punta a punta:

1. encontrar a una persona desde su único lead;
2. revisar historia e inversiones por empresa/moneda;
3. asignar responsable y próxima acción;
4. registrar una reinversión sin crear lead;
5. confirmar que roles y datos bancarios siguen aislados;
6. marcar/propagar `no_contactar` según la regla aprobada;
7. demostrar que capital y conversión no se duplican.

El piloto dura al menos cinco días hábiles y no avanza con un incidente P0/P1 abierto.

### 19.2 Activación progresiva

| Ola | Usuarios | Capacidades |
|---|---|---|
| 1 | Gerencia | Lectura 360, excepciones y asignación |
| 2 | Supervisor + usuarios piloto | Cola postventa y reinversión en alcance acotado |
| 3 | Fuerza comercial | Lista/Ficha 360 y acciones aprobadas |
| 4 | Operación completa | Métricas y ritual semanal consolidados |

Cada ola conserva una llave para ocultar la nueva UI sin borrar datos. La reversa funcional desconecta consumidores; la reversa de datos nunca elimina hechos económicos.

### 19.3 Capacitación y soporte

- guía de una página: “primera inversión vs. reinversión”;
- guía de Gerencia para identidad sin responsable y excepciones;
- demostración con casos no sensibles;
- canal único de incidentes con severidad y dueño;
- soporte diario durante piloto y primeras 72 horas de cada ola;
- oficina de dudas semanal durante el primer mes.

## 20. Seguimiento de beneficios

| Momento | Revisión | Decisión posible |
|---|---|---|
| Semana 0 | Baseline y calidad de fórmulas | Ratificar o ajustar meta |
| Fin de F1 | Cobertura de identidad y paridad | Continuar o corregir datos |
| Fin de F2 | Cero puertas paralelas y reinversión sin lead | Activar métricas |
| Fin del piloto | Uso real, tiempos y errores | Lanzar, extender o detener |
| Día 30 | Adopción, cobertura y oportunidades vencidas | Refuerzo operativo |
| Día 60 | Tasa de reinversión temprana y capital recurrente | Ajustar playbooks |
| Día 90 | Tendencia comercial y calidad sostenida | Escalar o redefinir meta |
| Mes 6 | +15% capital recurrente / +10 pp reinversión o meta ratificada | Cierre de beneficio |

Si la plataforma funciona pero el beneficio no aparece, el programa no se declara comercialmente exitoso. Se revisan cobertura, disciplina de próxima acción, propuesta comercial, tiempos y segmentación antes de atribuir el problema a la identidad.

## 21. Riesgos y mitigaciones

| Riesgo | Señal temprana | Mitigación | Dueño |
|---|---|---|---|
| Fusión de personas distintas | Coincidencia débil usada como verdad | Solo documento fuerte/revisión; cuarentena y reversa | Ingeniería + Gerencia |
| Duplicado por concurrencia | Dos altas simultáneas | Constraint único, upsert/lock transaccional y prueba de carrera | Ingeniería |
| Fuga de permisos | Perfil multirrol ve datos ajenos | RLS/grants por rol, funciones privadas y pruebas negativas | Ingeniería + revisor |
| Historial remoto divergente | `db push` propone decenas de archivos | Prohibir `db push`; ejecutar solo archivo/hash aprobado | Ingeniería |
| “Success” falso de despliegue | Historial cambia pero objetos no | Contar objetos y validar firmas/constraints vivas | Ingeniería + revisor |
| Corte rompe frontend | RPC nueva devuelve forma no tolerada | Front compatible primero, fixtures de payload viejo/nuevo | Ingeniería |
| Capital o conversión inflados | Delta no explicado | Oráculos, demos durables y meses sellados inmutables | Ingeniería + Miguel |
| Baja adopción | Usuarios siguen creando leads o notas paralelas | UI guiada, capacitación, bloqueo servidor y revisión semanal | Gerencia |
| Oportunidades sin dueño | Identidades válidas quedan nulas | Bandeja de Gerencia y SLA de asignación | Gerencia |
| Backfill envejecido | Datos cambian entre censo y corte | Recenso inmediato y abortar ante deriva | Ingeniería |
| Service role elude reglas | Escritura sin auditoría/RLS | Inventario, primitiva canónica y prueba HTTP | Ingeniería |
| Alcance crece hacia transferencias | Solicitudes de “cambiar titular” | Mantener F6 separado y sin mutar hechos históricos | Miguel |
| Meta comercial arbitraria | No existe baseline comparable | Semana 0 obligatoria y ratificación de la meta | Miguel |

## 22. Orden inmediato de arranque

1. Miguel aprueba G0: usar este plan como guía, sin autorizar SQL.
2. Medir COM-01 en modo solo lectura y congelar el baseline.
3. Ratificar o ajustar la propuesta de +15% y +10 pp.
4. Ratificar D4: una conversión acreditada por persona/mes.
5. Ratificar D5: solo Gerencia administra identidades sin responsable.
6. Consolidar D1–D7 en el contrato y cerrar R1/R2/R6.
7. Elaborar ADR-01/02/03 y el prototipo UX.
8. Preparar modelo, seguridad, backfill, pruebas y reversa.
9. Hacer revisión independiente y solicitar G1.
10. Solo después generar la migración candidata y comenzar el ensayo F1.

La aprobación G0 puede expresarse así:

> “Apruebo usar el plan maestro versión 2 como guía. Esto no autoriza SQL ni producción. Ratifico la meta comercial y las decisiones D4/D5 indicadas en el plan.”

Si Miguel desea otra meta cuantitativa, se reemplaza en esa misma aprobación antes de iniciar COM-01/02.

## 23. Referencias técnicas actuales

- [Supabase Changelog](https://supabase.com/changelog): cambios vigentes revisados el 2026-09-01, incluida la exposición no automática de tablas nuevas.
- [Supabase — Securing your API](https://supabase.com/docs/guides/api/securing-your-api): separación entre grants y RLS.
- [Supabase — Database Functions](https://supabase.com/docs/guides/database/functions): funciones privilegiadas y `search_path` seguro.
- [Supabase — Database Migrations](https://supabase.com/docs/guides/deployment/database-migrations): migraciones reproducibles y prueba desde una base reconstruida.
- [Supabase — Database Testing](https://supabase.com/docs/guides/local-development/testing/overview): pgTAP y `supabase test db`.
- [Supabase — Managing Environments](https://supabase.com/docs/guides/deployment/managing-environments): separación y promoción controlada entre entornos; subordinada al contrato local que prohíbe `db push`.
- [[Handoff deploy CRM orígenes 2026-07-17]] y `CRM-Avance-Corp/supabase/migrations/MIGRACIONES.md`: mecanismo real de despliegue y divergencia del historial.

## 24. Definición de terminado del programa

### Terminado técnicamente

Una persona reconocida no puede duplicarse por ninguna puerta; su único lead conserva toda la historia; sus inversiones crecen 1:N; sus roles siguen aislados; capital y conversión son correctos; Gerencia controla excepciones; y toda la operación está probada, auditable y reversible.

### Terminado operacionalmente

Gerencia y la fuerza comercial usan la lista postventa, dejan responsable y próxima acción, registran reinversiones sin nuevos leads y sostienen el ritual semanal durante al menos 30 días.

### Terminado comercialmente

El tablero demuestra una mejora frente al baseline en capital recurrente y tasa de reinversión según la meta ratificada, sin sacrificar seguridad, exactitud monetaria ni experiencia del inversionista.

Hasta cumplir las tres capas, cada fase cerrada es progreso comprobable, no una declaración prematura de “programa terminado”.
