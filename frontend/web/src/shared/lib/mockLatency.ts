/** Simulated network delay for mock services, so loading states stay visible. */
export const mockLatency = (ms = 300) => new Promise((resolve) => setTimeout(resolve, ms))
