# Gestión integral multiempresa — publicada

Implementación del [plan aprobado](../../../../BASE%20DE%20CONOCIMINETO/AVANCECORP/Cartera%20multiempresa%20-%20plan%20de%20gestion%20integral%20%282026-09-16%29.md).
**SQL instalado y frontend publicado el 16/09/2026.**
[Acta y versión publicada](PUBLICACION.json), [ensayo remoto](REMOTO.md) y
[verificación productiva](PRODUCCION.json). Fuente limpia `14be1e0581d8`,
Main igual a `avancecorp/main` al construir/publicar. Los párrafos de preparación
local describen el ensayo anterior a esta publicación.
Worktree autorizado: `/private/tmp/avancecorp-gestion-worktree`; implementación
en `codex/gestion-multiempresa`, origen `ffc9ab49`, integrada por PR #3. Se
conservaron los cambios de eliminación de contratos/PDF y los pendientes de
la carpeta original. El menú local `f15061b6` sigue separado en
`codex/menu-gerencia-pendiente-20260916`; no se incluyó en esta publicación.

## Comportamiento

La ficha permite corregir perfiles/cuentas Avance y contacto neutral, corregir
contratos e inversiones COOPAC según su autoridad, consultar cuotas/pagos,
PDF, tasas/autorizaciones, desglose económico y atribución/reasignación.
Supervisión/Gerencia recuperan «Nuevo cliente» con capacidad vigente. El analista
conserva la conversión desde Leads. Se retira la entrada adicional Gestión Avance.
La [matriz](MATRIZ.md) identifica escritor, rol y límite de cada acción.

Contacto neutral usa una tabla cerrada y versionada; no fabrica cuentas Auth ni
reescribe nombres históricos de inversiones. La fecha original más antigua,
autoría y responsable actuales gobiernan las cinco horas. Una fusión no reinicia
la ventana. El perfil Avance, si existe, sigue siendo la autoridad de sus datos.
Los formularios neutrales guardan recibo idempotente por actor; al fallar la red
conservan el envío y consultan su resultado. El servidor decide siempre.

## SQL y reversa concretos

- [Migración candidata](../../migrations/20260916152851_crm_gestion_integral_multiempresa.sql).
- [Reversa no destructiva](REVERTIR-20260916152851.sql).
- [Ensayo SQL, huellas y SHA-256](SQL-LOCAL.json).
- [24 grupos Auth/HTTP/SQL reales](HTTP-LOCAL.json).
- [Revisiones y evaluación del PRIMARY](EVALUACION-REVISION.md).

La migración crea una tabla CRM, un helper privado y tres RPC; amplía el CHECK de
la bitácora y adapta dos funciones existentes mediante guardas MD5. No hace DDL
sobre `public`, no cambia flags ni migra datos económicos. La corrección COOPAC
con lead archivado registra antes/después en la gestión neutral; la RPC antigua
conserva su comportamiento de llamada directa. Se mantiene la auditoría de tabla.

La reversa restaura los cuerpos anteriores y revoca las RPC nuevas. **Restaurar
primero la web anterior.** Conserva contacto, auditoría, recibos y CHECK ampliado,
con RLS y sin acceso directo. Los nombres/teléfonos corregidos dejan de proyectarse
en la lectura revertida; los valores quedan conservados para una recuperación.
No se vuelve a ejecutar la migración CREATE sobre esa tabla: una reactivación
requiere una nueva migración revisada que reutilice los datos.

## Verificación

Los detalles de comandos, resultados y límites están en [VERIFICACION.md](VERIFICACION.md).
El SQL se ensayó contra una copia PostgreSQL local con Auth y PostgREST reales:
ventanas antes/límite/después, ámbito propio/ajeno, revocación, fusión, idempotencia,
conflictos, datos históricos y llamadas reales al núcleo Avance. La instalación
sobre otra copia limpia y la reversa conservaron funciones `public`, propietarios
y ACL. Con 600 contactos, el lector tardó 29,08 ms y conservó exactamente los IDs
visibles antes/después de incorporar contactos; no es una medición productiva.

Antes de instalar, el 16/09/2026 se contrastó producción con una consulta de agregados de solo lectura:
496 identidades activas, 24 sin perfil Avance y 24 COOPAC vigentes sin condiciones
históricas. Postventa está habilitada. Las dos huellas previas coinciden con las
guardas; la tabla nueva aún no existía en ese momento. Tras instalar, las
lecturas de 23 cuentas activas pasaron y los datos anteriores quedaron intactos.
No se extrajeron datos personales.

## Reproducción local

Los scripts se ejecutan desde la raíz del repositorio. Requieren un banco local
preexistente `supabase_db_avancecorp-f5-bank`, snapshot `rls_vigente_20260916` y
Docker. No crean bancos remotos ni leen credenciales productivas.

```sh
node CRM-Avance-Corp/supabase/scripts/gestion-multiempresa/test-sql.mjs
node CRM-Avance-Corp/supabase/scripts/gestion-multiempresa/test-http.mjs /ruta/privada/entorno.json
node CRM-Avance-Corp/supabase/scripts/gestion-multiempresa/integrar-tipos.mjs /ruta/tipos-generados.ts --verificar
```

`test-sql.mjs` rechaza reutilizar su base `gestion_multiempresa_20260918`.
`test-http.mjs` admite loopback con base `gestion_multiempresa_AAAAMMDD` o una
rama remota cuyo ref exacto esté fijado por `CRM_GESTION_RAMA_REF`. Rechaza
producción. Para ese ensayo remoto se usa el adaptador SQL explícito del script;
la rama propia ya fue eliminada. El entorno
contiene SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY,
CRM_BANCO_PSQL_URL y CRM_DEMO_PASSWORD. Nunca versionar ese archivo. El banco
retira solo en su copia una fuente sintética sin identidad de la matriz anterior,
que de otro modo bloquearía intencionalmente el encendido F5. La preparación
usa acceso SQL privilegiado; las operaciones verificadas usan sesiones reales.
Los tipos se introspectan con Supabase CLI y se integran solo los cuatro nodos
nuevos; reemplazar todos los tipos desde un snapshot antiguo perdería cambios ajenos.

## Instalación y publicación completadas

Miguel autorizó el SQL `20260916152851`, el banco hasta US$0,10 y la web mediante
`$release-crm`. El SQL aprobado se ensayó en la rama temporal del mismo proyecto
PortalAvanceCorp: 1.866 aserciones RLS y 24 grupos Auth/HTTP/SQL PASS. Se promovió
solo esa migración por `merge_branch`, registro remoto `20260916174727`.

Los datos, permisos, flags e historial previo permanecieron intactos. Las lecturas
productivas de 23 cuentas pasaron. Supabase republicó las Edge al promover:
20 funciones y 48 archivos fuente idénticos; versiones de paquete actualizadas.
Advisors y límites constan en [REMOTO.md](REMOTO.md), sin atribuir cero avisos.
La rama se eliminó; coste estimado US$0,009353, por debajo del tope autorizado.

El artefacto `crm-20260916T182804Z-14be1e0581d8` se construyó desde Main limpio,
igual a `avancecorp/main`, y se publicó con el conector oficial de Hostinger.
95 comprobaciones HTTP PASS; acceso visible sin errores de JavaScript.
[Manifest](PUBLICACION-MANIFEST.json), [smoke](PUBLICACION-HTTP.json) y
[acta completa, rollback y límites](PUBLICACION.json).
