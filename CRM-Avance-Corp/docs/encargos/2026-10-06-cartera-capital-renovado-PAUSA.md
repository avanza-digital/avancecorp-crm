# Pausa segura: publicación del capital activo de cartera

> **Pausa finalizada:** el usuario indicó «sigue». Este documento conserva el
> punto histórico de pausa. El estado vigente está en
> [el acta del arreglo](2026-10-06-cartera-capital-renovado.md).
> **Cierre posterior:** el PR #210 se integró y el arreglo aislado se publicó y
> comprobó el 06/10/2026 a las 23:20 de Lima. La pausa y los pendientes de este
> documento son históricos; véase el acta vigente del arreglo.
> **Limpieza final autorizada:** las rutas temporales mencionadas abajo ya fueron
> retiradas; registros y capturas se conservan en
> `output/renovacion-capital-20261006/verificacion-local.tar.gz`. No usar este
> punto de pausa como instrucciones de reanudación.

El usuario autorizó publicar («ok ya esta corregido publica») y después pidió
«pausemos en un momento seguro». Se pausa por esa instrucción antes de integrar
Main, hacer commits/push o publicar. No se hicieron cambios en la base de datos.
No reanudar hasta que el usuario lo pida.

## Trabajo conservado

- Corrección local: lista y resumen muestran US$12.000 activos en el caso
  reportado, conservando US$17.000 como histórico consultable.
- Archivos propios: `app/src/screens/cartera-inversionistas.tsx`, su test y
  `app/e2e/f5-cartera.spec.ts`. Los cambios de otras tareas se preservaron.
- PASS previo: 6.226 tests, lint, tipos, build, bundle y 11 E2E Docker aislados.
- Acta: [diagnóstico y verificación](2026-10-06-cartera-capital-renovado.md).
- Parche propio guardado en `/private/tmp/crm-renovacion-capital-20261006/cambio.patch`.
- Se creó una copia Git sin checkout en
  `/private/tmp/crm-renovacion-release-20261006`; no se usó para construir ni desplegar.

## Estado observado al pausar

- Main local: `4e6ee7ee296be83cd96366e3e79685343b3b706b`.
- `avancecorp/main`, tras fetch: `62a375f0e23a220952489148c6f8e07357a053e8`.
- Build servido por producción: `build-20261006T213354829Z`.
- Main remoto incorporó #190 (llamadas), #207 (gestiones de clientes) y #208
  (upgrade cooperativo); todavía no se integraron en este workspace.

## Comprobación necesaria al retomar

Las actas de #207 y #208 indican que sus migraciones están pendientes de
instalación. La de #207 prohíbe adelantar su frontend porque consume cinco RPC
nuevas. Ese estado documental debe contrastarse con producción antes de publicar
cualquier paquete de Main. No se verificó ni se aplicó ese SQL durante esta
preparación. Publicar la corrección de cartera no autoriza instalar esas otras
migraciones.

Retomar desde este punto: comprobar backend y Main vigentes, integrar sin perder
WIP, aplicar el parche propio en una copia limpia, pasar el gate completo y E2E
del código definitivo, construir ZIP/manifiesto, alinear Main local/remoto y
ejecutar preflight y publicación según `../.agents/skills/release-crm/SKILL.md`.
La autorización de publicación permanece, pero la pausa está vigente hasta una
instrucción de reanudación.
