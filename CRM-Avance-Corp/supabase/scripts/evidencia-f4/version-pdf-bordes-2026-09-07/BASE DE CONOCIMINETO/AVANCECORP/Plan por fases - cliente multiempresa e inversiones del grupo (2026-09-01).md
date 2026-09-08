---
tags: [crm, inversionistas, multiempresa, identidad, contratos, cooperativas, roadmap]
fecha: 2026-09-01
estado: plan-vigente-f3-encendida-f4-en-construccion-local-G4-abierto
actualizado: 2026-09-07
decision_origen: Miguel-confirmo-un-cliente-puede-invertir-en-varias-empresas
alcance_inicial: [avance-corp, coopac-qorilazo, coopac-prodelco]
avance: por-evidencia-con-ciclo-mensual-obligatorio-en-G8
---

# Plan por fases — un cliente, múltiples inversiones y múltiples empresas

> [!important] Objetivo confirmado por Miguel — 2026-09-01
> Un mismo cliente debe poder invertir una o varias veces en Avance Corp, COOPAC Qorilazo y COOPAC Prodelco, manteniendo una sola identidad, un solo lead y un solo historial comercial.

> [!warning] Autorización
> La construcción y el ensayo local de F4 con datos sintéticos ya fueron autorizados por Miguel y están en curso. Este documento registra ese avance; no aprueba G4 ni autoriza backfill productivo, dinero real o activación en producción. Las ejecuciones posteriores conservan los gates y autorizaciones del plan.
>
> **Corrección documental del 07/09/2026:** se conservan las fuentes de Capital, el trabajo ya realizado en F2 y las reglas de conversión existentes, incluidos renovaciones y upgrades elegibles. Se alinean anulación, ensayo, piloto y gates con el maestro. Autoridad y evidencia: [[F4 multiempresa - reglas vigentes y punto de partida (2026-09-07)]].

## Estado vigente — evidencia al 07/09/2026, 22:09 Lima

**Estamos en F4.** El motor de nuevas inversiones ya tiene construcción y pruebas satisfactorias en el banco local. **G4 sigue abierto:** todavía falta completar sus requisitos de aceptación. La experiencia unificada desde la ficha corresponde a F5 y sigue pendiente.

| Fase | Estado actual | Resultado o trabajo pendiente |
|---|---|---|
| F0 / G0 — reglas y base del plan | Aprobadas y firmadas | Reglas comerciales y arquitectura acordadas |
| F1 — cimientos | Publicada | Identidad neutral, empresas y relaciones |
| F2 — vinculación histórica inicial | Publicada | Conservar lo resuelto; F4 debe ensayar y tratar solo faltantes comprobados |
| F3 — reconocimiento único | Publicada y encendida | Identidad unificada activa desde el 07/09 a las 10:09 Lima |
| **F4 — motor de inversiones** | **En construcción local; G4 abierto** | Completar documentos, históricos, titularidad, permisos, paridad financiera y recuperación/reversa |
| F5 — cartera y Ficha 360 | Pendiente | Integrar la ficha única y «Nueva inversión»; aceptar recorridos y permisos con datos sintéticos |
| F6 — postventa | Pendiente | Vencimientos, próxima acción, renovación y reinversión desde la misma persona |
| F7 — métricas | Pendiente | Conciliar Capital, conversión, producción y comisión; firmar G6 |
| F8 — piloto económico | Pendiente | Cumplir los volúmenes, recorridos, conciliaciones y firmas de G7 |
| F9 — activación y observación | Pendiente | Despliegue progresivo, ciclo operativo mensual completo y retirada de rutas antiguas en G8 |

El bloque PDF pasó **10 grupos adicionales con ocho contratos**: peticiones sin respuesta acotadas a 20 segundos, subida tardía tras la reserva real de 120 segundos, versiones incompatibles recibidas y dos antecedentes que conservan su régimen sin documento nuevo. Después pasó la regresión de **12 grupos con otros 10 contratos** por el servicio Deno real. Hay **42 pruebas** del handler/adaptador satisfactorias y revisión visual previa de 14 páginas de dos contratos ficticios. La auditoría de Claude también permitió corregir un reintento de inversiones ya confirmadas tras «No insistir». **El contenido del PDF permanece intacto. Cualquier incorporación relativa a cotitulares requiere mostrar texto y ubicación y recibir aprobación de Miguel antes de editar.**

El siguiente paso es completar la vinculación histórica, titularidad y permisos. Los bordes técnicos PDF ensayados ya pasaron; queda integrar toda la candidata sobre una reconstrucción limpia. F4 todavía no cumple todos los requisitos de cierre.

Detalle actual: [[F4 multiempresa - PDF real, recuperacion y auditoria (2026-09-07)]], [[F4 multiempresa - construccion y pruebas parciales (2026-09-07)]] y [[F4 multiempresa - objetivo de cierre y banco aislado (2026-09-07)]]. Evidencia trazable: [checkpoint de F4](../../CRM-Avance-Corp/supabase/scripts/evidencia-f4/2026-09-07-continuacion-pdf-bordes.json) y [matriz de aceptación](../../CRM-Avance-Corp/supabase/scripts/f4/ESTADO-ACEPTACION.md).

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

## 3. Diagnóstico inicial del 01/09/2026 (antecedente)

Las tablas de esta sección describen el punto de partida del plan, no el estado actual del servidor. F1–F3 ya fueron publicadas. El recenso del 07/09 está en [[F4 multiempresa - reglas vigentes y punto de partida (2026-09-07)]].

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

### 3.2 Bloqueos del diagnóstico inicial para multiempresa

| Problema al 01/09/2026 | Consecuencia |
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

> **Si la persona ya existe, se reutilizan su identidad y su lead canónico. Se conservan sus antecedentes y se agrega la inversión a la empresa seleccionada.**

## 4. Modelo objetivo

```text
Inversionista — una persona neutral
├── 0..1 lead canónico operativo + antecedentes históricos conservados
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

- `public.contratos` conserva la fuente económica de Avance.
- `crm.cierres_externos` conserva la fuente económica de Qorilazo y Prodelco; cada inversión externa confirmada tiene su propio hecho económico.
- `crm.inversiones`, existente desde F1, relaciona persona, empresa y fuente. No guarda una segunda verdad del dinero ni sustituye el cálculo de Capital.
- El esquema instalado enlaza la fuente mediante `contrato_id` o `cierre_externo_id`, exactamente una por inversión, con unicidad de cada fuente. La titularidad se conserva en `crm.inversion_titulares` con sus controles de coherencia.
- Las nuevas inversiones reutilizan la identidad y el lead canónico. Se evoluciona la restricción de un cierre por lead con pruebas sobre sus consumidores; no se elimina sin adaptar las rutas que suponen esa unicidad.
- La primera conversión del lead y los aportes de renovaciones/upgrades elegibles son hechos distintos. La conversión comercial continúa gobernada por el núcleo existente.
- F2 conserva la vinculación histórica ya realizada. El recenso previo a F4 identifica solo los faltantes que necesiten el proceso canónico de vinculación, sin volver a migrar cierres resueltos.

Cada inversión conserva empresa, fuente, fechas, estado, transacción, responsables, titularidad, evidencia y auditoría. Monto y moneda se leen de la fuente económica. Capital se obtiene del núcleo existente, sin sumas ni deduplicadores paralelos en las pantallas.

### 4.4 Acceso y Portal

Supuesto recomendado para este plan:

- invertir en Qorilazo/Prodelco no crea cuenta Portal;
- invertir en Avance sí puede crear/vincular el perfil cliente y Auth;
- una persona que empezó en cooperativa y luego invierte en Avance reutiliza su identidad y lead; solo entonces se crea o vincula su acceso Avance;
- tener otro rol —analista, supervisor, gerencia— no concede permisos de cliente ni viceversa.

## 5. Reglas comerciales vigentes

Reglas confirmadas en F0, con la aclaración de Miguel del 07/09: la conversión conserva la elegibilidad existente de renovaciones y upgrades. Ver [[Nucleo de conversion - diagnostico de llegadas y asignaciones 2026-09-04]].

| Regla | Decisión vigente |
|---|---|
| Empresas iniciales | Avance, Qorilazo y Prodelco |
| Leads | Uno canónico operativo por persona confirmada; antecedentes históricos conservados |
| Inversiones | Ilimitadas por persona y empresa |
| Portal | Solo se crea por una inversión Avance que lo requiera |
| Cooperativas | Se mantiene PEN mientras no exista una decisión distinta |
| Responsable actual | Uno para la relación completa del grupo |
| Atribución | Se conserva quién registró/cerró cada operación; la atribución efectiva sigue la política vigente de cada empresa y de las cadenas de upgrade. Meses sellados y comisiones pagadas no se reescriben |
| Conversión comercial | La decide el núcleo existente. Upgrade elegible = 1; renovación elegible = peso de Referido del período; máximo una operación de cartera elegible por cliente/mes. No se impone una prohibición vitalicia ni se convierte cada inversión automáticamente |
| Reinversión | Nunca crea lead ni vuelve a ejecutar la primera conversión |
| Anulación comercial | Conserva fila, autor y motivo; reduce conversión según ATR-4 y conserva Capital, producción y AUM |
| Datos demo | Se excluyen por clasificación técnica, no por nombres |
| Transferencias | Fuera del alcance inicial; requieren ledger legal propio |
| Fecha comercial en cooperativas | Propia por inversión: anterior o igual al registro, nunca futura; Capital y conversión la usan como en Avance; en mes sellado entra como ajuste posterior (decisión 9, **confirmada por Miguel el 02/09/2026**) |

### Decisiones confirmadas de F0 y precisión del 07/09

> [!success] Las 7 CONFIRMADAS por Miguel el 03/09/2026 con los valores recomendados (la 7 lo estaba desde el 02/09).

1. Responsable comercial: **único para las tres empresas** (la comisión de cada inversión igual queda para quien la cerró). ✅
2. Cooperativas: **solo PEN** por ahora; Avance sigue en PEN y USD. ✅
3. Documentos: **Avance, contrato PDF como hoy; cooperativas, comprobante de depósito, número de referencia y evidencia.** ✅
4. Registran: **vendedor en sus clientes, supervisor en su equipo, Gerencia en todos; Directorio solo lee.** ✅
5. Portal: **solo Avance**; no se crea acceso al Portal por invertir en cooperativa. ✅
6. Comisión: **cada inversión liquida según la regla de su empresa**. **Precisión de Miguel del 07/09:** la conversión depende de la elegibilidad definida en el proyecto, incluidos renovaciones y upgrades; se retira la formulación general de conversión vitalicia. ✅
7. si las inversiones en cooperativa llevan una fecha comercial propia, que puede ser anterior al registro pero nunca futura; Capital y conversión la usan igual que en Avance. Si cae en un mes ya sellado, entra como ajuste posterior, sin reescribir el mes (añadida el 02/09/2026 como decisión 9 de la lista de preguntas a Miguel; **CONFIRMADA por Miguel el 02/09/2026**).

> [!info] Estado real al 07/09/2026, 21:26 Lima — F4 en curso
> **F0/G0 están firmadas y F1, F2 y F3 están en producción**; la identidad unificada se encendió a las **10:09 Lima**.
> **La puerta técnica de nueva inversión ya existe en la candidata local de F4 y tiene pruebas parciales satisfactorias.** No está desplegada: `inversiones_escritura` (F4) y `ficha_360_neutral` (F5) siguen apagados en producción. El recorrido unificado desde la ficha se integrará en F5.
> En el recenso del encendido se observaron **930 de 937 leads vivos sin documento**; es una observación de esa hora, no un recenso nuevo. La modalidad de captura del documento en la web mejora la cobertura al entrar y sigue pendiente de decisión comercial; no bloquea construir y probar F4 con personas verificadas.
> Punto de retoma: [[RETOMAR-62 - identidad unificada ENCENDIDA, sigue F4 (2026-09-07)]].

## 6. Plan por fases

Se avanza por evidencia, sin esperas por calendario entre fases. Las estimaciones iniciales de semanas no son gates ni compromisos de entrega. G8 sí requiere un ciclo operativo mensual completo. F4/F5 se ensayan con datos sintéticos; el nuevo circuito económico real espera F7/G6 y F8/G7.

### F0 — contrato comercial y mapa completo

**Avance:** al completar la evidencia de esta fase.

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

**Avance:** al completar la evidencia de esta fase.

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

**Avance:** al completar la evidencia de esta fase.

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

**Avance:** al completar la evidencia de esta fase.

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

### F4 — motor de inversiones multiempresa (ensayo técnico aislado)

**Estado:** en construcción y ensayo local con datos sintéticos; **G4 abierto**. La candidata no se ha publicado ni registrado como migración aplicada en producción.

**Qué se construye:**

- puerta canónica «registrar nueva inversión» para una persona existente y selección de empresa;
- rama Avance: reutilizar contrato, cronograma, titularidad y recuperación de Auth/Portal;
- rama Qorilazo/Prodelco: un cierre económico por inversión, con monto, depósito, referencia, fecha comercial, vencimiento y evidencia;
- relación atómica entre persona, empresa, fuente e inversión utilizando la estructura de F1;
- autorización por rol/ámbito, veto, documento y estado; control de operaciones simultáneas;
- repetición idempotente por clave y contenido, depósito único y conflicto sin efectos ante datos diferentes;
- anulación comercial sin borrado y con Capital intacto, conforme a ATR-4;
- evolución controlada de `UNIQUE(lead_id)` y de los consumidores que hoy presuponen un cierre externo por lead;
- preservación de las reglas de conversión publicadas: primera operación de cartera elegible por cliente/mes, upgrade fuera del mes del primer contrato y peso de renovación del período.

**Base productiva observada el 07/09 a las 11:32–11:33 Lima:** 14 cierres de F2 ya tienen inversión y titular coherentes; existe 1 cierre adicional sin vincular. No se repiten las 14 vinculaciones. El faltante requiere clasificación y tratamiento acotado por el proceso canónico. No se considera resuelto por el solo formato válido del documento. Se deberá renovar el recenso antes de tratar datos reales.

**Construido y comprobado en el banco local:**

- Nueva inversión para persona existente: Avance→Qorilazo, Qorilazo→Prodelco y repetición en cooperativa; también contratos Avance en PEN/USD con perfil existente y acceso Qorilazo→Avance. Avance conserva términos libres; el catálogo no se vuelve obligatorio.
- Fuente económica, inversión y titular principal coherentes; contratos, cuentas y cronogramas Avance creados; comprobantes de cooperativas cargados y descargados con los mismos bytes. PDF: 10 grupos adicionales/ocho contratos y regresión posterior de 12 grupos/10 contratos, con recuperación Deno, reserva de 120 segundos reales y un archivo/sello por contrato. Storage sin respuesta se acota a 20 segundos; la subida tardía y la incompatibilidad recibida se recuperan. Dos antecedentes sin job conservan su contrato sin generar un documento nuevo. Cuatro contratos de ensayos interrumpidos también se recuperaron.
- Repetición segura por clave y contenido, conflicto sin efectos, depósito único con solicitudes simultáneas y apagado que espera a la confirmación en curso.
- Recuperación de Auth/Portal y cambio de responsable sin duplicar acceso, conservando la solicitud y la atribución histórica. Se probaron pérdida de respuestas, espera real de la reserva de acceso y recuperación por el equipo vigente.
- Corrección de documento y fusión canónica: **7 + 8 + 6 = 21 grupos nuevos**, incluidas cuatro carreras reales contra la confirmación, doble fusión y compatibilidad con un contexto Auth anterior. Se respetan los bloqueos de F3: el acceso inconcluso se recupera antes de la corrección/fusión autorizada. Las regresiones de Portal, revisión de responsable y cooperativas pasaron después de estos cambios.
- Paridad parcial sobre seis fuentes de referencia: S/8000 y 52 cuotas conservados; upgrade del mismo mes no aporta, uno elegible posterior sí y una segunda operación de cartera elegible del mismo cliente/mes no agrega conversión. Fecha comercial anterior y ajuste posterior a mes sellado probados; una inversión cooperativa adicional anulada conserva su capital e historia.
- Auditoría adversaria de Claude contrastada con código y ejecución real. Se corrigió la relectura de inversiones confirmadas tras «No insistir», conservando los permisos actuales y el bloqueo de inversiones nuevas o pendientes. Pasaron nueve oráculos de regresión; la estructura actual tiene 34 funciones, 17 nuevas y cuatro tablas nuevas.
- Plantilla, renderer, firma, fondo y fuentes PDF sin cambios; 42 pruebas del handler/adaptador y revisión visual previa de 14 páginas. La cotitularidad está en el registro contractual y snapshot, pero aún no se imprime. Miguel exige aprobación previa de texto y ubicación antes de cualquier incorporación. Claude no recibió las correcciones posteriores del worker; la auditoría no aprueba G4.

**Pendientes obligatorios para cerrar G4:**

1. **Históricos y cotitulares:** ensayar la vinculación canónica de F2 con casos resueltos, faltantes y conflictivos; preparar el tratamiento acotado tras un recenso nuevo. Completar cotitularidad neutral y sus efectos ante corrección/fusión, sin propagar permisos. Conservar el cotitular en el contrato no demuestra todavía el vínculo neutral completo. Cualquier incorporación al PDF requiere aprobación previa de texto y ubicación por Miguel.
2. **Permisos y lecturas:** cambios de rol, bajas, multirrol, personas sin responsable y lectores heredados. Separar el permiso del responsable actual de la atribución histórica de la inversión.
3. **Reglas financieras completas:** renovaciones ponderadas, comisión y comisión liquidada, atribución, demos, anulación inicial y Avance, ajustes y consumidores de fechas. Probar también la carrera entre sellado mensual y nueva operación; preservar Capital, historia y períodos sellados.
4. **Corrección de una solicitud preparada:** corregir términos o datos inválidos de forma trazable, conservando la repetición segura. La revisión de responsable ya probada no resuelve esta edición.
5. **Cobertura de puertas:** completar el inventario de escritores y lectores afectados, incluidos los que presuponen un cierre externo por lead, y comprobar que ninguna ruta evade los controles.
6. **Paquete final G4:** reconstruir la candidata completa desde un banco limpio, probar reversa/restauración, completar revisión adversaria integral y reunir el artefacto exacto con todas las pruebas de aceptación, incluida la integración documental final.

**Casos de aceptación:**

1. cliente Avance registra inversión Qorilazo;
2. inversionista Qorilazo registra inversión Prodelco;
3. inversionista Qorilazo pasa a Avance y recibe el acceso autorizado sin duplicarse;
4. cliente registra segunda inversión en la misma empresa sin otro lead;
5. misma solicitud repetida devuelve su resultado; misma clave con datos diferentes entra en conflicto sin efectos;
6. anulación comercial conserva historia, capital y tratamiento vigente de conversión;
7. upgrade elegible en otro mes sigue aportando; el no elegible y la segunda operación de cartera del mismo cliente/mes no generan aportes adicionales.

**Resultado exigido para terminar:** circuito técnico completo de nuevas inversiones probado con datos sintéticos, cumpliendo todos los casos y pendientes anteriores.

**Gate G4 — todavía abierto:** casos anteriores, concurrencia, permisos, recuperación, reconstrucción/reversa y paridad financiera/conversión en verde. La bandera `inversiones_escritura` se prueba solo en el entorno aislado y quedó apagada al cerrar esta tanda. G4 no autoriza dinero real ni el encendido productivo general. Evidencia y límites: [matriz de aceptación F4](../../CRM-Avance-Corp/supabase/scripts/f4/ESTADO-ACEPTACION.md).

### F5 — cartera y Ficha 360 multiempresa

**Avance:** al completar la evidencia de esta fase.

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

**Gate G5:** los cuatro roles ven exactamente lo permitido y completan sus recorridos con datos sintéticos, sin duplicaciones. No autoriza todavía el piloto económico.

### F6 — postventa, vencimientos y próxima inversión

**Avance:** al completar la evidencia de esta fase.

**Qué se adapta:**

- próxima acción a nivel de inversionista;
- alertas de vencimiento por empresa;
- renovación Avance desde contrato;
- reinversión externa desde inversión anterior;
- aumento o nueva inversión sin volver al pipeline;
- bandeja de inversionistas sin responsable;
- `no_contactar` aplicado a toda la persona;
- historial único de gestiones, conservando separados captación y postventa;
- solicitudes/revisión de retiro en cooperativas; su retirada financiera terminada requiere una definición posterior.

**Resultado visible:** el asesor puede continuar la relación y registrar la siguiente inversión desde la misma ficha.

**Salida F6:** toda inversión próxima a vencer puede terminar en una gestión, próxima acción y nueva inversión trazable, sin estados imposibles. G6 corresponde a la conciliación de F7.

### F7 — métricas y reportes por empresa, primero en sombra

**Avance:** al completar la evidencia de esta fase.

**Qué se adapta:**

- capital por empresa y moneda;
- número de inversiones por empresa;
- inversionistas con una, dos o tres empresas;
- primera inversión vs. reinversión;
- conversión comercial por las reglas y aportes publicados del núcleo; la identidad única no elimina renovaciones/upgrades elegibles;
- atribución y comisión por operación;
- vencimientos y oportunidades de cross-selling;
- demos excluidos técnicamente; anulación comercial aplicada a conversión y Capital conservado según ATR-4;
- meses sellados sin reescritura.

**Resultado visible:** Gerencia sabe cuánto se produjo en cada empresa y cuántos clientes invierten en más de una.

**Gate G6:** conciliación firmada de Capital, conversión, atribución y comisión; PEN/USD y empresas permanecen separados y ninguna inversión se cuenta dos veces. Recién entonces puede comenzar el piloto económico de F8.

### F8 — piloto económico real

**Equipo inicial:** Gerencia, un supervisor y dos usuarios comerciales.

**Evidencia mínima del maestro:**

- 15 identidades reales verificadas, al menos 5 representadas en cada empresa;
- 20 inversiones confirmadas y consecutivamente conciliadas, al menos 5 por empresa;
- 6 recorridos multiempresa, incluidos Avance→Qorilazo, Qorilazo→Avance, Qorilazo→Prodelco y segunda inversión en la misma empresa;
- casos multirrol, sin responsable, identidad provisional, cotitularidad, anulación, solicitud de retiro, upgrade reasignado y mes sellado;
- 10 reintentos idempotentes y 5 carreras controladas en el entorno aislado;
- fallos de Auth y depósito repetido cubiertos, cero P0/P1 abierto y cero diferencias financieras.

No se aprueba por cumplir cinco días de calendario: termina cuando cumple la evidencia y las firmas requeridas.

**Gate G7:** aceptación de Miguel y responsables financiero, de comisiones, técnico, de seguridad y operativo; conciliación firmada, soporte y reversa comprobados.

### F9 — activación progresiva y estabilización

**Olas tras aprobar G7:**

1. lectura 360 para Gerencia;
2. lectura y nuevas inversiones para usuarios piloto;
3. supervisores y fuerza comercial;
4. métricas y ritual operativo completo.

Cada ola avanza por evidencia de volumen, conciliación, seguridad y rendimiento. Se observa adopción, fricciones, oportunidades no atendidas y permisos. Las revisiones 30/60/90 son seguimiento comercial, no sustituyen los requisitos técnicos.

**Gate G8:** al menos un ciclo operativo mensual completo que cubra cierre y conciliación, procesos programados, vencimientos, Capital, conversión, atribución, comisión y ausencia de incidencias graves, huérfanos y procesos vencidos. Un cambio material o P0/P1 reinicia la observación del alcance afectado.

Solo después se retiran definitivamente permisos y rutas antiguas. Incorporar otras empresas y transferencias legales de titularidad se decide por separado.

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
- núcleos/helpers en schema no expuesto; RPC canónicas expuestas con `SECURITY DEFINER` solo con justificación, `search_path` fijo, `EXECUTE` revocado a `PUBLIC`, grants mínimos y autorización interna de identidad, rol y ámbito;
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
- anulación comercial → sanción de conversión vigente, Capital e historia intactos (ATR-4);
- primera inversión, reinversión y operaciones de cartera con su elegibilidad existente;
- upgrade del mismo mes frente a mes posterior, renovación ponderada y primera operación de cartera elegible por cliente/mes, sin calculadora nueva.

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

Numeración alineada con el maestro; los gates no son una renumeración de las fases.

| Gate | Requisito / alcance |
|---|---|
| G0 | Manifiesto productivo y reglas firmadas; base técnica para F1 |
| G1 | Esquema F1 reconstruible, reversible y seguro |
| G2 | Vinculación F2 clasificada y conciliada, sin fusiones ambiguas |
| G3 | Puertas F3 sin rutas paralelas que eviten los controles canónicos |
| G4 | Escritores F4 completos con datos sintéticos; concurrencia, idempotencia, permisos, documentos, recuperación, paridad financiera y reversa; sigue abierto y no autoriza dinero real |
| G5 | Ficha y permisos F5 aceptados con datos sintéticos |
| G6 | Métricas F7 conciliadas y firmadas; habilita solicitar el piloto económico |
| G7 | Piloto F8 aceptado por volumen, conciliación, pruebas y firmas |
| G8 | Despliegue progresivo y ciclo operativo mensual completos; retirada final de rutas antiguas |

Reglas de ejecución:

- preparar el SQL exacto, huellas, pruebas y reversa antes de su autorización;
- no usar `supabase db push` ni `migration repair` para ocultar divergencia;
- ejecutar solo el archivo aprobado y verificar los objetos reales después;
- desplegar primero el consumidor tolerante cuando cambie un payload;
- conservar controles para detener nuevas confirmaciones sin borrar operaciones;
- no restaurar escrituras directas ni crear dos fuentes de dinero como reversa;
- mantener Main local siguiendo `avancecorp/main`, integrar sin sobrescribir y publicar solo un artefacto construido desde su commit verificado; sin ramas de release ni `push --force`.

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

## 13. Orden inmediato — actualizado al 07/09/2026, 22:09 Lima

1. Completar históricos, cotitularidad neutral y permisos dinámicos, preservando las vinculaciones F2 resueltas y la atribución histórica. Los bordes técnicos PDF ya pasaron; conservar el contenido y aprobar con Miguel cualquier incorporación de cotitulares antes de editarla.
2. Cerrar la matriz financiera, las correcciones de solicitudes y el inventario de puertas/consumidores detallados en F4.
3. Reconstruir y revertir el paquete completo en banco; reunir y revisar la evidencia exacta para cerrar **G4**.
4. Continuar con **F5 → F6 → F7/G6 → F8/G7 → F9/G8**: ficha unificada, postventa, conciliación, piloto económico y activación progresiva con ciclo mensual completo.

F3 permanece encendida. Se conservan las fuentes de dinero y las reglas comerciales del proyecto, incluidos los upgrades que sí cumplen la elegibilidad. La modalidad de captura del documento en la web sigue pendiente de decisión comercial y no bloquea F4 con personas verificadas. Retoma y evidencia: [[F4 multiempresa - PDF real, recuperacion y auditoria (2026-09-07)]].

## 14. Fuentes relacionadas

- [[F4 multiempresa - PDF real, recuperacion y auditoria (2026-09-07)]];

- [[F4 multiempresa - construccion y pruebas parciales (2026-09-07)]];
- [[F4 multiempresa - objetivo de cierre y banco aislado (2026-09-07)]];
- [[RETOMAR-62 - identidad unificada ENCENDIDA, sigue F4 (2026-09-07)]];
- [[F4 multiempresa - reglas vigentes y punto de partida (2026-09-07)]];
- [[Nucleo de conversion - diagnostico de llegadas y asignaciones 2026-09-04]];

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
