# Control posterior al cierre real de jornada

24/09/2026, 18:58:18–18:58:23 Lima. **PASS: las RPC vigentes ya no
autorizan presentar ni posponer avisos después del cierre de las 18:00.**

Se consultó `crm.gestion_diaria_avisos_fn()` para los tres supervisores
efectivos, bajo el rol `authenticated` y el contexto de cada cuenta. La
transacción fue de solo lectura y usó el reloj real. No se registraron
entregas, reconocimientos ni aplazamientos durante la auditoría.

| Cuenta anonimizada | Casos de mañana pendientes | Casos de tarde pendientes | Puede presentar o posponer | Aplazamientos guardados hoy |
| --- | ---: | ---: | --- | ---: |
| A | 4 | 7 | No | 1 |
| B | 0 | 0 | No | 0 |
| C | 0 | 5 | No | 0 |

Los casos históricos pueden conservar el estado «pendiente» después del
cierre; eso no los habilita para emitir otro aviso. Los avisos existentes
informaron `fin_jornada = 2026-09-24 18:00:00-05:00`,
`puede_presentar = false` y `puede_posponer = false`. El aplazamiento de la
cuenta A sigue persistido. Ninguna de las tres cuentas tenía un reconocimiento
humano registrado ese día; no se atribuye uno como ejecutado.

La consulta también confirmó que F5 aún no está instalada en producción.
La primera versión del guion usó REPEATABLE READ y fue rechazada con `0A000`:
la identidad unificada exige READ COMMITTED para su candado compartido.
Se corrigió únicamente el aislamiento de la auditoría, conservando READ ONLY.
La consulta final pasó mediante el conector SQL; el CLI previo no llegó a
completar su inicialización de conexión.

Esta evidencia acredita el servidor después de las 18:00. No se presenta como
una nueva sesión manual, una observación visual del popup ni una prueba a las
18:00 exactas. Complementa el [corte de las 16:00](CORTE-1600.md) y la
auditoría anterior de persistencia. **Pendiente:** corte único real del sábado
26/09, que no se sustituye con un reloj simulado.

[SQL ejecutada](cierre-1800.sql) · [resultado agregado](cierre-1800.json).
