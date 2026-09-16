---
tags: [crm, rls, pruebas, f8, publicacion]
actualizado: 2026-09-16
---

# Matriz RLS global — reparación y candado F8

## Objetivo de la sesión

Dejar publicable [[Eliminar contratos con pagos por administrador - preparado 2026-09-15]]:
administrador puede eliminar contratos con pagos y se conserva copia de auditoría.
Miguel pidió reparar los fallos de la matriz general, no dejarlos como deuda.
El backend de eliminación está instalado. La publicación autorizada de Cartera
incluyó también esta interfaz desde `a09ecad`; 78 recursos HTTP coinciden con
el artefacto. No hace falta volver a publicar ese código para habilitarla.

## Reparación

Se actualizaron firmas y contratos de pruebas desfasados, fixtures de identidad,
campos de métricas, idempotencia, permisos administrativos y exclusión demo.
El correo ahora prueba la API vigente; no omite el bloque de una propuesta retirada.
La prueba de «solo referidos» usa un analista distinto del que recibe llegadas:
antes dependía del orden aleatorio de los UUID del banco.

D-19 detectó además un fallo real: F8 podía activarse con una lectura antigua de
F3 mientras otro administrador lo apagaba. La candidata
`20260916040442_crm_piloto_f8_activacion_serializada.sql` valida F3 bajo candado
y devuelve conflicto reintentable si los candados F3/F8 están ocupados. Así evita
esperar reteniendo la fila F8 y generar un interbloqueo con cambios de configuración.
No activa el piloto ni modifica datos o permisos. F3 sigue siendo apagado general.

## Evidencia y estado

- Matriz local: 1.867 aserciones PASS desde esquema vigente y datos ficticios.
- Concurrencia/operación: original 3 PASS / 5 FAIL; candidata 8 PASS / 0 FAIL.
- Guardas y reversa: 3 PASS.
- Interfaz integrada: 3.632 pruebas y 194 E2E PASS; 26 omisiones conocidas.
- Revisiones: dos CHANGES_REQUESTED, hallazgos evaluados/corregidos y límites
  documentados por el PRIMARY. No se atribuye un PASS al reviewer.
- Rama propia de ensayo: `gefmqtpagmyshukuyzgb`, `rls-vigente-20260916`,
  autorización previa a US$0,01344/h. Cierre y resultado remoto en el acta técnica.
- La nueva migración sigue **pendiente de mostrar el SQL y recibir autorización
  productiva**, conforme a [[Inicio]]. La web ya está publicada.

La matriz exige reconstrucción/seed entre ejecuciones; el ledger se conserva
intencionalmente. Ahora rechaza un banco usado al comenzar con un mensaje claro.
No se debilita RLS para reusar fixtures. Meses cerrados y caso positivo de mes
NULL con facturación no están cubiertos por este banco; límites explícitos.

Código, pruebas, reversa, revisión y resultados:
`CRM-Avance-Corp/supabase/scripts/rls-vigente/`.
Relacionado: [[Nucleo de conversion - diagnostico de llegadas y asignaciones 2026-09-04]],
[[Main unico - sincronizacion y publicacion 2026-09-04]].

## Pausa solicitada

16/09 00:32 Lima: cambios conservados sin commit en clone aislado. Rama temporal eliminada y ausencia confirmada; coste estimado US$0,01632. Remoto: 1865 PASS y un ETIMEDOUT; repetición D-5 local/remota 28 PASS cada una. Cierre documental/advisors e instalación F8 pendientes. Retoma: `supabase/scripts/rls-vigente/PAUSA.md`.

## Retoma y validación cerrada

Miguel pidió «sigamos». La repetición D-5 pasó local/remoto (28 cada una),
y la convivencia con Cartera vigente pasó 17 grupos SQL en otra copia local aislada.
La matriz remota original conserva un ETIMEDOUT; no se falsea como PASS completo.
Advisors: aviso Auth de contraseñas filtradas confirmado como ya presente en
producción antes de F8; ningún hallazgo nuevo atribuible a la migración privada.
SQL, reversa y evidencia listos. Único paso productivo pendiente: mostrar el SQL
exacto y recibir confirmación conforme a [[Inicio]]. La eliminación auditada
ya está publicada y no requiere otro despliegue web.
