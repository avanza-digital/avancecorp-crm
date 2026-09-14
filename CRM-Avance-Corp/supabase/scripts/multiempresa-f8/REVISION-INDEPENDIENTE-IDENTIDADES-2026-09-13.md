# F8 — revisión independiente del diagnóstico de identidades

Tarea distinta del ensayo original F8 y del cierre de la credencial CLI:
investigar las catorce fuentes pendientes. Codex actuó como PRIMARY y único
autor. Claude recibió únicamente código y evidencia agregada mediante
`scripts/claude-review`, en rol SECONDARY_REVIEWER, sin herramientas ni datos
nominativos. Se usaron dos consultas; la segunda aportó las definiciones vivas
que faltaban y revisó las aclaraciones de la propuesta.

## Dictámenes y decisiones del PRIMARY

1. **CHANGES_REQUESTED:** el diagnóstico y su partición estaban sustentados;
   la propuesta debía precisar procedencia documental, multirrol, paridad,
   altas futuras y autoridad de la clasificación demo.
2. **PASS, confianza MEDIUM, alcance diagnóstico:** tras adjuntar las funciones
   vivas, corregir la consulta y completar el contrato. No implica que haya
   SQL de mutación aplicado, que esté resuelto el piloto o que se hayan pasado
   pruebas de una implementación futura.

Decisiones incorporadas:

- Fuente documental histórica F2 explícita, con actor/canal de captura por
  comprobar, sin usar G6 como verificación documental. READ COMMITTED para la
  futura escritura, preimágenes y rechazo de una identidad concurrente no
  revisada. La consulta de diagnóstico conserva REPEATABLE READ READ ONLY.
- Perfil cliente como ancla económica en el caso multirrol; ninguna asociación
  de permisos por DNI para la cuenta analista, resolución auditada y prueba RLS.
- Clasificación demo bajo control de autoría y auditoría. Avance usa
  `contratos.es_demo`; los cierres usan la exclusión técnica fija ya existente.
  La implementación futura debe controlar ambas rutas y probar un intento de
  eludir la cobertura marcando una fuente real como prueba.
- Fecha, estado y primera conversión desde las reglas vigentes de F4 y
  conciliación pre/post en un mismo corte. No copiar los valores fijos de la
  carga histórica F2.
- La consulta elige documento y tipo de una sola fuente por empresa. También
  busca cierres con el mismo número y colisiones de número entre tipos en
  leads, etiquetándolas como señales, sin atribuirles identidad equivalente.
- Nuevos censos antes del encendido y después de suspensión/vencimiento;
  prueba futura de alta legada con documento inválido y monitoreo de rechazos.

Conclusiones del reviewer que se corrigieron con evidencia:

- **`inversion_id` nulo no bloquea por sí solo F5/F8.** La definición viva de
  `private.cartera_f5_fuentes()` resuelve identidades históricas por perfil o
  cierre/lead, sin exigir una fila `crm.inversiones`. El reviewer aceptó esta
  corrección en el segundo dictamen.
- **No está demostrado que toda venta durante F8 cree otro hueco.** La
  candidata ya habilita el espejo relacional para altas legadas de miembros y
  ajenos mientras su control está vigente; los bancos anteriores lo probaron.
  Sigue sin instalarse en producción. Un documento inválido puede abortar el
  alta completa: no se afirma un hueco persistente sin observar esa transacción.
- **El mapa F2 tiene unicidad por `(fuente, fila_id)`** en
  `backfill_mapa_fuente_fila_uq`. No se añade una agregación para ocultar posibles
  duplicados. La fotografía y el HTML tienen catorce fuentes únicas.

Los controles de escritura, concurrencia, RLS y paridad de la corrección futura
quedan **NOT RUN**. La comprobación visual del informe también es **NOT RUN**
por fallo de inicio de Browser; sí pasaron el parseo y la revisión estructural
local. Evidencia ejecutada y propuesta completa en
[REVISION-IDENTIDADES-2026-09-13.md](REVISION-IDENTIDADES-2026-09-13.md).
