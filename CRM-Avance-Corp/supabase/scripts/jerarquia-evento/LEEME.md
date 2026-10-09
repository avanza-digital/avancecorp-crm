**Estado (09/10/2026): en banco, sin aplicar.** Verificación completa en el banco Docker: ver la entrada 20261009223000 de `supabase/migrations/MIGRACIONES.md` (ensayo 22/22, mutante 10/22, negativas, gate sin rojos nuevos, auditor-rls sin P0/P1). Huellas medidas.

# Facturación fase 2: historia de todo cambio de supervisor

**Estado: en banco, sin aplicar.** Entrega preparada el 09/10/2026; banco **NOT RUN** por
el implementador (encargo sin Docker, red, producción ni otros agentes). Claude PRIMARY
debe medir las cuatro huellas nuevas y ejecutar el ciclo completo antes de aplicar.
No hubo commit ni push. No se editaron migraciones ya versionadas.

La garantía excluye a quien desactive los triggers o use
`session_replication_role = replica`.

## Archivos

- `../../migrations/20261009223000_crm_jerarquia_evento_en_toda_via.sql`: transacción
  con preflight, instalación y postflight; se niega ante estados parciales o deriva.
- `generar-cuerpos.py`: verifica las cinco huellas de `vivo/` y modifica solo dos cuerpos
  con sustituciones de ocurrencia única. `--verificar` no escribe.
- `reversa.sql`: restaura las dos RPC exactas de `vivo/`, quita los dos triggers y los
  dos ayudantes; idempotente, sin `CASCADE`, sin borrar eventos ni `schema_migrations`.
- `ensayo-sintetico.sql`: 22 aserciones en modo migrado; una aserción adicional (c0)
  en modo original. Guarda de banco vacío, fixtures propios y `ROLLBACK`.
- `vivo/`: evidencia recibida, conservada al byte.

## Decisiones implementadas

`private.trg_equipo_evento_jerarquia()` es el único escritor de
`jerarquia_actualizada` en estos flujos. Los dos triggers de `crm.equipo` son
`AFTER ... FOR EACH ROW`, con `WHEN`: INSERT con supervisor no NULL y UPDATE OF
supervisor_id solo si cambió. No se crean eventos por asignar el mismo valor.
La FK que ejecuta SET NULL también dispara el UPDATE.

El autor es `coalesce(auth.uid(), private.actor_sistema_eventos())`. El UUID reservado
para **sistema** es **`f6d2941b-2e93-4c81-9a27-0c5e786b104d`**. No tiene perfil en
`public`; no se crea identidad ni se añade FK. Una cascada con sesión conserva el
autor humano; sin `auth.uid()` se atribuye a sistema, incluido `service_role` sin sujeto.
Los dos ayudantes son de `postgres`, tienen `search_path` vacío y EXECUTE solo de
`postgres`; el del trigger es SECURITY DEFINER y el del UUID es IMMUTABLE INVOKER.

Las RPC pasan `p_idempotencia` y `p_perfil_id` en los GUC transaccionales
`crm.evento_jerarquia_idempotencia` y `crm.evento_jerarquia_objetivo` justo antes
de escribir equipo. El trigger solo usa y consume el recibo si coincide el objetivo.
Otra fila no lo consume; después del consumo, un nuevo cambio genera otro UUID.
El `INSERT` directo en `crm.usuario_eventos` no tiene `ON CONFLICT`: una colisión
revierte también la modificación del equipo. El detalle contiene solamente
`supervisor_anterior`, `supervisor_nuevo` y `via` (`rpc`/`automatica`), con tope de
4096 bytes comprobado también por la restricción existente de la tabla.

Las búsquedas de repetición de las dos RPC quedan **al byte**: actor, acción e
idempotencia siguen encontrando el evento del trigger. El alta sigue encontrando
rol, jerarquía y activación con el mismo recibo. `test-usuarios-jerarquia.sql` **no
se modifica**: permanecen 4 eventos con perfil nuevo (candidato, rol, jerarquía y
activación) y 3 con perfil existente. Cambia quién escribe la jerarquía, no su cantidad.
La respuesta repetida conserva los datos y cambia `idempotente` de false a true,
como antes; el ensayo compara el resto del JSON y prueba el reintento con versión antigua.

## Huellas de origen verificadas offline

| Función | MD5 de `pg_get_functiondef` recibido |
| --- | --- |
| `crm.actualizar_jerarquia_usuario_fn` | `79c43d9888cf0d54b92eb26e8b46c3af` |
| `crm.registrar_vendedor_usuario_fn` | `c3b73f85fdd791534d6edcc5015b14ff` |
| `crm.fijar_membresia_activa_fn` | `9be9925a221e64119b21e0f6a299ceb9` |
| `private.registrar_evento_usuario` | `8c423da784e0ff61e7eb91c896d851f2` |
| `crm.facturacion_diaria_fn` | `4b11e1da336f2f296c81f064ce30e35b` |

El preflight exige las cinco; las tres de solo lectura se verifican también al final.
Las cuatro funciones afectadas se controlan por dueño, ACL exacta, `prosecdef`,
volatilidad, lenguaje y `search_path`. Los triggers no tienen ACL/dueño independiente:
se comprueban la tabla, la función, el estado habilitado y **toda** la salida de
`pg_get_triggerdef`, incluido `WHEN` (no basta con `tgtype`). Se normalizan solo
espacios, mayúsculas y paréntesis de presentación en los dos predicados simples.
Reaplicar y repetir la reversa ejecuta estos controles; no acepta estados mixtos.

## Procedimiento para Claude en banco

Desde `CRM-Avance-Corp`, sin modificar `vivo/`:

```bash
python3 supabase/scripts/jerarquia-evento/generar-cuerpos.py --verificar
python3 supabase/scripts/jerarquia-evento/generar-cuerpos.py --medicion
```

`--medicion` **solo emite SQL**, con guarda de banco vacío y `ROLLBACK`. Ejecutar
esa salida en el banco Docker a paridad. Instala transitoriamente las cuatro
definiciones para consultar sus MD5, sin cambiar ni omitir el postflight real.
Copiar las cuatro huellas resultantes en `jerarquia_funciones`, tanto en la
migración como en la reversa, sustituyendo cada `PENDIENTE_MEDIR_EN_BANCO` de su
función. El generador comprueba que los dos catálogos permanezcan idénticos.
**Los marcadores pendientes provocan el aborto del postflight y deshacen todo**;
no sustituirlos con huellas calculadas sobre texto sin canonicalizar.

Con `psql -X -v ON_ERROR_STOP=1` conectado exclusivamente al banco local:

1. En estado original, ejecutar `ensayo-sintetico.sql` con
   `PGOPTIONS='-c ensayo.jerarquia_sin_migracion=on'`: (c0) debe dar PASS
   porque la baja traslada dos subordinados sin registrar jerarquía. Cerrar la conexión.
2. Medir/completar huellas; aplicar la migración dos veces: instalación y repetición.
3. En conexión sin la opción de (c0), ejecutar `ensayo-sintetico.sql`: esperar 22 PASS.
4. Ejecutar `test-usuarios-jerarquia.sql` con sus fixtures habituales y la matriz RLS
   pertinente. Los conteos 4/3 se mantienen.
5. Ejecutar la reversa dos veces; verificar las dos huellas originales, ausencia de
   los cuatro objetos nuevos y conservación de cualquier evento previo.
6. Repetir (c0), reaplicar y repetir el ensayo normal.
7. Probar rechazo por huella viva alterada, estado parcial, EXECUTE extra y trigger
   sin WHEN/deshabilitado, cada mutación en transacción deshecha. No dar PASS a un
   guardián solo por la presencia del texto de su comprobación.

El modo (c0) no borra ni deshabilita triggers: exige las dos RPC originales y
ausencia de los objetos nuevos. La ejecución normal se niega si falta la migración.
Ambos modos abortan antes de sembrar si `public.contratos` tiene una sola fila.

## Cobertura y límites del ensayo

Incluye (a) RPC y repetición; (b) alta nueva y sobre perfil existente, con sus
repeticiones; (c) baja con dos subordinados, Gerencia y vía automática;
(d) UPDATE sin sesión con autor sistema; (e) UPDATE sin cambio; (f) INSERT NULL;
(g) purga por `crm.purgar_membresia_crm` con SET NULL; (h) dos cambios de una fila;
(i) colisión real de la UNIQUE dentro de subbloque, comprobando reversión de toda
la fila de equipo y ausencia de evento parcial; (j) Facturación con Gerencia,
venta anterior S/ 1000 para el saliente y posterior S/ 2000 para el reemplazo.
Además verifica INSERT con supervisor y consumo/acotación de GUC entre filas.

Para (g) el subordinado es otro **supervisor**, que admite NULL. Un vendedor activo
sin supervisor es rechazado por una guarda preexistente; no se cambia esa regla.
Para (j) se fecha anteayer el evento de alta **sintético** de los dos subordinados;
la baja produce su propio evento hoy. Las ventas se siembran como contratos legacy
propios, ayer/hoy, siguiendo el ensayo de baja de analista y con los triggers activos.
Se ejecutan los constraints diferidos antes del rollback.

Se preservan los límites del diseño: Facturación atribuye por **día de Lima**, no
por instante (el día del cambio pertenece al nuevo supervisor); un tramo NULL usa
el supervisor actual. No se reconstruyen cambios históricos nunca registrados.
Los GUC son metadatos internos del flujo, no una frontera de autorización contra
un escritor SQL privilegiado. No se cambia ninguna de estas reglas.

## Verificación de esta entrega

- **PASS:** MD5 de los cinco archivos vivos; generación y cotejo exacto de los dos
  cuerpos nuevos y las dos restauraciones; cabeceras/precondiciones conservadas;
  catálogo y comprobaciones comunes de migración/reversa iguales.
- **PASS:** sintaxis Python; cinco copias con huella alterada rechazadas y dos
  patrones con multiplicidad incorrecta rechazados; salida de medición con cuatro
  funciones y `ROLLBACK`; `git diff --check` y espacios de los archivos nuevos.
- **PASS:** preflights offline `seed:preflight` y `test:rls:preflight`, con valores
  ficticios de entorno y sin conexiones. El primer intento sin entorno se detuvo
  por falta de `SUPABASE_URL`; la repetición offline pasó.
- **NOT RUN:** ejecución/compilación SQL en PostgreSQL, 22 casos del ensayo y (c0),
  aplicar/reaplicar/revertir, matriz RLS real, medición de huellas, advisors y review
  externo: prohibidos los accesos/servicios necesarios por este encargo.
- Frontend/build/E2E y regeneración de tipos no aplican a esta entrega: no cambia
  ninguna firma ni payload de RPC, tabla o columna expuesta. No hay cambios en `app/`.

Pendiente para Claude: medir las huellas, confirmar los invariantes de catálogo en
su banco y ejecutar los ensayos. No hay decisiones de negocio abiertas; permanecen
los límites diarios/NULL explícitos del encargo.
