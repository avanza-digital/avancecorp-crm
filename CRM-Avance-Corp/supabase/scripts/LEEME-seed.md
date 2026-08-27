# Sembrar una branch para el gate de RLS

Receta completa y probada el **2026-08-15** contra la branch `cierre-mes`
(`adiuadljotrdrzmpdyag`). Sin esto, montar una branch usable cuesta media tarde
de callejones sin salida.

```bash
export SUPABASE_URL="https://<ref>.supabase.co"
export SUPABASE_ANON_KEY="..."
export SUPABASE_SERVICE_ROLE_KEY="..."
export CRM_DEMO_PASSWORD="algo-de-12-o-mas"

npm run seed:demo        # avisa de UNA cosa que no puede hacer (ver abajo)
#   → ejecutar el bloque SQL de «Baja historica»
npm run test:rls
```

Las llaves y la cadena de psql de una branch salen de:

```bash
npx supabase branches get <branch-id> --project-ref <ref-de-produccion>
```

---

## Baja historica de `vendInactive`

**El seed avisa y sigue; este bloque lo completa.** Hay que correrlo por psql
(pooler en el 5432) despues de `npm run seed:demo`:

```sql
begin;
alter table crm.equipo disable trigger user;
update crm.equipo set activo = false
 where perfil_id = (select id from public.perfiles
                     where nombre_completo = 'VENDEDOR INACTIVO');
alter table crm.equipo enable trigger user;
update public.perfiles set activo = false
 where nombre_completo = 'VENDEDOR INACTIVO';
commit;
```

### Por que hace falta

El fixture `inactiveOwned` describe a **alguien que ya tenia leads abiertos
cuando se fue del equipo**. Es un estado HEREDADO, de los que existen de verdad
en una base con historia — y es justo el que `testOffboardingMatrix` tiene que
medir.

El esquema actual cierra **las dos vias** para construirlo, y las dos con razon:

| Orden | Que lo bloquea |
|---|---|
| asignar el lead y **despues** dar de baja | `20260807203740`: «La membresia conserva dependencias activas; reasigna antes de desactivar» |
| dar de baja y **despues** asignar el lead | `0C`: «El analista destino no existe, no esta activo o no puede recibir leads» |

Las dos reglas son correctas —en la vida real se reasigna antes de dar de baja—
pero juntas hacen el estado inalcanzable por escritura normal. El seed no puede
hacerlo desde PostgREST: no tiene forma de apagar un trigger.

⚠️ **Apagar el guardia NO lo relaja**: se apaga para una sola sentencia y se
vuelve a encender en la misma transaccion. Ese guardia es, ademas, una de las
cosas que el gate mide inmediatamente despues.

---

## Trampas de montar una branch (medidas el 15/08)

1. 🔴 **La branch nace con la replica de migraciones a medias.** Se queda en
   `MIGRATIONS_FAILED` en `20260812000259_crm_cierres_externos`, cuyo postflight
   ejecuta flujos de negocio completos y necesita datos que una branch sin datos
   no tiene. Quedan aplicadas 86 de 90.
   **Salida:** aplicar a mano las que falten **sin sus bloques `do $postflight$`**
   (son auto-pruebas que ya corrieron de verdad al aplicarse a produccion; el DDL
   va intacto) y registrarlas en `supabase_migrations.schema_migrations`.

2. ✅ **Y despues COMPROBAR que la copia es fiel**, que es lo que de verdad
   importa. Esta consulta tiene que dar lo MISMO en la branch y en produccion:

   ```sql
   select md5(string_agg(f, '|' order by f)) as huella, count(*)
   from (
     select n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')='||md5(p.prosrc) as f
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('crm','private')
   ) t;
   ```

   El 15/08 dio `be33cf5296e008c5b948f7d598d1dab1` / 189 funciones en las dos.

3. **`clean:crm` esta deshabilitado** (solo `--help` y `--preflight`). Para dejar
   la branch limpia entre intentos, por psql:

   ```sql
   begin;
   set local session_replication_role = replica;  -- el ledger es append-only
   truncate crm.actividades, crm.tareas, crm.lead_asignaciones, crm.leads cascade;
   delete from crm.equipo;
   set local session_replication_role = default;
   commit;
   ```

4. **El seed no es re-ejecutable a medias.** Si aborta despues de crear leads, el
   siguiente intento se atasca en la baja de `vendInactive`. Limpiar (punto 3) y
   volver a empezar.

---

## Adenda 2026-08-27 — el gate volvió a correr ENTERO (1175/1175)

La receta de arriba sigue válida; estos son los ajustes descubiertos al montar
el banco `banco-gate-rls` (replay manual 147/147 con las guardas md5 en verde):

1. **`CRM_BANCO_PSQL_URL` es ahora obligatoria para el gate**: la cadena psql
   del pooler (5432, modo sesión) del branch. `test-rls.mjs` la usa para las
   revocaciones FUERA DE BANDA de P04 (matriz y banca): el guard de jerarquía
   post-8-ago prohíbe —con razón— desactivar membresías con dependencias, y el
   estado heredado que esas sondas miden solo se construye como lo construye
   el seed. Se apaga SOLO `trg_equipo_validar_usuarios_jerarquia`: la rotación
   del token ICS y la auditoría siguen corriendo, como en una baja real.
2. **Dos migraciones hambrientas más** (además de `20260812000259`):
   `20260824231133` exige el backfill de agosto de PROD (48 ops/29 conv) — en
   banco se neutraliza SOLO ese assert de datos en la copia del replay (el de
   privilegios queda) — y `20260827090000` exige una GERENCIA activa
   (sembrarla antes, igual que la cadena supervisor→vendedor).
3. **El seed necesita un grant temporal**: `grant select on
   crm.periodos_cerrados to service_role` antes de `seed:demo` y `revoke`
   después — el trigger INVOKER `definir_periodo_comercial_contrato` lo lee al
   insertar contratos fixture y service_role no lo tiene (en prod nadie
   inserta contratos por PostgREST).
4. **Limpieza entre corridas** (punto 3): añadir
   `update public.perfiles set domicilio = null where rol = 'cliente';` — la
   sonda de domicilio exige arrancar con la columna vacía.
