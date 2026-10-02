import * as v from 'valibot'
import { TIPOS_DOCUMENTO_K } from './documento'

const Id = v.pipe(v.string(), v.uuid())
export const DocumentoLeadSchema = v.object({
  lead_id: Id,
  inversionista_id: v.nullable(Id),
  identificador_id: v.nullable(Id),
  tipo: v.picklist(TIPOS_DOCUMENTO_K),
  numero: v.nullable(v.string()),
  puede_corregir: v.boolean(),
})
export type DocumentoLead = v.InferOutput<typeof DocumentoLeadSchema>
