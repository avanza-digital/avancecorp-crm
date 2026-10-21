# Aviso para la tarea GUARDIANES-1610 (re-sellado de guardianes en rojo)

**Fecha:** 20/10/2026 · **Migración:** `20261020214445_crm_gestion_diaria_pendientes_recientes_primero.sql`

La migración de «pendientes de lo más reciente a lo más antiguo» **re-sella el gate H3**
`private.assert_gestion_diaria_pendientes()` porque cambia el cuerpo del núcleo de 5 argumentos
(pasa a ser un envoltorio) y añade el núcleo de 6:

| Objeto | Huella `md5(pg_get_functiondef)` antes | después |
| --- | --- | --- |
| `private.gestion_diaria_pendientes_core(uuid,boolean,integer,timestamptz,uuid)` | `a0bde87db9ea86694ba4ee79dc109729` | `681d76d982dbba77c2cc556e725ead0a` |
| `private.gestion_diaria_pendientes_core(…,boolean)` (nuevo) | — | `b55e6776ebfdbb2fdd61789ef06b26b6` |
| `private.assert_gestion_diaria_pendientes()` | `6aecb25a8a66e10cc5dcae69afb66281` | `81c4ce510bcc0de7eaeffa17c15c67ec` |
| `crm.gestion_diaria_cola_trabajo_fn(text,integer,integer,text)` (sin gate) | `c166b286f6577ebf35809dfd708a0ab4` | `4dc88038f8664a4ef8318f68151ac7b7` |

Qué significa para el re-sellado en pausa (`20261016210959`, `20261016211000`, `20261016211001`,
rama `crm/guardianes-resellar-20261016`):

- Si alguna de esas migraciones **vuelve a crear** `private.assert_gestion_diaria_pendientes()`
  con la huella vieja del núcleo (`a0bde87d…`), al aplicarse DESPUÉS de esta dejará ese gate en
  rojo por el núcleo. Hay que usar las huellas de la tabla (o el patrón `replace` sobre el gate
  vivo, que las conserva).
- Esta migración **no** llama al gate como condición: exige que su veredicto sea el MISMO antes y
  después. Hoy en producción ese veredicto es rojo por `crm.equipo_visible_fn()` (gate del día del
  analista), que es justo lo que GUARDIANES-1610 re-sella. Cuando se aplique el re-sellado, el gate
  H3 quedará verde con estas huellas sin tocar nada más.
- Si el re-sellado se aplica ANTES que esta migración, no pasa nada: el preflight de esta mide las
  huellas de pendientes (que no cambian con el re-sellado del día del analista) y el veredicto del
  gate sería `OK` antes y después.
