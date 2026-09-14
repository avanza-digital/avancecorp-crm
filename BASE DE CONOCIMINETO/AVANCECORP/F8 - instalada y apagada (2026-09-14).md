---
tags: [crm, multiempresa, f8, publicacion]
fecha: 2026-09-14
estado: instalada-off-equipo-y-g7-pendientes
---

# F8 instalada y apagada

Los dos SQL autorizados quedaron instalados y verificados en producción el
14/09 a las 11:51 Lima: control nominal del piloto y exclusión operativa de
fuentes demo. **F8 OFF, sin participantes; F3 ON y F4–F7 globales OFF.**

El Main verificado fue `8c185f689afbfdc48dcb459d6f0527bcd0db7301`;
las versiones productivas son `20260914161616` y `20260914161816`.
Se conservaron los archivos SQL originales y las 279 migraciones anteriores.
Cada sentencia instalada coincide literalmente con los SQL aprobados.

Ensayo completo: 31 pruebas SQL locales, 27 remotas y 12 grupos Auth/Data API.
Frontend: 3.513 pruebas, lint, tipos, build y manifiesto del artefacto PASS.
Claude revisó y pidió cambios; Codex resolvió sus recomendaciones con pruebas.
La suite general RLS heredada completa no se ejecutó en este ensayo combinado.

La lectura posterior encontró 600 fuentes reales con identidad coherente y
cinco demo excluidas de la operación, conservadas en la historia. Las 602
fuentes anteriores al merge mantuvieron exactamente su huella. Ventas y altas
posteriores se reconocen como actividad concurrente; Auth/perfiles no tienen
hash idéntico y no se reescribieron para forzarlo. Inversiones, cotitularidades,
periodos, equipo, Vault y Cron conservados. Los dos sitios responden HTTP 200;
Miguel confirmó acceso normal después de un error de conexión transitorio,
cuya causa no está determinada.

La rama exclusiva de instalación fue eliminada y su coste terminó. Esta entrega
instala SQL; no cambia el frontend ejecutable ni publica candidatas de Citas.

Sigue elegir **Gerencia, un supervisor y dos vendedores**, preparar su ventana
y SQL exacto para aprobar configuración/activación, y reunir los casos reales,
conciliación y firmas de G7. No se vuelve a pedir autorización de instalación.
F8 aún no está cerrada; F9 depende de G7. G6 sigue cerrado para su corte y las
comisiones permanecen fuera del sistema.

Acta técnica: `CRM-Avance-Corp/supabase/scripts/multiempresa-f8/PUBLICACION-2026-09-14.md`.
Antecedente: [[F8 - ensayo completo antes de instalar (2026-09-14)]].
Enlaces ya completados: [[F8 - enlaces reales aplicados (2026-09-13)]].
Plan: [[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]].
