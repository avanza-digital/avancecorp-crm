---
tags: [crm, gestion-diaria, typesafe, piloto]
estado: ensayo técnico local comprobado — piloto humano e integración productiva pendientes
fecha: 2026-09-21
---

# Gestión Diaria F4.1 — TypeSafe técnico y piloto humano pendiente

Miguel pidió TypeSafe en dos usos: posibles contradicciones entre notas y resultados
en Gestión Diaria, y apoyo técnico a las revisiones de código. El 21/09 confirmó que
**un supervisor validará el piloto y nos indicará quién**. No escogerlo automáticamente.

El acceso local a la API se verificó con `jev-1.13.0`. Se creó un ensayo de 20 notas
sintéticas, sin extracción del CRM ni etiquetas esperadas en la petición. La primera
prueba compartía el estado de los casos: 20/20. Tras la revisión de Claude, cada nota
se evaluó aisladamente: 19/20, una falsa alerta en «Se gestionó», con confianza 0,26.
Se guarda el fallo; no se ajustó un umbral para esconderlo ni se considera calibración.

El apoyo técnico existente se usó para ordenar tres extractos. Jev colocó primero el
constructor del estado, pero ninguno llegó al corte de 2 puntos: no acredita por sí
solo una conclusión. Codex sigue siendo PRIMARY; Claude revisa mediante el wrapper,
sin herramientas ni ediciones. Jev no reemplaza las pruebas ni evalúa al trabajador.

Verificación local: 14 tests nuevos PASS; 22 tests del toolkit Jev existente PASS.
Sin cambios de frontend, SQL, Edge o cron; sin datos reales enviados ni publicación.
La skill `typesafe-ai` orientó las tres salidas tipadas, el estado mínimo, la separación
de incertidumbre/fallos y la obligación de medir antes de activar.

Próximo paso: recibir el nombre del supervisor, acordar anonimización y criterios,
preparar 100–200 notas con etiquetas humanas y una validación independiente del ajuste.
Después se decide si construir/activar las sugerencias con permisos por equipo,
caché versionada y revisión humana. Cualquier SQL requiere autorización específica.

Plan único: `CRM-Avance-Corp/docs/gestion-diaria/GESTION-DIARIA.md`.
Acta técnica: `CRM-Avance-Corp/docs/gestion-diaria/F4.1-TYPESAFE-ARRANQUE-2026-09-21.md`.
Código preparado en `codex/gestion-diaria-typesafe-piloto`, taller existente
`/private/tmp/avancecorp-gd-f4-vista.chvRqh`. No integrar a ciegas sobre el trabajo
concurrente de Main; solo se reutilizó su cliente Jev, byte a byte.

Relacionadas: [[Gestion Diaria F4 - objetivos y piloto TypeSafe (2026-09-20)]] ·
[[Gestion Diaria F4 - detalle del analista preparado (2026-09-21)]] · [[Inicio]].
