# Citas: ticket mensual y CSV sobre el corte aceptado

Estado: candidata local `20261016233037_crm_citas_capital_corte.sql`, sin publicar.

`calcularAvanceCitas` convertía todo el USD mensual con la cotización del día o
fin de mes. Ese importe alimentaba el ticket y la proyección, y se exportaba en
el CSV. Son ventas confirmadas: desde octubre deben sumar los equivalentes de
las operaciones del mismo corte aceptado. La proyección sigue siendo estimada;
su componente de capital ya cerrado y el ticket observado utilizan el corte.

## Contrato y permisos

- Nueva `crm.citas_gerencia_consulta_v2_fn(date,date)`. La puerta anterior no
  cambia. Septiembre y meses abiertos con presentación desactivada devuelven
  exactamente el payload original. Solo PGRST202 permite compatibilidad en el
  cliente; errores de permiso, integridad o timeout no caen a datos antiguos.
- Se conservan las dos fuentes monetarias del lector original: población
  vinculada y capital. Ambas leen `capital_cortes_valorados.base`; no se unen
  equivalentes viejos a importes/fechas vivos después de una corrección.
- Se reutiliza el cuerpo original con guarda MD5 y anclas contadas. Sus citas,
  cohortes, contactos, identidad, filtros y testigo de Gerencia mantienen las
  reglas vigentes. Solo Gerencia y supervisión autorizada acceden a identidades.
  El ámbito actual de supervisión filtra también las operaciones del corte.
- Citas utiliza stock **sin anulados** y el analista del núcleo stock. Ranking
  ATR-4 puede conservar el capital anulado y tiene su atribución comercial
  propia. Son medidas diferentes; no se obliga a cuadrarlas borrando esa regla.
- La identidad canónica del capital se guarda en `base` al publicar. Vincular o
  unificar personas después no cambia el divisor del ticket aceptado. Una nueva
  publicación completa puede incorporar la nueva identidad sin revaluar dinero.
  La ampliación protege también el cuerpo del publicador con MD5. Un corte que
  carezca de esta identidad requiere nueva publicación; no se reconstruye el
  divisor vivo sobre una foto sellada.
- No se modifica ningún objeto de `public`. Helpers privados revocados;
  únicamente authenticated recibe EXECUTE de la nueva RPC, con puerta de rol
  dentro de la función y `search_path=''`.

## Presentación y exportación

Los equivalentes se suman en céntimos; el divisor sigue siendo la cantidad de
personas con capital elegible en el mismo corte. Sin primer corte, ticket,
capital y proyección quedan pendientes. Si falta una corrección, se conserva el
último corte completo y se muestra su cobertura. Un mes sellado conserva su
referencia aun después de suspender la presentación.

La pantalla no solicita otra cotización en modo valorado. El módulo muestra el
avance aunque haya ventas y ninguna cita/asignación; el guard anterior ocultaba
esos casos. Los filtros de actividad y persona conservan su significado.

El CSV comparte el modelo calculado de pantalla y conserva las 31 columnas
anteriores. Añade capital confirmado en soles, régimen, referencia/fecha del
corte y cobertura del ámbito CRM. Las columnas de tasa mensual y fecha de tasa
quedan vacías en modo por venta. El origen dice «Valoraciones por operación».
Mantiene BOM y protección contra fórmulas. Cobertura del ámbito CRM no afirma
ser un conteo recalculado por cada filtro local de la tabla.

## Evidencia

- Replay final de diez candidatas: 89 aserciones de cortes/permisos/escritores,
  incluidas 14 específicas de Citas; rollback y clon propio eliminado. La
  huella de catálogo confirma que `public` permanece intacto.
- SQL: paridad exacta de septiembre y política apagada; Gerencia/supervisión;
  denegación de Coordinación/Directorio/vendedor/inactivo; primer corte ausente;
  anulados; ámbito tras reasignación; corrección pendiente; identidad viva que
  cambia sin alterar la aceptada; sello tras suspensión y otra tasa.
- Fixtures ejecutados en SQL, sintéticos, en `app/test-fixtures/capital-valorado/`.
  `--fixtures-citas` regenera solo estos cuatro, sin tocar los anteriores.
- API/modelo/UI/CSV dirigidos: 97 PASS antes de añadir dos regresiones del
  módulo completo sin citas. Las dos regresiones ya se corrigieron (10 tests
  del archivo PASS); gate integral de 6 755 tests PASS en ESTADO.md.
- E2E Docker: tres escenarios legados PASS; dos nuevos PASS tras corregir el
  guard que ocultaba las ventas sin citas. Escritorio y móvil, descarga CSV,
  cambio 3,10 → 3,80, último corte pendiente y primer corte ausente.

Los E2E interceptan HTTP: no acreditan Auth/HTTP real ni ejecución productiva.
Las migraciones y la política siguen sin publicarse ni activarse.
