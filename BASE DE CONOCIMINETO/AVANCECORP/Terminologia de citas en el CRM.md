# Terminología de citas en el CRM

Decisión de producto del 2026-08-27: en toda la interfaz del CRM se presenta
**cita / citas** en lugar de **reunión / reuniones**.

El cambio es exclusivamente de frontend. El modelo interno conserva el contrato
histórico: ruta `reuniones`, tipo `reunion`, etapa `reunion_agendada`, campos
`*_reunion`, métricas, RPC y textos ya persistidos. La capa de presentación
traduce esos textos al mostrarlos y normaliza a la terminología histórica antes
de guardar una cita nueva.

La presentación cubre también la variante histórica `Reunion` sin tilde, pero
deliberadamente no altera identificadores como `reunion_agendada` o
`reuniones_realizadas`.

Relacionadas: [[Agenda comercial del CRM (plan v2)]] · [[Fundamentos UX del CRM]] · [[Deploy a Hostinger]]
