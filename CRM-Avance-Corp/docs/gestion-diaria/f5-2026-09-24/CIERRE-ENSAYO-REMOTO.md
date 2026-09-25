# F5 — Ensayo remoto concluido; producción pendiente

24/09/2026, 19:31 Lima. Reanudación después de la pausa solicitada por Miguel.
La autorización conservada cubre la misma organización y **US$5 como máximo
total** para el banco temporal. Después del ensayo, Miguel autorizó el SQL
F5 concreto y `$release-crm`, una vez aprobada la revisión y pasados los controles
de GitHub. Esa autorización persiste; todavía no se ejecutó la promoción.

## Resultado y alcance

**PASS:** SQL y oráculo, matriz candidata de 2.267 aserciones, 21 solicitudes
HTTP con siete inicios de sesión Auth reales de actores sintéticos, tipos,
catálogo, permisos y comparación de advisors. Una sonda adicional de solo
lectura concilia once propiedades del tablero con actividades y tareas crudas.
La reversa transaccional ya pasó en el primer banco sobre la misma candidata;
no se presenta como una segunda ejecución.

SQL exacto: `20260924201358_crm_gestion_diaria_pulso_habitos.sql`.
SHA-256: `5f904c2b9b492b72fdb1ff1815aac2376d881939d6a8eaed938d1404380bf6b2`.
Fuente integrada con Main `a1bbe24d46a607ef472671b985931af059ccc1e4` (PR #93),
en el commit de integración `e523085ec3e985d1f8c2a5b36c96b0551ef0d2e8`.
Las modificaciones F5 permanecieron iguales; los tipos incorporaron también
el contrato de venta cruzada de Main. No se desplegó F5 en producción.

## Banco reproducido y límites

Rama `gd-f5-cierre-20260924`, ID `a4451cca-48a6-4630-81c7-8356b5d635a9`,
proyecto `ozmxjmjopdnyhxsecmvf`, organización `fzxtxnkvslpcsscxqfbr` y padre
`dctqcbznekcyxhjujuci`. Creada sin datos el 24/09 a las 23:54:05 UTC.

El aprovisionamiento automático terminó `MIGRATIONS_FAILED`: solo había 86
migraciones, sin usuarios ni leads. No se atribuye un replay completo exitoso.
Se restauró el banco sintético prístino anterior, después de volver a capturar
el catálogo productivo mediante lectura. Este seguía idéntico: 761 funciones,
123 tablas y 355 migraciones. El respaldo sintético SHA-256
`2421af7ece21889556d8cc8b6cd4af08ac1715609464f66fe381ef6042833b27`
contenía siete leads y cinco tareas antes de cada matriz; nunca se copiaron
filas comerciales reales.

Se reconstruyeron los actores Auth sintéticos y permisos, se desactivaron los
dos cron del banco y se retiraron 88 privilegios adicionales heredados de la
plantilla. El cotejo de cuerpos, estructuras y permisos precedió al registro
del ledger canónico de 355 versiones. Solo se normalizaron paréntesis
equivalentes de tres CHECK históricos, documentados en el ensayo anterior.
Esta conciliación no equivale a haber repetido cada migración operacional.

La candidata añadió doce funciones y cambió dos cuerpos. Se verificaron 773
funciones, tablas/políticas/roles y permisos originales conservados, 356
migraciones con las 355 anteriores intactas, SQL exacto en el ledger y cron OFF.
Tras la matriz se restauró la candidata prístina y se reconciliaron 40 permisos
EXECUTE de funciones públicas reintroducidos por los defaults del restore;
el cotejo final volvió a pasar antes del contrato HTTP.

## Evidencias

Los enlaces siguientes apuntan a resultados saneados. En los logs versionados
solo se normalizaron espacios finales y líneas vacías al final; los originales
permanecen en el checkpoint privado. Respaldos, credenciales
y catálogos completos permanecen fuera de Git; las credenciales de la rama
eliminada fueron retiradas.

| Comprobación | Resultado y evidencia |
| --- | --- |
| Baseline idéntico al padre | [PASS, 761 funciones / 123 tablas / 355 migraciones](remoto-cierre/paridad-baseline.json) |
| Matriz baseline del primer banco | [PASS 2.226](remoto/matriz-baseline.json), conservada como antecedente; no se atribuyen 2.267 a esa ejecución |
| Matriz candidata con el script actual de Main #93 | [PASS](remoto-cierre/matriz-candidato.json), [2.267 aserciones, cero fallos](remoto-cierre/matriz-candidato-20260925000556096.log); el script de Main añade 41 comprobaciones |
| Oráculo SQL F5 | [PASS](remoto-cierre/sql-f5.log): fechas, paridad, permisos, hábitos, pendientes completos y reconciliación |
| Delta después de la matriz | [PASS](remoto-cierre/delta-f5-final.json): doce funciones nuevas, dos cuerpos cambiados, ninguna tabla/política/rol/permisos ajenos alterados |
| Auth y HTTP remotos | [PASS 21 solicitudes / 7 actores](remoto-cierre/http-f5.json): lectores, roles denegados, anónimo, fechas, revocación con el mismo JWT y ámbito propio/ajeno de supervisión |
| Sonda de conciliación | [PASS once controles](remoto-cierre/sonda-conciliacion.json): 9 llamadas, 8 útiles, 5 contestadas, 2 leads únicos, 3 citas y 1.008 tareas vencidas |
| Tipos regenerados | [PASS](remoto-cierre/tipos-cotejo.json): las dos RPC F5 coinciden con el cliente integrado con Main #93 |
| Reversa | [PASS en el primer banco](remoto/sql-reversa-resultado.json), misma huella SQL y mismos cuerpos originales |
| Advisors | [PASS sin avisos nuevos](remoto-cierre/advisors-delta.json); no acredita ausencia de deuda previa |

La sonda no sustituye las pruebas de comparación histórica, hábitos,
navegación o permisos negativos. Los ensayos usan datos sintéticos y no
demuestran el rendimiento ni la conciliación de una F5 productiva aún ausente.

## Advisors y diagnósticos conservados

Seguridad conserva 67 avisos INFO de RLS sin políticas, dos WARN por funciones
DEFINER ejecutables por anon, 226 por authenticated y un WARN por protección
de contraseñas filtradas desactivada. Son previos; F5 no los corrige ni los
aprueba. Referencias: [Database Linter](https://supabase.com/docs/guides/database/database-linter)
y [protección de contraseñas](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).

Rendimiento no añade avisos estructurales: 53 FK sin índice, dos initplans,
dos tablas sin PK, cinco políticas permisivas múltiples y un ajuste de
conexiones Auth ya existían. Los índices sin uso bajan de 218 a 212 tras las
pruebas; depende de estadísticas, no de una corrección de índices. `pg_trgm`
está en `extensions` en el banco y en `public` en el padre; esa diferencia de
plataforma se mantiene explícita.

El error del primer guion HTTP (`row_to_json(uuid)` por colisión del alias)
ocurrió antes de enviar solicitudes y quedó en la [pausa](PAUSA-2026-09-24.md).
Corregido el alias del guion temporal, las 21 solicitudes remotas pasaron.
Dos consultas diagnósticas posteriores a la raíz OpenAPI devolvieron 401;
no forman parte del contrato RPC ni acreditan la versión menor del servidor.
Por eso este cierre habla de PostgREST remoto sin atribuirle una versión.

## Coste y retirada del banco

Rama eliminada y ausencia comprobada a las **00:31:22 UTC del 25/09**
(19:31:22 Lima del 24/09). [Recibo](remoto-cierre/cierre-rama.json).
La rama ajena `banco-f7` se conservó. No queda un banco F5 remoto facturable.

Estimación a US$0,01344/h: US$0,008350 en esta rama + US$0,011024 de la anterior
= **US$0,019374 acumulados**, inferior a US$5. Es una estimación temporal,
no una factura ni un comprobante de cargos efectivos.

## Siguiente puerta

Revisión normal de GitHub pendiente. SQL concreto y flujo `$release-crm`
autorizados por Miguel después del cierre, condicionados a esa aprobación
y a los controles pasados. Para promover, recrear una rama
dentro del mismo tope restante, volver a cotejar el padre vigente y garantizar
que el único delta de migraciones sea F5. Usar merge nativo de rama; nunca
`apply_migration` directo a producción ni un `db push` general. Si cambia el
padre o el SQL, repetir los controles afectados antes de promover.

Después del servidor, construir y publicar el frontend desde Main limpio e
idéntico al remoto. Verificar archivos, recorrido vivo y sonda de conciliación;
recién entonces fijar T0 del [registro de observación F3–F5](../OBSERVACION-F3-F5.md).
F6 no ha acumulado ningún día de su semana obligatoria y Seguimiento sigue vigente.
