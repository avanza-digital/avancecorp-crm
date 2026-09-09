---
tags: [crm, cartera, F5, pruebas, publicacion]
fecha: 2026-09-09
estado: banco-verificado-correcciones-preparadas
---

# F5 — banco remoto y correcciones de instalación

Miguel pidió terminar todo el plan principal y confirmó instalar el SQL F5
original y usar el banco temporal cotizado. No volver a pedir esa autorización.
El frontend con el arreglo del salto ya está publicado; el servidor F5 todavía
no está instalado en producción.

La prueba remota encontró dos defectos:
- La consulta de capacidad no compartía el bloqueo de F3 al cambiar de modo.
  Se creó el SQL aditivo `20260909170900_crm_f5_candado_estado_cartera.sql`;
  el original permanece inmutable. Misma respuesta/permisos, sin tocar banderas.
- El proxy documental usaba una clave de servicio opaca como Bearer junto con
  apikey pública. Se corrigió solo la credencial de Storage; Auth y consultas
  documentales conservan la sesión del usuario y la comprobación vigente.

Resultado: **46 pruebas locales y 15 remotas PASS**, incluida descarga exacta,
reasignación, baja, integridad de importes y permisos. Replay, reversa, tipos
y preflights PASS. El gate general remoto dio 1.589 PASS/66 FAIL: 65 coinciden
exactamente con los fallos anteriores de Citas y el adicional era D-19.
D-19 quedó corregido y vuelto a comprobar; no se declara aprobado el gate general.

Banco propio: `f5-cartera-publicacion-20260909` / `suzyimzjeybeaqozqifi`.
Nació sin datos; ante el fallo del replay histórico se verificó el esquema
actual frente al padre antes de ensayar. Solo contiene fixtures ficticias.
Las otras ramas pertenecen a tareas diferentes. El banco propio debe eliminarse
al terminar su integración; el cómputo sigue facturándose mientras exista.

La corrección SQL adicional se presenta a Miguel conforme a «mostrar el SQL
primero y esperar confirmación» de [[Inicio]]. Después: integrar Main remoto,
construir el paquete exacto, comparar padre/Edge antes de merge, instalar las
dos migraciones, comprobar producción y retirar el banco. No adelantar F5 ON
ni escritura. No volver a instalar F4 ni normalizar el ledger remoto.

El censo productivo conserva 15 fuentes sin identidad vinculada. Requieren lotes
F4 revisados antes de activar. El resto del plan sigue siendo **F6 → F7/G6 →
F8/G7 → F9/G8**; G8 necesita un ciclo mensual real. Comisiones fuera del sistema.

Acta técnica y SQL:
`CRM-Avance-Corp/supabase/scripts/f5/INSTALACION-2026-09-09.md`.

Relacionados: [[F5 - prepublicacion y salto de cartera (2026-09-09)]],
[[Plan de implementacion F5 - cartera y ficha multiempresa (2026-09-08)]],
[[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]],
[[F4 cerrada - comisiones fuera del sistema (2026-09-08)]].
