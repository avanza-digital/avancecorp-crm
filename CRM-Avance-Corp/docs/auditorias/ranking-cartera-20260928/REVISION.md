# Ranking: cartera y procedencia — revisión 28/09/2026

Codex PRIMARY. Claude SECONDARY_REVIEWER por `scripts/claude-review`, sin
herramientas ni escritura. Dictamen CHANGES_REQUESTED, evaluado por PRIMARY.
El primer intento falló por red; el intento autorizado entregó el dictamen.

## Resolución con evidencia

- COOPAC (P1 condicional): descartado. El cuerpo compilado adjunto muestra
  `left join vinculos l on l.id = ce.lead_id`; no existe otra ruta para `l`.
  En Avance el nuevo fallback sigue después de directo, cliente, ledger y
  acreditado, conservando incluso sus ambigüedades.
- Mes cerrado (P2 condicional): descartado con cuerpo vivo.
  `cumplimiento_metas_sin_cartera_fn` lee `crm.periodos_cerrados` por el mismo
  periodo y publica `cierre.cerrado=true` si encuentra fila, false en otro caso.
  `cumplimiento_metas_fn` preserva esa clave. Ambas RPC son STABLE y comparten
  el snapshot del statement. El ensayo comprueba también la igualdad del flag.
- Validación secundaria (P2): aceptado. `cartera` malformada degrada a NULL;
  el resto de orígenes válidos sigue visible. El fallback financiero existente
  solo se muestra si concilia ambas monedas. Prueba de categorías inválidas PASS.
- Sello (P2): ampliadas aserciones. `_10_ranking_origen` precede a
  `_11_ranking_cartera`; `trg_cierre_mes_append_only` rechaza todo UPDATE/DELETE
  sin lista de columnas. Ensayo real guarda Nueva inversión 55.000 PEN,
  comprueba columna no NULL, inmutabilidad, independencia de solicitudes vivas
  y fotos antiguas NULL. No existe una ruta de UPDATE para volver a sellar.
- Consumidores/tipos (P2): no hay lecturas directas de `cierre_mes_vendedor`
  en app/src fuera del archivo de tipos. Tipos regenerados por CLI desde la
  rama (public,crm): solo tres campos y firma RPC v2 añadidos. Ledger actualizado.
- Revisión de metas (P3): ambos helpers eligen `revision desc limit 1`.
- Filas cero (P3): se oculta Nueva inversión cuando ambas monedas son cero.
- WARNING del sello (P3): se conserva la política existente; un desglose
  secundario no bloquea el cierre financiero. Aserciones nuevas detectan NULL
  accidental antes de publicar.
- Timeouts (P3): no se reescribe la primera migración ya versionada. Su ALTER
  es aditivo/nullable; la tabla productiva estaba vacía y el ensayo completo
  fue inmediato. La segunda migración ya limita lock_timeout a 5 s y statement
  a 90 s. No se modifican defaults productivos para aplicar este cambio.
- Rendimiento: índices UNIQUE existentes sobre inversiones.contrato_id,
  inversiones.cierre_externo_id y solicitudes.inversion_id. Sello de 34
  analistas/2.048 leads probado. El segundo lector se consulta solo al abrir ficha.

## Verificación

PASS: check integral 4.763 pruebas / 313 archivos; lint, tipos, cobertura,
build, bundle y duplicación. PASS Docker completo: 280 passed / 26 skipped,
0 failed. PASS focal desktop/mobile. PASS Auth/HTTP v1 y v2: gerencia y equipo
propio permitidos, equipo ajeno/inactivo/cliente/anónimo denegados. PASS pruebas
SQL de captura, fuente exacta, solicitud pendiente, COOPAC, conciliación y sello.

Advisors: nueva advertencia de RPC SECURITY DEFINER v2 intencional, con la
misma puerta autorizadora de v1 y pruebas de denegación reales. Helpers privados
sin EXECUTE para API. El cambio de avisos de índices sin uso deriva del banco
sin tráfico productivo; no se añadieron índices. Control analítico: 0 pendientes.

## Límite de datos

Miguel confirmó la cuenta demo del contrato terminado en 666666; se utilizó
`public.marcar_contrato_demo` con motivo auditado, sin borrar contrato ni cuotas.
El capital de prueba queda excluido por el núcleo existente. La procedencia del
contrato real terminado en 000670 no está acreditada; una coincidencia de correo
se descartó por identidad diferente. No se adivina el canal ni se crea un lead.
