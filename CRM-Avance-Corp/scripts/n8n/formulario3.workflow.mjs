// Generador reproducible del borrador; no contiene secretos.
// Por defecto mantiene el envío apagado y el nodo HTTP deshabilitado.
import { readFileSync } from 'node:fs'
import { pathToFileURL } from 'node:url'

export const WORKFLOW_ID = 'BjI5m1PKVWhO0NDb'
export const TABLA_PRODUCCION = '1foRUzITWOnUJsNf'
export const UMBRAL_MS = 100000
export const NOMBRE = 'Avance Corp — Formulario 3 → CRM'
export const AJUSTES = {"executionOrder":"v1","timezone":"America/Lima","executionTimeout":180,"saveDataSuccessExecution":"none","saveDataErrorExecution":"all","saveManualExecutions":true,"errorWorkflow":"4jfthNhVJLiZUeIo"}
export const GRUPOS = [
  {
    "name": "Lectura y preparación",
    "description": "Lee la hoja de Formulario 3, conserva las respuestas y prepara una huella estable por fila.",
    "nodeNames": [
      "Control del envío",
      "Leer leads filtrados",
      "Preparar leads",
      "Identificar fila"
    ]
  },
  {
    "name": "Importación con confirmación",
    "description": "Evita reprocesar filas confirmadas, importa una por una y guarda únicamente resultados definitivos.",
    "nodeNames": [
      "Omitir filas confirmadas",
      "Procesar de una en una",
      "Datos válidos",
      "Importar en CRM",
      "Confirmar respuesta del CRM",
      "Marcar para revisión",
      "Preparar recibo",
      "Registrar resultado",
      "Conservar recibo",
      "Seleccionar lote rotativo",
      "Tiempo disponible",
      "Mantener pendiente",
      "Aplazar hasta próxima revisión"
    ]
  }
]
export const CONEXIONES = [
  {
    "source": "Revisar hoja",
    "target": "Control del envío",
    "sourceIndex": 0,
    "targetIndex": 0
  },
  {
    "source": "Cada 5 minutos",
    "target": "Control del envío",
    "sourceIndex": 0,
    "targetIndex": 0
  },
  {
    "source": "Control del envío",
    "target": "Leer leads filtrados",
    "sourceIndex": 0,
    "targetIndex": 0
  },
  {
    "source": "Leer leads filtrados",
    "target": "Preparar leads",
    "sourceIndex": 0,
    "targetIndex": 0
  },
  {
    "source": "Preparar leads",
    "target": "Identificar fila",
    "sourceIndex": 0,
    "targetIndex": 0
  },
  {
    "source": "Identificar fila",
    "target": "Enviar al CRM",
    "sourceIndex": 0,
    "targetIndex": 0
  },
  {
    "source": "Enviar al CRM",
    "target": "Resumen de vista previa",
    "sourceIndex": 1,
    "targetIndex": 0
  },
  {
    "source": "Enviar al CRM",
    "target": "Omitir filas confirmadas",
    "sourceIndex": 0,
    "targetIndex": 0
  },
  {
    "source": "Omitir filas confirmadas",
    "target": "Seleccionar lote rotativo",
    "sourceIndex": 0,
    "targetIndex": 0
  },
  {
    "source": "Seleccionar lote rotativo",
    "target": "Procesar de una en una",
    "sourceIndex": 0,
    "targetIndex": 0
  },
  {
    "source": "Procesar de una en una",
    "target": "Resumen de importación",
    "sourceIndex": 0,
    "targetIndex": 0
  },
  {
    "source": "Procesar de una en una",
    "target": "Tiempo disponible",
    "sourceIndex": 1,
    "targetIndex": 0
  },
  {
    "source": "Tiempo disponible",
    "target": "Datos válidos",
    "sourceIndex": 0,
    "targetIndex": 0
  },
  {
    "source": "Tiempo disponible",
    "target": "Aplazar hasta próxima revisión",
    "sourceIndex": 1,
    "targetIndex": 0
  },
  {
    "source": "Aplazar hasta próxima revisión",
    "target": "Procesar de una en una",
    "loop": true,
    "sourceIndex": 0,
    "targetIndex": 0
  },
  {
    "source": "Datos válidos",
    "target": "Importar en CRM",
    "sourceIndex": 0,
    "targetIndex": 0
  },
  {
    "source": "Datos válidos",
    "target": "Marcar para revisión",
    "sourceIndex": 1,
    "targetIndex": 0
  },
  {
    "source": "Importar en CRM",
    "target": "Confirmar respuesta del CRM",
    "sourceIndex": 0,
    "targetIndex": 0
  },
  {
    "source": "Importar en CRM",
    "target": "Mantener pendiente",
    "sourceIndex": 1,
    "targetIndex": 0
  },
  {
    "source": "Confirmar respuesta del CRM",
    "target": "Preparar recibo",
    "sourceIndex": 0,
    "targetIndex": 0
  },
  {
    "source": "Confirmar respuesta del CRM",
    "target": "Mantener pendiente",
    "sourceIndex": 1,
    "targetIndex": 0
  },
  {
    "source": "Mantener pendiente",
    "target": "Procesar de una en una",
    "loop": true,
    "sourceIndex": 0,
    "targetIndex": 0
  },
  {
    "source": "Marcar para revisión",
    "target": "Preparar recibo",
    "sourceIndex": 0,
    "targetIndex": 0
  },
  {
    "source": "Preparar recibo",
    "target": "Registrar resultado",
    "sourceIndex": 0,
    "targetIndex": 0
  },
  {
    "source": "Registrar resultado",
    "target": "Conservar recibo",
    "sourceIndex": 0,
    "targetIndex": 0
  },
  {
    "source": "Conservar recibo",
    "target": "Procesar de una en una",
    "loop": true,
    "sourceIndex": 0,
    "targetIndex": 0
  }
]

export function definirNodos(codigoFuente) {
  const codigoNodo = codigoFuente.replace(/^export /gm, '')
  return [
  {
    "name": "Revisar hoja",
    "type": "n8n-nodes-base.manualTrigger",
    "typeVersion": 1,
    "parameters": {},
    "position": [
      0,
      120
    ],
    "output": [
      {}
    ]
  },
  {
    "name": "Cada 5 minutos",
    "type": "n8n-nodes-base.scheduleTrigger",
    "typeVersion": 1.4,
    "parameters": {
      "rule": {
        "interval": [
          {
            "field": "minutes",
            "minutesInterval": 5
          }
        ]
      }
    },
    "position": [
      0,
      360
    ],
    "output": [
      {}
    ]
  },
  {
    "name": "Control del envío",
    "type": "n8n-nodes-base.set",
    "typeVersion": 3.5,
    "parameters": {
      "mode": "raw",
      "jsonOutput": "={{ JSON.stringify({enviar_crm:false,simular_registro:false,inicio_ms:$now.toMillis()}) }}"
    },
    "position": [
      300,
      240
    ],
    "output": [
      {
        "enviar_crm": false,
        "simular_registro": false
      }
    ]
  },
  {
    "name": "Leer leads filtrados",
    "type": "n8n-nodes-base.googleSheets",
    "typeVersion": 4.7,
    "parameters": {
      "resource": "sheet",
      "operation": "read",
      "authentication": "oAuth2",
      "documentId": {
        "__rl": true,
        "mode": "id",
        "value": "1lPvJ-65PNY1d4eme5xpcJ8ITVazkQRdjtkgW4ZLoIsI"
      },
      "sheetName": {
        "__rl": true,
        "mode": "list",
        "value": "gid=0",
        "cachedResultName": "Hoja 1"
      },
      "options": {
        "dataLocationOnSheet": {
          "values": {
            "rangeDefinition": "specifyRangeA1",
            "range": "A1:J"
          }
        },
        "outputFormatting": {
          "values": {
            "general": "UNFORMATTED_VALUE",
            "date": "SERIAL_NUMBER"
          }
        }
      }
    },
    "credentials": {
      "googleSheetsOAuth2Api": {
        "id": "vPzsYCzKnotpycYi",
        "name": "Google Sheets account 2"
      }
    },
    "position": [
      580,
      240
    ],
    "output": [
      {
        "row_number": 2,
        "Fecha": "2026-10-07T22:33:22-05:00",
        "nombre completo": "PERSONA DE PRUEBA",
        "n.º celular": 999000111,
        "número de teléfono": "p:+51999000112",
        "¿en qué moneda te interesa ahorrar?": "🇵🇪_soles",
        "¿qué monto aproximado deseas evaluar para tu depósito?": "de_50,000_a_100,000",
        "ciudad": "Lima",
        "¿qué deseas hacer con qorilazo?": "respuesta_de_prueba",
        "¿qué información te gustaría evaluar antes de realizar un depósito a plazo fijo?": "respuesta_de_prueba",
        "¿qué te gustaría reforzar con el asesor antes de realizar tu deposito a plazo fijjo?": "respuesta_de_prueba"
      }
    ]
  },
  {
    "name": "Preparar leads",
    "type": "n8n-nodes-base.code",
    "typeVersion": 2,
    "parameters": {
      "mode": "runOnceForAllItems",
      "language": "javaScript",
      "jsCode": codigoNodo + "\nconst entradas=$input.all(); validarColumnas(entradas.map(item=>item.json));\nreturn entradas.map((item,index)=>({json:prepararFila(item.json),pairedItem:{item:index}})).filter(item=>item.json!==null);"
    },
    "position": [
      860,
      240
    ],
    "output": [
      {
        "fila": 2,
        "campania": "Formulario 3",
        "mapeo_correcto": true,
        "errores": [],
        "huella_material": "material_de_ejemplo",
        "payload": {
          "filas": [
            {
              "fila": 2,
              "nombre": "PERSONA DE PRUEBA",
              "telefono": "999000111",
              "capital": "50000",
              "moneda": "PEN",
              "canal": "FORMULARIO",
              "campania_origen": "Formulario 3"
            }
          ]
        }
      }
    ]
  },
  {
    "name": "Identificar fila",
    "type": "n8n-nodes-base.crypto",
    "typeVersion": 2,
    "parameters": {
      "action": "hash",
      "type": "SHA256",
      "value": "={{ $json.huella_material }}",
      "dataPropertyName": "huella",
      "encoding": "hex"
    },
    "position": [
      1140,
      240
    ],
    "output": [
      {
        "fila": 2,
        "huella": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "campania": "Formulario 3",
        "mapeo_correcto": true,
        "payload": {
          "filas": [
            {
              "fila": 2
            }
          ]
        }
      }
    ]
  },
  {
    "name": "Enviar al CRM",
    "type": "n8n-nodes-base.if",
    "typeVersion": 2.3,
    "parameters": {
      "conditions": {
        "options": {
          "caseSensitive": true,
          "leftValue": "",
          "typeValidation": "strict",
          "version": 2
        },
        "conditions": [
          {
            "leftValue": "={{ $(\"Control del envío\").first().json.enviar_crm }}",
            "rightValue": true,
            "operator": {
              "type": "boolean",
              "operation": "equals"
            }
          }
        ],
        "combinator": "and"
      }
    },
    "position": [
      1420,
      240
    ],
    "output": [
      {
        "fila": 2,
        "huella": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "mapeo_correcto": true,
        "payload": {
          "filas": [
            {
              "fila": 2
            }
          ]
        }
      }
    ]
  },
  {
    "name": "Resumen de vista previa",
    "type": "n8n-nodes-base.code",
    "typeVersion": 2,
    "parameters": {
      "mode": "runOnceForAllItems",
      "language": "javaScript",
      "jsCode": codigoNodo + "\nreturn [{json:resumirPreparacion($input.all().map(item=>item.json))}];"
    },
    "position": [
      1740,
      540
    ],
    "output": [
      {
        "campania": "Formulario 3",
        "total_filas": 10,
        "preparadas": 10,
        "envios_crm": 0
      }
    ]
  },
  {
    "name": "Omitir filas confirmadas",
    "type": "n8n-nodes-base.dataTable",
    "typeVersion": 1.1,
    "parameters": {
      "resource": "row",
      "operation": "rowNotExists",
      "dataTableId": {
        "__rl": true,
        "mode": "list",
        "value": "1foRUzITWOnUJsNf",
        "cachedResultName": "Formulario 3 — importaciones"
      },
      "matchType": "allConditions",
      "filters": {
        "conditions": [
          {
            "keyName": "huella",
            "keyValue": "={{ $json.huella }}"
          }
        ]
      }
    },
    "position": [
      1740,
      120
    ],
    "output": [
      {
        "fila": 2,
        "huella": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "mapeo_correcto": true,
        "payload": {
          "filas": [
            {
              "fila": 2
            }
          ]
        }
      }
    ]
  },
  {
    "name": "Procesar de una en una",
    "type": "n8n-nodes-base.splitInBatches",
    "typeVersion": 3,
    "parameters": {
      "batchSize": 1,
      "options": {
        "reset": false
      }
    },
    "position": [
      2020,
      120
    ],
    "output": [
      {
        "fila": 2,
        "huella": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "mapeo_correcto": true,
        "payload": {
          "filas": [
            {
              "fila": 2
            }
          ]
        }
      }
    ]
  },
  {
    "name": "Datos válidos",
    "type": "n8n-nodes-base.if",
    "typeVersion": 2.3,
    "parameters": {
      "conditions": {
        "options": {
          "caseSensitive": true,
          "leftValue": "",
          "typeValidation": "strict",
          "version": 2
        },
        "conditions": [
          {
            "leftValue": "={{ $json.mapeo_correcto }}",
            "rightValue": true,
            "operator": {
              "type": "boolean",
              "operation": "equals"
            }
          }
        ],
        "combinator": "and"
      }
    },
    "position": [
      2300,
      240
    ],
    "output": [
      {
        "fila": 2,
        "huella": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "mapeo_correcto": true,
        "payload": {
          "filas": [
            {
              "fila": 2
            }
          ]
        }
      }
    ]
  },
  {
    "name": "Importar en CRM",
    "type": "n8n-nodes-base.httpRequest",
    "typeVersion": 4.5,
    "parameters": {
      "method": "POST",
      "url": "https://dctqcbznekcyxhjujuci.supabase.co/functions/v1/crm-importar-leads",
      "authentication": "genericCredentialType",
      "genericAuthType": "httpTemplatedCustomAuth",
      "sendBody": true,
      "contentType": "json",
      "specifyBody": "json",
      "jsonBody": "={{ JSON.stringify($json.payload) }}",
      "options": {
        "timeout": 20000,
        "response": {
          "response": {
            "responseFormat": "json"
          }
        }
      }
    },
    "credentials": {
      "httpTemplatedCustomAuth": {
        "id": "YNRHr2PjhfLXnKff",
        "name": "Simplified Custom Auth account"
      }
    },
    "retryOnFail": true,
    "maxTries": 3,
    "waitBetweenTries": 1000,
    "position": [
      2600,
      160
    ],
    "output": [
      {
        "resultados": [
          {
            "fila": 2,
            "resultado": "importado",
            "estado": "IMPORTADO ✓"
          }
        ]
      }
    ],
    "disabled": true,
    "onError": "continueErrorOutput"
  },
  {
    "name": "Confirmar respuesta del CRM",
    "type": "n8n-nodes-base.code",
    "typeVersion": 2,
    "parameters": {
      "mode": "runOnceForAllItems",
      "language": "javaScript",
      "jsCode": codigoNodo + "\nconst recibidas=$input.all();\nif(recibidas.length!==1)throw new Error(\"Se esperaba la respuesta de una sola fila\");\nreturn [{json:conciliarRespuesta(recibidas[0].json,$(\"Datos válidos\").itemMatching(0).json),pairedItem:{item:0}}];"
    },
    "position": [
      2900,
      160
    ],
    "output": [
      {
        "huella": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "campania": "Formulario 3",
        "fila": 2,
        "resultado": "importado",
        "estado": "IMPORTADO ✓"
      }
    ],
    "onError": "continueErrorOutput"
  },
  {
    "name": "Marcar para revisión",
    "type": "n8n-nodes-base.code",
    "typeVersion": 2,
    "parameters": {
      "mode": "runOnceForAllItems",
      "language": "javaScript",
      "jsCode": codigoNodo + "\nreturn $input.all().map((item,index)=>({json:reciboDeRechazo(item.json),pairedItem:{item:index}}));"
    },
    "position": [
      2900,
      430
    ],
    "output": [
      {
        "huella": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "campania": "Formulario 3",
        "fila": 2,
        "resultado": "rechazado",
        "estado": "RECHAZADO: capital no reconocido"
      }
    ]
  },
  {
    "name": "Preparar recibo",
    "type": "n8n-nodes-base.set",
    "typeVersion": 3.5,
    "parameters": {
      "mode": "raw",
      "jsonOutput": "={{ JSON.stringify({huella:$json.huella,campania:$json.campania,fila:$json.fila,resultado:$json.resultado,estado:$json.estado,procesado_en:$now.toISO()}) }}"
    },
    "position": [
      3200,
      240
    ],
    "output": [
      {
        "huella": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "campania": "Formulario 3",
        "fila": 2,
        "resultado": "importado",
        "estado": "IMPORTADO ✓",
        "procesado_en": "2026-10-14T18:00:00Z"
      }
    ]
  },
  {
    "name": "Registrar resultado",
    "type": "n8n-nodes-base.dataTable",
    "typeVersion": 1.1,
    "parameters": {
      "resource": "row",
      "operation": "upsert",
      "dataTableId": {
        "__rl": true,
        "mode": "list",
        "value": "1foRUzITWOnUJsNf",
        "cachedResultName": "Formulario 3 — importaciones"
      },
      "matchType": "allConditions",
      "filters": {
        "conditions": [
          {
            "keyName": "huella",
            "condition": "eq",
            "keyValue": "={{ $json.huella }}"
          }
        ]
      },
      "columns": {
        "mappingMode": "defineBelow",
        "value": {
          "huella": "={{ $json.huella }}",
          "campania": "={{ $json.campania }}",
          "fila": "={{ $json.fila }}",
          "resultado": "={{ $json.resultado }}",
          "estado": "={{ $json.estado }}",
          "procesado_en": "={{ $json.procesado_en }}"
        }
      },
      "options": {
        "dryRun": "={{ $(\"Control del envío\").first().json.simular_registro }}"
      }
    },
    "position": [
      3480,
      240
    ],
    "output": [
      {
        "id": 1,
        "huella": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "resultado": "importado"
      }
    ]
  },
  {
    "name": "Conservar recibo",
    "type": "n8n-nodes-base.set",
    "typeVersion": 3.5,
    "parameters": {
      "mode": "raw",
      "jsonOutput": "={{ JSON.stringify($(\"Preparar recibo\").item.json) }}"
    },
    "position": [
      3760,
      240
    ],
    "output": [
      {
        "huella": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "campania": "Formulario 3",
        "fila": 2,
        "resultado": "importado",
        "estado": "IMPORTADO ✓"
      }
    ],
    "executeOnce": true
  },
  {
    "name": "Resumen de importación",
    "type": "n8n-nodes-base.code",
    "typeVersion": 2,
    "parameters": {
      "mode": "runOnceForAllItems",
      "language": "javaScript",
      "jsCode": codigoNodo + "\nreturn [{json:resumirImportacion($input.all().map(item=>item.json),$(\"Control del envío\").first().json.simular_registro)}];"
    },
    "position": [
      2300,
      -100
    ],
    "output": [
      {
        "campania": "Formulario 3",
        "filas_procesadas": 1,
        "resultados": {
          "importado": 1
        },
        "simulacion": false
      }
    ]
  },
  {
    "name": "Seleccionar lote rotativo",
    "type": "n8n-nodes-base.code",
    "typeVersion": 2,
    "parameters": {
      "mode": "runOnceForAllItems",
      "language": "javaScript",
      "jsCode": codigoNodo + "\nreturn seleccionarLote($input.all().map((item,index)=>({...item,pairedItem:{item:index}})),$(\"Control del envío\").first().json.inicio_ms);"
    },
    "position": [
      1900,
      120
    ],
    "output": [
      {
        "fila": 2,
        "huella": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "campania": "Formulario 3",
        "mapeo_correcto": true,
        "payload": {
          "filas": [
            {
              "fila": 2
            }
          ]
        }
      }
    ]
  },
  {
    "name": "Tiempo disponible",
    "type": "n8n-nodes-base.if",
    "typeVersion": 2.3,
    "parameters": {
      "conditions": {
        "options": {
          "caseSensitive": true,
          "leftValue": "",
          "typeValidation": "strict",
          "version": 2
        },
        "conditions": [
          {
            "leftValue": "={{ $now.toMillis()-$(\"Control del envío\").first().json.inicio_ms < " + UMBRAL_MS + " }}",
            "rightValue": true,
            "operator": {
              "type": "boolean",
              "operation": "equals"
            }
          }
        ],
        "combinator": "and"
      }
    },
    "position": [
      2200,
      240
    ],
    "output": [
      {
        "fila": 2,
        "huella": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "campania": "Formulario 3",
        "mapeo_correcto": true,
        "payload": {
          "filas": [
            {
              "fila": 2
            }
          ]
        }
      }
    ]
  },
  {
    "name": "Mantener pendiente",
    "type": "n8n-nodes-base.code",
    "typeVersion": 2,
    "parameters": {
      "mode": "runOnceForAllItems",
      "language": "javaScript",
      "jsCode": codigoNodo + "\nreturn [{json:pendienteDeFila($(\"Procesar de una en una\").itemMatching(0).json),pairedItem:{item:0}}];"
    },
    "position": [
      3050,
      700
    ],
    "output": [
      {
        "huella": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "campania": "Formulario 3",
        "fila": 2,
        "resultado": "pendiente",
        "estado": "PENDIENTE: sin respuesta definitiva"
      }
    ]
  },
  {
    "name": "Aplazar hasta próxima revisión",
    "type": "n8n-nodes-base.set",
    "typeVersion": 3.5,
    "parameters": {
      "mode": "raw",
      "jsonOutput": "={{ JSON.stringify({huella:$json.huella,campania:$json.campania,fila:$json.fila,resultado:\"aplazado\",estado:\"APLAZADO: se agotó el margen de esta ejecución\"}) }}"
    },
    "position": [
      2600,
      700
    ],
    "output": [
      {
        "huella": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "campania": "Formulario 3",
        "fila": 2,
        "resultado": "aplazado",
        "estado": "APLAZADO"
      }
    ]
  }
]
}


// El SDK interpreta código estático; la lógica de negocio corre en nodos Code.
function literalSDK(valor) {
  if (typeof valor === 'string' && valor.startsWith('={{')) return 'expr(' + JSON.stringify(valor.slice(1)) + ')'
  if (Array.isArray(valor)) return '[' + valor.map(literalSDK).join(',') + ']'
  if (valor && typeof valor === 'object') return '{' + Object.entries(valor).map(([clave, v]) => JSON.stringify(clave) + ':' + literalSDK(v)).join(',') + '}'
  return JSON.stringify(valor)
}

export function codigoSDK(nodos, id = WORKFLOW_ID, nombre = NOMBRE, conexiones = CONEXIONES, grupos = GRUPOS) {
  const handles = new Map(nodos.map((nodo, i) => [nodo.name, 'n' + i]))
  if (handles.size !== nodos.length) throw new Error('Nombres de nodos repetidos')
  const nodoPorNombre = new Map(nodos.map(nodo => [nodo.name, nodo]))
  const handle = nombreNodo => {
    if (!handles.has(nombreNodo)) throw new Error('Nodo desconocido: ' + nombreNodo)
    return handles.get(nombreNodo)
  }
  const definiciones = nodos.map((nodo, i) => {
    const { type, typeVersion, output, ...config } = nodo
    let literal = literalSDK(config)
    for (const [tipo, credencial] of Object.entries(nodo.credentials ?? {})) {
      literal = literal.replace(JSON.stringify(tipo) + ':' + literalSDK(credencial), JSON.stringify(tipo) + ':newCredential(' + JSON.stringify(credencial.name) + ')')
    }
    const fabrica = /Trigger$/.test(type) ? 'trigger' : type === 'n8n-nodes-base.if' ? 'ifElse' : type === 'n8n-nodes-base.splitInBatches' ? 'splitInBatches' : 'node'
    return 'const n' + i + ' = ' + fabrica + '({type:' + JSON.stringify(type) + ',version:' + typeVersion + ',config:' + literal + ',output:' + JSON.stringify(output) + '});'
  }).join('\n')
  const aristas = conexiones.map(arista => {
    const origen = handle(arista.source)
    let destino = handle(arista.target)
    if (arista.loop) destino = 'nextBatch(' + destino + ')'
    const tipo = nodoPorNombre.get(arista.source).type
    if (tipo === 'n8n-nodes-base.splitInBatches') return '.add(' + origen + (arista.sourceIndex === 1 ? '.onEachBatch(' : '.onDone(') + destino + '))'
    if (tipo === 'n8n-nodes-base.if') return '.add(' + origen + (arista.sourceIndex === 1 ? '.onFalse(' : '.onTrue(') + destino + '))'
    if (arista.sourceIndex === 1 && nodoPorNombre.get(arista.source).onError === 'continueErrorOutput') return '.add(' + origen + '.onError(' + destino + '))'
    return '.add(' + origen + '.output(' + (arista.sourceIndex ?? 0) + ').to(' + destino + '))'
  }).join('\n')
  const marcos = grupos.map(grupo => '.group(' + JSON.stringify(grupo.name) + ',[' + grupo.nodeNames.map(handle).join(',') + '],{description:' + JSON.stringify(grupo.description) + '})').join('\n')
  return "import {workflow,node,trigger,newCredential,ifElse,splitInBatches,nextBatch,expr} from '@n8n/workflow-sdk';\n" + definiciones +
    '\nexport default workflow(' + JSON.stringify(id) + ',' + JSON.stringify(nombre) + ')\n' + aristas + '\n' + marcos + ';\n'
}

// Banco cerrado: datos sintéticos en lugar de Google Sheets, respuesta simulada
// en lugar de HTTP y una tabla distinta, obligatoria. Nunca usa credenciales.
export function definirBanco(codigoFuente, { tablaId, filas, respuestaCodigo, inicioCodigo = '$now.toMillis()', simularRegistro = true }) {
  if (!tablaId || tablaId === TABLA_PRODUCCION) throw new Error('El banco requiere una tabla aislada de producción')
  if (!Array.isArray(filas) || !filas.length) throw new Error('Faltan filas sintéticas')
  const nodos = definirNodos(codigoFuente)
  for (const nodo of nodos) {
    delete nodo.credentials
    if (nodo.parameters.dataTableId) nodo.parameters.dataTableId = { __rl: true, mode: 'list', value: tablaId, cachedResultName: 'PRUEBA — Formulario 3 (recibos simulados)' }
    if (nodo.name === 'Control del envío') nodo.parameters.jsonOutput = '={{ JSON.stringify({enviar_crm:true,simular_registro:' + JSON.stringify(simularRegistro) + ',inicio_ms:' + inicioCodigo + '}) }}'
    if (nodo.name === 'Leer leads filtrados') {
      nodo.type = 'n8n-nodes-base.code'
      nodo.typeVersion = 2
      nodo.parameters = { mode: 'runOnceForAllItems', language: 'javaScript', jsCode: 'return ' + JSON.stringify(filas.map(json => ({ json }))) + ';' }
      nodo.output = filas
    }
    if (nodo.name === 'Importar en CRM') {
      nodo.type = 'n8n-nodes-base.code'
      nodo.typeVersion = 2
      nodo.disabled = false
      delete nodo.retryOnFail
      delete nodo.maxTries
      delete nodo.waitBetweenTries
      nodo.parameters = { mode: 'runOnceForAllItems', language: 'javaScript', jsCode: respuestaCodigo ?? 'return [{json:{resultados:[{fila:$input.first().json.fila,resultado:"importado",estado:"IMPORTADO SIMULADO"}]},pairedItem:{item:0}}];' }
    }
  }
  return nodos
}

export function cargarDefinicion() {
  const nodos = definirNodos(readFileSync(new URL('./formulario3.mjs', import.meta.url), 'utf8'))
  return { workflowId: WORKFLOW_ID, name: NOMBRE, nodes: nodos, connections: CONEXIONES, nodeGroups: GRUPOS, settings: AJUSTES, code: codigoSDK(nodos) }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.stdout.write(JSON.stringify(cargarDefinicion(), null, 2) + '\n')
}

