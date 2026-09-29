# Reasignación y conversión pendiente — 29/09/2026

**Estado: validada en rama remota y CI; pendiente de aprobación externa del PR #137.**

La migración `20260929201813_crm_reasignacion_conversion_consistente.sql` añade
un trigger privado AFTER UPDATE diferido al COMMIT a `crm.leads`. Una reasignación ya autorizada
por las puertas/RLS actuales lleva consigo el responsable de la persona y del
borrador de primera conversión, cuando su identidad e historia lo permiten.
Registra tramos, actividad y revisión con el actor real. La solicitud se revisa
mediante la RPC vigente; no duplica su lógica ni cambia datos/hash/autoría o la
saga de acceso. Una persona preparada sin solicitud también puede acompañar
al lead. Bandeja conserva el último responsable hasta la siguiente entrega.

## Reglas que conserva

- RLS y BEFORE de tenencia/reasignación siguen autorizando la operación original.
  El trigger revalida actor, destino activo y ámbito antes de mover la persona.
- No transfiere atribución económica, contratos ni inversiones confirmadas.
- Identidad ambigua, historial incorrecto, acceso inconsistente o gates de
  inversión mantienen su necesidad de conciliación: el bloque de excepción
  revierte todos los efectos de autosincronización, conserva el movimiento
  autorizado del lead y registra la actividad
  `reasignacion_conversion_requiere_revision`. No crea un estado de solicitud
  nuevo ni autoriza invertir. Esta es una limitación explícita de la reparación
  automática, no una promesa de que toda discrepancia histórica se resolverá.
- No insistir, identidad sin verificar y flags apagados no se sobreescriben.
  Con resolver OFF permanece el comportamiento anterior. Mantenimiento sin
  actor no imita a un gerente: registra la conciliación pendiente.
- Los errores de concurrencia sí abortan el movimiento completo con `40001`:
  el cliente existente los muestra como reintento. Candados de documento,
  persona, solicitud y recursos de acceso se adquieren sin espera tras el lead.
- Se ejecuta al cerrar la transacción, después del traslado canónico de una
  baja. Evita duplicar tramos o alertar por estados intermedios. Si hubo varios
  movimientos, procesa únicamente la asignación final. La toma directa sigue
  validada por su BEFORE vigente; su flag temporal ya se restauró al COMMIT.
- No cambia objetos de `public`, policies, grants de tablas, firmas ni tipos
  públicos. Función sin EXECUTE para PUBLIC/anon/authenticated/service_role.
- Dieciséis anclas rechazan la instalación si cambian contratos dependientes.

## Verificación local

Banco: base `reasignacion_conversion_v3_20260929` dentro de
`supabase_db_avancecorp-venta-cruzada`. Es una copia aislada del esquema y los
fixtures sintéticos del banco de venta cruzada, sin datos de producción.
No se instaló la candidata en la base original del contenedor.
La restauración necesitó dos autores históricos inactivos sintéticos para las
FK de configuración: no se desactivaron RLS/triggers ni se otorgaron permisos.

Ejecutar desde la raíz CRM, con Docker encendido y la candidata instalada:

```sh
docker exec -i supabase_db_avancecorp-venta-cruzada psql -U postgres -d reasignacion_conversion_v3_20260929 -v ON_ERROR_STOP=1 < supabase/scripts/reasignacion-conversion/test.sql
python3 supabase/scripts/reasignacion-conversion/concurrencia.py
docker exec -i supabase_db_avancecorp-venta-cruzada psql -U postgres -d reasignacion_conversion_v3_20260929 -v ON_ERROR_STOP=1 < supabase/scripts/reasignacion-conversion/guardas.sql
docker exec -i supabase_db_avancecorp-venta-cruzada psql -U postgres -d reasignacion_conversion_v3_20260929 -v ON_ERROR_STOP=1 < supabase/scripts/conversion-inversion/test-conversion.sql
```

`test.sql` y `guardas.sql` terminan en ROLLBACK. `concurrencia.py` trabaja
exclusivamente en el banco fijo: conserva una solicitud sintética y alterna su
analista entre A/A2, por lo que es repetible y conserva el historial del ensayo.

Resultados:

| Gate | Resultado |
| --- | --- |
| SQL con RLS real, roles/ámbitos, bandeja, toma, perfil, saga, lote mixto, baja, restricciones | PASS — 36 comprobaciones |
| Dos sesiones: persona/documento/solicitud bloqueados y reintento | PASS — 4 comprobaciones |
| Conversión económica vigente: cooperativa y Avance/Auth/contrato/cuentas/cronograma | PASS |
| Reversa y reinstalación | PASS |
| Guardas existentes | 27 PASS; 5 fallos previos idénticos; cero fallos nuevos |
| MSW del UPDATE + suite existente del store real | PASS — 88 pruebas |
| check:scripts, seed:preflight, test:rls:preflight, test:edge-preflight | PASS |
| SQL remoto / regresión económica remota | PASS — 36 comprobaciones / PASS |
| PostgREST real: ámbitos, veto y COMMIT alineado | PASS — 3 comprobaciones |
| test-rls.mjs remoto --contratos / --identidad-d5 | PASS — 287 / 30 comprobaciones |
| Advisors de la rama antes/después | PASS — cero avisos nuevos |
| Merge de la rama | PENDIENTE |
| CI Main actualizado: 318 archivos, 4.925 tests, tipos, build/bundle/duplicación | PASS — verify y preflight aprobados |
| E2E frontend | NOT RUN — sin cambio de código frontend de producto |

Los cinco fallos previos de guardas son: inventario de auditoría de 11 tablas
existentes, `cron.job` ausente en esta copia y tres suites de mutantes que exigen
`gestion_diaria.banco=on`. No se presentan como guardas aprobadas. Los preflights
seed/RLS usan configuración ficticia local y son offline, no sustituyen el gate
HTTP remoto. La comprobación MSW usa el código actual de cliente sin modificarlo.

## Publicación y reversa

Rama autorizada: `reasignacion-conversion-20260929`, ref `zlqywmvvtfknypkmfpbe`,
creada a las 21:45:59 UTC. Tarifa confirmada: US$0,01344/h. Su replay histórico
falló antes de instalar esta candidata; se reconstruyó el banco desde el esquema
vivo y fixtures sintéticos. La reconstrucción no es una migración para promover. Paridad previa del catálogo:
850 funciones, 332 triggers, 125 policies, 134 tablas/vistas y 7.668 grants
de columna. Las 22 Edge Functions conservan sus paquetes y configuración.
La matriz remota usa únicamente fixtures sintéticos; no se copiaron clientes.

Seguir `CLAUDE.md:51` y `supabase/migrations/LEEME.md:43`: rama Supabase → aplicar
la candidata exacta → matriz `test-rls.mjs` pertinente → advisors → merge.
Nunca instalar la migración directamente en producción. Si cambian las anclas,
revisar la diferencia; no quitar la protección para forzar la instalación.

`reversa.sql` retira solo el trigger y la función. Conserva todas las asignaciones,
actividades, solicitudes y tramos ya registrados. El problema puntual original
se corrigió por separado mediante las RPC vigentes; esta candidata previene
la desalineación en futuras conversiones elegibles.

## Recuperación de una conciliación pendiente

La nota es visible en el historial del lead: `lead-drawer.tsx` muestra `a.detalle`
para las actividades de tipo nota. El texto indica que Gerencia debe revisar el
responsable y el borrador antes de invertir. No se crea otra cola de trabajo.

Gerencia resuelve primero la causa indicada por los validadores (identidad,
restricción, saga o bandera). Después, en una transacción autenticada y con la
versión vigente del borrador, usa las puertas existentes
`crm.reasignar_responsable_relacion_fn(persona,analista,motivo)` y
`crm.revisar_solicitud_inversion_fn(solicitud,analista,revision,motivo)`.
No editar las tablas directamente ni borrar la nota histórica. El ensayo prueba
que el nuevo analista retoma la misma solicitud después de ese procedimiento.

## Revisiones independientes

Dos consultas al wrapper Claude, ambas `CHANGES_REQUESTED`, sin hallazgos de
fuga RLS ni permisos añadidos. El PRIMARY atendió las observaciones: rollback
selectivo de errores de negocio, pruebas de baja/lote/restricciones, ejecución
diferida para no duplicar historial, ancla del índice único ya existente,
consumidor de la nota y recuperación canónica probada, y candados oficiales.
No se afirma una tercera aprobación del reviewer: el cierre corresponde a los
checks reales del PRIMARY. Producción tenía cero enlaces canónicos sin
`leads.inversionista_id` al verificar este supuesto.

## Checkpoint de integración

[PR #137](https://github.com/avanza-digital/avancecorp-crm/pull/137), commit
`d34342cc9256265bfe08169b1090bfd474e490a3`, incorpora Main `7cae24e1`.
El 29/09 a las 22:44:29 UTC terminaron en PASS `verify`, `app-check`,
`cambios` y `preflight`. El merge normal fue rechazado por la aprobación
externa pendiente. No se usó override administrativo. Auto-merge no está
habilitado en este repositorio. La rama Supabase permanece para la promoción
tras aprobar e integrar; todavía no se instaló la candidata en producción.
