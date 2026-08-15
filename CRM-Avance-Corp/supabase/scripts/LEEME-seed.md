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
