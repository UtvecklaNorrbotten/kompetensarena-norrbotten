import { useRef, type Dispatch, type SetStateAction } from "react";

export const legendDoubleClickMs = 220;
type PendingClick = { key: string; time: number; hiddenBefore: string[]; keys: string[] };

/** Utgå från läget före första klicket när en snabb klickserie isolerar/återställer. */
export function legendClickState(
  keys: string[],
  hidden: string[],
  key: string,
  time: number,
  previous: PendingClick | null,
  keyboard = false,
): { hidden: string[]; pending: PendingClick | null } {
  const double =
    !keyboard &&
    previous?.key === key &&
    time - previous.time >= 0 &&
    time - previous.time <= legendDoubleClickMs &&
    keys.length === previous.keys.length &&
    keys.every((k, i) => k === previous.keys[i]);
  if (double && previous) {
    const others = keys.filter((k) => k !== key);
    const isolated =
      !previous.hiddenBefore.includes(key) &&
      others.every((k) => previous.hiddenBefore.includes(k));
    return { hidden: isolated ? [] : others, pending: null };
  }
  return {
    hidden: hidden.includes(key) ? hidden.filter((k) => k !== key) : [...hidden, key],
    pending: keyboard ? null : { key, time, hiddenBefore: [...hidden], keys: [...keys] },
  };
}

export function useLegendClick(
  keys: string[],
  hidden: string[],
  setHidden: Dispatch<SetStateAction<string[]>>,
) {
  const pending = useRef<PendingClick | null>(null);
  return (key: string, keyboard = false) => {
    const next = legendClickState(keys, hidden, key, performance.now(), pending.current, keyboard);
    pending.current = next.pending;
    setHidden(next.hidden);
  };
}
