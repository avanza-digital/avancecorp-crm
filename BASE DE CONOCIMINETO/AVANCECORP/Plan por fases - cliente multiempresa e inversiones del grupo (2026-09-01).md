---
tags: [crm, inversionistas, multiempresa, identidad, contratos, cooperativas, roadmap]
fecha: 2026-09-01
estado: plan-vigente-g6-cerrado-f8-instalada-off-g7-pendiente
actualizado: 2026-09-14
decision_origen: Miguel-confirmo-un-cliente-puede-invertir-en-varias-empresas
alcance_inicial: [avance-corp, coopac-qorilazo, coopac-prodelco]
avance: por-evidencia-con-ciclo-mensual-obligatorio-en-G8
---

# Plan por fases — un cliente, múltiples inversiones y múltiples empresas

> [!important] Objetivo confirmado por Miguel — 2026-09-01
> Un mismo cliente debe poder invertir una o varias veces en Avance Corp, COOPAC Qorilazo y COOPAC Prodelco, manteniendo una sola identidad, un solo lead y un solo historial comercial.

> [!warning] Autorización
> La construcción, el ensayo y posteriormente la publicación de F4 fueron autorizados por Miguel y están completados. G4 técnico se cierra con la evidencia y la decisión de alcance del 08/09; no autoriza backfill productivo, dinero real o activación en producción. Las ejecuciones posteriores conservan los gates y autorizaciones del plan.
>
> **Corrección documental del 07/09/2026:** se conservan las fuentes de Capital, el trabajo ya realizado en F2 y las reglas de conversión existentes, incluidos renovaciones y upgrades elegibles. Se alinean anulación, ensayo, piloto y gates con el maestro. Autoridad y evidencia: [[F4 multiempresa - reglas vigentes y punto de partida (2026-09-07)]].

## Estado vigente — F8 instalada y verificada, piloto sin activar

**F7 publicada e instalada, apagada.** Nuevo informe Empresas de Gerencia:
capital y cantidades separados por empresa/moneda, personas y cotitulares,
primeras/posteriores registradas, conversión y atribución conservadas,
vencimientos y oportunidades respetando No contactar. Cuatro funciones nuevas
y bandera propia OFF, sin sustituir los núcleos ni modificar fuentes.
Miguel aprobó el SQL exacto y el coste del banco Supabase (US$0.01344/h).
Instalación y publicación verificadas el 11/09/2026; banco propio eliminado.
3.355 pruebas frontend, 172 E2E y 16 SQL + 12 HTTP remotos PASS; 26 E2E SKIP.
La matriz RLS general mantiene 57 FAIL / 1.772 PASS antes/después, sin
regresiones. **Lectura real G6 verificada: 218 inversiones, sin diferencias;
conformidad humana/financiera recibida el 13/09 para el corte del 11/09. G6
cerrado. F8 quedó instalada y verificada OFF el 14/09, sin participantes.
Los diez huecos reales están corregidos y la exclusión demo ya está instalada.
El ensayo combinado pasó 31 pruebas SQL locales, 27 remotas y 12 grupos Auth;
Main integrado, 3.513 pruebas frontend y artefacto verificado. Producción:
600 fuentes reales sin brechas al corte de las 12:09 Lima y cinco demos
conservadas fuera del lector operativo. Rama exclusiva eliminada tras verificar.
Faltan equipo, configuración/activación autorizadas y evidencia G7.**
Punto vigente: [[F8 - instalada y apagada (2026-09-14)]].
Corrección demo: [[F8 - exclusion demo preparada (2026-09-13)]].
Paquete y procedimiento de instalación: [[F8 - instalacion apagada preparada (2026-09-13)]].
El preflight vivo pasó antes del merge y el catálogo posterior coincide con el
ensayo dentro de las diferencias administradas revisadas:
[[F8 - ensayo completo antes de instalar (2026-09-14)]].
Miguel confirmó el caso multirrol y aprobó el SQL de los diez movimientos reales.
La aplicación productiva pasó veinte verificaciones posteriores:
[[F8 - enlaces reales aplicados (2026-09-13)]].
Diagnóstico: [[F8 - revision de identidades pendientes (2026-09-13)]].
Evidencia y punto de retoma:
[[F8 - piloto economico preparado localmente (2026-09-13)]].

**F4 publicada con escritores apagados; G4 técnico cerrado.** La instalación fue autorizada por Miguel y verificada el 08/09. La nueva interfaz y el encendido conservan las fases siguientes. Acta: [[RETOMAR-65 - CARTERA F4 publicada y plan F5 (2026-09-08)]].

**F5 implementada, frontend publicado y servidor instalado y verificado, sin encender.**
Cartera, ficha neutral y nueva inversión integradas con F4. Main y su remoto
conservan los commits; el paquete incluye SQL exacto, tipos, frontend, función
documental, evidencia y reversa. Miguel valoró favorablemente las pantallas y
se completó su adaptación visual a los componentes del CRM. Acta vigente:
[[F5 - instalada y apagada (2026-09-10)]].

 Miguel confirmó que
las comisiones se calculan fuera del sistema y no quiere ese módulo. Se excluyen
su cálculo, liquidación y contraste de pagos externos de los requisitos del
producto. La atribución por inversión y las reglas de Capital/conversión se
conservan. Decisión: [[F4 cerrada - comisiones fuera del sistema (2026-09-08)]].

| Fase | Estado actual | Resultado o trabajo pendiente |
|---|---|---|
| F0 / G0 — reglas y base del plan | Aprobadas y firmadas | Comisiones externas aclaradas el 08/09 |
| F1 — cimientos | Publicada | Identidad neutral, empresas y relaciones |
| F2 — vinculación histórica inicial | Publicada | Conservar lo resuelto; recenso antes de tratar faltantes reales |
| F3 — reconocimiento único | Publicada y encendida | Identidad unificada activa desde el 07/09 a las 10:09 Lima |
| **F4 — motor de inversiones** | **Publicada; G4 técnico cerrado** | Motor instalado; escritores apagados y fuentes conservadas |
| F5 — cartera y Ficha 360 | Instalada y verificada; F5 apagada | VoiceOver aprobado; 46 pruebas locales y 15 remotas PASS. SQL correctivo aprobado, servidor instalado y banco temporal eliminado el 10/09. Los diez huecos reales se corrigieron el 13/09; la exclusión demo se instaló el 14/09. [[F8 - instalada y apagada (2026-09-14)]] |
| F6 — postventa | Últimos ajustes publicados; revisión manual cerrada con excepción; F6 apagada | Agenda por persona, vencimientos, veto, reinversión y retiro administrativo. Selector de archivos, foco y mensaje de conexión publicados el 11/09. Gate integrado: 3.246 tests y 160 E2E PASS (26 SKIP); 84 archivos y banderas verificados. VoiceOver omitido por Miguel (NOT RUN). Las 43 pruebas remotas iniciales y las observaciones de la matriz general/Auth conservan su alcance. [[F6 - cierre y ajustes publicados (2026-09-11)]] |
| F7 — métricas | Publicada e instalada OFF; G6 cerrado | Informe Empresas y SQL aditivo verificados; banco temporal cerrado. Corte real de 218 inversiones sin diferencias y conformidad humana/financiera recibida. Los diez enlaces técnicos pendientes se completaron en F8. [[G6 - conciliacion real preparada (2026-09-11)]] |
| F8 — piloto económico | Instalada y verificada OFF; G7 abierto | Enlaces y exclusión demo completos. Elegir Gerencia, supervisor y dos vendedores; aprobar configuración/activación y completar evidencia real G7. [[F8 - instalada y apagada (2026-09-14)]] |
| F9 — activación y observación | Pendiente | Despliegue progresivo, ciclo mensual y retirada de rutas en G8 |

Paquete F4: 48 funciones (18 adaptadas/30 nuevas), 11 módulos y siete tablas;
3050 tests frontend, 43 PDF Deno, reconstrucción y restauración, matrices de
finanzas/permisos/cotitulares/correcciones/históricos completadas. Evidencia y
límites en la [matriz de aceptación](../../CRM-Avance-Corp/supabase/scripts/f4/ESTADO-ACEPTACION.md).
El PDF conserva su contenido: cualquier incorporación impresa de cotitulares
requiere mostrar texto/ubicación y recibir aprobación de Miguel antes de editar.
Los snapshots de auditoría y el manifiesto previo se conservan como historia;
el acta de cierre registra la decisión posterior sin cambiar código ni SQL.

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
| Atribución | Se conserva quién registró/cerró cada operación; la atribución efectiva sigue la política vigente de cada empresa y de las cadenas de upgrade. Meses sellados no se reescriben; las comisiones/pagos se gestionan fuera del sistema |
| Conversión comercial | La decide el núcleo existente. Upgrade elegible = 1; renovación elegible = peso de Referido del período; máximo una operación de cartera elegible por cliente/mes. No se impone una prohibición vitalicia ni se convierte cada inversión automáticamente |
| Reinversión | Nunca crea lead ni vuelve a ejecutar la primera conversión |
| Anulación comercial | Conserva fila, autor y motivo; reduce conversión según ATR-4 y conserva Capital, producción y AUM |
| Datos demo | Se excluyen por clasificación técnica, no por nombres |
| Transferencias | Fuera del alcance inicial; requieren ledger legal propio |
| Fecha comercial en cooperativas | Propia por inversión: anterior o igual al registro, nunca futura; Capital y conversión la usan como en Avance; en mes sellado entra como ajuste posterior (decisión 9, **confirmada por Miguel el 02/09/2026**) |

### Decisiones confirmadas de F0 y precisión del 07/09

> [!success] Las 7 CONFIRMADAS por Miguel el 03/09/2026 con los valores recomendados (la 7 lo estaba desde el 02/09).

1. Responsable comercial: **único para las tres empresas** (se conserva quién cerró cada inversión; las comisiones se resuelven fuera del sistema). ✅
2. Cooperativas: **solo PEN** por ahora; Avance sigue en PEN y USD. ✅
3. Documentos: **Avance, contrato PDF como hoy; cooperativas, comprobante de depósito, número de referencia y evidencia.** ✅
4. Registran: **vendedor en sus clientes, supervisor en su equipo, Gerencia en todos; Directorio solo lee.** ✅
5. Portal: **solo Avance**; no se crea acceso al Portal por invertir en cooperativa. ✅
6. Comisión: **proceso externo al sistema**, según aclaración expresa de Miguel del 08/09; no se implementa cálculo, liquidación ni registro de pagos en el CRM. **Precisión de Miguel del 07/09:** la conversión depende de la elegibilidad definida en el proyecto, incluidos renovaciones y upgrades; se retira la formulación general de conversión vitalicia. ✅
7. si las inversiones en cooperativa llevan una fecha comercial propia, que puede ser anterior al registro pero nunca futura; Capital y conversión la usan igual que en Avance. Si cae en un mes ya sellado, entra como ajuste posterior, sin reescribir el mes (añadida el 02/09/2026 como decisión 9 de la lista de preguntas a Miguel; **CONFIRMADA por Miguel el 02/09/2026**).

> [!info] Antecedente histórico al 07/09/2026, 21:26 Lima — superado por el cierre técnico del 08/09
> **F0/G0 están firmadas y F1, F2 y F3 están en producción**; la identidad unificada se encendió a las **10:09 Lima**.
> **La puerta técnica de nueva inversión está publicada y verificada.** Está instalada con sus escritores apagados: `inversiones_escritura` (F4) y `ficha_360_neutral` (F5) siguen apagados en producción. El recorrido unificado desde la ficha se integrará en F5.
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
- fijar cómo se medirán capital, producción, atribución y conversión por empresa; comisiones externas fuera del producto (aclaración del 08/09).

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

### F4 — motor de inversiones multiempresa (publicada; escritores apagados)

**Estado al 08/09/2026:** candidata completa versionada, reconstruida y verificada
con datos sintéticos. **F4 terminada; G4 técnico cerrado.** Miguel confirmó que las
comisiones se calculan fuera del sistema y no quiere incorporar ese cálculo.
La exclusión explícita resuelve el único pendiente externo; no se afirma un PASS
de liquidaciones ni se modifica la evidencia previa.

**Construido:** puerta canónica de nueva inversión por persona/empresa;
Avance conserva contrato, cronograma, cuenta, PDF y Auth/Portal recuperable;
Qorilazo/Prodelco conservan monto, depósito único, referencia, fecha comercial,
vencimiento y evidencia privada. Una fuente económica, inversión y principal
atómicos por operación; no se crea otro lead por inversión adicional.
48 funciones (18 adaptadas, 30 nuevas), 11 módulos, siete tablas nuevas.

**Requisitos técnicos comprobados:**

1. Avance→Qorilazo, Qorilazo→Prodelco, repetición de cooperativa, Avance PEN/USD
   y Qorilazo→Avance con un solo Auth/Portal. Clave/contenido, depósito,
   concurrencia y apagado seguros. Dos reservas de acceso de diez minutos reales
   recuperadas; documento/fusión y revisión de responsable conservan el proceso.
2. Cotitularidad neutral: 16 grupos, procedencia inmutable, pendientes/documentos
   ocupados/reutilizados, corrección y fusión. Un cotitular del equipo ajeno no
   obtiene permiso sobre el principal, inversión o contrato. El PDF sigue igual;
   cualquier agregado impreso exige aprobación previa de Miguel de texto/ubicación.
3. Solicitudes preparadas: 20 grupos de corrección versionada, auditoría,
   repetición, revisión vieja, Auth reservado y carreras. Permisos: 19 grupos +
   multirrol 12; bajas, traslados, sin responsable y lectores heredados. Teléfono
   vivo sigue la relación actual; atribución del cierre conserva su historia.
4. F2 original e históricos: 12 grupos sobre corpus/semilla/oráculo publicados;
   censo 7, lote 19, concurrencia 7, identidad 6, mantenimiento 8 y máximo mixto
   de 100 fuentes. F2 global se retira al instalar F4, incluso apagada. Censo y
   lote acotado sustituyen una repetición global que ya no admite cardinalidad 1:N.
5. Finanzas: 13 grupos, renovación ponderada 0.15, elegibilidad por cliente/mes,
   rango parcial, PEN/USD, demos, anulación inicial Avance/cooperativa, Capital
   intacto, atribución de cadena y ambas carreras sello/confirmación. Fecha antigua
   en mes abierto mantiene imputación declarada; mes sellado conserva su foto y
   produce ajuste al vivo. Metas/ajustes de conversión no prueban comisión pagada.
6. Inventario: 546 funciones, 26 consumidores directos, 18 escritores, 97
   transitivos y 24 triggers; guarda de instalación contra deriva y dos mutantes
   rechazados. La pantalla existente admite inversión sin lead, fecha comercial
   y persona con Portal, sin adelantar el desarrollo de F5.
7. Reconstrucción independiente desde esquema sin datos; semilla real antes de
   aplicar candidata completa, paridad de cuatro contratos/dos cierres/52 cuotas/
   PEN 8000. Restauración hacia destinos nuevos: 133 tablas y 27 archivos, seis
   grupos PASS. Reversa operativa OFF conserva historia; no hay DOWN destructivo.
8. PDF: última tanda 12 grupos/10 contratos PASS y lectura de diez trabajos
   recuperados tras WORKER_LIMIT. El ensayo interrumpido conserva su FAIL original.
   Sin cambiar recursos/renderer/reloj; 43 tests Deno y revisión visual de 14
   páginas. Frontend completo 3050 tests, lint/typecheck/build/bundle, cuatro
   gates backend y 17 nodos de tipos introspectados. Claude revisó integralmente;
   Codex resolvió cada hallazgo con pruebas, sin atribuirle un PASS posterior.

**Cierre:** no quedan requisitos pendientes dentro del alcance técnico F4.
Comisiones/liquidaciones son externas y no bloquean la fase. Se conserva la
atribución por inversión, Capital, conversión, documentos y períodos sellados.
Sigue F5; el motor F4 está instalado y la activación comercial conserva los gates posteriores.

**Publicación del 08/09:** instalada la revisión compatible `20260908211349`, frontend y dos Edges verificados. Las fuentes económicas, 14 vínculos existentes, PDF v8 y la autorización administrativa se conservaron. No se ejecutó backfill. Escritores F4 y ficha F5 siguen apagados; G4 no habilita por sí solo el encendido comercial general. Cualquier completado histórico posterior exige censo vigente. [[RETOMAR-65 - CARTERA F4 publicada y plan F5 (2026-09-08)]].

Fuentes vigentes: [matriz de aceptación F4](../../CRM-Avance-Corp/supabase/scripts/f4/ESTADO-ACEPTACION.md),
[[F4 multiempresa - reconstruccion, finanzas y lectura vigente (2026-09-08)]].

### F5 — cartera y Ficha 360 multiempresa

Plan ejecutable: [[Plan de implementacion F5 - cartera y ficha multiempresa (2026-09-08)]].

**Implementación del 08/09:** cartera única, ficha y nueva inversión completadas.
38 pruebas de banco y el gate completo del CRM aprobados; capturas de escritorio,
móvil y roles, PDF PEN/USD conservado, SQL/reversa ensayados y tipos cotejados.
Miguel valoró favorablemente las capturas y se verificó el ajuste de coherencia
visual con el CRM. El 09/09 confirmó el recorrido manual guiado de VoiceOver:
cartera, ficha y campos del formulario de inversión Qorilazo. El alcance y los
casos no ensayados manualmente constan en el acta de aceptación.
El 09/09 se publicó la corrección del salto de cartera y se verificó el
frontend del commit `baad8cf`. El 10/09 se instaló el servidor y su corrección
autorizada desde Main `a884ac3`, con comprobación productiva y eliminación del
banco temporal. Hay 15 fuentes sin identidad vinculada que bloquean el encendido.
Detalle: [[F5 - instalada y apagada (2026-09-10)]].
Las escrituras F4 y la ficha F5 permanecen apagadas en producción. Evidencia:
[aceptación F5](../../CRM-Avance-Corp/supabase/scripts/f5/ACEPTACION.md).

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

**Avance al 11/09:** frontend y tres SQL instalados; últimos ajustes publicados,
con F6 apagada. Revisión manual cerrada con excepción autorizada: VoiceOver
omitido, NOT RUN. Gate integrado de publicación: 3.246 tests y 160 E2E PASS
(26 SKIP). Las 43 pruebas remotas F6 y 46 de regresión local F5 mantienen su
evidencia anterior. La matriz RLS general histórica conserva 1.772 PASS / 45 FAIL
antes/después, cero regresiones; no se presenta como aprobada. Se conserva la
observación Auth por refresco concurrente, sin afirmar igualdad íntegra.
No se aplicó SQL ni se encendieron banderas en la publicación del 11/09.
Evidencia y límites: [[F6 - cierre y ajustes publicados (2026-09-11)]].

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
- atribución por operación; cálculo/liquidación de comisiones externos al sistema;
- vencimientos y oportunidades de cross-selling;
- demos excluidos técnicamente; anulación comercial aplicada a conversión y Capital conservado según ATR-4;
- meses sellados sin reescritura.

**Resultado visible:** Gerencia sabe cuánto se produjo en cada empresa y cuántos clientes invierten en más de una.

**Gate G6:** conciliación firmada de Capital, conversión y atribución; PEN/USD y empresas permanecen separados y ninguna inversión se cuenta dos veces. Recién entonces puede comenzar el piloto económico de F8.

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

**Gate G8:** al menos un ciclo operativo mensual completo que cubra cierre y conciliación, procesos programados, vencimientos, Capital, conversión, atribución y ausencia de incidencias graves, huérfanos y procesos vencidos. Un cambio material o P0/P1 reinicia la observación del alcance afectado.

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
| G4 | Escritores F4 completos con datos sintéticos; concurrencia, idempotencia, permisos, documentos, recuperación, paridad financiera y reversa; **cerrado técnicamente el 08/09**, comisiones externas fuera del alcance; no autoriza dinero real |
| G5 | Matriz técnica F5 con datos sintéticos PASS; propuesta visual bien recibida por Miguel y ajuste al CRM verificado; recorrido manual guiado de VoiceOver aprobado el 09/09 para cartera, ficha y campos de inversión Qorilazo. Alcance en el acta de aceptación |
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

- cálculo, liquidación, indicación de cuánto pagar y conciliación de pagos de comisiones dentro del sistema; proceso externo confirmado por Miguel el 08/09;

- transferencias legales de titularidad;
- consolidar contablemente empresas distintas;
- convertir el Portal Avance en portal de todas las empresas;
- migrar Qorilazo/Prodelco a contratos completos de Avance;
- mezclar monedas;
- eliminar físicamente demos o históricos;
- incorporar nuevas empresas antes de estabilizar las tres iniciales.

## 13. Orden inmediato — actualizado al 13/09/2026

1. F4/G4 técnico cerrado: conservar el paquete probado de `bcdfa0d` y el acta
   posterior de comisiones externas. No repetir pendientes ya resueltos.
2. **F5 instalada y apagada:** revisión manual aprobada, salto corregido y SQL
   adicional autorizado e instalado. Datos y permisos verificados; banco eliminado.
   Conservar los 65 fallos anteriores del gate general como pendientes explícitos,
   sin etiquetarlo PASS. Los diez huecos reales ya se corrigieron; antes de
   encender, resolver el tratamiento de los cuatro demo y repetir el censo.
   Evidencia en [[F5 - instalada y apagada (2026-09-10)]].
3. **F6 publicada e instalada OFF:** conservar los tres SQL y la reversa.
   Los ajustes y la revisión manual quedaron cerrados el 11/09, con VoiceOver
   omitido por Miguel (NOT RUN). Conservar las observaciones de la matriz
   general. [[F6 - cierre y ajustes publicados (2026-09-11)]].
4. **F7 publicada e instalada OFF; G6 cerrado:** comparativo real aceptado por
   Miguel como responsable financiero para el corte del 11/09. SQL, ensayo,
   publicación y banco propio completados. [[G6 - conciliacion real preparada (2026-09-11)]].
5. **F8 preparada localmente, piloto OFF; enlaces reales aplicados:** resolver
   los cuatro huecos demo, elegir equipo, completar el ciclo de rama e iniciar
   el piloto autorizado. Después
   sigue F9/G8 con activación progresiva y un ciclo mensual completo.

F3 permanece encendida; F4/F5/F6/F7 permanecen apagadas. El preflight F8 inicial
del 13/09 contó diez huecos reales y cuatro demo. El lote exacto aprobado por
Miguel resolvió los diez reales, con lectura posterior a las 21:29 Lima:
[[F8 - enlaces reales aplicados (2026-09-13)]]. Quedan cuatro huecos demo.
La conformidad G6 conserva su corte; el completado no activa el piloto.
La modalidad de captura de documento web sigue como decisión
comercial independiente. Cierre y alcance: [[F4 cerrada - comisiones fuera del sistema (2026-09-08)]].

## 14. Fuentes relacionadas

- [[F4 cerrada - comisiones fuera del sistema (2026-09-08)]];

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
