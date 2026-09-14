---
tags: [crm, multiempresa, f8, piloto, verificacion]
fecha: 2026-09-14
estado: parcial-timeout-ficha-g7-abierto
---

# F8 — primer caso real verificado

El solicitante confirmó que realizó la prueba y pidió verificaciones antes de
comunicar sus observaciones. Se identificó una inversión adicional en Qorilazo
de PEN 4,500 sobre una persona que ya tenía PEN 4,500 en Prodelco. La primera
conversión ocurrió antes del encendido del piloto; la segunda inversión sí se
confirmó dentro de F8. Identidades y referencias nominales se excluyen del vault.

PASS SQL: una identidad canónica y un lead, dos fuentes que suman PEN 9,000,
solicitud confirmada una vez, comprobante privado vinculado y un depósito
reclamado. Lista/ficha del analista y núcleo de capital coinciden. Conversión
cuenta un solo cliente. Cinco firmas de tablas del caso no variaron durante
la comprobación. No se crearon ni reenviaron operaciones económicas.

La inversión de Qorilazo conserva la fecha comercial e imputación 11/09 que
ya traía la solicitud. Su registro ocurrió el 14/09. No afirmar que corresponde
a la facturación del 14/09 ni que la elección de esa fecha fue observada en UI.
La referencia libre `upgrade` no prueba una operación contractual de Avance.

Hallazgo P1 abierto G7-R01: la ficha de supervisor y Gerencia excede 20 segundos
en `crm.inversionista_ficha_fn` → `private.cartera_f5_personas_visibles`.
Los roles de acceso tienen 8 segundos configurados. La ficha del analista pasa
con ese límite; el listado de supervisor/Gerencia también falla bajo 8 segundos,
comprobado por el PRIMARY después del review de Claude. La otra analista queda
excluida.
Postventa autoriza a analista,
supervisor y Gerencia, y rechaza al actor sin ámbito. No atribuir a permisos
incorrectos las consultas F5 que no terminaron.

La raíz del coste todavía requiere medir el plan en un entorno de ensayo;
la materialización amplia y las resoluciones canónicas repetidas son hipótesis.
La futura corrección debe permanecer en los núcleos compartidos, conservando
autorización, fusiones y exclusión demo. No se cambió código ni configuración.

UI, Auth/HTTP y descarga/contenido del comprobante: NOT RUN, ningún navegador
conectado. Se usaron contextos SQL con `ROLLBACK`, no logins reales. No hubo
prueba de reintentos, carrera o nueva tarea de postventa en este caso.

G7 sigue ABIERTO, sin firmas nuevas; F7 conserva OFF y comisiones externas.
Recoger las observaciones del solicitante y resolver el timeout antes de
considerar completada la validación multirrol.

Evidencia y revisión independiente:
`CRM-Avance-Corp/supabase/scripts/multiempresa-f8/recorrido-real-2026-09-14/`.
Acta: `CRM-Avance-Corp/supabase/scripts/multiempresa-f8/ACTA-G7.md`.

Antecedente: [[F8 - piloto nominal activado (2026-09-14)]].
Plan: [[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]].
