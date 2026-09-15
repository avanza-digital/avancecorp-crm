# Revisión real para la apertura Multiempresa

Estado: **conciliación retrospectiva PASS; G7 ABIERTO; apertura general pendiente**.
Miguel autorizó continuar la revisión y preparar la apertura a todos los analistas.
Esta entrega no activa banderas, no registra inversiones, no modifica permisos y
no atribuye firmas humanas. No creó un banco remoto ni generó un cargo adicional.

## Resultado comprobado

Corte: **15/09/2026, 15:07:13 Lima**. Postflight: **15:16:43 Lima**.

| Control | Resultado |
|---|---|
| Cartera, Capital y lector F7 | 613 fuentes en cada uno; cero diferencias de fuente, empresa, moneda, importe, atribución y fecha de imputación |
| Empresas | Avance 589, Prodelco 6, Qorilazo 18 |
| Identidad | 467 personas canónicas; ninguna fuente incoherente ni duplicada; todas tienen un identificador vigente marcado como verificado |
| Muestra retrospectiva | 20 fuentes de 19 personas: 10 Avance, 5 Prodelco, 5 Qorilazo |
| Ficha productiva | 19 fichas y sus 25 inversiones completas; cantidades/importes/atribución/fechas coinciden con el núcleo, fuentes estables antes/después |
| Cuentas | 18 analistas, 3 supervisores, 2 Gerencia, 1 coordinador; 24 cuentas vigentes verificadas en Auth |
| Capacidades F5/F6 | Exactamente los cuatro participantes nominales; ningún acceso nuevo para los otros veinte |
| Sin responsable | Dos personas, tres inversiones; Gerencia puede leerlas y no puede abrir una inversión nueva sin asignación |
| Mes sellado | Agosto: 16 filas, mismas huellas antes/después |
| Conservación | Siete definiciones, cinco banderas y control nominal idénticos entre capturas |

La muestra toma la fuente más reciente de cada persona por empresa y elige diez
personas Avance y cinco de cada cooperativa. Una persona aparece en ambas
cooperativas: son 19 personas únicas. Las fichas incluyen otras cinco inversiones
de esas mismas personas; por eso se verificaron 25 inversiones al abrir las fichas.
No es una selección consecutiva de veinte operaciones nuevas del piloto.

## Qué acredita y qué queda abierto

El maestro exige veinte inversiones confirmadas y consecutivamente conciliadas;
no dice literalmente que todas deban crearse después de encender el piloto.
Esta revisión acredita volumen, identidades y paridad interna de datos reales
existentes. No acredita por sí sola veinte ejecuciones del nuevo flujo F8 ni
permite declarar completa su aceptación operativa.

Desde el inicio nominal hay diez altas Avance de analistas ajenos al piloto y
una alta Qorilazo del piloto; en F4 existe una solicitud confirmada. La única
persona con más de una empresa sigue siendo el caso Prodelco → Qorilazo ya
comunicado por Miguel. En el histórico también existen 145 transiciones Avance
→ Avance, distribuidas en 103 personas. No se detectaron Avance → Qorilazo,
Qorilazo → Avance ni Qorilazo → Prodelco.

No hay cotitulares reales en las tablas neutral/contractual, solicitudes de
retiro ni anulaciones comerciales reales en las superficies consultadas.
Hay 89 upgrades y uno cuyo analista atribuido difiere del vendedor registrado;
eso identifica un candidato de revisión, no demuestra toda la gestión de
reasignación ni su intención humana. Las 23 personas sin perfil de Portal no
son automáticamente identidades provisionales: todas las 467 están activas y
tienen un identificador marcado como verificado.

Hay 588 fuentes antiguas sin relación F4 explícita, admitidas por la lectura
histórica. No son fuentes perdidas: están incluidas y conciliadas. Nueve fuentes
Avance no tienen analista histórico; esto es distinto de las dos personas sin
responsable actual. No se reasignó ni corrigió ninguna por inferencia.

G7 conserva pendientes los recorridos operativos, la aplicación de la evidencia
de casos especiales a esta fase, la cobertura específica de reintentos/carreras,
Auth/HTTP/UI productivos, soporte/reversa operativa y las conformidades humanas.
Las pruebas sintéticas anteriores son antecedentes técnicos, no firmas ni
operaciones reales. No deben crearse ventas, retiros o anulaciones ficticias en
producción para completar una casilla.

[Complemento tras revisión](complemento.json): se fijó el inicio del acta para
el recuento acumulado y se comprobó la autoría, separada de la atribución. Las
seis filas de desglose del núcleo coinciden con las operaciones; las tres
renovaciones completas suman el capital de sus contratos. Las nueve renovaciones
históricas sin desglose siguen pendientes, sin inventar importes. Los 89 upgrades
son inversiones adicionales y no tienen puente de capital renovado/adicional.
El candidato de atribución a otro analista coincide en Capital/Cartera y conserva
el autor registrado; no se reprodujo su reasignación ni se firma esa intención.

## Método y archivos

- [conciliar.sql](conciliar.sql): transacción REPEATABLE READ READ ONLY; compara
  núcleos publicados con NUMERIC y `EXCEPT ALL`, conservando multiplicidad.
- [conciliacion.json](conciliacion.json) y [postflight.json](postflight.json):
  recibos saneados del corte y comprobación posterior; sin nombres/documentos,
  UUID de clientes, referencias contractuales ni importes individuales.
- [verificar-fichas.sql](verificar-fichas.sql): muestra fijada por huellas del
  corte, RPC productiva con Gerencia nominal y `SET LOCAL ROLE authenticated`.
- [verificar-roles.sql](verificar-roles.sql): capacidades F5/F6 para las 24 cuentas
  activas; comprueba metadata Auth, sin contraseñas, tokens ni sesiones nuevas.
- [verificar-casos.sql](verificar-casos.sql): personas sin responsable y cobertura
  de casos especiales. Sus [resultados](casos.json) no contienen datos personales.
- [verificar-evidencia.mjs](verificar-evidencia.mjs): verifica capturas y produce
  [verificacion.json](verificacion.json), con hashes SHA-256. No conecta a la BD.
- [guardias.json](guardias.json): huellas de controles y roster para preparar una
  futura activación; no es una autorización ni un script de encendido.
- [complemento.sql](complemento.sql): ancla acumulada del acta, autoría y
  confirmaciones F4, desglose, candidato reasignado y huellas de dependencias.

Las RPC necesitan bloqueos de filas y registran lecturas: se ejecutaron en
READ COMMITTED con **ROLLBACK**, sin persistir la auditoría de ensayo. La prueba
inicial de capacidades con READ ONLY devolvió `25006` en postventa; fue un error
del ejecutor, corregido antes del recibo final. Otro diagnóstico usó por error
`empresas.codigo` en lugar de `clave`; no escribió datos. No son fallos de producto.

La conciliación es **paridad interna**, no una revisión de comprobantes físicos
ni de contabilidad externa. Se compararon importes registrados, no se recalculó
rentabilidad o pagos. Las comisiones continúan fuera del CRM. Las lecturas SQL
no prueban login JWT/HTTP, clics, caché o visualización humana.

## Validación de esta entrega

SQL de conciliación, roles, fichas y casos: PASS con los límites anteriores.
Verificador de recibos: PASS. Build/frontend, RLS general, nuevas carreras
económicas y Auth/UI productivos: NOT RUN; este cambio agrega diagnóstico y
documentación, sin cambiar producto ni esquema. No se reabrieron ni reinstalaron
los bancos cerrados de F4–F8.

La apertura sigue el [procedimiento pendiente](APERTURA.md) y la
[acta G7](../ACTA-G7.md). No se han ejecutado cambios productivos de activación.
Claude entregó CHANGES_REQUESTED; [evaluación PRIMARY](EVALUACION-REVIEW.md)
con correcciones, matices y pendientes. El dictamen no se reescribió como PASS.
