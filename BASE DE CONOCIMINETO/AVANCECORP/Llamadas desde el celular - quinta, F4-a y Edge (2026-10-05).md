# Llamadas desde el celular — quinta migración, F4-a y Edge del contrato nuevo (2026-10-05)

**Estado: NADA APLICADO NI DESPLEGADO.** Todo va en el **PR #190 (borrador)**, rama
`crm/llamadas-quinta-migracion-20261005`, y se publica junto (decisión 1 de Miguel). Banco reducido 281/281; Edge
15/15 con 15 mutantes cazados.

## Cómo se llegó aquí
- Miguel fusionó el #178 (análisis de F5–F7) y el #179 (plan v2) el 04/10, **sin comentario ni respuesta a la N1**.
  Jhosep decidió el 05/10 contar la fusión como el OK, con la N1 según la recomendación (la salud del celular sin
  `envios_hoy` ni `ultimo_envio_en`).
- Jhosep decidió que **Codex r2 y auditor-rls van al final**, sobre la quinta + F4-a + la Edge juntas: es la última
  ronda y se publican juntas. Por eso todo crece en la misma rama del #190.

## Lo hecho el 05/10
1. **Quinta migración** (`20261005143843_crm_llamadas_celular_correccion.sql`): recepción de cada aviso en `private`
   antes de buscar el lead (32 días); id `C<n>-<segundos>` con la etiqueta de la asignación y ventana de 30 días;
   contrato `{resultado, mensaje}` sin P0409; candidatos del dueño + bolsa + reutilizables; visibles solo con el lead
   activo; candados resultado → lead → llamada → enlace; entrantes bloqueadas; retención decidida; salud sin envíos;
   bandeja duplicada retirada.
2. **F4-a** (`20261005155914_crm_llamadas_celular_enlace_exacto.sql`): `crm.registrar_llamada_v5` registra como la v4
   (sin tocarla) y une el resultado a su llamada por el id exacto; si el aviso no llegó, deja una intención que la
   ingesta cumple. Sin la regla de 10 minutos en este camino. Vía del enlace (`al_colgar`, `pestana`, `manual`).
   **Decisiones de Jhosep:** un enlace imposible no impide guardar el resultado; la llamada ambigua va a la pestaña.
3. **Edge** con el contrato nuevo: solo revisa el transporte (405, 415, 401, 413); todo lo demás llega a la base, que
   dice aceptado o inválido; sin 409.
4. **Revisión del agente de Miguel (16:16 UTC): CHANGES_REQUESTED** por un [P2] reproducido: la reversa de la quinta
   volvía a correr cuando la purga retiraba las recepciones a los 32 días. Corregido en `260c0a4a`: las reversas de la
   quinta y de F4-a solo corren **antes de dar de alta celulares**, con regresión y mutante. Respondido en el #190.

## Pendiente con Miguel
- La N1, los criterios de Claude y el efecto de visibilidad del descartado reutilizable (comentario del #190, 15:49 UTC).
- Que su agente revise `260c0a4a`.
- Al final: Codex r2 y auditor-rls sobre todo junto, ensayo en su banco y publicación con la barrera.

## Lo que sigue
- Paso 4: el bloque `testLlamadasCelular` del gate (todavía exige P0409 y no conoce la v5).
- Paso 5: guías de publicación y de la macro «sin Pro».
- Para cerrar el fallo 5 de verdad falta un trozo de F4-b: que F1 lleve el id hasta la encuesta y la encuesta llame a
  la v5.

## Lecciones
- **«Ahora está vacío» no prueba «nunca se usó»** (el [P2] de Miguel). Una guarda que mira tablas con purga se vuelve a
  abrir sola; hay que mirar algo que no se borra (las asignaciones).
- **En un oráculo, `<>` contra un valor nulo calla.** Tres mutantes de F4-a sobrevivían porque el motivo venía nulo;
  se usa `is distinct from`.
- **Las reversas también tienen orden**: la de la quinta se podía correr con F4-a puesta. Ahora cada reversa se niega
  si la siguiente sigue instalada.
- **Copiar cuerpos con un guion desde el blob de git** (reversas, ingesta y purga de F4-a) y comparar la huella del
  catálogo evita los errores de transcripción.

## Relacionado
- [[Llamadas desde el celular - decisiones de Miguel y plan v2 (2026-10-03)]]
- [[Llamadas desde el celular - revision antes de publicar (2026-10-02)]]
- [[Llamadas desde el celular - pruebas de MacroDroid en C1 (2026-10-02)]]
- Plan v2: `CRM-Avance-Corp/docs/plans/llamadas-celular/CORRECCION-PLAN-CORTO.md`; F4: `F4-PLAN-CORTO.md`.
- Ledger: `CRM-Avance-Corp/supabase/migrations/MIGRACIONES.md` (entradas `20261005143843` y `20261005155914`).
