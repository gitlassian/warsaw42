import assert from 'node:assert/strict'
import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join } from 'node:path'
import { test } from 'node:test'
import { EN } from './en.ts'

// Every `t('...')` call with a literal text must have an English entry, otherwise /en shows Polish.
const SRC = join(import.meta.dirname, '..')
const CALL = /\bt\(\s*('(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*"|`(?:[^`\\$]|\\.)*`)/g

function files(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name)
    if (statSync(path).isDirectory()) return files(path)
    return /\.tsx?$/.test(name) && !/\.test\.tsx?$/.test(name) ? [path] : []
  })
}

const unquote = (literal: string) => literal.slice(1, -1).replace(/\\(['"`\\])/g, '$1').replace(/\\n/g, '\n')

test('every translated text has an English version', () => {
  const missing: string[] = []
  for (const file of files(SRC)) {
    for (const [, literal] of readFileSync(file, 'utf8').matchAll(CALL)) {
      const key = unquote(literal)
      if (!(key in EN)) missing.push(`${file.slice(SRC.length + 1)}: ${key}`)
    }
  }
  assert.deepEqual(missing, [])
})

test('English texts keep the {placeholders} of their Polish key', () => {
  const names = (text: string) => [...text.matchAll(/\{(\w+)\}/g)].map((m) => m[1]).sort()
  const broken = Object.entries(EN).filter(([pl, en]) => JSON.stringify(names(pl)) !== JSON.stringify(names(en)))
  assert.deepEqual(broken, [])
})
