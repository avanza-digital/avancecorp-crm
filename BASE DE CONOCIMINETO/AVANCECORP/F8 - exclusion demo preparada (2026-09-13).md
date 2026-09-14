---
tags: [crm, multiempresa, f8, demos, cartera]
actualizado: 2026-09-13
estado: candidata-local-sin-aplicar
---

# F8 — exclusión demo preparada

Miguel autorizó preparar el tratamiento de los cuatro registros de prueba
restantes después de [[F8 - enlaces reales aplicados (2026-09-13)]]. Los diez
movimientos reales anteriores permanecen corregidos y no deben ejecutarse otra vez.

La migración nueva `20260914025926_crm_f8_excluir_fuentes_demo.sql` conserva las
598 fuentes históricas y usa solo las 593 reales para cobertura, cartera,
inversiones/cantidades de la ficha, documentos y fuentes de postventa. Las cinco
demo siguen archivadas; los cuatro huecos demo dejan de bloquear una vez instalado
el ajuste. No se crean identidades ficticias ni se modifica la clasificación de
ningún contrato. Gerencia conserva su puerta de marca demo con motivo y auditoría.

Personas mixtas conservan inversiones reales; personas con solo demos no
reaparecen por tener perfil cliente. Los clientes sin ninguna fuente conservan
su ficha. El lector administrativo completo y los importes de F7 no cambian.

Banco cerrado sintético: 31 pruebas SQL PASS (20 de demos y 11 del control),
incluidas reversa exacta, roles, deriva, dependencias y bloqueo de huecos reales.
Revisión de Claude y decisiones del PRIMARY registradas en
`CRM-Avance-Corp/supabase/scripts/multiempresa-f8/demos/REVISION-CLAUDE.md`.
SQL, orden de instalación, gates y límites:
`CRM-Avance-Corp/supabase/scripts/multiempresa-f8/demos/README.md`.

**Producción sigue sin este ajuste y sin control F8.** F3 ON; F4–F7 OFF.
La corrección requiere primero `20260913215240` instalado OFF. Falta presentar
el SQL para aprobación, completar el ciclo remoto permitido y comprobar la
instalación. La rama restaurada del ensayo anterior no era mergeable y no
cuenta como ensayo de esta migración. No se ejecutaron advisors/Auth/Data API
remotos de la corrección ni nuevas ventas reales.

La reversa restaura las ocho definiciones exactas y conserva filas; no modifica
el ledger de migraciones. Una reversa publicada/reinstalación se registra como
nuevas migraciones en el ciclo autorizado.

Después siguen equipo nominal, inicio autorizado y evidencia G7 de
[[F8 - piloto economico preparado localmente (2026-09-13)]] y
[[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]].
