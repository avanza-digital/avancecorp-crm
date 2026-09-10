---
tags: [crm, cartera, F5, publicacion, retomar]
fecha: 2026-09-10
estado: instalada-apagada-verificada
---

# F5 instalada y apagada

Miguel aprobó el SQL adicional con «hazlo. aprobado». Se instalaron las dos
migraciones F5 y la función de documentos desde Main sincronizado `a884ac3`.
El servidor terminó de desplegar; las consultas de capacidad devuelven OFF.
F3 sigue ON; F4 y F5 siguen OFF. No volver a pedir aprobación por esta instalación.

Se conservaron las huellas de 14 tablas de negocio y los 474 usuarios de Auth,
1.353 objetos previos y las 17 funciones Edge existentes. Las nueve funciones F5
y los documentos coinciden con el banco probado. D-19 queda en cero.
El banco temporal exclusivo fue eliminado y se verificó su ausencia.

Las versiones productivas son `20260909165335` y `20260909171452`.
Supabase separó el SQL en 33 y seis sentencias exactas: cambia el formato del
array del historial, no el texto aprobado ni las 266 migraciones anteriores.
No se normalizó el ledger ni se subió otro frontend.

Quedan 15 fuentes sin identidad (13 Avance, dos Qorilazo), que bloquean activar
F5. No se completaron automáticamente. El gate RLS general tiene 65 fallos
anteriores del banco pendientes; la matriz F5 específica sí pasó.

Sigue desarrollar **F6 — postventa**, luego F7/G6, F8/G7 y F9/G8. No confundir
la instalación de F5 con el cierre del plan completo o el permiso para un piloto
económico. G8 requiere un ciclo mensual real. Comisiones externas excluidas.

Acta: `CRM-Avance-Corp/supabase/scripts/f5/PUBLICACION-2026-09-10.md`.
Evidencia: `supabase/scripts/f5/evidencias/publicacion-2026-09-10/`.

Relacionados: [[F5 - banco remoto y correcciones de instalacion (2026-09-09)]],
[[Plan de implementacion F5 - cartera y ficha multiempresa (2026-09-08)]],
[[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]],
[[F4 cerrada - comisiones fuera del sistema (2026-09-08)]].
