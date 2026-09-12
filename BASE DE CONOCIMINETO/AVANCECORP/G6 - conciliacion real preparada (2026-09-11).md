---
tags: [crm, multiempresa, f7, g6, conciliacion, retomar]
fecha: 2026-09-11
estado: lectura-verificada-aceptacion-humana-pendiente
---

# G6: comparativo real preparado

Continúa [[F7 - publicada y apagada (2026-09-11)]] y
[[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]].
Miguel autorizó preparar la conciliación real. La lectura técnica está lista;
**G6 sigue abierto hasta la conformidad de Miguel y del responsable financiero**.

Corte final de producción: **11/09/2026, 17:51:44 Lima**. Agosto completo y
septiembre hasta el día 11: **218 inversiones** (161 + 57), ocho grupos de
empresa/moneda, sin diferencias de capital, conversión global ni atribución.
La comprobación compara cada fuente económica y números exactos en PostgreSQL,
además del contrato real del consumidor. La foto cerrada de agosto (16 filas),
diez funciones, conteo de 275 migraciones y banderas coinciden en la lectura posterior.

**F3 ON; F4/F5/F6/F7 OFF.** Se evaluó el SELECT de F7 instalado con la RPC de
cifras apagada; transacciones administrativas de solo lectura, sin migraciones,
backfill, dinero, activaciones ni nuevos usuarios. Comisiones fuera del CRM,
según [[F4 cerrada - comisiones fuera del sistema (2026-09-08)]].

## Cobertura que hay que explicar al revisar

- 580 fuentes históricas: 570 con identidad coherente y diez sin identidad.
  Sus importes están incluidos; los titulares no resueltos no cuentan entre
  las 434 personas identificadas. Anexo privado con los diez registros.
- 566 fuentes legado sin fila relacional F4. Es cobertura admitida por la
  lectura, no 566 nuevas regresiones. No se saneó ni se dio por resuelto el
  inventario histórico de quince huecos de F4/F5.
- Cuatro operaciones fuera del ranking en agosto y una en septiembre,
  incluidas con capital, referencia y responsable en el comparativo.
- Cero cotitulares, personas en varias empresas o personas con veto presentes
  en este universo. Esos recorridos reales siguen NOT RUN; los casos sintéticos
  F7 no se presentan como aceptación de cifras reales.
- Agosto compara conversión con la foto sellada; septiembre comparte el
  núcleo del reporte publicado. Esto es paridad interna, no contabilidad externa.
- La captura inicial tenía 217 operaciones. El corte final incluye una nueva
  inversión registrada durante el trabajo; no es una duplicación.

## Abrir y retomar

Comparativo en el Escritorio:
`Revision G6 - AVANCECORP 2026-09-11/Comparativo G6.html`.
Es un archivo local autónomo, sin conexión externa ni acciones de aprobación.
Incluye agosto/septiembre, importes de ambos informes, responsables y anexos.

[Acta G6](../../CRM-Avance-Corp/supabase/scripts/multiempresa-f7/ACTA-G6.md)
y [procedimiento](../../CRM-Avance-Corp/supabase/scripts/multiempresa-f7/g6/README.md).
Respaldo privado: `/Users/usuario/.codex/backups/avancecorp-g6-20260911`.
Captura SHA-256 `5a430de720f1f28468845e47957951fbed46a67026e58577001e69d560080ab1`.
Nombres, referencias e importes permanecen fuera de Git; allí solo hay código,
plantillas, dictámenes evaluados y resumen técnico sin datos personales.

Sigue revisar las cifras concretas, aceptar sus límites de cobertura y dejar
constancia en el acta. Solo entonces se podrá solicitar el piloto F8/G7;
F9/G8 requiere activación progresiva y un ciclo operativo mensual completo.
No reabrir el banco F7 cerrado ni reinstalar lo ya publicado.

Claude: primera revisión CHANGES_REQUESTED evaluada y corregida con evidencia.
La segunda respuesta fue incompleta (wrapper exit 1): no hay dictamen final
válido ni aprobación final de Claude. Detalles en el acta enlazada.

## Retoma y sincronización del 11/09

Miguel pidió continuar. Se completó el envío de la integración `f74f48d` a
`avancecorp/main` y `avancecorp/codex/f7-metricas`, conservando los tres avances
paralelos de Facturación. Lint, typecheck y build PASS; el gate de push pasó
**3.404 pruebas en 235 archivos**. Main local y remoto se verificaron iguales.
Esta sincronización no desplegó un nuevo CRM ni activó banderas. El comparativo
conserva el corte de las 17:51 y su hash, cotejado contra el respaldo privado.
Ya se abrió de nuevo para revisión. Ambas conformidades siguen pendientes;
la solicitud de continuar no se registra como firma G6 ni autorización F8.
