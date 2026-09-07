# Citas de Gerencia: correcciones comerciales y bases

El 7 de septiembre Miguel autorizó corregir los ocho puntos de [[Auditoria de Citas de Gerencia - frontend y contrato backend 2026-09-07]], después de aclarar qué requería frontend y qué requería ampliar la consulta existente. Se mantiene la instrucción de no crear funciones paralelas ni editar núcleos.

## Comportamiento acordado

1. **Totales conciliados.** La tabla conserva una fila «Fuera del desglose actual» con la diferencia entre el total servido y los responsables visibles; muestra también el total del período. No elimina citas históricas ni inventa porcentajes para esa diferencia.
2. **Cierres anteriores identificados.** Se conserva la regla vigente: primer cierre reconocido y no anulado dentro del horizonte, desde la hora programada de la última cita realizada del prospecto en el rango. El cierre 20 segundos anterior no se reclasifica sin evidencia de otra hora real. Se cuenta aparte como cierre anterior; no incrementa el indicador de cierres posteriores ni su capital.
3. **Una métrica principal.** Realización de citas presenta el porcentaje recibido y su base computable. Asistencia queda en un detalle desplegable, con su propia base de realizadas más inasistencias registradas.
4. **Estados separados.** Las vencidas sin resultado tienen un indicador propio; las reprogramadas muestran su cantidad y nueva fecha, sin mezclar el pendiente de cierre.
5. **Bases por analista.** La misma consulta entrega vencidas, divisor y exclusiones por sistema, otro asesor y reprogramación, además de próximas. La interfaz muestra esos campos y el porcentaje servido. Si faltan, indica «Base no disponible»; no deduce el divisor de un porcentaje redondeado.
6. **Próximas con alcance explícito.** El rótulo dice «dentro del período»; no representa toda la agenda futura.
7. **Capital con alcance explícito.** «Capital asociado a estos cierres» es acumulado sin recorte por fecha, para los prospectos que cumplen la atribución de cierre y en la moneda del prospecto. No equivale a captación del período ni a todo el capital de los atendidos.
8. **Resultado registrado.** Sustituye «Resultado final»; interesado, seguimiento o propuesta describen el resultado guardado de la cita.

Los cierres previos se buscan en el mismo conjunto que ya consulta el agregador, desde el inicio del rango. El seguimiento de cierres posteriores puede superar el final del rango y llega hasta el momento de consulta, presentado en hora de Lima. No se añadió tolerancia horaria ni se cambió a una regla por día calendario.

## Servidor y contrato

Migración canónica y ledger MCP: `20260907194622_crm_citas_gerencia_bases_y_alcance.sql`. El archivo se creó con la CLI y, antes de su primer commit, se alineó al identificador asignado por MCP; no se reaplicaron efectos ni se modificó el ledger. SHA-256: `615e9e8cb8dc63729899ca6e719755bbfdfcd9947583f8ad64164b7b86f42665`.

Solo se reemplazó `private.metricas_reuniones_implementacion(date,date)`: MD5 `6e8935eae3cf1a4c049a93cb20e1f3bd` → `cec7ee9ec1c31ddd8fa17f1d42e88fc1`. Se proyectan bases existentes y se agrega `leads_con_cierre_previo` a total, modalidades y orígenes. La fachada, firmas, OID, propietario, ACL y search_path se conservan. Huellas de los núcleos protegidos, verificadas antes y después:

- Citas: `ea636888a266941e959f26c6a5727216`.
- Conversión: `8a2549dbfa59c732da04900ed90b6361`.
- Capital: `b8f375fbb377582835f4cfe222240c5b`.
- Fachada: `de328143bd9221fb19bfa6af46695290`.
- Filtro de responsables: `2652303501f4e7ca1d55d37ede3fd24a`.

El contrato frontend acepta las nuevas proyecciones como opcionales para permitir reversión y respuestas anteriores. Rechaza bases incompatibles, un desglose mayor al total y cierres previos más posteriores que excedan su base. No calcula porcentajes comerciales.

## Verificación

- Banco PostgreSQL 16 aislado, sin conexión externa: funciones reales capturadas para Citas, Conversión, agregador, fachada y filtro; dobles declarados de Auth, catálogo y Capital. Prueba cierre 20 segundos antes, a la hora exacta, posterior al rango, última cita entre dos, anulación, cita sin prospecto, responsable histórico, exclusiones, roles, guardas, reversión y reaplicación. Todos los campos antiguos conservan paridad. No se presenta este banco como integración completa del núcleo de Capital.
- Producción: agosto y septiembre conservan todos los campos anteriores, salvo la hora de generación. Las respuestas nuevas pasan el esquema frontend. En el corte de verificación, septiembre muestra 7 de 43 computables (16.3%), 7 de 35 con asistencia registrada (20%), 6 vencidas sin resultado y 5 próximas dentro del rango. Hay 0 cierres posteriores de 7 prospectos y 1 cierre anterior. Agosto conserva 48 pactadas y 6 realizadas: 4 pactadas y 1 realizada están fuera del desglose vigente.
- Advisors: seguridad 210 → 210 y rendimiento 89 → 89, sin avisos nuevos.
- Frontend: 3.030 pruebas en 208 archivos aprobadas, tipos, compilación, configuración de release y auditoría de bundle aprobados. Dos recorridos nuevos de Citas aprobados, con escritorio, móvil, teclado y respuestas anteriores.
- El control global de duplicación conserva 40 clones y 702 líneas duplicadas, iguales al commit base; excede el umbral previo de 0.8%. Cuatro avisos previos de accesibilidad en coverflow. La suite antigua `graficas.spec.ts` tiene expectativas obsoletas de Resumen y carece de respuestas simuladas de Rentabilidad; sus fallos ocurren fuera de Citas. La nueva suite prueba directamente este apartado.

Evidencias locales completas (incluidas respuestas con datos internos): `CRM-Avance-Corp/releases/citas-ocho-evidencia/`. Banco reproducible: `supabase/scripts/test-citas-gerencia-local.py` con el JSON capturado de funciones y la migración. Reversión guardada: `supabase/scripts/rollback-citas-gerencia-bases-y-alcance.sql`, protegida por huella y permisos; el frontend tolera los campos ausentes después de revertir.

Publicación del frontend y comprobación en sesión real: en curso. Se construirá desde un commit limpio idéntico a Main y `avancecorp/main`, conservando las publicaciones anteriores y el trabajo UX pendiente. Véase [[Deploy a Hostinger]] y [[Main unico - sincronizacion y publicacion 2026-09-04]].
