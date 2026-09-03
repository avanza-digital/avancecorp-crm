---
tags: [crm, inversionistas, multiempresa, identidad, contratos, cooperativas, roadmap]
fecha: 2026-09-01
estado: propuesta-lista-para-aprobacion-no-autoriza-sql
decision_origen: Miguel-confirmo-un-cliente-puede-invertir-en-varias-empresas
alcance_inicial: [avance-corp, coopac-qorilazo, coopac-prodelco]
horizonte_estimado: 12-semanas-mas-estabilizacion
---

# Plan por fases — un cliente, múltiples inversiones y múltiples empresas

> [!important] Objetivo confirmado por Miguel — 2026-09-01
> Un mismo cliente debe poder invertir una o varias veces en Avance Corp, COOPAC Qorilazo y COOPAC Prodelco, manteniendo una sola identidad, un solo lead y un solo historial comercial.

> [!warning] Autorización
> Este documento es un plan. No autoriza SQL, backfill, cambios de datos ni producción. Cada gate de ejecución requiere aprobación separada.

## 1. Qué se va a lograr

Al terminar la adaptación, el equipo podrá:

1. buscar una sola vez a la persona;
2. abrir una única ficha de inversionista;
3. ver todas sus inversiones, separadas por empresa y moneda;
4. registrar una inversión adicional en cualquiera de las empresas;
5. reutilizar siempre el mismo lead y el mismo historial;
6. mantener separado el contrato, capital, vencimiento y documentación de cada empresa;
7. saber quién atiende actualmente al inversionista y quién originó cada operación;
8. medir capital y cierres por empresa sin duplicar cifras;
9. conservar el Portal de Avance solo para quien corresponda, sin crear accesos falsos para cooperativas.

### Ejemplo final

Una persona llamada Juan podrá tener en la misma ficha:

| Empresa | Inversión | Moneda | Estado |
|---|---:|---|---|
| Avance Corp | 20,000 | PEN | Activa |
| COOPAC Qorilazo | 10,000 | PEN | Activa |
| COOPAC Prodelco | 8,000 | PEN | Vencida |
| Avance Corp | 5,000 | USD | Activa |

Juan seguirá siendo una sola persona. Cada fila conservará sus propios documentos, fechas, empresa, moneda, estado y atribución.

## 2. Qué no significa “unificar”

La adaptación no debe:

- sumar PEN y USD;
- mezclar el dinero administrado por Avance con el capital de cooperativas;
- convertir contratos de distintas empresas en un solo documento;
- dar Portal de Avance a un inversionista solo de cooperativa;
- compartir datos bancarios o permisos entre roles;
- borrar o reescribir la historia anterior;
- crear un lead nuevo cada vez que la persona vuelve a invertir;
- implementar transferencias de titularidad como un simple cambio de dueño.

## 3. Diagnóstico de lo que existe hoy

### 3.1 Capacidades que se reutilizan

| Capacidad actual | Estado | Cómo se aprovecha |
|---|---|---|
| Contratos Avance | Operativos | Siguen siendo el hecho legal/económico de Avance |
| Renovaciones y aumentos | Implementados | Continúan creando contratos y operaciones de cartera |
| Ficha 360 de cliente Avance | Publicada | Se adapta; no se reconstruye desde cero |
| Actividades y tareas postventa | Implementadas | Se vinculan a la identidad neutral |
| Cierres Qorilazo/Prodelco | Implementados | Se conservan como cierre inicial y evidencia histórica |
| Conversión externa | Implementada | Se integra a la resolución de identidad |
| Núcleo de capital | Implementado | Se amplía para leer identidad y empresa de forma canónica |
| Núcleo de conversión | Implementado | Se adapta a la regla transversal por persona |
| Roles y ámbitos CRM | Implementados | Se reutilizan con pruebas nuevas por identidad |

### 3.2 Bloqueos actuales para multiempresa

| Problema actual | Consecuencia |
|---|---|
| No existe `crm.inversionistas` | Lead, perfil y cierre compiten como “la persona” |
| El cliente Avance se identifica por `public.perfiles` | Quien solo invierte en cooperativa no aparece como cliente unificado |
| `crm.cierres_externos` tiene `UNIQUE(lead_id)` | Un lead no puede respaldar varias inversiones externas |
| El cierre externo combina conversión e inversión | No existe una puerta limpia para la segunda inversión |
| El plan antiguo decía crear otro lead si luego invertía en Avance | Contradice directamente el nuevo objetivo |
| La Ficha 360 está anclada a perfil cliente | No puede mostrar una persona sin Portal o multirrol |
| Qorilazo y Prodelco están codificadas como opciones fijas | Agregar otra empresa exigiría tocar varias capas |
| Contratos Avance y cierres externos no comparten ancla de persona | La cartera no puede agruparlos con certeza |
| El capital externo puede no tener `cliente_id` | Las métricas no pueden agrupar bien por inversionista |
| Algunas lecturas asumen que un cliente puede volver con otro lead | Debe eliminarse esa suposición |

### 3.3 Regla anterior que queda reemplazada

La frase histórica “si el mismo prospecto luego invierte en Avance, se crea un lead nuevo” deja de ser válida.

La nueva regla es:

> **Si la persona ya existe, se reutilizan su identidad y su único lead. La nueva inversión se agrega a la empresa seleccionada.**

## 4. Modelo objetivo

```text
Inversionista — una persona neutral
├── 0..1 lead total
├── 0..N perfiles/Auth según roles reales
├── 0..N actividades y tareas comerciales
└── 0..N inversiones
    ├── Empresa: Avance Corp
    │   └── contrato, cronograma, pagos y Portal cuando corresponda
    ├── Empresa: COOPAC Qorilazo
    │   └── operación, depósito, referencia y vencimiento
    └── Empresa: COOPAC Prodelco
        └── operación, depósito, referencia y vencimiento
```

### 4.1 Identidad

- `crm.inversionistas`: una fila por persona confirmada;
- `crm.inversionista_identificadores`: DNI, CE, pasaporte y futuras fuentes verificadas;
- `crm.inversionista_perfiles`: puente opcional hacia perfiles/Auth existentes;
- `crm.leads.inversionista_id`: enlace al único lead total;
- responsable comercial actual y ledger histórico de asignaciones;
- `no_contactar` global cuando la identidad ya es fuerte.

Una persona sin documento puede continuar como lead, pero no se fusiona automáticamente por nombre, teléfono o correo.

### 4.2 Empresas

Crear un catálogo ampliable de empresas de inversión, con al menos:

- Avance Corp;
- COOPAC Qorilazo;
- COOPAC Prodelco.

Cada empresa define:

- nombre legal y nombre visible;
- activa/inactiva;
- monedas permitidas;
- si crea contrato Avance;
- si requiere Portal/Auth;
- si exige número de transacción;
- reglas de anulación y documentación.

Así, una cuarta empresa no requerirá inventar otro flujo paralelo completo.

### 4.3 Inversiones

Recomendación arquitectónica:

- `public.contratos` continúa como fuente de verdad de inversiones Avance;
- crear una entidad 1:N de inversiones externas para Qorilazo/Prodelco;
- `crm.cierres_externos` se conserva como evento de la primera conversión externa;
- la primera conversión externa crea, en una transacción, el cierre inicial y su inversión externa;
- las siguientes inversiones externas crean solo una nueva inversión, sin volver a convertir ni crear lead;
- cada inversión tiene `inversionista_id`, `empresa_id`, moneda, monto, fecha, vencimiento, estado, transacción, responsable/atribución y auditoría;
- una vista/núcleo canónico reúne contratos Avance e inversiones externas sin duplicar dinero.

Esto separa correctamente:

- **conversión:** el momento en que la relación comercial se ganó;
- **inversión:** cada hecho económico individual;
- **reinversión:** una nueva inversión de una persona ya existente;
- **renovación:** continuidad contractual según la regla de la empresa.

### 4.4 Acceso y Portal

Supuesto recomendado para este plan:

- invertir en Qorilazo/Prodelco no crea cuenta Portal;
- invertir en Avance sí puede crear/vincular el perfil cliente y Auth;
- una persona que empezó en cooperativa y luego invierte en Avance reutiliza su identidad y lead; solo entonces se crea o vincula su acceso Avance;
- tener otro rol —analista, supervisor, gerencia— no concede permisos de cliente ni viceversa.

## 5. Reglas comerciales asumidas por el plan

Estas reglas permiten diseñar sin dejar ambigüedades. Miguel puede cambiarlas antes de cerrar F0.

| Regla | Recomendación inicial |
|---|---|
| Empresas iniciales | Avance, Qorilazo y Prodelco |
| Leads | Uno total por persona confirmada |
| Inversiones | Ilimitadas por persona y empresa |
| Portal | Solo se crea por una inversión Avance que lo requiera |
| Cooperativas | Se mantiene PEN mientras no exista una decisión distinta |
| Responsable actual | Uno para la relación completa del grupo |
| Atribución | Cada inversión congela quién la cerró; una reasignación futura no la mueve |
| Conversión mensual | Máximo una acreditación por persona/mes; todas las inversiones sí cuentan como capital |
| Reinversión | Nunca crea lead ni vuelve a ejecutar la primera conversión |
| Anulación | No borra la fila; deja de contar y conserva autor/motivo |
| Datos demo | Se excluyen por clasificación técnica, no por nombres |
| Transferencias | Fuera del alcance inicial; requieren ledger legal propio |
| Fecha comercial en cooperativas | Propia por inversión: anterior o igual al registro, nunca futura; Capital y conversión la usan como en Avance; en mes sellado entra como ajuste posterior (decisión 9, **confirmada por Miguel el 02/09/2026**) |

### Decisiones que F0 debe confirmar

> [!success] Las 7 CONFIRMADAS por Miguel el 03/09/2026 con los valores recomendados (la 7 lo estaba desde el 02/09).

1. Responsable comercial: **único para las tres empresas** (la comisión de cada inversión igual queda para quien la cerró). ✅
2. Cooperativas: **solo PEN** por ahora; Avance sigue en PEN y USD. ✅
3. Documentos: **Avance, contrato PDF como hoy; cooperativas, comprobante de depósito, número de referencia y evidencia.** ✅
4. Registran: **vendedor en sus clientes, supervisor en su equipo, Gerencia en todos; Directorio solo lee.** ✅
5. Portal: **solo Avance**; no se crea acceso al Portal por invertir en cooperativa. ✅
6. Comisión: **cada inversión liquida según la regla de su empresa**; la conversión se acredita una sola vez en la vida (en la primera inversión). ✅
7. si las inversiones en cooperativa llevan una fecha comercial propia, que puede ser anterior al registro pero nunca futura; Capital y conversión la usan igual que en Avance. Si cae en un mes ya sellado, entra como ajuste posterior, sin reescribir el mes (añadida el 02/09/2026 como decisión 9 de la lista de preguntas a Miguel; **CONFIRMADA por Miguel el 02/09/2026**).

## 6. Plan por fases

Horizonte de referencia: **12 semanas**, suponiendo decisiones rápidas, una persona de ingeniería dedicada, revisión independiente y usuarios piloto disponibles. Los gates no se eliminan para recuperar retrasos.

### F0 — contrato comercial y mapa completo

**Duración estimada:** semana 0.

**Qué se hace:**

- aprobar las reglas de la sección 5;
- definir formalmente “cliente”, “inversionista”, “empresa”, “inversión”, “conversión”, “reinversión” y “renovación”;
- declarar reemplazadas las reglas antiguas que crean otro lead;
- inventariar todas las escrituras: lead, importación, conversión, perfil/Auth, contrato, cierre externo, renovación, aumento y corrección;
- levantar baseline de identidades, contratos, cierres, operaciones, demos y excepciones;
- fijar cómo se medirán capital, producción, comisión y conversión por empresa.

**Resultado visible:** todavía no cambia el CRM; queda acordado exactamente qué se construirá.

**Entregables:** contrato canónico, ADR multiempresa, catálogo de puertas, censo reproducible y matriz de decisiones.

**Gate F0:** ninguna contradicción comercial o técnica abierta.

### F1 — cimientos de identidad y empresas

**Duración estimada:** semanas 1–2.

**Qué se construye:**

- identidad neutral e identificadores fuertes;
- catálogo de empresas;
- enlaces opcionales desde leads, perfiles, contratos y cierres;
- puente 0:N de perfiles/Auth;
- responsable actual y ledger histórico;
- clasificación durable de demos;
- RLS, grants y RPC deny-by-default;
- índices de foreign keys, documento, empresa y columnas de ámbito.

Todo entra de manera aditiva y nullable. No se elimina ninguna columna ni se cambia todavía el comportamiento de producción.

**Resultado visible:** ninguno para usuarios; el sistema queda listo para reconocer una persona sin romper lo existente.

**Pruebas:** unicidad por documento, multirrol sin permisos heredados, empresa válida, responsable nulo solo visible a Gerencia y exposición Data API controlada.

**Gate F1:** esquema, seguridad, reconstrucción local y reversa aprobados.

### F2 — vincular los datos existentes

**Duración estimada:** semana 3.

**Qué se migra:**

- perfiles cliente Avance con documento fuerte;
- contratos y operaciones de cartera hacia la identidad correspondiente;
- cierres externos hacia identidad e inversión externa inicial;
- leads convertidos hacia su persona;
- perfiles multirrol mediante el puente, sin mezclar permisos;
- responsables actuales conocidos;
- exclusiones demo y cola manual.

**Clases:**

| Clase | Tratamiento |
|---|---|
| Documento fuerte único | Vinculación automática |
| Sin documento | Permanece operando sin fusión automática |
| Documento conflictivo | Cola manual; no se elige por aproximación |
| Coincidencia solo por nombre/teléfono/correo | Señal, nunca fusión automática |
| Multirrol legítimo | Una identidad, varios perfiles |
| Demo/prueba | Excluido del universo real y métricas |

**Resultado visible:** todavía se conserva la UI anterior, pero la mayoría de clientes reales ya tiene una identidad común detrás.

**Pruebas:** backfill idempotente, cero fusiones ambiguas, paridad de contratos/capital y mapa completo de reversa.

**Gate F2:** 100% de filas procesadas como automática, manual, sin identidad o demo; ninguna queda sin clasificación.

### F3 — una sola puerta para reconocer a la persona

**Duración estimada:** semanas 4–5.

**Qué se adapta:**

- alta manual de leads;
- importaciones y rutas service role;
- toma y reapertura;
- edición de documento;
- conversión Avance;
- conversión externa;
- creación de perfil/Auth;
- creación de contrato;
- renovaciones y aumentos;
- correcciones y fusiones autorizadas.

Todas deben usar la misma primitiva transaccional:

1. normalizar documento;
2. localizar/bloquear identidad;
3. crear o reutilizar identidad;
4. crear o reutilizar el único lead;
5. validar empresa, permisos y responsable;
6. escribir el hecho solicitado;
7. registrar auditoría e idempotencia.

**Resultado visible:** el sistema comienza a impedir que una misma persona sea creada nuevamente.

**Pruebas:** dos solicitudes simultáneas con el mismo documento producen una identidad; los payloads repetidos no duplican inversión; ninguna ruta service role evita la regla.

**Gate F3:** no existe una puerta paralela que pueda crear persona o lead por fuera del núcleo.

### F4 — motor de inversiones multiempresa

**Duración estimada:** semanas 6–7.

**Qué se construye:**

- entidad 1:N para inversiones externas;
- migración de cierres externos existentes como primera inversión;
- puerta “registrar nueva inversión” para una persona existente;
- selección de empresa;
- rama Avance: contrato/cronograma/Portal según corresponda;
- rama Qorilazo/Prodelco: monto, depósito, referencia, vencimiento y evidencia;
- idempotencia por número de transacción;
- anulaciones sin borrado;
- preservación de `UNIQUE(lead_id)` en el cierre inicial mientras la nueva puerta se estabiliza.

**Resultado visible:** por primera vez, un cliente existente puede invertir en otra empresa sin crear otro lead.

**Casos de aceptación:**

1. cliente Avance registra inversión Qorilazo;
2. inversionista Qorilazo registra inversión Prodelco;
3. inversionista Qorilazo pasa a Avance y recibe su acceso Avance sin duplicarse;
4. cliente registra segunda inversión en la misma empresa;
5. misma transacción repetida se rechaza o devuelve el resultado previo;
6. anulación no elimina la historia ni reabre el lead.

**Gate F4:** todos los casos anteriores funcionan bajo concurrencia y con capital exacto.

### F5 — cartera y Ficha 360 multiempresa

**Duración estimada:** semanas 8–9.

**Qué se adapta:**

- “Mi cartera” pasa de clientes Avance + sección externa separada a una lista de inversionistas;
- búsqueda por persona, documento, contacto y empresa;
- chips Avance/Qorilazo/Prodelco;
- Ficha 360 neutral, reutilizando la ficha ya publicada;
- inversiones agrupadas por empresa y moneda;
- estado, vencimiento y documentos por inversión;
- botón “Nueva inversión” con selección de empresa;
- actividades, tareas y responsable de la relación completa;
- cuentas bancarias solo en la rama Avance y para roles autorizados.

**Resultado visible:** el usuario ve “un cliente, varias empresas” en una sola pantalla.

**Pruebas:** vendedor, supervisor, Gerencia y Directorio; escritorio/móvil; teclado/foco; carga parcial; cambio de permisos mientras la ficha está abierta; cero desborde visual.

**Gate F5:** los cuatro roles ven exactamente lo permitido y pueden completar sus recorridos sin datos duplicados.

### F6 — postventa, vencimientos y próxima inversión

**Duración estimada:** semana 10.

**Qué se adapta:**

- próxima acción a nivel de inversionista;
- alertas de vencimiento por empresa;
- renovación Avance desde contrato;
- reinversión externa desde inversión anterior;
- aumento o nueva inversión sin volver al pipeline;
- bandeja de inversionistas sin responsable;
- `no_contactar` aplicado a toda la persona;
- historial único de gestiones, conservando separados captación y postventa.

**Resultado visible:** el asesor puede continuar la relación y registrar la siguiente inversión desde la misma ficha.

**Gate F6:** toda inversión próxima a vencer puede terminar en una gestión, próxima acción y nueva inversión trazable.

### F7 — métricas y reportes por empresa

**Duración estimada:** semana 10–11.

**Qué se adapta:**

- capital por empresa y moneda;
- número de inversiones por empresa;
- inversionistas con una, dos o tres empresas;
- primera inversión vs. reinversión;
- conversión transversal por persona/mes;
- atribución y comisión por operación;
- vencimientos y oportunidades de cross-selling;
- demos/anulaciones excluidas correctamente;
- meses sellados sin reescritura.

**Resultado visible:** Gerencia sabe cuánto se produjo en cada empresa y cuántos clientes invierten en más de una.

**Gate F7:** capital y conversión cuadran antes/después; PEN/USD y empresas permanecen separados; ninguna inversión se cuenta dos veces.

### F8 — piloto y activación progresiva

**Duración estimada:** semanas 11–12.

**Piloto:**

- Gerencia, un supervisor y dos usuarios comerciales;
- casos Avance→Qorilazo, Qorilazo→Avance, Qorilazo→Prodelco y segunda inversión en la misma empresa;
- al menos un caso multirrol y uno sin responsable;
- cinco días hábiles sin P0/P1 abierto.

**Olas:**

1. lectura 360 para Gerencia;
2. lectura y nuevas inversiones para usuarios piloto;
3. supervisores y fuerza comercial;
4. métricas y ritual operativo completo.

**Resultado visible:** la operación multiempresa queda disponible para todo el equipo autorizado.

**Gate F8:** aceptación de Miguel, evidencia funcional/visual, soporte preparado y reversa funcional probada.

### F9 — estabilización y beneficio

**Duración:** días 30/60/90 después del lanzamiento.

- corregir fricciones del flujo;
- medir adopción y operaciones multiempresa;
- revisar oportunidades no atendidas;
- ajustar permisos, filtros y reportes sin cambiar reglas cerradas;
- decidir si se incorporan nuevas empresas;
- decidir por separado transferencias de titularidad.

## 7. Recorridos finales obligatorios

### A. Cliente Avance invierte en Qorilazo

1. buscar cliente;
2. abrir Ficha 360;
3. elegir “Nueva inversión”;
4. seleccionar Qorilazo;
5. registrar depósito y condiciones;
6. agregar inversión a la misma persona;
7. mantener Portal y contratos Avance intactos.

### B. Inversionista Qorilazo invierte en Avance

1. encontrar identidad existente por documento;
2. reutilizar el único lead;
3. crear/vincular perfil cliente y Auth Avance una sola vez;
4. crear contrato Avance;
5. mostrar ambas empresas en la misma ficha.

### C. Cliente invierte nuevamente en la misma empresa

- Avance: nuevo contrato, renovación o aumento según corresponda;
- cooperativa: nueva inversión externa con nueva transacción;
- nunca se crea otro lead.

### D. Persona todavía sin documento

- el lead continúa;
- no se fusiona por nombre/teléfono/correo;
- para registrar inversión se verifica documento o interviene una revisión autorizada;
- se conserva toda la historia existente.

## 8. Seguridad y permisos

| Rol | Alcance multiempresa recomendado |
|---|---|
| Vendedor | Inversionistas bajo su responsabilidad actual; registra operaciones permitidas |
| Supervisor | Inversionistas de su equipo; reasignación según reglas actuales |
| Gerencia | Toda la cartera, excepciones, anulaciones y asignaciones |
| Directorio | Lectura global sin bancos ni acciones de escritura |
| Cliente Portal | Solo información Avance autorizada; no hereda acceso por identidad neutral |
| Service role | Solo puertas inventariadas, auditadas e idempotentes |

Controles obligatorios:

- RLS y grants mínimos antes de exponer cualquier objeto;
- vistas `security_invoker` o RPC con autorización explícita;
- `SECURITY DEFINER` solo en schema no expuesto, `search_path` fijo y `EXECUTE` revocado a `PUBLIC`;
- políticas UPDATE con lectura y validación del estado nuevo;
- índices en columnas usadas por RLS y foreign keys;
- ninguna identidad multirrol propaga permisos;
- información bancaria separada del agregado neutral.

## 9. Pruebas que deciden el GO

### Identidad y concurrencia

- mismo documento simultáneo → una identidad;
- misma persona por dos puertas → un lead;
- coincidencia débil → no fusión;
- multirrol → una persona, permisos separados.

### Inversiones

- una persona con tres empresas;
- varias inversiones en una empresa;
- misma transacción repetida → cero duplicado;
- anulación → cero capital, historia intacta;
- primera inversión vs. reinversión con comportamientos distintos.

### Dinero y métricas

- capital por empresa y moneda igual a las fuentes;
- ninguna fila contada como cierre e inversión dos veces;
- demos fuera;
- periodos sellados iguales;
- conversión transversal cumple la regla aprobada.

### Permisos

- cada rol probado con casos positivos y negativos;
- cliente Portal no ve otra empresa por accidente;
- Directorio no ve bancos;
- vendedor anterior no conserva acceso por atribución histórica;
- service role no evita el núcleo canónico.

### Producto

- escritorio y móvil;
- teclado, foco y lector de pantalla;
- estados cargando/vacío/error/reintento;
- permisos que cambian con ficha abierta;
- contratos y payloads viejos/nuevos durante despliegue escalonado.

## 10. Gates y despliegue

| Gate | Autoriza | Requisito |
|---|---|---|
| G0 | Congelar reglas y diseñar | Decisiones F0 firmadas |
| G1 | Construir migración candidata | Modelo, seguridad, backfill y pruebas sin P0 |
| G2 | Ensayar candidato | Archivo/hash exactos y entorno aislado |
| G3 | Ejecutar F1/F2 | Recenso, backup, reversa y autorización expresa de Miguel |
| G4 | Activar nuevas escrituras | F1/F2 aceptadas y pruebas de carrera verdes |
| G5 | Piloto UI | F4/F5/F6 reconciliadas y seguras |
| G6 | Lanzamiento general | Piloto aceptado, soporte y reversa funcional |

Reglas propias del repositorio:

- no usar `supabase db push`;
- no usar `migration repair` para ocultar la divergencia local/remota;
- ejecutar solo el archivo aprobado con hash;
- contar objetos reales después del despliegue; “success” no es evidencia;
- desplegar primero el consumidor tolerante cuando cambie un payload;
- conservar una llave para ocultar la nueva UI sin borrar datos.

## 11. Indicadores de éxito

### Técnicos y operativos

- 100% de nuevas inversiones multiempresa reutilizan identidad;
- 0 leads nuevos para una persona existente;
- 0 documentos fuertes duplicados;
- 0 inversiones duplicadas por transacción;
- 0 diferencia de capital por empresa/moneda;
- 0 propagación de permisos;
- 100% de puertas de escritura inventariadas y adaptadas.

### Comerciales

- número de inversionistas con dos o más empresas;
- capital captado por empresa y moneda;
- nuevas inversiones de clientes existentes;
- tasa de paso de una empresa a otra;
- vencimientos con próxima acción;
- tiempo desde oportunidad hasta nueva inversión;
- reinversiones que antes habrían requerido un lead nuevo: objetivo 0.

No se fija todavía un porcentaje artificial de crecimiento. Primero se habilita la capacidad multiempresa y se calcula el baseline; luego Miguel define la meta comercial sobre datos reales.

## 12. Fuera del alcance inicial

- transferencias legales de titularidad;
- consolidar contablemente empresas distintas;
- convertir el Portal Avance en portal de todas las empresas;
- migrar Qorilazo/Prodelco a contratos completos de Avance;
- mezclar monedas;
- eliminar físicamente demos o históricos;
- incorporar nuevas empresas antes de estabilizar las tres iniciales.

## 13. Orden inmediato

1. Miguel aprueba este objetivo y el plan F0–F9 como guía, sin autorizar SQL.
2. Confirmar las seis decisiones de F0.
3. Corregir el contrato de identidad y declarar reemplazada la regla de “nuevo lead”.
4. Diseñar identidad, empresa e inversión externa 1:N.
5. Preparar censo, backfill, seguridad, pruebas y reversa.
6. Revisar el paquete de manera independiente.
7. Solicitar G1 antes de crear la migración candidata.

## 14. Fuentes relacionadas

- [[Cierres en cooperativas Qorilazo y Prodelco - plan]];
- [[Gestión comercial de clientes - renovaciones y upgrades]];
- [[Ficha comercial 360 de clientes - plan]];
- [[Contrato arquitectonico consolidado - identidad unificada de inversionistas (F0 2026-08-31)]];
- [[Censo F0 de identidad unificada - resultado de solo lectura (2026-08-31)]];
- [[Cola F0.5 de identidad unificada - resultado de solo lectura (2026-08-31)]];
- [[Auditoria integral del plan de identidad unificada (2026-08-31)]];
- [[Plan maestro de ejecucion - identidad unificada de inversionistas (2026-08-31)]];
- [[Conversion unica en todo el CRM - plan de migraciones 2]].

## 15. Definición de terminado

La adaptación estará terminada cuando un usuario pueda tomar una persona ya existente, registrar inversiones en Avance, Qorilazo o Prodelco desde la misma ficha, repetir la operación cuantas veces corresponda, ver cada inversión separada y obtener métricas correctas, sin crear otro lead, sin duplicar identidad, sin mezclar permisos y sin reescribir la historia.
