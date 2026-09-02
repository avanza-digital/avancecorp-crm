# Producción fuera del ranking

Decisión comercial del 2026-09-02, complementaria a [[Rankings por mes calendario (decision 2026-09-02)]] y [[Ranking de capital total unificado (TC BCRP)]].

## Regla cerrada

- Solo los analistas comerciales pueden recibir puesto en los rankings individuales.
- Una inversión atribuida a un supervisor, Gerencia, coordinación, Directorio o una persona fuera de la estructura no se reasigna artificialmente a un analista.
- Esa producción sí forma parte del resultado total de la empresa, porque el capital y las operaciones existen.
- La misma producción no crea una fila rankeable, no aumenta el contador de analistas y no modifica posiciones, metas ni porcentajes individuales.
- Gerencia la ve nominada y desglosada bajo **«Producción fuera del ranking»**, con responsable, motivo, capital PEN/USD, contratos, cierres y operaciones de cartera.
- Supervisores y analistas no reciben ese bloque global.

## Implementación

No se crearon funciones, RPC ni tablas paralelas. La regla se incorporó a los núcleos mensuales existentes mediante la migración `20260902202247_crm_ranking_foto_mensual_coherente`.

En meses abiertos, Gerencia recibe el detalle calculado desde los mismos núcleos canónicos de conversión, producción y cartera. Al cerrar el mes, el detalle queda congelado dentro de `crm.periodos_cerrados.cobertura.fuera_ranking`; así el histórico no cambia cuando una persona cambia de rol o sale del equipo.

Un analista que produjo sin meta mensual conserva su producción con objetivos cero y, al cierre, permanece en la foto del equipo bajo el supervisor correspondiente. Esto es distinto de una inversión cuyo responsable no era analista.

## Orden de publicación

El frontend compatible debe publicarse antes que la migración porque `cumplimiento_metas_fn` añadirá la clave `fuera_ranking` a una respuesta validada de forma estricta. Ver [[Deploy a Hostinger]].

## Evidencia previa al despliegue

- Migración aplicada desde cero sobre un calco limpio del esquema productivo.
- Seis núcleos revisados con `plpgsql_check`: cero hallazgos.
- Oráculo SQL específico: analista sin meta preservado, supervisor nunca rankeado, detalle abierto/cerrado y aislamiento por rol; todo verde.
- Frontend: 2.635 pruebas unitarias, build y controles de bundle/duplicación aprobados.
- Navegador: 113 pruebas aprobadas, 26 omitidas por suites desactivadas y cero fallidas.

Estado al redactar esta nota: validado y pendiente de publicación frontend primero, migración después.
