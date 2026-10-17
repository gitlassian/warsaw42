/** Stable error code from the API (ENDPOINTS.md §11); the UI localizes the code, not the message. */
export class ApiError extends Error {
  readonly code: string
  /** Epoch ms when a rate-limited request may be retried (`Retry-After`). */
  readonly retryAt?: number

  constructor(code: string, retryAt?: number) {
    super(code)
    this.name = 'ApiError'
    this.code = code
    this.retryAt = retryAt
  }
}
