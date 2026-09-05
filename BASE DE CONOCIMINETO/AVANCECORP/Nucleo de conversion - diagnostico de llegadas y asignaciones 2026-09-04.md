---
tags: [crm, conversion, nucleo, diagnostico, origenes]
actualizado: 2026-09-04
estado: publicado-y-verificado
---

# Núcleo de conversión — llegadas vs. asignaciones (2026-09-04)

Relacionado con [[Conversion mensual - definicion cerrada]],
[[Conversion unica en todo el CRM - plan de migraciones]],
[[Deploy origen manual LANDING FORMULARIO 2026-09-01]] y
[[Gestión comercial de clientes - renovaciones y upgrades]].

## Aclaración de negocio de Miguel

Los únicos orígenes de lead que pertenecen al núcleo comercial de conversión
son **Landing, Formulario y Referido**. `Oficina` y `Otro` pueden seguir siendo
datos operativos del CRM, pero no deben alterar el porcentaje canónico.

La pregunta empresarial es cuántos leads **llegaron al sistema**, no cuántas
veces fueron asignados o reasignados. Las renovaciones y upgrades elegibles sí
aportan al numerador, siempre con divisor cero y con la deduplicación vigente
de máximo una operación elegible por cliente y mes.

### Corrección confirmada por Miguel — renovaciones

Miguel corrigió expresamente la tabla del diagnóstico: **la renovación tiene
la misma lógica de ponderación que el referido**. Cada renovación elegible
aporta el peso del referido del período (**0,15 actualmente**) al numerador y
**0 al divisor**. El upgrade elegible conserva aporte **1** al numerador y
**0 al divisor**. Una renovación con capital adicional sigue siendo una sola
operación; el dinero adicional no genera otro aporte de conversión.

Esta confirmación sustituye la regla anterior «renovación = 1». Se conserva
el máximo de una operación de cartera elegible por cliente/mes y el criterio
existente de elección de la primera operación; el cambio de peso no autoriza
a sumar una renovación y un upgrade del mismo cliente dos veces.

**Estado:** backend y frontend publicados y verificados el 04/09/2026.
Migración `20260904210831_crm_conversion_llegadas_unicas.sql`, aplicada a las
18:12 hora de Lima. Su versión y cuerpo registrados coinciden con el archivo
local (MD5 `a880b7ba0db22090577dff4b906df5ab`). El diagnóstico de asignaciones
que sigue describe el comportamiento anterior, no el actualmente publicado.

La fórmula comercial acordada, para un mismo período y ámbito, es:

`100 × (cierres Landing/Formulario + peso × cierres Referido + peso × renovaciones elegibles + upgrades elegibles − ajustes aplicables) / llegadas Landing/Formulario automáticas únicas`

La aplicación de ajustes conserva el tratamiento vigente de anulaciones y su
suelo en cero. Con divisor cero, la tasa queda sin base para calcularse;
los cierres y las operaciones siguen mostrándose en sus propios conteos.

## Evidencia de producción — 1 al 3 de septiembre de 2026

### Textos de gestión acordados después de publicar

Miguel pidió rótulos breves, sin explicaciones largas en el resumen. La
lectura «Cosecha del rango» se presenta como **Resultados de los leads
recibidos**. En Resumen y Conversiones, el desglose se expresa como
**243 leads recibidos: 231 automáticos · 11 manuales · 1 referido** (ejemplo;
los cuatro valores siguen viniendo del núcleo, no están fijados en pantalla).
Se retira «fuera de la base» del resumen, que inducía a pensar que esos leads
no contaban en ningún sentido. No cambian el divisor, la elegibilidad de los
cierres, los pesos, los filtros ni la atribución. El peso se rotula en una
sola línea: «Peso: referidos y renovaciones ×0,15 · Upgrades ×1».

Este ajuste de textos se **publicó y verificó el 04/09/2026, ~20:19 Lima**,
separado del despliegue del núcleo: commit `b8108ae3f4dc`, release
`crm-20260905T011158Z-b8108ae3f4dc`, build `build-20260905T011157779Z`.
Se comprobaron los rótulos y el desglose en Resumen y Conversiones de
producción con una sesión de Gerencia existente, sin errores de consola.
La base de datos no requirió ni recibió otra migración. Evidencia completa
y rollback exclusivo de frontend en [[Deploy a Hostinger]].

### Conteos verificados del rango

Consulta agregada de solo lectura, ventana Lima
`[2026-09-01 00:00, 2026-09-04 00:00)`:

- Formulario: 110 altas, de las cuales 6 fueron manuales; **104 llegadas automáticas**.
- Landing: 74 altas, de las cuales 2 fueron manuales; **72 llegadas automáticas**.
- Total de llegadas automáticas Landing + Formulario: **176**.
- Referido: 1 alta manual; por la regla vigente no entra al divisor.
- Fuera del núcleo comercial: 1 Oficina + 12 Otro.

Antes del cambio, el agregador publicado devolvía divisor **289**, compuesto por:

- 177 pares analista/lead correspondientes a las 176 llegadas del período
  (un lead pasó por dos analistas);
- 91 pares provenientes de 47 leads Landing/Formulario creados antes del rango
  y asignados o reasignados dentro de él;
- 8 altas manuales Landing/Formulario;
- 13 casos Oficina/Otro.

Por eso 289 no significa «leads que llegaron». Significa asignaciones únicas
por pareja analista/lead dentro de la ventana, incluidos arrastres y canales que
Miguel dejó fuera del núcleo.

En la ventana 1–4 de septiembre el mismo defecto explica exactamente el texto
de **345 asignaciones contabilizadas**: 178 Formulario + 154 Landing + 12 Otro
+ 1 Oficina; el Referido queda fuera del divisor.

El diagnóstico preliminar quedó confirmado contra las RPC reales después de
publicar: **9 / 176 = 5,11 %**, con siete cierres elegibles de lead y dos
upgrades. Las operaciones tienen fecha efectiva **02/09 y 03/09**: ambas
pertenecen al rango, sin incluir operaciones del día 4. No hay renovaciones ni
cierres de Referido en ese rango y no había ajustes pendientes por anulaciones
de meses cerrados en la verificación. Las llegadas comerciales suman **185**:
176 automáticas, 8 altas manuales Landing/Formulario y 1 Referido.

Ese índice no significa que nueve de las 176 llegadas se convirtieron:
incluye operaciones de clientes existentes y cierres de leads que llegaron
antes. La lectura independiente de cosecha del mismo lote devuelve 6 cierres
entre 185 llegadas comerciales (**3,2 %**) al momento de la consulta; es una
medida distinta y no sustituye la conversión ponderada.

### Hallazgo posterior: «25 llegaron a cita / 48 con cita pactada»

Diagnóstico de solo lectura del 04/09/2026, solicitado por Miguel después
del ajuste de textos. **Pendiente de corrección; no se modificó ni publicó
código por esta consulta.**

La tarjeta lee `cohorte.reuniones_realizadas` y
`cohorte.reuniones_agendadas` de la implementación existente. Son conteos
de leads del lote de llegada, no conteos de citas por fecha de realización.
El embudo infiere etapas anteriores: una propuesta o un cierre también
activa `reunion_realizada`, aun sin registro de una reunión; ese resultado
activa a su vez `reunion_agendada`.

Reproducción agregada en producción, llegadas del **1 al 4 de septiembre**
en Lima, sin filtro de origen adicional y reutilizando `conversion_episodios`:

- **243 leads únicos** en el lote.
- **25** «llegaron a cita»: 8 con la señal de realización que acepta el
  código (tarea completada o actividad `reunion_realizada`) y **17 sin esa
  señal**, inferidos por propuesta (12) o solo por cierre (5).
- **48** «con cita pactada»: 38 con señal de agendamiento (tarea de reunión
  o cambio a la etapa correspondiente) y **10 inferidos sin esa señal**.
  Solo 17 leads del lote tienen una tarea de reunión registrada.

No afirmar «25 asistieron de 48 citas reales», ni que los 23 restantes sean
inasistencias o pendientes. Tampoco llamar a los 8 «asistencias confirmadas»:
esta comprobación reproduce las señales del código, no una validación de
sus resultados/anulaciones. Las señales se buscan en todo el historial del
lead, sin recortar la fecha de la cita al rango de llegada. Corregir requiere
separar evidencia de citas y avance inferido dentro de las piezas existentes,
sin crear otra calculadora; todavía no hay autorización de implementación.

## Cómo estaba construido en producción antes del cambio

`private.conversion_episodios` emite tres clases de fila:

1. `recibido`: una fila por pareja analista/lead con asignación en la ventana;
2. `cierre`: un cierre del ledger, con anulado en cero y Referido ponderado;
3. `operacion`: primera renovación/upgrade elegible por cliente y mes.

La relación ya publica `aporte_divisor` y `aporte_numerador`. En particular,
marca con divisor cero los Referidos y las altas manuales Landing/Formulario.
Sin embargo, los consumidores no suman esas columnas: vuelven a reconstruir la
fórmula con `tipo` y `fue_referido`.

Verificado en producción el 2026-09-04 antes de la migración:

- `private.conversion_mensual_por_vendedor` ignora ambos aportes;
- `private.metricas_conversiones_implementacion` los ignora;
- `crm.metricas_conversiones_equipo_fn` los ignora;
- `private.metricas_distribucion_leads_v3_core` los ignora.

Consecuencia directa: la exclusión manual publicada el 01/09 existe en la
tabla-base, pero se pierde al agregar. Para el 1–3 de septiembre, la suma de
`aporte_divisor` del núcleo da 281 y el agregador publicado vuelve a 289.

Además, `conversion_episodios` no limitaba los orígenes: `Oficina` y `Otro`
recibían aporte 1 en divisor y cierre. Por eso el núcleo anterior no cumplía
la aclaración Landing/Formulario/Referido. La migración publicada lo corrige.

## Arquitectura que debe conservarse

No se necesita una función ni una calculadora paralela. La corrección debe
hacerse dentro de las piezas existentes:

1. `private.conversion_episodios` decide una sola vez qué evento pertenece al
   núcleo y cuánto aporta;
2. los agregadores existentes suman `aporte_divisor` y `aporte_numerador`, sin
   volver a interpretar origen, referido, anulación ni tipo de operación;
3. las RPC existentes solo recortan período/rol y forman el payload;
4. el frontend presenta el porcentaje recibido y jamás lo recalcula.

## Análisis comercial del siguiente cambio — reportes de llegadas

Miguel aclaró que las pantallas de reportes deben mostrar **lo que llega al
negocio**. La cantidad de asignaciones o cambios de responsable no es una
medida de captación: un lead que pasa por tres analistas sigue siendo una
sola llegada. Los movimientos de reparto sirven a la trazabilidad operativa.

La unidad del reporte es el **lead único y su fecha original de ingreso**,
en hora de Lima. Cambiar de analista, reasignar, descartar o reabrir no crea
una llegada adicional ni mueve ese ingreso a otro período. El lead antiguo
que se trabaja nuevamente sigue perteneciendo a su período de ingreso; un
cierre posterior sí aparece en su fecha real de cierre como arrastre.

Hay que distinguir los conteos de personas/eventos de su aporte a la fórmula:

- «Leads que llegaron»: número de leads únicos de los orígenes admitidos,
  desglosado por Landing, Formulario y Referido y por alta automática/manual.
- «Base de conversión»: llegadas automáticas Landing/Formulario. Los Referidos
  y las altas manuales tienen su conteo visible aunque aporten cero al divisor.
- «Cierres»: cantidad real de cierres admitidos, con origen y procedencia.
- «Renovaciones» y «Upgrades»: cantidades reales de operaciones; los aportes
  ponderados se explican por separado. Diez renovaciones elegibles son diez
  operaciones y aportan 1,5 al numerador, no diez leads nuevos.
- «Conversión comercial»: índice ponderado con cierres, operaciones y ajustes
  del período. No equivale a «porcentaje de esas mismas llegadas que cerró»,
  porque admite arrastre y operaciones de clientes existentes.

La cosecha del lote ya existente responde esa última pregunta: de los leads
que llegaron en el período, cuántos cerraron. Debe nombrarse y presentarse
como esa lectura, sin sustituir la conversión ponderada ni crear un cálculo
independiente por pantalla.

La fecha final visible debe limitar también las operaciones de cartera. Una
consulta 1–3 no debe incorporar una operación del día 4 por pedir internamente
el mes completo. Mes calendario, rango libre y foto de mes cerrado deben
conservar explícitamente su período y su carácter vivo/sellado.

### Atribución individual confirmada por Miguel

Miguel aprobó expresamente: si llega a Ana y después pasa a Luis, **la llegada
queda solo en Ana**. El cierre se acredita a quien lo consigue. La primera
atribución se busca en todo el historial antes de recortar el ámbito, no en
la primera asignación que encuentre cada analista dentro del período.

Sin analista todavía, el lead sí cuenta en el total empresarial, sin inventar
una persona. También se guarda ese agregado en futuras fotografías mensuales.

## Implementación publicada por etapas

1. Núcleo existente: alta original, llegada única y primera atribución;
   exclusión de manuales y canales ajenos en el divisor; cierre a su autor;
   renovación ponderada como Referido; cartera limitada por fecha real.
2. Agregadores existentes: suman aportes publicados; los conteos de operaciones
   permanecen enteros. Resumen, Conversiones, Ranking y Distribución comparten
   esa base. Los demás consumidores mensuales reciben el cambio a través de
   la misma RPC mensual (HOY, Equipo, Directorio, Metas y alertas).
3. Frontend: contratos compatibles con fuente anterior y nueva; validación de
   la ponderación; etiquetas de llegadas/base automática y explicación de la
   renovación. No se creó otra calculadora de producción. La demo existente
   también conserva una sola llegada por lead.
4. Fotografías: las ya cerradas no se recalculan; conservan fuente y peso
   anteriores. Las nuevas guardan `modelo_conversion=llegadas_v2` y la base
   sin analista. La vista Cosecha continúa siendo una lectura viva del lote.

La migración reemplaza siete funciones, sin cambiar firmas, propietario,
permisos, volatilidad ni `search_path`. Comprueba las huellas del código antes
de aplicar y el perímetro después; un desvío aborta toda la transacción. No
modifica Auth, acceso al CRM ni datos operativos de leads/contratos.

Pruebas SQL en banco aislado `crm_llegadas_20260904`: reasignaciones múltiples,
leads antiguos, manuales, canales excluidos, referido/renovación, upgrades,
anulados, fechas Lima, cortes parciales, deduplicación cliente/mes, total sin
analista, RPC mensual, paridad con reportes y denegación por rol/sin sesión.
También se verificaron la lectura de fotos anteriores y nuevas. El banco usa
funciones reales de conversión y stubs para servicios ajenos (capital/Auth).
No equivale a una prueba integral contra producción.

Verificación final local: **2.650 pruebas Vitest aprobadas**, suite Playwright
completa en modo demo (**115 aprobadas, 26 omisiones previas, cero fallos**), typecheck,
build, verificación del bundle, cuatro pruebas de configuración de release,
control de duplicación y `git diff --check` aprobados. Lint sin errores, con
cuatro advertencias previas del carrusel; el build conserva avisos de tamaño
de chunks e importación demo. Calidad y E2E también aprobados en GitHub Actions
para el commit publicado `ff21967acd193c9b4d9de0b9dc4843f31280fb26`.

## Verificación de producción y reversión

Se conservó un respaldo probado de las siete definiciones y comentarios,
se publicó primero el frontend compatible, se purgó la caché de Hostinger y
se verificaron sus archivos antes de aplicar el SQL. Release
`crm-20260904T225440Z-ff21967acd19`; trazabilidad completa en
[[Deploy a Hostinger]] y [[Main unico - sincronizacion y publicacion 2026-09-04]].

Las respuestas reales pasan **7 pruebas adicionales contra los contratos
Valibot del frontend publicado**: mensual de Analista/Supervisor/Gerencia,
equipo de Supervisor/Gerencia, rango global y Distribución V3. Rango y
Distribución concilian 176/9/5,11; sus sondas y las de equipo devuelven
`cuadra=true` y `paridad_nucleo=0`.

Las pruebas de rol en producción fueron consultas de solo lectura con
`authenticated` y claims del actor dentro de transacciones revertidas:
Analista ve una fila propia; Supervisor, su equipo; Gerencia, el global.
**9 denegaciones esperadas** comprobadas para accesos de Vendedor,
Coordinación, sin sesión y `anon`. No se usaron contraseñas ni se hizo un
login con credenciales reales: se verificó visualmente la pantalla de acceso
pública, HTTP 200, campos y botón habilitados, sin errores de consola/página.
No había un perfil Directorio activo para una sonda productiva de ese rol;
su recorrido está cubierto en modo demo.

Las siete funciones conservan propietario, ACL, firmas, volatilidad y
`search_path`. Seguridad: **174 avisos antes y después, sin altas ni bajas**
(135 WARN, 39 INFO, 0 ERROR). Rendimiento: 5 WARN, 72 INFO, 0 ERROR.
En las 100 entradas recientes recuperadas de API y las 100 de Postgres tras
la publicación no hubo errores 5xx ni ERROR/FATAL/PANIC, respectivamente.
`crm.periodos_cerrados` mantuvo sus cero filas; las fotos anteriores y nuevas
se ejercitaron en el banco aislado, no cerrando un mes real.

Los meses cerrados y ajustes de anulaciones conservan su tratamiento: el
reporte de rango muestra flujo bruto y la RPC mensual aplica los ajustes
existentes. Las pestañas antiguas deben guardar el trabajo y usar el aviso de
actualización; no se forzó una recarga que pudiera perder una edición.

Si se requiere reversión, restaurar **primero el SQL anterior** desde
`releases/conversion-llegadas-predeploy-20260904.sql` y solo después volver al
frontend `crm-20260904T194458Z-d75be7b5d8d3`. El cliente viejo rechaza la nueva
fuente de llegadas: no debe revertirse únicamente el frontend.
