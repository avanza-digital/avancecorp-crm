---
tags: [crm, gestion-diaria, typesafe, piloto, decisiones]
estado: preparación local — sin datos reales, SQL ni publicación
fecha: 2026-09-21
---

# Gestión Diaria F4.1 — banco humano y reglas de cortes

Miguel pidió preparar el piloto y cerrar pendientes con apoyo de Claude. Confirmó
tres reglas de F4: sábado mínimo tres llamadas a las 11:30 (jornada 09:00–13:00);
excluir de avisos de corte a analistas sin leads abiertos asignados, sin ocultarlos
en tabla; «Posponer 1 hora» una vez por aviso/supervisor/día Lima, sin reaviso al
cierre o después (18:00 L–V; 13:00 sábado) ni traslado al siguiente día. El pendiente
sigue visible según las reglas de resolución del primer y segundo corte. No extender
la exclusión a otras alertas. Estas decisiones están cerradas, no instaladas ni activadas.

Se preparó `CRM-Avance-Corp/scripts/gestion-diaria-typesafe/banco.mjs`:
`npm run gestion-diaria:banco` desde CRM, URL `http://127.0.0.1:5274/`.
Ambos supervisores revisan los mismos veinte ejemplos ficticios uno a uno y sin
ver las respuestas esperadas ni del modelo. A/B son espacios sin autenticación,
no permisos reales de equipo. El servidor escucha solo en loopback; no recibe
respuestas, claves ni datos del CRM. No se debe exponer a la red ni usar con notas reales.

La exportación/reanudación valida versión, huella, espacio e IDs; no incluye notas
ni identidad. «Duda sobre el criterio» queda aparte de «información insuficiente».
El comparador reporta acuerdo y pendientes, nunca calidad del modelo ni permiso
para enviar datos reales. Las pruebas usan respuestas ficticias, no humanas.

Guía en `CRM-Avance-Corp/docs/gestion-diaria/F4.1-GUIA-REVISION-HUMANA.md`:
rúbrica, resolución de desacuerdos, muestra total 100–200 repartida entre equipos,
separación por lead de ajuste/validación, mínimos e intervalos por equipo y
criterios propuestos todavía no aprobados. Cada supervisor verá solo notas reales
de su equipo en el futuro. Los casos compartidos ahora son únicamente ficticios.

La revisión pública del proveedor confirma compromiso de no entrenar con entradas,
pero no un plazo fijo ni ZDR en nuestra cuenta. Antes de la primera nota real faltan
rotación de clave, condiciones de tratamiento/retención aceptadas, criterios y
presupuesto acordados, muestra autorizada y etiquetas. No se contactó al proveedor.
Fuentes oficiales enlazadas en la guía; no se infiere cumplimiento legal.

Verificación y revisión independiente de esta entrega:
`CRM-Avance-Corp/docs/gestion-diaria/F4.1-BANCO-HUMANO-2026-09-21.md`.
No se toca la etapa 2 publicada (`baa63aea`) ni se instalan cortes. Su siguiente
implementación es F4 etapa 3; TypeSafe no la bloquea.

Solicitud posterior del 21/09: Miguel pidió «publica y ejecuta» y actualizar el
plan. Se comprobó que `8f1d009d` no añade aplicación productiva ni SQL/Edge de
cortes: contiene banco local, pruebas y documentación. Se pidió precisar entre
implementar/publicar F4 etapa 3 y compartir el banco ficticio. El plan principal
registra esta distinción; no se presenta la solicitud como un despliegue realizado
ni se ejecuta SQL de trabajos ajenos. Publicación/activación continúan pendientes.

Relacionadas: [[Gestion Diaria F4.1 - TypeSafe tecnico y piloto humano pendiente (2026-09-21)]] ·
[[Gestion Diaria F4 - objetivos y piloto TypeSafe (2026-09-20)]] · [[Inicio]].
