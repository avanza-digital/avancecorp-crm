---
tags: [crm, multiempresa, f8, piloto, g7]
actualizado: 2026-09-13
---

# F8 — piloto económico preparado y verificado en rama

G6 está cerrado y Miguel autorizó continuar con la preparación de F8 el
13/09/2026. Se creó una candidata técnica de control nominal y temporal,
instalada siempre apagada, para Gerencia, un supervisor y dos vendedores.
F4/F5/F6 pueden abrirse únicamente a esos actores; F7 y las banderas globales
permanecen apagadas. Las comisiones siguen fuera del CRM.

La candidata corregida tras review pasó 11 pruebas en el banco sintético local
y las mismas 11 en una rama Supabase aislada:
RLS/ACL, equipo exacto, usuario ajeno, perfil inactivo, revocación, cobertura,
sincronización, vencimiento, exclusión del rollout, cinco carreras del control y
reversa sin modificar las huellas económicas. Advisors y tipos también quedaron
verificados. No se
instaló ni activó producción. Contrato y evidencia:
`CRM-Avance-Corp/supabase/scripts/multiempresa-f8/README.md`.

La rama estándar no fue mergeable: al reconstruir sin datos, el historial remoto
se detuvo después de `20260811210049`, antes de F3–F7. Para el ensayo se restauró
el banco sintético, sin PII ni hechos reales, y se aplicó el SQL exacto. Este
resultado valida F8, pero no resuelve todavía el mecanismo de instalación.

Después del ensayo se retiró el acceso temporal `cli_login_postgres` que había
aparecido en la salida técnica. El aviso inicial lo confundió con la contraseña
principal: la credencial era temporal y ya había caducado. Se verificaron rol
ausente, cero sesiones y servicio saludable. Detalle en
[[Credencial temporal CLI - retirada tras ensayo F8 (2026-09-13)]].

El preflight real de las 17:09 Lima encontró F3 ON; F4–F7 OFF; 598 fuentes
totales. En ese corte la cobertura exacta tenía 14 bloqueos: diez fuentes reales ya
revisadas comercialmente en [[G6 - conciliacion real preparada (2026-09-11)]]
y cuatro demo. Prodelco tiene cuatro identidades coherentes y todavía no existen
personas multiempresa conocidas, de modo que la quinta identidad de Prodelco y
los seis recorridos deben suceder con evidencia durante el piloto.

La [[F8 - revision de identidades pendientes (2026-09-13)]] ya individualizó
los catorce movimientos: ocho reales para completado dirigido, dos de una ficha
multirrol cuya correspondencia Miguel ya confirmó y cuatro demo cuyo tratamiento
en la cobertura debe corregirse. El SQL de los diez reales se ensayó en
[[F8 - enlaces historicos preparados (2026-09-13)]] y ya se aplicó con autorización:
[[F8 - enlaces reales aplicados (2026-09-13)]]. Quedan cuatro huecos demo.
El informe nominativo está fuera de Git, en el escritorio de Miguel.

Sigue: resolver esa cobertura sin inferir identidad por datos blandos; elegir
el equipo nominal; resolver el historial de ramas; instalar OFF por un ciclo
autorizado; y recién después presentar el encendido exacto para autorización. G7 no se
cierra por calendario: exige casos reales, conciliaciones y firmas del
[[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]].
