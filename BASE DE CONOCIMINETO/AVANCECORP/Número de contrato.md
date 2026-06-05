# Número de contrato

> **Norma a prueba de errores** para que los asesores no escriban "cualquier cosa" en el número de contrato (pedida por Miguel, 2026-06-04). Hermana de [[Nombres en mayúscula]].

## El formato

**`2026-01-` + 6 dígitos** → ejemplo: `2026-01-000123`.

- **`2026-01-`** es un **prefijo fijo** que pone el sistema (se ve en gris al lado del casillero). El asesor **no lo puede escribir, borrar ni editar**.
- Los **6 dígitos** son lo único que el asesor escribe. Es un número que él ya tiene (del contrato físico / expediente) y lo **transcribe** — NO es un correlativo automático.

## Las reglas (en los DOS formularios: panel del analista y panel admin)

1. **Solo dígitos (0–9), exactamente 6.** El casillero bloquea letras y espacios, incluso al pegar.
2. **El prefijo `2026-01-` no se puede borrar** (no es parte del casillero editable).
3. **Obligatorio:** no se crea el contrato sin ese número.

## Detalles que conviene recordar

- El **`01` es fijo por ahora** — NO es el mes. El cambio automático por mes (`2026-02-…` en febrero, etc.) quedó **pospuesto** como decisión de Miguel; se implementa cuando él lo pida.
- Los **contratos viejos** (formato `AC-AAAA-####`) **conservan su número**. Si se editan, adoptan el formato nuevo.
- La unicidad la garantiza la base de datos (`UNIQUE (numero_contrato)`); si alguien repite un número, sale un mensaje claro ("ya existe").

## El admin ahora puede EDITAR contratos

Desde **2026-06-04** el **admin / superadmin** tiene botón **Editar** en cada contrato (antes solo creaba, veía o eliminaba; editar era exclusivo del [[Rol Analista|analista]] y solo dentro de su ventana de 5 h). El admin edita **cualquier** contrato sin límite de tiempo, **incluido el número** (con chequeo de que no se repita). Si el contrato **ya tiene cuotas pagadas**, el sistema **no permite** regenerar el cronograma (protege los pagos ya registrados).

Ver también: [[Arquitectura del portal]] · [[Rol Analista]] · [[Auditorías del portal]].
