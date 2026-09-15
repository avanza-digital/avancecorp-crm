# Evaluación de Codex PRIMARY

La revisión válida de Claude es CHANGES_REQUESTED. No halló P0/P1 ni exposición
de datos nueva. No se transforma ese dictamen en PASS. Se aplicaron las siguientes
decisiones y después se repitieron paridad, seguridad, concurrencia y volumen.

| Hallazgo | Decisión y evidencia |
|---|---|
| P2: materialización global y beneficio no demostrado | Se acepta exigir medición del cambio instalado en el banco antes de publicar y acreditar <1 s después. Se mantiene el diseño: la conclusión de que casi todo el coste queda en los CTE globales no está sustentada por contar buffers. El perfil adicional del cuerpo **vigente**, READ ONLY, atribuye aproximadamente 920,85 ms a las 12.278 iteraciones del lateral y 72,936 ms a `cartera_f5_fuentes`, sobre 1.054,606 ms totales. Los tiempos de nodos anidados no se suman. Esto apoya recortar personas antes de los laterales; todavía no acredita la candidata instalada. |
| P3: NULL | NULL significa listado completo en la firma privada y se documentó explícitamente. La ficha pública mantiene su filtro externo y devuelve NULL. Se amplió la matriz: 640 fichas y 328 salidas del núcleo, entrada NULL e inexistente incluidas. El helper canónico devuelve el UUID inexistente, no NULL; ese caso ya estaba cubierto. No se agrega otra lógica a la ficha para optimizar una entrada inválida. |
| P3: falta de poscondiciones/trazabilidad | Se agregaron MD5 finales de las tres funciones, owner postgres, SECURITY DEFINER, search_path y ACL exactas. El ensayo rechaza una ACL no prevista y un mutante que omite el filtro. Se guardó la definición resultante de la ficha. La reversa verifica esos mismos hashes y restaura firma/ACL/configuración originales. |

[Perfil adicional](evidencias/diagnostico-tiempos-produccion.json),
[matriz final](evidencias/paridad-local.json),
[seguridad final](evidencias/seguridad-local.json).

Los 12 accesos concurrentes locales usan procesos y PIDs distintos con tiempos
SQL superpuestos. Las seis revocaciones durante la llamada instrumentan el
contexto F4; no son commits entre sesiones. Las carreras reales de revocación,
Auth HTTP, matriz RLS general, advisors, tipos y replay remotos quedan pendientes
del banco autorizado. El objetivo productivo permanece abierto.

El primer intento del wrapper no entregó dictamen válido; el segundo sí. No se
hizo una tercera consulta. Las poscondiciones y los casos NULL/mutantes posteriores
al dictamen fueron implementados y verificados por el PRIMARY.
