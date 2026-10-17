import assert from 'node:assert/strict'
import { test } from 'node:test'
import { localeOf, otherLanguageHref } from './index.ts'

test('the path prefix decides the language', () => {
  assert.equal(localeOf('/'), 'pl')
  assert.equal(localeOf('/aed/1'), 'pl')
  assert.equal(localeOf('/en'), 'en')
  assert.equal(localeOf('/en/aed/1'), 'en')
  assert.equal(localeOf('/english'), 'pl')
})

test('the link to the other language keeps the page', () => {
  assert.equal(otherLanguageHref('/'), '/en')
  assert.equal(otherLanguageHref('/aed/12', '?a=1', '#x'), '/en/aed/12?a=1#x')
  assert.equal(otherLanguageHref('/en'), '/')
  assert.equal(otherLanguageHref('/en/aed/12', '?a=1'), '/aed/12?a=1')
})
