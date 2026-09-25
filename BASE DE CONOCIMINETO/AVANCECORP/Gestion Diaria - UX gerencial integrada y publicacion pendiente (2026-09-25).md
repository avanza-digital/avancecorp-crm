---
tags: [crm, gestion-diaria, f6, publicacion]
actualizado: 2026-09-25
---

# UX gerencial integrada; publicación pendiente

Continúa [[Gestion Diaria - UX horizontal de gerencia preparada (2026-09-25)]].
**PR #101 integrado manualmente por miguejbs98**, en Main `f9196dba`, sin
revisión APPROVED. El paquete está preparado y verificado; aún no se publicó.
No reutilizar la excepción de aprobación concedida solo para F5.

Main y el head del PR tienen el mismo árbol; la app coincide con `4a4cb1ec`
probada. Gate 4.421/298, Chromium 270/0/26, WebKit 10/0 y revisión independiente
PASS. Los tres controles de Main terminaron PASS. ZIP de 117 archivos,
`crm-20260925T054322Z-f9196dba908f.zip`; ver acta para hash y recuperación.

**La versión servida actual es `3027028d`**, publicada por otra tarea, con
79/79 HTML/JS/CSS cotejados. Ya incluye la cola F6 del PR #97 y el Resumen de
Gerencia #100; todavía no incluye la UX horizontal del PR #101. El respaldo
vigente es ese ZIP de `3027028d`, no el F5 anterior `b402a7f1`.

La conciliación productiva del nuevo día dio 11/11 PASS. El gate general CLI
no se midió por falta de variables de servicio. Su consulta a `crm.perfiles`
falló porque la tabla está en `public`; la corrección explícita del esquema
queda corregida y `check:scripts` PASS. La medición SQL de los nueve supuestos registró
290 clientes sin domicilio y las demás condiciones conformes. No confundir
esa lectura con un PASS del CLI ni con siete días completos de observación.

El acceso Hostinger devuelve HTTP401. Se solicitaron dos respuestas a Miguel:
autorizar $release-crm F6 tomando el merge manual como aprobación y restablecer
el acceso al hosting. No repetir preguntas ni imprimir credenciales. La
conformidad manual del recorrido de negocio permanece cerrada.

Acta: `CRM-Avance-Corp/docs/gestion-diaria/f6-ux-gerencia-2026-09-24/PUBLICACION-PENDIENTE.md`.
El mismo Figma distingue la cola publicada y la UX integrada pendiente.

La retirada exige siete días reales estables desde 24/09 21:57:11 Lima: no
antes del 01/10 a esa hora. Sábado 26/09 11:30 pendiente; no hay controles
programados garantizados. Enlaza con
[[Gestion Diaria - F5 publicada y F6 en observacion (2026-09-24)]],
[[Gestion Diaria - cola completa F6 preparada (2026-09-24)]] y [[Inicio]].
