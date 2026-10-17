import assert from 'node:assert/strict'
import { test } from 'node:test'
import { toE164, validateDraft } from './report.ts'

test('normalizes Polish phone numbers', () => {
  assert.equal(toE164('600 123 456'), '+48600123456')
  assert.equal(toE164('+48 600-123-456'), '+48600123456')
  assert.equal(toE164('0048600123456'), '+48600123456')
  assert.equal(toE164('60012345'), null)
  assert.equal(toE164('+49 600 123 456'), null)
})

test('validates the report draft', () => {
  assert.deepEqual(validateDraft({ category: 'other', description: 'Szafka jest zamknięta.', phone: '600123456' }), {})
  assert.deepEqual(Object.keys(validateDraft({ category: null, description: '  krótko  ', phone: '1' })), [
    'category',
    'description',
    'phone',
  ])
})
