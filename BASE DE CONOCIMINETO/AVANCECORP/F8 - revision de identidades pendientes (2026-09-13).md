---
tags: [crm, multiempresa, f8, identidad, conciliacion]
actualizado: 2026-09-13
---

# F8 — revisión de identidades pendientes

Miguel autorizó revisar las catorce fuentes que bloquean F5/F8. La lectura
productiva del 13/09 a las 19:52 Lima y su comprobación ampliada a las 20:02
confirmaron 598 fuentes, 593 reales y cinco demo. Se ejecutaron en transacción
`REPEATABLE READ READ ONLY` y terminaron con `ROLLBACK`. No se escribió en
producción.

La revisión está completada; los enlaces todavía no están corregidos:

- **Ocho movimientos reales:** siete contratos Avance de cinco perfiles y un
  cierre Qorilazo de otro lead. Se crearon después de la carga inicial F2. Sus
  documentos tienen formato válido y no hay colisiones ni identificadores
  vigentes/históricos coincidentes. El lead del cierre tiene DNI vacío, pero el
  cierre conserva el documento. Son seis fichas candidatas al completado
  dirigido con la procedencia documental histórica F2, auditoría y preimagen.
- **Dos movimientos reales:** una sola ficha cliente comparte documento con
  una cuenta de analista. Se consultó si ambas cuentas representan a la misma
  persona. La cuenta cliente será el enlace económico; la de analista conserva
  su acceso separado. Respuesta pendiente, sin inferir identidad por nombre.
- **Cuatro movimientos demo:** tres contratos de dos perfiles sin documento
  válido y un cierre de prueba. El gate actual los incluye, pero el contrato
  prohíbe crear identidades operativas con documentos inventados o no verificados.
  Hay que diseñar y probar su exclusión del universo real con clasificación
  controlada, de forma coherente en gate, listados, ficha y conteos. Ese ajuste
  todavía no se implementó.

Los diez movimientos reales corresponden a **siete fichas**, no a diez personas
distintas. La agrupación usa perfil y lead de origen. Los ocho primeros tampoco
son enlaces a una identidad neutral ya existente: ninguna de sus búsquedas
documentales encontró una. Un formato válido no sustituye la procedencia y
aceptación documental que deberá hacer explícitas el SQL de completado.

La conformidad comercial/financiera de [[G6 - conciliacion real preparada (2026-09-11)]]
sigue vigente para el corte aceptado. No se pide revisar de nuevo todos los
clientes ni los montos. La pregunta nueva trata exclusivamente la
correspondencia de las dos cuentas multirrol.

Informe nominativo privado en el escritorio:
`~/Desktop/Revision F8 - identidades 2026-09-13/Revision de identidades F8.html`.
Las dos fotografías JSON también quedan allí, fuera de Git, con carpeta `700`
y archivos `600`. El repositorio y Claude solo reciben evidencia agregada.

Contrato del diagnóstico y verificaciones:
`CRM-Avance-Corp/supabase/scripts/multiempresa-f8/REVISION-IDENTIDADES-2026-09-13.md`.
La consulta reutilizable está al lado, en `revision-identidades.sql`, y su salida
contiene PII que debe seguir guardándose fuera de Git.

Sigue: preparar las correcciones concretas y ensayarlas, mostrar su SQL antes
de la escritura, actualizar el censo, resolver la instalación, elegir el equipo
y completar los casos reales de G7. F8 sigue sin instalar ni activar; no hay
cambios en las fases cerradas ni en la decisión de comisiones fuera del CRM.

Relacionadas: [[F8 - piloto economico preparado localmente (2026-09-13)]],
[[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]],
[[Contrato arquitectonico consolidado - identidad unificada de inversionistas (F0 2026-08-31)]].
