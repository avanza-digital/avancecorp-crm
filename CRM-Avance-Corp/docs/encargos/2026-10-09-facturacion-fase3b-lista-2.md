# Encargo 2 a Codex (IMPLEMENTADOR) — Facturación 3B: cambios de las revisiones y de la decisión de Miguel

ROLE: IMPLEMENTER delegado por Claude (PRIMARY).
- Escribes SOLO dentro de este worktree. Sin commit, red, Docker ni producción, y sin otros agentes.
- Español. Nivel 3. Trabajas SOBRE lo que ya existe: migración `20261009234500`, kit
  `supabase/scripts/facturacion-lista/`, `test-rls.mjs` y `MIGRACIONES.md`.
- Base: `docs/encargos/2026-10-09-facturacion-fase3b-lista.md`. Las reglas de ese encargo siguen vigentes salvo lo que
  cambia aquí.

## Lo que hizo el PRIMARY desde tu entrega (no lo deshagas)

- **Resolución del inversionista canónico:** tu copia recursiva se sustituyó por la llamada a
  `private.inversionista_canonica(ce.inversionista_id)`, con un `left join lateral` solo para las filas de la página y
  solo si quien mira no es global. Medido: 93 llamadas, 1,1 ms. Su cuerpo vivo (md5 `34702897…`) ya está en `vivo/`.
- **Prueba de filtros:** usa el mes con MÁS operaciones.
- **Siembra del ensayo sintético:**
  - sin `beneficiario_dni*` (un trigger manda los datos bancarios a `cuentas_bancarias`);
  - con capital ≥ 100 (el catálogo rechaza fotografiar contratos fuera de 100..100 000 000).
- **Huellas medidas antes de este encargo:** núcleo `6596155d…` y puerta `f3b53fbe…`. Van a cambiar: vuelve a poner
  `'PENDIENTE_MEDIR_EN_BANCO'` en las dos, y las mediré yo.
- **Banco:** todo PASS (ciclo, gate y ensayo con cinco mutantes).

## Cambios a implementar

1. **DECISIÓN DE MIGUEL (09/10 noche): Directorio ve las COOPERATIVAS como «Cliente de otro equipo», igual que en el resto
   del CRM.**
   - El auditor comprobó que hoy Directorio no ve clientes de cooperativas en ninguna pantalla: `cierres_externos_fn` no
     le da filas y la cartera es `solo_avance`.
   - Los contratos sí los ve con nombre. Gerencia lo ve todo.
   - Implementarlo con dos banderas EXPLÍCITAS, sin depender de que `vendedor_ids_visibles` devuelva vacío para
     Directorio:
     - contratos: «todo visible» = Gerencia o lector global;
     - cooperativas: «todo visible» = solo Gerencia.

     Para Directorio, una cooperativa nunca es visible.
   - Ajustar comentarios, LEEME, oráculo, ensayo y gate. La comprobación «Directorio = Gerencia» pasa a ser:
     - mismas operaciones, total y totales;
     - mismas filas de contrato;
     - toda cooperativa enmascarada para Directorio.
2. **ORÁCULO POR POSICIÓN** (Codex revisor, P2-1 y P2-2). En `pg_temp.f3b_comparar`, además de lo que ya compara con la
   cifra:
   - calcular la SECUENCIA esperada desde `private.facturacion_operaciones_visibles` (mismos límites y filtros), ordenada
     por `(fecha, tipo, operacion_id)`, y exigir fila a fila, por `n`, igualdad de `fecha` (día de Lima), `tipo`,
     `moneda`, `monto`, `anulado`, `analista_id` y `supervisor_id`;
   - la VISIBILIDAD esperada se calcula de forma independiente:
     - Gerencia: todo visible;
     - contrato: `cliente_id ∈ private.cliente_ids_visibles_crm()`, o Directorio;
     - cooperativa: nunca para Directorio. Para los demás no globales, con inversionista se usa exactamente la regla del
       teléfono vivo de `crm.cierres_externos_fn`:
       `exists (select 1 from crm.inversionistas ip where ip.id = private.inversionista_canonica(ce.inversionista_id)
       and ip.responsable_relacion_id = any(private.vendedor_ids_visibles(auth.uid())))`;
       sin inversionista, el `vendedor_id` del lead pertenece a ese conjunto.

     Se exige que `visible` coincida.
   - en las filas visibles, los ids coinciden con los de la operación esperada:
     - contrato: `contrato_id`, `cliente_id` y `numero_contrato`;
     - cooperativa: `cierre_externo_id`, `lead_id` y `cooperativa`.
3. **RESPUESTA COMPLETA** (Codex revisor, P2-3):
   - claves EXACTAS del objeto raíz (`version`, `pagina`, `tamano`, `total`, `totales`, `filas`) y de cada elemento de
     `totales` (`moneda`, `operaciones`, `monto`);
   - la búsqueda de documentos se hace sobre CADA respuesta entera (`v_respuesta::text`), no solo sobre las filas. Igual
     en el gate.
4. **MÁS FUENTES DE DOCUMENTO** (auditor P3-7), en el oráculo y en el gate: `crm.leads.dni` del lead de cada operación y
   `crm.inversionista_identificadores.documento_normalizado` y `documento_original` de su inversionista. Se suman a
   `perfiles.dni`, `beneficiario_dni*` y `cierres_externos.documento`.
5. **`p_sin_analista boolean default false`** (auditor P3-5) justo DESPUÉS de `p_analistas`, en la puerta y en el núcleo.
   - Filtra `analista_id is null`, la fila «Sin analista» de la cifra.
   - Con `p_analistas` da 22023.
   - Va en la prueba de filtros del oráculo y en las negativas.
   - Actualizar TODAS las firmas: regprocedure del PREFLIGHT/POSTFLIGHT, censo del bloque L, reversa, registrador,
     generadores, ensayos y gate.
6. **GATE de la capa 2** (auditor P2-2), en `testFacturacionLista`:
   - sup1 y sup2 tienen ≥ 1 fila enmascarada en el mes, y su número coincide con un conteo independiente fuera de banda
     (identidad por los GUC, transacción de solo lectura);
   - hay ≥ 1 contrato visible con nombre y N.º;
   - todo `cliente_id` visible pertenece al conjunto esperado del fixture: asesor en el subárbol, o asesor nulo y
     `creado_por` en el subárbol;
   - una cooperativa cuya identidad canónica es de otro equipo sale enmascarada;
   - añadir la sesión `sup1Nested`;
   - fijar fuera de banda el md5 de las dos funciones, LEYÉNDOLO del bloque `HUELLAS` de la migración (una sola fuente,
     no constantes copiadas).

   Si la semilla del banco no tiene contratos entre equipos ni cooperativas en ese mes, crear el fixture fuera de banda
   SOLO para este bloque y retirarlo al final, con el patrón de limpieza de los otros bloques. NO cambies la semilla
   global y documenta la elección.
7. **ENSAYO SINTÉTICO** (auditor P3-4 y Codex revisor):
   - casos nuevos:
     - «inversionista propio», que debe salir visible;
     - «alias fusionado»: un alias con responsable propio cuya identidad canónica es de otro equipo, que debe salir
       enmascarado;
     - Directorio: contratos visibles y cooperativas enmascaradas.
   - mutantes nuevos, cada uno cazado SOLO por su SQLSTATE propio:
     - cooperativas siempre visibles;
     - todo enmascarado para los no globales;
     - sin `inversionista_canonica` (usar `ce.inversionista_id` directo);
     - Directorio ve las cooperativas;
     - fila duplicada con el mismo importe y orden;
     - clave extra con un documento en el objeto raíz;
     - `p_sin_analista` ignorado.
   - los cinco mutantes de antes se conservan.
8. **`medir.sql`** (auditor P3-3): además de Gerencia, mide como el supervisor con MÁS operaciones de cooperativa en
   septiembre y octubre, que es la ruta no global con el lateral. Mismo límite de 150 ms. Las dos rutas van en el mensaje
   final.
9. **CABECERA NEUTRA** (auditor P3-2): el texto de la migración no lleva «EN BANCO, SIN APLICAR», porque queda grabado
   en `schema_migrations`. Usar el estilo de la 3A: qué hace, precondición (3A aplicada y registrada) y reversa. El
   estado vive en el ledger y en el LEEME.
10. **COMENTARIOS EXACTOS** (auditor P3-6): la regla de cooperativas es la de la RELACIÓN de hoy, es decir, la del
    teléfono vivo de «En cooperativas». Es más estricta que el reparto de filas de esa sección, que va por
    `analista_efectivo_cierre`. No digas «la misma pieza que En cooperativas».
    - Excepción EXPLÍCITA del contrato: la fila de otro equipo conserva analista, supervisor, día, tipo, moneda, importe
      y `anulado`, que ya muestra la cifra o explican por qué cuenta. Ni un id del cliente, contrato, cierre ni lead.
      Escríbelo en el COMMENT de la puerta y en el LEEME.
11. **LEEME y MIGRACIONES.md con estado HONESTO:** «en banco, sin aplicar», con las huellas como PENDIENTE (las mido yo),
    la evidencia de banco anterior, las dos revisiones (aceptado/rechazado) y la decisión de Directorio.
    - Rechazado con motivo: retirar de la fila enmascarada analista, supervisor y anulada (excepción explícita del punto
      10).
    - Riesgo anotado: `private.facturacion_lista` depende de `cliente_ids_visibles_crm`, `vendedor_ids_visibles`,
      `inversionista_canonica`, `rol_crm` y `es_lector_global`, y hay que re-auditarla si cambian.

## Verificación offline al terminar

Generadores con `--verificar`, `test_generadores.py`, `node --check supabase/scripts/test-rls.mjs` y `git diff --check`.
Informe breve, con lo que no pudiste hacer.
