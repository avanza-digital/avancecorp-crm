# Reconciliar Main con la publicación de capital renovado

## Motivo

Miguel autorizó publicar el cierre de tareas de clientes (#207), continuarlo sin
esperar a llamadas del celular (#190) y reanudó el trabajo tras la pausa.
El interruptor cerrado de #209 ya está integrado. Mientras se verificaba la entrega,
otra publicación instaló `build-20261007T034648905Z`, fuente
`dfb8874d534bc6462432dee00298f022e4437a0b`, sobre el anterior vivo `4e6ee7ee`.

El contenido de esa corrección está también en Main mediante #210, pero el squash
no conserva el commit publicado como ancestro. El preflight oficial rechazó el
candidato de Main `e255e96d3d0ef39c55eedd29a9c879bf13822b91`:

```text
[preflight rechazado] el candidato e255e96d3d0e no contiene el release vivo dfb8874d534b
```

## Reconciliación preparada

Se aplica la regla de rescate de `CLAUDE.md`: rama aislada desde el commit vivo y
merge ordinario de Main completo. No se modifica el preflight, no se falsifican
manifiestos, no se reescribe historia ni se omiten entregas.

El merge `31ff074490c45934add394da5c30b1915a060796` conserva como ancestros tanto
el vivo `dfb8874d` como Main `e255e96d`. Su árbol completo es idéntico al Main probado:
`8b2834c4e63303d45d162445cdb22390c533f3f6` (`git diff --exit-code` PASS).
El único conflicto fue la firma del helper `montarF5` en `e2e/f5-cartera.spec.ts`:
se conservó la versión completa de Main, con ambas correcciones #208 y #210.
Esta nota es el único cambio adicional de archivos respecto a Main.

## Verificación reutilizable

- Main `e255e96d`: `npm run check` PASS, 392 archivos / 6.286 pruebas; lint, tipos,
  build, configuración, bundle y duplicación.
- Main anterior `ad111817`: ocho especificaciones Docker PASS, 43 aprobadas,
  13 omitidas, cero fallos y cero retries; 3,7 minutos.
- Único delta de producto de #210: presentación del capital en Cartera. Spec F5
  completo sobre `e255e96d`: 13 aprobadas, cero fallos y cero retries; 1,2 minutos.
- SQL #207 instalado y postflight de solo lectura PASS a
  `2026-10-07T03:45:13.885063Z`. Esta reconciliación no cambia SQL, Edge, datos ni permisos.
- `LLAMADAS_CELULAR_APROBADAS = false` permanece intacto.

## Integración y publicación

La integración debe conservar la ascendencia: **merge commit o avance directo que
conserve estos commits**. Squash o rebase descartaría otra vez el commit vivo y no
resolvería el rechazo del preflight. GitHub exige historial lineal, revisión y
checks; una excepción a esa regla de historial requiere intervención explícita
del responsable. Codex no cambia reglas ni usa bypass administrativo por su cuenta.

Preferir integrar primero, verificar Main local/remoto y su árbol de producto,
reconstruir desde Main limpio y ejecutar el preflight oficial. La excepción de
publicar desde rescate exige integrarlo en Main el mismo día; una PR abierta no
equivale a completar esa integración. No declarar esta entrega publicada antes de
confirmar el servidor y los hashes HTTP.

Recuperación vigente conservada: `crm-20261007T034649Z-dfb8874d534b.zip`, SHA-256
`47070ef4c08e5f1e3c1d5cc371abfcbc208d07fcbce9f5ba5ec6571b73565ca2`.
