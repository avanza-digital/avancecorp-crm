# F8 — revisión de las 14 fuentes pendientes

Revisión administrativa **de solo lectura**, completada el 13/09/2026 a las
19:52:10 Lima. Producción conserva sus datos y el piloto continúa sin instalar
ni activar. El resultado identifica las correcciones; **no certifica que los
enlaces ya estén resueltos**.

Seguimiento del mismo día: correspondencia multirrol confirmada y procedencia
documental investigada. El [SQL de los diez reales](identidades/README.md) fue
aprobado y [aplicado con verificación posterior](identidades/APLICACION-2026-09-13.md).
Quedan cuatro huecos demo. Los resultados siguientes conservan el diagnóstico
original; las pruebas están en [la verificación del completado](identidades/VERIFICACION.md).

## Resultado

La consulta [revision-identidades.sql](revision-identidades.sql) se ejecutó en
una transacción `REPEATABLE READ READ ONLY`, con timeouts y `ROLLBACK`. El motor
confirmó `transaction_read_only = on`. Encontró 598 fuentes: 593 reales y cinco
demo, con diez reales y cuatro demo sin identidad coherente.

| Grupo | Movimientos | Fichas de origen | Hallazgo | Siguiente tratamiento |
|---|---:|---:|---|---|
| Avance posterior a la carga F2 | 7 | 5 perfiles cliente | DNI con formato válido y único entre todos los perfiles; sin identificador ni lead asociado | Preparar completado dirigido por perfil y documento de la fuente |
| Qorilazo posterior a F2 | 1 | 1 lead | El cierre tiene DNI válido; el lead convertido tiene DNI vacío. No hay otro perfil, identificador ni lead con ese DNI | Preparar identidad desde el documento del cierre y enlace coherente del lead y cierre |
| Avance multirrol | 2 | 1 perfil cliente | El DNI aparece también en una cuenta de analista. Miguel confirmó que es la misma persona | Enlazar el perfil cliente y conservar la cuenta y permisos de analista separados |
| Demo Avance | 3 | 2 perfiles | Un perfil sin documento y otro con un DNI de cuatro caracteres | Mantenerlos clasificados como prueba; resolver el tratamiento de cobertura demo |
| Demo Qorilazo | 1 | 1 lead | Cierre de prueba ya clasificado técnicamente; documento con formato válido, sin identidad | Mantener la clasificación demo, sin convertirlo en identidad real |

Los diez movimientos reales corresponden a **siete fichas de origen**, no a
diez clientes distintos. Las cuatro fuentes demo corresponden a tres fichas.
La partición no usa similitud de nombres, teléfono o correo: agrupa por
`perfil_id` o por el enlace ya existente entre cierre y `lead_id`.

**Ninguno de los catorce casos tiene hoy un identificador documental coincidente**,
ni vigente ni histórico, incluyendo la búsqueda del mismo número entre tipos.
Por tanto, no hay una ficha canónica existente que pueda seleccionarse solo
mediante esa búsqueda. Formato válido no equivale a documento verificado.
La comprobación ampliada de las 20:02:51 Lima conservó los mismos catorce
movimientos, documentos, importes, monedas, estados y vínculos. También buscó
el número documental en todos los cierres: no apareció ningún cierre adicional
ni identidad canónica alternativa por esa vía.

## Causa y evidencia

Los cinco perfiles Avance y el cierre Qorilazo del primer grupo se crearon
después de la carga F2 del 03/09 a las 19:33:10 UTC. No tienen entrada en
`crm.backfill_multiempresa_mapa`. Sus ocho movimientos son posteriores a ese
corte. Esta observación explica que no entraran en aquella carga histórica;
no demuestra por sí sola el comportamiento de todas las puertas de alta actuales.

Los dos movimientos multirrol comparten **un mismo perfil cliente**, con una
entrada F2 clase E: `documento compartido con otro perfil (multirrol/colision)`.
La segunda cuenta es de analista, está activa, tiene cero contratos y tampoco
tiene identidad neutral. Miguel confirmó «sii son la misma» a la pregunta
específica sobre ambas cuentas. Los nombres se conservan únicamente en el
anexo privado; la confirmación resuelve la correspondencia, no aplica enlaces.

El cierre real Qorilazo ya referencia su lead convertido. El nombre coincidente
es contexto, no prueba de identidad. El DNI que puede sustentar el enlace está
en el cierre. La revisión encontró el lead activo, sin veto, sin perfil, sin
identidad y sin puente previo. Antes de escribir se deben revalidar también
el vendedor, su pertenencia activa al equipo y cualquier cambio concurrente.

## Propuesta de corrección

1. **Ocho movimientos sin colisión:** preparar un completado limitado a los
   cinco perfiles y al cierre real identificados, con procedencia documental,
   preimagen exacta, auditoría y reversa ensayada. La propuesta adopta el criterio
   histórico de F2: **documento procedente del perfil cliente o del cierre
   económico de confianza**, con fuente, actor y decisión registrados. El SQL
   propuesto deberá hacer explícita esa aceptación de procedencia antes de
   llamar al resolutor con `p_verificado = true`; no significa verificación
   contra un registro externo ni se deduce solo del formato. Se revalidarán
   formato, unicidad, ausencia de conflictos y preimagen bajo los candados
   pertinentes. No se ejecuta el backfill global. La conformidad comercial y
   financiera G6 se conserva, con el alcance de su corte; no se usa como prueba
   documental nueva.
2. **Dos movimientos multirrol:** con la correspondencia confirmada por Miguel,
   `crm.inversionistas.perfil_id` será el **perfil cliente**. La cuenta de
   analista no se enlazará a esa identidad ni obtendrá permisos por su DNI.
   La decisión multirrol quedará registrada con motivo y autor; se comprobará
   por RLS que el analista conserva únicamente su ámbito. No se fusionan
   cuentas Auth ni se amplía acceso por coincidencia de documento.
3. **Cuatro fuentes demo:** el gate actual de F5 y la candidata F8 comprueban
   todas las fuentes, también las demo. Tres movimientos demo carecen de
   documento válido, mientras el contrato F0 §4.3 prohíbe crear identidades
   operativas sin documento verificado. Por ello no se deben fabricar DNI ni
   insertar identidades vacías para obtener un gate favorable.

El plan principal ya dispone excluir las pruebas del universo real mediante
su clasificación técnica. La solución a diseñar para el tercer grupo debe
alinear esa exclusión con la cobertura y las lecturas de F5/F8, conservando las
fuentes históricas y el bloqueo de cualquier hueco **real**. No basta añadir un
filtro al encendido: hay que comprobar listados, ficha, conteos, detalle,
permisos y el caso de una persona con fuentes reales y demo. **Esa corrección
de comportamiento todavía no está implementada ni ensayada.** La candidata
actual sigue bloqueada por las cuatro fuentes demo; los diez huecos reales se
resolvieron posteriormente mediante el lote dirigido autorizado.

La clasificación demo tampoco puede convertirse en una salida para un hueco
real. La futura corrección deberá comprobar su procedencia y la autorización
para cambiarla, registrar las fuentes excluidas y probar el intento de marcar
como demo una fuente real sin identidad. No se añade un simple filtro sin
control de la clasificación ni se cambia la exclusión histórica de métricas.

### Inversiones y altas posteriores

La función vigente `private.cartera_f5_fuentes()` admite fuentes históricas sin
fila F4 en `crm.inversiones`: puede resolver Avance por `inversionistas.perfil_id`
y cooperativas por el cierre o el lead. Por eso un `inversion_id` nulo **no es
por sí solo el bloqueo F5/F8**. El gate exige una identidad canónica única;
no comprueba el documento verificado y no sustituye al resolutor F3.

El plan de escritura debe decidir explícitamente el espejo relacional del
cierre y cualquier otro completado F4 necesario; reutilizar su derivación
vigente para fecha comercial, estado, titulares y primera conversión. No
copiar `es_primera_conversion = true` de la migración F2 histórica ni inventar
fechas. Exigir paridad pre/post de fuentes, capital, atribuciones y conversiones
en el mismo corte, incluido el corte G6; un cambio posterior de ventas no se
confunde con una diferencia causada por el completado.

La candidata F8 **ya incorpora sincronización de altas legadas, incluso de
usuarios ajenos al equipo piloto**, mientras el control está vigente:
`private.inversiones_escritura_bajo_candado()` usa
`private.piloto_f8_control_activo()` y la operación nueva se restringe por actor
en `private.inversion_persona_autorizada()`. Los bancos local y remoto comprobaron
el control y los ámbitos de esa sincronización, no un alta económica completa
de extremo a extremo. No está instalada en producción. Entre la corrección
de datos y el encendido todavía hay que repetir el censo y cerrar la carrera
con el protocolo de activación; no se afirma que una fotografía antigua cubra
las ventas posteriores. No hay evidencia en esta revisión para declarar que
todo alta durante el futuro piloto romperá la cobertura.

Antes de cualquier escritura productiva se prepararán el SQL exacto y sus
pruebas, se actualizará el censo y se cumplirá la confirmación de SQL exigida
en el vault `Inicio.md`. No se cambia una migración ya versionada.

El contrato de ese completado exige además:

- **READ COMMITTED**, que es el aislamiento asumido por el resolutor; no
  reutilizar el `REPEATABLE READ` propio de este diagnóstico.
- Preimágenes por clave, búsqueda de colisión entre tipos bajo una protección
  que cubra las puertas escritoras y abortar si aparece una identidad que no
  estaba en la revisión. El resolutor puede devolver una identidad existente;
  el completado deberá detectarlo y no enlazarla silenciosamente.
- Registrar por caso el canal y actor de captura del documento y sus cambios,
  o dejar explícita la falta de esa evidencia antes de aprobar el SQL. Este
  diagnóstico no investigó esa trazabilidad y no la deduce de `creado_en`.
  Usar una `fuente` específica para la aceptación documental histórica F8.
- Probar las altas legadas con documento inválido durante el piloto: una
  excepción del resolutor puede rechazar el alta completa; no se presume que
  deje una inversión confirmada sin enlace. Vigilar rechazos y cobertura, y
  exigir un censo nuevo para cualquier reanudación tras suspensión o vencimiento.

## Evidencia privada

Directorio local, fuera de Git:

`~/Desktop/Revision F8 - identidades 2026-09-13/`

- `revision-privada.json`: fotografía de la consulta, con nombres, referencias
  y documentos necesarios para localizar cada caso.
- `revision-privada-verificada.json`: segunda lectura con la búsqueda ampliada
  de cierres y coincidencias de número entre tipos documentales.
- `Revision de identidades F8.html`: informe para Miguel, con los catorce
  movimientos y la propuesta por grupo.

Directorio con permisos `700`, archivos con `600`. Git y el review de Claude
solo reciben el diagnóstico agregado y código sin datos personales. Los
números de caso pertenecen a esta fotografía; las futuras guardas de escritura
deben usar las claves y preimágenes exactas del anexo, no posiciones de fila.

## Verificación

- PASS: consulta ejecutada en producción con solo lectura impuesto por el motor.
- PASS: conteo independiente previo, 10 reales + 4 demo, y partición por claves
  de origen: 7 + 1 + 2 + 3 + 1 = 14 movimientos.
- PASS: segunda ejecución de la consulta corregida; mismas preimágenes de
  identidad y hechos económicos en los catorce casos, y ningún cierre adicional
  por documento. La búsqueda por número en leads distingue DNI de una señal
  de colisión CE/PASAPORTE y no los considera identidades equivalentes.
- PASS: Claude, segunda consulta, para el cierre **como diagnóstico**. La
  primera pidió precisar la propuesta; el PRIMARY evaluó sus hallazgos y
  añadió evidencia. [Decisiones y límites del review](REVISION-INDEPENDIENTE-IDENTIDADES-2026-09-13.md).
- PASS: parseo local del HTML, catorce filas únicas y catorce detalles,
  contenido escapado, sin scripts ni recursos externos, permisos privados y
  `git diff --check`.
- NOT RUN: revisión visual en navegador. Browser no pudo iniciar por una
  referencia a un `browser-service.mjs` de una versión anterior inexistente.
  No se modificó la configuración del navegador; el parseo local no sustituye
  una revisión visual.
- NOT RUN: aplicación de correcciones, pruebas de mutación, RLS de una nueva
  implementación y activación del piloto. Esta entrega no modifica runtime,
  permisos, esquema ni datos y no sustituye esos gates futuros.
