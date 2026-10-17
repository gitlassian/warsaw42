import assert from 'node:assert/strict'
import { test } from 'node:test'
import { validateDraft } from './report.ts'

test('validates the report draft', () => {
  assert.deepEqual(validateDraft({ category: 'other', description: 'Szafka jest zamknięta.' }), {})
  assert.deepEqual(Object.keys(validateDraft({ category: null, description: '  krótko  ' })), ['category', 'description'])
})
