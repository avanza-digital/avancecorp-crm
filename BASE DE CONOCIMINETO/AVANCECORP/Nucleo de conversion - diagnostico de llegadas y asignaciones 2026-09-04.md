---
tags: [crm, conversion, nucleo, diagnostico, origenes]
actualizado: 2026-09-04
estado: implementado-local-publicacion-pendiente
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

**Estado:** implementado en backend y frontend locales mediante la migración
`20260904210831_crm_conversion_llegadas_unicas.sql`. Publicación pendiente;
producción todavía conserva el comportamiento documentado en el diagnóstico.

La fórmula comercial acordada, para un mismo período y ámbito, es:

`100 × (cierres Landing/Formulario + peso × cierres Referido + peso × renovaciones elegibles + upgrades elegibles − ajustes aplicables) / llegadas Landing/Formulario automáticas únicas`

La aplicación de ajustes conserva el tratamiento vigente de anulaciones y su
suelo en cero. Con divisor cero, la tasa queda sin base para calcularse;
los cierres y las operaciones siguen mostrándose en sus propios conteos.

## Evidencia de producción — 1 al 3 de septiembre de 2026

Consulta agregada de solo lectura, ventana Lima
`[2026-09-01 00:00, 2026-09-04 00:00)`:

- Formulario: 110 altas, de las cuales 6 fueron manuales; **104 llegadas automáticas**.
- Landing: 74 altas, de las cuales 2 fueron manuales; **72 llegadas automáticas**.
- Total de llegadas automáticas Landing + Formulario: **176**.
- Referido: 1 alta manual; por la regla vigente no entra al divisor.
- Fuera del núcleo comercial: 1 Oficina + 12 Otro.

El agregador publicado devolvió divisor **289**, compuesto por:

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

El diagnóstico anterior presentó **9 / 176 = 5,11 %** usando siete cierres de
lead y dos upgrades. La corrección del peso de renovaciones no cambia esa
aritmética, porque esas dos operaciones son upgrades. Sin embargo, el 5,11 %
debe tratarse como cálculo preliminar: la consulta de operaciones usó todo
septiembre (`p_periodo`) y aún debe verificarse su fecha dentro del rango 1–3.
No había ajustes pendientes por anulaciones de meses cerrados en la
verificación. Ese índice tampoco significa que nueve de las 176 llegadas se
convirtieron: incluye operaciones de clientes existentes y puede incluir
cierres de leads que llegaron antes.

## Cómo estaba construido en producción antes del cambio

`private.conversion_episodios` emite tres clases de fila:

1. `recibido`: una fila por pareja analista/lead con asignación en la ventana;
2. `cierre`: un cierre del ledger, con anulado en cero y Referido ponderado;
3. `operacion`: primera renovación/upgrade elegible por cliente y mes.

La relación ya publica `aporte_divisor` y `aporte_numerador`. En particular,
marca con divisor cero los Referidos y las altas manuales Landing/Formulario.
Sin embargo, los consumidores no suman esas columnas: vuelven a reconstruir la
fórmula con `tipo` y `fue_referido`.

Verificado en producción el 2026-09-04:

- `private.conversion_mensual_por_vendedor` ignora ambos aportes;
- `private.metricas_conversiones_implementacion` los ignora;
- `crm.metricas_conversiones_equipo_fn` los ignora;
- `private.metricas_distribucion_leads_v3_core` los ignora.

Consecuencia directa: la exclusión manual publicada el 01/09 existe en la
tabla-base, pero se pierde al agregar. Para el 1–3 de septiembre, la suma de
`aporte_divisor` del núcleo da 281 y el agregador publicado vuelve a 289.

Además, `conversion_episodios` no limita los orígenes: `Oficina` y `Otro`
reciben aporte 1 en divisor y cierre. Por eso el núcleo actual todavía no
cumple la aclaración Landing/Formulario/Referido.

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

## Implementación local por etapas

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

Verificación final local: **2.650 pruebas Vitest aprobadas**, cuatro recorridos
Playwright en modo demo (Analista/Supervisor/Gerencia/Directorio), typecheck,
build, verificación del bundle, cuatro pruebas de configuración de release,
control de duplicación y `git diff --check` aprobados. Lint sin errores, con
cuatro advertencias previas del carrusel; el build conserva avisos de tamaño
de chunks e importación demo. No se ejecutó un despliegue ni un login real.

Antes de publicar: conservar respaldo de las siete definiciones, publicar
primero el frontend compatible, comprobar el bundle nuevo y la recarga de
clientes existentes, aplicar la migración y contrastar los tres roles contra
el mismo rango. No se debe publicar SQL nuevo con un cliente viejo que exige
el literal de asignaciones. Los meses cerrados y ajustes de anulaciones
conservan su tratamiento; el reporte de rango muestra flujo bruto y la RPC
mensual aplica los ajustes ya existentes.
