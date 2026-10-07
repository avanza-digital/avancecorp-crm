# Tasa del nuevo upgrade Avance — 07/10/2026

**Implementado y probado en local y en la rama Supabase autorizada.**
El usuario confirmó que el registro de upgrades debe respetar el interruptor de
solicitudes de tasa que ya existe. No se creó otra configuración ni se activó enforcement.

## Regla y pantalla

El contrato activo elegido aporta la tasa de referencia. Se crea otro contrato
para el aporte adicional; el anterior conserva capital, tasa y cronograma.

- Solicitudes desactivadas (`observacion`): tasa editable inferior o superior,
  sin solicitudes ni consumo de aprobaciones. Una solicitud pendiente no bloquea.
  Se mantienen los límites numéricos y el tope vigentes.
- Solicitudes activadas (`enforcement`): una tasa menor o igual a la referencia
  se admite al registrar el nuevo upgrade. Una superior usa «Solicitar tasa
  superior», motivo y aprobación de Gerencia. Una pendiente sigue bloqueando.
- La referencia se precarga desde el origen, se actualiza al elegir otro contrato
  y no sustituye la tasa pactada al recuperar un borrador.
- Las renovaciones y cooperativas mantienen sus reglas. Una corrección de un
  contrato emitido no obtiene permiso para rebajar su tasa.

## SQL y compatibilidad

Migración: `../../migrations/20261007180108_crm_upgrade_tasa_flexible.sql`.
Se generó con el CLI de Supabase; sustituye tres cuerpos de `private` mediante
huellas completas y anclas únicas. Conserva propietario, ACL, firmas, search_path,
SECURITY DEFINER y volatilidad. No altera tablas, triggers ni policies de `public`.
El trigger existente registra origen y `tasa_inferior_sin_excepcion` en el ledger.

La respuesta conserva `tasa_minima_sin_autorizacion = tasa_base` para upgrades,
porque el CRM anterior rechaza un mínimo inferior en esa propiedad. La nueva
capacidad `tasa_minima_upgrade_sin_autorizacion` vale 0.01 para upgrade y null
en las otras categorías. El CRM nuevo comprueba categoría, regla, origen y tasa
de referencia antes de usarla. Sin capacidad sigue aplicando el comportamiento
anterior. El servidor nuevo conserva compatibilidad con el frontend anterior.

Censo de envoltorios productivos por SELECT: `crm.resolver_tasa_fn` devuelve
la resolución y `crm.resolver_tasa_lead_fn` añade `lead_id/bloqueo_conversion`.
Solicitar tasa, validar conversión y observar rentabilidad extraen claves
concretas; no requieren un objeto cerrado. Se inspeccionó `ResolucionTasaSchema`
en `e511d30504f24045aa28230a2d2eb03891bdf967`: utiliza `v.object`. El build vivo
consultado fue `build-20261007T152927260Z`, correspondiente a esa publicación.
La forma SQL sigue siendo `jsonb`, sin cambios de firmas/tablas que regenerar.

## Banco y pruebas

`banco.mjs` solo admite la base Docker `upgrade_tasa_20261007` del contenedor
`supabase_db_avancecorp-pr190-20261006`, con comentario de identidad obligatorio
`BANCO LOCAL upgrade tasa 20261007`. Se creó como copia del fixture sintético
`upgrade_cooperativas_20261006`; nunca usa una URL remota. Los tres cuerpos
originales coincidieron con producción y están en `base-funciones.json`.
No se modificó la base fuente. La copia queda disponible para repetir el ensayo.

```sh
node supabase/scripts/upgrade-tasa/banco.mjs test
node supabase/scripts/upgrade-tasa/banco.mjs reversa
node supabase/scripts/upgrade-tasa/banco.mjs carrera-reversa
```

`aplicar` instala una vez; `retirar` restaura el original únicamente en este banco.
`test.sql` usa actores sintéticos autenticados, la RPC contractual real y
`ROLLBACK`; no desactiva triggers. PASS: referencia 18, altas 0.01/16/18,
20 rechazado sin aprobación, origen ausente rechazado, renovación conserva piso,
trazabilidad, contrato anterior íntegro, vendedor no puede aprobar, pendiente
bloquea ON y deja operar OFF, tope 25, reactivación, consumo único y corrección
de capital manteniendo la tasa sin permitir rebajarla.

`reversa.sql` espera primero las escrituras de contratos y después bloquea el
ledger. Se niega si ya hubo un upgrade inferior bajo enforcement o si hay deriva
de funciones. PASS: restauración exacta y reaplicación, incluidos ACL/comentarios;
negativa tras primer uso; lock_timeout ante escritor concurrente, sin cambios.

## Verificación y publicación

- PASS: `npm run check` completo en la copia limpia de Main: lint, typecheck,
  6.364 tests con cobertura, configuración de release, service worker, build,
  bundle y duplicación (0.44 %). Se integró `avancecorp/main` antes de validar.
- PASS: 23/23 E2E locales Docker del flujo, sin retries, en la corrida final de
  `upgrade-tasa.spec.ts`, `solicitud-tasa.spec.ts` y `f5-cartera.spec.ts`.
  Los seis nuevos casos pasan por el parser real con RPC simuladas; el ensayo SQL
  separado usa las RPC contractuales reales. Capturas de escritorio y móvil revisadas.
- PASS: `check:scripts`, `test:edge-preflight`, `seed:preflight`,
  `test:rls:preflight`, sintaxis del banco y whitespace del diff.
- PASS: mismo `test.sql` en la rama temporal `upgrade-tasa-20261007`, con
  transacción y rollback, datos sintéticos, reglas activadas y desactivadas.
- Advisors de la rama: sin nuevos avisos de SQL atribuibles a esta migración.
  Los avisos de funciones DEFINER y tablas con RLS sin policies son anteriores.
  La advertencia de protección de contraseñas filtradas también existe en producción.
  No se cambió Auth, la política de tasas ni el código de las 22 Edge Functions.
- Gate de realidad: el CLI reportó falta de lectura de `periodos_cerrados`;
  la consulta equivalente de solo lectura confirmó **0 metas bajo el sello**.
  Permanece el dato preexistente de 275 clientes sin domicilio legal: para un
  nuevo contrato se exige completar ese dato, como ya ocurría antes.

La rama remota nació con el fallo histórico de replay de la migración 87. Se
reconstruyó exclusivamente su esquema desde producción, sin clientes, conservando
las 436 migraciones previas. Las diferencias esperadas del entorno se limitan a
los default ACL del rol gestionado `supabase_admin`, que no cambia esta migración.
Se restauraron los permisos efectivos de tablas/secuencias y el texto CRLF de
una restricción antes del ensayo. El seed canónico se completó con la receta de
contratos históricos y producto técnico del repositorio, sin relajar los triggers.

El usuario autorizó publicar y confirmó el costo de la rama temporal y su fusión
si las pruebas pasan. La suite E2E completa, la matriz RLS y el estado final de
publicación se registran en el acta `PUBLICACION.md` al cerrar el release.

Codex PRIMARY implementó; un Codex SECONDARY_REVIEWER realizó dos consultas sin
escribir. P1 del parser antiguo: corregido con capacidad compatible y tests HTTP.
P2 de concurrencia en reversa: aceptado, añadido bloqueo previo de contratos y
ensayo concurrente PASS. No se inició una cadena de otros agentes.
