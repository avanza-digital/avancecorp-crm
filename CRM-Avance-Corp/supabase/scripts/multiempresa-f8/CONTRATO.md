# F8 — contrato del piloto económico

## Acceso

- Participan exactamente cuatro perfiles vigentes: Gerencia, un supervisor y
  dos vendedores.
- Cada llamada vuelve a comprobar `public.perfiles`, `crm.equipo`, rol,
  membresía temporal y ventana del piloto.
- Ser la misma persona comercial en varios roles o empresas no propaga permisos.
- Cada rol conserva su alcance previo: vendedor sobre sus responsables,
  supervisor sobre su equipo y Gerencia sobre la cartera global.
- Directorio, coordinadores, usuarios ajenos, `anon` y `service_role` no reciben
  el piloto por pertenencia implícita.

## Capacidades

- F4: permite las escrituras relacionales ya protegidas por el motor publicado.
- F5: muestra la Ficha 360 únicamente si toda la cobertura histórica es
  coherente; nunca presenta una suma parcial como total.
- F6: habilita la postventa por persona y conserva sus permisos, idempotencia,
  veto de contacto, estados y trazabilidad.
- F7: permanece apagada durante F8. La conciliación se obtiene por lectura
  administrativa y no expone el informe global a los participantes.
- Comisiones: fuera del CRM; F8 no calcula cuánto pagar.

## Control y reversa

F8 nace apagada, sin miembros y sin permisos Data API sobre sus tablas. La
ventana dura como máximo 30 días. El piloto y las banderas globales son modos
mutuamente excluyentes y su encendido usa una misma llave transaccional.

Apagar el control corta las capacidades nuevas en las siguientes llamadas. La
reversa desactiva también a los miembros y conserva todos los hechos, archivos,
auditoría e inversiones ya confirmadas. Una revocación individual suspende de
inmediato todo el piloto. Un perfil inactivo o un rol cambiado también deja al
equipo completo sin capacidad; para reactivar se valida otra vez la composición.

Durante una ventana sana, los observadores relacionales acompañan las altas
legadas de todo el CRM para conservar cobertura. Esa sincronización de servidor
no concede a usuarios ajenos la nueva operación, Ficha 360 ni postventa.

## Aceptación

La instalación técnica no cierra F8. G7 requiere 15 identidades reales, 20
inversiones conciliadas, seis recorridos multiempresa, casos especiales, diez
reintentos, cinco carreras económicas, fallos de Auth/duplicado, cero P0/P1,
cero diferencias financieras, soporte/reversa y las firmas definidas en el
[acta](ACTA-G7.md).
