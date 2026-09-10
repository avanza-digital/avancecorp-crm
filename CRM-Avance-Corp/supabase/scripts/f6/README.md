# F6 — postventa por persona

**Implementada y ensayada localmente. SQL F6 no instalado en producción.**
La instalación crea `postventa_neutral=false`; no enciende F4, F5 ni el piloto.
Miguel autorizó también la publicación F6 apagada. El ensayo remoto detectó el
bucle de reintentos `40001` de PostgREST 14; se corrige antes de publicar.

## Resultado

- Hoy, Agenda y ficha comparten las mismas tareas. Las nuevas gestiones pueden
  pertenecer a una persona sin fabricar un lead o un perfil Portal.
- Cierre, próxima acción, reprogramación y confirmación conservan revisión,
  responsable vigente e historial. Veto global cancela los pendientes; levantarlo
  no los revive. La cola sin responsable corresponde a Gerencia.
- Vencimientos separados por empresa y moneda; renovación/upgrade Avance
  conservados. Reinversión cooperativa enlazada a su inversión anterior y
  confirmada por F4 con capital/depósito nuevos.
- Solicitud y revisión administrativa de retiro trazadas. No paga, liquida ni
  modifica el capital de la inversión. Comisiones fuera del sistema.
- Los envíos pendientes conservan actor, clave y contenido durante una pérdida de
  respuesta. Se consulta el recibo antes de reintentar; un resultado desconocido
  no habilita otro envío diferente. El servidor vuelve a comprobar el actor.

## Artefactos

- [SQL exacto](../../migrations/20260910150039_crm_f6_postventa_persona.sql), una
  transacción: dos columnas en `crm.tareas`, cinco tablas CRM cerradas con RLS y
  auditoría, doce RPC nuevas y seis integraciones con funciones existentes.
  No altera objetos `public`, fuentes financieras, Auth o inversiones históricas.
  SHA-256: `b88987c481119593f2dd5b0908aafff1e965f67e35455301a5bb56d91e6256cd`.
- Correctivas [HTTP 409](../../migrations/20260910190000_crm_f6_conflicto_http_sin_reintento.sql)
  y [consulta de recuperación](../../migrations/20260910191000_crm_f6_consulta_conflicto_http.sql):
  traducen `40001` a `PT409` en las fronteras F6 y sus cuatro trámites F4. Conservan
  el rollback, las firmas y ACL; F4 ordinaria conserva su contrato. Requieren OFF.
- [Reversa operativa](reversa-operativa.sql): apaga únicamente F6. Conserva datos,
  recibos e historia; la sincronización de identidad/responsable sigue operativa.
- [Base productiva leída el 10/09](base-productiva-2026-09-10.json): las seis huellas
  y ACL anteriores coinciden con las precondiciones del SQL y del ensayo local.
  Es evidencia de compatibilidad, no una instalación ni un gate remoto F6.
- [Aceptación y límites](ACEPTACION.md), [evaluación independiente](REVISION.md).
- [Recorrido manual pendiente](REVISION-MANUAL.md).
- `integrar-tipos.mjs`: compara/integra dieciocho nodos introspectados. Conserva
  contratos ajenos de Main que no están en la base sintética, incluidos los de Tasa.

## Reproducir el ensayo

Se utiliza exclusivamente el banco sintético F4/F5 existente en
`/private/tmp/avancecorp-f5-bank`: API `127.0.0.1:58321`, Postgres
`127.0.0.1:58322`, contenedor `supabase_db_avancecorp-f5-bank`.
`../f5/banco-local.mjs` rechaza destinos externos y claves ajenas al emisor demo.
El dump y los fixtures se conservan en el respaldo privado, fuera de Git.
No ejecutar estos scripts contra personas o dinero reales.

Desde `CRM-Avance-Corp`, con F4/F5 y F6 instaladas en ese banco:

```sh
node --test supabase/scripts/f6/postventa.test.mjs
node --test supabase/scripts/f6/reinversion.test.mjs
node --test supabase/scripts/f6/integridad.test.mjs
node --test supabase/scripts/f6/concurrencia.test.mjs
node --test supabase/scripts/f6/revision.test.mjs
node supabase/scripts/f6/replay-local.mjs
node supabase/scripts/f5/verificar-banco.mjs
npm run check:scripts
npm run seed:preflight
npm run test:rls:preflight
npm run test:edge-preflight
```

Los 43 tests usan Auth, PostgREST y Postgres reales. El banco remoto usa las mismas
aserciones, cambiando únicamente transporte SQL/HTTP y fixtures ficticios.
Se ejecutan en el orden mostrado: integridad utiliza el recibo creado en postventa.
Corren en serie
porque comparten banderas/fixtures; las carreras internas sí usan sesiones SQL
simultáneas. `finally` restaura banderas; los ensayos transaccionales hacen rollback.
Los antecedentes ficticios de otros casos se conservan en este banco descartable.

`replay-local.mjs` restaura `base-sintetica.dump` en una base nueva dentro del
contenedor, aplica las dos migraciones F5 y luego los tres archivos F6, compara funciones/ACL/datos,
prueba la reversa y elimina esa copia en `finally`. No hace replay global del
ledger ni cambia la base HTTP que utiliza el navegador.

Los preflights de seed/RLS requieren las variables del banco sintético. No son
pruebas de conexión a producción. Para tipos, desde `CRM-Avance-Corp`:

```sh
supabase gen types typescript --db-url postgresql://postgres:postgres@127.0.0.1:58322/postgres --schema public,crm > /private/tmp/avancecorp-f6-tipos.ts
node supabase/scripts/f6/integrar-tipos.mjs /private/tmp/avancecorp-f6-tipos.ts --verificar
```

Desde `CRM-Avance-Corp/app`:

```sh
npm run check
npm run test:e2e -- --workers=4
```

Los E2E usan el cliente real del frontend con respuestas sintéticas interceptadas;
no sustituyen los ensayos anteriores de servidor. Las capturas en `evidencias/`
contienen personas inventadas. La lectura manual con VoiceOver aprobada en F5
no se presenta como una aprobación manual de F6.

La agenda mantiene una cota de 2.000 pendientes neutrales, ordenados por
vencimiento, igual al límite del lote legado. El frontend registra la alarma
cuando alcanza el tope. Los vencimientos tienen paginación propia de 25 filas.

## Instalación posterior

1. Obtener aprobación del SQL concreto y comprobar su huella. Integrar Main con
   `avancecorp/main` sin sobrescribir trabajo remoto; construir desde el mismo
   commit verificado. No utilizar `origin/main`, `tronco`, release branches ni
   force push. El push del código no instala el SQL.
2. Preparar un branch Supabase autorizado, sembrar antes de aplicar, comprobar
   las seis bases/ACL y ensayar el archivo exacto con sus pre/postcondiciones.
   Ejecutar la matriz RLS pertinente y advisors. Registrar cualquier diferencia
   contra la línea base; los preflights offline no sustituyen estos gates.
3. Publicar primero el frontend compatible: tolera F6 ausente exclusivamente
   mediante `PGRST202`, sin ocultar errores distintos. Con F6 apagada mantiene
   el circuito anterior.
4. Volver a comprobar el padre y el commit antes del merge. Instalar sólo los tres
   archivos F6 mediante merge de branch; no `apply_migration` directo, `db push`,
   reparación del historial ni replay indiscriminado.
5. Verificar objetos reales, ACL, RLS, banderas OFF, fuentes, Auth e identidades.
   Archivar evidencia y eliminar el banco remoto temporal. La activación necesita
   resolver los quince huecos reales, conciliación F7/G6 y piloto F8/G7.

El apagado operativo no elimina la historia ni vuelve a conceder escrituras
directas. Una corrección posterior al commit requiere otra migración.
