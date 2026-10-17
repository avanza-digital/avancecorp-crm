# Supabase Advisors — antes/después local

PASS de comparación, diez candidatas; no equivale a ausencia de avisos.
CLI oficial 2.117.0 Linux arm64, sha256 contrastado con el digest del release:
`598c56a936fdf179ea486717901e6e49bc5d777b3ad317eab02f41faf21a95cb`.
[Release oficial](https://github.com/supabase/cli/releases/tag/v2.117.0).

`advisors-local.mjs` crea un clon vacío propio del esquema nativo, retira la
fundación vacía, ejecuta CLI db advisors antes y después de aplicar las diez
candidatas y retira únicamente su clon. Comparación sobre el mismo banco,
namespace network none, sin puertos/egreso; binario de solo lectura.

| Nivel | Antes | Después | Nuevos de esta tarea |
| --- | ---: | ---: | --- |
| ERROR | 0 | 0 | 0 |
| WARN | 7 | 7 | 0 |
| INFO | 434 | 445 | 13 nuevos / 2 ausentes del baseline |

Los trece INFO nuevos son siete unused_index y seis rls_enabled_no_policy.
En el banco vacío los índices nuevos aún no tienen uso; se conservan por sus
consultas y relaciones. Las seis tablas de tasas/trabajos/valoraciones/política/
cortes/sellos deniegan acceso directo, con RLS habilitado y sin políticas; se
sirven únicamente por RPC autorizadas. La matriz HTTP comprueba GET/PATCH
denegados aun para Gerencia/Directorio y usuarios sin acceso a escritores.
No abrir policies globales para silenciar el aviso.
[Unused index](https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index),
[RLS sin policy](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy).

La primera comparación de ocho candidatas señaló cuatro FK nuevas sin índice;
`20261017025829` añadió los cuatro índices. En la comparación final no aparece
ninguna FK nueva sin índice. Los avisos previos de otras tablas no se alteran.
Deltas por identidad nombre/detalle/metadata; las estadísticas de uso pueden
cambiar avisos INFO anteriores, por eso el incremento neto no es trece.

Evidencia privada temporal: advisors-antes.json, advisors-despues.json,
advisors-delta.json, cli-integridad.json y advisors-final-review.log.
También se consultaron Advisors productivos solo como baseline; no verifican
las candidatas que siguen sin instalarse. Sus avisos preexistentes no se
resuelven ampliando este alcance ni cambiando tablas/grants en producción.
