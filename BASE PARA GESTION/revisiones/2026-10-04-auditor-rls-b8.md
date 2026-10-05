# auditor-rls · B8 (04/10)

**PASS** con condición de despliegue (P2): el front publicado debe aceptar `base_cargada` y el capital vacío antes de
cargar ninguna base → ya cumplida (F5a en producción, `73c9b908`). Sin fugas fuera del ámbito del actor (rol resuelto en
el servidor; base sin delatar existencia; `lead_id` solo si es visible). Válvula `crm.op_bases_carga` solo alrededor del
INSERT y no encendible por un cliente. Las tres funciones vivas modificadas solo cambian lo declarado. Sin efectos (SLA,
ledger, llegadas, Descartes del mes). P3 aplicados en la r1: CHECK `enfriamiento_politica_base_cargada_dias_positivos`;
no devolver id de un retirado; fuera del ámbito solo `ya_existia` sin motivo (decisión del PRIMARY sobre la «consulta
masiva»); armar por gerencia con el subárbol del supervisor dueño. Para B10: los dormidos sin repartir saldrían en
«Gestión de la base» (F4) por `obtener_base_gestion`.
