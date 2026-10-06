# Preparación del despliegue · cierre de gestiones de clientes

## Alcance aprobado

Miguel aprobó la vista del CRM vigente en local el 06/10/2026 y pidió «prepara todo para el deploy». La aceptación visual queda resuelta. La instalación productiva de SQL y la publicación del frontend conservan sus puertas propias.

La entrega parte de `avancecorp/main`, commit `4e6ee7ee296be83cd96366e3e79685343b3b706b`, que también es la fuente del build vivo `build-20261006T213354829Z`. Incluye las restricciones vigentes de nueva inversión de #206. No se usa el demo heredado ni se empaquetan sus datos de ejemplo.

## Orden de instalación

1. Confirmar de nuevo `avancecorp/main`, el build vivo y la huella del paquete. Si cambia el código de Main, integrar y reconstruir.
2. Obtener la autorización del SQL exacto de las dos migraciones listadas abajo y un banco remoto de Supabase del proyecto `dctqcbznekcyxhjujuci`. Confirmar su coste antes de crear una rama. La rama existente `banco-f7` está en `MIGRATIONS_FAILED` y pertenece a otro trabajo; no se reutiliza ni modifica.
3. En la rama autorizada, ejecutar `supabase/scripts/gestiones-clientes/preflight.sql`: exige las 17 dependencias verificadas, ausencia de los objetos nuevos, RLS y ausencia de SELECT directo del historial F6.
4. Aplicar exclusivamente estas migraciones, en este orden, mediante el mecanismo de la rama:
   - `20261005224214_crm_resultados_cliente_postventa.sql`.
   - `20261006012208_crm_gestiones_clientes_supervision.sql`.
5. Ejecutar `comprobar-tras-aplicar.sql`, matriz HTTP RLS del proyecto y casos de este encargo en el banco autorizado; revisar advisors contra la línea base. Generar los tipos de la rama y cotejar las cinco RPC con el cliente. No sustituir tipos ajenos por un snapshot antiguo.
6. Solo con esos gates aprobados, integrar la rama de Supabase y repetir el control posterior contra producción. Preservar el historial de migraciones y las Edge Functions. No usar un `db push` general ni `apply_migration` directo a producción.
7. Con el backend verificado, la invocación humana de `$release-crm` autoriza publicar el frontend. Revalidar ZIP/manifiesto y el preflight Hostinger justo antes de subirlo.
8. Comprobar HTTP, build y hashes de todos los assets publicados. Verificar ficha, Agenda, Registro, resumen por analista y Citas sin fabricar gestiones reales para probar.

Si falla cualquier paso SQL, **no adelantar el frontend**: consume cinco RPC nuevas. La compatibilidad del writer permite mantener la pantalla anterior mientras se instala y valida la base.

## Verificación de esta preparación

| Gate | Resultado |
| --- | --- |
| `npm run check` sobre copia limpia de Main + este encargo | PASS: 387 archivos, 6.219 pruebas, tipos, lint, build, bundle y duplicación 0,43 % |
| Ensayo SQL de instalación exacta | PASS: control previo → dos migraciones → catálogo/permisos → cuatro suites → ROLLBACK |
| Dependencia F5 del banco | Actualizada desde el snapshot vigente de producción; suites SQL PASS |
| Control previo contra producción, solo lectura | PASS; 17 dependencias, 06/10/2026 22:16 UTC |
| `seed:preflight`, `test:rls:preflight` | PASS offline con destino loopback y valores ficticios; no acreditan RLS remoto |
| E2E Docker completo | En verificación; el acta final del paquete conserva el resumen real |
| Revisión Claude | Dos reviews previos; recomendaciones evaluadas y verificadas por Codex en el acta de revisión |
| Rama Supabase, matriz HTTP RLS y advisors posteriores | NOT RUN; requieren la rama autorizada y la confirmación de su coste |
| SQL y frontend productivos de este encargo | No instalados |

`gate:realidad` leyó producción: hay metas, cartera, tareas y equipo operativo; los cinco caminos de conversión coinciden. El canario de metas no tiene permiso por HTTP y se completó por SQL de solo lectura: cero revisiones bajo el sello. Se detectaron 277 clientes sin domicilio legal, condición preexistente del alta de contratos que no bloquea el cierre de gestiones. El comando HTTP terminó con exit 2 por ese permiso; no se presenta como un PASS íntegro.

Advisors de referencia guardados en `app/artifacts/gestiones-clientes-advisors-base.json`. Es una línea base productiva anterior a este SQL, no una validación posterior de las migraciones. Incluye avisos existentes de seguridad y rendimiento. Los helpers DEFINER nuevos se autorizan por sesión/rol/árbol y tienen `search_path` vacío; sus EXECUTE a authenticated permiten las puertas INVOKER. `private` no se expone como esquema de la API.

## Recuperación

Release publicado anterior: `releases/crm-20261006T213355Z-4e6ee7ee296b.zip`, con su manifiesto. SHA-256: `9b5be00b190443726f5520fc37a54ba27ff3785ace447200b7ce2d807430e33d`.

La recuperación preferida retira el frontend nuevo y conserva el writer compatible, los resultados, los recibos y el historial. No se borran actividades ni se reescriben resultados. El bundle anterior admite la base ampliada. Un rollback del frontend requiere decisión de Miguel: el preflight rechazará un commit anterior y no debe eludirse automáticamente.

Si hiciera falta retirar las cinco consultas nuevas, preparar una migración inversa específica, revisada y probada en rama, después de retirar sus consumidores. No se incluye un borrado automático del SQL ni se revierte el registro de migraciones. `ensayar-entrega.mjs` retira y repone objetos únicamente dentro de una transacción con ROLLBACK en el banco sintético sellado; no es un procedimiento productivo de reversa.

## Evidencia

- Implementación: [acta](2026-10-06-cierre-gestiones-clientes.md).
- Revisión y decisiones: [Claude](2026-10-06-cierre-gestiones-clientes-REVISION.md).
- Banco y controles: [README](../../supabase/scripts/gestiones-clientes/README.md).
- Logs: `app/artifacts/gestiones-clientes-entrega-*.log` y `gestiones-clientes-realidad-destino.json`.
- El paquete final agrega el commit, manifiesto, hashes, evidencia de E2E y resultado del preflight Hostinger.
