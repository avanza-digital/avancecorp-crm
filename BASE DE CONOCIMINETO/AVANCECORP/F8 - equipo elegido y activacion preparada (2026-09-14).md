---
tags: [crm, multiempresa, f8, piloto]
fecha: 2026-09-14
estado: equipo-elegido-activacion-pendiente
---

# F8 — equipo elegido y activación preparada

Miguel seleccionó los cuatro participantes requeridos: Gerencia, supervisor y
dos analistas. Las cuentas son únicas, activas, confirmadas y sin suspensión.
Uno de los analistas pertenece a otro equipo; conserva su jerarquía y alcance.
Los nombres/UUID están en el registro privado de esta sesión, fuera de Git.

El SQL de primera configuración y encendido está preparado para esos cuatro
UUID. Propone siete días desde la ejecución; se puede cerrar antes y no obliga
a esperar una semana para completar G7. Usa una transacción, rechaza cambios
previos y no reasigna personal ni modifica cuentas o movimientos económicos.
La propuesta identifica a Gerencia como responsable operativo explícito y
liga la referencia `F8-20260914-01` al SQL por SHA256. La aprobación humana
sigue pendiente; la ejecución administrativa no simula su sesión/firma.

PASS: 24 pruebas locales del paquete y 43 verificadores offline/sintaxis.
Claude: primera revisión CHANGES_REQUESTED, correcciones aplicadas y segunda
revisión PASS. Los dictámenes y la decisión del PRIMARY están en el paquete.
Se corrigió un conflicto de bloqueos reproducido solo en el banco sintético;
las carreras de activación frente a bandera global, reversa y otra activación
están cubiertas. La lectura
productiva conserva F8 OFF, revisión cero, sin participantes instalados,
F3 ON, F4–F7 OFF y cero brechas reales.

Falta aprobar el SQL nominal y la vigencia antes del encendido. La autorización
previa de instalación ya está ejecutada; no se solicita otra vez. La elección
del equipo está completa y no se vuelve a pedir nombres.

Paquete: `CRM-Avance-Corp/supabase/scripts/multiempresa-f8/activacion/README.md`.
Selección/SQL nominal privado:
`/private/tmp/avancecorp-f8-participantes-20260914/seleccion-completa.json` y
`activar-equipo.sql` en el mismo directorio.

Antecedente: [[F8 - instalada y apagada (2026-09-14)]].
Plan: [[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]].
