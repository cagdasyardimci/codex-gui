import type { ModelEffort } from './generated/workspace';

export function visibleEfforts(efforts: ModelEffort[], hidden: string[], selected?: string | null): ModelEffort[] {
  return efforts.filter(({ reasoningEffort }) => reasoningEffort === selected || !hidden.includes(reasoningEffort));
}
